# Disponibilité des variables à 14 h (jour J) — lignes « données »

Question de référence : cette prévision aurait-elle pu être calculée à 14 h le jour J ?

| Variable | Source | Disponibilité | Observée / prévue | Utilisée | Risque de fuite |
|---|---|---|---|---|---|
| Consommation J-1 et avant | éCO2mix (consolidée) | Latence supposée 1 h | Observée | oui | Faible : valeurs consolidées au lieu des provisoires |
| Consommation de J jusqu'à 13 h | éCO2mix | Dernière heure utilisable [12 h, 13 h[ (règle k = h + 12) | Observée | oui, pour h ≤ 12 | Aucun si la règle est respectée |
| Température observée J | SYNOP | Pas de 3 h, dernière observation ≥ 1 h avant l'origine (9 h UTC en été, 12 h UTC en hiver) | Observée | oui, non interpolée (`temp_obs`) | Aucun ; `temp_interp_oracle` est réservée à la météo parfaite et à l'exploration |
| Vent, humidité J | SYNOP | Idem | Observée | [à décider] | Idem |
| Météo de J+1 | SYNOP | Après J+1 | Observée | Météo parfaite seulement | Fuite si utilisée en opérationnel |
| Calendrier de J+1 | Construit | Connu à l'avance | Connu | oui | Aucun (vacances scolaires non incluses) |

À compléter par l'étape variables : retards, moyennes glissantes, variables dérivées.
