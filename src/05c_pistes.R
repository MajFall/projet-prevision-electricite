# =====================================================================
# 05c_pistes.R : pistes exploratoires, jugées sur la VALIDATION uniquement
# (le test 2025 n'est pas utilisé ; 06_evaluate.R n'est pas modifié).
#
# Trois questions :
#  A) n_zones_vacances apporte-t-elle quelque chose ? (ablation promise au rapport)
#  B) lendemain_ferie / veille_ferie : le dimanche après un férié du samedi
#     (cas du 2 novembre 2025) est-il mal traité ? -> on ne les active que les jours ouvrés
#  C) creux_fin_annee : 24-26 décembre et 27-31 décembre ont-ils le même niveau ?
#
# Deux évaluations hors échantillon, pour ne pas juger sur une seule année :
#  - validation 2024 (apprentissage 2018-2023, comme le pipeline)
#  - 2023 (apprentissage 2018-2022), simple contrôle supplémentaire
# Hyperparamètres inchangés ; aucun réglage. Résultats = pistes, pas des modèles retenus.
# =====================================================================
if (!file.exists("src/00_config.R"))
  stop("Lancer depuis la racine du projet (ouvrir le .Rproj).")
source("src/config.R"); source("src/utils_metrics.R"); source("src/utils_bench.R")
library(xgboost)

cas  <- readRDS(file.path(DIR_PROC, "cas_horaires.rds"))
VARS <- readRDS(file.path(DIR_PROC, "variables_modele.rds"))

# ---- Variables dérivées (calculées ici, 03_features.R n'est pas touché) ----
cas <- cas |> mutate(
  chauf_24 = pmax(16 - temp_moy_24h, 0), clim_24 = pmax(temp_moy_24h - 20, 0),
  chauf_72 = pmax(16 - temp_moy_72h, 0),
  chauf_der = pmax(16 - temp_derniere, 0), clim_der = pmax(temp_derniere - 20, 0),
  # B) les lendemains / veilles de férié comptent seulement un jour de semaine
  lend_ouvre  = lendemain_ferie & !weekend,
  veille_ouvre = veille_ferie   & !weekend,
  # C) fin d'année en deux blocs
  fa_noel = mois == 12 & mday(date_cible) >= 24 & mday(date_cible) <= 26,
  fa_fin  = mois == 12 & mday(date_cible) >= 27)

termes_base <- paste(
  "factor(h_loc) * factor(jour_sem) + factor(mois)",
  "+ ferie + pont + veille_ferie + lendemain_ferie + creux_fin_annee",
  "+ n_zones_vacances + conso_lag7 + conso_derniere + conso_moy_7j",
  "+ chauf_24 + clim_24 + chauf_72 + chauf_der + clim_der")

variantes_lm <- list(
  base              = termes_base,
  sans_vacances     = sub("+ n_zones_vacances ", "", termes_base, fixed = TRUE),
  ferie_jours_ouvres = sub("veille_ferie + lendemain_ferie", "veille_ouvre + lend_ouvre",
                           termes_base, fixed = TRUE),
  fin_annee_2_blocs = sub("creux_fin_annee", "fa_noel + fa_fin", termes_base, fixed = TRUE))
variantes_lm$ferie_et_fin_annee <- sub("creux_fin_annee", "fa_noel + fa_fin",
  sub("veille_ferie + lendemain_ferie", "veille_ouvre + lend_ouvre", termes_base, fixed = TRUE),
  fixed = TRUE)

# Garde-fou anti-fuite : aucune variable "parf_*" dans les formules
stopifnot(!any(grepl("parf", unlist(variantes_lm))))

fit_lm <- function(train, valid, termes, nom) {
  fm <- lm(as.formula(paste("conso_cible ~", termes, "+ conso_lag1")),
           data = filter(train, h_loc <= LAST_KNOWN_HOUR))
  fa <- lm(as.formula(paste("conso_cible ~", termes)),
           data = filter(train, h_loc > LAST_KNOWN_HOUR))
  stopifnot(!anyNA(coef(fm)), !anyNA(coef(fa)))
  i <- valid$h_loc <= LAST_KNOWN_HOUR
  p <- rep(NA_real_, nrow(valid))
  p[i]  <- predict(fm, newdata = valid[i, ])
  p[!i] <- predict(fa, newdata = valid[!i, ])
  to_fc(valid, p, paste0("lm_", nom))
}

