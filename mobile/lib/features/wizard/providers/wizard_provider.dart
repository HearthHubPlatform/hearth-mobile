import 'dart:async';

import 'package:flutter/material.dart';
import 'package:immich_mobile/domain/models/store.model.dart';
import 'package:immich_mobile/entities/store.entity.dart';
import 'package:immich_mobile/hearth_config.dart';
import 'package:immich_mobile/providers/auth.provider.dart';
import 'package:immich_mobile/providers/background_sync.provider.dart';
import 'package:immich_mobile/providers/gallery_permission.provider.dart';
import 'package:immich_mobile/providers/infrastructure/search.provider.dart';
import 'package:immich_mobile/providers/infrastructure/user.provider.dart';
import 'package:immich_mobile/providers/websocket.provider.dart';
import 'package:immich_mobile/repositories/activity_api.repository.dart';
import 'package:immich_mobile/repositories/album_api.repository.dart';
import 'package:immich_mobile/repositories/asset_api.repository.dart';
import 'package:immich_mobile/repositories/drift_album_api_repository.dart';
import 'package:immich_mobile/repositories/partner_api.repository.dart';
import 'package:immich_mobile/repositories/person_api.repository.dart';
import 'package:immich_mobile/repositories/timeline.repository.dart';
import 'package:immich_mobile/routing/router.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:immich_mobile/features/wizard/models/wizard_state.dart';
import 'package:immich_mobile/features/wizard/models/wizard_step.dart';
import 'package:immich_mobile/features/wizard/services/discovery.service.dart';

part 'wizard_provider.g.dart';

@riverpod
class WizardLogic extends _$WizardLogic {
  @override
  WizardState build() {
    return const WizardState();
  }

  /// Normalizes a raw server URL string into the canonical Hearth Hub
  /// endpoint `http://<host>:2283`. The Immich Core API is strictly
  /// isolated on port 2283; any other port is rewritten.
  String normalizeServerUrl(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) {
      return HearthConfig.serverUrl;
    }

    final withScheme = trimmed.contains('://') ? trimmed : 'http://$trimmed';
    final uri = Uri.tryParse(withScheme);
    if (uri == null || uri.host.isEmpty) {
      return HearthConfig.serverUrl;
    }

