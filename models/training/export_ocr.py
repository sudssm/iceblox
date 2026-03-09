#!/usr/bin/env python3
"""PP-OCRv3 model download, conversion, and export pipeline.

Downloads the fine-tuned USLicensePlateOCR PP-OCRv3 model and converts it to
ONNX, CoreML (.mlpackage), and TFLite (.tflite) for on-device inference.

Usage:
    python export_ocr.py                    # Full pipeline
    python export_ocr.py --download-only    # Just download
    python export_ocr.py --onnx-only        # Download + ONNX only
    python export_ocr.py --skip-tflite      # Skip TFLite conversion
"""

import argparse
import os
import shutil
import subprocess
import sys
import tarfile
import tempfile
import urllib.request
from pathlib import Path

# ---------------------------------------------------------------------------
# Source model URLs (tiered fallback)
# ---------------------------------------------------------------------------
# Tier 1: Fine-tuned USLicensePlateOCR model on Google Drive
GDRIVE_FILE_ID = "1-1p2dySPit9VJbJk6VH-4z6CsROiMVBr"

# Tier 2: Base PaddleOCR en_PP-OCRv3_rec
PADDLE_BASE_URL = (
    "https://paddleocr.bj.bcebos.com/PP-OCRv3/english/en_PP-OCRv3_rec_infer.tar"
)

# Tier 3: Pre-converted ONNX from HuggingFace
HF_ONNX_URL = (
    "https://huggingface.co/SWHL/RapidOCR/resolve/main/"
    "PP-OCRv3/en_PP-OCRv3_rec_infer/en_PP-OCRv3_rec_infer.onnx"
)

SCRIPT_DIR = Path(__file__).resolve().parent
EXPORT_DIR = SCRIPT_DIR.parent / "exports"
MODEL_DIR = SCRIPT_DIR / "ocr_model"

INPUT_SHAPE = [1, 3, 48, 320]


def download_finetuned(dest: Path) -> bool:
    """Tier 1: Download fine-tuned model from Google Drive via gdown."""
    try:
        import gdown
    except ImportError:
        print("  gdown not installed, skipping Google Drive download")
        return False

    print("Tier 1: Downloading fine-tuned USLicensePlateOCR model...")
    url = f"https://drive.google.com/uc?id={GDRIVE_FILE_ID}"
    output = dest / "finetuned.tar"
    try:
        gdown.download(url, str(output), quiet=False)
        if not output.exists() or output.stat().st_size < 1_000:
            print("  Download too small or failed, skipping")
            output.unlink(missing_ok=True)
            return False
        with tarfile.open(output) as tar:
            tar.extractall(path=dest)
        output.unlink()
        # Find the inference model files
        for dirpath, _dirnames, filenames in os.walk(dest):
            if "inference.pdmodel" in filenames:
                return True
        print("  No inference.pdmodel found in archive")
        return False
    except Exception as e:
        print(f"  Tier 1 failed: {e}")
        output.unlink(missing_ok=True)
        return False


def download_base_paddle(dest: Path) -> bool:
    """Tier 2: Download base en_PP-OCRv3_rec from PaddleOCR."""
    print("Tier 2: Downloading base en_PP-OCRv3_rec model...")
    output = dest / "base_model.tar"
    try:
        urllib.request.urlretrieve(PADDLE_BASE_URL, output)
        with tarfile.open(output) as tar:
            tar.extractall(path=dest)
        output.unlink()
        for dirpath, _dirnames, filenames in os.walk(dest):
            if "inference.pdmodel" in filenames:
                return True
        print("  No inference.pdmodel found")
        return False
    except Exception as e:
        print(f"  Tier 2 failed: {e}")
        output.unlink(missing_ok=True)
        return False


def download_hf_onnx(dest: Path) -> Path | None:
    """Tier 3: Download pre-converted ONNX from HuggingFace."""
    print("Tier 3: Downloading pre-converted ONNX from HuggingFace...")
    output = dest / "en_PP-OCRv3_rec_infer.onnx"
    try:
        urllib.request.urlretrieve(HF_ONNX_URL, output)
        if output.exists() and output.stat().st_size > 1_000:
            return output
        print("  Download failed or too small")
        output.unlink(missing_ok=True)
        return None
    except Exception as e:
        print(f"  Tier 3 failed: {e}")
        return None


def find_paddle_model(model_dir: Path) -> tuple[Path, Path] | None:
    """Find inference.pdmodel and inference.pdiparams in model_dir."""
    for dirpath, _dirnames, filenames in os.walk(model_dir):
        dp = Path(dirpath)
        pdmodel = dp / "inference.pdmodel"
        pdiparams = dp / "inference.pdiparams"
        if pdmodel.exists() and pdiparams.exists():
            return pdmodel, pdiparams
    return None


