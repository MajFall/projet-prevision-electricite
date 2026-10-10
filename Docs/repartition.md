## Répartition du travail

### Alioune : données et variables

Scripts : `01_download.R`, `02_prepare.R`, `02b_controles.R`, `02c_exploration.R`, `02d_sensibilite_poids.R`, `03_features.R`

- [x] Récupérer éCO2mix et SYNOP
- [x] Passer les données au pas horaire
- [x] Traiter valeurs manquantes, changements d'heure et valeurs atypiques
- [x] Faire l'exploration (cycles, relation température-consommation, jours fériés, ruptures)
- [x] Construire les variables : calendrier, retards, météo (disponibles à 14h)
- [x] Construire la variante « météo parfaite »
- [ ] Rédiger les sections 2 (données) et 3 (exploration) du rapport

### Maj: évaluation et modèles

Scripts : `04_benchmarks.R`, `05_models.R`, `05b_ablation.R`, `06_evaluate.R`

- [x] Écrire la fonction de découpage temporel (apprentissage / validation / test)
- [x] Écrire les métriques (MAE, RMSE, total journalier, valeur et heure de la pointe)
- [x] Implémenter les benchmarks (veille, semaine précédente)
- [x] Implémenter la régression simple et un modèle plus élaboré
- [x] Faire les ablations et la comparaison opérationnel / météo parfaite
- [ ] Rédiger les sections 4 (protocole), 5 (modèles) et 6 (résultats) du rapport

### Travail commun

- Analyse d'échecs et pistes exploratoires (après le test, sans modifier les modèles) : `07_analyse_echecs.R`, `05c_pistes.R`

- Protocole : période d'étude, découpage, définition de « 14h le jour J »
- Tableau de disponibilité des variables (`Docs/disponibilite_variables.md`)
- Format du tableau de données final et des prévisions
- Analyse d'échecs, audit critique, usage de l'IA, conclusion (sections 1, 7, 8, 9)
- Relecture croisée du code (recherche de fuites d'information) et préparation de l'oral

### Organisation Git

- Une branche par tâche (`donnees`, `benchmarks`, `modeles`…), fusionnée dans `main` par pull request relue par l'autre.
- Avant de travailler : `git pull`. Après : `git add .`, `git commit`, `git push`.
- Ne pas modifier le même fichier en même temps.
