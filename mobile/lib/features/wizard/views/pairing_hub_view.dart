import 'package:flutter/material.dart';
// flutter_hooks defines its own `Store` symbol that collides with Immich's
// Isar Store. Hide it so the Store reference below resolves to the Isar
// key/value store.
import 'package:flutter_hooks/flutter_hooks.dart' hide Store;
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:immich_mobile/domain/models/store.model.dart';
import 'package:immich_mobile/domain/models/user.model.dart';
import 'package:immich_mobile/entities/store.entity.dart';
import 'package:immich_mobile/providers/api.provider.dart';
import 'package:openapi/api.dart';
import 'package:qr_flutter/qr_flutter.dart';

/// Builds a `hearth://pair?host=...&email=...&pass=...` payload from the
/// signed-in server's host plus the supplied credentials. Returns null if
/// the stored server endpoint is missing or malformed.
String? _buildPairingPayload({required String email, required String password}) {
  final endpoint = Store.tryGet(StoreKey.serverEndpoint);
  if (endpoint == null || endpoint.isEmpty) return null;

  // serverEndpoint looks like `http://10.20.30.232:2283/api`; the pairing
  // payload only needs the host (the scanner forces port 2283).
  final host = Uri.tryParse(endpoint)?.host;
  if (host == null || host.isEmpty) return null;

  return Uri(
    scheme: 'hearth',
    host: 'pair',
    queryParameters: {'host': host, 'email': email, 'pass': password},
  ).toString();
}

/// A rendered QR card plus a security caveat, shared by both tabs.
class _PairingQr extends StatelessWidget {
  const _PairingQr({required this.payload});

  final String payload;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Center(
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12)),
            child: QrImageView(
              data: payload,
              version: QrVersions.auto,
              size: 240,
              backgroundColor: Colors.white,
            ),
          ),
        ),
        const SizedBox(height: 16),
        Text(
          "Scan this from the new device's onboarding screen. Anyone with this code can sign in, so share it carefully.",
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 13, color: Theme.of(context).colorScheme.error),
        ),
      ],
    );
  }
}

/// Device & Family Pairing hub. Tab 1 links a new device for the current
/// user; Tab 2 (admin-only) provisions a new family member account and emits
/// a pairing QR for it.
class PairingHubView extends HookConsumerWidget {
  const PairingHubView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Device & Family Pairing'),
          bottom: const TabBar(
            tabs: [
              Tab(text: 'My Device', icon: Icon(Icons.phonelink)),
              Tab(text: 'Family Member', icon: Icon(Icons.group_add_outlined)),
            ],
          ),
        ),
        body: const TabBarView(
          children: [_MyDeviceTab(), _FamilyMemberTab()],
        ),
      ),
    );
  }
}

class _MyDeviceTab extends HookConsumerWidget {
  const _MyDeviceTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final passwordController = useTextEditingController();
    final obscurePassword = useState(true);
    final payload = useState<String?>(null);
    final errorMessage = useState<String?>(null);

    final UserDto? user = Store.tryGet(StoreKey.currentUser);
    final email = user?.email;

    void generateQr() {
      final password = passwordController.text;
      if (password.isEmpty) {
        errorMessage.value = 'Enter your password to generate a pairing code.';
        payload.value = null;
        return;
      }
      if (email == null || email.isEmpty) {
        errorMessage.value = 'Could not read your account details. Please sign in again.';
        payload.value = null;
        return;
      }

      final built = _buildPairingPayload(email: email, password: password);
      if (built == null) {
        errorMessage.value = 'Could not read your server address. Please sign in again.';
        payload.value = null;
        return;
      }
      errorMessage.value = null;
      payload.value = built;
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Icon(Icons.phonelink, size: 64, color: Theme.of(context).colorScheme.primary),
          const SizedBox(height: 16),
          const Text(
            'Link a new device',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Text(
            email == null
                ? 'No signed-in account found.'
                : 'Confirm your password to create a QR code that signs $email in on another device.',
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 14, color: Colors.grey),
          ),
          const SizedBox(height: 24),
          TextField(
            controller: passwordController,
            obscureText: obscurePassword.value,
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => generateQr(),
            decoration: InputDecoration(
              labelText: 'Confirm Password',
              prefixIcon: const Icon(Icons.password_outlined),
              border: const OutlineInputBorder(),
              errorText: errorMessage.value,
              suffixIcon: IconButton(
                icon: Icon(obscurePassword.value ? Icons.visibility_off : Icons.visibility),
                onPressed: () => obscurePassword.value = !obscurePassword.value,
              ),
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            height: 50,
            child: ElevatedButton.icon(
              onPressed: generateQr,
              icon: const Icon(Icons.qr_code),
              label: const Text('Generate QR'),
            ),
          ),
          if (payload.value != null) ...[
            const SizedBox(height: 32),
            _PairingQr(payload: payload.value!),
          ],
        ],
      ),
    );
  }
}

