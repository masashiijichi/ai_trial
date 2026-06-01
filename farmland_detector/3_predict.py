"""
Step 3: 学習済みモデルで未ラベル画像を推論し、
        - 確信度が高い → farmland/ または problem/ に自動仕分け
        - 確信度が低い → review/ に移動（手動確認用）

使い方:
    python 3_predict.py --model models/model_v1.pth \
                         --input data/unlabeled \
                         --threshold 0.85
"""

import argparse
import importlib.util
import shutil
import sys
from pathlib import Path

import torch
import torch.nn.functional as F
import torchvision.transforms as T
from PIL import Image
from tqdm import tqdm

# 2_train_model.py を動的インポート（数字始まりのモジュール名対応）
_spec = importlib.util.spec_from_file_location(
    "train_model", Path(__file__).parent / "2_train_model.py"
)
_mod = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(_mod)
build_model = _mod.build_model

DEVICE = torch.device("cuda" if torch.cuda.is_available() else "cpu")

TRANSFORM = T.Compose(
    [
        T.Resize((224, 224)),
        T.ToTensor(),
        T.Normalize([0.485, 0.456, 0.406], [0.229, 0.224, 0.225]),
    ]
)


def load_model(model_path):
    state = torch.load(model_path, map_location=DEVICE)
    model = build_model().to(DEVICE)
    model.load_state_dict(state["model"])
    model.eval()
    idx_to_class = {v: k for k, v in state["class_to_idx"].items()}
    return model, idx_to_class


def predict_directory(model_path, input_dir, threshold, dry_run=False):
    input_dir = Path(input_dir)
    model, idx_to_class = load_model(model_path)

    out_dirs = {
        "farmland": input_dir.parent / "farmland",
        "problem": input_dir.parent / "problem",
        "review": input_dir.parent / "review",
    }
    if not dry_run:
        for d in out_dirs.values():
            d.mkdir(parents=True, exist_ok=True)

    images = list(input_dir.glob("*.jpg")) + list(input_dir.glob("*.jpeg")) + list(input_dir.glob("*.png"))
    print(f"推論対象: {len(images)} 枚")

    results = {"farmland": 0, "problem": 0, "review": 0}
    records = []

    with torch.no_grad():
        for img_path in tqdm(images, desc="推論"):
            try:
                img = Image.open(img_path).convert("RGB")
                tensor = TRANSFORM(img).unsqueeze(0).to(DEVICE)
                logits = model(tensor)
                probs = F.softmax(logits, dim=1)[0]
                pred_idx = probs.argmax().item()
                confidence = probs[pred_idx].item()
                pred_class = idx_to_class[pred_idx]

                if confidence >= threshold:
                    dest_dir = out_dirs[pred_class]
                    dest_key = pred_class
                else:
                    dest_dir = out_dirs["review"]
                    dest_key = "review"

                records.append(
                    {
                        "file": img_path.name,
                        "pred": pred_class,
                        "confidence": round(confidence, 4),
                        "dest": dest_key,
                    }
                )
                results[dest_key] += 1

                if not dry_run:
                    shutil.move(str(img_path), dest_dir / img_path.name)

            except Exception as e:
                tqdm.write(f"  [skip] {img_path.name}: {e}")

    import pandas as pd

    df = pd.DataFrame(records)
    report_path = input_dir.parent / "predict_report.csv"
    df.to_csv(report_path, index=False)

    print("\n--- 推論結果 ---")
    print(f"  farmland (自動): {results['farmland']}")
    print(f"  problem  (自動): {results['problem']}")
    print(f"  review   (要確認): {results['review']}")
    print(f"レポート: {report_path}")
    return df


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--model", required=True)
    parser.add_argument("--input", default="data/unlabeled")
    parser.add_argument("--threshold", type=float, default=0.85,
                        help="この確信度未満は review/ へ移動")
    parser.add_argument("--dry_run", action="store_true", help="実際には移動しない")
    args = parser.parse_args()

    print(f"デバイス: {DEVICE}")
    predict_directory(args.model, args.input, args.threshold, dry_run=args.dry_run)


if __name__ == "__main__":
    main()
