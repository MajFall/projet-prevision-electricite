# =====================================================================
# 02b_controles.R : contrôles qualité de la table maître
# Entrée : data/processed/master_horaire.rds
# Sortie : un petit tableau par contrôle dans results/ (c2 à c9b)
# Chaque contrôle affiche une ligne « attendu / obtenu » : à lire dans la console.
# =====================================================================
if (!file.exists("src/00_config.R"))
  stop("Lancer depuis la racine du projet : ouvrir projet-prevision-electricite.Rproj dans RStudio.")
source("src/00_config.R")
master <- readRDS(F_MASTER)

# ---- C1 : taille de la grille --------------------------------------------
cat("C1 grille :", nrow(master), "heures (attendu 70128 pour 2018-2025)\n")

# ---- C2 : jours à 23 h et à 25 h (changements d'heure) -------------------
c2 <- master %>% filter(jour_chgt_heure) %>% distinct(date_loc, n_h_jour)
write_csv(c2, file.path(DIR_OUT, "c2_jours_changement_heure.csv"))
cat("C2 jours à 23 h :", sum(c2$n_h_jour == 23), "| à 25 h :", sum(c2$n_h_jour == 25),
    "(attendu 8 et 8)\n")

# ---- C3 : consommation manquante, par année ------------------------------
c3 <- master %>%
  group_by(annee) %>%
  summarise(heures = n(),
            conso_na = sum(is.na(conso_mw)),
            pct_na = round(100 * mean(is.na(conso_mw)), 2),
            conso_suspecte = sum(conso_suspecte),      # consommation <= 0
            .groups = "drop")
write_csv(c3, file.path(DIR_OUT, "c3_manquants_conso.csv"))
print(c3)

derniere_date <- max(master$date_loc[!is.na(master$conso_mw)])
cat("C3 dernière date avec consommation :", format(derniere_date),
    if (derniere_date < DATE_FIN) " <-- DATE_FIN trop tardive : corriger 00_config.R" else "", "\n")

# ---- C3b : les heures sans consommation ----------------------------------
# Attendu : une par an, dans la nuit du passage à 25 h.
c3b <- master %>% filter(is.na(conso_mw)) %>%
  transmute(heure_utc = format(heure_utc), heure_loc = format(heure_loc), n_h_jour)
write_csv(c3b, file.path(DIR_OUT, "c3b_heures_manquantes.csv"))
cat("C3b heures sans consommation :", nrow(c3b),
    "| dont dans un jour à 25 h :", sum(c3b$n_h_jour == 25), "\n")

# ---- C4 : couverture de la météo, par année (un relevé toutes les 3 h) ---
c4 <- master %>%
  group_by(annee) %>%
  summarise(obs_temp = sum(!is.na(temp_obs)),
            attendu_3h = n() / 3,
            taux = round(obs_temp / attendu_3h, 3),
            couv_moy = round(mean(couv_temp, na.rm = TRUE), 3),
            .groups = "drop")
write_csv(c4, file.path(DIR_OUT, "c4_couverture_meteo.csv"))
print(c4)

# ---- C5 : les 12 stations sont-elles dans les fichiers SYNOP ? -----------
fichiers <- list.files(file.path(DIR_RAW, "synop"), pattern = "\\.csv\\.gz$", full.names = TRUE)
stations_lues <- map(fichiers, function(f)
  suppressMessages(
    read_delim(f, delim = ";", na = c("", "mq"), show_col_types = FALSE, progress = FALSE,
               col_select = any_of("numer_sta"), col_types = cols(.default = col_character()))
  )$numer_sta) %>%
  unlist() %>% as.integer() %>% unique() %>% sprintf("%05d", .)
manquantes <- setdiff(STATIONS$numer_sta, stations_lues)
cat("C5 stations introuvables dans les fichiers SYNOP :",
    if (length(manquantes)) paste(manquantes, collapse = ", ") else "aucune", "\n")

# ---- C6 : profil moyen par heure locale (vérifie la convention horaire) ---
c6 <- master %>%
  filter(!jour_chgt_heure, !is.na(conso_mw)) %>%
  group_by(h_loc) %>%
  summarise(conso_moy = round(mean(conso_mw)), .groups = "drop")
