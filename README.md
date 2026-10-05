# Prévision de la consommation électrique en France métropolitaine

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
| Calendrier | Heure, jour de semaine, mois, week-end, jours fériés, vacances | `src/03_features.R` |

- Période étudiée : [à compléter]
- Stations météo retenues et agrégation spatiale : [à compléter]
- Traitement des valeurs manquantes, changements d'heure, valeurs atypiques : [à compléter]

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

Prérequis : R (version [x.y]) et RStudio.

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
└── docs/                   # sujet, tableau de disponibilité, journal d'usage de l'IA
```

## 8. Étapes coûteuses

- Téléchargement des données : [durée, taille, connexion nécessaire]
- Entraînement des modèles : [durée]
- Résultats mis en cache : [oui/non, où]

## 9. Reproductibilité

- Graine aléatoire fixée avec `set.seed([valeur])`.
- Horodatages traités en UTC, convertis en heure locale uniquement pour le calendrier.
- Statistiques de transformation (moyennes, écarts-types) calculées sur l'apprentissage seulement.
- Tableau de disponibilité des variables : `docs/disponibilite_variables.md`.

## 10. Usage d'outils d'IA

Les usages sont consignés dans `docs/journal_usage_ia.md`
(trois exemples documentés dans le rapport).
