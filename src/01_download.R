# =====================================================================
# 01_download.R : télécharge les données brutes dans data/raw/
# Trois sources : éCO2mix (consommation), SYNOP (météo), calendrier scolaire.
# Un fichier déjà présent et valide n'est pas retéléchargé.
# =====================================================================
if (!file.exists("src/00_config.R"))
  stop("Lancer depuis la racine du projet : ouvrir projet-prevision-electricite.Rproj dans RStudio.")
source("src/00_config.R")
options(timeout = 900)   # un téléchargement peut durer plusieurs minutes

# Un site qui change d'adresse renvoie parfois une page HTML à la place du
# fichier : on vérifie donc le contenu du fichier, pas seulement son existence.
csv_valide <- function(fichier, mot_attendu) {
  file.exists(fichier) && file.size(fichier) > 1000 &&
    grepl(mot_attendu, readLines(fichier, n = 1, warn = FALSE), fixed = TRUE)
}
gz_valide <- function(fichier) {   # un fichier .gz commence par les octets 1f 8b
  file.exists(fichier) && file.size(fichier) > 0 &&
    identical(readBin(fichier, "raw", 2), as.raw(c(0x1f, 0x8b)))
}
telecharger <- function(url, fichier) download.file(url, fichier, mode = "wb", quiet = TRUE)

# ---- 1) Consommation : éCO2mix (un seul fichier) --------------------------
if (!csv_valide(F_ECO, "date_heure")) telecharger(ECO2MIX_URL, F_ECO)
if (!csv_valide(F_ECO, "date_heure"))
  stop("Fichier éCO2mix invalide. Vérifier ECO2MIX_URL dans src/00_config.R.")
message("éCO2mix : ", round(file.size(F_ECO) / 1e6, 1), " Mo")

# ---- 2) Calendrier scolaire (un seul petit fichier) -----------------------
if (!csv_valide(F_SCOLAIRE, "start_date")) telecharger(SCOLAIRE_URL, F_SCOLAIRE)
if (!csv_valide(F_SCOLAIRE, "start_date"))
  stop("Calendrier scolaire invalide. Vérifier SCOLAIRE_URL dans src/00_config.R.")
message("Calendrier scolaire : OK")

# ---- 3) Météo : SYNOP (un fichier par mois) -------------------------------
mois <- seq(floor_date(DATE_DEBUT, "month"), floor_date(DATE_FIN, "month"), by = "month")
echecs <- c()
for (ym in format(mois, "%Y%m")) {
  fichier <- file.path(DIR_RAW, "synop", paste0("synop.", ym, ".csv.gz"))
  if (gz_valide(fichier)) next                       # déjà téléchargé
  try(telecharger(paste0(SYNOP_BASE_URL, "/synop.", ym, ".csv.gz"), fichier), silent = TRUE)
  if (!gz_valide(fichier)) {                         # échec : on supprime le fichier invalide
    echecs <- c(echecs, ym)
    if (file.exists(fichier)) file.remove(fichier)
  }
}
if (length(echecs) > 0) {
  warning(length(echecs), " mois SYNOP non téléchargés : ", paste(echecs, collapse = ", "),
          ". Vérifier SYNOP_BASE_URL dans src/00_config.R.")
} else message("SYNOP : ", length(mois), " fichiers mensuels OK")
