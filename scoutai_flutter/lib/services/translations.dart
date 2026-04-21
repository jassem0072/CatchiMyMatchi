/// All app strings in EN and FR.

/// Usage: S.of(context).home  or  S.current.home

import 'package:flutter/widgets.dart';

import 'locale_notifier.dart';



class S {

  S._(this._lang);



  final String _lang;

  bool get _fr => _lang == 'fr';



  /// Convenient factory from BuildContext

  static S of(BuildContext context) =>

      S._(LocaleNotifier.instance.value.languageCode);



  /// Access without context (uses current locale)

  static S get current => S._(LocaleNotifier.instance.value.languageCode);



  // ─── Bottom Nav ────────────────────────────────────────

  String get home => _fr ? 'Accueil' : 'Home';

  String get team => _fr ? 'Équipe' : 'Team';

  String get challenges => _fr ? 'Défis' : 'Challenges';

  String get profile => _fr ? 'Profil' : 'Profile';

  String get explore => _fr ? 'Explorer' : 'Explore';

  String get teams => _fr ? 'Équipes' : 'Teams';

  String get uploads => _fr ? 'Envois' : 'Uploads';



  // ─── Settings ──────────────────────────────────────────

  String get settings => _fr ? 'Paramètres' : 'Settings';

  String get appearance => _fr ? 'APPARENCE' : 'APPEARANCE';

  String get darkMode => _fr ? 'Mode sombre' : 'Dark Mode';

  String get useDarkTheme => _fr ? 'Utiliser le thème sombre' : 'Use dark theme';

  String get language => _fr ? 'LANGUE' : 'LANGUAGE';

  String get notifications => _fr ? 'NOTIFICATIONS' : 'NOTIFICATIONS';

  String get pushNotifications => _fr ? 'Notifications push' : 'Push Notifications';

  String get receiveAlerts => _fr

      ? 'Recevoir des alertes sur les analyses et mises à jour'

      : 'Receive alerts about analyses and updates';

  String get about => _fr ? 'À PROPOS' : 'ABOUT';

  String get appInfo => _fr ? 'Info App' : 'App Info';

  String get termsAndConditions =>

      _fr ? 'Conditions générales' : 'Terms and Conditions';

  String get privacyPolicy =>

      _fr ? 'Politique de confidentialité' : 'Privacy Policy';

  String get helpAndSupport => _fr ? 'Aide & Support' : 'Help & Support';

  String get logout => _fr ? 'Déconnexion' : 'Logout';



  // ─── Auth ──────────────────────────────────────────────

  String get login => _fr ? 'Connexion' : 'Login';

  String get register => _fr ? "S'inscrire" : 'Register';

  String get email => _fr ? 'Email' : 'Email';

  String get password => _fr ? 'Mot de passe' : 'Password';

  String get forgotPassword =>

      _fr ? 'Mot de passe oublié ?' : 'Forgot password?';

  String get orContinueWith =>

      _fr ? 'OU CONTINUER AVEC' : 'OR CONTINUE WITH';

  String get noAccount =>

      _fr ? "Pas de compte ?" : "Don't have an account?";

  String get signUp => _fr ? "S'inscrire" : 'Sign up';

  String get alreadyHaveAccount =>

      _fr ? 'Déjà un compte ?' : 'Already have an account?';

  String get signIn => _fr ? 'Se connecter' : 'Sign in';

  String get fullName => _fr ? 'Nom complet' : 'Full Name';

  String get confirmPassword =>

      _fr ? 'Confirmer le mot de passe' : 'Confirm Password';

  String get iAmA => _fr ? 'Je suis un' : 'I am a';

  String get player => _fr ? 'Joueur' : 'Player';

  String get scouter => _fr ? 'Recruteur' : 'Scouter';

  String get resetPassword =>

      _fr ? 'Réinitialiser le mot de passe' : 'Reset Password';

  String get sendResetLink =>

      _fr ? 'Envoyer le lien' : 'Send Reset Link';

  String get welcomeBackScout =>

      _fr ? 'Bon retour, Scout' : 'Welcome Back, Scout';

