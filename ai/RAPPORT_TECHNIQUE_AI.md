# ScoutAI — Rapport Technique Complet du Système IA

## 1. Vue d'ensemble

ScoutAI est un système d'**analyse vidéo footballistique basé sur l'IA** permettant d'extraire des métriques de performance physique d'un joueur sélectionné dans une vidéo de match.

Le scouter sélectionne le joueur en dessinant un rectangle (bounding box) à un instant `t0`. L'IA détecte, suit et analyse ce joueur automatiquement.

**Métriques produites :**
- Distance totale parcourue (mètres)
- Vitesse moyenne et maximale (km/h)
- Nombre de sprints
- Accélérations et décélérations
- Carte de chaleur des positions (24×16)
- Changements de direction
- Ratio de mobilité (% temps en mouvement vs arrêt)

---

## 2. Architecture & Technologies

| Composant | Technologie | Rôle |
|---|---|---|
| Serveur API | FastAPI (Python) | Endpoints REST |
| Détection | **YOLOv8s** (ultralytics) | Détecter les personnes dans les frames |
| Tracking | **DeepSORT** (deep_sort_realtime) | Suivre chaque joueur avec ID stable |
| Vision | **OpenCV** (cv2) | Lecture vidéo, histogrammes, homographie |
| Calcul | **NumPy** | Vectorisation des métriques |
| Validation | **Pydantic** | Schémas d'entrée/sortie |

**Modèles YOLO disponibles :**
- `yolov8n.pt` (6.5 MB) — Rapide, moins précis
- `yolov8s.pt` (22.6 MB) — **Défaut**, bon compromis

---

## 3. Pipeline Principal (main.py)

```
Vidéo → [échantillonnage] → [détection cut] → [détection zoom]
      → [YOLOv8 détection] → [DeepSORT tracking] → [identification cible]
      → [réidentification si perdu] → [enregistrement position]
      → [interpolation] → [métriques] → [heatmap]
```

### Paramètres fondamentaux

```
FPS vidéo : détecté automatiquement (défaut: 25 FPS)
Sampling FPS : 3.0 FPS (configurable via SCOUTAI_WINDOW_SECONDS)
Step = round(orig_fps / samplingFps)  → ~1 frame sur 8 traitée
```

**Pourquoi échantillonner ?** Traiter 25 FPS complets serait 8× plus lent sans gain significatif. À 3 FPS on capture bien les déplacements d'un joueur.

---

## 4. Détection de Personnes — YOLOv8

YOLOv8 (You Only Look Once v8) détecte des objets en temps réel. Le système filtre uniquement **la classe 0 (person) COCO**.

```python
YOLO_CONF = 0.15        # Seuil bas = max rappel, quelques faux positifs
YOLO_MODEL_NAME = "yolov8s.pt"

# Sortie par frame :
# xyxy → bounding boxes (x1,y1,x2,y2) en pixels
# conf → score de confiance 0.0→1.0
# cls  → classe (on garde cls==0 seulement)
```

Le seuil à 0.15 est **volontairement bas** pour maximiser les détections. DeepSORT filtre ensuite les détections instables.

---

## 5. Suivi Multi-Objets — DeepSORT

DeepSORT associe les détections frame-par-frame grâce à :
- **Filtre de Kalman** : prédit la position future
- **Apparence profonde** : caractéristiques visuelles
- **Algorithme hongrois** : association optimale détection↔track

```python
DeepSort(
    max_age=90,   # Track vivant 90 frames sans détection (~3s à 3 FPS)
    n_init=1      # Confirmé dès la 1ère détection
)
```

**Reset du tracker** dans 2 cas :
1. Coupure de plan détectée
2. Zoom caméra détecté

---

## 6. Identification du Joueur Cible

### Acquisition initiale (autour de t0)

**Méthode 1 — IoU** : Track avec meilleur `IoU ≥ 0.01` avec la sélection utilisateur.

**Méthode 2 — Distance** (fallback IoU faible) : Track le plus proche dans un rayon `max(w,h) × 1.5` pixels.

