#!/usr/bin/env python3
"""
Model Evaluation Script

Evaluate the trained license plate detection model on the test dataset
and produce an accuracy report with metrics and visual samples.

Usage:
    python evaluate.py
    python evaluate.py --model /path/to/model.pt --test-dir /path/to/test/
    python evaluate.py --save-visuals
"""

import argparse
import json
import sys
from pathlib import Path

import yaml
from ultralytics import YOLO

DEFAULT_MODEL_LOCATIONS = [
    Path(__file__).resolve().parent.parent / "exports" / "plate_detector.pt",
    Path(__file__).resolve().parent / "runs" / "plate-detector-v1" / "weights" / "best.pt",
]


def find_model(model_path: Path | None) -> Path:
    if model_path and model_path.exists():
        return model_path
    for path in DEFAULT_MODEL_LOCATIONS:
        if path.exists():
            return path
    print("Error: No trained model found. Train first with: python train.py")
    sys.exit(1)


def find_test_data(test_dir: Path | None, dataset_dir: Path | None) -> tuple[Path | None, Path | None]:
    """Find the test images directory and data.yaml.

    Returns (test_images_dir, data_yaml_path).
    """
    if test_dir and test_dir.exists():
        # Custom test directory — look for data.yaml nearby
        parent = test_dir.parent
        if (parent / "data.yaml").exists():
            return test_dir, parent / "data.yaml"
        return test_dir, None

    # Auto-discover from training dataset
    training_dir = Path(__file__).resolve().parent
    ds_dir = dataset_dir or training_dir / "dataset"

    if not ds_dir.exists():
        print(f"Error: Dataset directory not found at {ds_dir}")
        print("  Provide --test-dir or ensure dataset is downloaded")
        sys.exit(1)

    data_yaml = None
    for candidate in ds_dir.glob("*.yaml"):
        data_yaml = candidate
        break

    test_images = ds_dir / "test" / "images"
    if not test_images.exists():
        print(f"Error: Test images not found at {test_images}")
        sys.exit(1)

    return test_images, data_yaml


def evaluate_with_val(model: YOLO, data_yaml: Path) -> dict:
    """Run YOLO val() for standard mAP/precision/recall metrics."""
    results = model.val(data=str(data_yaml), imgsz=640, split="test")
    return {
        "mAP@0.5": float(results.box.map50),
        "mAP@0.5:0.95": float(results.box.map),
        "precision": float(results.box.mp),
        "recall": float(results.box.mr),
    }


def evaluate_per_image(model: YOLO, test_images_dir: Path, conf: float = 0.7) -> list[dict]:
    """Run detection on each test image and collect per-image stats."""
    image_exts = {".jpg", ".jpeg", ".png", ".bmp", ".tiff", ".webp"}
    images = sorted(f for f in test_images_dir.iterdir() if f.suffix.lower() in image_exts)

    per_image = []
    for img_path in images:
        results = model(str(img_path), conf=conf, imgsz=640, verbose=False)
        for result in results:
            boxes = result.boxes
            detections = []
            for box in boxes:
                detections.append({
                    "confidence": float(box.conf[0]),
                    "bbox": [int(v) for v in box.xyxy[0].tolist()],
                })
            per_image.append({
                "image": img_path.name,
                "num_detections": len(detections),
                "detections": detections,
            })

    return per_image


def save_visual_results(model: YOLO, test_images_dir: Path, output_dir: Path, conf: float = 0.7):
    """Save annotated test images with detection results."""
    from PIL import Image

    output_dir.mkdir(parents=True, exist_ok=True)
    image_exts = {".jpg", ".jpeg", ".png", ".bmp", ".tiff", ".webp"}
    images = sorted(f for f in test_images_dir.iterdir() if f.suffix.lower() in image_exts)

    for img_path in images:
        results = model(str(img_path), conf=conf, imgsz=640, verbose=False)
        for result in results:
            annotated = result.plot()
            Image.fromarray(annotated[..., ::-1]).save(output_dir / f"eval_{img_path.name}")

    print(f"  Visual results saved to {output_dir}/ ({len(images)} images)")


def main():
    parser = argparse.ArgumentParser(description="Evaluate license plate detection model")
    parser.add_argument("--model", type=Path, help="Path to model weights")
    parser.add_argument("--test-dir", type=Path, help="Directory of test images")
    parser.add_argument("--dataset-dir", type=Path, help="Root dataset directory (with data.yaml)")
    parser.add_argument("--conf", type=float, default=0.7, help="Confidence threshold (default: 0.7)")
    parser.add_argument("--save-visuals", action="store_true", help="Save annotated test images")
    parser.add_argument("--output", type=Path, help="Output JSON report path")
    args = parser.parse_args()

    model_path = find_model(args.model)
    print(f"Model: {model_path}")
    model = YOLO(str(model_path))

    test_images_dir, data_yaml = find_test_data(args.test_dir, args.dataset_dir)
    print(f"Test images: {test_images_dir}")

    report = {"model": str(model_path)}

    # Standard YOLO validation metrics (requires data.yaml with test split)
    if data_yaml:
        print("\nRunning YOLO validation on test split...")
        val_metrics = evaluate_with_val(model, data_yaml)
        report["val_metrics"] = val_metrics

        gates = {"mAP@0.5": 0.80, "precision": 0.80, "recall": 0.75}
        print("\n=== Test Set Metrics ===")
        all_passed = True
        for metric, value in val_metrics.items():
            gate = gates.get(metric)
            if gate:
                passed = value >= gate
                status = "PASS" if passed else "FAIL"
                print(f"  {metric}: {value:.4f} (min: {gate}) [{status}]")
                if not passed:
                    all_passed = False
            else:
                print(f"  {metric}: {value:.4f}")
        report["quality_gates_passed"] = all_passed
    else:
        print("\nNo data.yaml found — skipping mAP validation")

    # Per-image detection analysis
    print(f"\nRunning per-image detection (conf={args.conf})...")
    per_image = evaluate_per_image(model, test_images_dir, conf=args.conf)
    report["per_image"] = per_image

    total_images = len(per_image)
    images_with_detections = sum(1 for r in per_image if r["num_detections"] > 0)
    total_detections = sum(r["num_detections"] for r in per_image)
    avg_conf = 0.0
    all_confs = [d["confidence"] for r in per_image for d in r["detections"]]
    if all_confs:
        avg_conf = sum(all_confs) / len(all_confs)

    print(f"\n=== Per-Image Summary ===")
    print(f"  Total test images: {total_images}")
    print(f"  Images with detections: {images_with_detections} ({images_with_detections/total_images*100:.1f}%)")
    print(f"  Total detections: {total_detections}")
    print(f"  Avg confidence: {avg_conf:.3f}")

    report["summary"] = {
        "total_images": total_images,
        "images_with_detections": images_with_detections,
        "total_detections": total_detections,
        "avg_confidence": avg_conf,
    }

    # Save visual results
    if args.save_visuals:
        vis_dir = Path(__file__).resolve().parent / "evaluation_results"
        save_visual_results(model, test_images_dir, vis_dir, conf=args.conf)

    # Save JSON report
    output_path = args.output or (Path(__file__).resolve().parent / "evaluation_report.json")
    with open(output_path, "w") as f:
        json.dump(report, f, indent=2)
    print(f"\nReport saved to {output_path}")


if __name__ == "__main__":
    main()