class _FamilyMemberTab extends HookConsumerWidget {
  const _FamilyMemberTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final UserDto? currentUser = Store.tryGet(StoreKey.currentUser);
    final isAdmin = currentUser?.isAdmin ?? false;

    final nameController = useTextEditingController();
    final emailController = useTextEditingController();
    final passwordController = useTextEditingController();
    final obscurePassword = useState(true);
    final isLoading = useState(false);
    final payload = useState<String?>(null);
    final errorMessage = useState<String?>(null);

    if (!isAdmin) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.lock_outline, size: 64, color: Theme.of(context).colorScheme.outline),
              const SizedBox(height: 16),
              const Text(
                'Only Admins can add family members.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 16),
              ),
            ],
          ),
        ),
      );
    }

    Future<void> createUserAndGenerateQr() async {
      final name = nameController.text.trim();
      final email = emailController.text.trim();
      final password = passwordController.text;

      if (name.isEmpty || email.isEmpty || password.isEmpty) {
        errorMessage.value = 'Name, email, and password are all required.';
        payload.value = null;
        return;
      }

      isLoading.value = true;
      errorMessage.value = null;
      payload.value = null;
      try {
        // UsersAdminApi is not registered on ApiService; build it from the
        // shared, authenticated ApiClient so it inherits the session headers.
        final usersAdminApi = UsersAdminApi(ref.read(apiServiceProvider).apiClient);
        await usersAdminApi.createUserAdmin(
          UserAdminCreateDto(email: email, password: password, name: name),
        );

        final built = _buildPairingPayload(email: email, password: password);
        if (built == null) {
          errorMessage.value = 'User created, but the server address could not be read for the QR code.';
          return;
        }
        payload.value = built;
      } catch (e) {
        errorMessage.value = 'Could not create the family member: $e';
      } finally {
        isLoading.value = false;
      }
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Icon(Icons.group_add_outlined, size: 64, color: Theme.of(context).colorScheme.primary),
          const SizedBox(height: 16),
          const Text(
            'Add a family member',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          const Text(
            'Create a new account on this Hearth Hub and generate a QR code to sign them in.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 14, color: Colors.grey),
          ),
          const SizedBox(height: 24),
          TextField(
            controller: nameController,
            textInputAction: TextInputAction.next,
            decoration: const InputDecoration(
              labelText: 'Name',
              prefixIcon: Icon(Icons.person_outline),
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: emailController,
            keyboardType: TextInputType.emailAddress,
            textInputAction: TextInputAction.next,
            decoration: const InputDecoration(
              labelText: 'Email Address',
              prefixIcon: Icon(Icons.email_outlined),
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: passwordController,
            obscureText: obscurePassword.value,
            textInputAction: TextInputAction.done,
            decoration: InputDecoration(
              labelText: 'Password',
              prefixIcon: const Icon(Icons.password_outlined),
              border: const OutlineInputBorder(),
              errorText: errorMessage.value,
              suffixIcon: IconButton(
                icon: Icon(obscurePassword.value ? Icons.visibility_off : Icons.visibility),
                onPressed: () => obscurePassword.value = !obscurePassword.value,
              ),
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            height: 50,
            child: ElevatedButton.icon(
              onPressed: isLoading.value ? null : createUserAndGenerateQr,
              icon: isLoading.value
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.5,
                        valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                      ),
                    )
                  : const Icon(Icons.person_add_alt),
              label: const Text('Create User & Generate QR'),
            ),
          ),
          if (payload.value != null) ...[
            const SizedBox(height: 32),
            _PairingQr(payload: payload.value!),
          ],
        ],
      ),
    );
  }
}