def convert_paddle_to_onnx(pdmodel: Path, pdiparams: Path, output: Path) -> bool:
    """Convert PaddlePaddle model to ONNX via paddle2onnx."""
    print(f"Converting PaddlePaddle → ONNX: {output}")
    cmd = [
        sys.executable, "-m", "paddle2onnx",
        "--model_dir", str(pdmodel.parent),
        "--model_filename", pdmodel.name,
        "--params_filename", pdiparams.name,
        "--save_file", str(output),
        "--opset_version", "11",
        "--enable_onnx_checker", "true",
    ]
    result = subprocess.run(cmd, capture_output=True, text=True)
    if result.returncode != 0:
        print(f"  paddle2onnx failed: {result.stderr}")
        return False
    return output.exists()


def optimize_onnx(input_path: Path, output_path: Path) -> bool:
    """Optimize ONNX model with onnxslim."""
    print(f"Optimizing ONNX: {input_path} → {output_path}")
    try:
        import onnxslim
        onnxslim.slim(str(input_path), str(output_path))
        return output_path.exists()
    except Exception as e:
        print(f"  onnxslim failed: {e}, using unoptimized model")
        shutil.copy2(input_path, output_path)
        return True


def verify_onnx(onnx_path: Path) -> bool:
    """Verify ONNX model loads and has expected shapes."""
    print(f"Verifying ONNX model: {onnx_path}")
    try:
        import onnxruntime as ort
        sess = ort.InferenceSession(str(onnx_path))
        inp = sess.get_inputs()[0]
        out = sess.get_outputs()[0]
        print(f"  Input:  name={inp.name}, shape={inp.shape}, dtype={inp.type}")
        print(f"  Output: name={out.name}, shape={out.shape}, dtype={out.type}")

        # Quick inference test with dummy data
        import numpy as np
        dummy = np.random.randn(*INPUT_SHAPE).astype(np.float32)
        result = sess.run(None, {inp.name: dummy})
        print(f"  Test inference output shape: {result[0].shape}")
        return True
    except Exception as e:
        print(f"  Verification failed: {e}")
        return False


def convert_to_coreml(onnx_path: Path, output_path: Path) -> bool:
    """Convert ONNX to CoreML .mlpackage."""
    print(f"Converting ONNX → CoreML: {output_path}")
    try:
        import coremltools as ct

        model = ct.converters.convert(
            str(onnx_path),
            minimum_deployment_target=ct.target.iOS17,
            convert_to="mlprogram",
        )
        model.save(str(output_path))
        print(f"  CoreML model saved: {output_path}")
        return output_path.exists()
    except Exception as e:
        print(f"  CoreML conversion failed: {e}")
        return False


def convert_to_tflite(onnx_path: Path, output_dir: Path) -> bool:
    """Convert ONNX to TFLite via onnx2tf."""
    print(f"Converting ONNX → TFLite: {output_dir / 'plate_ocr.tflite'}")
    try:
        cmd = [
            sys.executable, "-m", "onnx2tf",
            "-i", str(onnx_path),
            "-o", str(output_dir / "tflite_tmp"),
            "-osd",
            "--non_verbose",
        ]
        result = subprocess.run(cmd, capture_output=True, text=True)
        if result.returncode != 0:
            print(f"  onnx2tf failed: {result.stderr}")
            return False

        # Find the generated .tflite file
        tflite_dir = output_dir / "tflite_tmp"
        tflite_files = list(tflite_dir.rglob("*.tflite"))
        if not tflite_files:
            print("  No .tflite file generated")
            return False

        # Use the float32 version
        target = output_dir / "plate_ocr.tflite"
        for f in tflite_files:
            if "float32" in f.name or len(tflite_files) == 1:
                shutil.copy2(f, target)
                break
        else:
            shutil.copy2(tflite_files[0], target)

        # Cleanup temp dir
        shutil.rmtree(tflite_dir, ignore_errors=True)
        print(f"  TFLite model saved: {target}")
        return target.exists()
    except Exception as e:
        print(f"  TFLite conversion failed: {e}")
        return False