### Réidentification si l'ID est perdu

| Priorité | Méthode | Seuil |
|---|---|---|
| 1 | **IoU Reattach** | IoU ≥ 0.10-0.15 autour de last_xywh |
| 2 | **Histogramme couleur** | Similarité ≥ 0.10-0.15 |
| 3 | **Distance euclidienne** | Plus proche dans rayon 3× boîte |
| 4 | **Prédiction vélocité** | Si ≤ 3 frames perdues |

**Score composite de réacquisition :**
```
score = histogramme_sim × 0.6 + proximité × 0.4
```

**Lost limit = 90 frames** : après 90 frames sans retrouver le joueur, le système repart de zéro.

---

## 7. Détection des Coupures de Plan

Une coupure de plan = changement brutal de scène (replay, plan tribunes, etc.).

```python
# Histogramme HSV 30×32 bins par frame
hist = cv2.calcHist([hsv], [0, 1], None, [30, 32], [0, 180, 0, 256])

# Distance de Bhattacharyya entre frames consécutives
dist = cv2.compareHist(prev_hist, curr_hist, cv2.HISTCMP_BHATTACHARYYA)
is_cut = dist > 0.85   # Seuil empirique
```

**Distance de Bhattacharyya :** 0 = identique, 1 = totalement différent. Seuil 0.85 détecte uniquement les transitions très brutales.

**Actions sur coupure :**
- Timestamp enregistré dans `cuts[]`
- `target_track_id` réinitialisé
- `last_xywh` conservé (aide à la réacquisition)
- Tracker DeepSORT réinitialisé

---

## 8. Détection et Compensation du Zoom Caméra

Un zoom change **toutes** les bounding boxes simultanément → fausse les IDs et positions.

```python
# Comparer l'aire médiane des BB entre 2 frames
area_ratio = cur_median_area / prev_median_area

if abs(area_ratio - 1.0) > 0.35:   # >35% changement = zoom
    scale_factor = sqrt(area_ratio)
    
    # Mettre à l'échelle last_xywh
    nw = ow * scale_factor
    nh = oh * scale_factor
    ncx = ox + ow/2   # Centre conservé
    ncy = oy + oh/2
    
    # Reset tracker + cooldown 5 frames
    zoom_cooldown = 5
```

**Pendant le cooldown zoom :**
- Seuil IoU abaissé à 0.10 (plus tolérant)
- Seuil histogramme abaissé à 0.10

---

## 9. Réidentification par Histogramme de Couleur