  String get emailAddress =>

      _fr ? 'ADRESSE EMAIL' : 'EMAIL ADDRESS';

  String get securePassword =>

      _fr ? 'MOT DE PASSE SÉCURISÉ' : 'SECURE PASSWORD';

  String get rememberMe => _fr ? 'Se souvenir de moi' : 'Remember me';

  String get signInDashboard =>

      _fr ? 'SE CONNECTER' : 'SIGN IN TO DASHBOARD';

  String get continueWithGoogle =>

      _fr ? 'Continuer avec Google' : 'Continue with Google';

  String get newScout =>

      _fr ? 'Nouveau scout ? ' : 'New scout on the team? ';

  String get registerHub =>

      _fr ? "Centre d'inscription" : 'Register Hub';

  String get enterEmailPassword =>

      _fr ? "Entrez l'email et le mot de passe" : 'Enter email and password';

  String get platformSubtitle =>

      _fr ? "Plateforme d'analyse de match professionnelle" : 'Professional Match Analysis Platform';

  String get createAccount =>

      _fr ? 'Créer un compte' : 'Create Account';

  String get joinAcademy =>

      _fr ? "Rejoindre l'Académie" : 'Join the Academy';

  String get startAnalyzing =>

      _fr ? 'Commencez à analyser des matchs avec ' : 'Start analyzing matches with ';

  String get aiPerformance => _fr ? "IA\nperformance" : "AI\nperformance";

  String get trackingDot => _fr ? ' tracking.' : ' tracking.';

  String get nation => _fr ? 'Nation' : 'Nation';

  String get enterName =>

      _fr ? 'Entrez votre nom' : 'Enter your name';

  String get enterEmail =>

      _fr ? 'Entrez votre email' : 'Enter your email';

  String get passwordMinChars =>

      _fr ? 'Le mot de passe doit contenir au moins 6 caractères' : 'Password must be at least 6 characters';

  String get passwordsNoMatch =>

      _fr ? 'Les mots de passe ne correspondent pas' : 'Passwords do not match';

  String get repeatPassword =>

      _fr ? 'Répéter le mot de passe' : 'Repeat password';

  String get minChars =>

      _fr ? 'Min. 6 caractères' : 'Min. 6 characters';

  String get logIn => _fr ? 'Se connecter' : 'Log In';



  // ─── Player Home ───────────────────────────────────────

  String get welcomeBack => _fr ? 'Bon retour,' : 'Welcome back,';

  String get recentMatches => _fr ? 'MATCHS RÉCENTS' : 'RECENT MATCHES';

  String get noVideos =>

      _fr ? 'Aucune vidéo pour le moment' : 'No videos yet';

  String get uploadFirstVideo =>

      _fr ? 'Envoyez votre première vidéo !' : 'Upload your first video!';

  String get analyzed => _fr ? 'Analysé' : 'Analyzed';

  String get pending => _fr ? 'En attente' : 'Pending';

  String get yourStats => _fr ? 'VOS STATS' : 'YOUR STATS';

  String get totalDistance => _fr ? 'Distance totale' : 'Total Distance';

  String get maxSpeed => _fr ? 'Vitesse max' : 'Max Speed';

  String get totalSprints => _fr ? 'Sprints totaux' : 'Total Sprints';

  String get matchesAnalyzed => _fr ? 'Matchs analysés' : 'Matches Analyzed';

  String get recentActivity => _fr ? 'ACTIVITÉ RÉCENTE' : 'RECENT ACTIVITY';

  String get noVideosYetTap =>

      _fr ? 'Aucune vidéo envoyée. Appuyez sur + pour envoyer votre première !' : 'No videos uploaded yet. Tap + to upload your first video!';

  String get tapViewResults => _fr ? 'Voir les résultats' : 'Tap to view results';

  String get tapStartAnalysis => _fr ? 'Lancer l\'analyse' : 'Tap to start analysis';

  String get processing => _fr ? 'En cours' : 'Processing';



  // ─── Challenges ────────────────────────────────────────

  String get challengesTitle => _fr ? 'DÉFIS' : 'CHALLENGES';



