---
title: Visualisations et feuille de route
description: Visualisations Health.md actuellement disponibles dans Obsidian et graphiques prévus, classés par type de données exportées.
---

Health.md exporte un jeu de données local à schéma versionné pour Markdown, Obsidian Bases, JSON et CSV. La feuille de route ci-dessous relie ces données à l’extension de visualisation Obsidian associée. Elle présente les fonctions existantes, celles que les données exportées pourront permettre et les catégories qui nécessitent des graphiques génériques tenant compte du schéma.

<div class="callout">
<strong>Source des données.</strong>
<p style="margin-top:6px;">Cette page est organisée à partir du schéma d’export et du dictionnaire de données de Health.md : activité, sommeil, cœur, signes vitaux, corps, nutrition, pleine conscience, médicaments, entraînements, santé reproductive, symptômes, audition et métriques liées au mode de vie et à l’environnement.</p>
</div>

## Couverture actuelle des visualisations

<div class="reference-stats">
<div><strong>43</strong><span>moteurs de rendu de l’extension à ce jour</span></div>
<div><strong>18</strong><span>catégories de données exportées</span></div>
<div><strong>220+</strong><span>clés d’export canoniques</span></div>
<div><strong>1</strong><span>couche générique de métriques encore nécessaire</span></div>
</div>

## Prise en charge des plateformes par exportateur

La prise en charge des visualisations dépend de la disponibilité des données sources à la fois dans Apple HealthKit et Android Health Connect, ou uniquement dans le contrat d’export Apple HealthKit.

### iOS et Android

Ces visualisations utilisent les champs d’export communs à HealthKit et Health Connect :

| Catégorie | Types de visualisation |
| --- | --- |
| Vue d’ensemble | `intro-stats`, `summary-card`, `trend-tile` |
| Activité | `activity-rings`, `vitals-rings`, `bar-chart`, `activity-heatmap`, `step-spiral`, `weekday-average` |
| Cœur | `heart-terrain`, `heart-range`, `hrv-trend` |
| Respiration et signes vitaux | `oxygen-river`, `oxygen-range`, `breathing-wave` |
| Sommeil | `sleep-schedule`, `sleep-quality-bars`, `sleep-architecture`, `sleep-polar` |
| Mobilité | `walking-symmetry`* |
| Entraînements | `workout-log`, `workout-heart-rate`, `workout-zones`, `workout-trends`, `workout-intervals`, `workout-map` |

Remarques :

- `walking-symmetry` n’est que partiellement pris en charge sur Android : Android fournit la vitesse de marche, mais pas les détails propres à Apple sur l’asymétrie ou le double appui.
- `activity-rings` n’est que partiellement pris en charge sur Android pour la station debout : l’extension utilise une approximation dérivée des pas lorsque `standHours` est absent.
- Les graphiques d’itinéraire et d’échantillons d’entraînement nécessitent des données d’entraînement détaillées ainsi que l’autorisation ou le consentement relatif aux itinéraires.

### iOS uniquement

Visualisations de l’état d’esprit et de l’humeur HealthKit :

- `mood-trend` / `state-of-mind`
- `mood-calendar-heatmap`
- `mood-sleep-scatter`
- `mood-day-timeline`
- `mood-association-breakdown`
- `mood-label-cloud`
- `mood-volatility`
- `mood-kind-split`
- `mood-circadian-clock`
- `mood-recovery-tile`
- `mood-association-matrix`

Visualisations du catalogue de médicaments et des événements de prise :

- `medication-overview` / `medications` / `medication-adherence`
- `medication-inventory`
- `medication-adherence-summary`
- `medication-dose-status` / `per-medication-dose-status`
- `medication-adherence-trend` / `medication-daily-adherence-trend`
- `medication-recent-dose-events` / `medication-dose-events`

Android Health Connect ne fournit pas d’équivalents aux enregistrements d’état d’esprit HealthKit ni aux enregistrements de type HealthKit pour le catalogue de médicaments et les événements de prise.

### Android uniquement

Aucune visualisation dans le registre actuel de l’extension Obsidian. Android exporte des données propres à la plateforme, notamment des ressources PHR/FHIR, des entraînements planifiés et l’intensité de l’activité, mais aucun type de visualisation ne prend encore en charge ces champs.

