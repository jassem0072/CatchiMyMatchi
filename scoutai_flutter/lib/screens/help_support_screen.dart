import 'package:flutter/material.dart';

import '../services/translations.dart';
import '../theme/app_colors.dart';
import '../widgets/common.dart';

/// Help & Support screen.
class HelpSupportScreen extends StatelessWidget {
  const HelpSupportScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final isFr = s.language == 'LANGUE';
    return GradientScaffold(
      appBar: AppBar(
        title: Text(s.helpAndSupport),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(18, 18, 18, 28),
        children: [
          Text(
            isFr ? 'Comment pouvons-nous vous aider ?' : 'How can we help you?',
            style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 24),
          ),
          const SizedBox(height: 20),
          _HelpTile(
            icon: Icons.videocam,
            title: isFr ? 'Envoyer une vidéo' : 'Upload a Video',
            body: isFr
                ? 'Appuyez sur le bouton + depuis l\'accueil pour envoyer un fichier MP4 ou MOV. La taille maximale est de 2 Go.'
                : 'Tap the + button from the home screen to upload an MP4 or MOV file. Maximum size is 2GB.',
          ),
          _HelpTile(
            icon: Icons.analytics,
            title: isFr ? 'Lancer une analyse' : 'Start an Analysis',
            body: isFr
                ? 'Après l\'envoi, identifiez votre joueur dans la vidéo en appuyant dessus, puis confirmez pour lancer l\'analyse IA.'
                : 'After uploading, identify your player in the video by tapping on them, then confirm to start the AI analysis.',
          ),
          _HelpTile(
            icon: Icons.compare_arrows,
            title: isFr ? 'Comparer des joueurs' : 'Compare Players',
            body: isFr
                ? 'Utilisez le comparateur depuis la barre d\'outils pour sélectionner deux joueurs et comparer leurs statistiques.'
                : 'Use the comparator from the toolbar to select two players and compare their performance stats.',
          ),
          _HelpTile(
            icon: Icons.favorite,
            title: isFr ? 'Favoris (Recruteurs)' : 'Favorites (Scouters)',
            body: isFr
                ? 'En tant que recruteur, parcourez la marketplace et ajoutez des joueurs aux favoris pour suivre leurs performances.'
                : 'As a scouter, browse the marketplace and add players to favorites to follow their performance.',
          ),
          _HelpTile(
            icon: Icons.email_outlined,
            title: isFr ? 'Nous contacter' : 'Contact Us',
            body: isFr
                ? 'Envoyez un email à support@scoutai.app pour toute question ou signalement de problème.'
                : 'Send an email to support@scoutai.app for any questions or to report issues.',
          ),
        ],
      ),
    );
  }
}

class _HelpTile extends StatelessWidget {
  const _HelpTile({required this.icon, required this.title, required this.body});

  final IconData icon;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: GlassCard(
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              height: 40,
              width: 40,
              decoration: BoxDecoration(
                color: AppColors.surf2(context),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.bdr(context).withValues(alpha: 0.9)),
              ),
              child: Icon(icon, color: AppColors.primary, size: 20),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 15)),
                  const SizedBox(height: 6),
                  Text(body, style: TextStyle(color: AppColors.txMuted(context), fontSize: 13, height: 1.4)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
