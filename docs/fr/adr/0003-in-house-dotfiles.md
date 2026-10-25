# ADR 0003 — Configurations applicatives : déploiement maison

- **Statut** : accepté
- **Date** : 2026-10-20

## Contexte

Le setup doit déployer des configurations d'outils (Claude Code, herdr, Git, PowerShell, terminal, éditeur…), parfois dans des emplacements non standard, et différentes selon l'OS et la machine.

chezmoi a été envisagé (gabarits, diff, multiplateforme) mais écarté : il ajoute un logiciel sur la machine cible, une syntaxe de gabarits et des conventions de nommage à apprendre, pour un besoin que le moteur peut couvrir simplement.

## Décision

Le moteur déploie lui-même les fichiers de `dotfiles/`. Chaque élément du catalogue déclare dans son étape `configure` une liste de fichiers :

| Champ | Rôle |
|---|---|
| `source` | Chemin relatif dans `dotfiles/` |
| `target` | Chemin de destination, avec variables (ex. `{{UserProfile}}/.claude/settings.json`) |
| `mode` | `copy` (copie telle quelle), `template` (remplacement des variables `{{Nom}}`), `merge-json` (fusion profonde dans un JSON existant) |
| `when` | Condition optionnelle (OS, profil, machine…) |

Règles :

- **Gabarits volontairement simples** : substitution de variables uniquement, pas de logique. Une variante par OS = un fichier source distinct sélectionné par `when`.
- **`merge-json`** pour les fichiers que les applications réécrivent elles-mêmes (ex. `settings.json`) : le dépôt ne contient que les clés gérées, les autres clés de la machine sont conservées.
- **Idempotence** : le contenu attendu est comparé au contenu présent ; seuls les fichiers différents apparaissent dans le plan.
- **Diff** : le plan affiche les différences avant application.
- **Sauvegarde** : tout fichier existant modifié est d'abord copié dans `state/backups/<horodatage>/` (même arborescence).
- **Capture** (plus tard) : commande inverse pour rapatrier dans le dépôt une config modifiée sur la machine (hors mode `template`).

## Migration de l'existant

Avant le déploiement, le moteur exécute les étapes `migrate` déclarées par les éléments :

- détecter un emplacement existant différent de l'emplacement cible ;
- sauvegarder, puis déplacer / renommer (ex. dossiers de mémoire Claude Code, dont le nom dérive du chemin du projet) ;
- consigner l'opération dans le journal et le plan (`review` si ambigu).

Les **données utilisateur** (mémoires Claude Code, historiques…) ne sont pas des dotfiles et ne vont jamais dans ce dépôt public. Elles pourront vivre dans un **second dépôt privé**, à concevoir plus tard.

## Conséquences

- Aucun logiciel supplémentaire sur la machine cible.
- Le code de déploiement est dans le moteur (provider `file`) et testé (Pester) : copie, gabarit, fusion JSON (`merge-json`, première utilisation : préférences d'installation de Chrome) et sauvegarde sont faits ; le diff affiché avant remplacement reste à écrire.
- Les besoins avancés (secrets, logique dans les gabarits) devront être traités au cas par cas ; si leur nombre croît, réévaluer un outil dédié.
