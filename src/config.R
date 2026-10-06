# =====================================================================
# config.R : paramètres du protocole, partagés par tous les scripts
# Dates PROVISOIRES : à fixer à deux avant de lancer les vraies expériences
# =====================================================================

PERIODS <- list(
  train_start = as.Date("2015-01-01"),  # début de l'apprentissage
  train_end   = as.Date("2021-12-31"),  # fin de l'apprentissage
  valid_end   = as.Date("2022-12-31"),  # fin de la validation
  test_end    = as.Date("2023-12-31")   # fin du test final
)