import 'package:auto_route/auto_route.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart' hide Store;
import 'package:immich_mobile/domain/models/store.model.dart';
import 'package:immich_mobile/entities/store.entity.dart';
import 'package:immich_mobile/extensions/build_context_extensions.dart';
import 'package:immich_mobile/features/wizard/views/pairing_hub_view.dart';
import 'package:immich_mobile/features/wizard/views/user_management_view.dart';
import 'package:immich_mobile/routing/router.dart';
import 'package:immich_mobile/widgets/settings/advanced_settings.dart';
import 'package:immich_mobile/widgets/settings/asset_list_settings/asset_list_settings.dart';
import 'package:immich_mobile/widgets/settings/asset_viewer_settings/asset_viewer_settings.dart';
import 'package:immich_mobile/widgets/settings/backup_settings/backup_settings.dart';
import 'package:immich_mobile/widgets/settings/backup_settings/drift_backup_settings.dart';
import 'package:immich_mobile/widgets/settings/beta_sync_settings/sync_status_and_actions.dart';
import 'package:immich_mobile/widgets/settings/free_up_space_settings.dart';
import 'package:immich_mobile/widgets/settings/language_settings.dart';
import 'package:immich_mobile/widgets/settings/networking_settings/networking_settings.dart';
import 'package:immich_mobile/widgets/settings/notification_setting.dart';
import 'package:immich_mobile/widgets/settings/preference_settings/preference_setting.dart';
import 'package:immich_mobile/widgets/settings/settings_card.dart';

enum SettingSection {
  advanced('advanced', Icons.build_outlined, "advanced_settings_tile_subtitle"),
  assetViewer('asset_viewer_settings_title', Icons.image_outlined, "asset_viewer_settings_subtitle"),
  backup('backup', Icons.cloud_upload_outlined, "backup_settings_subtitle"),
  freeUpSpace('free_up_space', Icons.cleaning_services_outlined, "free_up_space_settings_subtitle"),
  languages('language', Icons.language, "setting_languages_subtitle"),
  networking('networking_settings', Icons.wifi, "networking_subtitle"),
  notifications('notifications', Icons.notifications_none_rounded, "setting_notifications_subtitle"),
  preferences('preferences_settings_title', Icons.interests_outlined, "preferences_settings_subtitle"),
  timeline('asset_list_settings_title', Icons.auto_awesome_mosaic_outlined, "asset_list_settings_subtitle"),
  beta('sync_status', Icons.sync_outlined, "sync_status_subtitle");

  final String title;
  final String subtitle;
  final IconData icon;

  Widget get widget => switch (this) {
    SettingSection.advanced => const AdvancedSettings(),
    SettingSection.assetViewer => const AssetViewerSettings(),
    SettingSection.backup =>
      Store.tryGet(StoreKey.betaTimeline) ?? false ? const DriftBackupSettings() : const BackupSettings(),
    SettingSection.freeUpSpace => const FreeUpSpaceSettings(),
    SettingSection.languages => const LanguageSettings(),
    SettingSection.networking => const NetworkingSettings(),
    SettingSection.notifications => const NotificationSetting(),
    SettingSection.preferences => const PreferenceSetting(),
    SettingSection.timeline => const AssetListSettings(),
    SettingSection.beta => const SyncStatusAndActions(),
  };

  const SettingSection(this.title, this.icon, this.subtitle);
}

@RoutePage()
class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    context.locale;
    return Scaffold(
      appBar: AppBar(centerTitle: false, title: const Text('settings').tr()),
      body: context.isMobile ? const _MobileLayout() : const _TabletLayout(),
    );
  }
}

