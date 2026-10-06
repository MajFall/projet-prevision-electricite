# =====================================================================
# 02_prepare.R : construction de la table maître horaire (UTC)
# Sortie : data/processed/master_horaire.rds (+ .csv)
#
# Principes :
#  * la grille de référence est horaire et en UTC (continue, sans trou
#    ni doublon, donc insensible aux changements d'heure) ;
#  * la météo est conservée à son pas natif (3 h) : AUCUNE valeur n'est
#    propagée ni interpolée dans les colonnes *_obs ; la jointure "as of 14 h"
#    est faite dans 03_features.R ;
#  * temp_interp_oracle sert à l'exploration et au scénario météo parfaite
#    UNIQUEMENT (elle utilise des valeurs futures) ;
#  * le calendrier est connu à l'avance, donc utilisable pour J+1.
# =====================================================================
if (!file.exists("src/00_config.R"))
  stop("Lancer depuis la racine du projet : ouvrir projet-prevision-electricite.Rproj dans RStudio.")
source("src/00_config.R")
modal <- function(x) as.numeric(names(which.max(table(x))))

# ---------------------------------------------------------------------
# 1) Grille horaire de référence (UTC) + repères en heure locale
# ---------------------------------------------------------------------
grille <- tibble(heure_utc = seq(T0_UTC, T1_UTC, by = "hour")) %>%
  mutate(heure_loc = with_tz(heure_utc, TZ_LOCAL),
         date_loc  = as.Date(heure_loc, tz = TZ_LOCAL),
         h_loc     = hour(heure_loc)) %>%
  group_by(date_loc) %>% mutate(n_h_jour = n()) %>% ungroup() %>%
  mutate(jour_chgt_heure = n_h_jour != 24)

# ---------------------------------------------------------------------
# 2) éCO2mix -> consommation horaire (moyenne des pas valides de l'heure)
# ---------------------------------------------------------------------
eco_raw <- read_delim(F_ECO, delim = ";", show_col_types = FALSE,
                      col_types = cols(.default = col_character()))
stopifnot(all(c("date_heure", "consommation") %in% names(eco_raw)))

eco <- eco_raw %>%
  transmute(time_utc = ymd_hms(date_heure, tz = "UTC", quiet = TRUE),
            conso    = as.numeric(consommation)) %>%
  filter(!is.na(time_utc), time_utc >= T0_UTC, time_utc < T1_UTC + 3600)

n_dup <- sum(duplicated(eco$time_utc))
eco   <- distinct(eco, time_utc, .keep_all = TRUE)

# On filtre les NA du quart d'heure et on moyenne les pas observés
eco_h <- eco %>%
  filter(!is.na(conso)) %>%
  mutate(heure_utc = floor_date(time_utc, "hour")) %>%
  group_by(heure_utc) %>%
  summarise(n_valides = n(),
            conso_mw  = mean(conso, na.rm = TRUE),
            .groups   = "drop") %>%
  # Fichier au pas de 30 min dont les lignes :15 et :45 sont vides : une heure
  # est valide si au moins un relevé existe (n_releves_conso = 1 ou 2).
  filter(n_valides >= 1) %>%
  select(heure_utc, conso_mw, n_releves_conso = n_valides)

# ---------------------------------------------------------------------
# 3) SYNOP -> série nationale (moyenne pondérée des stations disponibles)
# ---------------------------------------------------------------------
fichiers <- list.files(file.path(DIR_RAW, "synop"), pattern = "^synop\\..*\\.csv\\.gz$",
                       full.names = TRUE)
stopifnot(length(fichiers) > 0)
lire_synop <- function(f) {
  suppressMessages(   # chaque fichier a une colonne vide finale : message sans intérêt
    read_delim(f, delim = ";", na = c("", "mq"), show_col_types = FALSE, progress = FALSE,
               col_types = cols(.default = col_character()))) %>%
    select(any_of(c("numer_sta", "date", "t", "ff", "u"))) %>%
    rename(any_of(c(temp = "t", vent = "ff", hum = "u")))
}
syn <- map_dfr(fichiers, lire_synop) %>%
  mutate(numer_sta = sprintf("%05d", suppressWarnings(as.integer(numer_sta)))) %>%
  filter(numer_sta %in% STATIONS$numer_sta) %>%
  mutate(time_utc = ymd_hms(date, tz = "UTC", quiet = TRUE),
         temp = as.numeric(temp) - 273.15,       # Kelvin -> °C
         vent = as.numeric(vent),                # m/s
         hum  = as.numeric(hum)) %>%             # %
  filter(!is.na(time_utc)) %>%
  distinct(numer_sta, time_utc, .keep_all = TRUE) %>%
  left_join(STATIONS, by = "numer_sta")

# Valeurs physiquement impossibles -> NA (comptées, pas supprimées en silence)
masque <- with(syn, c(temp = sum(temp < -35 | temp > 50, na.rm = TRUE),
                      vent = sum(vent < 0 | vent > 80,  na.rm = TRUE),
                      hum  = sum(hum  < 0 | hum  > 100, na.rm = TRUE)))
syn <- syn %>% mutate(temp = if_else(temp < -35 | temp > 50, NA_real_, temp),
                      vent = if_else(vent < 0 | vent > 80,   NA_real_, vent),
                      hum  = if_else(hum  < 0 | hum  > 100,  NA_real_, hum))

