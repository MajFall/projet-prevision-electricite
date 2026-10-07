# Prévision de la consommation électrique en France métropolitaine

## Liens

- Rapport (Word en ligne, Office 365) : [https://univlyon2fr-my.sharepoint.com/:w:/g/personal/mfall10_univ-lyon2_fr/IQCRNOWIFuxoT7JgUh8RE4MnAeE63El1gMfPsg5IRWHc-gI?e=f8ry4D]
- Diapositives de l'oral : [lien, quand elles existeront]


Projet de données temporelles, groupe : Madjiguène, Alioune.

## 1. Problème de prévision

À 14h le jour J, on prévoit les 24 consommations horaires du jour J+1.
Le protocole respecte strictement l'information disponible à 14h le jour J :
aucune donnée observée après cette origine n'est utilisée dans le scénario
opérationnel. Le scénario « météo parfaite » (météo observée de J+1) n'est
utilisé que comme borne de performance, jamais comme méthode déployable.

## 2. Données

| Source | Contenu | Récupération |
|---|---|---|
| éCO2mix (RTE) | Consommation électrique | `src/01_download.R` |
| SYNOP (Météo-France) | Observations météorologiques | `src/01_download.R` |
| Calendrier scolaire (Éducation nationale) | Vacances des zones A, B et C | `src/01_download.R` |
| Calendrier construit | Jour de semaine, mois, week-end, jours fériés, ponts, fin d'année, nombre de zones en vacances (0 à 3) | `src/02_prepare.R` |

- Période étudiée : 1er janvier 2018 – 31 décembre 2025 (70 128 heures, grille horaire en UTC).
- Stations météo retenues et agrégation spatiale : 12 stations SYNOP (Paris-Orly, Lyon-Saint-Exupéry, Marseille, Toulouse, Bordeaux, Lille, Nantes, Nice, Strasbourg, Montpellier, Rennes, Brest), moyenne pondérée par un poids proche de la population de l'agglomération ; agrégat validé si au moins 70 % du poids est disponible (`STATIONS` dans `src/00_config.R`).
- Pas horaire : moyenne des relevés disponibles de l'heure (éCO2mix au pas de 30 min, lignes :15 et :45 vides) ; météo SYNOP gardée à son pas natif de 3 h, non interpolée.
- Valeurs manquantes : 8 heures de consommation sur 70 128 (heure de 00 h UTC du retour à l'heure d'hiver, chaque année), non imputées.
- Changements d'heure : 8 jours à 23 h et 8 jours à 25 h, conservés dans la table et exclus du score principal.
- Valeurs atypiques : aucune consommation négative ou nulle (`conso_suspecte`) ; pics isolés comparés aux heures voisines (maximum 8 %, pointe du soir) ; jours extrêmes expliqués par la météo. Aucune valeur n'est supprimée.
- Premier confinement (17/03 au 11/05/2020) : conservé dans la table, exclu de l'apprentissage seulement (colonne `utilise_apprentissage` de `cas_horaires.rds`) ; validation et test inchangés.
- Latences supposées : 1 h pour la consommation et pour la météo (`LATENCE_CONSO_H`, `LATENCE_METEO_H`).
- Table de prévision (`src/03_features.R`) : une ligne par heure cible de J+1, avec uniquement l'information connue à 14 h le jour J (calendrier de J+1 dont vacances scolaires, consommation retardée `conso_lag1` / `conso_lag7`, niveaux récents, météo observée de J). Les colonnes `parf_*` forment la variante « météo parfaite ». Sortie : `data/processed/cas_horaires.rds` ; listes de variables : `variables_modele.rds`.
- Contrôles qualité C1 à C9b : `src/02b_controles.R` (tableaux dans `results/`). Exploration : `src/02c_exploration.R` (figures e01 à e09, période 2018-2024 uniquement).

Les données brutes ne sont pas versionnées (trop volumineuses) :
elles sont téléchargées par le script `01_download.R`.

## 3. Protocole d'évaluation

- Apprentissage : [période]
- Validation : [période]
- Test final : [période], utilisé une seule fois, à la fin
- Fréquence de ré-estimation : [fixe / glissante / extensive]
- Métriques : MAE, RMSE, erreur sur le total journalier, sur la valeur et l'heure de la pointe
- Les méthodes sont comparées sur les mêmes dates et avec la même information.

## 4. Modèles comparés

| Modèle | Rôle | Fichier |
|---|---|---|
| Veille (même heure) | Benchmark | `src/04_benchmarks.R` |
| Même jour semaine précédente | Benchmark | `src/04_benchmarks.R` |
| [Régression simple] | Modèle simple | `src/05_models.R` |
| [Modèle élaboré] | Modèle plus complexe | `src/05_models.R` |

## 5. Installation

Prérequis : R (version 4.4.1 ou supérieure) et RStudio.

1. Cloner le dépôt :
   `git clone https://github.com/MajFall/projet-prevision-electricite.git`
2. Ouvrir `projet-prevision-electricite.Rproj` dans RStudio.
3. Dans la console R, installer les versions exactes des packages :
   `install.packages("renv"); renv::restore()`

## 6. Ordre d'exécution

Tout lancer : `source("run_all.R")`

Ou étape par étape (toujours depuis la racine du projet) :

| Étape | Script | Rôle | Durée approx. |
|---|---|---|---|
| 1 | `src/01_download.R` | Téléchargement des données | [long] |
| 2 | `src/02_prepare.R` | Nettoyage, pas horaire, agrégation | [x min] |
| 2b | `src/02b_controles.R` | Contrôles qualité C1 à C9b | [x min] |
| 2c | `src/02c_exploration.R` | Figures d'exploration e01 à e09 | [x min] |
| 3 | `src/03_features.R` | Variables calendaires, retards, météo | [x min] |
| 4 | `src/04_benchmarks.R` | Benchmarks | [x min] |
| 5 | `src/05_models.R` | Apprentissage et prévisions | [long] |
| 6 | `src/06_evaluate.R` | Métriques, figures, tableaux | [x min] |

## 7. Organisation des fichiers

```
├── README.md
├── projet-prevision-electricite.Rproj
├── renv.lock               # versions exactes des packages
├── run_all.R               # lance toute la chaîne
├── data/
│   ├── raw/                # données brutes (non versionnées)
│   └── processed/          # données préparées (non versionnées)
├── src/                    # scripts numérotés, dans l'ordre d'exécution
├── notebooks/              # exploration
├── results/                # figures et tableaux produits par le code
├── report/                 # rapport et diapositives
└── Docs/                   # sujet, tableau de disponibilité, journal d'usage de l'IA
```

## 8. Étapes coûteuses

- Téléchargement des données : connexion nécessaire ; un fichier éCO2mix et un fichier SYNOP par mois (96 fichiers) ; [durée à renseigner]. Le script saute les fichiers déjà valides.
- Entraînement des modèles : [durée]
- Résultats mis en cache : [oui/non, où]

## 9. Reproductibilité

- Graine aléatoire fixée avec `set.seed([valeur])`.
- Dépendances ajoutées par l'étape données : `ggplot2`, `scales` (lancer `renv::snapshot()` après installation).
- Horodatages traités en UTC, convertis en heure locale uniquement pour le calendrier.
- Statistiques de transformation (moyennes, écarts-types) calculées sur l'apprentissage seulement.
- Tableau de disponibilité des variables : `Docs/disponibilite_variables.md`.

## 10. Usage d'outils d'IA

Les usages sont consignés dans `Docs/journal_usage_ia.md`
(trois exemples documentés dans le rapport).