class _MobileLayout extends StatelessWidget {
  const _MobileLayout();
  @override
  Widget build(BuildContext context) {
    final List<Widget> settings = SettingSection.values
        .expand(
          (setting) => setting == SettingSection.beta
              ? [
                  if (Store.isBetaTimelineEnabled)
                    SettingsCard(
                      icon: Icons.sync_outlined,
                      title: 'sync_status'.tr(),
                      subtitle: 'sync_status_subtitle'.tr(),
                      settingRoute: const SyncStatusRoute(),
                    ),
                ]
              : [
                  SettingsCard(
                    title: setting.title.tr(),
                    subtitle: setting.subtitle.tr(),
                    icon: setting.icon,
                    settingRoute: SettingsSubRoute(section: setting),
                  ),
                ],
        )
        .toList();
    final isAdmin = Store.tryGet(StoreKey.currentUser)?.isAdmin ?? false;
    return ListView(
      padding: const EdgeInsets.only(top: 10.0, bottom: 60),
      children: [
        const _PairingHubTile(),
        if (isAdmin) const _FamilyManagementTile(),
        ...settings,
      ],
    );
  }
}

class _TabletLayout extends HookWidget {
  const _TabletLayout();
  @override
  Widget build(BuildContext context) {
    final selectedSection = useState<SettingSection>(SettingSection.values.first);

    return Row(
      mainAxisAlignment: MainAxisAlignment.start,
      children: [
        Expanded(
          flex: 2,
          child: CustomScrollView(
            slivers: [
              ...SettingSection.values.map(
                (s) => SliverToBoxAdapter(
                  child: ListTile(
                    title: Text(s.title).tr(),
                    leading: Icon(s.icon),
                    selected: s.index == selectedSection.value.index,
                    selectedColor: context.primaryColor,
                    selectedTileColor: context.themeData.highlightColor,
                    onTap: () => selectedSection.value = s,
                  ),
                ),
              ),
            ],
          ),
        ),
        const VerticalDivider(width: 1),
        Expanded(flex: 4, child: selectedSection.value.widget),
      ],
    );
  }
}

/// Card styled to match the native [SettingsCard] (same Padding/Card/ListTile
/// markup, radius, colors, and primary-colored title) but driven by a plain
/// Navigator.push instead of an AutoRoute, because this fork does not run
/// build_runner to regenerate router.gr.dart.
class _PairingSettingsCard extends StatelessWidget {
  const _PairingSettingsCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0),
      child: Card(
        elevation: 0,
        clipBehavior: Clip.antiAlias,
        color: context.colorScheme.surfaceContainer,
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(16))),
        margin: const EdgeInsets.symmetric(vertical: 4.0),
        child: ListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 16.0),
          leading: Container(
            decoration: BoxDecoration(
              borderRadius: const BorderRadius.all(Radius.circular(16)),
              color: context.isDarkTheme ? Colors.black26 : Colors.white.withAlpha(100),
            ),
            padding: const EdgeInsets.all(16.0),
            child: Icon(icon, color: context.primaryColor),
          ),
          title: Text(title, style: context.textTheme.titleMedium!.copyWith(color: context.primaryColor)),
          subtitle: Text(subtitle, style: context.textTheme.bodyMedium),
          onTap: onTap,
        ),
      ),
    );
  }
}

/// Account action: opens the Device & Family Pairing hub (link a new device
/// for the current user, or - for admins - create a family member account).
class _PairingHubTile extends StatelessWidget {
  const _PairingHubTile();

  @override
  Widget build(BuildContext context) {
    return _PairingSettingsCard(
      icon: Icons.qr_code_scanner,
      title: 'Device & Family Pairing',
      subtitle: 'Link a new device or add a family member',
      onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const PairingHubView())),
    );
  }
}

/// Admin-only action: opens the Family Management screen to natively reset a
/// user's password (no email recovery on an air-gapped appliance).
class _FamilyManagementTile extends StatelessWidget {
  const _FamilyManagementTile();

  @override
  Widget build(BuildContext context) {
    return _PairingSettingsCard(
      icon: Icons.manage_accounts,
      title: 'Family Management',
      subtitle: 'Reset a family member\'s password',
      onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const UserManagementView())),
    );
  }
}

@RoutePage()
class SettingsSubPage extends StatelessWidget {
  const SettingsSubPage(this.section, {super.key});

  final SettingSection section;

  @override
  Widget build(BuildContext context) {
    context.locale;
    return Scaffold(
      appBar: AppBar(centerTitle: false, title: Text(section.title).tr()),
      body: section.widget,
    );
  }
}
