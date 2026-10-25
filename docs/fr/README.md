# Documentation

[English](../en/README.md) · **Français**

## Utiliser le setup

| Page | Contenu |
|---|---|
| [Utilisation](usage.md) | Lancement, paramètres, fichiers de réponses, journaux, redémarrages, retour arrière |
| [Comment le setup modifie Windows](how-it-works.md) | Providers, registre (HKLM / HKCU), préférences et stratégies, étapes manuelles, valeurs d'origine |

## Ce que fait le setup

| Page | Contenu |
|---|---|
| [Réglages Windows](windows/settings.md) | Confidentialité, système, alimentation : effet, implications, retour arrière de chaque réglage |
| [Applications supprimables](windows/removable-apps.md) | Applications du Store, composants Windows et logiciels préinstallés |
| [Intégration au bureau](windows/desktop.md) | Barre des tâches, menu Démarrer, raccourcis |
| [Navigateurs](windows/browsers.md) | Edge neutralisé, télémétrie des navigateurs, navigateur par défaut |
| [Logiciels](windows/apps.md) | Logiciels courants du profil `base` |
| [Développement](windows/development.md) | Profil `dev` : Git, terminal, éditeurs, Node.js, agents, WSL, Docker |
| [Pilotes](windows/drivers.md) | Windows Update et outils des fabricants selon le matériel |

## Contribuer

| Page | Contenu |
|---|---|
| [Architecture](architecture.md) | Principes, concepts (éléments, profils, choix, providers), déroulement |
| [Ajouter un élément](adding-items.md) | Créer un logiciel ou un réglage dans le catalogue |
| [Tests](testing.md) | Tests unitaires, qualité du code, VM de test Hyper-V |
| [Pièges connus](pitfalls.md) | winget, Windows et PowerShell : comportements constatés |
| [Décisions d'architecture](adr/) | [0001](adr/0001-engine-language.md) langage du moteur · [0002](adr/0002-agent-assistance.md) assistance d'un agent · [0003](adr/0003-in-house-dotfiles.md) fichiers de configuration |

Voir aussi le [guide de contribution](../../CONTRIBUTING.fr.md).