  // ─── Notifications ─────────────────────────────────────

  String get notificationsTitle => _fr ? 'Notifications' : 'Notifications';

  String get noNotifications =>

      _fr ? 'Aucune notification' : 'No notifications';

  String get allCaughtUp => _fr

      ? "Vous êtes à jour ! Les notifications sur vos analyses et activités apparaîtront ici."

      : "You're all caught up! Notifications about your analyses and activity will appear here.";

  String get markAllRead => _fr ? 'Tout marquer comme lu' : 'Mark all as read';



  // ─── Upload ────────────────────────────────────────────

  String get uploadVideo => _fr ? 'Envoyer une vidéo' : 'Upload Video';

  String get selectFile =>

      _fr ? 'Sélectionner un fichier' : 'Select a file';

  String get upload => _fr ? 'Envoyer' : 'Upload';

  String get uploading => _fr ? 'Envoi en cours...' : 'Uploading...';

  String get uploadMatchVideo =>

      _fr ? 'Envoyer la vidéo du match' : 'Upload Match Video';

  String get newMatchAnalysis =>

      _fr ? 'Nouvelle analyse de match' : 'New Match Analysis';

  String get uploadInstructions => _fr

      ? 'Envoyez un fichier MP4 ou MOV de haute qualité pour les meilleurs\nrésultats de tracking IA.'

      : 'Upload a high-quality MP4 or MOV file for the best\nAI tracking results.';

  String get selectMatchVideo =>

      _fr ? 'Sélectionner la vidéo du match' : 'Select Match Video';

  String get tapToUpload => _fr

      ? 'Appuyez ici pour envoyer des fichiers MP4 ou MOV\ndepuis votre galerie (Max 2 Go)'

      : 'Tap here to upload MP4 or MOV files\nfrom your gallery (Max 2GB)';

  String get browseFiles => _fr ? 'Parcourir fichiers' : 'Browse Files';

  String get currentUpload => _fr ? 'Envoi actuel' : 'Current Upload';

  String get noFileSelected =>

      _fr ? 'Aucun fichier sélectionné' : 'No file selected';

  String get chooseVideo =>

      _fr ? 'Choisir une vidéo à envoyer' : 'Choose a video to upload';

  String get uploadedSuccessfully =>

      _fr ? 'Envoyé avec succès' : 'Uploaded successfully';

  String get uploadingVideo =>

      _fr ? 'Envoi de la vidéo...' : 'Uploading video...';

  String get ready => _fr ? 'Prêt' : 'Ready';

  String get encryptedTransfer =>

      _fr ? 'Transfert chiffré actif' : 'Encrypted transfer active';

  String get continueToAnalysis =>

      _fr ? "Continuer vers l'analyse" : 'Continue to Analysis';

  String get buttonActivateWhenDone => _fr

      ? "Le bouton s'activera une fois l'envoi terminé à 100%"

      : 'Button will activate once upload is 100% complete';

  String get unsupportedVideo => _fr

      ? 'Type de vidéo non supporté. Utilisez MP4/MOV/WebM.'

      : 'Unsupported video type. Please use MP4/MOV/WebM.';



  // ─── Analysis ──────────────────────────────────────────

  String get analysisDetails =>

      _fr ? "Détails de l'analyse" : 'Analysis Details';

  String get overview => _fr ? 'Aperçu' : 'Overview';

  String get heatmap => _fr ? 'Carte de chaleur' : 'Heatmap';

  String get speed => _fr ? 'Vitesse' : 'Speed';

  String get myVideos => _fr ? 'Mes vidéos' : 'My Videos';

  String get speedOverTime =>

      _fr ? 'Vitesse au fil du temps' : 'Speed Over Time';

  String get topSpeed => _fr ? 'Vitesse max' : 'Top Speed';

  String get avgSpeed => _fr ? 'Vitesse moy.' : 'Avg Speed';

  String get distance => _fr ? 'Distance' : 'Distance';

  String get sprints => _fr ? 'Sprints' : 'Sprints';

  String get aiInsights => _fr ? 'Analyse IA' : 'AI Insights';

