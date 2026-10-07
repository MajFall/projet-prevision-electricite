# =====================================================================
# 02c_exploration.R : exploration des données
# Entrée : data/processed/master_horaire.rds
# Sortie : figures e01 à e09 (PNG) et tableaux (CSV) dans results/,
#          + results/e00_resume_exploration.txt (chiffres clés à relire).
#
# Règle de rigueur : on n'explore QUE 2018-2024 (apprentissage + validation).
# L'année de test n'est jamais regardée, pour ne pas choisir des variables
# ou des modèles en ayant vu le test final.
#
# Un bloc = une figure. Les blocs sont indépendants : on peut en relancer un seul
# après avoir exécuté la partie « Préparation » ci-dessous.
# =====================================================================
if (!file.exists("src/00_config.R"))
  stop("Lancer depuis la racine du projet : ouvrir projet-prevision-electricite.Rproj dans RStudio.")
source("src/00_config.R")
library(ggplot2)

# ---------------------------------------------------------------------
# Préparation : style, fonctions d'aide, tables de travail
# ---------------------------------------------------------------------
BLEU <- "#2a78d6"; ORANGE <- "#eb6834"; VERT <- "#1baf7a"
VIOLET <- "#6250d6"; ROUGE <- "#e34948"; GRIS <- "#8a8a8a"
theme_set(theme_minimal(base_size = 11) +
  theme(plot.title = element_text(face = "bold", size = 12),
        plot.subtitle = element_text(colour = "grey35"),
        panel.grid.minor = element_blank(), legend.position = "bottom"))

sauve <- function(p, nom, l = 10, h = 5.5)
  ggsave(file.path(DIR_OUT, nom), p, width = l, height = h, dpi = 150, bg = "white")

# Les phrases « chiffres clés » sont affichées et gardées pour le fichier résumé.
RESUME <- character(0)
note <- function(...) { ligne <- paste0(...); RESUME <<- c(RESUME, ligne); message(ligne) }

# Moyenne glissante qui ignore les NA (utilisée pour les tendances).
moy_glissante <- function(x, n)
  zoo::rollapply(x, n, function(v) mean(v, na.rm = TRUE), fill = NA, align = "center")

# Type de jour et saison, pour les graphiques.
master <- readRDS(F_MASTER) %>%
  mutate(type_jour = factor(case_when(ferie & !weekend ~ "Férié (en semaine)",
                                      pont             ~ "Pont",
                                      weekend          ~ if_else(jour_sem == 6, "Samedi", "Dimanche"),
                                      TRUE             ~ "Jour ouvré normal"),
                            levels = c("Jour ouvré normal", "Pont", "Férié (en semaine)", "Samedi", "Dimanche")),
         saison = factor(case_when(mois %in% c(12, 1, 2) ~ "Hiver",
                                   mois %in% 3:5         ~ "Printemps",
                                   mois %in% 6:8         ~ "Été",
                                   TRUE                  ~ "Automne"),
                         levels = c("Hiver", "Printemps", "Été", "Automne")))

# On garde 2018-2024 seulement.
master_expl <- master %>% filter(date_loc <= FIN_VALIDATION)
note("Période explorée : ", format(min(master_expl$date_loc)), " -> ",
     format(max(master_expl$date_loc)), " (test ", year(FIN_VALIDATION) + 1, " exclu)")

# Table journalière : une ligne par jour. Un jour est « complet » s'il a 24 h
# de consommation connue (les jours à 23 h / 25 h et ceux avec un trou sont écartés).
quot <- master_expl %>%
  group_by(date_loc) %>%
  summarise(n_h_jour = first(n_h_jour),
            n_conso  = sum(!is.na(conso_mw)),
            conso_j  = mean(conso_mw, na.rm = TRUE),
            temp_j   = if (sum(!is.na(temp_obs)) >= 6) mean(temp_obs, na.rm = TRUE) else NA_real_,
            across(c(annee, mois, jour_sem, ferie, pont, creux_fin_annee, n_zones_vacances, type_jour, saison), first),
            .groups = "drop") %>%
  mutate(complet = n_h_jour == 24 & n_conso == 24,
         conso_j = if_else(complet, conso_j, NA_real_))

# Table horaire : heures des jours de 24 h avec consommation connue.
hh <- master_expl %>% filter(!jour_chgt_heure, !is.na(conso_mw))

