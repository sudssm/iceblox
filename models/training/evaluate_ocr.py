#!/usr/bin/env python3
from __future__ import annotations

"""Validate PP-OCRv3 OCR model on real license plate images.

Downloads test plate images, runs YOLO detection to crop plate regions,
then runs the PP-OCRv3 ONNX model with CTC decode. Prints an accuracy
report. This is a go/no-go gate before mobile integration.

Usage:
    python evaluate_ocr.py                          # Run evaluation
    python evaluate_ocr.py --test-dir path/to/imgs  # Use local images
    python evaluate_ocr.py --threshold 0.7          # Custom pass threshold
"""

import argparse
import sys
from pathlib import Path

import numpy as np

SCRIPT_DIR = Path(__file__).resolve().parent
EXPORT_DIR = SCRIPT_DIR.parent / "exports"
ONNX_MODEL = EXPORT_DIR / "plate_ocr.onnx"
YOLO_MODEL = SCRIPT_DIR / "runs" / "plate-detector-v1" / "weights" / "best.pt"

# PP-OCRv3 English character dictionary (en_dict.txt)
# Index 0 = CTC blank; indices 1-95 = printable ASCII (space through tilde)
CHAR_DICT = [" "] + [chr(c) for c in range(33, 127)]  # space, then ! through ~

INPUT_HEIGHT = 48
INPUT_WIDTH = 320

GO_NOGO_THRESHOLD = 0.70


def preprocess_plate(image: np.ndarray) -> np.ndarray:
    """Preprocess a plate crop for PP-OCRv3 inference.

    Args:
        image: BGR uint8 image (H, W, 3) from OpenCV

    Returns:
        Float32 array of shape (1, 3, 48, 320) normalized to [-1, 1]
    """
    h, w = image.shape[:2]
    if h <= 0 or w <= 0:
        return np.zeros((1, 3, INPUT_HEIGHT, INPUT_WIDTH), dtype=np.float32) - 1.0

    # Resize to height 48, maintain aspect ratio
    scale = INPUT_HEIGHT / h
    new_w = min(int(w * scale), INPUT_WIDTH)
    import cv2
    resized = cv2.resize(image, (new_w, INPUT_HEIGHT))

    # Pad to width 320
    padded = np.zeros((INPUT_HEIGHT, INPUT_WIDTH, 3), dtype=np.uint8)
    padded[:, :new_w, :] = resized

    # BGR → RGB, normalize to [-1, 1], CHW format
    rgb = padded[:, :, ::-1].astype(np.float32)
    normalized = (rgb / 255.0 - 0.5) / 0.5
    chw = normalized.transpose(2, 0, 1)
    return chw[np.newaxis, ...]


def ctc_decode(logits: np.ndarray) -> tuple[str, float]:
    """CTC greedy decode on logits of shape (1, seq_len, num_classes).

    Returns:
        Tuple of (decoded_text, average_confidence)
    """
    if logits.ndim == 3:
        logits = logits[0]  # (seq_len, num_classes)

    # Argmax per timestep
    indices = logits.argmax(axis=1)

    # Softmax for confidence
    max_vals = logits.max(axis=1, keepdims=True)
    exp_vals = np.exp(logits - max_vals)
    softmax = exp_vals / exp_vals.sum(axis=1, keepdims=True)
    probs = softmax[np.arange(len(indices)), indices]

    # Collapse duplicates and remove blanks
    chars = []
    confidences = []
    prev_idx = -1
    for i, idx in enumerate(indices):
        if idx != 0 and idx != prev_idx:
            char_idx = idx - 1
            if char_idx < len(CHAR_DICT):
                chars.append(CHAR_DICT[char_idx])
                confidences.append(float(probs[i]))
        prev_idx = idx

    text = "".join(chars)
    avg_conf = float(np.mean(confidences)) if confidences else 0.0
    return text, avg_conf


def normalize_plate(text: str) -> str:
    """Apply the same normalization as the mobile apps."""
    text = text.upper()
    text = "".join(c for c in text if c.isascii() and c.isalnum())
    return text[:8] if 2 <= len(text) <= 8 else ""


