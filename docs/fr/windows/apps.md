# Logiciels courants (Windows 10)

Menu « Logiciels courants » du profil `base` (`catalog/apps/`) : logiciels utiles sur toutes les machines, installés par winget. Leurs réglages sont dans le menu suivant, « Logiciels courants : réglages », qui ne propose un réglage que si son logiciel est choisi. Épingle et raccourci sur le bureau : voir [Intégration au bureau](desktop.md).

Volontairement absents : un outil de fichiers compressés (Windows ouvre déjà les `.zip`), un lecteur multimédia et les autres utilitaires, à ajouter au besoin.

## Discord — `discord`

✔ · installé pour le compte (pas d'admin) · winget `Discord.Discord`

- **Effet** : installe Discord dans `%LOCALAPPDATA%\Discord`. Discord se met ensuite à jour seul, à chaque lancement.
- **Implications** :
  - l'installeur (Squirrel) termine l'installation en arrière-plan puis **ouvre Discord** (fenêtre de connexion) : le setup attend que l'installation soit finie avant de continuer ;
  - à ce premier lancement, Discord tente d'installer **Discord System Helper** (`DiscordSystemHelper.exe`, service exécuté en administrateur) : une **invite UAC** « Discord System Helper », éditeur vérifié Discord Inc., s'affiche pendant le setup. Ce composant, encore expérimental et proposé à une partie des comptes seulement, ne sert qu'à faire fonctionner les raccourcis de Discord (appuyer pour parler, overlay) dans les jeux lancés en administrateur. Répondre **Non** n'empêche rien d'autre ; sans réponse, l'invite se ferme seule au bout de 2 minutes, comme un refus. Discord ne la repropose pas aux lancements suivants. Pour l'installer plus tard : Paramètres utilisateur > Paramètres Windows > System Helper (même endroit pour le désinstaller) ;
  - Discord se lance ensuite **à chaque ouverture de session** (réduit près de l'horloge), sauf si `discord-no-autostart` est coché ;
  - le raccourci posé sur le bureau par l'installeur est retiré, sauf si « Raccourci sur le bureau : Discord » est coché.
- **Revenir en arrière** : Paramètres > Applications > Discord > Désinstaller.

## Pas de lancement à l'ouverture de session — `discord-no-autostart`

○ · proposé si Discord est choisi · entrée de démarrage

- **Effet** : Discord ne se lance plus à l'ouverture de session ; on l'ouvre quand on en a besoin. Ses notifications (messages, appels) n'arrivent donc que lorsqu'il est ouvert.
- **Valeur** : entrée `Discord` de `HKCU\Software\Microsoft\Windows\CurrentVersion\Run`, désactivée comme le fait le Gestionnaire des tâches (onglet Démarrage) : `HKCU\…\Explorer\StartupApproved\Run`, valeur `Discord`, premier octet impair. Discord peut recréer son entrée (réglage « Ouvrir Discord » dans ses paramètres), elle reste désactivée.
- **Revenir en arrière** : Gestionnaire des tâches > Démarrage > Discord > Activer.