  String get analysisResults =>

      _fr ? "Résultats de l'analyse" : 'Analysis Results';

  String get aiAnalysisComplete =>

      _fr ? 'ANALYSE IA TERMINÉE' : 'AI ANALYSIS COMPLETE';

  String get accelPeaks => _fr ? 'Pics accél.' : 'Accel Peaks';

  String get positions => _fr ? 'Positions' : 'Positions';

  String get fieldHeatmap =>

      _fr ? 'Carte de chaleur du terrain' : 'Field Heatmap';

  String get noHeatmapData =>

      _fr ? 'Pas de données de heatmap' : 'No heatmap data';

  String get speedTimeline =>

      _fr ? 'Chronologie de vitesse' : 'Speed Timeline';

  String get notEnoughData =>

      _fr ? 'Pas assez de données pour le graphique' : 'Not enough data for speed chart';

  String get peakVelocity => _fr ? 'VITESSE MAX' : 'PEAK VELOCITY';

  String get averageVelocity => _fr ? 'VITESSE MOYENNE' : 'AVERAGE VELOCITY';

  String get noVideosUploaded =>

      _fr ? 'Aucune vidéo envoyée.' : 'No videos uploaded yet.';

  String get notAnalyzed => _fr ? 'Non analysé' : 'Not analyzed';

  String get aiAnalysis => _fr ? 'Analyse IA' : 'AI Analysis';

  String get analyzing => _fr ? 'Analyse...' : 'Analyzing...';

  String get aiProcessing =>

      _fr ? 'L\'IA traite votre vidéo' : 'AI is processing your video';

  String get mayTakeFewMinutes =>

      _fr ? 'Cela peut prendre quelques minutes' : 'This may take a few minutes';

  String get analysisComplete =>

      _fr ? 'Analyse terminée !' : 'Analysis Complete!';

  String get aiFinished =>

      _fr ? 'L\'IA a fini de traiter votre vidéo' : 'AI has finished processing your video';

  String get viewResults =>

      _fr ? "Voir les résultats de l'analyse" : 'View Analysis Results';

  String get goBack => _fr ? 'Retour' : 'Go Back';



  // ─── Comparator ────────────────────────────────────────

  String get compareTitle =>

      _fr ? 'Comparer les joueurs' : 'Compare Players';

  String get playerComparator =>

      _fr ? 'Comparateur de joueurs' : 'Player Comparator';

  String get selectTwoPlayers => _fr

      ? 'Sélectionnez deux joueurs et comparez leurs statistiques.'

      : 'Select two players and compare their stats.';

  String get player1 => _fr ? 'Joueur 1' : 'Player 1';

  String get player2 => _fr ? 'Joueur 2' : 'Player 2';

  String get compare => _fr ? 'Comparer' : 'Compare';

  String get aiPerformanceAnalysis =>

      _fr ? 'ANALYSE DE PERFORMANCE IA' : 'AI PERFORMANCE ANALYSIS';

  String get analyzedVideos => _fr ? 'Vidéos analysées' : 'Analyzed Videos';

  String get selectPlayer => _fr ? 'Sélectionner' : 'Select';

  String get change => _fr ? 'Changer' : 'Change';

  String get selectAPlayer =>

      _fr ? 'Sélectionner un joueur' : 'Select a Player';

  String get searchByName =>

      _fr ? 'Rechercher par nom ou position…' : 'Search by name or position…';

  String get noPlayersFound =>

      _fr ? 'Aucun joueur trouvé' : 'No players found';

  String get aiScoutingInsights =>

      _fr ? 'ANALYSE IA DE SCOUTING' : 'AI SCOUTING INSIGHTS';

  String get perVideoBreakdown =>

      _fr ? 'DÉTAIL PAR VIDÉO' : 'PER-VIDEO BREAKDOWN';



  // ─── Profile ───────────────────────────────────────────

  String get editProfile => _fr ? 'Modifier le profil' : 'Edit Profile';

  String get position => _fr ? 'Position' : 'Position';

  String get nationality => _fr ? 'Nationalité' : 'Nationality';

  String get role => _fr ? 'Rôle' : 'Role';

