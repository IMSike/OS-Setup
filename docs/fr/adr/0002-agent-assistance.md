# ADR 0002 — Intervention d'un agent IA dans le setup

- **Statut** : proposé
- **Date** : 2026-10-20

## Contexte

Le setup doit fonctionner sur machine vierge, mais aussi sur une machine **déjà utilisée** : logiciels installés hors winget,
emplacements non standard, configurations existantes (Claude Code, etc.) à préserver ou fusionner.
Ces cas sont trop variés pour être tous codés de façon déterministe.

## Décision

Le moteur reste **déterministe et autonome** ; l'agent est une **couche optionnelle** qui intervient sur les cas non couverts.

1. **Audit** (`setup -Audit`) : le moteur inventorie l'existant (paquets winget, emplacements d'installation, fichiers de config présents, réglages déjà appliqués) et écrit un rapport JSON (`state/audit-<date>.json`).
2. **Plan** : le moteur compare l'audit aux choix de l'utilisateur et produit un plan JSON où chaque étape est `ok` (déjà conforme), `todo` (action automatique) ou `review` (conflit / cas inconnu).
3. **Assistance agent** (`setup -Assist`, optionnel) : un agent (Claude Code en mode non interactif) reçoit le plan et ne traite que les étapes `review`. Il **propose** des résolutions (ex. emplacement réel d'un logiciel, fusion d'une config existante) sous forme d'un fichier de réponses complété.
4. **Validation humaine** : les propositions de l'agent sont affichées et doivent être approuvées avant exécution. L'exécution passe toujours par le moteur (même journalisation, même `-WhatIf`).

Un élément de catalogue peut aussi déclarer une étape `verify` avec une consigne destinée à l'agent (ex. « vérifier que Claude Code voit bien les MCP configurés »), exécutée seulement en mode `-Assist`.

## Conséquences

- Le setup reste utilisable sans agent ni connexion à un service IA.
- L'agent n'agit jamais directement sur le système : il produit des données que le moteur exécute.
- L'assistance est **situationnelle** (peut ne jamais servir). Si elle est requise, le moteur installe d'abord Claude Code **et sa configuration**, puis met en pause et demande à l'utilisateur de se connecter (`claude` → login) avant de reprendre la main.
- Format exact du rapport d'audit et du plan : à définir avec les schémas JSON.
