#!/usr/bin/env python3
"""
License Plate Detection Model Training Script

Downloads a license plate dataset, fine-tunes YOLOv8-nano, validates against
quality gates, and exports to Core ML and TFLite formats.

Usage:
    python train.py                              # download HuggingFace dataset + train
    python train.py --dataset-dir /path/to/data  # use pre-downloaded YOLO-format dataset
    python train.py --epochs 50 --resume         # resume training
    python train.py --validate-only              # just validate existing model
    python train.py --skip-export                # train but skip CoreML/TFLite export
"""

import argparse
import os
import shutil
import sys
from datetime import datetime
from pathlib import Path

import yaml


def download_hf_dataset(output_dir: Path) -> Path:
    """Download the keremberke/license-plate-object-detection dataset from
    HuggingFace and convert from COCO to YOLO format.

    Dataset: 8,823 images (6,176 train / 1,765 val / 882 test), single class.
    """
    from datasets import load_dataset

    output_dir.mkdir(parents=True, exist_ok=True)

    splits = {"train": "train", "valid": "validation", "test": "test"}

    for split_name, hf_split in splits.items():
        print(f"  Downloading {hf_split} split...")
        ds = load_dataset(
            "keremberke/license-plate-object-detection",
            name="full",
            split=hf_split,
        )

        img_dir = output_dir / split_name / "images"
        lbl_dir = output_dir / split_name / "labels"
        img_dir.mkdir(parents=True, exist_ok=True)
        lbl_dir.mkdir(parents=True, exist_ok=True)

        for i, example in enumerate(ds):
            image = example["image"]
            img_w = example["width"]
            img_h = example["height"]
            objects = example["objects"]

            img_name = f"{i:06d}.jpg"
            lbl_name = f"{i:06d}.txt"

            image.save(img_dir / img_name)

            # Convert COCO bbox [x, y, w, h] to YOLO [cx, cy, w, h] (normalized)
            lines = []
            for bbox, cat in zip(objects["bbox"], objects["category"]):
                x, y, w, h = bbox
                cx = (x + w / 2) / img_w
                cy = (y + h / 2) / img_h
                nw = w / img_w
                nh = h / img_h
                # All objects are class 0 (license_plate)
                lines.append(f"0 {cx:.6f} {cy:.6f} {nw:.6f} {nh:.6f}")

            (lbl_dir / lbl_name).write_text("\n".join(lines) + "\n" if lines else "")

        print(f"    {split_name}: {len(ds)} images")

    # Write data.yaml
    data_yaml = output_dir / "data.yaml"
    config = {
        "path": str(output_dir.resolve()),
        "train": "train/images",
        "val": "valid/images",
        "test": "test/images",
        "nc": 1,
        "names": ["license-plate"],
    }
    with open(data_yaml, "w") as f:
        yaml.dump(config, f, default_flow_style=False)

    print(f"  Dataset ready at {output_dir}")
    return output_dir


def download_roboflow_dataset(api_key: str, output_dir: Path) -> Path:
    """Download the Roboflow US-EU license plates dataset (requires API key)."""
    from roboflow import Roboflow

    rf = Roboflow(api_key=api_key)
    project = rf.workspace("roboflow-ambw7").project("license-plates-us-eu")
    version = project.version(1)
    dataset = version.download("yolov8", location=str(output_dir))
    return Path(dataset.location)


def filter_single_class(dataset_dir: Path, data_yaml: Path) -> Path:
    """Filter dataset to only keep license-plate class annotations."""
    with open(data_yaml) as f:
        config = yaml.safe_load(f)

    names = config.get("names", [])
    if isinstance(names, dict):
        names_list = [names[k] for k in sorted(names.keys())]
    else:
        names_list = list(names)

    # Already single-class license-plate
    if len(names_list) == 1:
        return data_yaml

    # Find the license-plate class index
    plate_idx = None
    for i, name in enumerate(names_list):
        normalized = name.lower().replace("_", "-").replace(" ", "-")
        if normalized in ("license-plate", "license-plates", "plate"):
            plate_idx = i
            break

    if plate_idx is None:
        print(f"Warning: Could not find license-plate class in {names_list}")
        return data_yaml

    print(f"Filtering to single class: '{names_list[plate_idx]}' (index {plate_idx})")

    for split in ["train", "valid", "val", "test"]:
        labels_dir = dataset_dir / split / "labels"
        if not labels_dir.exists():
            continue
        for label_file in labels_dir.glob("*.txt"):
            lines = label_file.read_text().strip().split("\n")
            filtered = []
            for line in lines:
                if not line.strip():
                    continue
                parts = line.strip().split()
                if int(parts[0]) == plate_idx:
                    filtered.append("0 " + " ".join(parts[1:]))
            label_file.write_text("\n".join(filtered) + "\n" if filtered else "")

    config["nc"] = 1
    config["names"] = ["license-plate"]
    with open(data_yaml, "w") as f:
        yaml.dump(config, f, default_flow_style=False)

    return data_yaml


