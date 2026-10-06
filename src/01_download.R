# =====================================================================
# 01_download.R : récupération des données brutes (étape coûteuse)
# - éCO2mix consolidé/définitif : un seul fichier (2 colonnes, pas de 30 min)
# - SYNOP Météo-France : un fichier .csv.gz par mois (déjà présents = ignorés)
# Les fichiers bruts ne sont jamais modifiés par la suite.
# =====================================================================
if (!file.exists("src/00_config.R"))
  stop("Lancer depuis la racine du projet : ouvrir projet-prevision-electricite.Rproj dans RStudio.")
source("src/00_config.R")
options(timeout = 900)

# ---- Validation des fichiers téléchargés ---------------------------------
# Un site qui a changé d'adresse renvoie souvent une page HTML au lieu du
# fichier demandé : on vérifie le contenu, pas seulement la taille.
eco_valide <- function(f) file.exists(f) && file.size(f) > 1e5 &&
  grepl("date_heure", readLines(f, n = 1, warn = FALSE), fixed = TRUE)
gz_valide  <- function(f) file.exists(f) && file.size(f) > 0 &&
  identical(readBin(f, "raw", 2), as.raw(c(0x1f, 0x8b)))     # en-tête gzip

# ---- éCO2mix ------------------------------------------------------------
if (!eco_valide(F_ECO)) {
  message("Téléchargement éCO2mix ...")
  download.file(ECO2MIX_URL, F_ECO, mode = "wb", quiet = FALSE)
}
if (!eco_valide(F_ECO))
  stop("Fichier éCO2mix invalide (page d'erreur ?). Vérifier ECO2MIX_URL dans 00_config.R.")
message("éCO2mix : ", round(file.size(F_ECO) / 1e6, 1), " Mo")

# Ancien fichier de stations (l'URL renvoyait une page HTML) : plus utilisé
unlink(file.path(DIR_RAW, "postesSynop.csv"))

# ---- SYNOP mensuel ------------------------------------------------------
mois <- seq(floor_date(DATE_DEBUT, "month"), floor_date(DATE_FIN, "month"), by = "month")
echecs <- character(0)
for (i in seq_along(mois)) {
  ym   <- format(mois[i], "%Y%m")
  dest <- file.path(DIR_RAW, "synop", paste0("synop.", ym, ".csv.gz"))
  if (gz_valide(dest)) next
  res <- try(download.file(paste0(SYNOP_BASE_URL, "/synop.", ym, ".csv.gz"),
                           dest, mode = "wb", quiet = TRUE), silent = TRUE)
  if (inherits(res, "try-error") || !gz_valide(dest)) {
    echecs <- c(echecs, ym)
    if (file.exists(dest)) file.remove(dest)
  }
}
if (length(echecs) > 0) {
  warning("Mois SYNOP non téléchargés (", length(echecs), ") : ",
          paste(echecs, collapse = ", "),
          "\nVérifier SYNOP_BASE_URL dans 00_config.R.")
} else message("SYNOP : ", length(mois), " fichiers mensuels OK")
