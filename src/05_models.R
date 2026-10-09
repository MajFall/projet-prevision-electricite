# =====================================================================
# 05_models.R : modèles avec apprentissage, évalués sur la validation
# Le test (2025) n'est PAS utilisé ici.
# =====================================================================
if (!file.exists("src/00_config.R"))
  stop("Lancer depuis la racine du projet (ouvrir le .Rproj).")
source("src/config.R"); source("src/utils_metrics.R"); source("src/utils_bench.R")

cas  <- readRDS(file.path(DIR_PROC, "cas_horaires.rds"))
VARS <- readRDS(file.path(DIR_PROC, "variables_modele.rds"))

# Apprentissage : hors confinement, et seulement les lignes avec une cible
train <- cas |> filter(utilise_apprentissage, !is.na(conso_cible))
valid <- cas |> filter(jeu == "validation", score_principal)

# ---- Modèle 1 : calendrier + retards (sans météo) -------------------
# Profil horaire différent selon le jour de la semaine (h_loc x jour_sem),
# plus mois, jours spéciaux, vacances et quelques retards de consommation.
termes <- paste(
  "factor(h_loc) * factor(jour_sem) + factor(mois)",
  "+ ferie + pont + veille_ferie + lendemain_ferie + creux_fin_annee",
  "+ n_zones_vacances + conso_lag7 + conso_derniere + conso_moy_7j")
f_matin <- as.formula(paste("conso_cible ~", termes, "+ conso_lag1"))  # h <= 12
f_apres <- as.formula(paste("conso_cible ~", termes))                  # h > 12 (lag1 absent)

# GARDE-FOUS ANTI-FUITE : uniquement des variables opérationnelles
vars_utilisees <- setdiff(unique(c(all.vars(f_matin), all.vars(f_apres))), "conso_cible")
stopifnot(all(vars_utilisees %in% c(VARS$calendrier, VARS$retards, VARS$meteo_operationnelle)))
stopifnot(!any(grepl("^parf_", vars_utilisees)))

fit_m <- lm(f_matin, data = filter(train, h_loc <= LAST_KNOWN_HOUR))
fit_a <- lm(f_apres, data = filter(train, h_loc >  LAST_KNOWN_HOUR))
stopifnot(!anyNA(coef(fit_m)), !anyNA(coef(fit_a)))   # pas de colinéarité parfaite

i_m  <- valid$h_loc <= LAST_KNOWN_HOUR
pred <- rep(NA_real_, nrow(valid))
pred[i_m]  <- predict(fit_m, newdata = valid[i_m, ])
pred[!i_m] <- predict(fit_a, newdata = valid[!i_m, ])

cat("MAE sur l'apprentissage (contrôle de sur-ajustement) : h<=12 =",
    round(mean(abs(residuals(fit_m))), 0), "; h>12 =", round(mean(abs(residuals(fit_a))), 0), "\n")

# ---- Comparaison avec les benchmarks, sur les MÊMES journées --------
bench  <- readRDS(file.path(DIR_PROC, "prev_benchmarks_validation.rds"))
fc_all <- bind_rows(bench, to_fc(valid, pred, "lm_calendrier_retards"))
saveRDS(fc_all, file.path(DIR_PROC, "prev_modeles_validation.rds"))

res <- summarise_models(common_rows(fc_all))
write.csv(res, file.path(DIR_OUT, "b02_metriques_modeles_validation.csv"), row.names = FALSE)
print(res)

# =====================================================================
# Modèles 2 et 3 : + température (opérationnelle, puis "parfaite")
# =====================================================================
add_meteo <- function(d) d |> mutate(
  # opérationnel : température observée AVANT 14h le jour J
  chauf_24  = pmax(16 - temp_moy_24h, 0),  clim_24  = pmax(temp_moy_24h - 20, 0),
  chauf_72  = pmax(16 - temp_moy_72h, 0),
  chauf_der = pmax(16 - temp_derniere, 0), clim_der = pmax(temp_derniere - 20, 0),
  # parfaite : température OBSERVÉE de J+1 (borne de performance, non déployable)
  chauf_parf = pmax(16 - parf_temp_horaire, 0), clim_parf = pmax(parf_temp_horaire - 20, 0),
  chauf_parf_jour = pmax(16 - parf_temp_moy_jour, 0)
)
train2 <- add_meteo(train)
valid2 <- add_meteo(valid)

