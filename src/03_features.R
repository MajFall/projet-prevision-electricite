# =====================================================================
# 03_features.R : table de prévision (une ligne = une heure cible de J+1)
# Entrée : data/processed/master_horaire.rds
# Sortie : data/processed/cas_horaires.rds
#          data/processed/variables_modele.rds  (listes de variables par bloc)
#          results/f01_valeurs_manquantes_features.csv
#
# Principe : pour chaque jour J, on se place à 14 h (heure locale) et on ne
# garde que ce qui est CONNU à ce moment :
#   * calendrier de J+1 : connu à l'avance ;
#   * consommation : une heure n'est utilisable que LATENCE_CONSO_H après sa fin ;
#   * météo SYNOP : une observation n'est utilisable que LATENCE_METEO_H après
#     son instant (pas natif de 3 h, jamais interpolée) ;
#   * variante « météo parfaite » : colonnes préfixées parf_, qui utilisent la
#     météo observée de J+1. Borne de performance, jamais déployable.
# La disponibilité est calculée à partir des horodatages, pas à la main.
# =====================================================================
if (!file.exists("src/00_config.R"))
  stop("Lancer depuis la racine du projet : ouvrir projet-prevision-electricite.Rproj dans RStudio.")
source("src/00_config.R")
master <- readRDS(F_MASTER) %>% arrange(heure_utc)

# ---------------------------------------------------------------------
# 1) Les origines : 14 h locale du jour J, pour chaque jour cible J+1
# ---------------------------------------------------------------------
jours <- tibble(date_cible = seq(DATE_DEBUT + 1, DATE_FIN, by = "day")) %>%
  mutate(origine_utc = with_tz(as.POSIXct(paste(date_cible - 1,
                                                sprintf("%02d:00:00", ORIGINE_HEURE_LOCALE)),
                                          tz = TZ_LOCAL), "UTC"),
         lim_conso = origine_utc - LATENCE_CONSO_H * 3600,  # une heure doit finir avant
         lim_meteo = origine_utc - LATENCE_METEO_H * 3600)  # une observation doit dater d'avant

# ---------------------------------------------------------------------
# 2) Niveau récent de la consommation (dernière heure connue, moyennes 24 h et 7 j)
# ---------------------------------------------------------------------
moy_glissante <- function(x, n)
  zoo::rollapplyr(x, n, function(v) mean(v, na.rm = TRUE), fill = NA)
conso_h <- master %>%
  transmute(debut_h = heure_utc, conso_derniere = conso_mw,
            conso_moy_24h = moy_glissante(conso_mw, 24),
            conso_moy_7j  = moy_glissante(conso_mw, 168)) %>%
  mutate(across(starts_with("conso_"), ~ ifelse(is.nan(.x), NA_real_, .x)))

niveaux <- jours %>%
  mutate(debut_h = lim_conso - 3600) %>%          # dernière heure terminée avant la limite
  left_join(conso_h, by = "debut_h") %>%
  select(date_cible, conso_derniere, conso_moy_24h, conso_moy_7j)

# ---------------------------------------------------------------------
# 3) Météo observée à 14 h : dernière valeur et moyennes sur 24 h et 72 h
# ---------------------------------------------------------------------
serie_obs <- function(var)
  master %>% filter(!is.na(.data[[var]])) %>% transmute(t = as.numeric(heure_utc), v = .data[[var]])
derniere <- function(s, lim) {                    # dernière observation <= lim
  i <- findInterval(lim, s$t)
  list(v = ifelse(i > 0, s$v[pmax(i, 1)], NA_real_), t = ifelse(i > 0, s$t[pmax(i, 1)], NA_real_))
}
moyenne_fenetre <- function(s, lim, heures) {     # moyenne des observations de ]lim - heures, lim]
  cs <- c(0, cumsum(s$v))
  hi <- findInterval(lim, s$t); lo <- findInterval(lim - heures * 3600, s$t)
  ifelse(hi > lo, (cs[hi + 1] - cs[lo + 1]) / (hi - lo), NA_real_)
}
lim <- as.numeric(jours$lim_meteo)
s_temp <- serie_obs("temp_obs"); s_vent <- serie_obs("vent_obs"); s_hum <- serie_obs("hum_obs")
d_temp <- derniere(s_temp, lim)
meteo_j <- jours %>%
  transmute(date_cible,
            temp_derniere = d_temp$v,
            temp_moy_24h  = moyenne_fenetre(s_temp, lim, 24),
            temp_moy_72h  = moyenne_fenetre(s_temp, lim, 72),
            vent_derniere = derniere(s_vent, lim)$v,
            hum_derniere  = derniere(s_hum,  lim)$v,
            t_meteo_utilisee = as.POSIXct(d_temp$t, origin = "1970-01-01", tz = "UTC"),
            lim_meteo_utc    = lim_meteo)

# ---------------------------------------------------------------------
# 4) Cibles (les heures de J+1) et retards (même heure locale, k jours avant)
# ---------------------------------------------------------------------
cibles <- master %>%
  filter(date_loc >= DATE_DEBUT + 1) %>%
  group_by(date_loc) %>%
  mutate(parf_temp_moy_jour = if (sum(!is.na(temp_obs)) >= 6) mean(temp_obs, na.rm = TRUE) else NA_real_) %>%
  ungroup() %>%
  transmute(date_cible = date_loc, h_loc, heure_utc, n_h_jour, jour_chgt_heure,
            conso_cible = conso_mw,
            annee, mois, jour_annee, jour_sem, weekend, ferie, pont,
            veille_ferie, lendemain_ferie, jour_ouvre, creux_fin_annee,
            n_zones_vacances,          # nombre de zones A/B/C en vacances (0 à 3), connu à l'avance
            confinement,               # jour du premier confinement (sert à l'exclusion ci-dessous)
            parf_temp_horaire = temp_interp_oracle, parf_temp_moy_jour)

