# License Plate OCR Model

## Purpose

Define the OCR model, conversion pipeline, and integration approach for on-device license plate text recognition. This replaces the generic text recognition engines (Apple Vision `VNRecognizeTextRequest` on iOS, Google ML Kit Text Recognition on Android) with a specialized model fine-tuned for US license plates.

## Motivation

Generic text recognition engines achieve ~49% accuracy on license plates because they:
- Try to form dictionary words from random alphanumeric sequences (e.g., `B8M4X2` → `BAMAKO`)
- Confuse visually similar characters critical for plates: `0/O/D`, `1/I/L`, `5/S`, `8/B`, `2/Z`
- Support thousands of character classes when only 36 are needed (A-Z, 0-9)
- Are not trained on dashboard-camera degradation (motion blur, glare, angle distortion)

A fine-tuned PaddleOCR PP-OCRv3 model achieves **98.79% accuracy** on US license plates.

## Model Overview

| Property | Value |
|---|---|
| Architecture | PaddleOCR PP-OCRv3 (PP-LCNet backbone + 2-layer SVTR transformer + CTC decoder) |
| Base model | `en_PP-OCRv3_rec` (English recognition, ~9.6 MB) |
| Fine-tuned variant | USLicensePlateOCR (trained on OpenALPR US plate benchmark) |
| Input shape | `(1, 3, 48, 320)` — batch, channels (RGB), height, width |
| Input normalization | `(pixel / 255.0 - 0.5) / 0.5` → range `[-1, 1]` |
| Output shape | `(1, seq_len, 95)` — CTC logits (94 characters + blank token) |
| Character set | 94 printable ASCII characters (`en_dict.txt`) + CTC blank at index 0 |
| Export targets | Core ML (`.mlpackage`) for iOS, TFLite (`.tflite`) for Android |
| Model size | ~5–10 MB |

## Input Preprocessing

Before inference, the cropped plate region must be preprocessed:

1. **Resize** to height = 48 pixels, maintaining aspect ratio
2. **Pad** width to 320 pixels (right-pad with zeros / black pixels). If the resized width exceeds 320, scale down to fit.
3. **Normalize** pixel values: `(pixel / 255.0 - 0.5) / 0.5` to map `[0, 255]` → `[-1, 1]`
4. **Arrange** as CHW format `(3, 48, 320)` — channels first (R, G, B)

## Output Decoding

The model outputs CTC logits of shape `(1, seq_len, 95)`. Decoding uses CTC greedy decode:

1. **Argmax** at each timestep to get the most likely character index
2. **Collapse** consecutive duplicate indices (e.g., `A A A B B` → `A B`)
3. **Remove** blank tokens (index 0)
4. **Map** remaining indices to characters via the dictionary (indices 1–94)

**Confidence** is computed as the average softmax probability of the decoded (non-blank, non-duplicate) characters. The existing OCR confidence threshold (default 0.6, `AppConfig.ocrConfidenceThreshold`) is applied to this value.

## Character Dictionary

The PP-OCRv3 English dictionary (`en_dict.txt`) contains 94 printable ASCII characters. Index 0 is reserved for the CTC blank token. The dictionary is hardcoded in the platform OCR implementations (not loaded from a file) since it is small and stable:

```
Index 0:  <blank> (CTC)
Index 1:  ' ' (space)
Index 2:  !
Index 3:  "
...
Index 17: 0
Index 18: 1
...
Index 26: 9
...
Index 33: A
Index 34: B
...
Index 58: Z
...
Index 65: a
Index 66: b
...
Index 90: z
...
Index 94: ~
```

After CTC decoding, the output is passed to `PlateNormalizer` which strips non-alphanumeric characters, uppercases, and validates length — so only A-Z and 0-9 survive.

## Conversion Pipeline

### Overview

```
Fine-tuned PaddlePaddle model
    ↓ (paddle2onnx, opset 11)
ONNX model
    ↓ (onnxslim)
Optimized ONNX model
    ├──→ CoreML (.mlpackage)  via coremltools
    └──→ TFLite (.tflite)    via onnx2tf
```

### Steps

1. **Download** the fine-tuned model from the USLicensePlateOCR Google Drive link
2. **Export to inference format** (if training checkpoints): `tools/export_model.py` from PaddleOCR converts `.pdparams` to `inference.pdmodel` + `inference.pdiparams`
3. **Convert to ONNX**: `paddle2onnx --opset_version 11`
4. **Optimize**: `onnxslim` to reduce model size and improve inference speed
5. **Convert to CoreML**: `coremltools.convert()` with `minimum_deployment_target=iOS17`, fixed input shape `(1, 3, 48, 320)`
6. **Convert to TFLite**: `onnx2tf` with float32 precision

### Dependencies

