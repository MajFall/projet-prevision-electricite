# =====================================================================
# utils_split.R : évaluation glissante simulant les prévisions de 14h
# =====================================================================

library(dplyr)

# Format de la table de données (une ligne par jour J et heure h de J+1) :
#   origin_date : le jour J (origine de prévision, 14h)
#   target_date : le jour J+1
#   hour        : heure prévue, 0 à 23
#   y           : consommation réelle de J+1 à l'heure h
#   + variables explicatives connues à 14h le jour J

# data         : la table ci-dessus
# origin_dates : les jours J à prévoir (ex. toutes les dates de la période de test)
# fit_fun      : function(train) -> modèle ajusté
# predict_fun  : function(fit, newdata) -> vecteur de 24 prévisions
# refit_every  : le modèle est réestimé tous les N jours d'origine
rolling_forecast <- function(data, origin_dates, fit_fun, predict_fun, model_name,
                             refit_every = 30, train_start = PERIODS$train_start) {
  out <- vector("list", length(origin_dates))
  fit <- NULL
  
  for (i in seq_along(origin_dates)) {
    J <- origin_dates[i]
    
    # Réestimation du modèle toutes les refit_every origines
    if (is.null(fit) || (i - 1) %% refit_every == 0) {
      # RÈGLE ANTI-FUITE : on n'apprend que sur des jours J+1 déjà COMPLETS
      # à 14h le jour J, c'est-à-dire target_date < J.
      # (target_date == J serait un jour dont l'après-midi n'est pas encore observé.)
      train <- data |>
        filter(target_date >= train_start, target_date < J,
               !(target_date >= CONFINEMENT_DEBUT & target_date <= CONFINEMENT_FIN))
      stopifnot(nrow(train) > 0, max(train$target_date) < J)
      fit <- fit_fun(train)
    }
    
    # Les 24 heures de J+1 à prévoir
    newdata <- data |> filter(origin_date == J)
    stopifnot(nrow(newdata) == 24, all(newdata$target_date == J + 1))
    
    out[[i]] <- tibble(
      origin_date = J, target_date = newdata$target_date, hour = newdata$hour,
      model = model_name, y_true = newdata$y,
      y_pred = predict_fun(fit, newdata)
    )
  }
  bind_rows(out)
}