# =====================================================================
# utils_bench.R : benchmarks sans apprentissage, sur la table cas_horaires
# =====================================================================
library(dplyr)

# Instant d'origine de prévision (14h locale, jour J = date_cible - 1)
origin_14h <- function(x) {
  as.POSIXct(paste(x$date_cible - 1, sprintf("%02d:00:00", ORIGINE_HEURE_LOCALE)),
             tz = TZ_LOCAL)
}

# GARDE-FOU ANTI-FUITE : la valeur recopiée (heure commençant à src_utc)
# n'est utilisable qu'après la fin de l'heure + la latence.
# Elle doit donc être disponible à 14h le jour J.
check_dispo <- function(x, src_utc) {
  ok <- is.na(src_utc) | x$jour_chgt_heure |
    (src_utc + (1 + LATENCE_CONSO_H) * 3600 <= origin_14h(x))
  stopifnot(all(ok))
  invisible(TRUE)
}

# Benchmark 1 : "veille"
# h <= LAST_KNOWN_HOUR : même heure que J (colonne conso_lag1, connue)
# h >  LAST_KNOWN_HOUR : J n'est pas encore observé, on prend J-1 (48 h avant la cible)
bench_veille <- function(x) {
  t_utc  <- as.numeric(x$heure_utc)
  prev48 <- x$conso_cible[match(t_utc - 48 * 3600, t_utc)]
  src    <- if_else(x$h_loc <= LAST_KNOWN_HOUR, x$heure_utc - 24 * 3600,
                    x$heure_utc - 48 * 3600)
  check_dispo(x, src)
  if_else(x$h_loc <= LAST_KNOWN_HOUR, x$conso_lag1, prev48)
}

# Benchmark 2 : même heure, même jour de la semaine, 7 jours avant (colonne conso_lag7)
bench_semaine <- function(x) {
  check_dispo(x, x$heure_utc - 7 * 24 * 3600)
  x$conso_lag7
}

# Met une prévision au format commun (celui attendu par utils_metrics.R)
to_fc <- function(x, y_pred, model_name) {
  x |> transmute(
    origin_date = date_cible - 1, target_date = date_cible, hour = h_loc,
    jeu, score_principal, model = model_name,
    y_true = conso_cible, y_pred = y_pred
  )
}