  String get videosAnalyzed => _fr ? 'Vidéos\nAnalysées' : 'Videos\nAnalyzed';

  String get accountSettings =>

      _fr ? 'PARAMÈTRES DU COMPTE' : 'ACCOUNT SETTINGS';

  String get securityPrivacy =>

      _fr ? 'Sécurité & Confidentialité' : 'Security & Privacy';

  String get subscription => _fr ? 'ABONNEMENT' : 'SUBSCRIPTION';

  String get scouterPlanActive =>

      _fr ? 'Forfait Recruteur actif' : 'Scouter Plan Active';

  String get billingHistory =>

      _fr ? 'Historique de facturation' : 'Billing History';

  String get upgradeToScouter =>

      _fr ? 'Passer Recruteur' : 'Upgrade to Scouter';

  String get oneTimePayment =>

      _fr ? '40\$ paiement unique' : '\$40 one-time payment';

  String get upgradedSuccess => _fr

      ? '🎉 Passage en Recruteur réussi !'

      : '🎉 Upgraded to Scouter successfully!';

  String get unsupportedImage => _fr

      ? 'Type d\'image non supporté. Utilisez PNG/JPG/WebP/GIF.'

      : 'Unsupported image type. Please use PNG/JPG/WebP/GIF.';

  String get cardNumber => _fr ? 'Numéro de carte' : 'Card Number';

  String get expiry => _fr ? 'Expiration' : 'Expiry';

  String get oneTimeNoRecurring => _fr

      ? 'Paiement unique · Aucun frais récurrent'

      : 'One-time payment · No recurring charges';

  String get browseDiscoverPlayers =>

      _fr ? 'Parcourir et découvrir des joueurs' : 'Browse and discover players';

  String get saveToFavorites =>

      _fr ? 'Sauvegarder des joueurs en favoris' : 'Save players to favorites';

  String get accessAnalytics => _fr

      ? 'Accéder aux analyses détaillées des joueurs'

      : 'Access detailed player analytics';

  String get videosWillBeRemoved => _fr

      ? 'Vos vidéos envoyées seront supprimées'

      : 'Your uploaded videos will be removed';

  String get payAmount =>

      _fr ? 'Payer 40,00\$' : 'Pay \$40.00';

  String get processingPayment =>

      _fr ? 'Traitement...' : 'Processing...';

  String get paymentNotCompleted => _fr

      ? 'Le paiement n\'a pas abouti. Veuillez réessayer.'

      : 'Payment was not completed. Please try again.';

  String get changePassword =>

      _fr ? 'Changer le mot de passe' : 'Change Password';

  String get currentPassword =>

      _fr ? 'Mot de passe actuel' : 'Current Password';

  String get newPassword =>

      _fr ? 'Nouveau mot de passe' : 'New Password';

  String get deleteAccount =>

      _fr ? 'Supprimer le compte' : 'Delete Account';

  String get deleteAccountWarning => _fr

      ? 'Cette action est irréversible. Toutes vos données seront supprimées.'

      : 'This action is irreversible. All your data will be deleted.';

  String get noBillingHistory => _fr

      ? 'Aucun historique de facturation'

      : 'No billing history';

  String get noBillingYet => _fr

      ? 'Vos transactions apparaîtront ici.'

      : 'Your transactions will appear here.';

  String get displayName => _fr ? 'Nom d\'affichage' : 'Display Name';

  String get saved => _fr ? 'Enregistré !' : 'Saved!';



  // ─── Scouter ───────────────────────────────────────────

  String get marketplace => _fr ? 'Marché' : 'Marketplace';

  String get following => _fr ? 'Suivis' : 'Following';

  String get searchPlayers =>

      _fr ? 'Rechercher des joueurs' : 'Search players or matches';

  String get noFavoritesYet =>

      _fr ? 'Aucun favori pour le moment' : 'No favorites yet';

  String get browseMaketplaceHint => _fr

      ? 'Parcourez le Marché pour découvrir des joueurs et les ajouter en favoris.'

      : 'Browse the Marketplace to discover players and add them to your favorites.';

