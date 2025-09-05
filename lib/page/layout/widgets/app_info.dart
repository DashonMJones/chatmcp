import 'package:chatmcp/page/layout/widgets/llm_icon.dart';
import 'package:flutter/material.dart';
import 'package:chatmcp/utils/color.dart';
import 'package:chatmcp/utils/platform.dart';
import 'package:chatmcp/generated/app_localizations.dart';
import 'package:logging/logging.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:chatmcp/widgets/upgrade.dart';
import 'package:url_launcher/url_launcher.dart';

class AppInfo extends StatelessWidget {
  final String? appWebsite;
  final String? githubUrl;
  final String? licenseInfo;

  const AppInfo({super.key, this.appWebsite, this.githubUrl = 'https://github.com/daodao97/chatmcp', this.licenseInfo = 'Apache License 2.0'});

  Future<String> _getAppVersion() async {
    final packageInfo = await PackageInfo.fromPlatform();
    return packageInfo.version;
  }

  void _showAboutDialog(BuildContext context) async {
    final l10n = AppLocalizations.of(context)!;
    final version = await _getAppVersion();

    Logger.root.info('AppInfo: $version');

    if (!context.mounted) return;

    showDialog(
      context: context,
      builder: (context) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8.0)),
        child: Container(
          width: kIsMobile ? null : 450,
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Logo
              ClipRRect(borderRadius: BorderRadius.circular(8.0), child: Image.asset('assets/logo.png', width: 80, height: 80)),
              const SizedBox(height: 16),

              // App Name
              Text(
                'Rovena',
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: AppColors.getThemeTextColor(context)),
              ),

              // Version
              Text('v$version', style: TextStyle(fontSize: 16, color: AppColors.getThemeTextColor(context).withAlpha(120))),
              const SizedBox(height: 16),

              // Description
              Text(
                l10n.appDescription,
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 14, color: AppColors.getThemeTextColor(context)),
              ),
              const SizedBox(height: 24),

              // Links
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (appWebsite != null) _buildLinkButton(context, LlmIcon(icon: "github"), l10n.visitWebsite, appWebsite!),
                  if (appWebsite != null && githubUrl != null) const SizedBox(width: 12),
                  if (githubUrl != null) _buildLinkButton(context, LlmIcon(icon: "github"), 'GitHub', githubUrl!),
                  const SizedBox(width: 12),
                  UpgradeNotice(owner: 'daodao97', repo: 'chatmcp', showCheckUpdate: true, autoCheck: true),
                ],
              ),

              if (licenseInfo != null) ...[
                const SizedBox(height: 16),
                Text(
                  licenseInfo!,
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 12, color: AppColors.getThemeTextColor(context).withAlpha(128)),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLinkButton(BuildContext context, LlmIcon icon, String label, String url) {
    return InkWell(
      onTap: () {
        launchUrl(Uri.parse(url));
      },
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(color: AppColors.getInkIconHoverColor(context), borderRadius: BorderRadius.circular(20)),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            icon,
            const SizedBox(width: 8),
            Text(label, style: TextStyle(color: AppColors.getThemeTextColor(context))),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => _showAboutDialog(context),
      child: LlmIcon(icon: "github", tooltip: AppLocalizations.of(context)!.aboutApp),
    );
  }
}