    // Always force the Hearth port, regardless of what mDNS or the QR
    // payload claimed.
    final forced = Uri(
      scheme: uri.scheme.isEmpty ? 'http' : uri.scheme,
      host: uri.host,
      port: HearthConfig.defaultPort,
      path: uri.path,
    );
    return forced.toString();
  }

  void setServerUrl(String url) {
    state = state.copyWith(serverUrl: normalizeServerUrl(url), errorMessage: null);
  }

  void moveToStep(WizardStep step) {
    state = state.copyWith(step: step);
  }

  /// Triggers mDNS discovery on the local network with a 5s budget.
  /// On success, the discovered URL is normalized to :2283 and wired
  /// into the global Immich ApiService via [authProvider.validateServerUrl].
  Future<void> startDiscovery() async {
    if (state.discoveryStatus == WizardDiscoveryStatus.discovering) {
      return;
    }

    state = state.copyWith(isLoading: true, errorMessage: null, discoveryStatus: WizardDiscoveryStatus.discovering);
    debugPrint('[Wizard] startDiscovery: kicking off mDNS sweep');

    try {
      // Capture the URL from the method's return value directly. Reading
      // hearthDiscoveryProvider's AsyncValue.state here previously raced
      // with Riverpod's internal FutureHandler when the native nsd plugin
      // threw on a background thread, producing "Bad state: Future
      // already completed". The discovery service no longer mutates its
      // state at all - the URL is the contract.
      final discoveredUrl = await ref.read(hearthDiscoveryProvider.notifier).discoverServer();
      debugPrint('[Wizard] startDiscovery: mDNS resolved url="$discoveredUrl"');

      if (discoveredUrl == null || discoveredUrl.isEmpty) {
        state = state.copyWith(isLoading: false, discoveryStatus: WizardDiscoveryStatus.discoveryFailed);
        return;
      }

      // Auto-advance: connectToServer awaits validateServerUrl and, on
      // success, sets step=login + discoveryStatus=discovered, which the
      // WizardScreen ref.listen will pick up to swap views.
      await connectToServer(discoveredUrl, WizardDiscoveryStatus.discovered);
      debugPrint(
        '[Wizard] startDiscovery: connectToServer returned step=${state.step} status=${state.discoveryStatus}',
      );
    } catch (e, st) {
      debugPrint('[Wizard] startDiscovery FAILED: $e\n$st');
      state = state.copyWith(isLoading: false, discoveryStatus: WizardDiscoveryStatus.discoveryFailed);
    }
  }

  /// Normalizes the URL, pushes it into Immich's native ApiService via
  /// [AuthNotifier.validateServerUrl] (which writes to StoreKey.serverEndpoint
  /// so the rest of the app picks it up), and advances the wizard to the
  /// login step on success.
  Future<void> connectToServer(String rawUrl, [WizardDiscoveryStatus? discoveryStatusOnSuccess]) async {
    final normalizedUrl = normalizeServerUrl(rawUrl);
    debugPrint('[Wizard] connectToServer raw="$rawUrl" normalized="$normalizedUrl"');
    state = state.copyWith(serverUrl: normalizedUrl, isLoading: true, errorMessage: null);

    try {
      final resolved = await ref.read(authProvider.notifier).validateServerUrl(normalizedUrl);
      debugPrint('[Wizard] validateServerUrl resolved="$resolved"');
      state = state.copyWith(
        isLoading: false,
        isServerValidated: true,
        step: WizardStep.login,
        discoveryStatus: discoveryStatusOnSuccess ?? WizardDiscoveryStatus.discovered,
      );
    } catch (e, stack) {
      debugPrint('[Wizard] validateServerUrl FAILED for "$normalizedUrl": $e\n$stack');
      state = state.copyWith(
        isLoading: false,
        discoveryStatus: WizardDiscoveryStatus.discoveryFailed,
        errorMessage: 'Could not reach $normalizedUrl. ${e.toString()}',
      );
    }
  }

  Future<void> validateServer() async {
    final target = state.serverUrl.isEmpty ? HearthConfig.serverUrl : state.serverUrl;
    await connectToServer(target);
  }

  Future<void> login(String email, String password) async {
    final trimmedEmail = email.trim();
    state = state.copyWith(isLoading: true, errorMessage: null);

    // Mirror login_form.dart:247 - invalidate every API repository so the
    // next .read pulls a fresh client with the new access token / endpoint.
    _invalidateAllApiRepositoryProviders();

    try {
      final result = await ref.read(authProvider.notifier).login(trimmedEmail, password);
      debugPrint('[Wizard] login successful for $trimmedEmail');
      state = state.copyWith(isLoading: false);

      final router = ref.read(appRouterProvider);

      // Branch 1: forced password change (admin-set initial password, etc.)
      if (result.shouldChangePassword && !result.isAdmin) {
        debugPrint('[Wizard] shouldChangePassword=true -> ChangePasswordRoute');
        await router.push(const ChangePasswordRoute());
        return;
      }

      // Branch 2: beta timeline - full sync orchestration, then TabShellRoute.
      // Mirrors login_form.dart:255-265 step-for-step, minus the manage-media
      // permission dialog (skipped because dialogs require a BuildContext
      // which the wizard provider does not have; see comment below).
      final isBeta = Store.isBetaTimelineEnabled;
      if (isBeta) {
        debugPrint('[Wizard] beta timeline -> requesting gallery permission');
        await ref.read(galleryPermissionNotifier.notifier).requestGalleryPermission();

        // login_form.dart calls getManageMediaPermission() here on Android
        // when StoreKey.manageLocalMediaAndroid is true. That helper shows
        // an AlertDialog asking the user to grant MANAGE_MEDIA. We can't
        // open dialogs from a provider, so this prompt is intentionally
        // deferred - the user can grant it later from Settings, or we can
        // surface it from login_step.dart after this method returns.

        debugPrint('[Wizard] beta -> handleSyncFlow (background, unawaited)');
        unawaited(_handleSyncFlow());

        debugPrint('[Wizard] beta -> websocket connect');
        ref.read(websocketProvider.notifier).connect();

        debugPrint('[Wizard] -> TabShellRoute (replaceAll)');
        unawaited(router.replaceAll([const TabShellRoute()]));
        return;
      }

      // Branch 3: legacy (non-beta) timeline - straight to TabController.
      debugPrint('[Wizard] legacy timeline -> TabControllerRoute (replaceAll)');
      await router.replaceAll([const TabControllerRoute()]);
    } catch (e, st) {
      debugPrint('[Wizard] login FAILED for "$trimmedEmail": $e\n$st');
      final friendlyError = _friendlyLoginError(e);
      state = state.copyWith(isLoading: false, errorMessage: friendlyError);
    }
  }

  /// Mirrors login_form.dart's `handleSyncFlow()` (lines 182-192). Pulls
  /// the local media catalog, drains the remote sync stream, hashes new
  /// assets, and optionally re-syncs linked albums when the user opted
  /// into album sync. Run unawaited so the UI can transition immediately.
  Future<void> _handleSyncFlow() async {
    final backgroundManager = ref.read(backgroundSyncProvider);
    debugPrint('[Wizard] handleSyncFlow: syncLocal(full)');
    await backgroundManager.syncLocal(full: true);
    debugPrint('[Wizard] handleSyncFlow: syncRemote');
    await backgroundManager.syncRemote();
    debugPrint('[Wizard] handleSyncFlow: hashAssets');
    await backgroundManager.hashAssets();
    if (Store.get(StoreKey.syncAlbums, false)) {
      debugPrint('[Wizard] handleSyncFlow: syncLinkedAlbum');
      await backgroundManager.syncLinkedAlbum();
    }
    debugPrint('[Wizard] handleSyncFlow: complete');
  }

  /// Direct inline port of `utils/provider_utils.dart`'s
  /// `invalidateAllApiRepositoryProviders`, which takes a `WidgetRef` and
  /// is therefore unusable from a riverpod_annotation Notifier. The body
  /// is byte-identical to the upstream helper - keep them in sync.
  void _invalidateAllApiRepositoryProviders() {
    ref.invalidate(userApiRepositoryProvider);
    ref.invalidate(activityApiRepositoryProvider);
    ref.invalidate(partnerApiRepositoryProvider);
    ref.invalidate(albumApiRepositoryProvider);
    ref.invalidate(personApiRepositoryProvider);
    ref.invalidate(assetApiRepositoryProvider);
    ref.invalidate(timelineRepositoryProvider);
    ref.invalidate(searchApiRepositoryProvider);
    ref.invalidate(driftAlbumApiRepositoryProvider);
  }

  String _friendlyLoginError(Object error) {
    final message = error.toString();
    if (message.contains('401') || message.toLowerCase().contains('unauthorized')) {
      return 'Invalid email or password.';
    }
    if (message.contains('SocketException') || message.toLowerCase().contains('network')) {
      return 'Could not reach the server. Check your connection.';
    }
    return 'Login failed. Please try again.';
  }

  void reset() {
    state = const WizardState();
  }
}