  String get removeFromFavorites =>

      _fr ? 'Retirer des favoris' : 'Remove from favorites';

  String get addToFavorites =>

      _fr ? 'Ajouter aux favoris' : 'Add to favorites';

  String get searchByNamePositionNation => _fr

      ? 'Rechercher par nom, position ou nation...'

      : 'Search by name, position, or nation...';

  String get playersWillAppear => _fr

      ? 'Les joueurs apparaîtront ici une fois inscrits et ayant envoyé des vidéos.'

      : 'Players will appear here once they sign up and upload videos.';



  // ─── Team ──────────────────────────────────────────────

  String get myTeam => _fr ? 'MON ÉQUIPE' : 'MY TEAM';

  String get searchInvite =>

      _fr ? 'Rechercher des joueurs à inviter...' : 'Search players to invite...';

  String get noTeamMembers =>

      _fr ? 'Aucun membre pour le moment' : 'No team members yet';

  String get inviteTeammates => _fr

      ? 'Invitez des coéquipiers pour comparer vos stats et progresser ensemble.'

      : 'Invite teammates to compare stats and improve together.';

  String get suggestedPlayers =>

      _fr ? 'JOUEURS SUGGÉRÉS' : 'SUGGESTED PLAYERS';

  String get suggestedWillAppear => _fr

      ? 'Des joueurs suggérés apparaîtront ici en fonction de vos matchs.'

      : 'Suggested players will appear here based on your matches.';



  // ─── Team (extended) ──────────────────────────────────

  String get createTeam => _fr ? 'Créer une équipe' : 'Create Team';

  String get teamName => _fr ? 'Nom de l\'équipe' : 'Team Name';

  String get enterTeamName => _fr ? 'Entrez le nom de l\'équipe' : 'Enter team name';

  String get create => _fr ? 'Créer' : 'Create';

  String get myTeams => _fr ? 'MES ÉQUIPES' : 'MY TEAMS';

  String get members => _fr ? 'membres' : 'members';

  String get invitePlayers => _fr ? 'Inviter des joueurs' : 'Invite Players';

  String get invite => _fr ? 'Inviter' : 'Invite';

  String get inviteSent => _fr ? 'Invitation envoyée !' : 'Invitation sent!';

  String get teamCreated => _fr ? 'Équipe créée !' : 'Team created!';

  String get deleteTeam => _fr ? 'Supprimer l\'équipe' : 'Delete Team';

  String get leaveTeam => _fr ? 'Quitter l\'équipe' : 'Leave Team';

  String get teamMembers => _fr ? 'MEMBRES' : 'MEMBERS';

  String get owner => _fr ? 'Propriétaire' : 'Owner';

  String get pendingInvites => _fr ? 'EN ATTENTE' : 'PENDING';

  String get noTeamsYet => _fr ? 'Aucune équipe pour le moment' : 'No teams yet';

  String get createTeamHint => _fr

      ? 'Créez une équipe et invitez des joueurs pour les taguer dans vos vidéos.'

      : 'Create a team and invite players to tag them in your videos.';

  String get searchPlayersToInvite =>

      _fr ? 'Rechercher des joueurs...' : 'Search players...';

  String get teamInvitation => _fr ? 'Invitation d\'équipe' : 'Team Invitation';

  String get accept => _fr ? 'Accepter' : 'Accept';

  String get decline => _fr ? 'Décliner' : 'Decline';

  String get invitedYou => _fr ? 'vous a invité à rejoindre' : 'invited you to join';

  String get remove => _fr ? 'Retirer' : 'Remove';



  // ─── Video Tagging ──────────────────────────────────────

  String get tagTeammates => _fr ? 'Taguer des coéquipiers' : 'Tag Teammates';

  String get tagTeammatesHint => _fr

      ? 'Sélectionnez les coéquipiers présents dans cette vidéo.'

      : 'Select teammates who appear in this video.';

  String get videoVisibility => _fr ? 'Visibilité' : 'Visibility';

  String get publicVideo => _fr ? 'Publique' : 'Public';

  String get privateVideo => _fr ? 'Privée' : 'Private';

