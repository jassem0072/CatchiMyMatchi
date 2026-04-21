import 'package:flutter/material.dart';

import '../app/scoutai_app.dart';
import '../services/translations.dart';
import '../theme/app_colors.dart';
import '../widgets/common.dart';

/// Terms of Use screen shown right after registration.
/// The user must scroll through and accept the terms before proceeding.
class TermsScreen extends StatefulWidget {
  const TermsScreen({super.key});

  @override
  State<TermsScreen> createState() => _TermsScreenState();
}

class _TermsScreenState extends State<TermsScreen> {
  bool _accepted = false;

  void _continue() {
    if (!_accepted) return;
    Navigator.of(context).pushReplacementNamed(AppRoutes.playerHome);
  }

  @override
  Widget build(BuildContext context) {
    return GradientScaffold(
      appBar: AppBar(
        title: Text(S.of(context).termsOfUse),
        automaticallyImplyLeading: false,
      ),
      body: Column(
        children: [
          // Scrollable contract content
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Center(child: AppLogo(size: 56)),
                  const SizedBox(height: 14),
                  const Center(
                    child: Text(
                      'ScoutAI — Terms of Use',
                      style: TextStyle(fontWeight: FontWeight.w900, fontSize: 22),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Center(
                    child: Text(
                      'Last updated: February 2026',
                      style: TextStyle(color: AppColors.textMuted, fontSize: 12),
                    ),
                  ),
                  const SizedBox(height: 20),
                  _sectionTitle('1. Acceptance of Terms'),
                  _paragraph(
                    'By creating an account and using ScoutAI ("the Application"), '
                    'you agree to be bound by these Terms of Use. If you do not agree '
                    'to these terms, do not use the Application.',
                  ),
                  _sectionTitle('2. Description of Service'),
                  _paragraph(
                    'ScoutAI is a sports analytics platform that uses artificial '
                    'intelligence to analyze football match videos, track player '
                    'performance, and provide statistical insights. The service '
                    'includes video upload, AI-powered analysis, player dashboards, '
                    'and scouter marketplace features.',
                  ),
                  _sectionTitle('3. User Accounts'),
                  _paragraph(
                    'You are responsible for maintaining the confidentiality of your '
                    'account credentials. You agree to provide accurate and complete '
                    'information during registration. You must be at least 16 years '
                    'old to create an account.',
                  ),
                  _sectionTitle('4. User Content'),
                  _paragraph(
                    'You retain ownership of videos and content you upload. By '
                    'uploading content, you grant ScoutAI a non-exclusive, worldwide '
                    'license to process, analyze, and store your content solely for '
                    'the purpose of providing the service. You represent that you have '
                    'the right to upload all content and that it does not violate any '
                    'third-party rights.',
                  ),
                  _sectionTitle('5. Privacy & Data'),
                  _paragraph(
                    'We collect and process personal data necessary to provide our '
                    'services, including your name, email, uploaded videos, and '
                    'performance analytics. Your data is stored securely and is not '
                    'sold to third parties. Performance data may be visible to '
                    'scouters browsing the marketplace if your profile is public.',
                  ),
                  _sectionTitle('6. Fair Usage'),
                  _paragraph(
                    'You agree not to: (a) use the service for any unlawful purpose; '
                    '(b) upload content that is offensive, harmful, or violates '
                    'others\' rights; (c) attempt to reverse-engineer the AI models; '
                    '(d) share your account with others; (e) use automated scripts to '
                    'access the service.',
                  ),
                  _sectionTitle('7. Scouter Upgrade & Payments'),
                  _paragraph(
                    'The scouter upgrade is a monthly recurring subscription. All payments are '
                    'processed securely through Stripe. If payment is not received, '
                    'access to scouter features will be suspended. Upon upgrading, any previously uploaded player videos will '
                    'be removed.',
                  ),
                  _sectionTitle('8. Intellectual Property'),
                  _paragraph(
                    'The ScoutAI name, logo, AI models, and all associated '
                    'technology are the property of ScoutAI. You may not copy, '
                    'modify, or distribute any part of the application without '
                    'prior written consent.',
                  ),
                  _sectionTitle('9. Limitation of Liability'),
                  _paragraph(
                    'ScoutAI is provided "as is" without warranties of any kind. '
                    'We are not liable for any indirect, incidental, or '
                    'consequential damages arising from your use of the service. '
                    'AI-generated analytics are for informational purposes only '
                    'and should not be the sole basis for professional decisions.',
                  ),
                  _sectionTitle('10. Termination'),
                  _paragraph(
                    'We reserve the right to suspend or terminate your account at '
                    'any time for violation of these terms. You may delete your '
                    'account at any time through the application settings.',
                  ),
                  _sectionTitle('11. Changes to Terms'),
                  _paragraph(
                    'We may update these terms from time to time. Continued use of '
                    'the application after changes constitutes acceptance of the '
                    'new terms. We will notify users of significant changes via '
                    'email or in-app notification.',
                  ),
                  const SizedBox(height: 12),
                ],
              ),
            ),
          ),

          // Bottom: checkbox + button
          Container(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
            decoration: BoxDecoration(
              color: AppColors.surface.withValues(alpha: 0.97),
              border: Border(
                top: BorderSide(color: Colors.white.withValues(alpha: 0.06)),
              ),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                InkWell(
                  onTap: () => setState(() => _accepted = !_accepted),
                  borderRadius: BorderRadius.circular(10),
                  child: Row(
                    children: [
                      Checkbox(
                        value: _accepted,
                        onChanged: (v) => setState(() => _accepted = v ?? false),
                        activeColor: AppColors.primary,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          S.of(context).acceptTerms,
                          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: _accepted ? _continue : null,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.check_circle_outline, size: 18),
                        const SizedBox(width: 8),
                        Text(S.of(context).acceptAndContinue),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _sectionTitle(String text) {
    return Padding(
      padding: const EdgeInsets.only(top: 18, bottom: 6),
      child: Text(
        text,
        style: const TextStyle(
          fontWeight: FontWeight.w900,
          fontSize: 15,
          color: AppColors.primary,
        ),
      ),
    );
  }

  Widget _paragraph(String text) {
    return Text(
      text,
      style: const TextStyle(
        color: AppColors.textMuted,
        fontSize: 13.5,
        height: 1.6,
      ),
    );
  }
}