<span id="visualization-screenshot-gallery"></span>

## Catalogue des visualisations

Chaque élément renvoie à la variante publique correspondante dans la [galerie de visualisations Health.md](/visualizations/). Ces liens utilisent la variante `theme-colors` afin que la documentation reste rapide et stable, plutôt que d’intégrer chaque moteur de rendu dans cette page.

### Résumé et vue d’ensemble

- [Statistiques d’introduction](/visualizations/overview-trends/intro-stats/theme-colors/) — `intro-stats`
- [Fiche récapitulative](/visualizations/overview-trends/summary-card/theme-colors/) — `summary-card`
- [Tuile de tendance](/visualizations/overview-trends/trend-tile/theme-colors/) — `trend-tile`

### Activité

- [Anneaux d’activité](/visualizations/activity-fitness/activity-rings/theme-colors/) — `activity-rings`
- [Graphique en barres](/visualizations/activity-fitness/bar-chart/theme-colors/) — `bar-chart`
- [Carte thermique d’activité](/visualizations/activity-fitness/activity-heatmap/theme-colors/) — `activity-heatmap`
- [Spirale des pas](/visualizations/activity-fitness/step-spiral/theme-colors/) — `step-spiral`
- [Moyenne par jour de la semaine](/visualizations/activity-fitness/weekday-average/theme-colors/) — `weekday-average`

### Cœur

- [Relief cardiaque](/visualizations/heart-health/heart-terrain/theme-colors/) — `heart-terrain`
- [Plage de fréquence cardiaque](/visualizations/heart-health/heart-range/theme-colors/) — `heart-range`
- [Tendance de la VFC](/visualizations/heart-health/hrv-trend/theme-colors/) — `hrv-trend`

### Respiration, oxygène et signes vitaux

- [Rivière d’oxygène](/visualizations/respiratory-oxygen/oxygen-river/theme-colors/) — `oxygen-river`
- [Plage d’oxygène](/visualizations/respiratory-oxygen/oxygen-range/theme-colors/) — `oxygen-range`
- [Onde respiratoire](/visualizations/respiratory-oxygen/breathing-wave/theme-colors/) — `breathing-wave`
- [Anneaux des signes vitaux](/visualizations/activity-fitness/vitals-rings/theme-colors/) — `vitals-rings`

### Sommeil

- [Horaires de sommeil](/visualizations/sleep-analysis/sleep-schedule/theme-colors/) — `sleep-schedule`
- [Barres de qualité du sommeil](/visualizations/sleep-analysis/sleep-quality-bars/theme-colors/) — `sleep-quality-bars`
- [Architecture du sommeil](/visualizations/sleep-analysis/sleep-architecture/theme-colors/) — `sleep-architecture`
- [Sommeil polaire](/visualizations/sleep-analysis/sleep-polar/theme-colors/) — `sleep-polar`

### Pleine conscience et humeur

- [Tendance de l’humeur](/visualizations/mindfulness-mood/mood-trend/theme-colors/) — `mood-trend`
- [Carte thermique calendaire de l’humeur](/visualizations/mindfulness-mood/mood-calendar-heatmap/theme-colors/) — `mood-calendar-heatmap`
- [Nuage de points humeur × sommeil](/visualizations/mindfulness-mood/mood-sleep-scatter/theme-colors/) — `mood-sleep-scatter`
- [Chronologie quotidienne de l’humeur](/visualizations/mindfulness-mood/mood-day-timeline/theme-colors/) — `mood-day-timeline`
- [Humeur par association](/visualizations/mindfulness-mood/mood-association-breakdown/theme-colors/) — `mood-association-breakdown`
- [Nuage de libellés d’humeur](/visualizations/mindfulness-mood/mood-label-cloud/theme-colors/) — `mood-label-cloud`
- [Volatilité de l’humeur](/visualizations/mindfulness-mood/mood-volatility/theme-colors/) — `mood-volatility`
- [Humeur quotidienne ou ponctuelle](/visualizations/mindfulness-mood/mood-kind-split/theme-colors/) — `mood-kind-split`
- [Horloge circadienne de l’humeur](/visualizations/mindfulness-mood/mood-circadian-clock/theme-colors/) — `mood-circadian-clock`
- [Tuile récupération et état d’esprit](/visualizations/mindfulness-mood/mood-recovery-tile/theme-colors/) — `mood-recovery-tile`
- [Matrice des associations de l’humeur](/visualizations/mindfulness-mood/mood-association-matrix/theme-colors/) — `mood-association-matrix`