agreger <- function(df, var) {
  out <- df %>% filter(!is.na(.data[[var]])) %>% group_by(time_utc) %>%
    summarise(val  = weighted.mean(.data[[var]], poids),
              couv = sum(poids) / POIDS_TOTAL, .groups = "drop") %>%
    mutate(val = if_else(couv >= SEUIL_COUVERTURE, val, NA_real_))
  names(out)[names(out) == "val"]  <- paste0(var, "_obs")
  names(out)[names(out) == "couv"] <- paste0("couv_", var)
  out
}
meteo <- reduce(map(c("temp", "vent", "hum"), ~ agreger(syn, .x)),
                full_join, by = "time_utc") %>%
  rename(heure_utc = time_utc)

# ---------------------------------------------------------------------
# 4) Calendrier (connu à l'avance)
# ---------------------------------------------------------------------
paques <- function(an) {                    # algorithme de Meeus/Jones/Butcher
  a <- an %% 19; b <- an %/% 100; c <- an %% 100
  d <- b %/% 4; e <- b %% 4; f <- (b + 8) %/% 25; g <- (b - f + 1) %/% 3
  h <- (19 * a + b - d - g + 15) %% 30; i <- c %/% 4; k <- c %% 4
  l <- (32 + 2 * e + 2 * i - h - k) %% 7; m <- (a + 11 * h + 22 * l) %/% 451
  mois <- (h + l - 7 * m + 114) %/% 31; jour <- ((h + l - 7 * m + 114) %% 31) + 1
  as.Date(sprintf("%04d-%02d-%02d", an, mois, jour))
}
feries_annee <- function(an) {
  p <- paques(an)
  tibble(date = c(as.Date(sprintf("%d-01-01", an)), p + 1,
                  as.Date(sprintf("%d-05-01", an)), as.Date(sprintf("%d-05-08", an)),
                  p + 39, p + 50,
                  as.Date(sprintf("%d-07-14", an)), as.Date(sprintf("%d-08-15", an)),
                  as.Date(sprintf("%d-11-01", an)), as.Date(sprintf("%d-11-11", an)),
                  as.Date(sprintf("%d-12-25", an))),
         nom_ferie = c("Jour de l'an", "Lundi de Paques", "Fete du travail", "Victoire 1945",
                       "Ascension", "Lundi de Pentecote", "Fete nationale", "Assomption",
                       "Toussaint", "Armistice 1918", "Noel"))
}
# années voisines incluses : le 1er janvier suivant sert à marquer "veille_ferie" au 31/12
feries <- map_dfr((year(DATE_DEBUT) - 1):(year(DATE_FIN) + 1), feries_annee)

calendrier <- tibble(date_loc = seq(DATE_DEBUT - 7, DATE_FIN + 7, by = "day")) %>%
  left_join(feries, by = c("date_loc" = "date")) %>%
  mutate(annee      = year(date_loc), mois = month(date_loc),
         jour_annee = yday(date_loc),
         jour_sem   = wday(date_loc, week_start = 1),   # 1 = lundi ... 7 = dimanche
         weekend    = jour_sem >= 6,
         ferie      = !is.na(nom_ferie),
         veille_ferie    = lead(ferie, default = FALSE),
         lendemain_ferie = lag(ferie,  default = FALSE),
         pont = !ferie & !weekend &
                ((jour_sem == 5 & lag(ferie, default = FALSE)) |
                 (jour_sem == 1 & lead(ferie, default = FALSE))),
         jour_ouvre = !weekend & !ferie,
         creux_fin_annee = (mois == 12 & mday(date_loc) >= 24) |
                           (mois == 1  & mday(date_loc) == 1)) %>%
  filter(date_loc >= DATE_DEBUT, date_loc <= DATE_FIN)

# ---------------------------------------------------------------------
# 5) Assemblage de la table maître
# ---------------------------------------------------------------------
master <- grille %>%
  left_join(eco_h, by = "heure_utc") %>%
  left_join(meteo, by = "heure_utc") %>%
  left_join(calendrier, by = "date_loc") %>%
  arrange(heure_utc) %>%
  mutate(# EXPLORATION / ORACLE UNIQUEMENT : interpolation utilisant des valeurs futures
         temp_interp_oracle = zoo::na.approx(temp_obs, maxgap = 6, na.rm = FALSE),
         conso_suspecte = !is.na(conso_mw) & conso_mw <= 0)

# Contrôles bloquants
stopifnot(!anyDuplicated(master$heure_utc),
          nrow(master) == length(seq(T0_UTC, T1_UTC, by = "hour")))

saveRDS(master, F_MASTER)
write_csv(master %>% mutate(heure_utc = format(heure_utc, "%Y-%m-%d %H:%M:%S"),
                            heure_loc = format(heure_loc, "%Y-%m-%d %H:%M:%S")),
          file.path(DIR_PROC, "master_horaire.csv"))
write_csv(calendrier, file.path(DIR_PROC, "calendrier.csv"))

message("Table maître : ", nrow(master), " heures ; doublons éCO2mix retirés : ", n_dup)
message("Valeurs SYNOP impossibles masquées : ",
        paste(names(masque), masque, sep = "=", collapse = ", "))
