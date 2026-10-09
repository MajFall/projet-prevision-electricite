# =====================================================================
# 00_config.R : paramètres globaux du projet
# Tous les choix méthodologiques du cadrage sont centralisés
# ici. Les autres scripts font source("src/00_config.R") et ne contiennent
# aucun "nombre magique". Exécuter les scripts depuis la racine du projet.
# =====================================================================
suppressPackageStartupMessages({
  library(dplyr); library(readr); library(lubridate)
  library(tidyr); library(purrr); library(zoo)
})

# ---- Temps et période ------------------------------------------------
TZ_LOCAL   <- "Europe/Paris"
DATE_DEBUT <- as.Date("2018-01-01")   # premier jour local étudié
DATE_FIN   <- as.Date("2025-12-31")   # dernier jour local étudié

# Découpage chronologique (protocole) : test final = année 2025
FIN_APPRENTISSAGE <- as.Date("2023-12-31")
FIN_VALIDATION    <- as.Date("2024-12-31")

# Premier confinement : exclu de l'APPRENTISSAGE seulement (jamais de la validation ni du test)
CONFINEMENT_DEBUT <- as.Date("2020-03-17")
CONFINEMENT_FIN   <- as.Date("2020-05-11")

# ---- Origine de prévision et latences (utilisées dans 03_features.R) ---------
ORIGINE_HEURE_LOCALE <- 14   # 14h00 heure locale du jour J
LATENCE_CONSO_H <- 1  # une heure de conso n'est utilisable qu'1 h après sa fin
LATENCE_METEO_H <- 1  # idem pour une observation SYNOP (hypothèse prudente)

# ---- Sources (À VÉRIFIER : les URL institutionnelles évoluent) --------
ECO2MIX_DATASET <- "eco2mix-national-cons-def"
ECO2MIX_URL <- paste0(
  "https://odre.opendatasoft.com/api/explore/v2.1/catalog/datasets/",
  ECO2MIX_DATASET,
  "/exports/csv?select=date_heure%2Cconsommation",
  "&order_by=date_heure&delimiter=%3B&timezone=UTC")

# Calendrier scolaire officiel (Éducation nationale) : une ligne par période de vacances et par zone
SCOLAIRE_URL <- paste0("https://data.education.gouv.fr/api/explore/v2.1/catalog/datasets/",
                       "fr-en-calendrier-scolaire/exports/csv?delimiter=%3B")

SYNOP_BASE_URL <- "https://donneespubliques.meteofrance.fr/donnees_libres/Txt/Synop/Archive"

# ---- Stations SYNOP et poids d'agrégation spatiale --------------------
# Identifiants OMM vérifiés : les 12 stations existent bien dans
# les fichiers SYNOP (contrôle C5 de 02b_controles.R). Poids = ordre de grandeur de la population de
# l'agglomération (millions) : à justifier ou remplacer par des chiffres INSEE.
STATIONS <- tibble::tribble(
  ~numer_sta, ~nom,                    ~poids,
  "07149",    "Paris-Orly",            12.5,   # Remplace 07156 (absent de SYNOP)
  "07481",    "Lyon-Saint-Exupery",     2.3,   # Remplace 07480 (absent de SYNOP)
  "07650",    "Marseille-Marignane",    1.9,
  "07630",    "Toulouse-Blagnac",       1.4,
  "07510",    "Bordeaux-Merignac",      1.4,
  "07015",    "Lille-Lesquin",          1.2,
  "07222",    "Nantes-Bouguenais",      1.0,
  "07690",    "Nice-Cote-d-Azur",       1.0,
  "07190",    "Strasbourg-Entzheim",    0.8,
  "07643",    "Montpellier",            0.8,
  "07130",    "Rennes-Saint-Jacques",   0.75,
  "07110",    "Brest-Guipavas",         0.4
)
POIDS_TOTAL      <- sum(STATIONS$poids)
SEUIL_COUVERTURE <- 0.70   # part minimale du poids total pour valider un agrégat

# ---- Chemins ----------------------------------------------------------
DIR_RAW   <- "data/raw"
DIR_PROC  <- "data/processed"
DIR_OUT   <- "results"
F_ECO     <- file.path(DIR_RAW, "eco2mix_cons_def.csv")
F_SCOLAIRE <- file.path(DIR_RAW, "calendrier_scolaire.csv")
F_MASTER  <- file.path(DIR_PROC, "master_horaire.rds")
for (d in c(DIR_RAW, file.path(DIR_RAW, "synop"), DIR_PROC, DIR_OUT))
  dir.create(d, recursive = TRUE, showWarnings = FALSE)

# ---- Bornes de la grille horaire (en UTC) -----------------------------
T0_UTC <- with_tz(as.POSIXct(paste(DATE_DEBUT, "00:00:00"), tz = TZ_LOCAL), "UTC")
T1_UTC <- with_tz(as.POSIXct(paste(DATE_FIN,   "23:00:00"), tz = TZ_LOCAL), "UTC")
