# =====================================================================
# 02_prepare.R : construit la table horaire data/processed/master_horaire.rds
# Une ligne = une heure (en UTC), du début à la fin de la période étudiée.
#
# Cinq blocs :
#   1) la grille d'heures          4) le calendrier
#   2) la consommation horaire     5) l'assemblage de la table
#   3) la météo (12 stations -> une série nationale)
#
# Règles à retenir :
#  - tout est en UTC : pas de doublon ni de trou au changement d'heure ;
#    l'heure locale n'est qu'une colonne en plus ;
#  - la météo garde son pas de 3 h : les colonnes *_obs ne sont JAMAIS
#    interpolées, car interpoler utiliserait une valeur future ;
#  - temp_interp_oracle (interpolée) sert seulement à l'exploration et au
#    scénario « météo parfaite » ;
#  - le calendrier est connu à l'avance, donc utilisable pour J+1.
# =====================================================================
if (!file.exists("src/00_config.R"))
  stop("Lancer depuis la racine du projet : ouvrir projet-prevision-electricite.Rproj dans RStudio.")
source("src/00_config.R")

# ---------------------------------------------------------------------
# 1) La grille : une ligne par heure, avec les repères en heure locale
# ---------------------------------------------------------------------
grille <- tibble(heure_utc = seq(T0_UTC, T1_UTC, by = "hour")) %>%
  mutate(heure_loc = with_tz(heure_utc, TZ_LOCAL),
         date_loc  = as.Date(heure_loc, tz = TZ_LOCAL),
         h_loc     = hour(heure_loc)) %>%
  group_by(date_loc) %>%
  mutate(n_h_jour = n()) %>%                 # 23, 24 ou 25 heures dans le jour local
  ungroup() %>%
  mutate(jour_chgt_heure = n_h_jour != 24)

# ---------------------------------------------------------------------
# 2) La consommation : éCO2mix (pas de 30 min) -> moyenne par heure
# ---------------------------------------------------------------------
eco <- read_delim(F_ECO, delim = ";", show_col_types = FALSE,
                  col_types = cols(.default = col_character())) %>%
  transmute(temps_utc = ymd_hms(date_heure, tz = "UTC", quiet = TRUE),
            conso     = as.numeric(consommation)) %>%
  filter(!is.na(temps_utc), temps_utc >= T0_UTC, temps_utc < T1_UTC + 3600)

n_doublons <- sum(duplicated(eco$temps_utc))
eco <- eco %>%
  distinct(temps_utc, .keep_all = TRUE) %>%   # un seul relevé par instant
  filter(!is.na(conso))                       # les lignes de :15 et :45 sont vides

# Une heure est valide dès qu'elle a au moins un relevé (à :00 ou à :30).
conso_horaire <- eco %>%
  mutate(heure_utc = floor_date(temps_utc, "hour")) %>%
  group_by(heure_utc) %>%
  summarise(conso_mw = mean(conso), n_releves_conso = n(), .groups = "drop")

# ---------------------------------------------------------------------
# 3) La météo : SYNOP -> une moyenne pondérée des 12 stations
# ---------------------------------------------------------------------
# Lecture d'un fichier mensuel : on garde la station, la date, la température
# (t, en kelvins), le vent (ff) et l'humidité (u).
lire_synop <- function(fichier) {
  suppressMessages(                           # colonne vide finale : message inutile
    read_delim(fichier, delim = ";", na = c("", "mq"), show_col_types = FALSE,
               progress = FALSE, col_types = cols(.default = col_character()))) %>%
    select(any_of(c("numer_sta", "date", "t", "ff", "u"))) %>%
    rename(any_of(c(temp = "t", vent = "ff", hum = "u")))
}

fichiers <- list.files(file.path(DIR_RAW, "synop"), pattern = "\\.csv\\.gz$", full.names = TRUE)
stopifnot(length(fichiers) > 0)

