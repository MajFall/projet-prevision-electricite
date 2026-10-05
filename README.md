# Prévision de la consommation électrique en France métropolitaine

Projet de données temporelles (groupe : NOM1, NOM2).

## Problème
À 14h le jour J, prévoir les 24 valeurs horaires de consommation du jour J+1.

## Données
- Consommation : éCO2mix (RTE)
- Météo : SYNOP (Météo-France)
- Calendrier : construit dans `src/03_features.R`

## Installation
1. Ouvrir `projet-prevision-electricite.Rproj` dans RStudio
2. Dans la console : `install.packages("renv"); renv::restore()`

## Ordre d'exécution
Tout lancer : `source("run_all.R")`, ou étape par étape :
1. `src/01_download.R`   (long : téléchargement)
2. `src/02_prepare.R`
3. `src/03_features.R`
4. `src/04_benchmarks.R`
5. `src/05_models.R`     (long : entraînement)
6. `src/06_evaluate.R`

## Organisation des fichiers
(à décrire)

## Étapes coûteuses
(à compléter)
