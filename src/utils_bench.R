# =====================================================================
# utils_bench.R : benchmarks simples (prévisions sans apprentissage)
# =====================================================================

library(dplyr)

# load_hourly  : table avec les colonnes  date, hour, load  (consommation réelle)
# origin_dates : les jours J à prévoir
# rule         : function(J, h) -> date de la valeur passée à recopier
#                (pour prévoir l'heure h de J+1)
bench_forecast <- function(load_hourly, origin_dates, rule, model_name) {
  
  grid <- expand.grid(origin_date = origin_dates, hour = 0:23) |>
    as_tibble() |>
    mutate(target_date = origin_date + 1,
           src_date    = rule(origin_date, hour))   # jour dont on recopie la valeur
  
  # GARDE-FOU ANTI-FUITE : la valeur recopiée doit être connue à 14h le jour J
  #   soit un jour antérieur à J,
  #   soit le jour J lui-même, mais seulement jusqu'à LAST_KNOWN_HOUR.
  stopifnot(all(grid$src_date < grid$origin_date |
                  (grid$src_date == grid$origin_date & grid$hour <= LAST_KNOWN_HOUR)))
  
  res <- grid |>
    left_join(load_hourly |> rename(y_true = load),
              by = c("target_date" = "date", "hour")) |>
    left_join(load_hourly |> rename(y_pred = load),
              by = c("src_date" = "date", "hour")) |>
    transmute(origin_date, target_date, hour, model = model_name, y_true, y_pred)
  
  res
}

# Benchmark 1 : "veille"
# Heures <= LAST_KNOWN_HOUR : valeur du jour J (la veille de J+1), connue.
# Heures suivantes : le jour J n'est pas encore observé, on prend J-1.
rule_veille <- function(J, h) if_else(h <= LAST_KNOWN_HOUR, J, J - 1)

# Benchmark 2 : même jour de la semaine, la semaine précédente
# J+1 moins 7 jours = J-6, toujours connu à 14h.
rule_semaine <- function(J, h) J - 6