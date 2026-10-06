# =====================================================================
# 02b_controles.R : contrôles qualité de la table maître
# Chaque contrôle produit un tableau dans results/ (réutilisable dans le
# rapport) et affiche une ligne de diagnostic. Lire attentivement la console.
# =====================================================================
if (!file.exists("src/00_config.R"))
  stop("Lancer depuis la racine du projet : ouvrir projet-prevision-electricite.Rproj dans RStudio.")
source("src/00_config.R")
master <- readRDS(F_MASTER)

# ---- C1 : taille de la grille (attendu : 70128 pour 2018-2025) ----------
cat("C1 grille :", nrow(master), "heures (attendu 70128 si 2018-01-01 -> 2025-12-31)\n")

# ---- C2 : jours à 23 h / 25 h (attendu : 8 de chaque) --------------------
chgt <- master %>% filter(jour_chgt_heure) %>% distinct(date_loc, n_h_jour)
write_csv(chgt, file.path(DIR_OUT, "c2_jours_changement_heure.csv"))
cat("C2 jours à 23 h :", sum(chgt$n_h_jour == 23), "| à 25 h :", sum(chgt$n_h_jour == 25), "\n")

# ---- C3 : manquants de consommation par année ----------------------------
c3 <- master %>% group_by(annee) %>%
  summarise(heures = n(), conso_na = sum(is.na(conso_mw)),
            pct_na = round(100 * mean(is.na(conso_mw)), 2),
            conso_suspecte = sum(conso_suspecte), .groups = "drop")
write_csv(c3, file.path(DIR_OUT, "c3_manquants_conso.csv")); print(c3)
dernier <- max(master$date_loc[!is.na(master$conso_mw)])
cat("C3 dernière date avec consommation :", format(dernier),
    if (dernier < DATE_FIN) "  <-- DATE_FIN trop tardive, ajuster 00_config.R !" else "", "\n")

# ---- C3b : heures sans consommation (attendu : 1 par an, nuit du passage à 25 h)
c3b <- master %>% filter(is.na(conso_mw)) %>%
  transmute(heure_utc = format(heure_utc), heure_loc = format(heure_loc), n_h_jour)
write_csv(c3b, file.path(DIR_OUT, "c3b_heures_manquantes.csv"))
cat("C3b heures sans consommation :", nrow(c3b), "| dont dans un jour à 25 h :",
    sum(c3b$n_h_jour == 25), "\n")

# ---- C4 : couverture météo par année (créneaux de 3 h) -------------------
c4 <- master %>%
  group_by(annee) %>%
  summarise(obs_temp = sum(!is.na(temp_obs)),
            attendu_3h = n() / 3,
            taux = round(obs_temp / attendu_3h, 3),
            couv_moy = round(mean(couv_temp, na.rm = TRUE), 3), .groups = "drop")
write_csv(c4, file.path(DIR_OUT, "c4_couverture_meteo.csv")); print(c4)

# ---- C5 : stations réellement présentes dans les fichiers SYNOP ----------
f_syn <- list.files(file.path(DIR_RAW, "synop"), pattern = "\\.csv\\.gz$", full.names = TRUE)
ids <- unlist(lapply(f_syn, function(f)
  unique(suppressMessages(
    read_delim(f, delim = ";", na = c("", "mq"), show_col_types = FALSE, progress = FALSE,
               col_select = any_of("numer_sta"),
               col_types = cols(.default = col_character())))$numer_sta)))
ids  <- sprintf("%05d", suppressWarnings(as.integer(unique(ids))))
manq <- setdiff(STATIONS$numer_sta, ids)
cat("C5 stations introuvables dans les fichiers SYNOP :",
    if (length(manq)) paste(manq, collapse = ", ") else "aucune", "\n")

# ---- C6 : convention horaire d'éCO2mix (profil moyen par heure locale) ---
c6 <- master %>% filter(!jour_chgt_heure, !is.na(conso_mw)) %>%
  group_by(h_loc) %>% summarise(conso_moy = round(mean(conso_mw)), .groups = "drop")
write_csv(c6, file.path(DIR_OUT, "c6_profil_horaire.csv"))
cat("C6 heure locale du minimum de consommation :", c6$h_loc[which.min(c6$conso_moy)],
    "(attendu : entre 4 et 6)\n")
cat("C6 heure locale du maximum :", c6$h_loc[which.max(c6$conso_moy)], "\n")

# ---- C7 : cohérence calendrier -------------------------------------------
cat("C7 jours fériés sur la période :", sum(master$ferie & master$h_loc == 0),
    "| ponts :", sum(master$pont & master$h_loc == 0), "\n")
cat("C7 Pâques 2025 (attendu 2025-04-20) -> lundi de Pâques :",
    format(master$date_loc[which(master$nom_ferie == "Lundi de Paques" & master$annee == 2025)[1]]),
    "(attendu 2025-04-21)\n")

# ---- C8 : heures de consommation valides sur un seul relevé (sur 2) ------------
c8 <- master %>% filter(!is.na(conso_mw)) %>% group_by(annee) %>%
  summarise(heures_valides = n(), heures_un_seul_releve = sum(n_releves_conso == 1),
            .groups = "drop")
write_csv(c8, file.path(DIR_OUT, "c8_heures_un_seul_releve.csv")); print(c8)