write_csv(c6, file.path(DIR_OUT, "c6_profil_horaire.csv"))
cat("C6 heure locale du minimum :", c6$h_loc[which.min(c6$conso_moy)], "(attendu entre 4 et 6)\n")
cat("C6 heure locale du maximum :", c6$h_loc[which.max(c6$conso_moy)], "\n")

# ---- C7 : cohérence du calendrier ----------------------------------------
cat("C7 jours fériés :", sum(master$ferie & master$h_loc == 0),
    "| ponts :", sum(master$pont & master$h_loc == 0), "(attendu 88 et 24)\n")
paques_2025 <- master$date_loc[which(master$nom_ferie == "Lundi de Paques" & master$annee == 2025)[1]]
cat("C7 lundi de Pâques 2025 :", format(paques_2025), "(attendu 2025-04-21)\n")

# ---- C8 : heures valides avec un seul relevé sur deux --------------------
c8 <- master %>%
  filter(!is.na(conso_mw)) %>%
  group_by(annee) %>%
  summarise(heures_valides = n(),
            heures_un_seul_releve = sum(n_releves_conso == 1),
            .groups = "drop")
write_csv(c8, file.path(DIR_OUT, "c8_heures_un_seul_releve.csv"))
print(c8)

# ---- C9 : pics ou creux isolés (erreurs de mesure possibles) --------------
# Une vraie courbe de consommation est lisse d'une heure à l'autre. Une erreur
# de mesure donne un pic ou un creux sur UNE heure. On compare donc chaque heure
# à la moyenne de l'heure d'avant et de l'heure d'après (écart en %).
# On ne supprime rien : on liste les 10 pires heures pour les regarder.
c9 <- master %>%
  arrange(heure_utc) %>%
  mutate(voisines  = (lag(conso_mw) + lead(conso_mw)) / 2,
         saut_pct  = 100 * (conso_mw - voisines) / voisines) %>%
  filter(!is.na(saut_pct))
pires_sauts <- c9 %>%
  arrange(desc(abs(saut_pct))) %>%
  slice_head(n = 10) %>%
  transmute(heure_loc = format(heure_loc), conso_mw = round(conso_mw),
            voisines = round(voisines), saut_pct = round(saut_pct, 1))
write_csv(pires_sauts, file.path(DIR_OUT, "c9_pics_isoles.csv"))
cat("C9 heures avec un saut isolé de plus de 5 % :", sum(abs(c9$saut_pct) > 5),
    "sur", nrow(c9), "heures\n")
cat("C9 les 10 plus forts sauts isolés :\n")
print(as.data.frame(pires_sauts))

# ---- C9b : jours inhabituels par rapport à leur mois ----------------------
# Une heure est « normale » si elle ressemble à la médiane des heures comparables
# (même année, même mois, même jour de la semaine, même heure). Écart en % de
# cette médiane. On écarte fériés, ponts, fin d'année et changements d'heure.
# ATTENTION : cet écart n'enlève pas l'effet de la météo. Un jour très froid
# ressort donc comme « inhabituel » sans être une erreur : lire la colonne
# temp_moy_jour avant de conclure.
c9b <- master %>%
  filter(!is.na(conso_mw), !jour_chgt_heure, !ferie, !pont, !creux_fin_annee) %>%
  group_by(annee, mois, jour_sem, h_loc) %>%
  mutate(ecart_pct = 100 * (conso_mw - median(conso_mw)) / median(conso_mw)) %>%
  ungroup()

jours_inhabituels <- c9b %>%
  group_by(date_loc) %>%
  mutate(temp_moy_jour = round(mean(temp_obs, na.rm = TRUE), 1)) %>%
  slice_max(abs(ecart_pct), n = 1, with_ties = FALSE) %>%
  ungroup() %>%
  transmute(date_loc, jour_sem, heure_la_plus_ecartee = h_loc,
            ecart_pct = round(ecart_pct, 1),
            temp_moy_jour, confinement, n_zones_vacances) %>%
  arrange(desc(abs(ecart_pct))) %>%
  slice_head(n = 10)
write_csv(jours_inhabituels, file.path(DIR_OUT, "c9b_jours_inhabituels.csv"))
cat("C9b les 10 jours les plus éloignés de la normale de leur mois :\n")
print(as.data.frame(jours_inhabituels))
