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

/// Admin-only screen to natively reset family members' passwords. Because the
/// appliance is air-gapped, there is no email-based recovery - an admin sets a
/// new temporary password here via the admin users API.
class UserManagementView extends HookConsumerWidget {
  const UserManagementView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final UserDto? me = Store.tryGet(StoreKey.currentUser);
    final myId = me?.id;

    // One-shot fetch of all users on this server. A password reset doesn't
    // change name/email, so the list needs no refresh after a reset.
    final usersFuture = useMemoized(
      () => UsersAdminApi(ref.read(apiServiceProvider).apiClient).searchUsersAdmin(),
      const [],
    );
    final snapshot = useFuture(usersFuture);

    Widget body;
    if (snapshot.connectionState == ConnectionState.waiting) {
      body = const Center(child: CircularProgressIndicator());
    } else if (snapshot.hasError) {
      body = Center(
        child: Padding(
          padding: const EdgeInsets.all(32.0),
          child: Text(
            'Could not load users: ${snapshot.error}',
            textAlign: TextAlign.center,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        ),
      );
    } else {
      // Filter out the current admin so they can't reset themselves here.
      final users = (snapshot.data ?? <UserAdminResponseDto>[])
          .where((u) => u.id != myId)
          .toList();

      if (users.isEmpty) {
        body = const Center(
          child: Padding(
            padding: EdgeInsets.all(32.0),
            child: Text('No other users on this Hearth Hub yet.', textAlign: TextAlign.center),
          ),
        );
      } else {
        body = ListView.separated(
          itemCount: users.length,
          separatorBuilder: (_, __) => const Divider(height: 1),
          itemBuilder: (_, index) => _UserTile(user: users[index]),
        );
      }
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Family Management')),
      body: body,
    );
  }
}

class _UserTile extends ConsumerWidget {
  const _UserTile({required this.user});

  final UserAdminResponseDto user;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    Future<void> onResetPassword() async {
      final newPassword = await showDialog<String>(
        context: context,
        builder: (_) => _ResetPasswordDialog(userName: user.name),
      );
      if (newPassword == null || newPassword.isEmpty) return;

      // Capture the messenger before the await so we don't touch a possibly
      // unmounted context afterwards.
      final messenger = ScaffoldMessenger.of(context);
      try {
        final usersAdminApi = UsersAdminApi(ref.read(apiServiceProvider).apiClient);
        await usersAdminApi.updateUserAdmin(user.id, UserAdminUpdateDto(password: newPassword));
        messenger
          ..hideCurrentSnackBar()
          ..showSnackBar(
            SnackBar(content: Text('Password reset for ${user.name}.'), behavior: SnackBarBehavior.floating),
          );
      } catch (e) {
        messenger
          ..hideCurrentSnackBar()
          ..showSnackBar(
            SnackBar(
              content: Text('Failed to reset password: $e'),
              backgroundColor: Theme.of(context).colorScheme.error,
              behavior: SnackBarBehavior.floating,
            ),
          );
      }
    }

    return ListTile(
      leading: const CircleAvatar(child: Icon(Icons.person_outline)),
      title: Text(user.name),
      subtitle: Text(user.email),
      trailing: TextButton.icon(
        icon: const Icon(Icons.lock_reset),
        label: const Text('Reset Password'),
        onPressed: onResetPassword,
      ),
    );
  }
}

/// Dialog that collects a new temporary password for [userName]. Pops with
/// the entered password on confirm, or null on cancel.
class _ResetPasswordDialog extends HookWidget {
  const _ResetPasswordDialog({required this.userName});

  final String userName;

  @override
  Widget build(BuildContext context) {
    final passwordController = useTextEditingController();
    final obscurePassword = useState(true);
    final errorText = useState<String?>(null);

    void confirm() {
      final value = passwordController.text;
      if (value.isEmpty) {
        errorText.value = 'Enter a temporary password.';
        return;
      }
      Navigator.of(context).pop(value);
    }

    return AlertDialog(
      title: Text('Reset password for $userName'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            'Set a temporary password. Share it with the user so they can sign in and change it.',
            style: TextStyle(fontSize: 13, color: Colors.grey),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: passwordController,
            obscureText: obscurePassword.value,
            autofocus: true,
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => confirm(),
            decoration: InputDecoration(
              labelText: 'New Temporary Password',
              border: const OutlineInputBorder(),
              errorText: errorText.value,
              suffixIcon: IconButton(
                icon: Icon(obscurePassword.value ? Icons.visibility_off : Icons.visibility),
                onPressed: () => obscurePassword.value = !obscurePassword.value,
              ),
            ),
          ),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),
        ElevatedButton(onPressed: confirm, child: const Text('Reset Password')),
      ],
    );
  }
}