La couleur du maillot est une **signature visuelle stable**. Conversion en espace HSV (ignore la luminosité, robuste à l'éclairage).

```python
# Histogramme HSV 16×16 bins sur la région du joueur
crop = frame[y1:y2, x1:x2]
hsv = cv2.cvtColor(crop, cv2.COLOR_BGR2HSV)
hist = cv2.calcHist([hsv], [0, 1], None, [16, 16], [0, 180, 0, 256])
# → Vecteur 256 dimensions
```

**Mise à jour progressive :**
```python
target_hist = 0.9 × target_hist + 0.1 × new_hist
```
Adaptation aux changements progressifs (salissures, transpiration).

**Banque d'histogrammes (hist_bank) :**
```python
HIST_BANK_MAX = 12          # 12 histogrammes max
HIST_BANK_MIN_DIFF = 0.15   # Diversité minimale anti-doublons
```
Couvre : joueur de face, de dos, de profil, en mouvement.

---

## 10. Prédiction par Vélocité

Si le joueur est perdu ≤ 3 frames consécutives, position **prédite** par extrapolation linéaire :

```python
vx = (cx_prev - cx_prev2) / dt     # Vitesse X en px/s
vy = (cy_prev - cy_prev2) / dt     # Vitesse Y en px/s

pred_cx = cx_prev + vx * dt_now    # Prédiction
pred_cy = cy_prev + vy * dt_now
# Confiance = 0.30 (clairement marqué "prédit")
```

**Limite :** max 3s de gap. Au-delà, on ne prédit plus.

---

## 11. Interpolation des Gaps

Après la boucle principale, interpolation **linéaire** pour combler les gaps ≤ 2 secondes :

```python
max_gap_s = 2.0
for gap entre positions consécutives:
    if 1.8/fps < gap <= 2.0:
        n_fill = round(gap / sample_interval) - 1
        for k in range(n_fill):
            frac = k / (n_fill + 1)
            interp_cx = p0_cx + (p1_cx - p0_cx) × frac
            # Confiance = 0.25 (interpolé)
```

Récupère les positions pendant des occlusions courtes (joueur caché derrière un autre).

---

## 12. Calibration Spatiale

### Mode Auto-Frame
```python
meter_per_px = 105.0 / frame_width
```
Hypothèse grossière : frame = terrain complet.

### Mode Two-Points (2 clics utilisateur)
```python
dpx = sqrt((x2-x1)² + (y2-y1)²)
meter_per_px = distance_m / dpx
```
Exemple : cliquer sur 2 poteaux de but (7.32m).

### Mode Homographie (4 points)
```python
H = cv2.getPerspectiveTransform(src_4pts_image, dst_4pts_terrain)
# Transforme pixels → coordonnées réelles (0..105m × 0..68m)
out = cv2.perspectiveTransform(positions, H)
```
Correction complète de la distorsion perspective.

### Coordonnées normalisées (zoom-invariant)
```python
ncx = cx / frame_width    # 0.0 → 1.0
ncy = cy / frame_height   # 0.0 → 1.0
```
Utilisées pour les analyses de direction afin d'éliminer l'effet du zoom.

---

## 13. Calcul des Métriques

### Pré-traitement (3 étapes)

**1. Rejet des téléportations**
```python
max_px_per_s = 800.0   # Limite physique
# Tout saut > 800 px/s supprimé (artefact tracker)
```

**2. Lissage exponentiel des positions**
```python
alpha = 0.45
sx[i] = 0.45 × xs[i] + 0.55 × sx[i-1]
```

**3. Filtrage médian + moyenne mobile des vitesses**
```python
v = _median_filter(v_raw, window=3)
v = _moving_average(v, window=5)
v = clip(v, 0, 45/3.6)   # Cap 45 km/h
```

### Métriques calculées

| Métrique | Formule |
|---|---|
| Distance | `sum(v_mps × dt)` |
| Vitesse max | `max(v_kmh)` |
| Vitesse moy | `distance_m / duration_s × 3.6` |
| Accélération | `diff(v_mps) / dt` |
| Sprints | Segments > 25 km/h durant ≥ 1s |

### Zones d'intensité (avec calibration)

| Zone | Vitesse |
|---|---|
| Marche | 0 — 7 km/h |
| Jogging | 7 — 14 km/h |
| Course | 14 — 21 km/h |
| Haute vitesse | 21 — 25 km/h |
| Sprint | > 25 km/h |

---

## 14. Heatmap — Carte de Chaleur

**Grille 24 × 16 = 384 cellules**

### Sans calibration — Rotation PCA

Les positions pixel brutes ont un axe diagonal (caméra oblique). La PCA corrige cela :

```python
# 1. Matrice de covariance des positions
cov = np.cov(centered_xs, centered_ys)
eigvals, eigvecs = np.linalg.eigh(cov)

# 2. Rotation pour aligner l'axe principal horizontalement
angle = arctan2(principal[1], principal[0])
rx = xs × cos(-angle) - ys × sin(-angle)
ry = xs × sin(-angle) + ys × cos(-angle)

# 3. Si encore trop vertical → rotation 90°
if y_range > x_range × 1.2:
    rx, ry = ry, -rx
```

### Avec calibration homographique
Coordonnées directement en mètres (0..105 × 0..68). Heatmap = représentation terrain réelle.

---

## 15. Analyse du Mouvement

### Changements de direction
```python
# Angle entre 2 segments consécutifs
dot = dx[i] × dx[i-1] + dy[i] × dy[i-1]
cross = |dx[i] × dy[i-1] - dy[i] × dx[i-1]|
angle = arctan2(cross, dot)

if angle > π/6:   # > 30° = changement de direction
    dir_changes += 1
```

**Métriques :**
- `directionChanges` : nombre total
- `dirChangesPerMin` : fréquence
- `avgTurnDegPerSec` : intensité moyenne

### Ratio de mobilité
```python
move_threshold = max_range × 0.005
moving_count = count(step_dist > move_threshold)
movingRatio = moving_count / total_segments
```
Distingue : joueur actif vs joueur qui attend.

### Work Rate
```python
workRateMetersPerMin = distance_m / duration_minutes
```
Standard football : milieu élite ≈ 120 m/min.

---

## 16. Score de Qualité des Données

```python
pts_score    = min(1.0, n_positions / 150)        # 150+ pts = max
dur_score    = min(1.0, duration_s / 30)           # 30s+ = max
continuity   = min(1.0, n_positions / (duration × 3))
cal_bonus    = 0.15 if has_calibration else 0.0

qualityScore = min(1.0,
    0.35 × pts_score +
    0.25 × dur_score +
    0.25 × continuity +
    cal_bonus
)
```

Un score > 0.7 indique des données fiables. < 0.3 = résultats à prendre avec précaution.

---

## 17. API REST — Endpoints

### POST `/process-chunk`
Analyse une vidéo référencée par chemin local ou URL.
```json
{
  "chunkPathOrUrl": "/tmp/video.mp4",
  "chunkIndex": 0,
  "samplingFps": 3.0,
  "selection": {"t0": 5.2, "x": 120, "y": 80, "w": 60, "h": 180},
  "calibration": {"type": "two_points", "x1": 100, "y1": 200, "x2": 400, "y2": 210, "distance_m": 7.32}
}
```

### POST `/process-upload`
Upload multipart d'un fichier vidéo + paramètres form-data.

### POST `/merge`
Fusionne plusieurs chunks en une seule analyse :
```json
{"chunks": [chunk1_response, chunk2_response, ...]}
```

**Réponse commune :**
```json
{
  "chunkIndex": 0,
  "frameSamplingFps": 3.0,
  "positions": [{"t": 0.0, "cx": 640, "cy": 360, "ncx": 0.5, "ncy": 0.5, "conf": 1.0}],
  "cuts": [12.4, 45.1],
  "metrics": {
    "distanceMeters": 1250.4,
    "avgSpeedKmh": 9.2,
    "maxSpeedKmh": 31.7,
    "sprintCount": 8,
    "accelPeaks": [4.2],
    "movement": {
      "directionChanges": 142,
      "dirChangesPerMin": 28.4,
      "movingRatio": 0.84,
      "qualityScore": 0.72,
      "zones": {"walking_pct": 25, "jogging_pct": 40, "running_pct": 20, "sprinting_pct": 5}
    },
    "heatmap": {"grid_w": 24, "grid_h": 16, "counts": [...], "coord_space": "image"}
  }
}
```

---

## 18. Scénarios d'Utilisation

### Scénario 1 — Analyse simple sans calibration
1. Scouter upload une vidéo de match
2. Sélectionne le joueur à `t0 = 5s`
3. API analyse → retourne positions en pixels
4. Heatmap avec rotation PCA
5. Métriques pixel : maxPxPerSec, totalPxDist, directionChanges, movingRatio
6. ❌ Pas de distance en mètres, pas de km/h

### Scénario 2 — Analyse avec calibration 2 points
1. Scouter indique 2 points connus (ex: poteaux = 7.32m)
2. `meter_per_px` calculé
3. ✅ Distance, vitesse, sprints en unités réelles
4. ✅ Zones d'intensité calculées

### Scénario 3 — Analyse avec homographie complète
1. Scouter mappe 4 coins du terrain à leurs coordonnées (0..105m, 0..68m)
2. Transformation perspective exacte
3. ✅ Toutes les métriques précises
4. ✅ Heatmap en coordonnées terrain réelles

### Scénario 4 — Coupure de plan (replay)
1. Joueur suivi sur action de 10s
2. Coupure de plan à 10s (replay en ralenti)
3. Système détecte la coupure (Bhattacharyya > 0.85)
4. Timestamp de coupure enregistré
5. Tracker réinitialisé
6. Réacquisition par histogramme quand le plan revient sur le terrain

### Scénario 5 — Zoom caméra
1. Caméra zoome sur le joueur vedette
2. Toutes les bounding boxes augmentent de taille (>35%)
3. Système détecte le zoom (median area ratio)
4. `last_xywh` mis à l'échelle par `sqrt(area_ratio)`
5. Cooldown 5 frames avec seuils abaissés
6. Réacquisition par histogramme

### Scénario 6 — Occlusion courte (≤2s)
1. Joueur caché derrière un groupe de joueurs pendant 1.5s
2. DeepSORT ne retrouve pas l'ID
3. Prédiction par vélocité (≤3 frames)
4. Interpolation linéaire (gaps ≤2s)
5. Données récupérées avec confiance 0.25

### Scénario 7 — Analyse multi-chunks (longue vidéo)
1. Vidéo de 90 minutes découpée en chunks de 5 minutes
2. Chaque chunk traité indépendamment
3. POST `/merge` fusionne tous les chunks
4. Métriques recalculées sur la timeline complète

---

## 19. Limites Connues

| Situation | Impact |
|---|---|
| Caméra très mobile (panning rapide) | Faux zooms détectés |
| Nombreux joueurs portant le même maillot | Confusion histogramme |
| Occlusion > 2 secondes | Perte de données |
| Vidéo faible résolution | Bounding boxes imprécises |
| Absence de calibration | Pas de métriques en mètres/km/h |
| Joueur hors champ prolongé | Lost limit atteint (90 frames) |
| Changements d'éclairage brutaux | Possible fausse détection de cut |

---

## 20. Variables d'Environnement

| Variable | Défaut | Description |
|---|---|---|
| `SCOUTAI_YOLO_MODEL` | `yolov8s.pt` | Modèle YOLO à utiliser |
| `SCOUTAI_YOLO_CONF` | `0.15` | Seuil de confiance détection |
| `SCOUTAI_YOLO_IMG_SIZE` | auto | Taille image pour inference |
| `SCOUTAI_AUTO_CALIBRATION` | `1` | Active calibration auto-frame |
| `SCOUTAI_WINDOW_MODE` | `0` | Analyse fenêtre temporelle seulement |
| `SCOUTAI_WINDOW_SECONDS` | `120` | Durée fenêtre si window_mode=1 |
| `SCOUTAI_ALLOWED_ORIGINS` | `*` | CORS origines autorisées |

---

## 21. Glossaire Technique

| Terme | Définition |
|---|---|
| **Bounding Box (BB)** | Rectangle délimitant un joueur dans une frame |
| **IoU** | Intersection over Union — mesure le chevauchement de deux boîtes |
| **DeepSORT** | Algorithme de suivi multi-objets avec apparence profonde |
| **YOLOv8** | Réseau de neurones pour détection d'objets temps réel |
| **Histogramme HSV** | Distribution des couleurs (Hue/Saturation) d'une région |
| **Bhattacharyya** | Mesure de dissimilarité entre distributions |
| **Homographie** | Transformation perspective entre 2 plans |
| **PCA** | Analyse en Composantes Principales — rotation des axes |
| **Filtre de Kalman** | Prédicteur de position basé sur état et bruit |
| **Sampling FPS** | Fréquence d'échantillonnage des frames analysées |
| **Track ID** | Identifiant unique attribué à chaque joueur par DeepSORT |
| **Cut** | Coupure de plan dans la vidéo |
| **Lost count** | Nombre de frames consécutives sans trouver le joueur |
| **Work Rate** | Distance parcourue par minute (indicateur d'intensité) |
| **Sprint** | Déplacement > 25 km/h pendant ≥ 1 seconde |
