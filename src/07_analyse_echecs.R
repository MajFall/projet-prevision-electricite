# =====================================================================
# 07_analyse_echecs.R : analyse des erreurs du test 2025 (aucun réajustement)
# Entrées : data/processed/prev_test_2025.rds (prévisions déjà produites par 06)
#           data/processed/cas_horaires.rds
# Sorties : results/s02 à s06 (tableaux) et s02_biais_vs_variation_temp.png
#
# Ce script relit seulement les prévisions enregistrées : il ne réestime
# aucun modèle et ne modifie rien. La météo réelle de J+1 (colonnes parf_*)
# sert ICI uniquement à EXPLIQUER les erreurs, jamais à prévoir.
# Variation de température delta_T = température moyenne de J+1 (observée)
#                                    - température moyenne des 24 h avant 14 h le jour J.
# =====================================================================
if (!file.exists("src/00_config.R"))
  stop("Lancer depuis la racine du projet : ouvrir projet-prevision-electricite.Rproj dans RStudio.")
source("src/config.R"); source("src/utils_metrics.R")
library(ggplot2)

f_prev <- file.path(DIR_PROC, "prev_test_2025.rds")
if (!file.exists(f_prev))
  stop("Prévisions du test introuvables. Ne pas relancer 06_evaluate.R sans raison : voir README.")
fc  <- readRDS(f_prev)
cas <- readRDS(file.path(DIR_PROC, "cas_horaires.rds"))
fcc <- common_rows(fc)                      # mêmes journées pour tous les modèles

# ---- 1) Une ligne par journée et par modèle, avec la météo --------------
meteo_jour <- cas %>%
  distinct(date_cible, mois, weekend, ferie, temp_moy_24h, parf_temp_moy_jour) %>%
  mutate(delta_T = parf_temp_moy_jour - temp_moy_24h,
         classe_temp = cut(parf_temp_moy_jour, c(-Inf, 5, 16, Inf), right = FALSE,
                           labels = c("froid_<5C", "intermediaire_5-16C", "doux_>=16C")),
         classe_variation = cut(abs(delta_T), c(-Inf, 2, 4, Inf), right = FALSE,
                                labels = c("stable_<2C", "variation_2-4C", "forte_variation_>=4C")),
         trimestre = paste0("T", ceiling(mois / 3)))

jour <- fcc %>%
  group_by(model, target_date) %>%
  summarise(MAE_jour = mean(abs(y_pred - y_true)),
            biais = mean(y_pred - y_true), .groups = "drop") %>%
  left_join(meteo_jour, by = c("target_date" = "date_cible"))

# ---- 2) Les 10 pires journées du modèle retenu, avec leur contexte -------
pires <- jour %>%
  filter(model == "lm_meteo_oper") %>%
  slice_max(MAE_jour, n = 10) %>%
  transmute(date = target_date, jour = weekdays(target_date),
            MAE_jour = round(MAE_jour), biais = round(biais),
            temp_J1 = round(parf_temp_moy_jour, 1), temp_24h_avant_14h = round(temp_moy_24h, 1),
            delta_T = round(delta_T, 1), ferie, weekend)
write_csv(pires, file.path(DIR_OUT, "s02_pires_jours_contexte.csv"))
cat("\n== 10 pires journées de lm_meteo_oper (erreur, et variation de température) ==\n")
print(as.data.frame(pires))

# ---- 3) L'erreur suit-elle la variation de température ? ----------------
cor_tab <- jour %>%
  filter(model %in% c("lm_meteo_oper", "xgb_meteo_oper"), !is.na(delta_T)) %>%
  group_by(model) %>%
  summarise(n_jours = n(),
            cor_pearson  = round(cor(biais, delta_T), 2),
            cor_spearman = round(cor(biais, delta_T, method = "spearman"), 2), .groups = "drop")
cat("\n== Corrélation entre le biais journalier et la variation de température ==\n")
print(as.data.frame(cor_tab))

p <- jour %>% filter(model == "lm_meteo_oper", !is.na(delta_T)) %>%
  ggplot(aes(delta_T, biais)) +
  geom_hline(yintercept = 0, colour = "grey60") + geom_vline(xintercept = 0, colour = "grey60") +
  geom_point(alpha = 0.6) + geom_smooth(method = "lm", formula = y ~ x, se = FALSE) +
  labs(x = "Variation de température J+1 par rapport aux 24 h avant 14 h (°C)",
       y = "Biais journalier (prévu - réel, MW)",
       title = "lm_meteo_oper, test 2025 : le biais suit la variation de température")
ggsave(file.path(DIR_OUT, "s02_biais_vs_variation_temp.png"), p, width = 7.5, height = 4.8, dpi = 150, bg = "white")

# ---- 4) Erreur selon les conditions météo --------------------------------
par_classe <- function(var) jour %>%
  filter(!is.na(.data[[var]])) %>%
  group_by(model, classe = .data[[var]]) %>%
  summarise(MAE = round(mean(MAE_jour)), .groups = "drop") %>%
  pivot_wider(names_from = classe, values_from = MAE)
