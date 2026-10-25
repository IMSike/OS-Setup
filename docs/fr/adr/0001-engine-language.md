# ADR 0001 — Langage du moteur : PowerShell 7

- **Statut** : accepté pour Windows ; Fedora à réévaluer quand la question se posera
- **Date** : 2026-10-20

## Contexte

Le setup doit cibler Windows 10/11 puis Fedora (et d'autres distributions Linux plus tard ; pas de macOS).
Le moteur a deux types de responsabilités :

- **communes** : lire et valider le JSON, fusionner les profils, afficher les menus, résoudre les dépendances, journaliser, produire un plan ;
- **spécifiques à l'OS** : winget, registre, services, fonctionnalités Windows / dnf, gsettings, systemd…
  Ces actions se réduisent essentiellement à appeler des commandes système, quel que soit le langage.

Options étudiées :

| Option | Pour | Contre |
|---|---|---|
| PowerShell 7 partout | Un seul moteur ; excellent sur Windows (registre, services, Appx) ; `Test-Json -Schema` natif | Absent de Fedora par défaut (installable depuis le dépôt Microsoft) ; peu idiomatique sous Linux |
| Python 3 | Natif sur Fedora ; bonnes bibliothèques (menus, jsonschema) | Absent de Windows ; réglages Windows souvent délégués à PowerShell ; gestion venv/dépendances |
| Go / Rust (binaire) | Aucun runtime requis | Chaîne de build et releases ; évolution plus lourde |
| Natif par OS (PowerShell + Bash) | Idiomatique, zéro dépendance | Deux moteurs : logique profils/choix/menus dupliquée |
| Ansible / WinGet Configuration (DSC) | Outils éprouvés | Ansible : contrôleur Linux + WinRM ; DSC : Windows uniquement ; choix interactifs pénibles |

## Décision

- Moteur unique en **PowerShell 7** (`pwsh`), partagé entre plateformes.
- Deux **bootstraps** minimaux, seuls fichiers propres à chaque OS en dehors des providers :
  - `bootstrap.ps1` (Windows PowerShell 5.1) : installe Git et PowerShell 7 via winget, clone, lance `setup.ps1` ;
  - `bootstrap.sh` (Bash) : installe Git et PowerShell 7 via dnf, clone, lance `setup.ps1`.
- Le code spécifique à un OS est confiné aux **providers** et aux éléments de catalogue.

## Conséquences

- PowerShell 7 devient une dépendance du setup sur toutes les plateformes (il est de toute façon utile au profil `dev`).
- Fedora ne figure pas dans la liste officielle des distributions supportées par PowerShell : l'installation via le paquet RHEL du dépôt Microsoft est à **valider en VM** avant de considérer la décision comme acceptée.
- Repli possible : Python 3, si PowerShell sous Fedora pose problème.
