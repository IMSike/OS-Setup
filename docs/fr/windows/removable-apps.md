# Applications et composants supprimables (Windows 10 22H2)

Référence de chaque suppression du catalogue (`catalog/remove/`) : ce que c'est, les implications et comment le récupérer. Les mécanismes communs sont expliqués dans [`../how-it-works.md`](../how-it-works.md).

Inventaire relevé sur Windows 10 22H2 fraîchement installé et sur une machine déjà utilisée. Un élément absent de la machine est considéré comme conforme : le même catalogue sert aux deux.

Légende : **✔** coché par défaut · **○** proposé, décoché par défaut · **✘** à ne pas supprimer. Tout ce qui se supprime est choisi dans un menu, comme tout ce qui s'installe (vérifié au chargement des données).

## Mécanismes

| Type | Provider | Ce qui est fait | Récupérer l'élément |
|---|---|---|---|
| Application du Store | `appx` | **Déprovisionnement** (sinon elle revient pour chaque nouveau compte), puis suppression **pour tous les comptes** — dans cet ordre, sinon Windows refuse (0x80073CFA). Sous PowerShell 7 / Windows 10, le module Appx passe par Windows PowerShell 5.1. | Microsoft Store, ou `winget install --source msstore <nom>` |
| Composant Windows (« capacité ») | `windows-capability` | `Remove-WindowsCapability` ; un redémarrage peut être demandé. | Paramètres > Applications > Fonctionnalités facultatives > Ajouter une fonctionnalité |
| Fonctionnalité Windows | `windows-feature` (`enabled: false`) | `dism /Disable-Feature`. | Panneau de configuration > Programmes > Activer ou désactiver des fonctionnalités Windows |
| Logiciel classique | `win32-uninstall` | Désinstalleur déclaré dans « Programmes et fonctionnalités », lancé sans interaction (MSI : `msiexec /x … /qn`). | Réinstaller le logiciel (winget, site de l'éditeur) |

Les mises à jour majeures de Windows peuvent réinstaller certaines applications : relancer le setup les supprime de nouveau. Avant chaque suppression, l'état d'origine (paquets présents) est enregistré dans `original-values.json`.

Avertissements : un élément dont la suppression efface des données locales le signale quand il est coché (`checkedWarning`), sous le résumé du menu.

---

## Applications préinstallées (menu « Applications préinstallées à supprimer », tout coché)

| Élément | Application (paquet) | Implications |
|---|---|---|
| `remove-cortana` | Cortana (`Microsoft.549981C3F5F10`) | Aucune : abandonnée, et indisponible en français. |
| `remove-weather` | Météo (`Microsoft.BingWeather`) | Plus d'application météo (le navigateur reste). |
| `remove-bing` | Recherche Bing, Actualités (`Microsoft.BingSearch`, `Microsoft.BingNews`) | Aucune ; absentes de l'image de base, arrivées par les mises à jour. |
| `remove-get-help` | Obtenir de l'aide (`Microsoft.GetHelp`) | Les liens « Obtenir de l'aide » de Windows ne mènent plus nulle part. |
| `remove-tips` | Astuces (`Microsoft.Getstarted`) | Aucune. |
| `remove-feedback-hub` | Hub de commentaires (`Microsoft.WindowsFeedbackHub`) | Plus de retour possible vers Microsoft (cohérent avec la confidentialité). |
| `remove-maps` | Cartes (`Microsoft.WindowsMaps`) | Plus de cartes hors ligne. |
| `remove-office-hub` | Office, lanceur et publicité Microsoft 365 (`Microsoft.MicrosoftOfficeHub`) | Aucune : n'est pas Office ; un Office installé n'est pas touché. |
| `remove-onenote-uwp` | OneNote pour Windows 10 (`Microsoft.Office.OneNote`) | Version abandonnée. **Avertissement** : notes non synchronisées effacées. Le OneNote d'Office n'est pas touché. |
| `remove-solitaire` | Solitaire (`Microsoft.MicrosoftSolitaireCollection`) | Aucune. |
| `remove-3d-viewer` | Visionneuse 3D (`Microsoft.Microsoft3DViewer`) | Plus d'ouverture directe des fichiers 3D. |
| `remove-paint-3d` | Paint 3D (`Microsoft.MSPaint`) | Le Paint classique (`mspaint.exe`) reste. |
| `remove-mixed-reality` | Portail de réalité mixte (`Microsoft.MixedReality.Portal`) | Inutile sans casque de réalité mixte. |
| `remove-people` | Contacts (`Microsoft.People`) | Plus de carnet d'adresses Windows (utilisé par Courrier, supprimé aussi). |
| `remove-skype` | Skype (`Microsoft.SkypeApp`) | Service arrêté par Microsoft. |
| `remove-wallet` | Portefeuille (`Microsoft.Wallet`) | Aucune. |
| `remove-your-phone` | Mobile connecté, expérience multi-appareils (`Microsoft.YourPhone`, `MicrosoftWindows.CrossDevice`) | Plus de liaison avec un téléphone (SMS, notifications, photos). |
| `remove-mail-calendar` | Courrier et Calendrier (`microsoft.windowscommunicationsapps`) | Abandonnés : plus de synchronisation depuis fin 2024. **Avertissement** : comptes et données locales effacés. |
| `remove-new-outlook` | Nouvel Outlook pour Windows (`Microsoft.OutlookForWindows`) | Remplaçant de Courrier, installé par les mises à jour. Les comptes tiers (Gmail, IMAP…) y passent par le cloud de Microsoft. L'Outlook d'Office (« classique ») n'est pas touché. |
| `remove-groove` | Groove Musique (`Microsoft.ZuneMusic`) | Lecteur audio par défaut : les fichiers audio s'ouvrent ensuite avec le Lecteur Windows Media (conservé). |
| `remove-movies-tv` | Films et TV (`Microsoft.ZuneVideo`) | Lecteur vidéo par défaut : idem, Lecteur Windows Media. |
| `remove-dev-home` | Dev Home (`Microsoft.Windows.DevHome`) | Abandonné par Microsoft. |
| `remove-onedrive` | OneDrive (logiciel classique) | Désinstallation, puis stratégie `HKLM\SOFTWARE\Policies\Microsoft\Windows\OneDrive` `DisableFileSyncNGSC` = 1 : OneDrive ne se réinstalle pas pour les nouveaux comptes et disparaît de l'Explorateur. **Avertissement** : les fichiers déjà synchronisés restent dans le dossier OneDrive ; ceux qui n'étaient qu'en ligne ne sont plus accessibles depuis l'Explorateur (toujours sur onedrive.com). Réinstaller : supprimer la stratégie, puis `winget install Microsoft.OneDrive`. |

## Applications utiles (menu « Applications utiles à supprimer », rien de coché)

| Élément | Application (paquet) | Implications |
|---|---|---|
| `remove-sticky-notes` | Pense-bêtes (`Microsoft.MicrosoftStickyNotes`) | **Avertissement** : notes non synchronisées effacées. |
| `remove-alarms` | Alarmes et horloge (`Microsoft.WindowsAlarms`) | Plus de minuteur, chronomètre ni alarme. |
| `remove-camera` | Caméra (`Microsoft.WindowsCamera`) | Plus d'application pour la webcam (les logiciels de visio ne sont pas concernés). |
| `remove-sound-recorder` | Enregistreur vocal (`Microsoft.WindowsSoundRecorder`) | Les enregistrements déjà faits restent dans Documents. |
| `remove-calculator` | Calculatrice (`Microsoft.WindowsCalculator`) | Plus de calculatrice. |
| `remove-screen-sketch` | Capture d'écran et croquis (`Microsoft.ScreenSketch`) | **Avertissement** : `Win+Maj+S` n'ouvre plus l'outil d'annotation. L'Outil Capture reste. |
| `remove-photos` | Photos (`Microsoft.Windows.Photos`) | **Avertissement** : plus de visionneuse d'images par défaut (Paint, ou une visionneuse installée par un profil). |

## Xbox (menu « Xbox à supprimer », rien de coché)

À trancher avec un futur profil jeu.

| Élément | Application (paquets) | Implications |
|---|---|---|
| `remove-xbox-app` | Application Xbox (`Microsoft.XboxApp`) | Plus d'accès au Game Pass PC depuis cette application. |
| `remove-game-bar` | Xbox Game Bar et superpositions (`Microsoft.XboxGamingOverlay`, `Microsoft.XboxGameOverlay`, `Microsoft.XboxSpeechToTextOverlay`) | **Avertissement** : `Win+G` (captures et enregistrements de jeu) ne fonctionne plus. |
| `remove-xbox-live` | Composants Xbox Live (`Microsoft.Xbox.TCUI`, `Microsoft.XboxIdentityProvider`) | **Avertissement** : certains jeux (Store, Game Pass, jeux Microsoft) ne peuvent plus se connecter. |

## Composants Windows (menu « Composants Windows à retirer »)

| Élément | Défaut | Composant | Implications |
|---|---|---|---|
| `remove-internet-explorer` | ✔ | Internet Explorer 11 (capacité `Browser.InternetExplorer`) | Retiré par Microsoft depuis 2023 (il redirige vers Edge). Le moteur de rendu utilisé par d'anciennes applications reste dans Windows. |
| `remove-powershell-v2` | ✔ | Windows PowerShell 2.0 (fonctionnalité `MicrosoftWindowsPowerShellV2Root`) | Moteur obsolète qui permet de contourner l'antivirus (AMSI) et la journalisation de PowerShell ; retiré par Microsoft des versions récentes. PowerShell 5.1 et 7 ne sont pas concernés. |
| `remove-steps-recorder` | ✔ | Enregistreur d'actions (`App.StepsRecorder`) | Enregistrait clics et captures d'écran pour un support technique ; abandonné par Microsoft. |
| `remove-wordpad` | ✔ | WordPad (`Microsoft.Windows.WordPad`) | Abandonné (retiré de Windows 11 24H2) ; les `.rtf` s'ouvrent avec un traitement de texte installé. |
| `remove-powershell-ise` | ✔ | PowerShell ISE (`Microsoft.Windows.PowerShell.ISE`) | Ancien éditeur de scripts de PowerShell 5.1, sans prise en charge de PowerShell 7 ; remplacé par VS Code. |
| `remove-math-input` | ○ | Panneau de saisie mathématique (`MathRecognizer`) | Saisie de formules au stylet, rarement utilisée. |
| `remove-hello-face` | ✔ | Windows Hello : reconnaissance faciale (`Hello.Face.*`, le numéro dépend de la version de Windows) | Inutile sans caméra infrarouge compatible. **Avertissement** : plus de connexion par le visage. |
| `remove-quick-assist` | ✔ | Assistance rapide (`App.Support.QuickAssist`) | Plus d'aide à distance intégrée (version Store disponible). |
| `remove-fax-scan` | ○ | Télécopie et numérisation Windows (`Print.Fax.Scan`) | **Avertissement** : certains scanners ne fonctionnent qu'avec cet outil. |
| `remove-print-management` | ✔ | Console de gestion de l'impression (`Print.Management.Console`) | Outil d'administration de serveurs d'impression. |
| `remove-work-folders` | ✔ | Dossiers de travail (fonctionnalité `WorkFolders-Client`) | Synchronisation de fichiers d'entreprise, inutile chez un particulier. |
| `remove-smb-direct` | ✔ | SMB Direct (fonctionnalité `SmbDirect`) | Partage de fichiers sur cartes réseau RDMA (serveurs). |
| `remove-xps-printer` | ✔ | Imprimante Microsoft XPS Document Writer (fonctionnalité `Printing-XPSServices-Features`) | Format XPS abandonné ; « Microsoft Print to PDF » reste. |

## À ne jamais supprimer (✘)

| Élément | Raison |
|---|---|
| App Installer (`Microsoft.DesktopAppInstaller`) et sa source winget | **winget** : le setup en dépend |
| Microsoft Store, service d'achat | Mises à jour d'App Installer et de dépendances |
| Extensions HEIF, VP9, WebM, WebP | Codecs (images, vidéos) |
| Pack de langue fr-FR | Langue de l'interface |
| **Edge**, WebView2 | Windows 10 : désinstallation non prise en charge (`NoRemove` = 1), réinstallé par les mises à jour, des parties de Windows l'ouvrent ; WebView2 sert à de nombreuses applications. Edge sera **neutralisé** (lancement au démarrage, navigateur par défaut, épinglage, stratégies) avec la configuration des navigateurs ; désinstallation complète à étudier pour Windows 11. |
| Lecteur Windows Media | Seul lecteur restant si Groove et Films et TV sont supprimés, en attendant un lecteur choisi dans un profil |
| Paint, Bloc-notes, Outil Capture, Bureau à distance, Microsoft Print to PDF, client OpenSSH, langues, .NET | Utiles ou nécessaires au système |
| Applications système (écran de verrouillage, Démarrer, Sécurité Windows…) | Composants de Windows |
| Microsoft Update Health Tools, mises à jour (KB) | Composants de Windows Update |
| Panneaux de pilotes (NVIDIA, Realtek…) | Spécifiques au matériel |
| **Windows PowerShell 5.1** | Fait partie de Windows (pas une fonctionnalité facultative) ; utilisé par des composants système et par le bootstrap du setup. PowerShell 7 sera le défaut du profil `dev`. |

## Autres constats

- **Applications sponsorisées** auto-installées (Candy Crush, etc.) : empêchées par `sponsored-apps-off` (voir [`settings.md`](settings.md)). Le menu Démarrer garde des **vignettes de téléchargement** (flèche) pour les applications promues de la disposition par défaut ; elles s'installent au premier clic. À retirer avec la disposition du menu Démarrer (intégration au bureau).
- **Lancement au démarrage** (inventaire VM) : OneDrive (supprimé ci-dessus), Edge (« démarrage rapide », après sa première ouverture : traité avec les navigateurs), Sécurité Windows (✘, état de l'antivirus), mise à jour d'Edge (✘ tant qu'Edge reste). Les logiciels installés par le setup recevront un réglage « ne pas lancer au démarrage » quand c'est pertinent.
