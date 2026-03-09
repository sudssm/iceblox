# License Plate Detection Model — Build & Export
#
# Workflow:
#   make setup          Install Python venv and dependencies
#   make download       Download training dataset from HuggingFace
#   make train          Fine-tune YOLOv8-nano on license plate data
#   make validate       Validate model against quality gates
#   make export         Export to Core ML (.mlpackage) and TFLite (.tflite)
#   make deploy         Copy exported models to iOS and Android app directories
#   make all            Run full pipeline: download → train → export → deploy
#   make export-ocr     Download + convert PP-OCRv3 OCR model (ONNX/CoreML/TFLite)
#   make evaluate-ocr   Validate OCR model on real plate images (go/no-go gate)
#   make deploy-ocr     Copy OCR models to iOS and Android app directories
#   make clean          Remove training artifacts (keeps exported models)
#
# The trained model detects a single class ("license-plate") using YOLOv8-nano
# (~6 MB). Training data comes from the keremberke/license-plate-object-detection
# dataset on HuggingFace (8,823 images, CC BY 4.0).

SHELL := /bin/bash

# Paths (relative to this Makefile, which lives in models/)
TRAINING_DIR   := training
VENV           := $(TRAINING_DIR)/.venv
PYTHON         := $(VENV)/bin/python3
PIP            := $(VENV)/bin/pip
DATASET_DIR    := $(TRAINING_DIR)/dataset
RUNS_DIR       := $(TRAINING_DIR)/runs
BEST_MODEL     := $(RUNS_DIR)/plate-detector-v1/weights/best.pt
EXPORT_DIR     := exports

# App model destinations
IOS_MODEL_DIR  := ../ios/IceBloxApp/Models
ANDROID_ASSETS := ../android/app/src/main/assets

.PHONY: all setup download train validate export deploy clean help \
       download-ocr export-ocr deploy-ocr evaluate-ocr

