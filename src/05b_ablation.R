# =====================================================================
# 05b_ablation.R : apport de chaque groupe de variables (xgboost, météo opérationnelle)
# Mêmes hyperparamètres que 05_models.R, aucun réglage. Validation 2024 uniquement.
# =====================================================================
if (!file.exists("src/00_config.R"))
  stop("Lancer depuis la racine du projet (ouvrir le .Rproj).")
source("src/config.R"); source("src/utils_metrics.R"); source("src/utils_bench.R")
library(xgboost)
set.seed(123)

cas  <- readRDS(file.path(DIR_PROC, "cas_horaires.rds"))
VARS <- readRDS(file.path(DIR_PROC, "variables_modele.rds"))
train <- cas |> filter(utilise_apprentissage, !is.na(conso_cible))
valid <- cas |> filter(jeu == "validation", score_principal)

variantes <- list(
  complet         = c(VARS$calendrier, VARS$retards, VARS$meteo_operationnelle),
  sans_meteo      = c(VARS$calendrier, VARS$retards),
  sans_calendrier = c("h_loc", VARS$retards, VARS$meteo_operationnelle),  # h_loc conservé
  sans_retards    = c(VARS$calendrier, VARS$meteo_operationnelle)
)
# GARDE-FOU : aucune variante ne contient de variable "météo parfaite"
stopifnot(!any(grepl("^parf_", unlist(variantes))))

to_mat <- function(d, v) as.matrix(mutate(select(d, all_of(v)), across(everything(), as.numeric)))
params_xgb <- list(objective = "reg:squarederror", eta = 0.05, max_depth = 6,
                   subsample = 0.8, colsample_bytree = 0.8, nthread = 2, seed = 123)

fc <- bind_rows(lapply(names(variantes), function(nom) {
  v <- variantes[[nom]]
  m <- xgb.train(params = params_xgb, nrounds = 400, verbose = 0,
                 data = xgb.DMatrix(data = to_mat(train, v), label = train$conso_cible))
  p <- predict(m, xgb.DMatrix(data = to_mat(valid, v)))
  to_fc(valid, p, paste0("xgb_", nom))
}))

res <- summarise_models(common_rows(fc))
write.csv(res, file.path(DIR_OUT, "b05_ablation_xgboost_validation.csv"), row.names = FALSE)
print(res)