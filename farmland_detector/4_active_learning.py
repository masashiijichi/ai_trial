"""
Step 4: review/ フォルダを手動で仕分けした後、新たに追加されたラベル済み画像で
        既存モデルを継続学習（Active Learning ループ）する。

手順:
    1. 3_predict.py を実行 → review/ フォルダに要確認画像が集まる
    2. review/ の画像を手動で farmland/ または problem/ に移動
    3. このスクリプトを実行して再学習

使い方:
    python 4_active_learning.py --base_model models/model_v1.pth \
                                  --data_dir data \
                                  --output models/model_v2.pth \
                                  --epochs 10
"""

import argparse
import importlib.util
from pathlib import Path

# 2_train_model の train 関数を再利用
_spec = importlib.util.spec_from_file_location(
    "train_model", Path(__file__).parent / "2_train_model.py"
)
_mod = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(_mod)
train = _mod.train


def check_dataset(data_dir):
    data_dir = Path(data_dir)
    farmland_count = len(list((data_dir / "farmland").glob("*.jpg"))) if (data_dir / "farmland").exists() else 0
    problem_count = len(list((data_dir / "problem").glob("*.jpg"))) if (data_dir / "problem").exists() else 0
    review_count = len(list((data_dir / "review").glob("*.jpg"))) if (data_dir / "review").exists() else 0

    print("--- データセット状況 ---")
    print(f"  farmland: {farmland_count} 枚")
    print(f"  problem : {problem_count} 枚")
    if review_count > 0:
        print(f"  review  : {review_count} 枚 ← まだ仕分けされていません")
        print("  ※ review/ の画像を farmland/ または problem/ に移動してから再実行してください")
        return False
    if farmland_count < 10 or problem_count < 10:
        print(f"  学習データが少なすぎます（各クラス10枚以上必要）")
        return False
    return True


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--base_model", required=True, help="継続学習の起点となるモデル")
    parser.add_argument("--data_dir", default="data")
    parser.add_argument("--output", required=True, help="新バージョンのモデル保存先")
    parser.add_argument("--epochs", type=int, default=10)
    parser.add_argument("--batch_size", type=int, default=32)
    parser.add_argument("--lr", type=float, default=5e-5, help="継続学習は小さめの学習率")
    args = parser.parse_args()

    if not check_dataset(args.data_dir):
        return

    print(f"\n継続学習開始: {args.base_model} → {args.output}")
    train(
        data_dir=args.data_dir,
        output_path=args.output,
        epochs=args.epochs,
        batch_size=args.batch_size,
        lr=args.lr,
        resume=args.base_model,
    )


if __name__ == "__main__":
    main()
