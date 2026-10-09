# =====================================================================
# config.R : paramètres propres à l'évaluation
# Les dates et latences viennent de 00_config.R (source unique de vérité)
# =====================================================================
source("src/00_config.R")

PERIODS <- list(
  train_start = DATE_DEBUT,
  train_end   = FIN_APPRENTISSAGE,
  valid_end   = FIN_VALIDATION,
  test_end    = DATE_FIN
)

# Dernière heure de J connue à 14h : l'heure h finit à h+1, et elle n'est
# utilisable qu'après LATENCE_CONSO_H. Avec 14, 1 et 1 on obtient 12.
LAST_KNOWN_HOUR <- ORIGINE_HEURE_LOCALE - LATENCE_CONSO_H - 1