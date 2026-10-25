# Pilotes

Objectif : installer et mettre à jour les pilotes **selon le matériel détecté**. Menu « Pilotes » du profil `base` (`catalog/drivers/`) : une option n'est proposée que si elle correspond à la machine (faits `Manufacturer`, `CpuVendor`, `GpuVendor`, condition `when`).

## Approche retenue

1. **Passe Windows Update « pilotes »** sur toutes les machines, par l'API intégrée de Windows Update.
2. **Outils des fabricants** quand le matériel correspond : ceux des PC de marque (pilotes **et BIOS**) cochés par défaut, celui d'Intel décoché.
3. **Cartes graphiques NVIDIA et AMD** : par Windows Update pour l'instant (leurs outils ne sont pas dans winget). Une étape manuelle guidée (page officielle, vérification) pourra être ajoutée.
4. **Bilan** en fin de setup : périphériques sans pilote ou en erreur, ajoutés au récapitulatif.

## Éléments

### Windows Update : pilotes proposés — `windows-update-drivers`

✔ · admin · provider `windows-update`

- **Effet** : recherche auprès de Windows Update les pilotes manquants ou plus récents **pour le matériel présent**, les télécharge et les installe. Si Windows demande un redémarrage, le setup redémarre et reprend automatiquement.
- **Mécanisme** : objet COM `Microsoft.Update.Session` (critère `IsInstalled=0 and Type='Driver' and IsHidden=0`), sans module tiers ; fonctionne sur Windows non activé. Conforme quand Windows Update ne propose plus aucun pilote.
- **Implications** : la recherche interroge les serveurs de Microsoft (une à quelques minutes, résultat mémorisé pendant l'exécution). Les versions proposées sont souvent en retard, surtout pour les cartes graphiques. Un pilote qui échoue à s'installer met l'élément en échec (titre indiqué) ; il sera retenté à la relance.
- **Revenir en arrière** : Gestionnaire de périphériques > périphérique > Pilote > « Restaurer le pilote ».

### Outils des fabricants (installés par winget)

| Élément | Défaut | Proposé si | Outil (identifiant winget) | Ce qu'il apporte |
|---|---|---|---|---|
| `dell-command-update` | ✔ | PC Dell (`Manufacturer` = dell) | Dell Command \| Update (`Dell.CommandUpdate`) | Tous les pilotes et le BIOS des PC Dell |
| `lenovo-system-update` | ✔ | PC Lenovo | Lenovo System Update (`Lenovo.SystemUpdate`) | Tous les pilotes et le BIOS des PC Lenovo |
| `hp-support-assistant` | ✔ | PC HP | HP Support Assistant (`HP.SupportAssistant`) | Pilotes et BIOS des PC HP (HP Image Assistant, outil d'entreprise, n'est pas proposé) |
| `intel-driver-assistant` | ○ | processeur Intel (`CpuVendor` = intel) | Intel Driver & Support Assistant (`Intel.IntelDriverAndSupportAssistant`) | Pilotes Intel (graphique, Wi-Fi, Bluetooth) plus récents que ceux de Windows Update |

- **Implications** : ces outils restent installés (service et, souvent, icône près de l'horloge) et proposent ensuite eux-mêmes les mises à jour. Les mises à jour de BIOS se font depuis l'outil, à la demande de l'utilisateur.
- **Revenir en arrière** : désinstaller l'outil (Paramètres > Applications).
- La condition Intel porte sur le processeur : un PC à processeur Intel a presque toujours des composants graphiques, Wi-Fi ou Bluetooth Intel (la condition `when` ne sait pas combiner deux faits par « ou »).

## Bilan des périphériques

En fin de setup (hors simulation), le récapitulatif liste les périphériques signalés par le Gestionnaire de périphériques : sans pilote (code 28), en erreur, ou désactivés (code 22). C'est ce qui reste à faire à la main ; « aucun » est affiché quand tout va bien.

## Options étudiées

| Option | Pour | Contre |
|---|---|---|
| **Windows Update, API intégrée** (retenue) | Natif, couvre tout le matériel, fonctionne sans licence | Versions souvent en retard (surtout GPU) |
| Module PSWindowsUpdate | Pratique | Dépendance tierce à installer : écartée, le natif suffit |
| `pnputil` | Natif | N'utilise que les pilotes déjà présents sur la machine |
| **Outils fabricants de composants** via winget (retenu pour Intel) | Pilotes récents, mises à jour suivies ensuite | NVIDIA App et AMD Adrenalin absents de winget |
| **Outils constructeurs de PC** (retenus : Dell, Lenovo, HP) | Gèrent BIOS + tous les pilotes | Uniquement sur PC de marque |
| Téléchargement direct (NVIDIA, AMD) | Automatique | Adresses et versions changeantes, téléchargements bloqués par AMD : maintenance fragile |
| Packs de pilotes tiers (Snappy Driver Installer…) | Hors ligne, exhaustif | Source tierce, risque de pilotes inadaptés : **écarté** |
