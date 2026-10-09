# =====================================================================
# utils_metrics.R : fonctions de métriques d'évaluation
# Utilisé par les scripts 04_benchmarks.R, 05_models.R, 06_evaluate.R
# Ce fichier ne fait que DÉFINIR des fonctions, il n'exécute rien.
# =====================================================================

library(dplyr)   # fournit group_by, summarise, mutate, left_join

# ---------------------------------------------------------------------
# Format attendu des prévisions (une ligne par modèle, jour prévu, heure) :
#   model        : nom du modèle (ex. "veille", "lm_calendrier")
#   target_date  : le jour prévu (J+1)
#   hour         : l'heure prévue, de 0 à 23
#   y_true       : consommation réelle
#   y_pred       : consommation prévue
# ---------------------------------------------------------------------


# ---- Erreurs sur les valeurs horaires --------------------------------

# MAE = moyenne des écarts en valeur absolue.
# Donne l'erreur "typique", dans la même unité que la consommation (MW).
mae  <- function(y, yhat) mean(abs(y - yhat))

# RMSE = racine de la moyenne des écarts au carré.
# Le carré donne plus de poids aux gros écarts : un RMSE bien supérieur
# au MAE signale quelques erreurs importantes.
rmse <- function(y, yhat) sqrt(mean((y - yhat)^2))


# ---- Erreurs journalières --------------------------------------------

# Pour chaque modèle et chaque jour prévu, calcule :
#   - le total de la journée (somme des 24 heures)
#   - la valeur de la pointe (maximum de la journée)
#   - l'heure de la pointe
# puis les erreurs signées (prévu - réel) :
#   positif = surestimation, négatif = sous-estimation.
daily_metrics <- function(df) {
  df |>
    # un "paquet" par couple (modèle, jour) : 24 lignes par paquet
    group_by(model, target_date) |>
    # réduit chaque paquet à une seule ligne
    summarise(
      total_true = sum(y_true),             total_pred = sum(y_pred),
      peak_true  = max(y_true),             peak_pred  = max(y_pred),
      # which.max donne la POSITION du maximum, hour[...] l'heure associée
      hpeak_true = hour[which.max(y_true)], hpeak_pred = hour[which.max(y_pred)],
      .groups = "drop"                      # retire le groupement après calcul
    ) |>
    # ajoute les colonnes d'erreurs signées
    mutate(
      err_total = total_pred - total_true,  # erreur sur le volume de la journée
      err_peak  = peak_pred  - peak_true,   # erreur sur la valeur de la pointe
      err_hpeak = hpeak_pred - hpeak_true   # erreur en heures sur l'heure de la pointe
    )
}


# ---- Tableau récapitulatif par modèle --------------------------------

# Renvoie une ligne par modèle avec toutes les métriques,
# prêt à être mis dans la section "Résultats" du rapport.
summarise_models <- function(df) {
  
  # 1) métriques calculées sur toutes les valeurs horaires
  hourly <- df |>
    group_by(model) |>
    summarise(MAE = mae(y_true, y_pred), RMSE = rmse(y_true, y_pred), .groups = "drop")
  
  # 2) métriques journalières, moyennées par modèle
  #    (valeur absolue : sinon surestimations et sous-estimations s'annulent)
  daily <- daily_metrics(df) |>
    group_by(model) |>
    summarise(MAE_total_jour   = mean(abs(err_total)),   # erreur moyenne sur le total journalier
              MAE_pointe       = mean(abs(err_peak)),    # erreur moyenne sur la valeur de la pointe
              MAE_heure_pointe = mean(abs(err_hpeak)),   # erreur moyenne (en heures) sur l'heure de la pointe
              .groups = "drop")
  
  # 3) assemble les deux tableaux côte à côte, aligné sur la colonne "model"
  left_join(hourly, daily, by = "model")
}

# ---- Lignes communes à tous les modèles -------------------------------
# Retire les JOURNÉES où au moins une prévision ou une cible manque,
# pour TOUS les modèles à la fois : les modèles sont ainsi comparés
# sur exactement les mêmes dates, avec 24 heures par journée.
common_rows <- function(df) {
  jours_ko <- df |>
    filter(is.na(y_pred) | is.na(y_true)) |>
    distinct(target_date)
  out <- df |> anti_join(jours_ko, by = "target_date")
  message(nrow(jours_ko), " journée(s) retirée(s) pour tous les modèles")
  chk <- out |> count(model, target_date)
  stopifnot(all(chk$n == 24))      # chaque journée gardée a bien 24 heures
  out
}