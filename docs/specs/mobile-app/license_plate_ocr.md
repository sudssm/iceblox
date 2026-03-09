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
| Output shape | `(1, 40, 97)` — CTC softmax probabilities (95 characters + blank + unknown) |
| Character set | 95 printable ASCII characters (`en_dict.txt`) + CTC blank at index 0 + unknown at index 96 |
| Export targets | ONNX (`.onnx`) for both iOS and Android via ONNX Runtime |
| Model size | ~5–10 MB |

## Input Preprocessing

Before inference, the cropped plate region must be preprocessed:

1. **Resize** to height = 48 pixels, maintaining aspect ratio
2. **Pad** width to 320 pixels (right-pad with zeros / black pixels). If the resized width exceeds 320, scale down to fit.
3. **Normalize** pixel values: `(pixel / 255.0 - 0.5) / 0.5` to map `[0, 255]` → `[-1, 1]`
4. **Arrange** as CHW format `(3, 48, 320)` — channels first (R, G, B)

## Output Decoding

The model outputs softmax probabilities of shape `(1, 40, 97)`. Decoding uses CTC greedy decode:

1. **Argmax** at each timestep to get the most likely character index
2. **Collapse** consecutive duplicate indices (e.g., `A A A B B` → `A B`)
3. **Remove** blank tokens (index 0)
4. **Map** remaining indices to characters via the dictionary (indices 1–95; index 96 is unknown/padding, ignored)

**Confidence** is computed as the average softmax probability of the decoded (non-blank, non-duplicate) characters. Since the model outputs softmax probabilities directly (not raw logits), the max value at each timestep is used directly as the character confidence. The existing OCR confidence threshold (default 0.6, `AppConfig.ocrConfidenceThreshold`) is applied to this value.

## Character Dictionary

The PP-OCRv3 English dictionary (`en_dict.txt`) contains 95 printable ASCII characters. Index 0 is reserved for the CTC blank token. Index 96 is unknown/padding (ignored). The dictionary is hardcoded in the platform OCR implementations (not loaded from a file) since it is small and stable.

**Important:** The dictionary order is NOT ASCII order. It follows PaddleOCR's `en_dict.txt` ordering:

```
Index 0:   <blank> (CTC)
Index 1:   ' ' (space)
Index 2-11:  0-9
Index 12-38: : ; < = > ? @ A-Z
Index 39-64: [ \ ] ^ _ ` a-z
Index 65-70: { | } ~
Index 71-85: ! " # $ % & ' ( ) * + , - . /
Index 96:  <unknown/padding> (ignored)
```

The full 95-character string (indices 1–95):
```
 0123456789:;<=>?@ABCDEFGHIJKLMNOPQRSTUVWXYZ[\]^_`abcdefghijklmnopqrstuvwxyz{|}~!"#$%&'()*+,-./
```

After CTC decoding, the output is passed to `PlateNormalizer` which strips non-alphanumeric characters, uppercases, and validates length — so only A-Z and 0-9 survive.

## Conversion Pipeline

### Overview

```
Fine-tuned PaddlePaddle model (Tier 1)
    ↓ (paddle2onnx, opset 11)
ONNX model ←── or download pre-converted from HuggingFace (Tier 3)
    ↓ (onnxslim, optional)
plate_ocr.onnx  →  deployed to both iOS and Android
```

CoreML and TFLite conversions were attempted but failed due to the SVTR transformer architecture's incompatibility with those runtimes. ONNX Runtime is used on both platforms instead, ensuring zero conversion drift.

### Steps

1. **Download** — tiered fallback: (1) fine-tuned from Google Drive, (2) base en_PP-OCRv3_rec from PaddleOCR, (3) pre-converted ONNX from HuggingFace
2. **Convert to ONNX** (if PaddlePaddle format): `paddle2onnx --opset_version 11`
3. **Optimize** (optional): `onnxslim` to reduce model size
4. **Verify**: run dummy inference, check input/output shapes
5. **Deploy**: copy `plate_ocr.onnx` to iOS `Models/` directory and Android `assets/` directory

### Dependencies

```
paddle2onnx>=1.0.0    # Only needed if converting from PaddlePaddle
onnxslim>=0.1.0       # Optional optimization
onnx>=1.14.0
onnxruntime>=1.16.0
```

## Fallback Strategy

The fine-tuned model from Google Drive is the riskiest dependency. If unavailable:

| Tier | Source | Format | US Plate Accuracy |
|---|---|---|---|
| 1 | USLicensePlateOCR fine-tuned model (Google Drive) | PaddlePaddle | ~98.79% |
| 2 | Base `en_PP-OCRv3_rec` from PaddleOCR releases | PaddlePaddle | ~49% standalone, higher with YOLO pre-crop + normalizer |
| 3 | Pre-converted ONNX from HuggingFace (deepghs/paddleocr) | ONNX | ~49% standalone |

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

- Load `plate_ocr.onnx` via ONNX Runtime (`ORTEnv`, `ORTSession`, `ORTValue`)
- ONNX Runtime added via Swift Package Manager (`onnxruntime-swift-package-manager`)
- Preprocessing uses Accelerate framework for efficient fill
- Input packed as `NSMutableData` of shape `[1, 3, 48, 320]`
- CTC decode implemented in Swift, using softmax probabilities directly
- Signature unchanged: `PlateOCR.recognizeText(in: CVPixelBuffer) -> String?`

### Android

- Load `plate_ocr.onnx` via ONNX Runtime (`OrtEnvironment`, `OrtSession`, `OnnxTensor`)
- Constructor accepts `Context` to load model from assets
- Input packed as `FloatArray` in CHW format via `FloatBuffer`
- CTC decode implemented in Kotlin, using softmax probabilities directly
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
│   └── plate_ocr.onnx               # NEW: ONNX model (deployed to both platforms)
```

## Implementation Order

| Step | Description |
|---|---|
| 1 | Create `models/training/export_ocr.py` — download + convert pipeline |
| 2 | Add Makefile targets (`download-ocr`, `export-ocr`, `deploy-ocr`, `evaluate-ocr`) |
| 3 | Run conversion, validate output models have correct shapes |
| 4 | Run `evaluate_ocr.py` against real plate images — **go/no-go gate** |
| 5 | Rewrite iOS `PlateOCR.swift` — ONNX Runtime model loading + preprocessing + CTC decode |
| 6 | Rewrite Android `PlateOCR.kt` — ONNX Runtime model loading + preprocessing + CTC decode |
| 7 | Update `FrameAnalyzer.kt` to pass `Context`, add `close()` call |
| 8 | Remove ML Kit dependency from Android build files |
| 9 | Test full pipeline on both platforms with real plate images |
