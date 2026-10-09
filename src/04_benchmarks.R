# =====================================================================
# 04_benchmarks.R : benchmarks sans apprentissage, évalués sur la validation
# Le test (2025) n'est PAS utilisé ici : il ne se regarde qu'à la fin.
# =====================================================================
if (!file.exists("src/00_config.R"))
  stop("Lancer depuis la racine du projet (ouvrir le .Rproj).")
source("src/config.R"); source("src/utils_metrics.R"); source("src/utils_bench.R")

x <- readRDS(file.path(DIR_PROC, "cas_horaires.rds"))

fc <- bind_rows(
  to_fc(x, bench_veille(x),  "veille"),
  to_fc(x, bench_semaine(x), "semaine_precedente")
) |> filter(jeu == "validation", score_principal)

saveRDS(fc, file.path(DIR_PROC, "prev_benchmarks_validation.rds"))

res <- summarise_models(common_rows(fc))
write.csv(res, file.path(DIR_OUT, "b01_metriques_benchmarks_validation.csv"), row.names = FALSE)
print(res)