def get_device() -> str:
    """Auto-detect best available device: MPS > CUDA > CPU."""
    import torch

    if torch.backends.mps.is_available():
        return "mps"
    if torch.cuda.is_available():
        return "0"
    return "cpu"


def train_model(data_yaml: Path, runs_dir: Path, epochs: int, resume: bool):
    """Train YOLOv8-nano on the license plate dataset."""
    from ultralytics import YOLO

    device = get_device()
    print(f"Using device: {device}")

    if resume:
        last_pt = runs_dir / "plate-detector-v1" / "weights" / "last.pt"
        if last_pt.exists():
            print(f"Resuming from {last_pt}")
            model = YOLO(str(last_pt))
        else:
            print("No checkpoint found, starting fresh")
            model = YOLO("yolov8n.pt")
    else:
        model = YOLO("yolov8n.pt")

    model.train(
        data=str(data_yaml),
        epochs=epochs,
        imgsz=640,
        batch=16,
        device=device,
        name="plate-detector-v1",
        project=str(runs_dir),
        exist_ok=True,
        # Augmentation settings from spec
        hsv_h=0.015,
        hsv_s=0.3,
        hsv_v=0.3,
        degrees=10.0,
        scale=0.5,
        fliplr=0.5,
        # Training settings
        patience=20,
        save=True,
        plots=True,
    )


def validate_model(model_path: Path, data_yaml: Path) -> tuple[dict, bool]:
    """Validate model against quality gates. Returns (metrics_dict, all_passed)."""
    from ultralytics import YOLO

    model = YOLO(str(model_path))
    results = model.val(data=str(data_yaml), imgsz=640)

    metrics = {
        "mAP@0.5": float(results.box.map50),
        "mAP@0.5:0.95": float(results.box.map),
        "precision": float(results.box.mp),
        "recall": float(results.box.mr),
    }

    gates = {
        "mAP@0.5": 0.80,
        "precision": 0.80,
        "recall": 0.75,
    }

    print("\n=== Validation Results ===")
    all_passed = True
    for metric, value in metrics.items():
        gate = gates.get(metric)
        if gate:
            passed = value >= gate
            status = "PASS" if passed else "FAIL"
            print(f"  {metric}: {value:.4f} (min: {gate}) [{status}]")
            if not passed:
                all_passed = False
        else:
            print(f"  {metric}: {value:.4f}")

    return metrics, all_passed


def export_models(model_path: Path, export_dir: Path) -> dict:
    """Export model to Core ML and TFLite formats. Returns paths dict."""
    from ultralytics import YOLO

    export_dir.mkdir(parents=True, exist_ok=True)
    model = YOLO(str(model_path))
    paths = {}

    # PyTorch
    pt_dest = export_dir / "plate_detector.pt"
    shutil.copy2(model_path, pt_dest)
    paths["pytorch"] = str(pt_dest)
    print(f"  PyTorch model: {pt_dest}")

    # Core ML for iOS
    print("Exporting to Core ML...")
    try:
        coreml_path = model.export(format="coreml", nms=True, imgsz=640)
        coreml_dest = export_dir / "plate_detector.mlpackage"
        if Path(coreml_path).exists():
            if coreml_dest.exists():
                shutil.rmtree(coreml_dest)
            shutil.copytree(coreml_path, coreml_dest)
            paths["coreml"] = str(coreml_dest)
            print(f"  Core ML model: {coreml_dest}")
    except Exception as e:
        print(f"  Core ML export failed: {e}")

    # TFLite for Android
    print("Exporting to TFLite...")
    try:
        tflite_path = model.export(format="tflite", imgsz=640)
        tflite_dest = export_dir / "plate_detector.tflite"
        if Path(tflite_path).exists():
            shutil.copy2(tflite_path, tflite_dest)
            paths["tflite"] = str(tflite_dest)
            print(f"  TFLite model: {tflite_dest}")
    except Exception as e:
        print(f"  TFLite export failed: {e}")

    return paths


