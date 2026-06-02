import 'package:immich_mobile/features/wizard/models/wizard_step.dart';

enum WizardDiscoveryStatus { idle, discovering, discovered, discoveryFailed }

class WizardState {
  final WizardStep step;
  final String serverUrl;
  final bool isLoading;
  final bool isServerValidated;
  final bool isServerInitialized;
  final String? errorMessage;
  final WizardDiscoveryStatus discoveryStatus;

  const WizardState({
    this.step = WizardStep.serverUrl,
    this.serverUrl = '',
    this.isLoading = false,
    this.isServerValidated = false,
    this.isServerInitialized = true,
    this.errorMessage,
    this.discoveryStatus = WizardDiscoveryStatus.idle,
  });

  // Manual copyWith since Freezed isn't working
  WizardState copyWith({
    WizardStep? step,
    String? serverUrl,
    bool? isLoading,
    bool? isServerValidated,
    bool? isServerInitialized,
    String? errorMessage,
    WizardDiscoveryStatus? discoveryStatus,
  }) {
    return WizardState(
      step: step ?? this.step,
      serverUrl: serverUrl ?? this.serverUrl,
      isLoading: isLoading ?? this.isLoading,
      isServerValidated: isServerValidated ?? this.isServerValidated,
      isServerInitialized: isServerInitialized ?? this.isServerInitialized,
      errorMessage: errorMessage, // We allow passing null to clear errors
      discoveryStatus: discoveryStatus ?? this.discoveryStatus,
    );
  }
}