to_mat <- function(d, v) as.matrix(mutate(select(d, all_of(v)), across(everything(), as.numeric)))
params_xgb <- list(objective = "reg:squarederror", eta = 0.05, max_depth = 6,
                   subsample = 0.8, colsample_bytree = 0.8, nthread = 2, seed = 123)
fit_xgb <- function(train, valid, v, nom) {
  set.seed(123)
  m <- xgb.train(params = params_xgb, nrounds = 400, verbose = 0,
                 data = xgb.DMatrix(data = to_mat(train, v), label = train$conso_cible))
  to_fc(valid, predict(m, xgb.DMatrix(data = to_mat(valid, v))), paste0("xgb_", nom))
}
vars_xgb <- c(VARS$calendrier, VARS$retards, VARS$meteo_operationnelle)
stopifnot(!any(grepl("^parf_", vars_xgb)))

evaluer <- function(train, valid, etiquette) {
  fc_lm <- bind_rows(lapply(names(variantes_lm), function(n)
    fit_lm(train, valid, variantes_lm[[n]], n)))
  fc <- bind_rows(
    fc_lm,
    fit_xgb(train, valid, vars_xgb, "base"),
    fit_xgb(train, valid, setdiff(vars_xgb, "n_zones_vacances"), "sans_vacances"))
  stopifnot(n_distinct(fc$model) == length(variantes_lm) + 2)   # toutes les variantes présentes
  fcc <- common_rows(fc)

  # Erreur globale
  glob <- summarise_models(fcc) |> mutate(evaluation = etiquette, .before = 1)

  # Erreur ciblée : jours concernés par les pistes B et C
  cal <- valid |> distinct(target_date = date_cible, lendemain_ferie, veille_ferie, weekend, mois, fa = creux_fin_annee)
  cible <- fcc |> left_join(cal, by = "target_date") |>
    mutate(groupe = case_when(
      fa ~ "fin_annee_24dec_1jan",
      (lendemain_ferie | veille_ferie) & weekend ~ "weekend_autour_d_un_ferie",
      (lendemain_ferie | veille_ferie) ~ "jour_ouvre_autour_d_un_ferie",
      TRUE ~ "autres")) |>
    group_by(model, groupe) |>
    summarise(MAE = round(mean(abs(y_pred - y_true))), n_jours = n_distinct(target_date), .groups = "drop") |>
    mutate(evaluation = etiquette, .before = 1)
  list(global = glob, cible = cible)
}

# ---- Évaluation 1 : validation 2024 (protocole du projet) -----------------
train1 <- cas |> filter(utilise_apprentissage, !is.na(conso_cible))
valid1 <- cas |> filter(jeu == "validation", score_principal)
r1 <- evaluer(train1, valid1, "validation_2024")

# ---- Évaluation 2 : 2023, apprentissage 2018-2022 -----------------------------
train2 <- train1 |> filter(date_cible <= as.Date("2022-12-31"))
valid2 <- cas |> filter(year(date_cible) == 2023, score_principal, !is.na(conso_cible))
r2 <- evaluer(train2, valid2, "controle_2023")

glob  <- bind_rows(r1$global, r2$global) |>
  select(evaluation, model, MAE, RMSE, MAE_total_jour, MAE_pointe) |>
  mutate(across(where(is.numeric), ~ round(.x)))
cible <- bind_rows(r1$cible, r2$cible)
write_csv(glob,  file.path(DIR_OUT, "b06_pistes_global.csv"))
write_csv(cible, file.path(DIR_OUT, "b06_pistes_jours_cibles.csv"))

cat("\n== Erreur globale (MW) ; base = modèle du projet ==\n"); print(as.data.frame(glob))
cat("\n== Erreur selon le type de jour (MAE, MW) ==\n")
print(as.data.frame(cible |> select(-n_jours) |>
      pivot_wider(names_from = groupe, values_from = MAE)))
cat("\nNombre de journées par groupe :\n")
print(as.data.frame(cible |> filter(model == "lm_base") |> select(evaluation, groupe, n_jours)))
cat("\nLecture : une piste n'est intéressante que si elle améliore la MAE globale",
    "dans LES DEUX évaluations. Sinon, on la note comme essai non concluant.\n")
