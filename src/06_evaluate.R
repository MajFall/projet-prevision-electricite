# =====================================================================
# 06_evaluate.R : ÉVALUATION FINALE SUR LE TEST 2025 (UNE SEULE EXÉCUTION)
# Protocole figé AVANT d'ouvrir le test :
#  - modèle retenu (déclaré d'avance) : lm_meteo_oper ; concurrent : xgb_meteo_oper
#  - un seul refit sur 2018-2024 (hors confinement), mêmes formules et hyperparamètres
#  - aucune réestimation pendant 2025, aucune modification après lecture des résultats
# =====================================================================
if (!file.exists("src/00_config.R"))
  stop("Lancer depuis la racine du projet (ouvrir le .Rproj).")
source("src/config.R"); source("src/utils_metrics.R"); source("src/utils_bench.R")
library(xgboost); library(ggplot2)

trace_file <- file.path(DIR_OUT, "TEST_2025_EXECUTE.txt")
if (file.exists(trace_file) && Sys.getenv("REFAIRE_TEST") != "1")
  stop("Le test 2025 a déjà été exécuté (", trace_file, "). Ne pas le relancer pour ",
       "modifier un modèle. Pour une simple vérification de reproductibilité : ",
       'Sys.setenv(REFAIRE_TEST = "1")')

cas  <- readRDS(file.path(DIR_PROC, "cas_horaires.rds"))
VARS <- readRDS(file.path(DIR_PROC, "variables_modele.rds"))

# Apprentissage final = apprentissage (hors confinement) + validation 2024
train <- cas |> filter(utilise_apprentissage | jeu == "validation", !is.na(conso_cible))
test  <- cas |> filter(jeu == "test", score_principal)
# GARDE-FOUS : rien du test dans l'apprentissage, pas de confinement
stopifnot(!any(train$jeu == "test"), max(train$date_cible) <= FIN_VALIDATION,
          !any(train$confinement), min(test$date_cible) > FIN_VALIDATION)

# ---- Benchmarks (sans apprentissage) --------------------------------
fc_bench <- bind_rows(to_fc(cas, bench_veille(cas),  "veille"),
                      to_fc(cas, bench_semaine(cas), "semaine_precedente")) |>
  filter(jeu == "test", score_principal)

# ---- Modèles linéaires (mêmes formules que 05_models.R) -------------
termes <- paste(
  "factor(h_loc) * factor(jour_sem) + factor(mois)",
  "+ ferie + pont + veille_ferie + lendemain_ferie + creux_fin_annee",
  "+ n_zones_vacances + conso_lag7 + conso_derniere + conso_moy_7j")
add_meteo <- function(d) d |> mutate(
  chauf_24  = pmax(16 - temp_moy_24h, 0),  clim_24  = pmax(temp_moy_24h - 20, 0),
  chauf_72  = pmax(16 - temp_moy_72h, 0),
  chauf_der = pmax(16 - temp_derniere, 0), clim_der = pmax(temp_derniere - 20, 0),
  chauf_parf = pmax(16 - parf_temp_horaire, 0), clim_parf = pmax(parf_temp_horaire - 20, 0),
  chauf_parf_jour = pmax(16 - parf_temp_moy_jour, 0))
train2 <- add_meteo(train); test2 <- add_meteo(test)

fit_lm <- function(extra, nom) {
  f_m <- as.formula(paste("conso_cible ~", termes, extra, "+ conso_lag1"))
  f_a <- as.formula(paste("conso_cible ~", termes, extra))
  fm <- lm(f_m, data = filter(train2, h_loc <= LAST_KNOWN_HOUR))
  fa <- lm(f_a, data = filter(train2, h_loc >  LAST_KNOWN_HOUR))
  stopifnot(!anyNA(coef(fm)), !anyNA(coef(fa)))
  i_m <- test2$h_loc <= LAST_KNOWN_HOUR
  p <- rep(NA_real_, nrow(test2))
  p[i_m]  <- predict(fm, newdata = test2[i_m, ])
  p[!i_m] <- predict(fa, newdata = test2[!i_m, ])
  to_fc(test2, p, nom)
}
extra_oper <- "+ chauf_24 + clim_24 + chauf_72 + chauf_der + clim_der"
extra_parf <- paste(extra_oper, "+ chauf_parf + clim_parf + chauf_parf_jour")
stopifnot(!grepl("parf", extra_oper))   # l'opérationnel n'utilise aucune météo de J+1

fc_lm <- bind_rows(fit_lm("", "lm_calendrier_retards"),
                   fit_lm(extra_oper, "lm_meteo_oper"),
                   fit_lm(extra_parf, "lm_meteo_parfaite"))

