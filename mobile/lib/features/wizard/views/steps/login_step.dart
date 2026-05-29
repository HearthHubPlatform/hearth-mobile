import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:immich_mobile/features/wizard/models/wizard_state.dart';
import 'package:immich_mobile/features/wizard/providers/wizard_provider.dart';
import 'package:immich_mobile/features/wizard/models/wizard_step.dart';

class LoginStep extends HookConsumerWidget {
  const LoginStep({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(wizardLogicProvider);
    final notifier = ref.read(wizardLogicProvider.notifier);

    final emailController = useTextEditingController();
    final passwordController = useTextEditingController();

    // Surface backend / validation failures from `notifier.login` as a
    // red SnackBar. We listen on the wizard state instead of awaiting
    // the future so the UI stays decoupled from the call site and
    // multiple error sources (validateServer, login) can share the
    // same surface.
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
        Icon(Icons.lock_person_outlined, size: 80, color: Theme.of(context).colorScheme.primary),
        const SizedBox(height: 24),
        const Text("Sign In", style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold)),
        const SizedBox(height: 12),
        Text("Connected to ${state.serverUrl}", style: const TextStyle(color: Colors.grey)),
        const SizedBox(height: 40),
        TextField(
          controller: emailController,
          decoration: const InputDecoration(
            labelText: "Email Address",
            prefixIcon: Icon(Icons.email_outlined),
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 16),
        TextField(
          controller: passwordController,
          obscureText: true,
          decoration: const InputDecoration(
            labelText: "Password",
            prefixIcon: Icon(Icons.password_outlined),
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 32),
        SizedBox(
          height: 50,
          width: double.infinity,
          child: ElevatedButton(
            onPressed: state.isLoading ? null : () => notifier.login(emailController.text, passwordController.text),
            child: state.isLoading
                ? const SizedBox(
                    height: 24,
                    width: 24,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.5,
                      valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                    ),
                  )
                : const Text("Login to Hearth Hub"),
          ),
        ),
        TextButton(onPressed: () => notifier.moveToStep(WizardStep.serverUrl), child: const Text("Change Server URL")),
      ],
    );
  }
}