# ---------------------------------------------------------------------
# E1 : la série dans le temps (niveau, tendance, événements)
# ---------------------------------------------------------------------
q1 <- quot %>% mutate(gw = conso_j / 1000, tendance = moy_glissante(gw, 365))
p <- ggplot(q1, aes(date_loc, gw)) +
  annotate("rect", xmin = CONFINEMENT_DEBUT, xmax = CONFINEMENT_FIN,
           ymin = -Inf, ymax = Inf, fill = ORANGE, alpha = .18) +
  annotate("rect", xmin = as.Date("2022-10-01"), xmax = as.Date("2023-03-31"),
           ymin = -Inf, ymax = Inf, fill = VIOLET, alpha = .12) +
  geom_vline(xintercept = as.numeric(FIN_APPRENTISSAGE) + 0.5, linetype = "dashed", colour = GRIS) +
  geom_line(colour = BLEU, linewidth = .3, na.rm = TRUE) +
  geom_line(aes(y = tendance), colour = ROUGE, linewidth = 1, na.rm = TRUE) +
  annotate("text", x = as.Date("2020-04-14"), y = Inf, label = "Confinement",
           vjust = 1.6, size = 3, colour = ORANGE) +
  annotate("text", x = as.Date("2023-01-01"), y = Inf, label = "Sobriété énergétique",
           vjust = 1.6, size = 3, colour = VIOLET) +
  annotate("text", x = FIN_APPRENTISSAGE + 20, y = -Inf, label = "validation",
           vjust = -1, hjust = 0, size = 3, colour = GRIS) +
  labs(title = "Consommation journalière moyenne en France",
       subtitle = "Bleu : jours complets ; rouge : moyenne glissante sur 365 jours ; zones colorées : périodes indicatives",
       x = NULL, y = "GW (moyenne du jour)")
sauve(p, "e01_serie_journaliere.png")
m <- q1 %>% filter(!is.na(tendance))
note("E1 tendance 365 j : min ", round(min(m$tendance), 1), " GW (", format(m$date_loc[which.min(m$tendance)]),
     "), max ", round(max(m$tendance), 1), " GW (", format(m$date_loc[which.max(m$tendance)]), ")")

# ---------------------------------------------------------------------
# E2 : cycle journalier (profil horaire moyen par saison et type de jour)
# ---------------------------------------------------------------------
prof <- hh %>%
  filter(type_jour %in% c("Jour ouvré normal", "Samedi", "Dimanche")) %>%
  group_by(type_jour, saison, h_loc) %>%
  summarise(gw = mean(conso_mw) / 1000, .groups = "drop")
p <- ggplot(prof, aes(h_loc, gw, colour = saison)) +
  geom_line(linewidth = 1) +
  facet_wrap(~ type_jour) +
  scale_x_continuous(breaks = seq(0, 23, 3)) +
  scale_colour_manual(values = c("Hiver" = BLEU, "Printemps" = VERT, "Été" = ORANGE, "Automne" = VIOLET)) +
  labs(title = "Cycle journalier : profil horaire moyen",
       subtitle = "Heure locale ; hors jours fériés, ponts et jours de changement d'heure",
       x = "Heure locale", y = "GW", colour = NULL)
sauve(p, "e02_cycle_journalier.png", h = 4.8)
w <- prof %>% filter(type_jour == "Jour ouvré normal") %>% group_by(saison) %>%
  summarise(h_min = h_loc[which.min(gw)], h_max = h_loc[which.max(gw)],
            ecart_gw = round(max(gw) - min(gw), 1), .groups = "drop")
for (i in seq_len(nrow(w)))
  note("E2 jour ouvré, ", as.character(w$saison[i]), " : minimum à ", w$h_min[i],
       " h, maximum à ", w$h_max[i], " h, amplitude ", w$ecart_gw[i], " GW")

# ---------------------------------------------------------------------
# E3 : cycle hebdomadaire (jour de la semaine x heure)
# ---------------------------------------------------------------------
hm <- hh %>% filter(!ferie, !pont) %>%
  group_by(jour_sem, h_loc) %>%
  summarise(gw = mean(conso_mw) / 1000, .groups = "drop") %>%
  mutate(jour = factor(jour_sem, levels = 7:1,
                       labels = c("Dim", "Sam", "Ven", "Jeu", "Mer", "Mar", "Lun")))
