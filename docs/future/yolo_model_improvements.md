# YOLO Model Improvements — Phase 2 & 3

> These phases are pursued if Phase 1 (Roboflow US-EU + augmentation) does not meet production quality targets, or to improve accuracy and robustness over time.

## Phase 2: Expanded Training Data

### Goal

Merge multiple open-source datasets to reach ~5,000 real images, supplemented with augmentation to reach ~15,000-20,000 effective training samples.

### Additional Data Sources

| Dataset | Size | Region | Format | License | Notes |
|---|---|---|---|---|---|
| Google Open Images v7 ("Vehicle registration plate" class) | ~1,800 images | Global (incl. US) | Open Images format → convert to YOLO | CC BY 4.0 | Largest free annotated set |
| Roboflow Universe community sets | 5,000-10,000+ images | Mixed | YOLO (native) | Varies by dataset | Cherry-pick sets with US plates and good annotation quality |
| OpenALPR US subset | 222 images | US | Custom → convert to YOLO | AGPL v3 | Small but specifically US plates |
| UCSD Car Dataset | ~878 images | US (California) | Custom → convert to YOLO | Academic | Hand-labeled with bounding boxes |

### Data Preparation

1. **Download** each dataset
2. **Convert** to YOLO format (bounding box annotations as normalized xywh in `.txt` files)
3. **Filter** for US plates where possible (discard non-US images to reduce noise)
4. **Deduplicate** across sources (hash-based image dedup to avoid train/test leakage)
5. **Merge** into a single dataset with unified class mapping (`license-plate` → class 0)
6. **Split** 80/10/10 (train/val/test), stratified by source to ensure diversity in all splits

### Conversion Notes

**Google Open Images → YOLO:**
- Download via `openimages` CLI or FiftyOne
- Filter for class `/m/01jfm_` (Vehicle registration plate)
- Convert bounding boxes from absolute (xmin, ymin, xmax, ymax) to YOLO (x_center, y_center, width, height), normalized

**OpenALPR / UCSD → YOLO:**
- Parse XML or CSV annotations
- Convert to YOLO `.txt` format

### Training

Same pipeline as Phase 1, but with the merged dataset:

```
yolo detect train \
  model=yolov8n.pt \
  data=merged_dataset.yaml \
  epochs=150 \
  imgsz=640 \
  batch=16 \
  name=plate-detector-v2
```

### Expected Improvement

| Metric | Phase 1 Target | Phase 2 Target |
|---|---|---|
| mAP@0.5 | 0.90 | 0.95 |
| Recall | 0.85 | 0.92 |
| False positive rate | < 5% | < 2% |

### Risks

- Mixed-region data may confuse the model on plate geometry (EU plates are wider/narrower than US)
- Community datasets vary in annotation quality — manual spot-checking required
- License compatibility: AGPL (OpenALPR) and academic-only (UCSD) may restrict distribution — consult legal

---

## Phase 3: Custom Data Collection

### Goal

Collect 500-1,000 images from the exact deployment scenario (dashboard-mounted camera, driving in target region) to maximize real-world accuracy.

### Collection Method

1. **Mount phone on dashboard** in the same position the app will be deployed
2. **Record video** while driving (1080p, 30fps)
3. **Drive routes** that represent the deployment environment:
   - Urban streets with parked cars (close range, 3-8m)
   - Highways with moving traffic (longer range, 10-20m)
   - Night driving with headlights
   - Rain/wet conditions (if possible)
   - Parking lots (dense plates, varying angles)
4. **Extract frames** at 1fps intervals (avoid near-duplicate frames)
5. **Annotate** using Roboflow Annotate or CVAT:
   - Draw bounding boxes around all visible plates
   - Target: 500-1,000 annotated images from 2-4 hours of driving

### Annotation Guidelines

- Annotate ALL visible plates in each frame (not just the nearest)
- Include partially occluded plates if >50% of the plate is visible
- Include angled plates up to ~45 degrees
- Do NOT annotate plates that are too small to read (< 20px width in the image)
- Label: `license-plate` (single class)

### Training

Fine-tune the Phase 2 model (not from COCO scratch):

```
yolo detect train \
  model=plate-detector-v2-best.pt \
  data=custom_dataset.yaml \
  epochs=50 \
  imgsz=640 \
  batch=16 \
  name=plate-detector-v3
```

### Expected Improvement

This phase primarily improves:
- Detection at dashboard-specific angles and distances
- Performance in the specific lighting/weather of the target region
- Reduction of false positives on signs, bumper stickers, and other text

### Effort Estimate

| Task | Time |
|---|---|
| Video collection (driving) | 2-4 hours |
| Frame extraction | 30 minutes (automated) |
| Annotation (500 images) | 4-6 hours |
| Training + validation | 2-3 hours |
| **Total** | **~1-2 days** |

---

## Decision: When to Move Between Phases

```
Phase 1 (Roboflow 350 images)
    │
    ├─ mAP@0.5 ≥ 0.85 AND recall ≥ 0.75?
    │   ├─ YES → Ship Phase 1 model, plan Phase 2 for next release
    │   └─ NO  → Proceed to Phase 2 before shipping
    │
Phase 2 (Merged ~5K images)
    │
    ├─ mAP@0.5 ≥ 0.90 AND false positive < 5%?
    │   ├─ YES → Ship Phase 2 model, Phase 3 for tuning
    │   └─ NO  → Proceed to Phase 3 (likely data distribution issue)
    │
Phase 3 (Custom collection)
    │
    └─ Model validated on real deployment footage
        └─ Ship Phase 3 model
```