synop <- map_dfr(fichiers, lire_synop) %>%
  mutate(numer_sta = sprintf("%05d", suppressWarnings(as.integer(numer_sta)))) %>%
  filter(numer_sta %in% STATIONS$numer_sta) %>%       # les 12 stations retenues
  mutate(temps_utc = ymd_hms(date, tz = "UTC", quiet = TRUE),
         temp = as.numeric(temp) - 273.15,            # kelvins -> °C
         vent = as.numeric(vent),                     # m/s
         hum  = as.numeric(hum)) %>%                  # %
  filter(!is.na(temps_utc)) %>%
  distinct(numer_sta, temps_utc, .keep_all = TRUE) %>%
  left_join(STATIONS, by = "numer_sta")               # ajoute le poids de chaque station

# Valeurs physiquement impossibles : on les compte, puis on les met à NA.
impossible_temp <- synop$temp < -35 | synop$temp > 50
impossible_vent <- synop$vent < 0   | synop$vent > 80
impossible_hum  <- synop$hum  < 0   | synop$hum  > 100
n_impossibles <- c(temp = sum(impossible_temp, na.rm = TRUE),
                   vent = sum(impossible_vent, na.rm = TRUE),
                   hum  = sum(impossible_hum,  na.rm = TRUE))
synop$temp[which(impossible_temp)] <- NA
synop$vent[which(impossible_vent)] <- NA
synop$hum[which(impossible_hum)]   <- NA

# Moyenne pondérée des stations disponibles à chaque instant.
# On garde la valeur seulement si les stations présentes pèsent au moins
# SEUIL_COUVERTURE du poids total (sinon NA).
agreger <- function(variable) {
  synop %>%
    filter(!is.na(.data[[variable]])) %>%
    group_by(temps_utc) %>%
    summarise(valeur = weighted.mean(.data[[variable]], poids),
              couverture = sum(poids) / POIDS_TOTAL, .groups = "drop") %>%
    mutate(valeur = if_else(couverture >= SEUIL_COUVERTURE, valeur, NA_real_)) %>%
    rename(!!paste0(variable, "_obs") := valeur,
           !!paste0("couv_", variable) := couverture)
}
meteo <- agreger("temp") %>%
  full_join(agreger("vent"), by = "temps_utc") %>%
  full_join(agreger("hum"),  by = "temps_utc") %>%
  rename(heure_utc = temps_utc)

# ---------------------------------------------------------------------
# 4) Le calendrier : jours fériés, ponts, fin d'année
# ---------------------------------------------------------------------
# Dimanche de Pâques (algorithme de Meeus/Jones/Butcher).
paques <- function(an) {
  a <- an %% 19; b <- an %/% 100; c <- an %% 100
  d <- b %/% 4; e <- b %% 4; f <- (b + 8) %/% 25; g <- (b - f + 1) %/% 3
  h <- (19 * a + b - d - g + 15) %% 30; i <- c %/% 4; k <- c %% 4
  l <- (32 + 2 * e + 2 * i - h - k) %% 7; m <- (a + 11 * h + 22 * l) %/% 451
  mois <- (h + l - 7 * m + 114) %/% 31
  jour <- ((h + l - 7 * m + 114) %% 31) + 1
  as.Date(sprintf("%04d-%02d-%02d", an, mois, jour))
}

# Les 11 jours fériés d'une année (3 dépendent de Pâques : lundi de Pâques,
# Ascension à Pâques + 39 jours, lundi de Pentecôte à Pâques + 50 jours).
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
# On prend une année de marge de chaque côté : le 1er janvier suivant sert
# à repérer la veille de férié du 31 décembre.
feries <- map_dfr((year(DATE_DEBUT) - 1):(year(DATE_FIN) + 1), feries_annee)

calendrier <- tibble(date_loc = seq(DATE_DEBUT - 7, DATE_FIN + 7, by = "day")) %>%
  left_join(feries, by = c("date_loc" = "date")) %>%
  mutate(annee      = year(date_loc),
         mois       = month(date_loc),
         jour_annee = yday(date_loc),
         jour_sem   = wday(date_loc, week_start = 1),     # 1 = lundi ... 7 = dimanche
         weekend    = jour_sem >= 6,
         ferie      = !is.na(nom_ferie),
         veille_ferie    = lead(ferie, default = FALSE),
         lendemain_ferie = lag(ferie,  default = FALSE),
         # pont : vendredi après un férié du jeudi, ou lundi avant un férié du mardi
         pont = !ferie & !weekend &
                ((jour_sem == 5 & lag(ferie,  default = FALSE)) |
                 (jour_sem == 1 & lead(ferie, default = FALSE))),
         jour_ouvre = !weekend & !ferie,
         # creux de fin d'année : du 24 décembre au 1er janvier
         creux_fin_annee = (mois == 12 & mday(date_loc) >= 24) |
                           (mois == 1  & mday(date_loc) == 1)) %>%
  filter(date_loc >= DATE_DEBUT, date_loc <= DATE_FIN)

