# License Plate OCR Model

## Purpose

Define the OCR model, conversion pipeline, and integration approach for on-device license plate text recognition. This replaces the generic text recognition engines (Apple Vision `VNRecognizeTextRequest` on iOS, Google ML Kit Text Recognition on Android) with a specialized model trained on license plate images.

## Motivation

Generic text recognition engines achieve ~49% accuracy on license plates because they:
- Try to form dictionary words from random alphanumeric sequences (e.g., `B8M4X2` → `BAMAKO`)
- Confuse visually similar characters critical for plates: `0/O/D`, `1/I/L`, `5/S`, `8/B`, `2/Z`
- Support thousands of character classes when only 36 are needed (A-Z, 0-9)
- Are not trained on dashboard-camera degradation (motion blur, glare, angle distortion)

## Model Overview

| Property | Value |
|---|---|
| Architecture | CCT-XS (Compact Convolutional Transformer, Extra Small) |
| Source | [fast-plate-ocr](https://github.com/ankandrew/fast-plate-ocr) `cct_xs_v1_global` |
| Training data | 220k+ license plate images from 65+ countries |
| Input shape | `(1, 64, 128, 3)` — batch, height, width, channels (BHWC, uint8) |
| Input normalization | **None** — normalization baked into model, raw uint8 RGB pixels |
| Output shape | `(1, 9, 37)` — batch, slots, alphabet (softmax probabilities) |
| Decoding | Fixed-slot argmax (9 character slots, strip `_` padding) |
| Character set | `0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ_` (37 chars, `_` = padding) |
| Export format | ONNX (`.onnx`) for both iOS and Android via ONNX Runtime |
| Model size | **2.0 MB** |
| Accuracy | ~92-94% on license plates |

## Input Preprocessing

Before inference, the cropped plate region must be preprocessed:

1. **Resize** to exactly 64×128 pixels (height × width), no aspect ratio preservation
2. **Convert** pixel format to RGB uint8 (BGRA→RGB on iOS, ARGB→RGB on Android)
3. **Pack** as HWC byte array of shape `(64, 128, 3)`

No float normalization is required — the model accepts raw uint8 pixel values and has normalization baked into its first layers.

## Output Decoding

The model outputs softmax probabilities of shape `(1, 9, 37)`. Decoding uses fixed-slot argmax:

1. **Argmax** at each of the 9 character slots to get the most likely character index
2. **Map** each index to the corresponding character in the alphabet
3. **Strip** padding characters (`_` at index 36)

There is no CTC collapse step — each slot independently predicts one character.

**Confidence** is computed as the average softmax probability of the decoded non-padding characters. The existing OCR confidence threshold (default 0.6, `AppConfig.ocrConfidenceThreshold`) is applied to this value.

**Per-character confidences** — the max softmax probability at each decoded slot — MUST be preserved and returned alongside the decoded text.

**Per-slot candidate lists** — at each decoded (non-padding) slot, all characters with softmax probability >= `ocrCandidateThreshold` (default: 0.05) MUST be collected, sorted by probability descending, and returned as `slotCandidates`. These candidate lists are used by LookalikeExpander (REQ-M-12a) to generate model-derived plate variants instead of relying on hardcoded confusable character groups. The OCR output type carries the decoded text, per-character confidence array, and per-slot candidate lists (iOS: `OCROutput`, Android: `OCRResult`).

## Character Alphabet

The alphabet is 37 characters in ASCII order:

```
Index 0-9:   0-9
Index 10-35: A-Z
Index 36:    _ (padding)
```

Full string: `0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ_`

After decoding, the output is passed to `PlateNormalizer` which strips non-alphanumeric characters, uppercases, and validates length — so only A-Z and 0-9 survive.

## Export Pipeline

### Overview

```
Pre-trained CCT-XS ONNX model (GitHub releases)
    ↓ (download + verify)
plate_ocr.onnx  →  deployed to both iOS and Android
```

### Steps

1. **Download** — primary: `cct_xs_v1_global.onnx` from GitHub releases; fallback: `cct_s_v1_global.onnx` (larger CCT-S variant)
2. **Verify** — run dummy inference, check uint8 input, softmax output (sums to ~1.0 per slot), shape `[1, 9, 37]`
3. **Deploy** — copy `plate_ocr.onnx` to iOS `Models/` directory and Android `assets/` directory

### Dependencies

```
onnx>=1.14.0
onnxruntime>=1.16.0
pyyaml>=6.0
Pillow>=10.0.0
numpy>=1.24.0
```

## Validation Criteria

The model MUST meet these thresholds before being bundled into the app:

| Metric | Minimum | Target |
|---|---|---|
| Full-plate exact match | 70% | 95% |
| Inference time (iPhone 12) | < 50ms | < 15ms |
| Inference time (Pixel 6) | < 50ms | < 15ms |
| Model size (exported) | < 10 MB | < 5 MB |

### Pre-Integration Validation

Before integrating into iOS or Android, the ONNX model MUST be validated in Python against real license plate images:

1. Download test plate images from public sources
2. Run YOLO detection to crop plate regions (if detector available)
3. Run CCT-XS ONNX inference + fixed-slot decode on crops
4. Compare output against ground truth
5. **Go/no-go gate**: if exact match rate is below 70%, do not proceed to mobile integration

## Constraints

- C-1: Model must be < 10 MB to keep app bundle size reasonable
- C-2: Must work entirely on-device (no network connectivity required)
- C-3: Fixed input size 64×128 pixels, uint8 RGB
- C-4: Fixed-slot decoding must be implemented natively on each platform (no Python runtime dependency)
- C-5: The character alphabet is hardcoded in source code, not loaded from a bundled file

## Platform Integration

### iOS

- Load `plate_ocr.onnx` via ONNX Runtime (`ORTEnv`, `ORTSession`, `ORTValue`)
- ONNX Runtime added via Swift Package Manager (`onnxruntime-swift-package-manager`)
- Preprocessing: nearest-neighbor resize from CVPixelBuffer, BGRA→RGB byte conversion
- Input packed as `NSMutableData` of uint8 bytes, shape `[1, 64, 128, 3]`
- Fixed-slot decode implemented in Swift
- Signature: `PlateOCR.recognizeText(in: CVPixelBuffer) -> OCROutput?` where `OCROutput` contains the decoded text and per-character confidence array

### Android

- Load `plate_ocr.onnx` via ONNX Runtime (`OrtEnvironment`, `OrtSession`, `OnnxTensor`)
- Constructor accepts `Context` to load model from assets
- Input packed as `ByteArray` (uint8 RGB HWC) via `ByteBuffer` with `OnnxJavaType.UINT8`
- Fixed-slot decode implemented in Kotlin
- Signature unchanged: `PlateOCR.recognizeText(bitmap: Bitmap, region: RectF) -> OCRResult?`
- ML Kit Text Recognition dependency removed from build

## Project Structure

```
models/
├── Makefile                          # Existing detection targets + OCR targets
├── training/
│   ├── train.py                      # Existing: YOLO detection training
│   ├── export_ocr.py                 # Download + verify CCT-XS ONNX model
│   ├── evaluate_ocr.py              # Validate OCR model on real plate images
│   └── requirements.txt              # Dependencies
├── exports/
│   ├── plate_detector.mlpackage      # Existing
│   ├── plate_detector.tflite         # Existing
│   └── plate_ocr.onnx               # CCT-XS ONNX model (deployed to both platforms)
```

## Implementation Order

| Step | Description |
|---|---|
| 1 | Create `models/training/export_ocr.py` — download + verify pipeline |
| 2 | Add Makefile targets (`download-ocr`, `export-ocr`, `deploy-ocr`, `evaluate-ocr`) |
| 3 | Run download, validate output model has correct shapes |
| 4 | Run `evaluate_ocr.py` against real plate images — **go/no-go gate** |
| 5 | Rewrite iOS `PlateOCR.swift` — ONNX Runtime model loading + preprocessing + fixed-slot decode |
| 6 | Rewrite Android `PlateOCR.kt` — ONNX Runtime model loading + preprocessing + fixed-slot decode |
| 7 | Test full pipeline on both platforms with real plate images |
