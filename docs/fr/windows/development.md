# Développement (Windows 10)

Profil `dev` (`profiles/dev.json`, éléments dans `catalog/dev/`) : il étend le profil `base`. Ses logiciels sont proposés dans les menus, dans cet ordre : « Outils de développement », « Avec WSL », « Éditeur de code », « Extensions VS Code », « JavaScript / TypeScript », « Agents et terminal », « Logiciels de développement », « Comptes (étapes manuelles guidées) », « Extensions GitHub CLI » et « Épinglés à la barre des tâches (développement) ». Un menu ne propose que ce qui dépend d'éléments cochés auparavant (ex. extensions VS Code sans VS Code). Leurs réglages (`items` du profil) sont appliqués automatiquement quand le logiciel concerné est choisi, et ignorés sinon. Les notions communes (fusion JSON, sauvegarde, retour arrière, étapes manuelles) sont expliquées dans [`../how-it-works.md`](../how-it-works.md).

Légende : **✔** coché par défaut · **○** proposé, décoché par défaut · **auto** : appliqué quand ses dépendances sont choisies · **technique** : ajouté automatiquement comme dépendance, jamais proposé.

Paquets winget « portables » (fnm, pnpm, lazygit, rtk) : winget les décompresse dans `%LOCALAPPDATA%\Microsoft\WinGet\Packages` et crée la commande dans `%LOCALAPPDATA%\Microsoft\WinGet\Links`, ajouté au PATH du compte ; ils se désinstallent par `winget uninstall --id <Id>`.

## Dossier des projets — `dev-root`

auto · dossier

- **Effet** : crée le dossier racine des projets, `{{DevRoot}}` (par défaut `Documents\repo`, modifiable avec « Personnaliser les emplacements ? » ou le fichier de réponses).
- **Revenir en arrière** : supprimer le dossier s'il est vide.

## Git — `git`

✔ · admin · winget `Git.Git` (pour toute la machine)