p <- ggplot(hm, aes(h_loc, jour, fill = gw)) +
  geom_tile() +
  scale_fill_gradient(low = "#e6f1fb", high = "#0c447c") +
  scale_x_continuous(breaks = seq(0, 23, 3), expand = c(0, 0)) +
  labs(title = "Cycle hebdomadaire : consommation moyenne par jour et heure",
       subtitle = "Hors jours fériés et ponts", x = "Heure locale", y = NULL, fill = "GW") +
  theme(legend.key.width = unit(1.5, "cm"))
sauve(p, "e03_cycle_hebdomadaire.png", h = 4.2)
j <- quot %>% filter(!ferie, !pont, complet) %>% group_by(jour_sem) %>%
  summarise(gw = mean(conso_j) / 1000, .groups = "drop")
note("E3 conso journalière moyenne (GW), lun à dim : ", paste(round(j$gw, 1), collapse = " / "))

# ---------------------------------------------------------------------
# E4 : saisonnalité annuelle (une courbe par année)
# ---------------------------------------------------------------------
mens <- quot %>% filter(complet) %>%
  group_by(annee, mois) %>%
  summarise(gw = mean(conso_j) / 1000, .groups = "drop")
p <- ggplot(mens, aes(mois, gw, colour = factor(annee), group = annee)) +
  geom_line(linewidth = .9) + geom_point(size = 1.4) +
  scale_x_continuous(breaks = 1:12, labels = c("J", "F", "M", "A", "M", "J", "J", "A", "S", "O", "N", "D")) +
  scale_colour_viridis_d(end = .9) +
  labs(title = "Saisonnalité annuelle : consommation moyenne par mois",
       subtitle = "Une courbe par année ; l'écart entre courbes révèle les ruptures de niveau",
       x = "Mois", y = "GW", colour = NULL)
sauve(p, "e04_saisonnalite_annuelle.png", h = 4.8)
ms <- mens %>% group_by(mois) %>% summarise(gw = mean(gw), .groups = "drop")
note("E4 mois le plus consommateur : ", ms$mois[which.max(ms$gw)], " (", round(max(ms$gw), 1),
     " GW) ; le moins : ", ms$mois[which.min(ms$gw)], " (", round(min(ms$gw), 1), " GW)")

# ---------------------------------------------------------------------
# E5a : relation température - consommation (thermosensibilité)
# ---------------------------------------------------------------------
th_all <- quot %>%
  filter(complet, !is.na(temp_j), type_jour %in% c("Jour ouvré normal", "Samedi", "Dimanche")) %>%
  mutate(groupe = if_else(type_jour == "Jour ouvré normal", "Jour ouvré normal", "Week-end"))
th <- th_all %>% filter(groupe == "Jour ouvré normal")

# Seuil de chauffage : le seuil s qui donne la meilleure droite
# consommation = a + b * min(température, s) sur les jours ouvrés.
seuils <- 10:22
erreurs <- sapply(seuils, function(s) sum(resid(lm(conso_j ~ pmin(temp_j, s), data = th))^2))
S_OPT <- seuils[which.min(erreurs)]
pente_froid <- -unname(coef(lm(conso_j ~ pmin(temp_j, S_OPT), data = th))[2])
chaud <- th %>% filter(temp_j > S_OPT + 4)
pente_chaud <- if (nrow(chaud) > 30) unname(coef(lm(conso_j ~ temp_j, data = chaud))[2]) else NA_real_
write_csv(tibble(seuil_chauffage_C = S_OPT, pente_froid_MW_par_C = round(pente_froid),
                 pente_chaud_MW_par_C = round(pente_chaud)),
          file.path(DIR_OUT, "e05_thermosensibilite.csv"))

p <- ggplot(th_all, aes(temp_j, conso_j / 1000, colour = groupe)) +
  geom_point(alpha = .35, size = 1) +
  geom_smooth(method = "loess", formula = y ~ x, se = FALSE, linewidth = 1.1) +
  geom_vline(xintercept = S_OPT, linetype = "dashed", colour = GRIS) +
  scale_colour_manual(values = c("Jour ouvré normal" = BLEU, "Week-end" = ORANGE)) +
  labs(title = "Relation température - consommation (un point = un jour)",
       subtitle = paste0("Seuil de chauffage estimé : ", S_OPT, " °C (jours ouvrés)"),
       x = "Température moyenne du jour (°C, 12 stations pondérées)", y = "Consommation moyenne (GW)",
       colour = NULL)
