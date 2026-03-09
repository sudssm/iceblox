#!/usr/bin/env python3
from __future__ import annotations

"""Validate license plate OCR model on real plate images.

Downloads test plate images, runs YOLO detection to crop plate regions,
then runs the CCT-XS ONNX model with fixed-slot decode. Prints an accuracy
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

ALPHABET = "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ_"
PAD_CHAR = "_"

INPUT_HEIGHT = 64
INPUT_WIDTH = 128

GO_NOGO_THRESHOLD = 0.70


def preprocess_plate(image: np.ndarray) -> np.ndarray:
    """Preprocess a plate crop for CCT-XS inference.

    Args:
        image: BGR uint8 image (H, W, 3) from OpenCV

    Returns:
        uint8 array of shape (1, 64, 128, 3) in RGB order
    """
    import cv2

    h, w = image.shape[:2]
    if h <= 0 or w <= 0:
        return np.zeros((1, INPUT_HEIGHT, INPUT_WIDTH, 3), dtype=np.uint8)

    # Resize to exact 64x128 (no aspect ratio preservation)
    resized = cv2.resize(image, (INPUT_WIDTH, INPUT_HEIGHT), interpolation=cv2.INTER_LINEAR)

    # BGR -> RGB
    rgb = resized[:, :, ::-1].copy()

    return rgb[np.newaxis, ...].astype(np.uint8)


def fixed_slot_decode(output: np.ndarray) -> tuple[str, float]:
    """Fixed-slot argmax decode on output of shape (1, 9, 37).

    Returns:
        Tuple of (decoded_text, average_confidence)
    """
    if output.ndim == 3:
        output = output[0]  # (9, 37)

    chars = []
    confidences = []

    for slot in range(output.shape[0]):
        scores = output[slot]
        max_idx = int(scores.argmax())
        max_val = float(scores[max_idx])

        ch = ALPHABET[max_idx]
        if ch != PAD_CHAR:
            chars.append(ch)
            confidences.append(max_val)

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
                    images.append((img, img_path.stem))
    else:
        print("No test directory provided or found. Creating synthetic test images...")
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

    for img, label in images:
        crops = []

        if detector:
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
            crops = [img]

        for crop in crops:
            preprocessed = preprocess_plate(crop)
            output = sess.run(None, {input_name: preprocessed})

            raw_text, confidence = fixed_slot_decode(output[0])
            normalized = normalize_plate(raw_text)

            total += 1
            is_match = normalized != "" and normalized.lower() == normalize_plate(label).lower()
            if is_match:
                correct += 1

            status = "Y" if is_match else "N" if normalize_plate(label) else "?"
            print(f"{label:<30} {raw_text:<20} {normalized:<12} {confidence:>5.2f}  {status}")

    print("-" * 70)

    accuracy = correct / total if total > 0 else 0
    print(f"\nResults: {correct}/{total} exact matches ({accuracy:.1%})")
    print(f"Go/no-go threshold: {threshold:.0%}")

    passed = accuracy >= threshold
    if passed:
        print(f"\nPASSED — accuracy {accuracy:.1%} >= {threshold:.0%}")
    else:
        print(f"\nFAILED — accuracy {accuracy:.1%} < {threshold:.0%}")
        print("  Do NOT proceed to mobile integration.")

    return passed


def main():
    parser = argparse.ArgumentParser(description="Evaluate plate OCR model")
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
