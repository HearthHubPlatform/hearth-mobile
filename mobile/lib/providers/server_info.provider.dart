import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:immich_mobile/domain/models/user.model.dart';
import 'package:immich_mobile/models/server_info/server_config.model.dart';
import 'package:immich_mobile/models/server_info/server_disk_info.model.dart';
import 'package:immich_mobile/models/server_info/server_features.model.dart';
import 'package:immich_mobile/models/server_info/server_info.model.dart';
import 'package:immich_mobile/models/server_info/server_version.model.dart';
import 'package:immich_mobile/services/server_info.service.dart';
import 'package:logging/logging.dart';

class ServerInfoNotifier extends StateNotifier<ServerInfo> {
  ServerInfoNotifier(this._serverInfoService)
    : super(
        const ServerInfo(
          serverVersion: ServerVersion(major: 0, minor: 0, patch: 0),
          serverFeatures: ServerFeatures(map: true, trash: true, oauthEnabled: false, passwordLogin: true),
          serverConfig: ServerConfig(
            trashDays: 30,
            oauthButtonText: '',
            externalDomain: '',
            mapLightStyleUrl: 'https://tiles.immich.cloud/v1/style/light.json',
            mapDarkStyleUrl: 'https://tiles.immich.cloud/v1/style/dark.json',
          ),
          serverDiskInfo: ServerDiskInfo(diskAvailable: "0", diskSize: "0", diskUse: "0", diskUsagePercentage: 0),
          versionStatus: VersionStatus.upToDate,
        ),
      );

  final ServerInfoService _serverInfoService;
  final _log = Logger("ServerInfoNotifier");

  Future<ServerInfo> getServerInfo() async {
    await getServerVersion();
    await getServerFeatures();
    await getServerConfig();
    return state;
  }

  Future<void> getServerVersion() async {
    // Hearth Hub is a sovereign, air-gapped appliance: we never compare
    // versions or surface an "update available" banner. We still record the
    // server version for display, but the status is always upToDate.
    try {
      final serverVersion = await _serverInfoService.getServerVersion();
      if (serverVersion == null) {
        return;
      }
      await _checkServerVersionMismatch(serverVersion);
    } catch (e, stackTrace) {
      _log.severe("Failed to get server version", e, stackTrace);
      return;
    }
  }

  _checkServerVersionMismatch(ServerVersion serverVersion) async {
    // Sovereign appliance: ignore any latest/release version and never flag a
    // mismatch. Record the server version and force upToDate so the update
    // banner can never render.
    state = state.copyWith(serverVersion: serverVersion, versionStatus: VersionStatus.upToDate);
  }

  handleReleaseInfo(ServerVersion serverVersion, ServerVersion? latestVersion) {
    // Neutered for Hearth Hub: release/update info (originating from GitHub via
    // the server) is ignored so the app always believes it is up to date.
  }

  getServerFeatures() async {
    final serverFeatures = await _serverInfoService.getServerFeatures();
    if (serverFeatures == null) {
      return;
    }
    state = state.copyWith(serverFeatures: serverFeatures);
  }

  getServerConfig() async {
    final serverConfig = await _serverInfoService.getServerConfig();
    if (serverConfig == null) {
      return;
    }
    state = state.copyWith(serverConfig: serverConfig);
  }
}

final serverInfoProvider = StateNotifierProvider<ServerInfoNotifier, ServerInfo>((ref) {
  return ServerInfoNotifier(ref.read(serverInfoServiceProvider));
});

final versionWarningPresentProvider = Provider.family<bool, UserDto?>((ref, user) {
  // Sovereign appliance: the update/version-mismatch banner is permanently
  // disabled so users can never be nudged toward the official Immich app.
  return false;
});