sauve(p, "e05a_temperature_consommation.png")
note("E5 seuil de chauffage estimé : ", S_OPT, " °C ; pente sous le seuil : ", round(pente_froid),
     " MW par °C en moins ; au-dessus de ", S_OPT + 4, " °C : ", round(pente_chaud), " MW par °C (climatisation)")

# ---------------------------------------------------------------------
# E5b : thermosensibilité selon l'heure du jour
# ---------------------------------------------------------------------
hj <- hh %>%
  filter(type_jour == "Jour ouvré normal") %>%
  left_join(quot %>% select(date_loc, temp_j), by = "date_loc") %>%
  filter(!is.na(temp_j))
sens <- hj %>% group_by(h_loc) %>%
  summarise(pente = -unname(coef(lm(conso_mw ~ pmin(temp_j, S_OPT)))[2]), .groups = "drop")
p <- ggplot(sens, aes(h_loc, pente)) +
  geom_col(fill = BLEU, width = .7) +
  scale_x_continuous(breaks = seq(0, 23, 3)) +
  labs(title = "Thermosensibilité selon l'heure du jour",
       subtitle = paste0("MW de consommation en plus par °C en moins, sous ", S_OPT, " °C (jours ouvrés)"),
       x = "Heure locale", y = "MW par °C")
sauve(p, "e05b_thermosensibilite_par_heure.png", h = 4.2)
note("E5b thermosensibilité maximale à ", sens$h_loc[which.max(sens$pente)], " h (",
     round(max(sens$pente)), " MW/°C), minimale à ", sens$h_loc[which.min(sens$pente)], " h (",
     round(min(sens$pente)), " MW/°C)")

# ---------------------------------------------------------------------
# E6 : jours fériés, ponts et creux de fin d'année
# On divise la consommation du jour par la moyenne centrée sur 35 jours (5 semaines
# pleines) : cela retire le niveau de saison et le cycle hebdomadaire moyen.
# ---------------------------------------------------------------------
q6 <- quot %>%
  mutate(ref = moy_glissante(conso_j, 35), ratio = conso_j / ref) %>%
  filter(!is.na(ratio))

p <- ggplot(q6, aes(type_jour, ratio)) +
  geom_hline(yintercept = 1, colour = GRIS, linetype = "dashed") +
  geom_boxplot(fill = "#b5d4f4", colour = BLEU, outlier.alpha = .4) +
  labs(title = "Effet du type de jour sur la consommation",
       subtitle = "Consommation du jour / moyenne centrée sur 35 jours (1 = niveau du moment)",
       x = NULL, y = "Rapport")
sauve(p, "e06a_types_de_jour.png", h = 4.8)
med <- q6 %>% group_by(type_jour) %>% summarise(m = median(ratio), n = n(), .groups = "drop")
for (i in seq_len(nrow(med)))
  note("E6 ", as.character(med$type_jour[i]), " : rapport médian ", round(med$m[i], 3), " (", med$n[i], " jours)")

fin <- q6 %>% filter(creux_fin_annee) %>%
  mutate(lab = factor(format(date_loc, "%d/%m"), levels = c(sprintf("%02d/12", 24:31), "01/01")))
p <- ggplot(fin, aes(lab, ratio)) +
  geom_hline(yintercept = 1, colour = GRIS, linetype = "dashed") +
  geom_boxplot(fill = "#f5c4b3", colour = ORANGE, outlier.alpha = .4) +
  labs(title = "Creux de fin d'année (24 décembre - 1er janvier)",
       subtitle = "Une observation par année (2018-2024)", x = "Jour",
       y = "Rapport à la moyenne centrée sur 35 jours")
sauve(p, "e06b_fin_annee.png", h = 4.5)

# ---------------------------------------------------------------------
# E6c : vacances scolaires (nombre de zones A/B/C en vacances, 0 à 3)
# On retire d'abord l'effet de la température (modèle de chauffage) et le niveau de
# chaque année ; il reste un écart, en GW, qu'on compare selon le nombre de zones en
# vacances. Jours ouvrés normaux seulement, hors fin d'année (déjà traitée en E6b).
# ---------------------------------------------------------------------
v <- quot %>%
  filter(complet, !is.na(temp_j), type_jour == "Jour ouvré normal", !creux_fin_annee)
