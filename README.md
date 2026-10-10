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
- Poids des stations : `src/02d_sensibilite_poids.R` compare quatre jeux de poids (actuel, égaux, plafonnés à 3, racine) sur 2018-2024. Les poids actuels donnent la meilleure corrélation température-consommation en hiver ; ils sont conservés (`results/s01_sensibilite_poids.csv`).

Les données brutes ne sont pas versionnées (trop volumineuses) :
elles sont téléchargées par le script `01_download.R`.

## 3. Protocole d'évaluation

| Période | Dates | Usage |
|---|---|---|
| Apprentissage | 2018-01-01 → 2023-12-31, hors premier confinement (17/03 → 11/05/2020) | ajustement des modèles |
| Validation | 2024 | mesures et diagnostics, aucune sélection automatique |
| Test final | 2025 | exécuté **une seule fois** (`src/06_evaluate.R`) |

- **Réestimation :** sur la validation, chaque modèle est ajusté une fois sur l'apprentissage. Pour le test, un seul refit sur 2018-2024 (hors confinement), mêmes formules et mêmes hyperparamètres, sans réestimation pendant 2025.
- **Hyperparamètres :** xgboost avec des valeurs fixées a priori (`eta = 0.05`, `max_depth = 6`, 400 arbres, `subsample = 0.8`, `colsample_bytree = 0.8`), non réglées.
- **Métriques :** MAE, RMSE, erreur sur le total journalier, sur la valeur de la pointe et sur son heure (`src/utils_metrics.R`), détaillées par saison, type de jour et heure.
- **Mêmes dates pour tous :** `common_rows()` retire les journées où une prévision manque (2 journées en validation, 3 en test) pour **tous** les modèles. Les jours à 23 h ou 25 h sont hors du score principal.
- **Protection du test :** le modèle retenu (`lm_meteo_oper`) a été déclaré avant le test. Un tag Git `avant-test-2025` fige l'état précédent, et `06_evaluate.R` refuse de se relancer (fichier `results/TEST_2025_EXECUTE.txt`).

## 4. Modèles comparés

| Modèle | Rôle | Météo utilisée | Fichier |
|---|---|---|---|
| `veille` | Benchmark | aucune | `src/04_benchmarks.R` |
| `semaine_precedente` | Benchmark | aucune | `src/04_benchmarks.R` |
| `lm_calendrier_retards` | Modèle simple | aucune | `src/05_models.R` |
| `lm_meteo_oper` | **Modèle retenu** | observée avant 14 h le jour J | `src/05_models.R` |
| `xgb_meteo_oper` | Modèle élaboré (concurrent) | observée avant 14 h le jour J | `src/05_models.R` |
| `lm_meteo_parfaite`, `xgb_meteo_parfaite` | **Borne de performance, non déployable** | observée de J+1 | `src/05_models.R` |

- `veille` recopie l'heure de J jusqu'à 12 h (seule partie connue à 14 h) et J-1 au-delà.
- Les modèles linéaires sont ajustés séparément pour les heures ≤ 12 (avec `conso_lag1`) et > 12 (sans).
- Ablation par groupes de variables (xgboost) : `src/05b_ablation.R`.
- Pistes exploratoires (validation seulement, aucune retenue) : `src/05c_pistes.R`, voir section 11.

## 5. Installation

