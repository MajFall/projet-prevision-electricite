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