# Vacances scolaires : nombre de zones (A, B, C) en vacances ce jour-là, de 0 à 3.
# Dans le fichier, les dates sont en UTC (minuit local = 22 h ou 23 h la veille) :
# on les convertit en dates locales. start_date = premier jour de vacances,
# end_date = jour de reprise des cours (donc exclu).
vacances <- read_delim(F_SCOLAIRE, delim = ";", show_col_types = FALSE,
                       col_types = cols(.default = col_character())) %>%
  filter(zones %in% c("Zone A", "Zone B", "Zone C"),    # métropole seulement
         population %in% c("-", "Élèves"),              # on écarte les lignes « enseignants »
         grepl("^Vacances", description)) %>%           # on écarte ponts et jours fériés
  transmute(zone  = zones,
            debut = as.Date(with_tz(ymd_hms(start_date, tz = "UTC"), TZ_LOCAL), tz = TZ_LOCAL),
            fin   = as.Date(with_tz(ymd_hms(end_date,   tz = "UTC"), TZ_LOCAL), tz = TZ_LOCAL)) %>%
  filter(!is.na(debut), !is.na(fin))

jours_vacances <- vacances %>%
  mutate(date_loc = map2(debut, fin - 1, seq, by = "day")) %>%   # un jour par ligne
  unnest(date_loc) %>%
  distinct(zone, date_loc) %>%
  count(date_loc, name = "n_zones_vacances")

calendrier <- calendrier %>%
  left_join(jours_vacances, by = "date_loc") %>%
  mutate(n_zones_vacances = replace_na(n_zones_vacances, 0L),
         # premier confinement : repéré ici, exclu de l'apprentissage dans 03_features.R
         confinement = date_loc >= CONFINEMENT_DEBUT & date_loc <= CONFINEMENT_FIN)

stopifnot(all(calendrier$n_zones_vacances %in% 0:3))

# ---------------------------------------------------------------------
# 5) L'assemblage : on colle tout sur la grille d'heures
# ---------------------------------------------------------------------
master <- grille %>%
  left_join(conso_horaire, by = "heure_utc") %>%
  left_join(meteo,         by = "heure_utc") %>%
  left_join(calendrier,    by = "date_loc") %>%
  arrange(heure_utc) %>%
  mutate(
    # ATTENTION : interpolation qui utilise des valeurs futures.
    # Réservée à l'exploration et à la météo parfaite.
    temp_interp_oracle = zoo::na.approx(temp_obs, maxgap = 6, na.rm = FALSE),
    conso_suspecte     = !is.na(conso_mw) & conso_mw <= 0)

# Contrôles bloquants : une ligne par heure, sans doublon.
stopifnot(!anyDuplicated(master$heure_utc),
          nrow(master) == length(seq(T0_UTC, T1_UTC, by = "hour")))

saveRDS(master, F_MASTER)
write_csv(master %>% mutate(heure_utc = format(heure_utc, "%Y-%m-%d %H:%M:%S"),
                            heure_loc = format(heure_loc, "%Y-%m-%d %H:%M:%S")),
          file.path(DIR_PROC, "master_horaire.csv"))
write_csv(calendrier, file.path(DIR_PROC, "calendrier.csv"))

message("Table maître : ", nrow(master), " heures ; doublons éCO2mix retirés : ", n_doublons)
message("Jours par nombre de zones en vacances : ",
        paste(names(table(calendrier$n_zones_vacances)), table(calendrier$n_zones_vacances),
              sep = "=", collapse = ", "))
message("Jours de confinement repérés : ", sum(calendrier$confinement))
message("Valeurs SYNOP impossibles masquées : ",
        paste(names(n_impossibles), n_impossibles, sep = "=", collapse = ", "))