def main():
    parser = argparse.ArgumentParser(description="PP-OCRv3 export pipeline")
    parser.add_argument("--download-only", action="store_true", help="Only download model")
    parser.add_argument("--onnx-only", action="store_true", help="Stop after ONNX conversion")
    parser.add_argument("--skip-tflite", action="store_true", help="Skip TFLite conversion")
    parser.add_argument("--skip-coreml", action="store_true", help="Skip CoreML conversion")
    args = parser.parse_args()

    EXPORT_DIR.mkdir(parents=True, exist_ok=True)
    MODEL_DIR.mkdir(parents=True, exist_ok=True)

    onnx_path = EXPORT_DIR / "plate_ocr.onnx"
    onnx_optimized = EXPORT_DIR / "plate_ocr.onnx"
    coreml_path = EXPORT_DIR / "plate_ocr.mlpackage"
    tflite_path = EXPORT_DIR / "plate_ocr.tflite"

    # ── Step 1: Download ────────────────────────────────────────────────
    print("=" * 60)
    print("Step 1: Download PP-OCRv3 model")
    print("=" * 60)

    have_paddle = False
    have_onnx = False

    # Try tiered download
    if not find_paddle_model(MODEL_DIR):
        if download_finetuned(MODEL_DIR):
            have_paddle = True
            print("  ✓ Fine-tuned model downloaded")
        elif download_base_paddle(MODEL_DIR):
            have_paddle = True
            print("  ✓ Base PP-OCRv3 model downloaded (fallback)")
        else:
            result = download_hf_onnx(MODEL_DIR)
            if result:
                have_onnx = True
                # Move to export dir as raw ONNX
                raw_onnx = MODEL_DIR / "en_PP-OCRv3_rec_infer.onnx"
                shutil.copy2(raw_onnx, onnx_path)
                print("  ✓ Pre-converted ONNX downloaded (fallback)")
            else:
                print("ERROR: All download tiers failed")
                sys.exit(1)
    else:
        have_paddle = True
        print("  ✓ PaddlePaddle model already present")

    if args.download_only:
        print("\n--download-only: stopping here")
        return

    # ── Step 2: Convert to ONNX ─────────────────────────────────────────
    if have_paddle and not have_onnx:
        print("\n" + "=" * 60)
        print("Step 2: Convert PaddlePaddle → ONNX")
        print("=" * 60)

        paddle_files = find_paddle_model(MODEL_DIR)
        if not paddle_files:
            print("ERROR: PaddlePaddle model files not found")
            sys.exit(1)

        raw_onnx = EXPORT_DIR / "plate_ocr_raw.onnx"
        if not convert_paddle_to_onnx(paddle_files[0], paddle_files[1], raw_onnx):
            print("ERROR: ONNX conversion failed")
            sys.exit(1)

        if not optimize_onnx(raw_onnx, onnx_path):
            print("ERROR: ONNX optimization failed")
            sys.exit(1)

        raw_onnx.unlink(missing_ok=True)
    elif have_onnx:
        print("\n  ONNX model already available, skipping conversion")

    # ── Step 3: Verify ONNX ─────────────────────────────────────────────
    print("\n" + "=" * 60)
    print("Step 3: Verify ONNX model")
    print("=" * 60)
    if not verify_onnx(onnx_path):
        print("ERROR: ONNX verification failed")
        sys.exit(1)

    if args.onnx_only:
        print("\n--onnx-only: stopping here")
        return

    # ── Step 4: Convert to CoreML ───────────────────────────────────────
    if not args.skip_coreml:
        print("\n" + "=" * 60)
        print("Step 4: Convert ONNX → CoreML (.mlpackage)")
        print("=" * 60)
        if not convert_to_coreml(onnx_path, coreml_path):
            print("WARNING: CoreML conversion failed (macOS only)")

    # ── Step 5: Convert to TFLite ───────────────────────────────────────
    if not args.skip_tflite:
        print("\n" + "=" * 60)
        print("Step 5: Convert ONNX → TFLite (.tflite)")
        print("=" * 60)
        if not convert_to_tflite(onnx_path, EXPORT_DIR):
            print("WARNING: TFLite conversion failed")

    # ── Summary ─────────────────────────────────────────────────────────
    print("\n" + "=" * 60)
    print("Export Summary")
    print("=" * 60)
    for path, label in [
        (onnx_path, "ONNX"),
        (coreml_path, "CoreML"),
        (tflite_path, "TFLite"),
    ]:
        if path.exists():
            size_mb = path.stat().st_size / (1024 * 1024) if path.is_file() else sum(
                f.stat().st_size for f in path.rglob("*") if f.is_file()
            ) / (1024 * 1024)
            print(f"  ✓ {label}: {path} ({size_mb:.1f} MB)")
        else:
            print(f"  ✗ {label}: not generated")


if __name__ == "__main__":
    main()