def write_changelog(
    changelog_path: Path, metrics: dict, export_paths: dict, epochs: int, num_images: int
):
    """Write model version info to CHANGELOG.md."""
    size_mb = "N/A"
    pt_path = export_paths.get("pytorch")
    if pt_path and Path(pt_path).exists():
        size_mb = f"{Path(pt_path).stat().st_size / 1024 / 1024:.1f}"

    content = f"""# Model Changelog

## v1.0 — {datetime.now().strftime('%Y-%m-%d')}

**Architecture:** YOLOv8-nano (3.2M params)
**Base weights:** COCO-pretrained (yolov8n.pt)
**Training data:** License Plate Object Detection ({num_images} images, CC BY 4.0)
**Epochs:** {epochs}
**Input size:** 640x640

### Validation Metrics

| Metric | Value |
|---|---|
| mAP@0.5 | {metrics.get('mAP@0.5', 0):.4f} |
| mAP@0.5:0.95 | {metrics.get('mAP@0.5:0.95', 0):.4f} |
| Precision | {metrics.get('precision', 0):.4f} |
| Recall | {metrics.get('recall', 0):.4f} |
| Model size | {size_mb} MB |

### Exports

| Format | Path |
|---|---|
"""
    for fmt, path in export_paths.items():
        content += f"| {fmt} | `{path}` |\n"

    content += """
### Augmentation

| Setting | Value |
|---|---|
| HSV hue | +/-0.015 |
| HSV saturation | +/-0.3 |
| HSV value | +/-0.3 |
| Rotation | +/-10 deg |
| Scale | 0.5x |
| Horizontal flip | 50% |
"""

    changelog_path.write_text(content)
    print(f"\nChangelog written to {changelog_path}")


def main():
    parser = argparse.ArgumentParser(description="Train license plate detection model")
    parser.add_argument("--dataset-dir", type=Path, help="Path to pre-downloaded YOLO-format dataset")
    parser.add_argument("--epochs", type=int, default=100, help="Training epochs (default: 100)")
    parser.add_argument("--resume", action="store_true", help="Resume from last checkpoint")
    parser.add_argument("--skip-export", action="store_true", help="Skip model export step")
    parser.add_argument("--validate-only", action="store_true", help="Only run validation")
    parser.add_argument(
        "--source",
        choices=["huggingface", "roboflow"],
        default="huggingface",
        help="Dataset source (default: huggingface, no API key needed)",
    )
    parser.add_argument("--api-key", type=str, help="Roboflow API key (only for --source roboflow)")
    args = parser.parse_args()

    project_root = Path(__file__).resolve().parent.parent.parent
    models_dir = project_root / "models"
    training_dir = models_dir / "training"
    runs_dir = training_dir / "runs"
    export_dir = models_dir / "exports"

    # Step 1: Get dataset
    num_images = 0
    if args.dataset_dir:
        dataset_dir = args.dataset_dir.resolve()
    else:
        dataset_dir = training_dir / "dataset"
        if not dataset_dir.exists() or not any(dataset_dir.iterdir()):
            if args.source == "roboflow":
                api_key = args.api_key or os.environ.get("ROBOFLOW_API_KEY")
                if not api_key:
                    print("Error: Roboflow API key required.")
                    print("  Get a free key at https://roboflow.com/")
                    print("  Then: export ROBOFLOW_API_KEY=your_key")
                    sys.exit(1)
                print("Downloading dataset from Roboflow...")
                dataset_dir = download_roboflow_dataset(api_key, dataset_dir)
            else:
                print("Downloading dataset from HuggingFace...")
                dataset_dir = download_hf_dataset(dataset_dir)
        else:
            print(f"Using existing dataset at {dataset_dir}")

    # Find data.yaml
    data_yaml = dataset_dir / "data.yaml"
    if not data_yaml.exists():
        candidates = list(dataset_dir.glob("*.yaml"))
        if candidates:
            data_yaml = candidates[0]
        else:
            print(f"Error: No data.yaml found in {dataset_dir}")
            sys.exit(1)

    data_yaml = filter_single_class(dataset_dir, data_yaml)

    # Count images
    train_imgs = dataset_dir / "train" / "images"
    if train_imgs.exists():
        num_images = sum(1 for _ in train_imgs.iterdir())

    # Step 2: Train
    best_model = runs_dir / "plate-detector-v1" / "weights" / "best.pt"

    if not args.validate_only:
        print(f"\nTraining YOLOv8-nano for {args.epochs} epochs on {num_images} training images...")
        train_model(data_yaml, runs_dir, epochs=args.epochs, resume=args.resume)

    if not best_model.exists():
        print(f"Error: Best model not found at {best_model}")
        sys.exit(1)

    # Step 3: Validate
    print("\nValidating model...")
    metrics, passed = validate_model(best_model, data_yaml)

    if not passed:
        print("\nWARNING: Model did not meet all quality gates.")
        print("Consider more epochs or additional training data.")
    else:
        print("\nAll quality gates passed!")

    # Step 4: Export
    export_paths = {}
    if not args.skip_export and not args.validate_only:
        print("\nExporting models...")
        export_paths = export_models(best_model, export_dir)

    # Step 5: Write changelog
    changelog_path = models_dir / "CHANGELOG.md"
    if export_paths:
        write_changelog(changelog_path, metrics, export_paths, args.epochs, num_images)

    print("\nDone!")
    if export_paths:
        print(f"Model artifacts in {export_dir}/")
    print(f"Best weights at {best_model}")


if __name__ == "__main__":
    main()
