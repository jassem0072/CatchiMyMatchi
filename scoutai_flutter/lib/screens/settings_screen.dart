import 'package:flutter/material.dart';

import '../app/scoutai_app.dart';
import '../services/auth_storage.dart';
import '../services/locale_notifier.dart';
import '../services/translations.dart';
import '../theme/app_colors.dart';
import '../theme/theme_notifier.dart';
import '../widgets/common.dart';

/// Settings screen: Dark/Light, FR/EN, Notifications, App info, Terms, Privacy, Help.
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _darkMode = ThemeNotifier.instance.isDark;
  bool _notificationsEnabled = true;
  String _language = LocaleNotifier.instance.code == 'fr' ? 'FR' : 'EN';

  Future<void> _logout() async {
    await AuthStorage.clear();
    if (!mounted) return;
    Navigator.of(context).pushNamedAndRemoveUntil(AppRoutes.login, (_) => false);
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    return GradientScaffold(
      appBar: AppBar(title: Text(s.settings)),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(18, 8, 18, 28),
        children: [
          Text(
            s.appearance,
            style: TextStyle(color: AppColors.txMuted(context), fontWeight: FontWeight.w900, letterSpacing: 1.8),
          ),
          const SizedBox(height: 12),
          GlassCard(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(s.darkMode, style: const TextStyle(fontWeight: FontWeight.w700)),
              subtitle: Text(s.useDarkTheme, style: TextStyle(color: AppColors.txMuted(context), fontSize: 12)),
              value: _darkMode,
              onChanged: (v) {
                ThemeNotifier.instance.setDark(v);
                setState(() => _darkMode = v);
              },
              secondary: Icon(
                _darkMode ? Icons.dark_mode : Icons.light_mode,
                color: AppColors.primary,
              ),
            ),
          ),
          const SizedBox(height: 18),
          Text(
            s.language,
            style: TextStyle(color: AppColors.txMuted(context), fontWeight: FontWeight.w900, letterSpacing: 1.8),
          ),
          const SizedBox(height: 12),
          GlassCard(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Column(
              children: [
                RadioListTile<String>(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('English', style: TextStyle(fontWeight: FontWeight.w700)),
                  value: 'EN',
                  groupValue: _language,
                  onChanged: (v) {
                    LocaleNotifier.instance.setLocale('en');
                    setState(() => _language = v ?? 'EN');
                  },
                  secondary: const Text('🇬🇧', style: TextStyle(fontSize: 22)),
                ),
                const Divider(height: 1),
                RadioListTile<String>(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Français', style: TextStyle(fontWeight: FontWeight.w700)),
                  value: 'FR',
                  groupValue: _language,
                  onChanged: (v) {
                    LocaleNotifier.instance.setLocale('fr');
                    setState(() => _language = v ?? 'FR');
                  },
                  secondary: const Text('🇫🇷', style: TextStyle(fontSize: 22)),
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          Text(
            s.notifications,
            style: TextStyle(color: AppColors.txMuted(context), fontWeight: FontWeight.w900, letterSpacing: 1.8),
          ),
          const SizedBox(height: 12),
          GlassCard(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(s.pushNotifications, style: const TextStyle(fontWeight: FontWeight.w700)),
              subtitle: Text(s.receiveAlerts, style: TextStyle(color: AppColors.txMuted(context), fontSize: 12)),
              value: _notificationsEnabled,
              onChanged: (v) => setState(() => _notificationsEnabled = v),
              secondary: const Icon(Icons.notifications_outlined, color: AppColors.primary),
            ),
          ),
          const SizedBox(height: 18),
          Text(
            s.about,
            style: TextStyle(color: AppColors.txMuted(context), fontWeight: FontWeight.w900, letterSpacing: 1.8),
          ),
          const SizedBox(height: 12),
          _InfoTile(icon: Icons.info_outline, label: s.appInfo, subtitle: 'ScoutAI v1.0.0'),
          _InfoTile(icon: Icons.description_outlined, label: s.termsAndConditions, onTap: () => Navigator.of(context).pushNamed(AppRoutes.terms)),
          _InfoTile(icon: Icons.privacy_tip_outlined, label: s.privacyPolicy, onTap: () => Navigator.of(context).pushNamed(AppRoutes.privacyPolicy)),
          _InfoTile(icon: Icons.help_outline, label: s.helpAndSupport, onTap: () => Navigator.of(context).pushNamed(AppRoutes.helpSupport)),
          const SizedBox(height: 18),
          FilledButton(
            onPressed: _logout,
            style: FilledButton.styleFrom(backgroundColor: AppColors.danger),
            child: Text(s.logout),
          ),
        ],
      ),
    );
  }
}

class _InfoTile extends StatelessWidget {
  const _InfoTile({required this.icon, required this.label, this.subtitle, this.onTap});

  final IconData icon;
  final String label;
  final String? subtitle;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: GestureDetector(
        onTap: onTap,
        child: GlassCard(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              Container(
                height: 38,
                width: 38,
                decoration: BoxDecoration(
                  color: AppColors.surf2(context),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.bdr(context).withValues(alpha: 0.9)),
                ),
                child: Icon(icon, color: AppColors.primary, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(label, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 15)),
                    if (subtitle != null)
                      Text(subtitle!, style: TextStyle(color: AppColors.txMuted(context), fontSize: 12)),
                  ],
                ),
              ),
              if (onTap != null) Icon(Icons.chevron_right, color: AppColors.txMuted(context)),
            ],
          ),
        ),
      ),
    );
  }
}