help: ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | \
		awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-14s\033[0m %s\n", $$1, $$2}'

all: setup download train export deploy ## Full pipeline: setup → train → export → deploy

# ── Setup ────────────────────────────────────────────────────────────────────

setup: $(VENV)/bin/activate ## Create venv and install dependencies
$(VENV)/bin/activate: $(TRAINING_DIR)/requirements.txt
	python3 -m venv $(VENV)
	$(PIP) install --upgrade pip
	$(PIP) install -r $(TRAINING_DIR)/requirements.txt
	touch $(VENV)/bin/activate

# ── Dataset ──────────────────────────────────────────────────────────────────

download: setup $(DATASET_DIR)/data.yaml ## Download dataset from HuggingFace
$(DATASET_DIR)/data.yaml:
	@echo "Downloading license plate dataset from HuggingFace..."
	$(PYTHON) $(TRAINING_DIR)/train.py --epochs 0 --skip-export --validate-only 2>/dev/null || \
		$(PYTHON) -c " \
			import sys; sys.path.insert(0, '$(TRAINING_DIR)'); \
			from train import download_hf_dataset; \
			from pathlib import Path; \
			download_hf_dataset(Path('$(DATASET_DIR)')) \
		"
	@echo "Dataset ready at $(DATASET_DIR)/"

# ── Training ─────────────────────────────────────────────────────────────────

train: setup ## Train YOLOv8-nano (fine-tune from COCO weights, ~100 epochs)
	$(PYTHON) $(TRAINING_DIR)/train.py --skip-export
	@echo ""
	@echo "Training complete. Best model: $(BEST_MODEL)"

train-resume: setup ## Resume training from last checkpoint
	$(PYTHON) $(TRAINING_DIR)/train.py --skip-export --resume

# ── Validation ───────────────────────────────────────────────────────────────

validate: setup ## Validate model against quality gates (mAP≥0.80, P≥0.80, R≥0.75)
	@test -f $(BEST_MODEL) || (echo "Error: No trained model at $(BEST_MODEL)" && echo "Run 'make train' first." && exit 1)
	$(PYTHON) $(TRAINING_DIR)/train.py --validate-only

evaluate: setup ## Run full evaluation with per-image stats and save visuals
	$(PYTHON) $(TRAINING_DIR)/evaluate.py --save-visuals

# ── Export ───────────────────────────────────────────────────────────────────

export: setup $(EXPORT_DIR)/plate_detector.mlpackage $(EXPORT_DIR)/plate_detector.tflite ## Export to Core ML and TFLite

$(EXPORT_DIR)/plate_detector.mlpackage $(EXPORT_DIR)/plate_detector.tflite: $(BEST_MODEL)
	@echo "Exporting model to Core ML and TFLite..."
	$(PYTHON) -c " \
		import sys; sys.path.insert(0, '$(TRAINING_DIR)'); \
		from train import export_models; \
		from pathlib import Path; \
		paths = export_models(Path('$(BEST_MODEL)'), Path('$(EXPORT_DIR)')); \
		print(); \
		for fmt, p in paths.items(): print(f'  {fmt}: {p}') \
	"
	@echo ""
	@echo "Exports in $(EXPORT_DIR)/"

# ── Deploy ───────────────────────────────────────────────────────────────────

deploy: ## Copy exported models to iOS and Android app directories
	@test -d $(EXPORT_DIR)/plate_detector.mlpackage || (echo "Error: No Core ML model. Run 'make export' first." && exit 1)
	@test -f $(EXPORT_DIR)/plate_detector.tflite || (echo "Error: No TFLite model. Run 'make export' first." && exit 1)
	@mkdir -p $(IOS_MODEL_DIR) $(ANDROID_ASSETS)
	@echo "Deploying models to app directories..."
	cp -r $(EXPORT_DIR)/plate_detector.mlpackage $(IOS_MODEL_DIR)/
	cp $(EXPORT_DIR)/plate_detector.tflite $(ANDROID_ASSETS)/
	@echo "  iOS:     $(IOS_MODEL_DIR)/plate_detector.mlpackage"
	@echo "  Android: $(ANDROID_ASSETS)/plate_detector.tflite"

# ── OCR Model (PP-OCRv3) ────────────────────────────────────────────────────

download-ocr: setup ## Download PP-OCRv3 model (fine-tuned or base fallback)
	$(PYTHON) $(TRAINING_DIR)/export_ocr.py --download-only

export-ocr: setup ## Download + convert PP-OCRv3 to ONNX, CoreML, TFLite
	$(PYTHON) $(TRAINING_DIR)/export_ocr.py

evaluate-ocr: setup ## Validate OCR model on real plate images (go/no-go gate)
	@test -f $(EXPORT_DIR)/plate_ocr.onnx || (echo "Error: No ONNX model. Run 'make export-ocr' first." && exit 1)
	$(PYTHON) $(TRAINING_DIR)/evaluate_ocr.py $(if $(TEST_DIR),--test-dir $(TEST_DIR))

deploy-ocr: ## Copy OCR models to iOS and Android app directories
	@test -d $(EXPORT_DIR)/plate_ocr.mlpackage || (echo "Error: No CoreML OCR model. Run 'make export-ocr' first." && exit 1)
	@test -f $(EXPORT_DIR)/plate_ocr.tflite || (echo "Error: No TFLite OCR model. Run 'make export-ocr' first." && exit 1)
	@mkdir -p $(IOS_MODEL_DIR) $(ANDROID_ASSETS)
	@echo "Deploying OCR models to app directories..."
	cp -r $(EXPORT_DIR)/plate_ocr.mlpackage $(IOS_MODEL_DIR)/
	cp $(EXPORT_DIR)/plate_ocr.tflite $(ANDROID_ASSETS)/
	@echo "  iOS:     $(IOS_MODEL_DIR)/plate_ocr.mlpackage"
	@echo "  Android: $(ANDROID_ASSETS)/plate_ocr.tflite"

# ── Detect ───────────────────────────────────────────────────────────────────

detect: setup ## Run detection on images: make detect IMAGES=path/to/images
	@test -n "$(IMAGES)" || (echo "Usage: make detect IMAGES=path/to/image.jpg" && exit 1)
	$(PYTHON) $(TRAINING_DIR)/detect.py $(IMAGES) --save

# ── Cleanup ──────────────────────────────────────────────────────────────────

clean: ## Remove training runs, dataset cache, and exports
	rm -rf $(RUNS_DIR) $(DATASET_DIR) $(EXPORT_DIR)
	rm -f $(TRAINING_DIR)/evaluation_report.json
	rm -rf $(TRAINING_DIR)/evaluation_results $(TRAINING_DIR)/detection_results
	rm -rf $(TRAINING_DIR)/ocr_model
	rm -f CHANGELOG.md
	@echo "Cleaned training artifacts. Venv preserved (use 'make clean-all' to remove)."

clean-all: clean ## Remove everything including venv
	rm -rf $(VENV)
	@echo "Cleaned everything including venv."