### Médicaments

- [Vue d’ensemble des médicaments](/visualizations/medication-adherence/medication-overview/theme-colors/) — `medication-overview`
- [Inventaire des médicaments](/visualizations/medication-adherence/medication-inventory/theme-colors/) — `medication-inventory`
- [Résumé de l’observance médicamenteuse](/visualizations/medication-adherence/medication-adherence-summary/theme-colors/) — `medication-adherence-summary`
- [État des prises de médicaments](/visualizations/medication-adherence/medication-dose-status/theme-colors/) — `medication-dose-status`
- [Tendance de l’observance médicamenteuse](/visualizations/medication-adherence/medication-adherence-trend/theme-colors/) — `medication-adherence-trend`
- [Événements de prise récents](/visualizations/medication-adherence/medication-recent-dose-events/theme-colors/) — `medication-recent-dose-events`

### Mobilité, démarche et technique de course

- [Symétrie de la marche](/visualizations/mobility-gait/walking-symmetry/theme-colors/) — `walking-symmetry`

### Entraînements

- [Journal des entraînements](/visualizations/workout-analytics/workout-log/theme-colors/) — `workout-log`
- [Fréquence cardiaque pendant l’entraînement](/visualizations/workout-analytics/workout-heart-rate/theme-colors/) — `workout-heart-rate`
- [Zones d’entraînement](/visualizations/workout-analytics/workout-zones/theme-colors/) — `workout-zones`
- [Tendances des entraînements](/visualizations/workout-analytics/workout-trends/theme-colors/) — `workout-trends`
- [Intervalles d’entraînement](/visualizations/workout-analytics/workout-intervals/theme-colors/) — `workout-intervals`
- [Carte de l’entraînement](/visualizations/workout-analytics/workout-map/theme-colors/) — `workout-map`

## Feuille de route de l’infrastructure

La principale lacune du produit n’est pas un graphique manquant en particulier. Il manque une couche générique de métriques tenant compte du schéma, qui permette de représenter n’importe quel champ Health.md exporté sans devoir écrire un analyseur et un moteur de rendu personnalisés pour chaque métrique.

### Réalisé

- Détection de la compatibilité des schémas pour les exports quotidiens, les anciens fichiers, les agrégations et les fichiers de dictionnaire de données.
- Chargement des formats JSON, CSV, Markdown et Obsidian Bases.
- Prise en compte des agrégations pour que les résumés hebdomadaires, mensuels et annuels ne faussent pas les graphiques quotidiens.
- Navigation depuis les points d’un graphique vers le fichier Health.md source correspondant.

### Prévu

- **Accesseur de métriques générique tenant compte du schéma** — lire `_healthmd_data_dictionary.json` pour obtenir les libellés, unités, catégories, règles d’agrégation et alias.
- **Tendance de métrique générique** — graphique linéaire ou en aires pour toute clé numérique exportée.
- **Barres de métrique génériques** — barres quotidiennes, hebdomadaires ou mensuelles généralisées, avec lignes d’objectif et de seuil.
- **Carte thermique calendaire générique** — toute métrique numérique quotidienne sous forme de grille calendaire.
- **Rapport de couverture des visualisations** — afficher les champs présents dans un coffre par rapport aux champs couverts par des moteurs de rendu dédiés.

---

## Résumé et vue d’ensemble

### Réalisé

- [`intro-stats`](/visualizations/overview-trends/intro-stats/theme-colors/) — résumé du jeu de données comprenant totaux, moyennes, sommeil et signes vitaux.
- [`summary-card`](/visualizations/overview-trends/summary-card/theme-colors/) — fiche d’indicateur principal dans le style Apple, avec mini-graphique et comparaison avec la période précédente.
- [`trend-tile`](/visualizations/overview-trends/trend-tile/theme-colors/) — comparaison sous forme de fiche de tendances entre les périodes actuelle et précédente.