# ---- xgboost (mêmes hyperparamètres que 05_models.R, fixés a priori) -
vars_oper <- c(VARS$calendrier, VARS$retards, VARS$meteo_operationnelle)
vars_parf <- c(vars_oper, VARS$meteo_parfaite)
stopifnot(!any(grepl("^parf_", vars_oper)))
to_mat <- function(d, v) as.matrix(mutate(select(d, all_of(v)), across(everything(), as.numeric)))
params_xgb <- list(objective = "reg:squarederror", eta = 0.05, max_depth = 6,
                   subsample = 0.8, colsample_bytree = 0.8, nthread = 2, seed = 123)
fit_xgb <- function(v, nom) {
  m <- xgb.train(params = params_xgb, nrounds = 400, verbose = 0,
                 data = xgb.DMatrix(data = to_mat(train, v), label = train$conso_cible))
  to_fc(test, predict(m, xgb.DMatrix(data = to_mat(test, v))), nom)
}
fc_xgb <- bind_rows(fit_xgb(vars_oper, "xgb_meteo_oper"), fit_xgb(vars_parf, "xgb_meteo_parfaite"))

# ---- Enregistrement : toute analyse ultérieure relit ce fichier -----
fc <- bind_rows(fc_bench, fc_lm, fc_xgb)
saveRDS(fc, file.path(DIR_PROC, "prev_test_2025.rds"))
writeLines(c(paste("Test 2025 exécuté le", format(Sys.time())),
             "Prévisions : data/processed/prev_test_2025.rds"), trace_file)

# ---- Résultats -------------------------------------------------------
fcc <- common_rows(fc)
cal <- cas |> distinct(date_cible, weekend, ferie, mois)
fc2 <- fcc |> left_join(cal, by = c("target_date" = "date_cible")) |>
  mutate(type_jour = case_when(ferie ~ "ferie", weekend ~ "weekend", TRUE ~ "semaine"),
         saison = case_when(mois %in% c(12, 1, 2) ~ "hiver", mois %in% 3:5 ~ "printemps",
                            mois %in% 6:8 ~ "ete", TRUE ~ "automne"))

met <- summarise_models(fcc)
biais <- fcc |> group_by(model) |> summarise(biais_moyen = mean(y_pred - y_true))
met <- left_join(met, biais, by = "model")
write.csv(met, file.path(DIR_OUT, "t01_metriques_test.csv"), row.names = FALSE)
print(met, width = Inf)

par_groupe <- function(var) fc2 |> group_by(model, g = .data[[var]]) |>
  summarise(MAE = round(mae(y_true, y_pred)), .groups = "drop") |>
  pivot_wider(names_from = g, values_from = MAE)
write.csv(par_groupe("type_jour"), file.path(DIR_OUT, "t02_mae_type_jour_test.csv"), row.names = FALSE)
write.csv(par_groupe("saison"),    file.path(DIR_OUT, "t03_mae_saison_test.csv"), row.names = FALSE)
write.csv(par_groupe("hour"),      file.path(DIR_OUT, "t04_mae_heure_test.csv"), row.names = FALSE)
print(par_groupe("type_jour"), width = Inf); print(par_groupe("saison"), width = Inf)

pires <- fcc |> filter(model %in% c("lm_meteo_oper", "xgb_meteo_oper")) |>
  group_by(model, target_date) |>
  summarise(MAE_jour = round(mae(y_true, y_pred)), biais = round(mean(y_pred - y_true)),
            .groups = "drop") |>
  group_by(model) |> slice_max(MAE_jour, n = 8) |> ungroup() |>
  mutate(jour = weekdays(target_date)) |> arrange(model, desc(MAE_jour))
write.csv(pires, file.path(DIR_OUT, "t05_pires_jours_test.csv"), row.names = FALSE)
print(pires, n = 20)

try({
  ggsave(file.path(DIR_OUT, "t01_mae_modeles_test.png"), width = 7, height = 4, dpi = 150,
         ggplot(met, aes(reorder(model, MAE), MAE)) + geom_col() + coord_flip() +
           labs(x = NULL, y = "MAE (MW)", title = "MAE sur le test 2025"))
  ggsave(file.path(DIR_OUT, "t02_mae_heure_test.png"), width = 8, height = 4.5, dpi = 150,
         fcc |> group_by(model, hour) |> summarise(MAE = mae(y_true, y_pred), .groups = "drop") |>
           ggplot(aes(hour, MAE, colour = model)) + geom_line() +
           labs(x = "Heure", y = "MAE (MW)", title = "MAE par heure, test 2025"))
})