```
paddle2onnx>=1.0.0
onnxslim>=0.1.0
coremltools>=7.0
onnx2tf>=1.20.0
onnx>=1.14.0
onnxruntime>=1.16.0
```

## Fallback Strategy

The fine-tuned model from Google Drive is the riskiest dependency. If unavailable:

| Tier | Source | Format | US Plate Accuracy |
|---|---|---|---|
| 1 | USLicensePlateOCR fine-tuned model (Google Drive) | PaddlePaddle | ~98.79% |
| 2 | Base `en_PP-OCRv3_rec` from PaddleOCR releases | PaddlePaddle | ~49% standalone, higher with YOLO pre-crop + normalizer |
| 3 | Pre-converted ONNX from HuggingFace (SWHL/RapidOCR) | ONNX | ~49% standalone |

If only the base model is available, the effective accuracy is higher than 49% because:
- YOLO detection pre-crops the plate region (the 49% figure is on full images)
- `PlateNormalizer` filters non-alphanumeric characters and validates length

## Validation Criteria

The model MUST meet these thresholds before being bundled into the app:

| Metric | Minimum | Target |
|---|---|---|
| Full-plate exact match (US plates) | 70% | 95% |
| Inference time (iPhone 12) | < 50ms | < 15ms |
| Inference time (Pixel 6) | < 50ms | < 15ms |
| Model size (exported) | < 10 MB | < 5 MB |

### Pre-Integration Validation

Before integrating into iOS or Android, the converted ONNX model MUST be validated in Python against real license plate images:

1. Download test plate images from public sources (e.g., stopice.net/platetracker/)
2. Run YOLO detection to crop plate regions
3. Run PP-OCRv3 ONNX inference + CTC decode on crops
4. Compare output against ground truth
5. **Go/no-go gate**: if exact match rate is below 70%, do not proceed to mobile integration

## Constraints

- C-1: Model must be < 10 MB to keep app bundle size reasonable
- C-2: Must work entirely on-device (no network connectivity required)
- C-3: Fixed input height 48px, padded width 320px
- C-4: CTC decoding must be implemented natively on each platform (no PaddlePaddle runtime dependency)
- C-5: The character dictionary is hardcoded in source code, not loaded from a bundled file

## Platform Integration

### iOS

- Load `plate_ocr.mlpackage` via `MLModel` directly (not `VNCoreMLModel`, since custom input/output handling is needed)
- Preprocessing uses `vImage` (Accelerate framework) for efficient resize
- Input packed as `MLMultiArray` of shape `[1, 3, 48, 320]`
- CTC decode implemented in Swift
- Signature unchanged: `PlateOCR.recognizeText(in: CVPixelBuffer) -> String?`

### Android

- Load `plate_ocr.tflite` via TFLite `Interpreter` (same pattern as `PlateDetector.kt`)
- Constructor accepts `Context` to load model from assets
- Input packed as `ByteBuffer` in CHW or HWC format (depending on conversion output)
- CTC decode implemented in Kotlin
- Signature unchanged: `PlateOCR.recognizeText(bitmap: Bitmap, region: RectF) -> OCRResult?`
- ML Kit Text Recognition dependency removed from build

## Project Structure

```
models/
├── Makefile                          # Existing detection targets + new OCR targets
├── training/
│   ├── train.py                      # Existing: YOLO detection training
│   ├── export_ocr.py                 # NEW: PP-OCRv3 download, convert, export
│   ├── evaluate_ocr.py              # NEW: validate OCR model on real plate images
│   └── requirements.txt              # Updated with conversion dependencies
├── exports/
│   ├── plate_detector.mlpackage      # Existing
│   ├── plate_detector.tflite         # Existing
│   ├── plate_ocr.onnx               # NEW: intermediate ONNX model
│   ├── plate_ocr.mlpackage          # NEW: CoreML export
│   └── plate_ocr.tflite             # NEW: TFLite export
```

## Implementation Order

| Step | Description |
|---|---|
| 1 | Create `models/training/export_ocr.py` — download + convert pipeline |
| 2 | Add Makefile targets (`download-ocr`, `export-ocr`, `deploy-ocr`, `evaluate-ocr`) |
| 3 | Run conversion, validate output models have correct shapes |
| 4 | Run `evaluate_ocr.py` against real plate images — **go/no-go gate** |
| 5 | Rewrite iOS `PlateOCR.swift` — CoreML model loading + preprocessing + CTC decode |
| 6 | Rewrite Android `PlateOCR.kt` — TFLite model loading + preprocessing + CTC decode |
| 7 | Update `FrameAnalyzer.kt` to pass `Context`, add `close()` call |
| 8 | Remove ML Kit dependency from Android build files |
| 9 | Test full pipeline on both platforms with real plate images |