### Prévu

- Tableau de bord généré automatiquement à partir des champs présents dans le dossier Health.md sélectionné.
- Tableau de bord de couverture du schéma par catégorie de données.
- Fiches récapitulatives de corrélation, par exemple sommeil et humeur, VFC et entraînements, symptômes et médicaments, ou alcool et sommeil.

---

## Activité

Health.md exporte les pas, l’énergie active, l’énergie basale, la durée d’exercice, la durée en station debout, les étages montés, la distance de marche ou de course, le cyclisme, la natation, l’activité en fauteuil roulant, la distance de sports de neige en descente, la durée de mouvement, l’effort physique et le VO₂ max.

### Réalisé

- [`activity-rings`](/visualizations/activity-fitness/activity-rings/theme-colors/)
- [`vitals-rings`](/visualizations/activity-fitness/vitals-rings/theme-colors/)
- [`bar-chart`](/visualizations/activity-fitness/bar-chart/theme-colors/)
- [`activity-heatmap`](/visualizations/activity-fitness/activity-heatmap/theme-colors/)
- [`step-spiral`](/visualizations/activity-fitness/step-spiral/theme-colors/)
- [`weekday-average`](/visualizations/activity-fitness/weekday-average/theme-colors/)

### Prévu

- Tableau de bord de la charge d’activité pour les pas, les calories, l’exercice, les heures en station debout et l’effort physique.
- Tendance du VO₂ max.
- Graphique de régularité du mouvement, de l’exercice et de la station debout.
- Graphique de répartition des distances entre marche ou course, cyclisme, natation, fauteuil roulant et sports de neige.
- Graphique de la distance de natation et des mouvements.
- Graphique de la distance et des poussées en fauteuil roulant.

---

## Sommeil

Health.md exporte la durée totale du sommeil, l’heure du coucher, l’heure du réveil, les durées de sommeil profond, paradoxal, lent, d’éveil et au lit, ainsi que les intervalles détaillés des phases de sommeil.

### Réalisé

- [`sleep-schedule`](/visualizations/sleep-analysis/sleep-schedule/theme-colors/)
- [`sleep-quality-bars`](/visualizations/sleep-analysis/sleep-quality-bars/theme-colors/)
- [`sleep-architecture`](/visualizations/sleep-analysis/sleep-architecture/theme-colors/)
- [`sleep-polar`](/visualizations/sleep-analysis/sleep-polar/theme-colors/)

### Prévu

- Dette de sommeil et score de régularité.
- Tendance de la proportion des phases de sommeil.
- Carte thermique de la régularité des heures de coucher et de réveil.
- Tableau de bord de récupération combinant sommeil, VFC et fréquence cardiaque au repos.

---

## Cœur

Health.md exporte la fréquence cardiaque au repos, la fréquence cardiaque pendant la marche, les fréquences cardiaques moyenne, minimale et maximale, la VFC, les échantillons de fréquence cardiaque, les échantillons de VFC, la récupération de la fréquence cardiaque et la charge de fibrillation atriale.

### Réalisé

- [`heart-terrain`](/visualizations/heart-health/heart-terrain/theme-colors/)
- [`heart-range`](/visualizations/heart-health/heart-range/theme-colors/)
- [`hrv-trend`](/visualizations/heart-health/hrv-trend/theme-colors/)

### Prévu

- Tendance de la fréquence cardiaque au repos.
- Tendance de la fréquence cardiaque pendant la marche.
- Tendance de la récupération de la fréquence cardiaque.
- Graphique de la charge de fibrillation atriale.
- Tuile de récupération combinant VFC et fréquence cardiaque au repos.
- Profil circadien de la fréquence cardiaque selon l’heure de la journée.

---

## Respiration et oxygène

Health.md exporte les valeurs moyenne, minimale et maximale de l’oxygène sanguin, les échantillons d’oxygène sanguin, les valeurs moyenne, minimale et maximale de la fréquence respiratoire, ainsi que les échantillons de fréquence respiratoire.

### Réalisé