t_temp <- par_classe("classe_temp"); t_var <- par_classe("classe_variation")
write_csv(t_temp, file.path(DIR_OUT, "s03_mae_classe_temperature.csv"))
write_csv(t_var,  file.path(DIR_OUT, "s03_mae_classe_variation.csv"))
cat("\n== MAE selon la température de J+1 ==\n");              print(as.data.frame(t_temp))
cat("\n== MAE selon la variation de température ==\n");        print(as.data.frame(t_var))
cat("\nNombre de journées par classe de variation :\n")
print(as.data.frame(jour %>% filter(model == "lm_meteo_oper") %>% count(classe_variation)))

# ---- 5) Stabilité du classement par trimestre ----------------------------
trim <- jour %>% group_by(model, trimestre) %>%
  summarise(MAE = round(mean(MAE_jour)), .groups = "drop") %>%
  pivot_wider(names_from = trimestre, values_from = MAE)
write_csv(trim, file.path(DIR_OUT, "s04_mae_trimestre.csv"))
cat("\n== MAE par trimestre (T1 = janvier-mars, etc.) ==\n"); print(as.data.frame(trim))

# ---- 6) Biais par mois (dérive de niveau ?) ------------------------------
biais_mois <- jour %>%
  filter(model %in% c("lm_calendrier_retards", "lm_meteo_oper", "xgb_meteo_oper")) %>%
  group_by(model, mois) %>% summarise(biais = round(mean(biais)), .groups = "drop") %>%
  pivot_wider(id_cols = mois, names_from = model, values_from = biais)
write_csv(biais_mois, file.path(DIR_OUT, "s05_biais_par_mois.csv"))
cat("\n== Biais moyen par mois (prévu - réel, MW) ==\n"); print(as.data.frame(biais_mois))

# ---- 6b) Même biais par mois sur la VALIDATION 2024 ------------------------
# Question : le biais positif d'hiver est-il propre à 2025 (dérive) ou récurrent ?
f_val <- file.path(DIR_PROC, "prev_modeles_validation.rds")
if (file.exists(f_val)) {
  val <- common_rows(readRDS(f_val)) %>%
    filter(model %in% c("lm_calendrier_retards", "lm_meteo_oper", "xgb_meteo_oper")) %>%
    group_by(model, target_date) %>% summarise(biais = mean(y_pred - y_true), .groups = "drop") %>%
    mutate(mois = month(target_date)) %>%
    group_by(model, mois) %>% summarise(biais = round(mean(biais)), .groups = "drop") %>%
    pivot_wider(id_cols = mois, names_from = model, values_from = biais)
  write_csv(val, file.path(DIR_OUT, "s05b_biais_par_mois_validation.csv"))
  cat("\n== Biais moyen par mois, VALIDATION 2024 (prévu - réel, MW) ==\n"); print(as.data.frame(val))
}

# ---- 7) Les écarts entre modèles sont-ils établis ? (bootstrap par journées) ----
quot <- daily_metrics(fcc)
ecarts <- jour %>% select(model, target_date, MAE_jour) %>%
  left_join(quot %>% transmute(model, target_date, abs_total = abs(err_total), abs_pointe = abs(err_peak)),
            by = c("model", "target_date"))

boot_diff <- function(metrique, a, b, nreps = 2000) {
  x <- ecarts[ecarts$model == a, ]; x <- x[order(x$target_date), ][[metrique]]
  y <- ecarts[ecarts$model == b, ]; y <- y[order(y$target_date), ][[metrique]]
  d <- x - y                                    # écart par journée : a - b (négatif = a meilleur)
  set.seed(123)
  m <- replicate(nreps, mean(sample(d, replace = TRUE)))
  tibble(comparaison = paste(a, "-", b), metrique = metrique, ecart_moyen = round(mean(d)),
         ic95_bas = round(unname(quantile(m, 0.025))), ic95_haut = round(unname(quantile(m, 0.975))))
}
paires <- list(c("xgb_meteo_oper", "lm_meteo_oper"),
               c("lm_meteo_oper", "lm_calendrier_retards"),
               c("lm_meteo_oper", "veille"))
ic <- map_dfr(paires, function(p) map_dfr(c("MAE_jour", "abs_total", "abs_pointe"), boot_diff, a = p[1], b = p[2]))
write_csv(ic, file.path(DIR_OUT, "s06_intervalles_bootstrap.csv"))
cat("\n== Écart entre modèles et intervalle à 95 % (négatif = le premier est meilleur) ==\n")
cat("   MAE_jour = erreur horaire moyenne ; abs_total = erreur sur le total journalier ; abs_pointe = erreur sur la pointe\n")
print(as.data.frame(ic))
cat("Si l'intervalle contient 0, l'écart n'est pas établi sur ces journées.\n")