fit_pred <- function(extra, nom) {
  f_m <- as.formula(paste("conso_cible ~", termes, extra, "+ conso_lag1"))
  f_a <- as.formula(paste("conso_cible ~", termes, extra))
  fm <- lm(f_m, data = filter(train2, h_loc <= LAST_KNOWN_HOUR))
  fa <- lm(f_a, data = filter(train2, h_loc >  LAST_KNOWN_HOUR))
  stopifnot(!anyNA(coef(fm)), !anyNA(coef(fa)))
  i_m <- valid2$h_loc <= LAST_KNOWN_HOUR
  p <- rep(NA_real_, nrow(valid2))
  p[i_m]  <- predict(fm, newdata = valid2[i_m, ])
  p[!i_m] <- predict(fa, newdata = valid2[!i_m, ])
  to_fc(valid2, p, nom)
}

extra_oper <- "+ chauf_24 + clim_24 + chauf_72 + chauf_der + clim_der"
extra_parf <- paste(extra_oper, "+ chauf_parf + clim_parf + chauf_parf_jour")

# GARDE-FOU : la variante opérationnelle ne doit contenir aucune colonne parf_*
# ni dérivée de parf_* (chauf_parf, clim_parf, chauf_parf_jour)
stopifnot(!grepl("parf", extra_oper))

fc_all2 <- bind_rows(
  fc_all,
  fit_pred(extra_oper, "lm_meteo_oper"),
  fit_pred(extra_parf, "lm_meteo_parfaite")
)
saveRDS(fc_all2, file.path(DIR_PROC, "prev_modeles_validation.rds"))

res2 <- summarise_models(common_rows(fc_all2))
write.csv(res2, file.path(DIR_OUT, "b03_metriques_meteo_validation.csv"), row.names = FALSE)
print(res2)

# =====================================================================
# Modèles 4 et 5 : gradient boosting (xgboost), même information que le linéaire
# Hyperparamètres FIXES, choisis a priori : la validation ne sert qu'à mesurer.
# =====================================================================
library(xgboost)
set.seed(123)

vars_oper <- c(VARS$calendrier, VARS$retards, VARS$meteo_operationnelle)
vars_parf <- c(vars_oper, VARS$meteo_parfaite)   # borne de performance uniquement

# GARDE-FOU : la variante opérationnelle ne contient aucune colonne parf_*
stopifnot(!any(grepl("^parf_", vars_oper)))

to_mat <- function(d, v) as.matrix(mutate(select(d, all_of(v)), across(everything(), as.numeric)))

params_xgb <- list(objective = "reg:squarederror", eta = 0.05, max_depth = 6,
                   subsample = 0.8, colsample_bytree = 0.8, nthread = 2)
NROUNDS <- 400

fit_xgb <- function(v, nom) {
  dtrain <- xgb.DMatrix(data = to_mat(train, v), label = train$conso_cible)
  m <- xgb.train(params = params_xgb, data = dtrain, nrounds = NROUNDS, verbose = 0)
  p <- predict(m, xgb.DMatrix(data = to_mat(valid, v)))
  list(model = m, fc = to_fc(valid, p, nom))
}

xo <- fit_xgb(vars_oper, "xgb_meteo_oper")
xp <- fit_xgb(vars_parf, "xgb_meteo_parfaite")

cat("\nVariables les plus utilisées (xgb_meteo_oper) :\n")
print(head(xgb.importance(model = xo$model), 10))

fc_all3 <- bind_rows(fc_all2, xo$fc, xp$fc)
saveRDS(fc_all3, file.path(DIR_PROC, "prev_modeles_validation.rds"))

res3 <- summarise_models(common_rows(fc_all3))
write.csv(res3, file.path(DIR_OUT, "b04_metriques_xgboost_validation.csv"), row.names = FALSE)
print(res3)