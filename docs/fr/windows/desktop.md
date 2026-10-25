# Intégration au bureau (Windows 10)

Référence des éléments du catalogue `catalog/desktop/` : barre des tâches, menu Démarrer, raccourcis du bureau. Les notions communes (préférence, stratégie, HKCU, retour arrière) sont expliquées dans [`../how-it-works.md`](../how-it-works.md).

Principe : **chaque logiciel déclare ce qu'il peut offrir** (épingle, raccourci) et l'utilisateur choisit dans les menus du profil. Un menu ne propose que les options des logiciels effectivement choisis (épingler Vivaldi n'apparaît que si Vivaldi est coché).

Légende : **✔** coché par défaut · **○** proposé, décoché par défaut · **session** : effectif à la prochaine ouverture de session (ou au redémarrage de l'Explorateur, fait par la disposition en fin de setup).

## Barre des tâches et menu Démarrer : la disposition

### Barre des tâches et menu Démarrer : disposition — `desktop-layout`

Toujours présent dans le profil `base`, traité **en dernier** (il redémarre l'Explorateur, ce qui rend aussi effectifs les réglages de la barre des tâches appliqués avant lui).

- **Pourquoi ce mécanisme** : Windows 10 n'a plus d'API pour épingler (retirée par Microsoft en 2018 ; seul « désépingler » reste possible par script). La méthode officielle est un fichier `LayoutModification.xml` appliqué par la stratégie de groupe « Start layout ».
- **Déroulement** : le moteur rassemble les épingles (`taskbarPin`) et la disposition du menu Démarrer (`startLayout`) des éléments retenus dans un seul fichier ; il active la stratégie **verrouillée** (`HKCU\Software\Policies\Microsoft\Windows\Explorer` `StartLayoutFile`, `LockedStartLayout` = 1), redémarre l'Explorateur, puis la **déverrouille et la retire** et supprime le fichier. L'Explorateur est arrêté et Windows le relance de lui-même ; s'il ne l'a pas fait au bout de 30 s (constaté une fois pendant qu'un installeur créait ses raccourcis), le setup le lance par une tâche planifiée temporaire, **sans** ses droits administrateur (vérifié en VM en désactivant la relance automatique).
- **Effet** : la barre des tâches contient exactement les épingles choisies, dans l'ordre des menus — celles de Windows (Edge, Store, Courrier) et celles que les installeurs ajoutent d'eux-mêmes (Firefox, Brave, Vivaldi le font) sont retirées.
- **Implications** : les fenêtres de l'Explorateur ouvertes se ferment pendant le setup. L'utilisateur garde ensuite la main : ses changements (épingler, désépingler) sont conservés, y compris après redémarrage (vérifié en VM). Une relance du setup ne réapplique la disposition que si les choix ont changé : son empreinte est mémorisée dans `HKCU\Software\OS-Setup` `DesktopLayout`.
- **Revenir en arrière** : épingler ou désépingler à la main (clic droit). Supprimer la valeur `DesktopLayout` pour que le setup réapplique sa disposition.

### Épingles (menu « Épinglés à la barre des tâches », tout coché)

| Élément | Épingle | Proposé si |
|---|---|---|
| `pin-explorer` | Explorateur de fichiers | toujours |
| `pin-firefox` | Firefox | Firefox est choisi |
| `pin-chrome` | Google Chrome | Chrome est choisi |
| `pin-brave` | Brave | Brave est choisi |
| `pin-vivaldi` | Vivaldi | Vivaldi est choisi |
| `pin-discord` | Discord | Discord est choisi |
| `pin-windows-terminal` | Windows Terminal (application du Store ; menu « Épinglés à la barre des tâches (développement) » du profil `dev`) | Terminal est choisi |

Une épingle désigne le raccourci du menu Démarrer créé par l'installeur (ex. `{{StartMenu}}\Vivaldi.lnk`), ou, pour une application du Store qui n'en a pas, son identifiant AppUserModelID (ex. `Microsoft.WindowsTerminal_8wekyb3d8bbwe!App`). Tout décocher laisse la barre des tâches telle quelle.

### Menu Démarrer : sans vignette — `start-no-tiles`

✔ · menu « Barre des tâches et menu Démarrer »

- **Effet** : le menu Démarrer n'a plus de vignettes (partie droite) : il se réduit à la liste des applications.
- **Implications** : disparaissent aussi les **vignettes de téléchargement** des applications promues (flèche), qui installaient une application au premier clic. On peut épingler ensuite ses propres vignettes.
- **Mécanisme** : partie `DefaultLayoutOverride` du fichier de disposition (voir `desktop-layout`).
- **Revenir en arrière** : clic droit sur une application > « Épingler à l'écran de démarrage ».

## Réglages de la barre des tâches et du menu Démarrer (menu « Barre des tâches et menu Démarrer »)

Préférences HKCU : elles s'appliquent même sur Windows non activé, bien que la page *Personnalisation* soit verrouillée (retour arrière par `regedit` dans ce cas).

| Élément | Défaut | Effet | Valeur | Revenir en arrière |
|---|---|---|---|---|
| `taskbar-search-icon` | ✔ | Zone de recherche réduite à une loupe : place libérée dans la barre des tâches | `HKCU\Software\Microsoft\Windows\CurrentVersion\Search` `SearchboxTaskbarMode` = 1 (0 : masquée, 2 : zone complète) | Clic droit sur la barre des tâches > Rechercher |
| `taskbar-hide-taskview` | ○ | Bouton « Affichage des tâches » masqué (`Win+Tab` reste disponible) | `…\Explorer\Advanced` `ShowTaskViewButton` = 0 | Clic droit sur la barre des tâches |
| `taskbar-hide-people` | ✔ | Bouton « Contacts » masqué (application supprimée par ailleurs) | `…\Explorer\Advanced\People` `PeopleBand` = 0 | Clic droit sur la barre des tâches |
| `taskbar-hide-meetnow` | ✔ | Bouton « Conversation instantanée » (Meet Now, Skype) masqué dans la zone de notification | stratégie utilisateur `HKCU\Software\Microsoft\Windows\CurrentVersion\Policies\Explorer` `HideSCAMeetNow` = 1 | `regedit` : supprimer la valeur |
| `taskbar-hide-ink` | ✔ | Bouton « Espace de travail Windows Ink » masqué (utile seulement avec un stylet) | `HKCU\Software\Microsoft\Windows\CurrentVersion\PenWorkspace` `PenWorkspaceButtonDesiredVisibility` = 0 | Clic droit sur la barre des tâches |
| `tray-show-all` | ○ | Toutes les icônes de la zone de notification visibles (plus de flèche « afficher les icônes cachées ») | `HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer` `EnableAutoTray` = 0 | Paramètres > Personnalisation > Barre des tâches |
| `start-hide-recent` | ○ | Plus de section « Ajoutées récemment » en haut du menu Démarrer | stratégie utilisateur `HKCU\Software\Policies\Microsoft\Windows\Explorer` `HideRecentlyAddedApps` = 1 | `regedit` : supprimer la valeur |
| `desktop-this-pc` | ○ | Icône « Ce PC » sur le bureau | `…\Explorer\HideDesktopIcons\NewStartPanel` `{20D04FE0-3AEA-1069-A2D8-08002B30309D}` = 0 | Paramètres > Personnalisation > Thèmes > Paramètres des icônes du bureau |

### Barre des tâches : masquée automatiquement — `taskbar-autohide`

✔ · menu « Barre des tâches et menu Démarrer »

- **Effet** : la barre des tâches se cache et réapparaît quand la souris touche le bord de l'écran (ou avec la touche Windows). Effet immédiat.
- **Implications** : plus de place pour les fenêtres ; les notifications de la barre (icône qui clignote, ex. cloche de Windows Terminal) ne se voient que si la barre réapparaît — Windows la fait ressortir brièvement quand une application demande l'attention.
- **Mécanisme** : provider `taskbar`, API `SHAppBarMessage` (celle qu'utilise la case de Paramètres), compte courant. L'Explorateur range le réglage dans la valeur binaire `HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\StuckRects3` `Settings` (9ᵉ octet : `03` masquée, `02` visible), qui contient aussi la position et la taille de la barre ; il ne l'écrit qu'en se fermant normalement (fermeture de session, redémarrage). L'écrire directement ne prendrait effet qu'au redémarrage de l'Explorateur, qui la réécrirait en se fermant. Arrêté de force par `desktop-layout`, l'Explorateur perdrait le réglage appliqué juste avant : le setup le rétablit après ce redémarrage (constaté en VM, puis corrigé).
- **Revenir en arrière** : Paramètres > Personnalisation > Barre des tâches > « Masquer automatiquement la barre des tâches en mode Bureau ». Page verrouillée sur Windows non activé : dans PowerShell 7, depuis le dossier du setup, `Import-Module ./src/OSSetup/OSSetup.psd1; Set-OSSetupTaskbarAutoHide -Enabled $false`.

Les autres réglages ci-dessus sont marqués « session » : effectifs au redémarrage de l'Explorateur fait par `desktop-layout`, sinon à la prochaine ouverture de session.

## Raccourcis sur le bureau (menu « Raccourcis sur le bureau », rien de coché)

**Bureau vide par défaut** : chaque navigateur retire le raccourci que son installeur dépose sur le bureau (Firefox et Chrome sur le bureau public, Brave et Vivaldi sur celui du compte) — sauf si son raccourci est demandé dans ce menu. Chrome crée en plus un raccourci sur le bureau **de chaque compte**, au premier démarrage de l'Explorateur de ce compte (mécanisme « Active Setup », rejoué après chaque mise à jour de Chrome) : le setup fusionne dans ses préférences d'installation (`initial_preferences`, mode `merge-json`) les options `do_not_create_desktop_shortcut`, `do_not_create_quick_launch_shortcut` et `do_not_create_taskbar_shortcut` (vérifié en VM : Active Setup rejoué sans recréer le raccourci), puis retire un éventuel raccourci déjà créé. Une mise à jour qui recréerait le raccourci est corrigée à la relance du setup. Le raccourci d'Edge sera traité avec la neutralisation d'Edge (navigateurs).

| Élément | Raccourci | Proposé si |
|---|---|---|
| `desktop-firefox` | `Firefox.lnk` (bureau public, copie du raccourci du menu Démarrer) | Firefox est choisi |
| `desktop-chrome` | `Google Chrome.lnk` (bureau public) | Chrome est choisi |
| `desktop-brave` | `Brave.lnk` (bureau du compte) | Brave est choisi |
| `desktop-vivaldi` | `Vivaldi.lnk` (bureau du compte) | Vivaldi est choisi |
| `desktop-discord` | `Discord.lnk` (bureau du compte) | Discord est choisi |

- **Mécanisme** : provider `shortcut` — copie du raccourci du menu Démarrer créé par l'installeur (même cible, même icône), ou suppression.
- **Revenir en arrière** : créer ou supprimer le raccourci à la main.