v$ecart_gw <- resid(lm(conso_j ~ pmin(temp_j, S_OPT) + factor(annee), data = v)) / 1000
v$zones <- factor(v$n_zones_vacances, levels = 0:3)

p <- ggplot(v, aes(zones, ecart_gw)) +
  geom_hline(yintercept = 0, colour = GRIS, linetype = "dashed") +
  geom_boxplot(fill = "#c8ecdc", colour = VERT, outlier.alpha = .4) +
  labs(title = "Effet des vacances scolaires sur la consommation",
       subtitle = "Écart à la consommation attendue selon la température et l'année ; jours ouvrés normaux",
       x = "Nombre de zones (A, B, C) en vacances", y = "Écart (GW)")
sauve(p, "e06c_vacances_scolaires.png", h = 4.5)
med_v <- v %>% group_by(zones) %>% summarise(m = median(ecart_gw), n = n(), .groups = "drop")
for (i in seq_len(nrow(med_v)))
  note("E6c vacances, ", med_v$zones[i], " zone(s) : écart médian ", round(med_v$m[i], 2),
       " GW (", med_v$n[i], " jours)")

# ---------------------------------------------------------------------
# E7 : ruptures de niveau d'une année à l'autre
# Indicateur « à météo comparable » : consommation moyenne des jours ouvrés
# normaux dont la température du jour est entre 10 et 20 °C.
# ---------------------------------------------------------------------
tab7 <- quot %>% filter(complet) %>% group_by(annee) %>%
  summarise(conso_moy_gw = mean(conso_j) / 1000, temp_moy = mean(temp_j, na.rm = TRUE), .groups = "drop")
meteo_comparable <- quot %>%
  filter(complet, type_jour == "Jour ouvré normal", !is.na(temp_j), temp_j >= 10, temp_j <= 20) %>%
  group_by(annee) %>%
  summarise(conso_ouvre_10_20C_gw = mean(conso_j) / 1000, n_jours = n(), .groups = "drop")
tab7 <- tab7 %>%
  left_join(meteo_comparable, by = "annee") %>%
  mutate(ecart_vs_2019_pct = round(100 * (conso_ouvre_10_20C_gw / conso_ouvre_10_20C_gw[annee == 2019] - 1), 1),
         conso_moy_gw = round(conso_moy_gw, 2), temp_moy = round(temp_moy, 2),
         conso_ouvre_10_20C_gw = round(conso_ouvre_10_20C_gw, 2))
write_csv(tab7, file.path(DIR_OUT, "e07_moyennes_annuelles.csv"))
print(as.data.frame(tab7))

p <- ggplot(tab7, aes(factor(annee), ecart_vs_2019_pct)) +
  geom_col(fill = BLEU, width = .65) +
  geom_hline(yintercept = 0, colour = "grey30") +
  geom_text(aes(label = paste0(ecart_vs_2019_pct, " %"),
                vjust = if_else(ecart_vs_2019_pct >= 0, -0.4, 1.3)), size = 3.4) +
  labs(title = "Niveau de consommation à météo comparable, par rapport à 2019",
       subtitle = "Jours ouvrés normaux, température du jour entre 10 et 20 °C",
       x = NULL, y = "Écart à 2019 (%)")
sauve(p, "e07_ruptures_annuelles.png", h = 4.5)
note("E7 écart à 2019 (%) par année : ",
     paste(tab7$annee, tab7$ecart_vs_2019_pct, sep = "=", collapse = ", "))

# ---------------------------------------------------------------------
# E8a : autocorrélation (horaire et journalière)
# ---------------------------------------------------------------------
xj <- quot$conso_j
xh <- master_expl %>% arrange(heure_utc) %>% pull(conso_mw)
a_h <- acf(xh, lag.max = 24 * 14, na.action = na.pass, plot = FALSE)
a_j <- acf(xj, lag.max = 60,      na.action = na.pass, plot = FALSE)
d <- bind_rows(
  tibble(panel = "Série horaire (retard en jours)", lag_j = as.numeric(a_h$lag) / 24,
         acf = as.numeric(a_h$acf), b = 1.96 / sqrt(sum(!is.na(xh)))),
  tibble(panel = "Série journalière (retard en jours)", lag_j = as.numeric(a_j$lag),
         acf = as.numeric(a_j$acf), b = 1.96 / sqrt(sum(!is.na(xj))))) %>%
  filter(lag_j > 0)
