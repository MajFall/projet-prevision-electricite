# Journal d'usage de l'IA (étape données)

| # | Tâche | Proposition de l'IA | Décision | Vérification |
|---|---|---|---|---|
| 1 | Règle d'accès aux données à 14 h | Latence de 1 h : dernière heure de consommation utilisable [12 h, 13 h[ ; idem pour SYNOP | Conservée | [à compléter] |
| 2 | Agrégation des demi-heures en heures | Heure valide seulement si tous les pas présents | Modifiée : les lignes :15 et :45 sont vides, la règle invalidait toutes les heures ; remplacée par « au moins un relevé » | Comptage des manquants (8 heures sur 70 128), contrôles C3 et C8 |
| 3 | Liste des stations SYNOP | Téléchargement de `postesSynop.csv` et contrôle C5 | Rejetée : le fichier était une page HTML, C5 annonçait 12 stations introuvables ; C5 réécrit sur les fichiers SYNOP | Lecture des premières lignes ; tableau station × année |
| 4 | Code des scripts 01 à 04 | Code R écrit sans exécution possible côté IA | Testé et corrigé par Alioune (chemins `setwd` supprimés, validations de fichiers ajoutées) | Exécution complète et lecture des sorties |
| 5 | Exploration | Script `02c_exploration.R` (figures e01-e09) | Conservé après exécution et lecture des figures | Sorties console, tableaux CSV, figures |
