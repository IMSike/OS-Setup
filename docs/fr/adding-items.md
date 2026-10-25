# Ajouter un élément au catalogue

Un élément est un fichier JSON de `catalog/<catégorie>/`, validé par [`schemas/item.schema.json`](../../schemas/item.schema.json). Ajouter un logiciel ou un réglage ne demande pas de modifier le moteur.

## Exemple

```json
{
  "$schema": "../../schemas/item.schema.json",
  "id": "explorer-show-extensions",
  "name": "Explorateur : extensions de fichiers affichées",
  "category": "system",
  "platforms": ["windows"],
  "notes": "Pris en compte au redémarrage de l'Explorateur ou à la prochaine session.",
  "actions": [
    {
      "provider": "registry",
      "path": "HKCU:\\Software\\Microsoft\\Windows\\CurrentVersion\\Explorer\\Advanced",
      "name": "HideFileExt",
      "type": "DWord",
      "value": 0
    }
  ]
}
```

Les providers disponibles et leurs paramètres sont décrits dans [Comment le setup modifie Windows](how-it-works.md#providers) ; le schéma fait foi.

## Étapes

1. **Paquet winget** : trouver l'identifiant exact avec `winget search <nom>`, puis `winget show --id <Id> --exact`. Le provider utilise toujours `--exact --id`, `--source winget`, `--accept-package-agreements`, `--accept-source-agreements` et `--silent`. Préciser le `scope` (`user` ou `machine`). Voir les [pièges de winget](pitfalls.md#winget-windows-10-winget-129).
2. **Créer le fichier** dans la bonne catégorie :

   | Catégorie | Contenu | Documentation |
   |---|---|---|
   | `system/`, `privacy/`, `power/` | Réglages Windows | [Réglages Windows](windows/settings.md) |
   | `remove/` | Applications, composants et logiciels préinstallés à supprimer | [Applications supprimables](windows/removable-apps.md) |
   | `desktop/` | Épingles, menu Démarrer, raccourcis, barre des tâches | [Intégration au bureau](windows/desktop.md) |
   | `browsers/`, `browser-settings/` | Navigateurs et leurs stratégies | [Navigateurs](windows/browsers.md) |
   | `drivers/` | Pilotes, outils des fabricants | [Pilotes](windows/drivers.md) |
   | `dev/` | Profil développement | [Développement](windows/development.md) |
   | `apps/` | Logiciels courants | [Logiciels](windows/apps.md) |

3. **Nom** (`name`) sous la forme « Sujet : état » ou « Logiciel : précision » (ex. « Localisation : désactivée », « lazygit : interface Git dans le terminal ») ; un logiciel seul garde son nom (« Firefox »). Le sujet vient en premier ; les menus affichent en couleur la partie après « : ». Les conséquences à connaître vont dans `uncheckedWarning` ou `checkedWarning`, pas dans le nom.
4. **PATH** : le moteur recharge le PATH de la session après chaque installation. Si l'installeur n'ajoute pas lui-même le logiciel au PATH, ajouter une action `path`.
5. **Dépendances** (`dependsOn`), **conditions** (`when`), **redémarrage** (`requiresReboot`) ou **fermeture de session** (`requiresLogoff`) : voir [Architecture](architecture.md#concepts).
6. **Le proposer dans un profil** (`profiles/`) : tout ce qui s'installe ou se supprime va dans un groupe de choix, jamais dans `items` (vérifié au chargement).
7. **Le documenter** dans la page de sa catégorie, **en anglais et en français**, sous son identifiant entre accents graves : effet, implications, valeur modifiée (préférence ou stratégie, HKCU ou HKLM), retour arrière manuel. Un test vérifie qu'aucun élément n'est oublié.
8. **Vérifier** : `Invoke-Pester -Path tests`, puis `./setup.ps1 -WhatIf` affiche le plan attendu, puis un test en VM ([Tests](testing.md)). Pour un réglage Windows, vérifier après redémarrage que la page de Paramètres concernée (ou le comportement) est dans l'état attendu : relire une valeur ne prouve pas que Windows la prend en compte.

## Machines sans licence

La plupart des machines cibles ne sont pas activées : les pages de personnalisation des Paramètres y sont verrouillées. Un réglage de personnalisation doit être appliqué par registre ou par commande, et testé sur une machine non activée.