- **Effet** : installe Git pour Windows, avec Git Bash et Git Credential Manager (connexion HTTPS aux forges, jeton rangé dans le gestionnaire d'identifiants de Windows).
- **Revenir en arrière** : Paramètres > Applications > Git > Désinstaller.

### Configuration de Git — `git-config`, `git-identity`, `git-vscode`

auto (avec `git`) · provider `git-config` : `git config --global <clé> <valeur>`, dans `%USERPROFILE%\.gitconfig`

Clé par clé : les autres réglages de l'utilisateur sont conservés, et une clé modifiée sur la machine est remise à la valeur du dépôt à la relance du setup. Ancienne valeur de chaque clé enregistrée dans les valeurs d'origine.

| Élément | Clé | Valeur | Effet (défaut de Git entre parenthèses) |
|---|---|---|---|
| `git-config` | `init.defaultBranch` | `main` | Branche initiale d'un nouveau dépôt (`master`) |
| | `core.autocrlf` | `input` | Fins de ligne : CRLF converties en LF à l'enregistrement, rien converti à l'extraction (`true` posé par l'installeur de Git pour Windows : LF → CRLF à l'extraction). Les fichiers qui doivent rester en CRLF se déclarent dans le `.gitattributes` du projet |
| | `core.longpaths` | `true` | Chemins de plus de 260 caractères acceptés (dossiers `node_modules` profonds) |
| | `pull.rebase` | `true` | `git pull` rejoue les commits locaux sur la branche distante au lieu de créer un commit de fusion |
| | `rebase.autoStash` | `true` | Les modifications non commitées sont mises de côté puis restaurées autour d'un rebase (`pull` compris) |
| | `push.autoSetupRemote` | `true` | Premier `git push` d'une nouvelle branche : branche distante créée et suivie, sans `--set-upstream` |
| | `fetch.prune` | `true` | Les branches distantes supprimées disparaissent aussi en local à chaque `fetch`/`pull` |
| | `merge.conflictStyle` | `zdiff3` | Conflit affiché avec la version d'origine commune en plus des deux côtés (`merge`) |
| `git-identity` | `user.name`, `user.email` | demandés à l'exécution | Auteur des commits. **Informations personnelles** : jamais dans le dépôt, demandées par l'étape « Informations personnelles » de l'assistant ; non renseignées, l'élément est ignoré (signalé dans le plan) |
| `git-vscode` (avec `vscode`) | `core.editor` | `code --wait` | Messages de commit, rebase interactif : édités dans VS Code |
| | `diff.tool`, `difftool.vscode.cmd` | `vscode`, `code --wait --diff "$LOCAL" "$REMOTE"` | `git difftool` ouvre la comparaison dans VS Code |
| | `merge.tool`, `mergetool.vscode.cmd` | `vscode`, `code --wait --merge "$REMOTE" "$LOCAL" "$BASE" "$MERGED"` | `git mergetool` ouvre l'éditeur de fusion à trois volets de VS Code |

- **Revenir en arrière** : `git config --global --unset <clé>` (ou modifier `%USERPROFILE%\.gitconfig`).

## GitHub CLI — `gh`, `gh-auth`, `gh-dash`

`gh` : ✔ · admin · winget `GitHub.cli` (MSI, pour toute la machine)

- **Effet** : commande `gh` : dépôts, demandes de fusion (pull requests), tickets, actions GitHub depuis le terminal.
- **Revenir en arrière** : Paramètres > Applications > GitHub CLI > Désinstaller.

`gh-auth` : ✔ · menu « Comptes (étapes manuelles guidées) » · provider `manual`

- **Effet** : connexion de `gh` à github.com en **HTTPS** (`gh auth login --web --git-protocol https`), dans la console du setup : gh affiche un code à usage unique et ouvre la page de connexion (par l'Explorateur, donc dans le navigateur sans droits administrateur). Si gh propose de connecter Git avec ce compte, répondre oui : `git push` vers GitHub n'aura plus besoin d'identifiants.
- **Vérification** : `gh auth status --hostname github.com`. « Passer » laisse l'étape à faire plus tard ; sans surveillance, elle est signalée sans rien lancer.
- **Implications** : jeton rangé dans le gestionnaire d'identifiants de Windows. Pas de clé SSH (HTTPS retenu : rien à générer ni à déclarer sur GitHub, fonctionne derrière les pare-feu qui bloquent le port 22).
- **Revenir en arrière** : `gh auth logout`.

`gh-dash` : ✔ (si `gh-auth` coché) · menu « Extensions GitHub CLI » · provider `gh-extension`

- **Effet** : `gh dash`, tableau de bord des pull requests et tickets dans le terminal ([dlvhdr/gh-dash](https://github.com/dlvhdr/gh-dash)).
- **Implications** : `gh extension install` exige que gh soit connecté : ignoré si l'étape `gh-auth` a été passée.
- **Revenir en arrière** : `gh extension remove dlvhdr/gh-dash`.

`gh-dash-config` : auto (avec `gh-dash`) · provider `file` (copie de `dotfiles/gh-dash/config.yml` vers `%USERPROFILE%\.config\gh-dash\config.yml`)

- **Effet** : sections du tableau de bord — PR (« My Pull Requests », « Needs My Review », « Involved », « All »), issues (créées, assignées, impliqué) et notifications par motif ; aperçu ouvert à droite (45 %), 20 éléments par section, colonnes et largeurs, actualisation toutes les 30 min, pas de confirmation pour quitter.
- **Implications** : le fichier est remplacé en entier (copie, l'existant est sauvegardé) : une personnalisation faite à la main est écrasée à la relance du setup ; la reporter dans le dépôt. « All » (`is:open`, ajoutée aux sections par défaut de gh-dash) liste toutes les PR ouvertes du dépôt quand `gh dash` est lancé dans un dépôt : le filtrage intelligent (`smartFilteringAtLaunch`) ajoute alors `repo:<dépôt>` à chaque section (touche `t` pour l'enlever). Lancé hors d'un dépôt, cette section porte sur tout GitHub et n'est pas utile.
- **Revenir en arrière** : supprimer `%USERPROFILE%\.config\gh-dash\config.yml` (gh-dash reprend ses valeurs par défaut).

## lazygit — `lazygit`

✔ · winget `JesseDuffield.lazygit` (portable)

- **Effet** : commande `lazygit`, interface Git plein écran dans le terminal (indexation par ligne, rebase interactif, résolution de conflits). Icônes avec la Nerd Font.
- **Revenir en arrière** : `winget uninstall --id JesseDuffield.lazygit`.

## PowerShell 7 — `pwsh`

✔ · admin · winget `Microsoft.PowerShell` (MSI, pour toute la machine) · suppression de la version du Store (`Microsoft.PowerShell`)

- **Effet** : installe PowerShell 7 dans `%ProgramFiles%\PowerShell\7`, à côté de Windows PowerShell 5.1 (qui reste : composant de Windows). Si la version du Store (MSIX) est présente, elle est supprimée une fois le MSI en place. Pas épinglé à la barre des tâches : on l'utilise depuis Windows Terminal.
- **Implications** :
  - le paquet par défaut est un MSIX, non installable pour toute la machine sous Windows 10 : le MSI est forcé ;
  - la version du Store est mise à jour par le Store, qui **ferme de force tous ses `pwsh.exe`** à chaque mise à jour : shells de Windows Terminal et des volets herdr, agents lancés dedans, travail en cours compris. D'où sa suppression, ses réglages et son profil (`Documents\PowerShell`) étant partagés avec le MSI ;
  - le MSI se met à jour par winget (`winget upgrade Microsoft.PowerShell`) ou Microsoft Update, sans fermer les sessions ouvertes ;
  - présence vérifiée par le fichier `pwsh.exe` du MSI : winget rattache la version du Store au même identifiant.
- **Revenir en arrière** : Paramètres > Applications > PowerShell 7 > Désinstaller ; la version du Store se réinstalle depuis le Microsoft Store.

### Profil PowerShell 7 — `pwsh-profile`

auto (avec `pwsh`) · fichier gabarit

- **Effet** : déploie `Documents\PowerShell\Microsoft.PowerShell_profile.ps1` depuis `dotfiles/powershell/` : variable `DEV_ROOT`, commande `dev` (aller au dossier des projets), si fnm est installé son intégration (version de Node.js du projet, voir `node-lts`), et une session Playwright CLI propre à chaque terminal (`PLAYWRIGHT_CLI_SESSION` = `term-<n° du processus>`, voir `playwright-cli`).
- **Implications** : le fichier existant est sauvegardé puis remplacé ; une modification faite sur la machine est écrasée à la relance du setup (modifier le dépôt).
- **Revenir en arrière** : restaurer la sauvegarde (`state\backups\…`) ou supprimer le fichier.

## Windows Terminal — `windows-terminal`

✔ · pour le compte · winget `Microsoft.WindowsTerminal`

- **Effet** : installe Windows Terminal (onglets, volets, rendu moderne), mis à jour ensuite par winget.
- **Implications** : application du Store (MSIX), installée pour le compte : l'installation pour toute la machine n'est pas prise en charge sous Windows 10. Sous Windows 10, Terminal ne peut pas devenir le terminal par défaut de Windows (Windows 11 seulement) : un script lancé par double-clic s'ouvre encore dans la console classique.
- **Revenir en arrière** : Paramètres > Applications > Windows Terminal > Désinstaller.

### Réglages de Windows Terminal

Fichier `%LOCALAPPDATA%\Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState\settings.json`, **fusionné** (`merge-json`) : seules les clés gérées par le dépôt sont écrites, Terminal complète lui-même le reste (profils détectés, etc.) et les autres réglages faits sur la machine sont conservés. Fonctionne avant le premier lancement de Terminal (le fichier est alors créé avec les seules clés gérées). Fichier existant sauvegardé avant modification.

| Élément | Appliqué si | Effet | Valeur (`dotfiles/windows-terminal/`) |
|---|---|---|---|
| `terminal-settings` | Terminal choisi | Apparence et comportement, détaillés ci-dessous | `settings.json` |
| `terminal-pwsh-default` | Terminal et PowerShell 7 choisis | Un nouvel onglet ou une nouvelle fenêtre ouvre PowerShell 7 | `pwsh-default.json` : `defaultProfile` = `{574e775e-4f2a-5b96-ac1e-a2962a402336}` (identifiant fixe du profil PowerShell 7 détecté par Terminal) |
| `terminal-font` | Terminal et la police choisis | Police JetBrainsMono Nerd Font dans tous les profils | `font.json` : `profiles.defaults.font.face` |

Détail de `terminal-settings` (défaut de Terminal entre parenthèses) :

| Clé | Valeur | Effet |
|---|---|---|
| `theme` | `dark` (celui de Windows) | Fenêtre et onglets en thème sombre |
| `launchMode` | `maximized` (120 × 30 caractères) | Fenêtre agrandie à l'ouverture |
| `firstWindowPreference` | `persistedLayoutAndContent` (nouvel onglet) | À la réouverture, les onglets, volets et leur contenu affiché sont restaurés (les programmes qui y tournaient ne sont pas relancés). Ancien nom `persistedWindowLayout`, que Terminal renomme lui-même : le dépôt utilise le nouveau pour rester conforme à la relance |
| `copyOnSelect` | `true` (`false`) | Sélectionner du texte le copie, sans `Ctrl+C` |
| `keybindings` | `Ctrl+C` copier, `Ctrl+V` coller, `Alt+Maj+D` dupliquer le volet (même liste) | Raccourcis que Terminal écrit dans son fichier à son premier lancement (ils ne font pas partie de ses valeurs par défaut depuis la version 1.21). Le setup crée le fichier avant ce premier lancement : sans cette liste, `Ctrl+V` n'était pas un raccourci de Terminal et était transmis tel quel au programme (Claude Code ne collait pas le texte ; `Ctrl+Maj+V` fonctionnait). La liste remplace celle d'un fichier existant (sauvegardé avant) |
| `disabledProfileSources` | `Windows.Terminal.Azure` (aucun) | Profil Azure Cloud Shell retiré de la liste ; Windows PowerShell 5.1 et l'Invite de commandes restent |
| `profiles.defaults.font.size` | `8` (12) | Taille de police, pour tous les profils |
| `profiles.defaults.useAcrylic`, `opacity` | `true`, `80` (pas de transparence) | Fond transparent et flouté (effet acrylique) : 80 laisse bien voir ce qui est derrière la fenêtre. Le flou n'est pas réglable, seule l'opacité l'est. Sous Windows 10, la transparence n'est possible qu'avec l'effet acrylique ; la transparence sans flou (`useAcrylic` = `false`) n'existe que sous Windows 11 (à proposer avec la prise en charge de Windows 11). Essai en direct : Ctrl+Maj+molette dans le terminal |
| `compatibility.enableUnfocusedAcrylic` | `true` (`false`) | L'effet acrylique reste quand la fenêtre n'est pas active (sinon le fond redevient opaque) |
| `profiles.defaults.colorScheme` | `One Half Dark` (Campbell) | Jeu de couleurs fourni avec Terminal |
| `profiles.defaults.padding` | `1` (8) | Marge intérieure de 1 pixel autour du texte |
| `profiles.defaults.bellStyle` | `taskbar` (son) | Le caractère « cloche » ne fait plus de son : l'icône clignote dans la barre des tâches (utile pour voir qu'un programme, ex. un agent, attend une réponse) |
| `profiles.defaults.historySize` | `20000` (9 001) | Lignes conservées dans l'historique de défilement |

- **Revenir en arrière** : Terminal > Paramètres (ou `Ctrl+,`), ou retirer la clé de `settings.json`. Un réglage modifié sur la machine est remis à la valeur du dépôt à la relance du setup (seules les clés ci-dessus sont concernées).

## Police JetBrainsMono Nerd Font — `nerd-font`

✔ · admin · winget `DEVCOM.JetBrainsMonoNerdFont`

- **Effet** : installe pour toute la machine la police JetBrains Mono complétée des icônes [Nerd Fonts](https://www.nerdfonts.com/) (Git, dossiers, langages, flèches de barre d'invite), affichées par lazygit, herdr ou une invite de commande enrichie. Seule Nerd Font disponible dans winget ; utilisable dans Terminal, VS Code et tout logiciel à police fixe.
- **Implications** : 96 fichiers de police dans `C:\Windows\Fonts`. Trois familles : « JetBrainsMono Nerd Font » (icônes à largeur double, pour les terminaux), « … Nerd Font Mono » (icônes à largeur simple), « … Nerd Font Propo » (proportionnelle) ; Windows les affiche sous les noms courts « JetBrainsMono NF », « NFM », « NFP ».
- **Revenir en arrière** : Paramètres > Applications > JetBrainsMono Nerd Font > Désinstaller.

## Éditeurs de code — `vscode`, `cursor`

Menu « Éditeurs de code », les deux cochés : on peut garder l'un, l'autre ou les deux. Cursor est dérivé de VS Code : il reçoit les **mêmes réglages** (mêmes fichiers de `dotfiles/vscode/`), plus quelques réglages qui lui sont propres.

`vscode` : ✔ · pour le compte · winget `Microsoft.VisualStudioCode`

- **Effet** : installe l'éditeur VS Code dans le profil de l'utilisateur, mis à jour par lui-même.
- **Revenir en arrière** : Paramètres > Applications > Microsoft Visual Studio Code > Désinstaller.

`cursor` : ✔ · pour le compte · winget `Anysphere.Cursor`

- **Effet** : installe l'éditeur Cursor (VS Code avec agent et complétion intégrés) dans le profil de l'utilisateur, mis à jour par lui-même ; commande `cursor`. Distinct de Cursor CLI (`cursor-agent`, menu « Agents et terminal »).
- **Implications** : compte Cursor demandé au premier lancement. Ses extensions viennent d'[Open VSX](https://open-vsx.org/) et non du Marketplace de Microsoft.
- **Revenir en arrière** : Paramètres > Applications > Cursor > Désinstaller.

### Réglages des éditeurs

Fusion JSON (provider `file`, mode `merge-json`) dans `%APPDATA%\Code\User\settings.json` (VS Code) et `%APPDATA%\Cursor\User\settings.json` (Cursor) : seules les clés listées sont imposées, les autres réglages de l'utilisateur sont conservés ; le fichier existant est sauvegardé. Ces fichiers acceptent les commentaires, mais une fusion les retire (le fichier est réécrit).

| Élément (VS Code / Cursor) | Condition | Réglages (fichier de `dotfiles/vscode/`) | Effet (valeur par défaut) |
|---|---|---|---|
| `vscode-settings` / `cursor-settings` | éditeur choisi | `editor.formatOnSave` : `true` (`false`) ; `editor.codeActionsOnSave` : `source.organizeImports` et `source.fixAll` à `always` | À chaque enregistrement : mise en forme, imports triés et inutilisés retirés, corrections automatiques (ESLint compris) |
| | | `editor.detectIndentation` : `false` (`true`) ; `editor.insertSpaces` : `false` (`true`) | Indentation par tabulations partout, sans deviner d'après le fichier (un projet peut l'imposer autrement dans son `.vscode/settings.json` ou `.editorconfig` avec l'extension EditorConfig) |
| | | `editor.minimap.enabled` : `false` (`true`) ; `workbench.tree.indent` : `20` (8) | Pas de minimap à droite ; arborescence de l'explorateur plus indentée |
| | | `argv.json` : `enable-crash-reporter` : `false` (`true`), dans `%USERPROFILE%\.vscode\` / `%USERPROFILE%\.cursor\` | Aucun rapport de plantage envoyé (pris en compte au redémarrage de l'éditeur) |
| `vscode-prettier` / `cursor-prettier` | extension Prettier choisie | `editor.defaultFormatter` : `esbenp.prettier-vscode` ; `prettier.*` (`prettier.json`) | Prettier formate par défaut. Style appliqué **seulement aux projets sans configuration Prettier** (`.prettierrc`…) : tabulations de largeur 4, sans point-virgule, guillemets simples (JSX compris), lignes de 120 caractères, guillemets des clés d'objet cohérents, indentation de `<script>`/`<style>` dans Vue ; fichiers TS, JS, TSX, JSX et JSON |
| `vscode-terminal-pwsh` / `cursor-terminal-pwsh` | PowerShell 7 choisi | `terminal.integrated.defaultProfile.windows` : `PowerShell` (`PowerShell`, déjà) | Le terminal intégré ouvre le profil « PowerShell », que l'éditeur fait pointer vers PowerShell 7 quand il est installé (Windows PowerShell 5.1 sinon) : imposé pour que le choix reste explicite, comme dans Windows Terminal |
| `vscode-terminal-font` / `cursor-terminal-font` | police Nerd Font choisie | `terminal.integrated.fontFamily` : `JetBrainsMono Nerd Font` (police de l'éditeur) | Icônes de lazygit, herdr, d'une invite enrichie affichées dans le terminal intégré |
| `vscode-wsl` / `cursor-wsl` | WSL choisi | `security.allowedUNCHosts` : `["wsl.localhost"]` (vide) | Ouvrir un fichier d'une distribution WSL (`\\wsl.localhost\…`) sans avertissement de sécurité. Remplace la liste existante |

Réglages propres à Cursor (`cursor-settings`, fichier `dotfiles/cursor/settings.json`) :

| Réglage | Valeur (défaut entre parenthèses si connu) | Effet |
|---|---|---|
| `workbench.colorTheme` | `Cursor Dark High Contrast` | Thème sombre à contraste élevé |
| `window.autoDetectColorScheme` | `false` | Le thème ne suit pas le mode clair/sombre de Windows |
| `window.commandCenter` | `true` | Barre de recherche et de commandes au centre de la barre de titre |
| `crashReporting.enabled` | `off` | Aucun rapport de plantage envoyé |
| `cursor.cpp.enablePartialAccepts` | `true` (`false`) | Une suggestion de complétion (Tab) peut être acceptée mot par mot (`Ctrl+→`) |
| `cursor.composer.usageSummaryDisplay` | `always` | Consommation (requêtes, jetons) affichée après chaque réponse de l'agent |

Volontairement absents : `css.validate`/`scss.validate` à `false` (désactiveraient la vérification CSS dans tous les projets : un projet Tailwind les désactive dans son propre `.vscode/settings.json`, ou utilise l'extension Tailwind CSS IntelliSense), `javascript.format.*` (sans effet quand Prettier formate), `json.schemas` vide, `cursor.general.disableHttp2` (contournement d'un proxy qui casse HTTP/2, inutile sur un réseau normal).

- **Revenir en arrière** : retirer les clés du `settings.json` (Paramètres de l'éditeur > icône « Ouvrir les paramètres (JSON) »), ou restaurer la sauvegarde du setup.

### Extensions — `vscode-eslint`, `vscode-prettier`, `cursor-*`

✔ · menus « Extensions VS Code » et « Extensions Cursor » · provider `vscode-extension` (`code --install-extension <id>` ou `cursor --install-extension <id>`, pour le compte, dans `%USERPROFILE%\.vscode\extensions` ou `%USERPROFILE%\.cursor\extensions`)

| Élément | Extension | Effet |
|---|---|---|
| `vscode-eslint`, `cursor-eslint` | `dbaeumer.vscode-eslint` | Erreurs ESLint du projet affichées dans l'éditeur (utilise l'ESLint installé dans le projet) |
| `vscode-prettier`, `cursor-prettier` | `esbenp.prettier-vscode` | Mise en forme par Prettier (utilise le Prettier et la configuration du projet) ; avec ses réglages (ci-dessus) |
| `cursor-remote-wsl` (avec WSL) | `anysphere.remote-wsl` | Ouvrir un dossier d'une distribution WSL : l'éditeur travaille dans Linux (terminal, outils, extensions) |
| `cursor-remote-ssh` | `anysphere.remote-ssh` | Travailler sur une machine distante par SSH |
| `cursor-remote-containers` (avec Docker Desktop) | `anysphere.remote-containers` | Ouvrir un projet dans un conteneur de développement (`.devcontainer`) |

- **Implications** : l'éditeur les met ensuite à jour lui-même. Les extensions « remote » de Cursor sont celles de son éditeur (Anysphere), équivalentes à celles de Microsoft pour VS Code (non installées ici).
- **Revenir en arrière** : Extensions > Désinstaller, ou `code --uninstall-extension <id>` (`cursor --uninstall-extension <id>`).

## Node.js et TypeScript — `fnm`, `node-lts`, `pnpm`, `typescript-global`

`fnm` : technique (avec `node-lts`) · winget `Schniz.fnm` (portable)

- **Effet** : [fnm](https://github.com/Schniz/fnm), gestionnaire de versions de Node.js : plusieurs versions installées côte à côte (dans `%APPDATA%\fnm`), chaque projet utilisant celle qu'il demande. Retenu plutôt que nvm-windows : plus rapide, multiplateforme (même outil sous Fedora), lit `.nvmrc` et `.node-version`, change de version automatiquement en entrant dans un dossier.

`node-lts` : ✔ · menu « JavaScript / TypeScript » · provider `fnm-node`

- **Effet** : installe la dernière version LTS de Node.js (avec npm) et en fait la version par défaut (`fnm install --lts`, `fnm default lts-latest`). Le dossier de cette version par défaut (`%APPDATA%\fnm\aliases\default`) est ajouté au PATH du compte : `node` et `npm` fonctionnent partout (Git Bash, donc Claude Code ; invite de commandes ; applications). Dans PowerShell 7, le profil (`pwsh-profile`) active l'intégration de fnm : en entrant dans un projet, la version de son `.nvmrc` ou `.node-version` est utilisée (fnm propose de l'installer si elle manque).
- **Implications** : une nouvelle LTS n'est pas installée automatiquement : `fnm install --lts` puis `fnm default lts-latest`. Les paquets npm globaux sont propres à chaque version de Node.js.
- **Revenir en arrière** : `fnm uninstall <version>`, retirer le dossier du PATH du compte, `winget uninstall --id Schniz.fnm`.

`pnpm` : ✔ · winget `pnpm.pnpm` (portable)

- **Effet** : gestionnaire de paquets pnpm (dépendances partagées entre projets, installations plus rapides), en exécutable autonome : indépendant de la version de Node.js. npm reste disponible avec Node.js.
- **Revenir en arrière** : `winget uninstall --id pnpm.pnpm`.

`typescript-global` : ○ · provider `npm-global` (`npm install --global typescript`)

- **Effet** : commande `tsc` disponible hors de tout projet (essais rapides, scripts).
- **Implications** : décoché par défaut parce que chaque projet déclare sa propre version de TypeScript (`devDependencies`) et l'utilise via `npx tsc` ou ses scripts : un `tsc` global peut différer de celle du projet et masquer un oubli. Installé pour la version de Node.js par défaut seulement.
- **Revenir en arrière** : `npm uninstall --global typescript`.

## Agents et terminal — `claude-code`, `rtk`, `rtk-claude`, `cursor-cli`, `herdr`

Menu « Agents et terminal », tout coché. Claude Code, Cursor CLI et herdr s'installent par le **script officiel** de leur éditeur (provider `install-script`, `irm <url> | iex` dans Windows PowerShell) : c'est la méthode recommandée, avec mises à jour automatiques. Les scripts ont été relus avant leur ajout au catalogue ; ils s'installent dans le profil du compte, sans droits administrateur.

| Élément | Installation | Commande | Revenir en arrière |
|---|---|---|---|
| `claude-code` (dépend de Git : Claude Code utilise Git Bash) | script `https://claude.ai/install.ps1` : `%USERPROFILE%\.local\bin\claude.exe`. Le script n'ajoute pas ce dossier au PATH : le setup le fait (PATH du compte) | `claude` | `claude uninstall` ou supprimer `%USERPROFILE%\.local\bin\claude.exe` et `%USERPROFILE%\.claude` |
| `rtk` | winget `rtk-ai.rtk` (portable), avec `vcredist` | `rtk` | `winget uninstall --id rtk-ai.rtk` |
| `cursor-cli` (dépend de Git) | script `https://cursor.com/install?win32=true` : `%LOCALAPPDATA%\cursor-agent`, ajouté au PATH du compte | `cursor-agent` ou `agent` | supprimer `%LOCALAPPDATA%\cursor-agent` et l'entrée du PATH |
| `herdr` | script `https://herdr.dev/install.ps1` (version stable) : `%USERPROFILE%\.herdr`, dossier de la version ajouté au PATH du compte | `herdr` | supprimer `%USERPROFILE%\.herdr` et l'entrée du PATH |

- **Claude Code** : installation et réglages de base (ci-dessous). La configuration complète (skills, plugins, MCP, emplacement des mémoires, reprise des données d'une installation existante) n'est pas encore prise en charge.
- **rtk** ([rtk-ai/rtk](https://github.com/rtk-ai/rtk)) : réécrit les commandes lancées par les agents pour en résumer la sortie (moins de jetons consommés).
- **`rtk-claude`** (auto, avec `rtk` et `claude-code`, provider `rtk-init`) : `rtk init --global --auto-patch` ajoute le crochet `PreToolUse` (`rtk hook claude`, sur l'outil Bash) dans `%USERPROFILE%\.claude\settings.json`, crée `RTK.md` et sa référence `@RTK.md` dans `%USERPROFILE%\.claude\CLAUDE.md`. Vérification : `rtk init --show`. rtk demande d'abord s'il peut envoyer des statistiques d'usage anonymes ; sans réponse enregistrée, la question bloquerait le setup : le refus est enregistré (`rtk telemetry disable`), modifiable avec `rtk telemetry enable`. Revenir en arrière : `rtk init --global --uninstall`.
- **herdr** ([herdrdev/herdr](https://github.com/herdrdev/herdr)) : réglages et plugin ci-dessous.

### Playwright CLI — `playwright-cli`, `playwright-skill-claude`, `playwright-skill-agents`, `playwright-chrome`, `playwright-msedge`, `playwright-chromium`, `playwright-firefox`

`playwright-cli` : ✔ · menu « Agents et terminal » (si Node.js choisi) · provider `npm-global` (`@playwright/cli`)

- **Effet** : commande `playwright-cli` ([microsoft/playwright-cli](https://github.com/microsoft/playwright-cli)) avec laquelle **tous les agents** pilotent un navigateur (ouvrir une page, cliquer, remplir, capture d'écran, requêtes réseau…). Remplace le serveur MCP Playwright : rien à configurer dans chaque agent, et moins de jetons consommés (pas de schémas d'outils ni d'arbre de la page injectés dans la conversation).
- **Isolation entre agents** (vérifiée en VM) : chaque **session nommée** (`playwright-cli -s=<nom> …`, ou variable `PLAYWRIGHT_CLI_SESSION` pour tout un agent) a son propre navigateur, avec un profil **en mémoire** (cookies, stockage, onglets propres, perdus à la fermeture) ; deux dossiers différents, deux worktrees d'un même dépôt compris, ont chacun leur navigateur. Deux agents lancés dans le même dossier sans nom de session partageraient la session `default` (mêmes onglets), et la skill ne leur dit pas d'en choisir un : le profil PowerShell (`pwsh-profile`) donne donc à **chaque terminal** (fenêtre, onglet, volet herdr, terminal de l'éditeur) sa propre session, dont héritent les agents qui y sont lancés. Reste le cas de sous-agents d'un même agent travaillant en parallèle (même terminal) : non couvert pour l'instant. Le MCP, lui, utilisait par défaut un profil persistant qu'une seule instance peut ouvrir à la fois.
- **Implications** : sans interface par défaut (`open --headed` pour voir le navigateur) ; une session sans interface se ferme après 1 h sans commande. `playwright-cli list` liste les sessions, `close-all` les ferme.
- **Revenir en arrière** : `npm uninstall --global @playwright/cli`.

`playwright-skill-claude` (auto, avec Claude Code) et `playwright-skill-agents` (auto, avec Cursor CLI) · provider `playwright-cli`

- **Effet** : `playwright-cli install --skills --global` installe la skill qui apprend la commande à Claude Code (`%USERPROFILE%\.claude\skills\playwright-cli`) ; `--skills=agents` l'installe pour les autres agents (`%USERPROFILE%\.agents\skills\playwright-cli`, dossier commun aux agents qui suivent la convention « Agent Skills »).
- **Implications** : la prise en compte de `~/.agents/skills` par Cursor CLI n'est pas confirmée (sans skill, un agent peut lire `playwright-cli --help`).
- **Revenir en arrière** : supprimer le dossier `playwright-cli` de la skill.

Menu « Navigateur de Playwright CLI » (choix unique) · fichier `%USERPROFILE%\.playwright\cli.config.json` (réglages globaux de la CLI, copie de `dotfiles/playwright/<navigateur>.json` ; un projet peut avoir les siens dans `.playwright/cli.config.json`)

| Élément | Navigateur | Espace disque | Condition |
|---|---|---|---|
| `playwright-chrome` (par défaut) | Google Chrome installé sur la machine (`channel` `chrome`) | aucun en plus | Chrome choisi dans les navigateurs. Sans Chrome, la CLI échoue (« Chromium distribution 'chrome' is not found ») : choisir un autre navigateur |
| `playwright-msedge` | Microsoft Edge de Windows (`channel` `msedge`) | aucun en plus | Windows 10 (Edge y reste installé, neutralisé) |
| `playwright-chromium` | Chromium fourni par Playwright, téléchargé par `playwright-cli install-browser chromium` | ~720 Mo (Chromium et sa version sans interface) | — |
| `playwright-firefox` | Firefox fourni par Playwright (`install-browser firefox`) | ~350 Mo | — |

- **Implications** : les navigateurs fournis par Playwright vont dans `%LOCALAPPDATA%\ms-playwright` ; une mise à jour de la CLI peut en télécharger une nouvelle révision (Playwright supprime les révisions qui ne servent plus). Utiliser Chrome ou Edge de la machine évite cet espace disque. N'importe quel navigateur reste utilisable ponctuellement : `playwright-cli open --browser=firefox`.
- **Revenir en arrière** : supprimer `%USERPROFILE%\.playwright\cli.config.json` (Chrome par défaut) ; navigateurs téléchargés : supprimer leur dossier dans `%LOCALAPPDATA%\ms-playwright`.

### Réglages de Claude Code — `claude-settings`, `claude-bypass-permissions`, `claude-dx`

Fusion JSON (provider `file`, mode `merge-json`) dans `%USERPROFILE%\.claude\settings.json` (réglages du compte, valables dans tous les projets) : seules les clés listées sont imposées ; le crochet de rtk et les autres réglages sont conservés. Claude Code relit le fichier à chaud.

`claude-settings` : auto (avec `claude-code`) · `dotfiles/claude/settings.json`

| Réglage | Valeur | Effet |
|---|---|---|
| `model`, `advisorModel` | `opus` | Modèle par défaut (et conseiller) : Opus |
| `effortLevel` | `xhigh` | Effort de raisonnement très élevé : réponses plus réfléchies, plus lentes et plus coûteuses en quota |
| `language` | `French` | Claude répond en français |
| `theme`, `editorMode`, `verbose` | `dark`, `normal`, `true` | Thème sombre, saisie sans mode vim, sortie détaillée des outils |
| `env.CLAUDE_AUTOCOMPACT_PCT_OVERRIDE`, `env.CLAUDE_CODE_AUTO_COMPACT_WINDOW`, `autoCompactEnabled` | `30`, `1000000`, `true` | Compaction automatique de la conversation, déclenchée à 30 % d'une fenêtre de contexte comptée sur 1 million de jetons |
| `env.CLAUDE_CODE_MAX_TOOL_USE_CONCURRENCY`, `env.CLAUDE_CODE_MAX_CONCURRENT_SUBAGENTS` | `30`, `30` | Jusqu'à 30 outils et 30 sous-agents en parallèle |
| `env.DISABLE_TELEMETRY`, `env.DISABLE_ERROR_REPORTING`, `env.DISABLE_FEEDBACK_COMMAND` | `1` | Aucune statistique d'usage ni rapport d'erreur envoyés ; commande `/feedback` retirée |
| `attribution` | vides, `sessionUrl` : `false` | Pas de mention « Co-Authored-By: Claude » dans les commits, ni de lien de session dans les PR |
| `dialogExpiry`, `preferredNotifChannel` | `60s`, `auto` | Délai des boîtes de dialogue ; canal de notification choisi selon le terminal |
| `autoUpdatesChannel` | `latest` | Mises à jour dès leur publication |
| `autoContinueAtUsageLimit` | `true` | Reprend seul quand la limite d'usage est levée |

Volontairement absents : `SHELL` (Claude Code trouve Git Bash seul), les crochets (rtk les écrit lui-même ; celui de herdr est installé et réécrit par herdr), les plugins (installés par leur propre élément, ex. `claude-dx`), les skills (pas encore pris en charge).

`claude-bypass-permissions` : ✔ · menu « Claude Code : options » · `dotfiles/claude/bypass-permissions.json`

- **Effet** : `permissions.defaultMode` = `bypassPermissions`, `skipDangerousModePermissionPrompt` et `skipAutoPermissionPrompt` = `true` : Claude exécute commandes et modifications **sans demander d'autorisation**, et sans l'avertissement de lancement de ce mode.
- **Implications** : l'agent peut tout faire avec les droits du compte (supprimer des fichiers, lancer n'importe quelle commande, accéder au réseau). Choix du mainteneur, coché par défaut ; le décocher garde les demandes d'autorisation.
- **Revenir en arrière** : retirer ces trois clés (ou `/config` > mode d'autorisation par défaut).

`claude-dx` : ✔ · menu « Claude Code : options » · provider `claude-plugin`

- **Effet** : installe pour le compte le plugin `dx` de la marketplace [IMSike/CC-Plugins](https://github.com/IMSike/CC-Plugins) (`claude plugin install dx --marketplace IMSike/CC-Plugins`) : un bandeau au-dessus du prompt avec le modèle, l'effort de raisonnement, le répertoire et la branche Git, et des jauges pour le contexte et les limites d'usage sur 5 heures et sur 7 jours, colorées selon leur niveau ([documentation du plugin](https://github.com/IMSike/CC-Plugins/blob/main/docs/fr/plugins/dx.md)). La commande ajoute la marketplace `cc-plugins` et active le plugin dans `settings.json` (`extraKnownMarketplaces`, `enabledPlugins`) ; le plugin est copié dans `%USERPROFILE%\.claude\plugins\`.
- **Implications** : aucune dépendance (ni `jq` ni bash). Nécessite Claude Code 2.1.310 ou plus récent (installé par `claude-code`) et l'accès à GitHub pendant le setup. Le plugin est un mod à hooks de fonction, une API de Claude Code en accès anticipé : une mise à jour de Claude Code peut demander une mise à jour du plugin (`/plugin marketplace update cc-plugins`, ou mise à jour automatique de la marketplace dans `/plugin`). Le bandeau occupe cinq lignes au-dessus du prompt (repliable : `ctrl+x ctrl+a`) ; il n'est dessiné que dans le terminal et l'application de bureau.
- **Revenir en arrière** : `claude plugin uninstall dx@cc-plugins` (ou `claude plugin disable dx@cc-plugins` pour le garder installé), puis `claude plugin marketplace remove cc-plugins`.
- **Ancienne barre d'état** : une machine configurée par une version précédente du setup garde son réglage `statusLine` (script `statusline-command.sh` lu avec `jq`), affiché sous le prompt en plus du bandeau. Pour la retirer : supprimer `statusLine` de `settings.json`, puis `statusline-command.sh` et `statusline-config.json` de `%USERPROFILE%\.claude\` ; `jq` se désinstalle par `winget uninstall --id jqlang.jq`.

### Réglages de herdr — `herdr-config`, `herdr-explorer`

`herdr-config` : auto (avec `herdr` et PowerShell 7) · copie de `dotfiles/herdr/config.toml` vers `%APPDATA%\herdr\config.toml`

| Réglage | Valeur (par défaut) | Effet |
|---|---|---|
| `onboarding` | `false` | Pas d'écran de premier lancement (choix des notifications) |
| `theme.name` | `gruvbox` (`catppuccin`) | Thème de couleurs |
| `terminal.default_shell` | `pwsh.exe` | Les nouveaux volets ouvrent PowerShell 7 |
| `ui.sidebar_width` | `26` | Largeur de la barre latérale |
| `ui.mouse_scroll_lines` | `5` | Lignes défilées par cran de molette |
| `ui.prompt_new_tab_name` | `false` | Nouvel onglet créé sans demander son nom |
| `ui.pane_gaps` | `false` | Volets séparés par une bordure commune |
| `ui.toast.delivery` | `system` (`off`) | Notifications de Windows quand un agent a fini ou attend une réponse dans un espace en arrière-plan |
| `experimental.pane_history` | `false` | Historique des volets non conservé après un redémarrage du serveur herdr |

- **Implications** : seuls les écarts aux valeurs par défaut sont déployés. Le fichier est remplacé en entier (TOML, pas de fusion ; l'existant est sauvegardé) : un réglage changé dans herdr (`prefix+s`) est écrasé à la relance du setup ; le reporter dans le dépôt.
- **Revenir en arrière** : supprimer `%APPDATA%\herdr\config.toml` (valeurs par défaut).

`herdr-explorer` : ✔ · menu « Plugins herdr » (si Node.js choisi) · provider `herdr-plugin`

- **Effet** : plugin tiers [gcaudan/herdr-explorer](https://github.com/gcaudan/herdr-explorer) : explorateur de fichiers, aperçu, recherche et suivi Git (source control) dans chaque onglet. Installé par `herdr plugin install gcaudan/herdr-explorer` (clone géré par herdr, mis à jour par `herdr plugin update`) ; présence vérifiée dans `%APPDATA%\herdr\plugins.json`. Le fichier de réglages déployé est alors `config-explorer.toml` (mêmes réglages, plus les raccourcis du plugin, que cette méthode d'installation n'ajoute pas) : `prefix+f` explorateur, `prefix+a` aller à un fichier, `prefix+d` suivi Git. Réglages du plugin fusionnés dans `%LOCALAPPDATA%\herdr\plugins\gcaudan.explorer\settings.json` (`explorer-settings.json`, les autres réglages sont conservés) : `autoOpen` = `false` (l'explorateur ne s'ouvre plus seul dans chaque nouvel onglet, seulement avec `prefix+f`) et `side` = `right` (ancré à droite).
- **Implications** : nécessite Node.js 20 ou plus (`node-lts`), Git et une Nerd Font. Code tiers exécuté par herdr.
- **Revenir en arrière** : `herdr plugin uninstall gcaudan.explorer`, puis retirer les trois raccourcis de `config.toml`. Réglages : touche `,` dans l'explorateur, ou modifier `settings.json`.

### Microsoft Visual C++ Redistributable — `vcredist`

technique (avec `rtk`) · admin · winget `Microsoft.VCRedist.2015+.x64`

- **Effet** : bibliothèques d'exécution de Visual C++ (`vcruntime140.dll`…), absentes d'un Windows neuf. Sans elles, rtk ne démarre pas (code `0xC0000135`, « DLL introuvable », sans message) : constaté en VM, le paquet winget de rtk ne les déclare pas.
- **Revenir en arrière** : Paramètres > Applications > Microsoft Visual C++ 2015-2022 Redistributable (x64) — d'autres logiciels peuvent en avoir besoin.

## Logiciels de développement — `postman`, `pgadmin`

✔ · menu « Logiciels de développement »

| Élément | Paquet | Effet | Revenir en arrière |
|---|---|---|---|
| `postman` | winget `Postman.Postman` (pour le compte) | Client d'API (requêtes HTTP, collections). Compte Postman facultatif | Paramètres > Applications > Postman |
| `pgadmin` | winget `PostgreSQL.pgAdmin` | Administration de bases PostgreSQL (ex. celle d'un projet lancée par Docker, ci-dessous) | Paramètres > Applications > pgAdmin 4 |

## WSL — `wsl`, `wsl-platform`

✔ · admin · fonctionnalités Windows + winget `Microsoft.WSL`

- **Effet** : `wsl-platform` (ajouté automatiquement) active les fonctionnalités « Sous-système Windows pour Linux » et « Plateforme de machine virtuelle » ; après le redémarrage (fait et repris automatiquement), `wsl` installe WSL 2 (version distribuée hors Windows). Il écrit aussi `OOBEComplete` = 1 (DWORD, préférence HKCU, `HKCU\Software\Microsoft\Windows\CurrentVersion\Lxss`) : sans cette valeur, WSL ouvre au premier démarrage d'une distribution une fenêtre « Bienvenue dans WSL » (présentation des fonctionnalités), puis l'écrit lui-même. Sans elle, la fenêtre s'ouvre à la première ouverture de session, quand Docker Desktop démarre sa distribution.
- **Implications** : requiert la virtualisation activée dans le BIOS/UEFI ; un redémarrage. Docker Desktop fait tourner son moteur dans WSL 2 : WSL démarre avec lui (distribution `docker-desktop`, qu'il arrête après quelques minutes sans conteneur).
- **Revenir en arrière** : Paramètres > Applications > Windows Subsystem for Linux > Désinstaller, puis « Activer ou désactiver des fonctionnalités Windows ». Revoir la fenêtre de bienvenue : menu Démarrer > Paramètres WSL.

### Mémoire de WSL — `wsl-config`

auto (avec `wsl`) · provider `wsl-config` (clé `memory` de la section `[wsl2]` de `%USERPROFILE%\.wslconfig`)

- **Effet** : plafonne la mémoire de la VM de WSL 2 à **40 % de la RAM** (WSL prend sinon jusqu'à la moitié). Docker Desktop tourne dans cette VM : le plafond le concerne aussi. Linux garde en cache les fichiers lus tant qu'il n'est pas à court de mémoire ; un plafond plus bas l'oblige à libérer ce cache avant que Windows ne manque de mémoire (sans plafond, plus de 18 Go de cache retenus par la VM ont été constatés).
- **Sécurité matérielle** : la valeur est calculée sur la machine, pas écrite en dur : un fichier de réponses rejoué sur une machine plus petite reste valable. Bornes : au moins 2 Go pour WSL, au moins 4 Go laissés à Windows ; une valeur ramenée dans ces bornes est signalée dans le journal. En dessous de 6 Go de RAM, aucun plafond n'est écrit (valeur par défaut de WSL). Exemples : 16 Go → 6 Go ; 32 Go → 12 Go ; 64 Go → 25 Go.
- **Implications** : seule cette clé est écrite, le reste du fichier est conservé (sauvegardé avant modification). Pris en compte au prochain démarrage de WSL (`wsl --shutdown` pour l'appliquer tout de suite). `autoMemoryReclaim` (restitution du cache à Windows) n'est pas écrit : `dropCache` est déjà la valeur par défaut de WSL.
- **Revenir en arrière** : retirer la ligne `memory=` de `%USERPROFILE%\.wslconfig`.

### Distributions Linux — `wsl-ubuntu`, `wsl-fedora`

○ · menu « Avec WSL » · provider `manual` (étape manuelle guidée)

Facultatives : utiles seulement pour travailler dans un terminal Linux (outils propres à Linux, projets à compiler sous Linux). **Docker Desktop n'en a pas besoin** : il installe sa propre distribution interne (`docker-desktop`), sans compte utilisateur, et `docker` fonctionne depuis Windows.

| Élément | Distribution WSL | Revenir en arrière |
|---|---|---|
| `wsl-ubuntu` | `Ubuntu` (dernière LTS) | `wsl --unregister Ubuntu` |
| `wsl-fedora` | `FedoraLinux-44` (le nom WSL de Fedora inclut sa version : à mettre à jour à chaque nouvelle version de Fedora) | `wsl --unregister FedoraLinux-44` |

- **Effet** : installe la distribution dans WSL (`wsl --install --distribution <nom>`, dans une nouvelle fenêtre) ; à son premier lancement, elle demande le nom et le mot de passe du **compte Linux** : seule partie manuelle. Le setup vérifie ensuite que la distribution est enregistrée avec un compte autre que root (registre `HKCU\Software\Microsoft\Windows\CurrentVersion\Lxss`, `DefaultUid`).
- **Implications** : traité après le redémarrage de WSL. Le mot de passe sert à `sudo` ; il n'est connu que de l'utilisateur. `wsl --unregister` supprime la distribution et ses fichiers.

### Docker Desktop — `docker-desktop`

✔ · menu « Avec WSL » · admin · winget `Docker.DockerDesktop`

- **Effet** : Docker (conteneurs) avec WSL 2 comme moteur : `docker` et `docker compose` dans tous les terminaux.
- **Implications** : l'installeur ajoute le compte au groupe local `docker-users`, pris en compte à l'ouverture de session suivante (sans elle : `failed to connect to the docker API at npipe:////./pipe/docker_engine`) ; l'élément est donc marqué `requiresLogoff` et le setup ferme la session en fin d'exécution. Démarré à l'ouverture de session (par la tâche d'entretien, voir ci-dessous), il demande d'accepter ses conditions au premier lancement (gratuit pour un usage personnel ou une petite entreprise). Sa mémoire est celle de WSL (`wsl-config`) ; son espace disque est traité ci-dessous.
- **Revenir en arrière** : Paramètres > Applications > Docker Desktop > Désinstaller.

### Espace disque de Docker

Docker range images, conteneurs, volumes (données des bases) et cache de build dans **un seul disque virtuel**, `%LOCALAPPDATA%\Docker\wsl\disk\docker_data.vhdx`. Ce fichier **grossit quand Docker a besoin de plus de place, mais ne rétrécit jamais seul** : supprimer des images libère de la place dans le disque virtuel (Docker la réutilise), pas sur le disque de Windows. Si le contenu s'accumule sans être nettoyé, le fichier bat sans cesse de nouveaux records. Avec WSL 2, Docker Desktop n'offre **aucune taille maximale** réglable (taille théorique : 1 To). Le setup agit donc ainsi :

- **Plafond du cache de build** (`docker-build-cache`, ci-dessous) : le plus gros consommateur est nettoyé automatiquement par Docker.
- **Avertissement d'espace disque** : au plan, si le disque système a moins de 40 Go libres, un avertissement le signale (rien n'est bloqué).
- **Entretien hebdomadaire** (`docker-maintenance`, ci-dessous) : compactage du disque virtuel (l'espace libéré est rendu à Windows) et suppression des images orphelines.
- **Non fait** : suppression des images inutilisées (complètes, mais utilisées par aucun conteneur) : un projet qui en a de nouveau besoin devrait la retélécharger ou la reconstruire (`docker image prune --all` à la main si besoin).
- **Écarté** : le mode « sparse » de WSL (disque qui rend l'espace seul) a été bloqué par Microsoft en 2025 après des corruptions de données, et n'est réautorisé qu'en préversion expérimentale.

`docker-build-cache` : auto (avec `docker-desktop`) · provider `docker-build-cache` (clés `builder.gc` de `%USERPROFILE%\.docker\daemon.json`, fusionnées : les autres réglages du moteur sont conservés)

- **Effet** : `builder.gc.enabled` = `true`, `defaultKeepStorage` = **30 Go** (20 Go par défaut) : au-delà, Docker supprime lui-même le cache de build le plus ancien. Un build qui en avait besoin refait seulement les étapes concernées (plus lent la première fois).
- **Sécurité matérielle** : ramené à **10 % de la taille du disque système** quand c'est moins (ex. disque de 128 Go : 12 Go), signalé au journal.
- **Implications** : pris en compte au prochain démarrage de Docker Desktop (fichier sauvegardé avant modification). Docker Desktop affiche aussi ce fichier dans Paramètres > Docker Engine.
- **Revenir en arrière** : retirer la section `builder` de `daemon.json` (Paramètres > Docker Engine).

`docker-maintenance` : auto (avec `docker-desktop`) · script `dotfiles/docker/docker-maintenance.ps1` copié dans `%LOCALAPPDATA%\OS-Setup\` (hors du dépôt, qui peut être supprimé en fin de setup) · provider `logon-task` (tâche planifiée « OS-Setup - Docker (entretien) », à l'ouverture de session, droits les plus élevés, Windows PowerShell 5.1)

- **Effet**, à chaque ouverture de session :
  1. **Une fois par semaine au plus**, **compactage** du disque virtuel de Docker (`diskpart` : `attach vdisk readonly`, `compact vdisk`) tant que Docker et WSL sont arrêtés : le fichier est ramené à ce qu'il contient vraiment, l'espace libéré revient à Windows. Si Docker ou une distribution WSL tourne déjà, reporté à la session suivante.
  2. **Démarrage de Docker Desktop** (sans droits administrateur, par l'Explorateur), à la place de son propre lancement automatique, désactivé comme le fait le Gestionnaire des tâches pour qu'il ne démarre pas pendant le compactage. Le réglage « démarrer avec Windows » de Docker Desktop reste respecté : décoché, Docker n'est pas démarré.
  3. **Une fois par semaine au plus**, suppression des **images orphelines** (`docker image prune` : restes d'images reconstruites, sans nom, jamais réutilisés), une fois le moteur prêt (5 minutes d'attente au plus).
- **Implications** : seul Docker est prêt un peu plus tard le jour du compactage (de quelques secondes à quelques minutes selon la taille du disque virtuel) ; Windows et la session démarrent normalement. Les volumes (données des bases), les images utilisées ou simplement inutilisées ne sont jamais supprimés. Journal : `%LOCALAPPDATA%\OS-Setup\docker-maintenance.log` (tailles avant et après) ; dates des derniers entretiens : `docker-maintenance.json` (le supprimer force l'entretien à la prochaine session).
- **Revenir en arrière** : supprimer la tâche « OS-Setup - Docker (entretien) » (Planificateur de tâches), réactiver Docker Desktop dans Gestionnaire des tâches > Démarrage, supprimer `%LOCALAPPDATA%\OS-Setup\docker-maintenance.*`.

### PostgreSQL : une base par projet, dans Docker

Pas d'élément PostgreSQL dans le catalogue (décision : un serveur par projet plutôt qu'un service installé sur la machine). Chaque projet déclare sa base dans un `docker-compose.yml`, avec la version qu'il lui faut :

```yaml
services:
  db:
    image: postgres:17
    environment:
      POSTGRES_USER: app
      POSTGRES_PASSWORD: app   # mot de passe de développement local, jamais de production
      POSTGRES_DB: app
    ports:
      - "5432:5432"            # un autre port (ex. "5433:5432") pour un 2e projet lancé en même temps
    volumes:
      - db-data:/var/lib/postgresql/data
volumes:
  db-data:
```

`docker compose up -d` démarre la base, `docker compose down` l'arrête (les données restent dans le volume ; `down -v` les supprime). Dans pgAdmin : serveur `localhost`, port `5432`, utilisateur et mot de passe ci-dessus.
