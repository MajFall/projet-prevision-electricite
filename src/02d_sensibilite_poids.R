# =====================================================================
# 02d_sensibilite_poids.R : la température nationale dépend-elle des poids ?
# Entrées : data/raw/synop/*.csv.gz et data/processed/master_horaire.rds
# Sortie  : results/s01_sensibilite_poids.csv
#
# Les poids des 12 stations sont des ordres de grandeur (population des
# agglomérations). Plutôt que de les changer (ce qui modifierait toutes les
# variables et donc les résultats), on mesure ici si le choix compte.
# Période : 2018-2024 seulement (le test 2025 n'est pas utilisé).
# =====================================================================
if (!file.exists("src/00_config.R"))
  stop("Lancer depuis la racine du projet : ouvrir projet-prevision-electricite.Rproj dans RStudio.")
source("src/00_config.R")
master <- readRDS(F_MASTER)

# 1) Températures brutes des 12 stations (en °C)
lire_temp <- function(fichier) {
  suppressMessages(
    read_delim(fichier, delim = ";", na = c("", "mq"), show_col_types = FALSE,
               progress = FALSE, col_types = cols(.default = col_character()))) %>%
    select(any_of(c("numer_sta", "date", "t")))
}
fichiers <- list.files(file.path(DIR_RAW, "synop"), pattern = "\\.csv\\.gz$", full.names = TRUE)
temp <- map_dfr(fichiers, lire_temp) %>%
  mutate(numer_sta = sprintf("%05d", suppressWarnings(as.integer(numer_sta))),
         temps_utc = ymd_hms(date, tz = "UTC", quiet = TRUE),
         temp      = as.numeric(t) - 273.15) %>%
  filter(numer_sta %in% STATIONS$numer_sta, !is.na(temps_utc), !is.na(temp)) %>%
  distinct(numer_sta, temps_utc, .keep_all = TRUE)

# 2) Même agrégation que 02_prepare.R, avec un vecteur de poids au choix
#    (l'ordre des poids est celui du tableau STATIONS)
agreger <- function(poids) {
  temp %>%
    mutate(w = poids[match(numer_sta, STATIONS$numer_sta)]) %>%
    group_by(temps_utc) %>%
    summarise(valeur = weighted.mean(temp, w), couv = sum(w) / sum(poids), .groups = "drop") %>%
    filter(couv >= SEUIL_COUVERTURE) %>%
    select(temps_utc, valeur)
}

variantes <- list(
  actuel        = STATIONS$poids,              # poids du projet
  egaux         = rep(1, nrow(STATIONS)),      # 12 stations à poids égal
  plafonnes_a_3 = pmin(STATIONS$poids, 3),     # Paris ramené à 3 (au lieu de 12,5)
  racine        = sqrt(STATIONS$poids))        # poids adoucis

agg <- imap(variantes, function(p, nom) agreger(p) %>% rename(!!nom := valeur)) %>%
  reduce(inner_join, by = "temps_utc")

# 3) Comparaison : écart de température et lien avec la consommation en hiver
res <- agg %>%
  left_join(master %>% select(temps_utc = heure_utc, conso_mw, mois, annee), by = "temps_utc") %>%
  filter(annee <= 2024)
hiver <- res %>% filter(mois %in% c(12, 1, 2), !is.na(conso_mw))

tab <- tibble(variante = names(variantes)) %>%
  rowwise() %>%
  mutate(ecart_abs_moyen_C = round(mean(abs(res[[variante]] - res$actuel)), 2),
         ecart_abs_p95_C   = round(unname(quantile(abs(res[[variante]] - res$actuel), 0.95)), 2),
         cor_conso_hiver   = round(cor(hiver[[variante]], hiver$conso_mw), 3)) %>%
  ungroup()

write_csv(tab, file.path(DIR_OUT, "s01_sensibilite_poids.csv"))
cat("Sensibilité de la température nationale aux poids des stations (2018-2024) :\n")
print(as.data.frame(tab))
cat("Lecture : ecart_abs_* = écart avec les poids du projet (en °C) ;",
    "cor_conso_hiver = corrélation température-consommation en hiver (plus elle est négative, mieux c'est).\n")
