# Lance toute la chaîne dans l'ordre (depuis la racine : ouvrir le .Rproj)
source("src/01_download.R")    # long : téléchargement
source("src/02_prepare.R")
source("src/02b_controles.R")  # contrôles qualité C1-C9b -> results/
source("src/02c_exploration.R")# figures d'exploration e01-e09 (+ e06c, e08c) -> results/
source("src/03_features.R")
source("src/04_benchmarks.R")
source("src/05_models.R")      # long : entraînement
source("src/06_evaluate.R")