# Source des retards : une valeur par (date locale, heure locale) ; un jour de
# 25 h donne la moyenne des deux heures répétées.
source_retard <- master %>%
  group_by(date_loc, h_loc) %>%
  summarise(conso = mean(conso_mw, na.rm = TRUE), fin_h = max(heure_utc) + 3600, .groups = "drop") %>%
  mutate(conso = ifelse(is.nan(conso), NA_real_, conso))

ajoute_retard <- function(df, k, nom) {
  src <- source_retard %>% transmute(date_cible = date_loc + k, h_loc, c_k = conso, fin_k = fin_h)
  df %>% left_join(src, by = c("date_cible", "h_loc")) %>%
    left_join(jours %>% select(date_cible, origine_utc), by = "date_cible") %>%
    # utilisable seulement si l'heure source est terminée depuis LATENCE_CONSO_H à l'origine
    mutate(!!nom := if_else(!is.na(fin_k) & fin_k + LATENCE_CONSO_H * 3600 <= origine_utc, c_k, NA_real_)) %>%
    select(-c_k, -fin_k, -origine_utc)
}

cas <- cibles %>%
  ajoute_retard(1, "conso_lag1") %>%     # même heure la veille (seulement si h <= 12)
  ajoute_retard(7, "conso_lag7") %>%     # même heure, même jour de la semaine précédente
  left_join(niveaux,  by = "date_cible") %>%
  left_join(meteo_j,  by = "date_cible") %>%
  mutate(jeu = case_when(date_cible <= FIN_APPRENTISSAGE ~ "apprentissage",
                         date_cible <= FIN_VALIDATION    ~ "validation",
                         TRUE                            ~ "test"),
         # Les jours du premier confinement sont exclus de l'APPRENTISSAGE seulement :
         # les modèles s'ajustent sur les lignes où utilise_apprentissage vaut TRUE.
         # Validation et test ne sont pas modifiés.
         utilise_apprentissage = jeu == "apprentissage" & !confinement,
         score_principal = !jour_chgt_heure & !is.na(conso_cible)) %>%
  arrange(heure_utc)

# ---------------------------------------------------------------------
# 5) Contrôles bloquants : aucune fuite d'information
# ---------------------------------------------------------------------
h_max <- ORIGINE_HEURE_LOCALE - 1 - LATENCE_CONSO_H      # dernière heure connue (12 h)
normal <- cas %>% filter(!jour_chgt_heure)
stopifnot(
  # la veille à la même heure n'existe que pour h <= h_max
  all(is.na(normal$conso_lag1[normal$h_loc > h_max])),
  # la météo utilisée date d'avant la limite de disponibilité (origine - latence)
  all(cas$t_meteo_utilisee <= cas$lim_meteo_utc, na.rm = TRUE),
  # une seule ligne par heure cible
  !anyDuplicated(cas$heure_utc))
cas <- cas %>% select(-t_meteo_utilisee, -lim_meteo_utc)

# ---------------------------------------------------------------------
# 6) Sorties
# ---------------------------------------------------------------------
VARS <- list(
  calendrier = c("h_loc", "jour_sem", "mois", "jour_annee", "weekend", "ferie", "pont",
                 "veille_ferie", "lendemain_ferie", "jour_ouvre", "creux_fin_annee",
                 "n_zones_vacances"),
  retards    = c("conso_lag1", "conso_lag7", "conso_derniere", "conso_moy_24h", "conso_moy_7j"),
  meteo_operationnelle = c("temp_derniere", "temp_moy_24h", "temp_moy_72h", "vent_derniere", "hum_derniere"),
  meteo_parfaite       = c("parf_temp_horaire", "parf_temp_moy_jour"))
# les variables opérationnelles ne contiennent aucune colonne « météo parfaite »
stopifnot(!any(grepl("^parf_", unlist(VARS[c("calendrier", "retards", "meteo_operationnelle")]))))
saveRDS(cas,  file.path(DIR_PROC, "cas_horaires.rds"))
saveRDS(VARS, file.path(DIR_PROC, "variables_modele.rds"))

na_par_var <- cas %>% filter(score_principal) %>%
  summarise(across(all_of(unname(unlist(VARS))), ~ sum(is.na(.x)))) %>%
  pivot_longer(everything(), names_to = "variable", values_to = "n_na") %>%
  mutate(pct_na = round(100 * n_na / sum(cas$score_principal), 2))
write_csv(na_par_var, file.path(DIR_OUT, "f01_valeurs_manquantes_features.csv"))

message("Cas horaires : ", nrow(cas), " lignes (", sum(cas$score_principal), " dans le score principal)")
message("Répartition : ", paste(names(table(cas$jeu)), table(cas$jeu), sep = "=", collapse = ", "))
message("Apprentissage : ", sum(cas$jeu == "apprentissage"), " lignes, dont ",
        sum(cas$jeu == "apprentissage" & cas$confinement), " exclues (confinement) -> ",
        sum(cas$utilise_apprentissage), " utilisées")
print(as.data.frame(na_par_var))

# Jours sans moyenne de température observée (météo parfaite indisponible)
j_sans <- cas %>% filter(is.na(parf_temp_moy_jour)) %>% distinct(date_cible)
message("Jours sans température journalière de référence : ", nrow(j_sans), " (", paste(format(j_sans$date_cible), collapse = ", "), ")")
