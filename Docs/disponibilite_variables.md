# Disponibilité des variables à 14 h (jour J) — lignes « données »

Question de référence : cette prévision aurait-elle pu être calculée à 14 h le jour J ?

| Variable | Source | Disponibilité | Observée / prévue | Utilisée | Risque de fuite |
|---|---|---|---|---|---|
| Consommation J-1 et avant | éCO2mix (consolidée) | Latence supposée 1 h | Observée | oui | Faible : valeurs consolidées au lieu des provisoires |
| Consommation de J jusqu'à 13 h | éCO2mix | Dernière heure utilisable [12 h, 13 h[ (règle k = h + 12) | Observée | oui, pour h ≤ 12 | Aucun si la règle est respectée |
| Température observée J | SYNOP | Pas de 3 h, dernière observation ≥ 1 h avant l'origine (9 h UTC en été, 12 h UTC en hiver) | Observée | oui : `temp_derniere`, `temp_moy_24h`, `temp_moy_72h` (non interpolée) | Aucun ; `temp_interp_oracle` est réservée à la météo parfaite et à l'exploration |
| Vent, humidité J | SYNOP | Idem | Observée | oui : `vent_derniere`, `hum_derniere` (candidates) | Idem |
| Météo de J+1 | SYNOP | Après J+1 | Observée | Météo parfaite seulement : `parf_temp_horaire`, `parf_temp_moy_jour` | Fuite si utilisée en opérationnel |
| Calendrier de J+1 (jour, mois, férié, pont, fin d'année) | Construit | Connu à l'avance | Connu | oui | Aucun |
| Vacances scolaires de J+1 (`n_zones_vacances`, 0 à 3) | Éducation nationale | Calendrier publié des années à l'avance | Connu | oui | Aucun |
| Même heure la veille (`conso_lag1`) | éCO2mix | Disponible seulement si h ≤ 12 (heure de J+1) | Observée | oui, vide si h > 12 | Contrôle bloquant dans `03_features.R` |
| Même heure 7 jours avant (`conso_lag7`) | éCO2mix | Toujours disponible | Observée | oui | Aucun |
| Dernière heure connue, moyennes 24 h et 7 j (`conso_derniere`, `conso_moy_24h`, `conso_moy_7j`) | éCO2mix | Heure [12 h, 13 h[ de J et avant | Observée | oui | Aucun |

La disponibilité est calculée dans `03_features.R` à partir des horodatages (origine moins latence), pas écrite à la main.