p <- ggplot(d, aes(lag_j, acf)) +
  geom_hline(yintercept = 0, colour = "grey30") +
  geom_hline(aes(yintercept = b), linetype = "dashed", colour = ROUGE) +
  geom_hline(aes(yintercept = -b), linetype = "dashed", colour = ROUGE) +
  geom_segment(aes(xend = lag_j, yend = 0), colour = BLEU, linewidth = .5) +
  facet_wrap(~ panel, scales = "free_x", ncol = 1) +
  labs(title = "Autocorrélation de la consommation",
       subtitle = "Pics tous les jours (série horaire) et toutes les semaines (série journalière)",
       x = "Retard (jours)", y = "ACF")
sauve(p, "e08a_autocorrelation.png", h = 6)
acf_a <- function(a, k) round(as.numeric(a$acf)[k + 1], 3)       # valeur de l'ACF au retard k
note("E8 ACF horaire : retard 1 h = ", acf_a(a_h, 1), ", 24 h = ", acf_a(a_h, 24), ", 168 h = ", acf_a(a_h, 168))
note("E8 ACF journalière : retard 1 j = ", acf_a(a_j, 1), ", 7 j = ", acf_a(a_j, 7), ", 14 j = ", acf_a(a_j, 14))

# ---------------------------------------------------------------------
# E8b : décomposition STL (tendance, saison hebdomadaire, reste)
# ---------------------------------------------------------------------
xf <- zoo::na.approx(xj / 1000, na.rm = FALSE, rule = 2)         # trous comblés pour cet exercice
s <- stl(ts(xf, frequency = 7), s.window = "periodic", t.window = 91, robust = TRUE)
cp <- as.data.frame(s$time.series)
dec <- tibble(date_loc = quot$date_loc,
              `Série` = as.numeric(xf),
              `Tendance et saison annuelle` = cp$trend,
              `Reste` = cp$remainder) %>%
  pivot_longer(-date_loc, names_to = "composante", values_to = "gw") %>%
  mutate(composante = factor(composante, levels = c("Série", "Tendance et saison annuelle", "Reste")))
p <- ggplot(dec, aes(date_loc, gw)) +
  geom_line(colour = BLEU, linewidth = .35) +
  facet_grid(composante ~ ., scales = "free_y") +
  labs(title = "Décomposition STL de la consommation journalière (période 7 jours)",
       subtitle = "Les jours à 23 h ou 25 h sont interpolés pour cet exercice ; motif de la semaine : figure e08c", x = NULL, y = "GW")
sauve(p, "e08b_decomposition_stl.png", h = 6)

# Le motif hebdomadaire est le même toutes les semaines : on montre une seule semaine.
semaine <- tibble(jour_sem = quot$jour_sem[1:7], gw = cp$seasonal[1:7]) %>%
  mutate(jour = factor(jour_sem, levels = 1:7, labels = c("Lun", "Mar", "Mer", "Jeu", "Ven", "Sam", "Dim")))
p <- ggplot(semaine, aes(jour, gw)) +
  geom_col(fill = BLEU, width = .65) +
  geom_hline(yintercept = 0, colour = "grey30") +
  labs(title = "Motif hebdomadaire de la consommation (composante saisonnière du STL)",
       subtitle = "Écart au niveau de la semaine, en GW", x = NULL, y = "GW")
sauve(p, "e08c_motif_hebdomadaire.png", h = 4)
note("E8 STL : amplitude hebdomadaire ", round(diff(range(cp$seasonal)), 2),
     " GW ; écart-type du reste ", round(sd(cp$remainder), 2), " GW ; écart-type de la série ",
     round(sd(xf), 2), " GW")