  String get publicHint => _fr

      ? 'Visible par les recruteurs pour analyse'

      : 'Visible to scouts for analysis';

  String get privateHint => _fr

      ? 'Visible uniquement par vous et les joueurs tagués'

      : 'Only visible to you and tagged players';

  String get skipTagging => _fr ? 'Passer' : 'Skip';

  String get saveAndContinue => _fr ? 'Enregistrer et continuer' : 'Save & Continue';

  String get noTeammates => _fr

      ? 'Aucun coéquipier. Créez une équipe d\'abord !'

      : 'No teammates. Create a team first!';



  // ─── Player Detail ─────────────────────────────────────

  String get performance => _fr ? 'PERFORMANCE' : 'PERFORMANCE';

  String get videos => _fr ? 'Vidéos' : 'Videos';

  String get matchVideos => _fr ? 'VIDÉOS DE MATCH' : 'MATCH VIDEOS';

  String get noDataAvailable =>

      _fr ? 'Aucune donnée disponible.' : 'No data available.';



  // ─── Identify Player ──────────────────────────────────

  String get identifyPlayer =>

      _fr ? 'Identifier le joueur' : 'Identify Player';

  String get resetSelection =>

      _fr ? 'Réinitialiser la sélection' : 'Reset selection';

  String get scrubInstruction => _fr

      ? 'Naviguez jusqu\'à la bonne image et appuyez sur le joueur à\nanalyser.'

      : 'Scrub to the right frame and tap on the player to\nanalyze.';

  String get playerLocked => _fr ? 'JOUEUR VERROUILLÉ' : 'PLAYER LOCKED';

  String get tapOnPlayer =>

      _fr ? 'APPUYEZ SUR UN JOUEUR' : 'TAP ON A PLAYER';

  String get confirmAnalyze => _fr

      ? 'Confirmer la sélection & Analyser'

      : 'Confirm selection & Analyze';

  String get tapPlayerToEnable => _fr

      ? 'Appuyez sur un joueur dans la vidéo pour lancer l\'analyse'

      : 'Tap on a player in the video to enable analysis';



  // ─── Forgot Password ──────────────────────────────────

  String get resetYourPassword =>

      _fr ? 'Réinitialiser votre mot de passe' : 'Reset your password';

  String get resetInstructions => _fr

      ? 'Entrez votre email, demandez un jeton de réinitialisation, puis entrez le nouveau mot de passe.'

      : 'Enter your email, request a reset token, then enter new password.';

  String get requestResetToken =>

      _fr ? 'Demander un jeton' : 'Request reset token';

  String get token => _fr ? 'JETON' : 'TOKEN';

  String get pasteToken =>

      _fr ? 'Collez le jeton ici' : 'Paste token here';

  String get newPasswordLabel =>

      _fr ? 'NOUVEAU MOT DE PASSE' : 'NEW PASSWORD';



  // ─── Generic ───────────────────────────────────────────

  String get loading => _fr ? 'Chargement...' : 'Loading...';

  String get error => _fr ? 'Erreur' : 'Error';

  String get complete => _fr ? 'Terminé' : 'Complete';

  String get available => _fr ? 'disponible(s)' : 'available';



  // ─── Terms ─────────────────────────────────────────────

  String get termsOfUse => _fr ? "Conditions d'utilisation" : 'Terms of Use';

  String get acceptTerms => _fr

      ? "J'ai lu et j'accepte les conditions d'utilisation et la politique de confidentialité"

      : 'I have read and accept the Terms of Use and Privacy Policy';

  String get acceptAndContinue => _fr ? 'Accepter & Continuer' : 'Accept & Continue';

  String get retry => _fr ? 'Réessayer' : 'Retry';

  String get save => _fr ? 'Enregistrer' : 'Save';

  String get cancel => _fr ? 'Annuler' : 'Cancel';

  String get ok => _fr ? "D'accord" : 'OK';

  String get yes => _fr ? 'Oui' : 'Yes';

  String get no => _fr ? 'Non' : 'No';

  String get done => _fr ? 'Terminé' : 'Done';

}