- [`oxygen-river`](/visualizations/respiratory-oxygen/oxygen-river/theme-colors/)
- [`oxygen-range`](/visualizations/respiratory-oxygen/oxygen-range/theme-colors/)
- [`breathing-wave`](/visualizations/respiratory-oxygen/breathing-wave/theme-colors/)

### Prévu

- Graphique dédié à la plage respiratoire.
- Graphique des épisodes de désaturation en oxygène.
- Tableau de bord respiratoire nocturne combinant phases de sommeil, oxygène et fréquence respiratoire.

---

## Signes vitaux

Health.md exporte la température corporelle, la pression artérielle, la glycémie, la température corporelle basale, la température du poignet, l’activité électrodermale, la capacité vitale forcée, le VEMS, le débit expiratoire de pointe et l’utilisation d’un inhalateur.

### Réalisé

- Couverture partielle au moyen de fiches récapitulatives et de graphiques quotidiens génériques.

### Prévu

- Graphique des plages de pression artérielle systolique et diastolique avec bandes de seuil.
- Graphique de la plage glycémique.
- Tendance des températures corporelle, basale et du poignet.
- Tuile de récupération ou de maladie fondée sur la température du poignet.
- Tableau de bord de la fonction respiratoire pour la CVF, le VEMS, le débit de pointe et l’utilisation d’un inhalateur.
- Tendance de l’activité électrodermale et du stress.

---

## Mensurations corporelles

Health.md exporte le poids, la taille, l’IMC, le pourcentage de masse grasse, la masse corporelle maigre et le tour de taille.

### Réalisé

- Aucun moteur de rendu dédié à la composition corporelle pour le moment.

### Prévu

- Tableau de bord de la composition corporelle.
- Tendance du poids avec moyenne mobile et ligne d’objectif.
- Tendance de l’IMC avec bandes de catégories.
- Graphique comparant masse grasse et masse maigre.
- Tendance du tour de taille.

---

## Mobilité, démarche et technique de course

Health.md exporte la vitesse de marche, la longueur des pas, le double appui, l’asymétrie de la marche, la vitesse de montée et de descente des escaliers, le test de marche de six minutes, la stabilité de la marche, la vitesse de course, la longueur de foulée, le temps de contact au sol, l’oscillation verticale et la puissance de course.

### Réalisé

- [`walking-symmetry`](/visualizations/mobility-gait/walking-symmetry/theme-colors/)

### Prévu

- Tableau de bord de la démarche.
- Jauge de stabilité de la marche.
- Tendance du test de marche de six minutes.
- Graphique de la vitesse de montée et de descente des escaliers.
- Tableau de bord de la technique de course pour la vitesse, la foulée, le contact au sol, l’oscillation verticale et la puissance.

---

## Entraînements

Health.md exporte le nombre d’entraînements, leur durée en minutes, les calories, la distance, les types d’entraînement, les statistiques de fréquence cardiaque, les métriques de technique de course et de cyclisme, la puissance, le dénivelé, les tours, les segments, les points d’itinéraire, les zones de fréquence cardiaque et les échantillons de séries temporelles d’entraînement.

### Réalisé

- [`workout-log`](/visualizations/workout-analytics/workout-log/theme-colors/)
- [`workout-heart-rate`](/visualizations/workout-analytics/workout-heart-rate/theme-colors/)
- [`workout-zones`](/visualizations/workout-analytics/workout-zones/theme-colors/)
- [`workout-trends`](/visualizations/workout-analytics/workout-trends/theme-colors/)
- [`workout-intervals`](/visualizations/workout-analytics/workout-intervals/theme-colors/)
- [`workout-map`](/visualizations/workout-analytics/workout-map/theme-colors/)

### Prévu

- Carte thermique calendaire des entraînements.
- Graphique de la charge d’entraînement fondé sur la durée et l’intensité.
- Répartition hebdomadaire des entraînements par type.
- Tendance de l’allure et de la vitesse par type d’entraînement.
- Tendance des dénivelés positif et négatif.
- Petits multiples pour comparer les itinéraires.
- Courbe de puissance et meilleures performances.
- Tableaux de bord de la technique de course et des performances cyclistes.

---

## Pleine conscience et humeur

