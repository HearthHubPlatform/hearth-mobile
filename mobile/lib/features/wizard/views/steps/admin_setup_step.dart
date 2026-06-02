import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:immich_mobile/features/wizard/models/wizard_state.dart';
import 'package:immich_mobile/features/wizard/providers/wizard_provider.dart';

class AdminSetupStep extends HookConsumerWidget {
  const AdminSetupStep({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(wizardLogicProvider);
    final notifier = ref.read(wizardLogicProvider.notifier);

    final nameController = useTextEditingController();
    final emailController = useTextEditingController();
    final passwordController = useTextEditingController();
    final obscurePassword = useState(true);

    // Surface backend / validation failures from `notifier.createAdmin` as a
    // red SnackBar. We listen on the wizard state instead of awaiting the
    // future so the UI stays decoupled from the call site.
    ref.listen<WizardState>(wizardLogicProvider, (previous, next) {
      final newError = next.errorMessage;
      if (newError != null && newError.isNotEmpty && newError != previous?.errorMessage) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(
            SnackBar(
              content: Text(newError),
              backgroundColor: Theme.of(context).colorScheme.error,
              behavior: SnackBarBehavior.floating,
            ),
          );
      }
    });

    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(Icons.admin_panel_settings_outlined, size: 80, color: Theme.of(context).colorScheme.primary),
        const SizedBox(height: 24),
        const Text("Welcome to Hearth Hub", style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold)),
        const SizedBox(height: 12),
        const Text(
          "This is a brand-new Hearth Hub. Create the first administrator account to get started.",
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 16, color: Colors.grey),
        ),
        const SizedBox(height: 40),
        TextField(
          controller: nameController,
          textInputAction: TextInputAction.next,
          decoration: const InputDecoration(
            labelText: "Name",
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
            labelText: "Email Address",
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
            labelText: "Password",
            prefixIcon: const Icon(Icons.password_outlined),
            border: const OutlineInputBorder(),
            suffixIcon: IconButton(
              icon: Icon(obscurePassword.value ? Icons.visibility_off : Icons.visibility),
              onPressed: () => obscurePassword.value = !obscurePassword.value,
            ),
          ),
        ),
        const SizedBox(height: 32),
        SizedBox(
          height: 50,
          width: double.infinity,
          child: ElevatedButton(
            onPressed: state.isLoading
                ? null
                : () => notifier.createAdmin(emailController.text, passwordController.text, nameController.text),
            child: state.isLoading
                ? const SizedBox(
                    height: 24,
                    width: 24,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.5,
                      valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                    ),
                  )
                : const Text("Create Hearth Hub Admin"),
          ),
        ),
      ],
    );
  }
}
