#!/usr/bin/env python3
"""
License Plate Detection Script

Detect license plates in images using the trained YOLOv8-nano model.

Usage:
    python detect.py image.jpg
    python detect.py /path/to/images/
    python detect.py image.jpg --save --conf 0.5
    python detect.py image.jpg --model /path/to/model.pt
"""

import argparse
import sys
from pathlib import Path

from ultralytics import YOLO

DEFAULT_MODEL_LOCATIONS = [
    Path(__file__).resolve().parent.parent / "exports" / "plate_detector.pt",
    Path(__file__).resolve().parent / "runs" / "plate-detector-v1" / "weights" / "best.pt",
]

IMAGE_EXTENSIONS = {".jpg", ".jpeg", ".png", ".bmp", ".tiff", ".webp"}


def find_model(model_path: Path | None) -> Path:
    """Find the trained model file."""
    if model_path:
        if model_path.exists():
            return model_path
        print(f"Error: Model not found at {model_path}")
        sys.exit(1)

    for path in DEFAULT_MODEL_LOCATIONS:
        if path.exists():
            return path

    print("Error: No trained model found.")
    print("  Train a model first: python train.py")
    print("  Or specify: python detect.py --model /path/to/model.pt image.jpg")
    sys.exit(1)


def collect_images(source: Path) -> list[Path]:
    """Collect image paths from a file or directory."""
    if source.is_file():
        return [source]
    if source.is_dir():
        images = [f for f in sorted(source.iterdir()) if f.suffix.lower() in IMAGE_EXTENSIONS]
        if not images:
            print(f"No images found in {source}")
            sys.exit(1)
        return images
    print(f"Error: {source} is not a file or directory")
    sys.exit(1)


def main():
    parser = argparse.ArgumentParser(description="Detect license plates in images")
    parser.add_argument("source", type=Path, help="Image file or directory of images")
    parser.add_argument("--model", type=Path, help="Path to model weights (.pt file)")
    parser.add_argument("--conf", type=float, default=0.7, help="Confidence threshold (default: 0.7)")
    parser.add_argument("--save", action="store_true", help="Save annotated images")
    parser.add_argument("--save-dir", type=Path, help="Directory to save results (default: ./detection_results)")
    args = parser.parse_args()

    model_path = find_model(args.model)
    print(f"Model: {model_path}")

    model = YOLO(str(model_path))
    images = collect_images(args.source)
    print(f"Processing {len(images)} image(s)...\n")

    total_detections = 0

    for img_path in images:
        results = model(str(img_path), conf=args.conf, imgsz=640, verbose=False)

        for result in results:
            boxes = result.boxes
            n = len(boxes)
            total_detections += n

            print(f"{img_path.name}: {n} plate(s) detected")

            for i, box in enumerate(boxes):
                conf = float(box.conf[0])
                x1, y1, x2, y2 = [int(v) for v in box.xyxy[0].tolist()]
                w, h = x2 - x1, y2 - y1
                print(f"  [{i+1}] conf={conf:.3f}  bbox=({x1}, {y1}, {x2}, {y2})  size={w}x{h}")

            if args.save:
                save_dir = args.save_dir or Path("detection_results")
                save_dir.mkdir(parents=True, exist_ok=True)
                annotated = result.plot()
                from PIL import Image
                Image.fromarray(annotated[..., ::-1]).save(save_dir / f"det_{img_path.name}")

    print(f"\nTotal: {total_detections} plate(s) in {len(images)} image(s)")
    return 0 if total_detections > 0 else 1


if __name__ == "__main__":
    sys.exit(main())