Health.md exporte les minutes de pleine conscience, les séances de pleine conscience, les entrées d’état d’esprit, la valence moyenne, l’humeur quotidienne, les émotions ponctuelles, les libellés et les associations.

### Réalisé

- [`mood-trend`](/visualizations/mindfulness-mood/mood-trend/theme-colors/)
- [`mood-calendar-heatmap`](/visualizations/mindfulness-mood/mood-calendar-heatmap/theme-colors/)
- [`mood-sleep-scatter`](/visualizations/mindfulness-mood/mood-sleep-scatter/theme-colors/)
- [`mood-day-timeline`](/visualizations/mindfulness-mood/mood-day-timeline/theme-colors/)
- [`mood-association-breakdown`](/visualizations/mindfulness-mood/mood-association-breakdown/theme-colors/)
- [`mood-label-cloud`](/visualizations/mindfulness-mood/mood-label-cloud/theme-colors/)
- [`mood-volatility`](/visualizations/mindfulness-mood/mood-volatility/theme-colors/)
- [`mood-kind-split`](/visualizations/mindfulness-mood/mood-kind-split/theme-colors/)
- [`mood-circadian-clock`](/visualizations/mindfulness-mood/mood-circadian-clock/theme-colors/)
- [`mood-recovery-tile`](/visualizations/mindfulness-mood/mood-recovery-tile/theme-colors/)
- [`mood-association-matrix`](/visualizations/mindfulness-mood/mood-association-matrix/theme-colors/)

### Prévu

- Tendance des minutes de pleine conscience.
- Série ou calendrier des séances de pleine conscience.
- Humeur selon l’observance médicamenteuse.
- Humeur selon la nutrition, l’alcool et la caféine.
- Chronologie des libellés d’humeur.

---

## Médicaments

Health.md exporte l’inventaire des médicaments, le nombre de médicaments actifs et archivés, le nombre d’événements de prise, le nombre de prises effectuées et ignorées, les informations sur les médicaments, les métadonnées RxNorm et de codage, les quantités des doses, le type de calendrier, les dates prévues, de début et de fin, les états et les métadonnées.

### Réalisé

- [`medication-overview`](/visualizations/medication-adherence/medication-overview/theme-colors/)
- [`medication-inventory`](/visualizations/medication-adherence/medication-inventory/theme-colors/)
- [`medication-adherence-summary`](/visualizations/medication-adherence/medication-adherence-summary/theme-colors/)
- [`medication-dose-status`](/visualizations/medication-adherence/medication-dose-status/theme-colors/)
- [`medication-adherence-trend`](/visualizations/medication-adherence/medication-adherence-trend/theme-colors/)
- [`medication-recent-dose-events`](/visualizations/medication-adherence/medication-recent-dose-events/theme-colors/)

### Prévu

- Chronologie du calendrier des médicaments.
- Carte thermique calendaire de l’observance médicamenteuse.
- Graphique du retard des prises comparant l’heure prévue à l’heure effective.
- Tendance de la quantité des doses.
- Vues de corrélation entre médicaments et symptômes ou humeur.
- Panneau détaillé RxNorm et de codage.

---

## Nutrition

Health.md exporte les calories alimentaires, les protéines, les glucides, les lipides, les graisses saturées, mono-insaturées et polyinsaturées, les fibres, le sucre, le sodium, le cholestérol, l’eau et la caféine.

### Réalisé

- Aucun moteur de rendu dédié à la nutrition pour le moment.

### Prévu

- Tableau de bord nutritionnel.
- Graphique de répartition des macronutriments.
- Graphique comparant les calories consommées aux calories actives.
- Tendance de l’hydratation.
- Graphique de la quantité quotidienne et des horaires de consommation de caféine.
- Graphiques de seuil pour le sucre et le sodium.
- Progression vers les objectifs de fibres et de protéines.

---

## Vitamines et minéraux

Health.md exporte les vitamines A, B6, B12, C, D, E et K, la thiamine, la riboflavine, la niacine, les folates, la biotine, l’acide pantothénique, le calcium, le fer, le potassium, le magnésium, le phosphore, le zinc, le sélénium, le cuivre, le manganèse, le chrome, le molybdène, le chlorure et l’iode.

### Réalisé

- Aucun moteur de rendu dédié aux micronutriments pour le moment.