Prérequis : R (4.5.2 utilisé pour les résultats) et RStudio.

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
| 1 | `src/01_download.R` | Téléchargement des données | ~ 2 min 30 |
| 2 | `src/02_prepare.R` | Nettoyage, pas horaire, agrégation | ~ 28 s |
| 2b | `src/02b_controles.R` | Contrôles qualité C1 à C9b | ~ 12 s |
| 2c | `src/02c_exploration.R` | Figures d'exploration e01 à e09 | ~ 10 s |
| 2d | `src/02d_sensibilite_poids.R` | Sensibilité de la température aux poids des stations | < 1 min |
| 3 | `src/03_features.R` | Variables calendaires, retards, météo | ~ 14 s |
| 4 | `src/04_benchmarks.R` | Benchmarks | ~ 4,5 s |
| 5 | `src/05_models.R` | Apprentissage et prévisions | ~ 11 s |
| 5b | `src/05b_ablation.R` | Ablation météo / calendrier / retards | ~ 9 s |
| 5c | `src/05c_pistes.R` | Pistes exploratoires (vacances, fériés, fin d'année), validation 2024 et contrôle 2023 | < 1 min |
| 6 | `src/06_evaluate.R` | Test 2025 (une seule exécution), tableaux et figures | ~ 16 s |
| 7 | `src/07_analyse_echecs.R` | Analyse des erreurs du test 2025, à partir des prévisions déjà enregistrées | < 1 min |

## 7. Organisation des fichiers

```
├── README.md
├── projet-prevision-electricite.Rproj
├── renv.lock               # versions des packages
├── run_all.R               # lance toute la chaîne
├── data/                   # NON versionné (régénéré par les scripts)
│   ├── raw/                # eco2mix_cons_def.csv, calendrier_scolaire.csv, synop/ (96 fichiers)
│   └── processed/          # voir tableau ci-dessous
├── src/
│   ├── 00_config.R         # paramètres globaux (dates, latences, stations)
│   ├── 01_download.R … 03_features.R   # données et variables
│   ├── 02b_controles.R, 02c_exploration.R, 02d_sensibilite_poids.R
│   ├── 04_benchmarks.R, 05_models.R, 05b_ablation.R, 05c_pistes.R
│   ├── 06_evaluate.R, 07_analyse_echecs.R
│   ├── config.R            # paramètres d'évaluation (lit 00_config.R)
│   ├── utils_metrics.R     # métriques et lignes communes
│   ├── utils_bench.R       # benchmarks et garde-fous de disponibilité
│   └── utils_split.R       # évaluation glissante (essai, non utilisée dans la chaîne finale)
├── results/                # tableaux et figures (versionnés)
└── Docs/                   # sujet, tableau de disponibilité, journal IA, répartition
```

### Fichiers produits

| Fichier | Produit par | Contenu |
|---|---|---|
| `data/processed/master_horaire.rds` | `02_prepare.R` | grille horaire 2018-2025 |
| `data/processed/cas_horaires.rds`, `variables_modele.rds` | `03_features.R` | table de prévision et listes de variables |
| `data/processed/prev_benchmarks_validation.rds`, `prev_modeles_validation.rds` | `04`, `05` | prévisions sur la validation 2024 |
| `data/processed/prev_test_2025.rds` | `06_evaluate.R` | prévisions sur le test 2025 |
| `results/c*.csv`, `e*.png`, `f01_*.csv` | `02b`, `02c`, `03` | contrôles qualité, exploration, valeurs manquantes |
| `results/b01` à `b05` | `04`, `05`, `05b` | métriques sur la validation |
| `results/b06_*.csv` | `05c_pistes.R` | pistes exploratoires (validation 2024, contrôle 2023) |
| `results/s01_*.csv` | `02d_sensibilite_poids.R` | sensibilité aux poids des stations |
| `results/s02` à `s06`, `s05b` | `07_analyse_echecs.R` | analyse des erreurs du test (pires jours, météo, biais par mois, intervalles) |
| `results/t01` à `t05`, `TEST_2025_EXECUTE.txt` | `06_evaluate.R` | résultats du test et trace d'exécution |

## 8. Étapes coûteuses

- **Téléchargement :** ~2,5 min sur notre connexion, 96 fichiers SYNOP + éCO2mix (~16 Mo) ; connexion nécessaire. Les fichiers déjà valides ne sont pas retéléchargés.
- **Entraînement :** quelques secondes à ~15 s par script, rien de coûteux.
- **Test 2025 :** `06_evaluate.R` refuse de se relancer. `run_all.R` ne le relance pas s'il a déjà été exécuté ; une vérification de reproductibilité se fait à la main, hors `run_all.R`, sans rien modifier ensuite.

## 9. Reproductibilité

- Graine : `seed = 123` dans `params_xgb` (xgboost). Les modèles linéaires sont déterministes.
- Versions de R : tous les résultats du dépôt ont été obtenus avec R 4.5.2. Les versions de packages de `renv.lock` (dont `xgboost` 3.2.1.1 et `ggplot2` 4.0.3) sont celles de cette session ; le champ `R` du lockfile indique encore 4.4.1, sans conséquence sur les calculs. Avec une autre version de R, `renv::restore()` peut proposer des versions différentes : les résultats chiffrés pourraient alors varier légèrement.
- Horodatages traités en UTC, convertis en heure locale uniquement pour le calendrier.
- Les statistiques apprises (coefficients, arbres) viennent de l'apprentissage seulement ; la météo parfaite n'entre jamais dans les modèles opérationnels (garde-fous `stopifnot`).
- Tableau de disponibilité des variables : `Docs/disponibilite_variables.md`.

## 10. Usage d'outils d'IA

Les usages sont consignés dans `Docs/journal_usage_ia.md`
(trois exemples documentés dans le rapport).

## 11. Analyse des erreurs et pistes exploratoires

Ces deux étapes viennent **après** la lecture du test 2025. Elles n'ont modifié
ni les modèles, ni `06_evaluate.R`, ni les résultats du test.

- **Analyse des erreurs (`07_analyse_echecs.R`)** : relit les prévisions enregistrées du test. La météo réelle de J+1 sert ici à expliquer les erreurs, jamais à prévoir. Constats : la variation de température entre les 24 h avant 14 h et J+1 explique 8 des 10 pires journées ; les jours de forte variation (≥ 4 °C) ont une MAE de 2072 MW contre 1283 MW en temps stable ; le biais est positif en hiver, en 2024 (validation) comme en 2025 (test). Les écarts entre `xgb_meteo_oper` et `lm_meteo_oper` ne sont pas établis (intervalle bootstrap par journées contenant 0), sauf sur la pointe où xgboost est moins bon.
- **Pistes (`05c_pistes.R`)** : retirer `n_zones_vacances`, limiter `veille_ferie` / `lendemain_ferie` aux jours ouvrés, découper la fin d'année en deux blocs. Jugées sur la validation 2024 et sur un contrôle 2023. Aucune n'améliore nettement l'erreur : `lm_meteo_oper` reste le modèle retenu. Les gains sans les vacances (2 à 4 MW pour le linéaire) sont trop faibles pour conclure.
- Les cas de calendrier rares (2 novembre 2025, 26-31 décembre 2025) sont présentés comme une limite du modèle.
- Explication a posteriori de novembre 2025 : bulletin climatique de Météo-France (novembre 2025), jamais utilisé comme variable.
