#!/usr/bin/env python3
from __future__ import annotations

"""License plate OCR model download and export pipeline.

Downloads a pre-trained CCT (Compact Convolutional Transformer) ONNX model
from the fast-plate-ocr project for on-device license plate recognition.

Usage:
    python export_ocr.py                    # Full pipeline
    python export_ocr.py --download-only    # Just download
"""

import argparse
import sys
import urllib.request
from pathlib import Path

# ---------------------------------------------------------------------------
# Model: fast-plate-ocr CCT-XS (global, 65+ countries)
# https://github.com/ankandrew/fast-plate-ocr
# TODO: Replace with US-plate fine-tuned model when available
# ---------------------------------------------------------------------------
ONNX_URL = (
    "https://github.com/ankandrew/fast-plate-ocr/releases/download/"
    "arg-plates/cct_xs_v1_global.onnx"
)
CONFIG_URL = (
    "https://github.com/ankandrew/fast-plate-ocr/releases/download/"
    "arg-plates/cct_xs_v1_global_plate_config.yaml"
)

# Fallback: CCT-S (larger, same architecture)
FALLBACK_ONNX_URL = (
    "https://github.com/ankandrew/fast-plate-ocr/releases/download/"
    "arg-plates/cct_s_v1_global.onnx"
)

SCRIPT_DIR = Path(__file__).resolve().parent
EXPORT_DIR = SCRIPT_DIR.parent / "exports"
MODEL_DIR = SCRIPT_DIR / "ocr_model"

# Expected model properties (verified from ONNX inspection)
INPUT_SHAPE = [1, 64, 128, 3]  # BHWC, uint8
OUTPUT_SHAPE = [1, 9, 37]      # batch, slots, alphabet
ALPHABET = "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ_"


def download_model(url: str, dest: Path, label: str) -> bool:
    """Download a file from URL to dest."""
    print(f"  Downloading {label} from {url}...")
    try:
        urllib.request.urlretrieve(url, dest)
        if dest.exists() and dest.stat().st_size > 1_000:
            size_mb = dest.stat().st_size / (1024 * 1024)
            print(f"  Downloaded: {dest.name} ({size_mb:.1f} MB)")
            return True
        print(f"  Download too small or failed")
        dest.unlink(missing_ok=True)
        return False
    except Exception as e:
        print(f"  Download failed: {e}")
        dest.unlink(missing_ok=True)
        return False


def verify_onnx(onnx_path: Path) -> bool:
    """Verify ONNX model has expected input/output shapes."""
    print(f"Verifying ONNX model: {onnx_path}")
    try:
        import onnxruntime as ort
        import numpy as np

        sess = ort.InferenceSession(str(onnx_path))
        inp = sess.get_inputs()[0]
        out = sess.get_outputs()[0]
        print(f"  Input:  name={inp.name}, shape={inp.shape}, dtype={inp.type}")
        print(f"  Output: name={out.name}, shape={out.shape}, dtype={out.type}")

        # Verify input accepts uint8
        if "uint8" not in inp.type:
            print(f"  WARNING: Expected uint8 input, got {inp.type}")

        # Quick inference test
        dummy = np.random.randint(0, 255, INPUT_SHAPE, dtype=np.uint8)
        result = sess.run(None, {inp.name: dummy})
        print(f"  Test inference output shape: {result[0].shape}")

        # Verify output shape
        if list(result[0].shape) != OUTPUT_SHAPE:
            print(f"  WARNING: Expected output {OUTPUT_SHAPE}, got {list(result[0].shape)}")

        # Verify output is softmax (sums to ~1.0 per slot)
        slot_sums = result[0][0].sum(axis=1)
        if not all(abs(s - 1.0) < 0.01 for s in slot_sums):
            print(f"  WARNING: Output does not sum to 1.0 per slot: {slot_sums}")

        print("  Verification passed")
        return True
    except Exception as e:
        print(f"  Verification failed: {e}")
        return False


def main():
    parser = argparse.ArgumentParser(description="License plate OCR model export")
    parser.add_argument("--download-only", action="store_true", help="Only download model")
    args = parser.parse_args()

    EXPORT_DIR.mkdir(parents=True, exist_ok=True)
    MODEL_DIR.mkdir(parents=True, exist_ok=True)

    onnx_path = EXPORT_DIR / "plate_ocr.onnx"
    config_path = MODEL_DIR / "config.yaml"

    # ── Step 1: Download ────────────────────────────────────────────────
    print("=" * 60)
    print("Step 1: Download fast-plate-ocr CCT-XS model")
    print("=" * 60)

    downloaded = False
    if not downloaded:
        downloaded = download_model(ONNX_URL, onnx_path, "CCT-XS ONNX")

    if not downloaded:
        print("  CCT-XS failed, trying CCT-S fallback...")
        downloaded = download_model(FALLBACK_ONNX_URL, onnx_path, "CCT-S ONNX (fallback)")

    if not downloaded:
        print("ERROR: All downloads failed")
        sys.exit(1)

    # Download config YAML for reference
    download_model(CONFIG_URL, config_path, "config YAML")

    if args.download_only:
        print("\n--download-only: stopping here")
        return

    # ── Step 2: Verify ──────────────────────────────────────────────────
    print("\n" + "=" * 60)
    print("Step 2: Verify ONNX model")
    print("=" * 60)
    if not verify_onnx(onnx_path):
        print("ERROR: ONNX verification failed")
        sys.exit(1)

    # ── Summary ─────────────────────────────────────────────────────────
    print("\n" + "=" * 60)
    print("Export Summary")
    print("=" * 60)
    size_mb = onnx_path.stat().st_size / (1024 * 1024)
    print(f"  Model: {onnx_path} ({size_mb:.1f} MB)")
    print(f"  Input: uint8 {INPUT_SHAPE} (BHWC)")
    print(f"  Output: float32 {OUTPUT_SHAPE} (batch, slots, alphabet)")
    print(f"  Alphabet: {ALPHABET}")
    print(f"\n  Deploy to iOS:     cp {onnx_path} ios/IceBloxApp/Models/plate_ocr.onnx")
    print(f"  Deploy to Android: cp {onnx_path} android/app/src/main/assets/plate_ocr.onnx")


if __name__ == "__main__":
    main()
