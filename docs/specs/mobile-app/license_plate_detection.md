# License Plate Detection Model — Phase 1

## Purpose

Define the training data sources, training process, and export pipeline for the YOLOv8-nano license plate detection model used in the mobile app.

## Model Overview

| Property | Value |
|---|---|
| Architecture | YOLOv8-nano (3.2M parameters) |
| Base weights | COCO-pretrained (`yolov8n.pt`) |
| Training approach | Fine-tune from COCO (not from scratch) |
| Output class | Single class: `license-plate` |
| Export targets | Core ML (`.mlmodel`) for iOS, TFLite (`.tflite`) for Android |

## Training Data

### Primary Source: Roboflow US-EU License Plates

- **URL**: https://public.roboflow.com/object-detection/license-plates-us-eu
- **Size**: 350 images (245 train / 70 val / 35 test)
- **Classes**: `vehicle`, `license-plate` (we use only `license-plate`)
- **Format**: YOLO (ready to use, no conversion needed)
- **License**: CC BY 4.0 (annotations), CC BY 2.0 (images)
- **Origin**: Curated subset of Google Open Images

This dataset is small but sufficient to bootstrap a working prototype. The COCO-pretrained backbone already understands vehicle features, so fine-tuning needs fewer images than training from scratch.

### Data Augmentation

To expand the effective training set, apply the following augmentations during training:

| Augmentation | Rationale |
|---|---|
| Brightness/contrast jitter (±30%) | Night driving, headlight glare, shadows |
| Motion blur (horizontal, 5-15px kernel) | Camera mounted in a moving vehicle |
| Random rotation (±10°) | Angled plates, road curvature |
| Random scale (0.5x–1.5x) | Plates at varying distances (3-20m) |
| HSV shift (hue ±10, sat ±30, val ±30) | Different plate colors, lighting conditions |
| Horizontal flip (50%) | Plates visible from either side |

With augmentation, the effective training set expands to ~2,000-3,000 samples.

## Training Pipeline

### Prerequisites

```
pip install ultralytics roboflow
```

### Steps

1. **Download dataset** from Roboflow in YOLOv8 format
2. **Train** YOLOv8-nano with fine-tuning:
   ```
   yolo detect train \
     model=yolov8n.pt \
     data=dataset.yaml \
     epochs=100 \
     imgsz=640 \
     batch=16 \
     name=plate-detector-v1
   ```
3. **Validate** on held-out test set — target metrics:
   - mAP@0.5 ≥ 0.85
   - mAP@0.5:0.95 ≥ 0.60
   - Inference time < 30ms on desktop GPU (proxy for mobile performance)
4. **Export** to mobile formats:
   ```
   yolo export model=best.pt format=coreml    # iOS
   yolo export model=best.pt format=tflite    # Android
   ```

### Validation Criteria

The model MUST meet these thresholds before being bundled into the app:

| Metric | Minimum | Target |
|---|---|---|
| mAP@0.5 | 0.80 | 0.90 |
| Precision | 0.80 | 0.90 |
| Recall | 0.75 | 0.85 |
| False positive rate | < 10% | < 5% |
| Inference (iPhone 12) | < 50ms | < 30ms |
| Inference (Pixel 6) | < 50ms | < 30ms |

If Phase 1 metrics fall short, proceed to Phase 2 (additional data sources) before shipping.

## Export Details

### iOS (Core ML)

```python
from ultralytics import YOLO
model = YOLO("best.pt")
model.export(format="coreml", nms=True, imgsz=640)
```

Output: `best.mlmodel` — bundle in Xcode project under `Models/`.

### Android (TFLite)

```python
from ultralytics import YOLO
model = YOLO("best.pt")
model.export(format="tflite", imgsz=640)
```

Output: `best_float32.tflite` — bundle in Android project under `assets/`.

## Model Versioning

- Models are stored in the repo under `models/` (gitignored if >100MB, use Git LFS otherwise)
- Each model release is tagged: `plate-detector-v1.0`, `plate-detector-v1.1`, etc.
- The `models/CHANGELOG.md` file tracks: training data used, augmentation settings, validation metrics, export formats

## Constraints

- C-1: Model must be < 10 MB to keep app bundle size reasonable (YOLOv8-nano is ~6.2 MB)
- C-2: Single class detection only (`license-plate`) — vehicle detection is not needed
- C-3: Input resolution fixed at 640x640 (standard YOLO input, frames are resized before inference)
