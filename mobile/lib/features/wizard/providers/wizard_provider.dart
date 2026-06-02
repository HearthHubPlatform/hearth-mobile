import 'dart:async';

import 'package:flutter/material.dart';
import 'package:immich_mobile/domain/models/store.model.dart';
import 'package:immich_mobile/entities/store.entity.dart';
import 'package:immich_mobile/hearth_config.dart';
import 'package:immich_mobile/providers/api.provider.dart';
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
import 'package:openapi/api.dart';

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

      // Zero-touch onboarding: ask the server whether it has been
      // initialized (i.e. whether an admin account already exists). A
      // brand-new appliance reports isInitialized=false, in which case we
      // present the in-app Admin Setup step instead of the login form.
      // We default to "initialized" if the probe fails so a transient
      // config-fetch error never strands the user on a setup screen they
      // can't complete.
      bool isInitialized = true;
      try {
        final config = await ref.read(apiServiceProvider).serverInfoApi.getServerConfig();
        isInitialized = config?.isInitialized ?? true;
        debugPrint('[Wizard] getServerConfig isInitialized=$isInitialized');
      } catch (e) {
        debugPrint('[Wizard] getServerConfig failed ($e), assuming initialized');
      }

      state = state.copyWith(
        isLoading: false,
        isServerValidated: true,
        isServerInitialized: isInitialized,
        step: isInitialized ? WizardStep.login : WizardStep.adminSetup,
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

      // Forced password change (admin-set initial password, etc.) is
      // specific to email/password auth - API-key auto-login skips it.
      if (result.shouldChangePassword && !result.isAdmin) {
        debugPrint('[Wizard] shouldChangePassword=true -> ChangePasswordRoute');
        await ref.read(appRouterProvider).push(const ChangePasswordRoute());
        return;
      }

      await _runPostAuthOrchestration(source: 'email/password login');
    } catch (e, st) {
      debugPrint('[Wizard] login FAILED for "$trimmedEmail": $e\n$st');
      final friendlyError = _friendlyLoginError(e);
      state = state.copyWith(isLoading: false, errorMessage: friendlyError);
    }
  }

  /// Zero-touch onboarding: provisions the first admin account on a
  /// brand-new appliance via `POST /auth/admin-sign-up`, then immediately
  /// authenticates the new credentials by chaining into [login] (which
  /// runs the full post-auth orchestration and routes to the timeline).
  ///
  /// Only meaningful while the server reports `isInitialized == false`;
  /// the backend rejects a second admin sign-up with a 400 once an admin
  /// exists, which surfaces here as a friendly error.
  Future<void> createAdmin(String email, String password, String name) async {
    final trimmedEmail = email.trim();
    final trimmedName = name.trim();
    state = state.copyWith(isLoading: true, errorMessage: null);

    try {
      debugPrint('[Wizard] createAdmin: signing up first admin "$trimmedEmail"');
      await ref
          .read(apiServiceProvider)
          .authenticationApi
          .signUpAdmin(SignUpDto(email: trimmedEmail, password: password, name: trimmedName));
      debugPrint('[Wizard] createAdmin: admin created, chaining into login()');

      // login() owns the isLoading lifecycle + post-auth orchestration, so
      // we hand off directly. The server is now initialized.
      state = state.copyWith(isServerInitialized: true);
      await login(trimmedEmail, password);
    } catch (e, st) {
      debugPrint('[Wizard] createAdmin FAILED for "$trimmedEmail": $e\n$st');
      state = state.copyWith(isLoading: false, errorMessage: _friendlyLoginError(e));
    }
  }

  /// Shared post-authentication orchestration. Runs after either a
  /// successful email/password login or an API-key handoff, and mirrors
  /// login_form.dart:255-266 step-for-step (minus the manage-media
  /// dialog, which needs a BuildContext we don't have here).
  ///
  /// Branches:
  ///   - beta timeline -> request gallery permission, kick off sync,
  ///     connect websocket, replaceAll([TabShellRoute()]).
  ///   - legacy timeline -> replaceAll([TabControllerRoute()]).
  Future<void> _runPostAuthOrchestration({required String source}) async {
    final router = ref.read(appRouterProvider);
    final isBeta = Store.isBetaTimelineEnabled;

    if (isBeta) {
      debugPrint('[Wizard][$source] beta timeline -> requesting gallery permission');
      await ref.read(galleryPermissionNotifier.notifier).requestGalleryPermission();

      // login_form.dart calls getManageMediaPermission() here on Android
      // when StoreKey.manageLocalMediaAndroid is true. That helper shows
      // an AlertDialog, which a provider cannot open. The prompt is
      // intentionally deferred - the user can grant it later from
      // Settings.

      debugPrint('[Wizard][$source] beta -> handleSyncFlow (unawaited)');
      unawaited(_handleSyncFlow());

      debugPrint('[Wizard][$source] beta -> websocket connect');
      ref.read(websocketProvider.notifier).connect();

      debugPrint('[Wizard][$source] -> TabShellRoute (replaceAll)');
      unawaited(router.replaceAll([const TabShellRoute()]));
      return;
    }

    // Legacy (non-beta) timeline - straight to TabController. Still
    // request gallery permission so the timeline can populate from the
    // local device immediately on first launch.
    debugPrint('[Wizard][$source] legacy -> requesting gallery permission');
    await ref.read(galleryPermissionNotifier.notifier).requestGalleryPermission();
    debugPrint('[Wizard][$source] legacy -> TabControllerRoute (replaceAll)');
    await router.replaceAll([const TabControllerRoute()]);
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

  /// Parses a raw QR pairing payload such as
  /// `hearth://pair?host=10.20.30.232&email=admin@hearth.local&pass=secret`:
  ///   1. Extracts `host` and connects to `http://<host>:2283` via
  ///      [connectToServer] (skips the mDNS sweep).
  ///   2. If `email` + `pass` query params are present, delegates straight
  ///      to [login], which performs the standard email/password sign-in
  ///      (issuing a real Session Token via /auth/login) and runs the full
  ///      post-auth orchestration. This is the only auth path that yields a
  ///      session token the sync endpoints will accept.
  ///   3. If credentials are absent, the wizard simply lands on the login
  ///      step with the server already validated.
  Future<void> processQRCodePayload(String rawPayload) async {
    debugPrint('[Wizard] processQRCodePayload raw="$rawPayload"');

    final uri = Uri.tryParse(rawPayload);
    if (uri == null || uri.scheme != 'hearth' || uri.host != 'pair') {
      debugPrint('[Wizard] processQRCodePayload: rejecting non-hearth uri');
      state = state.copyWith(errorMessage: 'That QR code is not a Hearth Hub pairing code.');
      return;
    }

    final host = uri.queryParameters['host']?.trim();
    if (host == null || host.isEmpty) {
      debugPrint('[Wizard] processQRCodePayload: missing host param');
      state = state.copyWith(errorMessage: 'Pairing QR code is missing the host address.');
      return;
    }

    // Force the canonical Hearth port; the QR payload deliberately omits
    // it so we cannot be tricked into talking to an arbitrary port.
    final connectUrl = 'http://$host:${HearthConfig.defaultPort}';
    debugPrint('[Wizard] processQRCodePayload -> connectToServer("$connectUrl")');
    await connectToServer(connectUrl);

    // connectToServer sets isServerValidated=true on success and an
    // errorMessage on failure. Bail if it failed - the SnackBar listener
    // in the UI will surface the reason.
    if (!state.isServerValidated) {
      debugPrint('[Wizard] processQRCodePayload: server validation failed, aborting credential handoff');
      return;
    }

    final email = uri.queryParameters['email']?.trim();
    final pass = uri.queryParameters['pass'];
    if (email == null || email.isEmpty || pass == null || pass.isEmpty) {
      debugPrint('[Wizard] processQRCodePayload: no email/pass, leaving wizard on login step');
      return;
    }

    // Hand off to the standard login path. login() issues a real Session
    // Token via /auth/login, persists it, and runs the full post-auth
    // orchestration (sync, websocket, routing) - the same flow as a manual
    // sign-in, so background isolates get a sync-capable session token.
    debugPrint('[Wizard] processQRCodePayload: credentials present, delegating to login()');
    await login(email, pass);
  }
}
