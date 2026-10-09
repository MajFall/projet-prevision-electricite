# Lance toute la chaîne dans l'ordre (depuis la racine du projet)
source("src/01_download.R")      # ~2,5 min, connexion nécessaire
source("src/02_prepare.R")       # ~30 s
source("src/02b_controles.R")    # contrôles qualité
source("src/02c_exploration.R")  # figures d'exploration
source("src/03_features.R")      # ~15 s
source("src/04_benchmarks.R")    # ~5 s
source("src/05_models.R")        # ~11 s
source("src/05b_ablation.R")     # ablation par groupes de variables

# Le test 2025 refuse de se relancer (garde-fou), et results/TEST_2025_EXECUTE.txt
# est versionné. Cette ligne sert UNIQUEMENT à vérifier la reproductibilité,
# jamais à modifier un modèle après lecture des résultats.
Sys.setenv(REFAIRE_TEST = "1")
source("src/06_evaluate.R")      # ~16 s