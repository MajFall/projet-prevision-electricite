# Lance toute la chaîne dans l'ordre (depuis la racine du projet)
source("src/01_download.R")      # ~2,5 min, connexion nécessaire
source("src/02_prepare.R")       # ~30 s
source("src/02b_controles.R")    # contrôles qualité
source("src/02c_exploration.R")  # figures d'exploration
source("src/02d_sensibilite_poids.R")  # sensibilité aux poids des stations
source("src/03_features.R")      # ~15 s
source("src/04_benchmarks.R")    # ~5 s
source("src/05_models.R")        # ~11 s
source("src/05b_ablation.R")     # ablation par groupes de variables
source("src/05c_pistes.R")       # pistes exploratoires (validation seulement)

# Test 2025 : exécuté UNE seule fois (trace : results/TEST_2025_EXECUTE.txt).
# run_all ne le relance que s'il n'a jamais été exécuté.
# (Pour une vérification de reproductibilité, le faire à la main, hors run_all :
#  Sys.setenv(REFAIRE_TEST = "1"); source("src/06_evaluate.R"), puis ne rien modifier.)
if (!file.exists("results/TEST_2025_EXECUTE.txt")) {
  source("src/06_evaluate.R")      # ~16 s
} else message("Test 2025 déjà exécuté : non relancé (voir README).")

# Analyse des erreurs du test : relit les prévisions enregistrées, ne réestime rien.
if (file.exists("data/processed/prev_test_2025.rds")) {
  source("src/07_analyse_echecs.R")
} else message("Prévisions du test absentes : 07 non lancé (voir README, section 8).")