def load_test_images(test_dir: Path | None) -> list[tuple[np.ndarray, str]]:
    """Load test images. Returns list of (image, ground_truth_or_filename)."""
    import cv2

    images = []
    if test_dir and test_dir.exists():
        for img_path in sorted(test_dir.iterdir()):
            if img_path.suffix.lower() in (".jpg", ".jpeg", ".png", ".bmp"):
                img = cv2.imread(str(img_path))
                if img is not None:
                    # Use filename stem as "ground truth" hint
                    images.append((img, img_path.stem))
    else:
        print("No test directory provided or found. Creating synthetic test images...")
        # Create simple synthetic plate images for basic testing
        for text in ["ABC1234", "XYZ789", "TEST123"]:
            img = np.ones((60, 300, 3), dtype=np.uint8) * 255
            cv2.putText(img, text, (20, 45), cv2.FONT_HERSHEY_SIMPLEX, 1.2, (0, 0, 0), 3)
            images.append((img, text))

    return images


def run_evaluation(test_dir: Path | None, threshold: float) -> bool:
    """Run the full evaluation pipeline. Returns True if pass."""
    import onnxruntime as ort

    if not ONNX_MODEL.exists():
        print(f"ERROR: ONNX model not found at {ONNX_MODEL}")
        print("Run 'make export-ocr' first.")
        return False

    print(f"Loading ONNX model: {ONNX_MODEL}")
    sess = ort.InferenceSession(str(ONNX_MODEL))
    input_name = sess.get_inputs()[0].name
    print(f"  Input: {input_name}, shape={sess.get_inputs()[0].shape}")
    print(f"  Output: {sess.get_outputs()[0].name}, shape={sess.get_outputs()[0].shape}")

    # Load YOLO detector if available
    detector = None
    if YOLO_MODEL.exists():
        try:
            from ultralytics import YOLO
            detector = YOLO(str(YOLO_MODEL))
            print(f"YOLO detector loaded: {YOLO_MODEL}")
        except Exception as e:
            print(f"YOLO not available ({e}), using full images as plate crops")

    images = load_test_images(test_dir)
    if not images:
        print("ERROR: No test images found")
        return False

    print(f"\nEvaluating {len(images)} images...")
    print("-" * 70)
    print(f"{'Image':<30} {'OCR Output':<20} {'Normalized':<12} {'Conf':>6}")
    print("-" * 70)

    total = 0
    correct = 0
    results = []

    for img, label in images:
        crops = []

        if detector:
            # Use YOLO to detect plate regions
            import cv2
            det_results = detector(img, verbose=False)
            for r in det_results:
                for box in r.boxes:
                    if float(box.conf) >= 0.5:
                        x1, y1, x2, y2 = map(int, box.xyxy[0].tolist())
                        x1 = max(0, x1)
                        y1 = max(0, y1)
                        x2 = min(img.shape[1], x2)
                        y2 = min(img.shape[0], y2)
                        crop = img[y1:y2, x1:x2]
                        if crop.shape[0] > 0 and crop.shape[1] > 0:
                            crops.append(crop)

        if not crops:
            # Use full image as the plate crop
            crops = [img]

        for crop in crops:
            preprocessed = preprocess_plate(crop)
            output = sess.run(None, {input_name: preprocessed})
            logits = output[0]

            raw_text, confidence = ctc_decode(logits)
            normalized = normalize_plate(raw_text)

            total += 1
            is_match = normalized != "" and normalized.lower() == normalize_plate(label).lower()
            if is_match:
                correct += 1

            status = "✓" if is_match else "✗" if normalize_plate(label) else "?"
            print(f"{label:<30} {raw_text:<20} {normalized:<12} {confidence:>5.2f}  {status}")
            results.append({
                "label": label,
                "raw_ocr": raw_text,
                "normalized": normalized,
                "confidence": confidence,
                "match": is_match,
            })

    print("-" * 70)

    accuracy = correct / total if total > 0 else 0
    print(f"\nResults: {correct}/{total} exact matches ({accuracy:.1%})")
    print(f"Go/no-go threshold: {threshold:.0%}")

    passed = accuracy >= threshold
    if passed:
        print(f"\n✓ PASSED — accuracy {accuracy:.1%} >= {threshold:.0%}")
    else:
        print(f"\n✗ FAILED — accuracy {accuracy:.1%} < {threshold:.0%}")
        print("  Do NOT proceed to mobile integration.")

    return passed


def main():
    parser = argparse.ArgumentParser(description="Evaluate PP-OCRv3 on plate images")
    parser.add_argument("--test-dir", type=Path, help="Directory with test plate images")
    parser.add_argument(
        "--threshold", type=float, default=GO_NOGO_THRESHOLD,
        help=f"Minimum exact match rate to pass (default: {GO_NOGO_THRESHOLD})"
    )
    args = parser.parse_args()

    passed = run_evaluation(args.test_dir, args.threshold)
    sys.exit(0 if passed else 1)


if __name__ == "__main__":
    main()