### Prévu

- Carte thermique des micronutriments.
- Grille de progression vers les valeurs quotidiennes recommandées.
- Tableau de bord des tendances des vitamines.
- Tableau de bord des tendances des minéraux.
- Panneau signalant les apports insuffisants ou excessifs.
- Score d’exhaustivité des données nutritionnelles.

---

## Audition

Health.md exporte le niveau sonore des écouteurs et le niveau sonore ambiant.

### Réalisé

- Couverture partielle limitée aux résumés.

### Prévu

- Tendance de l’exposition sonore.
- Calendrier des journées bruyantes.
- Bandes de seuil d’exposition sans risque.
- Résumé hebdomadaire de l’exposition.

---

## Santé reproductive et suivi du cycle

Health.md exporte le flux menstruel, l’activité sexuelle, le résultat des tests d’ovulation, la qualité de la glaire cervicale et les saignements intermenstruels.

### Réalisé

- Aucun moteur de rendu dédié à la santé reproductive pour le moment.

### Prévu

- Calendrier du cycle.
- Carte thermique du flux menstruel.
- Chronologie des indicateurs de fertilité.
- Superposition du cycle et des symptômes combinant santé reproductive, symptômes, humeur et sommeil.
- Chronologie des saignements légers et intermenstruels.

---

## Symptômes

Health.md exporte le nombre quotidien de symptômes pour les maux de tête, la fatigue, les nausées, les vertiges, les changements d’humeur, les changements du sommeil, les changements d’appétit, les bouffées de chaleur, les frissons, la fièvre, les douleurs lombaires, les ballonnements, la constipation, la diarrhée, les brûlures d’estomac, la toux, les maux de gorge, l’écoulement nasal, l’essoufflement, les douleurs thoraciques, les battements cardiaques manqués, l’accélération du rythme cardiaque, l’acné, la peau sèche, la chute des cheveux, les trous de mémoire, les sueurs nocturnes, les vomissements, les crampes abdominales, les douleurs mammaires, les douleurs pelviennes, les courbatures, les évanouissements, la perte de l’odorat, la perte du goût, la respiration sifflante, la congestion des sinus, l’incontinence urinaire et la sécheresse vaginale.

### Réalisé

- Aucun moteur de rendu dédié aux symptômes pour le moment.

### Prévu

- Carte thermique calendaire des symptômes.
- Classement de la fréquence des symptômes.
- Matrice de cooccurrence des symptômes.
- Chronologie des poussées.
- Explorateur de corrélations des symptômes.
- Tableau de bord des symptômes regroupés par système corporel.

---

## Autres données de santé, de mode de vie et d’environnement

Health.md exporte l’exposition aux UV, le temps passé à la lumière du jour, les chutes, l’alcoolémie, les boissons alcoolisées, l’administration d’insuline, le brossage des dents, le lavage des mains, la température de l’eau et la profondeur sous l’eau.

### Réalisé

- Aucun moteur de rendu dédié au mode de vie ou à l’environnement pour le moment.

### Prévu

- Calendrier de la lumière du jour et des UV.
- Chronologie des chutes.
- Graphique comparant l’alcool au sommeil ou à la VFC.
- Tendance de l’administration d’insuline.
- Séries de brossage des dents et de lavage des mains.
- Graphique de la température de l’eau et de la profondeur sous l’eau.

---

## Ordre de priorité

1. Infrastructure de métriques générique tenant compte du schéma.
2. Moteurs de rendu génériques pour les tendances, les barres et les cartes thermiques calendaires.
3. Suite de signes vitaux : pression artérielle, glycémie, température, fonction respiratoire.
4. Tableau de bord de la composition corporelle.
5. Tableau de bord nutritionnel.
6. Carte thermique, classement et vues de corrélation des symptômes.
7. Calendrier du cycle et de la santé reproductive.
8. Carte thermique des micronutriments et grille des AJR.
9. Tableau de bord étendu de la mobilité et de la technique de course.
10. Graphiques de l’audition, du mode de vie et de l’environnement.

<p style="margin-top:48px; color:var(--sl-color-gray-3); font-size:14px;">Dernière mise à jour : 2026-06-25</p>