# ---------------------------------------------------------------------
# E9 : quelles informations utiliser à 14 h pour prévoir J+1 ?
# À 14 h le jour J (latence de 1 h), la dernière heure connue est [12 h, 13 h[ de J.
# Pour la cible (J+1, heure h), trois prédicteurs naïfs :
#   - même heure la veille (J, h)    : disponible seulement si h <= 12
#   - même heure 7 jours avant       : toujours disponible
#   - dernier relevé connu (J, 12 h) : toujours disponible
# On compare leur erreur absolue moyenne (MAE), hors fériés et ponts
# (pour la cible et pour les jours de référence).
# ---------------------------------------------------------------------
# Une ligne par jour, une colonne par heure (h0 ... h23).
w <- hh %>% filter(n_h_jour == 24) %>%
  select(date_loc, h_loc, conso_mw) %>%
  pivot_wider(names_from = h_loc, values_from = conso_mw, names_prefix = "h")

# Décale un tableau de k jours : la ligne du jour D devient la ligne du jour D + k.
decale <- function(d, k) d %>% mutate(date_loc = date_loc + k)
info <- quot %>% transmute(date_loc, special = ferie | pont, semaine = jour_sem <= 5)

j <- w %>%
  inner_join(rename_with(decale(w, 1), ~ paste0(.x, "_v"), starts_with("h")), by = "date_loc") %>%   # veille
  inner_join(rename_with(decale(w, 7), ~ paste0(.x, "_s"), starts_with("h")), by = "date_loc") %>%   # 7 jours avant
  inner_join(info, by = "date_loc") %>%
  inner_join(info %>% decale(1) %>% transmute(date_loc, sp_v = special), by = "date_loc") %>%
  inner_join(info %>% decale(7) %>% transmute(date_loc, sp_s = special), by = "date_loc") %>%
  filter(!special, !sp_v, !sp_s)
note("E9 jours utilisables pour la comparaison : ", nrow(j))

res9 <- map_dfr(0:23, function(h) {
  y <- j[[paste0("h", h)]]
  tibble(h_loc = h, semaine = j$semaine,
         `Même heure la veille (si h <= 12)` =
           if (h <= 12) abs(y - j[[paste0("h", h, "_v")]]) else NA_real_,
         `Même heure 7 jours avant` = abs(y - j[[paste0("h", h, "_s")]]),
         `Dernier relevé connu (12 h)` = abs(y - j[["h12_v"]]))
}) %>%
  pivot_longer(-c(h_loc, semaine), names_to = "predicteur", values_to = "ae") %>%
  filter(!is.na(ae)) %>%
  mutate(cible = if_else(semaine, "Cible : lundi à vendredi", "Cible : samedi et dimanche")) %>%
  group_by(cible, h_loc, predicteur) %>%
  summarise(mae_mw = mean(ae), .groups = "drop")
write_csv(res9 %>% mutate(mae_mw = round(mae_mw)), file.path(DIR_OUT, "e09_mae_predicteurs_naifs.csv"))

p <- ggplot(res9, aes(h_loc, mae_mw / 1000, colour = predicteur)) +
  geom_line(linewidth = 1) + geom_point(size = 1.2) +
  facet_wrap(~ cible) +
  scale_x_continuous(breaks = seq(0, 23, 3)) +
  scale_colour_manual(values = c("Même heure la veille (si h <= 12)" = VERT,
                                 "Même heure 7 jours avant" = BLEU,
                                 "Dernier relevé connu (12 h)" = ORANGE)) +
  guides(colour = guide_legend(nrow = 3)) +
  labs(title = "Prévoir J+1 à 14 h : erreur de trois prédicteurs naïfs",
       subtitle = "MAE selon l'heure cible (heure locale du jour J+1)",
       x = "Heure cible (J+1)", y = "MAE (GW)", colour = NULL)
sauve(p, "e09_retards_admissibles.png", h = 5.2)
m9 <- res9 %>% group_by(cible, predicteur) %>% summarise(m = round(mean(mae_mw)), .groups = "drop")
for (i in seq_len(nrow(m9)))
  note("E9 MAE moyenne, ", m9$cible[i], ", ", m9$predicteur[i], " : ", m9$m[i], " MW")

# ---------------------------------------------------------------------
# Résumé des chiffres clés
# ---------------------------------------------------------------------
writeLines(RESUME, file.path(DIR_OUT, "e00_resume_exploration.txt"))
message("\nFigures et tableaux dans ", DIR_OUT, "/ ; résumé : e00_resume_exploration.txt")
