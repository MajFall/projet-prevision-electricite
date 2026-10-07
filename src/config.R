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

# Dernière heure de la journée J considérée comme connue à 14h le jour J.
# L'heure 13 se termine à 14h pile, et les données éCO2mix sont publiées avec
# un délai : on retient 12 par prudence. VALEUR PROVISOIRE, à confirmer
# avec le binôme en regardant le délai de publication réel.
LAST_KNOWN_HOUR <- 12