"""
Step 2: 手動で仕分けした画像でCNNを学習する。

ディレクトリ構造:
    data/
      farmland/   ← 正常な農地画像
      problem/    ← 問題エリア画像（建物・道路が1/3以上）

使い方:
    python 2_train_model.py --data_dir data \
                             --epochs 20 \
                             --batch_size 32 \
                             --output models/model_v1.pth
"""

import argparse
import json
import os
from pathlib import Path

import torch
import torch.nn as nn
import torchvision.transforms as T
from torch.utils.data import DataLoader, random_split
from torchvision import datasets, models
from tqdm import tqdm


CLASSES = ["farmland", "problem"]
DEVICE = torch.device("cuda" if torch.cuda.is_available() else "cpu")


def build_transforms(train=True):
    if train:
        return T.Compose(
            [
                T.Resize((224, 224)),
                T.RandomHorizontalFlip(),
                T.RandomVerticalFlip(),
                T.ColorJitter(brightness=0.2, contrast=0.2, saturation=0.1),
                T.RandomRotation(15),
                T.ToTensor(),
                T.Normalize([0.485, 0.456, 0.406], [0.229, 0.224, 0.225]),
            ]
        )
    return T.Compose(
        [
            T.Resize((224, 224)),
            T.ToTensor(),
            T.Normalize([0.485, 0.456, 0.406], [0.229, 0.224, 0.225]),
        ]
    )


def build_model(num_classes=2, freeze_backbone=False):
    """EfficientNet-B0 をベースに転移学習。"""
    model = models.efficientnet_b0(weights=models.EfficientNet_B0_Weights.DEFAULT)
    if freeze_backbone:
        for p in model.features.parameters():
            p.requires_grad = False
    in_features = model.classifier[1].in_features
    model.classifier[1] = nn.Linear(in_features, num_classes)
    return model


def train_epoch(model, loader, criterion, optimizer):
    model.train()
    total_loss, correct, total = 0.0, 0, 0
    for imgs, labels in tqdm(loader, leave=False, desc="  train"):
        imgs, labels = imgs.to(DEVICE), labels.to(DEVICE)
        optimizer.zero_grad()
        out = model(imgs)
        loss = criterion(out, labels)
        loss.backward()
        optimizer.step()
        total_loss += loss.item() * imgs.size(0)
        correct += (out.argmax(1) == labels).sum().item()
        total += imgs.size(0)
    return total_loss / total, correct / total


def eval_epoch(model, loader, criterion):
    model.eval()
    total_loss, correct, total = 0.0, 0, 0
    with torch.no_grad():
        for imgs, labels in tqdm(loader, leave=False, desc="  val  "):
            imgs, labels = imgs.to(DEVICE), labels.to(DEVICE)
            out = model(imgs)
            loss = criterion(out, labels)
            total_loss += loss.item() * imgs.size(0)
            correct += (out.argmax(1) == labels).sum().item()
            total += imgs.size(0)
    return total_loss / total, correct / total


def train(data_dir, output_path, epochs, batch_size, lr, val_ratio=0.15, resume=None):
    data_dir = Path(data_dir)

    # データセット（train/val 共通の augmentation は train のみ）
    full_ds = datasets.ImageFolder(data_dir, transform=build_transforms(train=True))

    # クラス確認
    print(f"クラス: {full_ds.class_to_idx}")
    print(f"総サンプル数: {len(full_ds)}")

    n_val = max(1, int(len(full_ds) * val_ratio))
    n_train = len(full_ds) - n_val
    train_ds, val_ds = random_split(full_ds, [n_train, n_val], generator=torch.Generator().manual_seed(42))

    # val は augmentation なし
    val_ds.dataset = datasets.ImageFolder(data_dir, transform=build_transforms(train=False))

    train_loader = DataLoader(train_ds, batch_size=batch_size, shuffle=True, num_workers=4, pin_memory=True)
    val_loader = DataLoader(val_ds, batch_size=batch_size, shuffle=False, num_workers=4, pin_memory=True)

    model = build_model().to(DEVICE)

    if resume and Path(resume).exists():
        print(f"チェックポイント読み込み: {resume}")
        state = torch.load(resume, map_location=DEVICE)
        model.load_state_dict(state["model"])

    # クラス不均衡対策
    counts = [0] * 2
    for _, label in full_ds.samples:
        counts[label] += 1
    weights = torch.tensor([1.0 / c for c in counts], dtype=torch.float).to(DEVICE)
    criterion = nn.CrossEntropyLoss(weight=weights)

    optimizer = torch.optim.AdamW(model.parameters(), lr=lr, weight_decay=1e-4)
    scheduler = torch.optim.lr_scheduler.CosineAnnealingLR(optimizer, T_max=epochs)

    best_val_acc = 0.0
    history = []

    output_path = Path(output_path)
    output_path.parent.mkdir(parents=True, exist_ok=True)

    for epoch in range(1, epochs + 1):
        train_loss, train_acc = train_epoch(model, train_loader, criterion, optimizer)
        val_loss, val_acc = eval_epoch(model, val_loader, criterion)
        scheduler.step()

        print(
            f"Epoch {epoch:03d}/{epochs} | "
            f"train loss={train_loss:.4f} acc={train_acc:.4f} | "
            f"val loss={val_loss:.4f} acc={val_acc:.4f}"
        )

        history.append({"epoch": epoch, "train_loss": train_loss, "train_acc": train_acc,
                         "val_loss": val_loss, "val_acc": val_acc})

        if val_acc > best_val_acc:
            best_val_acc = val_acc
            torch.save(
                {
                    "epoch": epoch,
                    "model": model.state_dict(),
                    "class_to_idx": full_ds.class_to_idx,
                    "val_acc": val_acc,
                },
                output_path,
            )
            print(f"  → モデル保存 (val_acc={val_acc:.4f})")

    # 学習履歴保存
    log_path = output_path.parent / (output_path.stem + "_history.json")
    with open(log_path, "w") as f:
        json.dump(history, f, indent=2)

    print(f"\n学習完了。最良 val_acc={best_val_acc:.4f}")
    print(f"モデル: {output_path}")


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--data_dir", default="data", help="farmland/ と problem/ を含むディレクトリ")
    parser.add_argument("--output", default="models/model_v1.pth")
    parser.add_argument("--epochs", type=int, default=20)
    parser.add_argument("--batch_size", type=int, default=32)
    parser.add_argument("--lr", type=float, default=1e-4)
    parser.add_argument("--resume", default=None, help="継続学習するチェックポイントパス")
    args = parser.parse_args()

    print(f"デバイス: {DEVICE}")
    train(args.data_dir, args.output, args.epochs, args.batch_size, args.lr, resume=args.resume)


if __name__ == "__main__":
    main()
