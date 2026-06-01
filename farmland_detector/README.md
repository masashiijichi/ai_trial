# 農地問題エリア検出システム

農地GeoJSONとSentinel-2衛星画像を組み合わせ、建物・道路が1/3以上を占める「問題エリア」をCNNで判別する。

## セットアップ

```bash
pip install -r requirements.txt

# Google Earth Engine 認証（初回のみ）
earthengine authenticate
```

## ワークフロー

```
GeoJSON
  ↓
[Step 1] 画像取得 → data/unlabeled/
  ↓
[手動ラベリング] 一部を farmland/ と problem/ に仕分け
  ↓
[Step 2] 初回学習 → models/model_v1.pth
  ↓
[Step 3] 全unlabeled画像を推論 → 確信度低は review/ へ
  ↓
[手動仕分け] review/ の画像を farmland/ or problem/ へ移動
  ↓
[Step 4] 継続学習 → models/model_v2.pth
  ↓ (Step3→手動仕分け→Step4 を繰り返す)
```

## Step 1: 衛星画像の取得

```bash
python 1_download_images.py \
  --geojson path/to/farmland.geojson \
  --output data/unlabeled \
  --year 2023 \
  --max_polygons 10000
```

出力: `data/unlabeled/<uid>.jpg`（農地ポリゴン境界を緑線でオーバーレイ済み）

## Step 2: 初回学習

まず `data/unlabeled/` から数百枚を手動で仕分けしてください:
- `data/farmland/` ← 正常な農地
- `data/problem/`  ← 建物・道路が多い問題エリア

```bash
python 2_train_model.py \
  --data_dir data \
  --output models/model_v1.pth \
  --epochs 20
```

## Step 3: 未ラベル画像の推論

```bash
python 3_predict.py \
  --model models/model_v1.pth \
  --input data/unlabeled \
  --threshold 0.85
```

- 確信度 ≥ 0.85 → `data/farmland/` or `data/problem/` に自動移動
- 確信度 < 0.85 → `data/review/` に移動（要手動確認）

## Step 4: 継続学習（Active Learning）

`data/review/` の画像を手動で `farmland/` または `problem/` に移動してから:

```bash
python 4_active_learning.py \
  --base_model models/model_v1.pth \
  --data_dir data \
  --output models/model_v2.pth \
  --epochs 10
```

Step 3 → 手動仕分け → Step 4 を繰り返すことで精度が向上する。

## ディレクトリ構造

```
farmland_detector/
├── data/
│   ├── unlabeled/   # Step1 の出力・推論前の画像
│   ├── farmland/    # 正常農地（ラベル済み）
│   ├── problem/     # 問題エリア（ラベル済み）
│   └── review/      # 確信度低・手動確認待ち
├── models/          # 学習済みモデル
├── logs/
├── 1_download_images.py
├── 2_train_model.py
├── 3_predict.py
├── 4_active_learning.py
└── requirements.txt
```

## Google Earth Engine について

- 研究・非営利目的は無料: https://signup.earthengine.google.com/
- 商用利用は有償プランが必要
- Sentinel-2 データは10m解像度・無償公開（ESA）
