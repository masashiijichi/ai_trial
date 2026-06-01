"""
Step 1: GeoJSONの農地ポリゴンからGoogle Earth Engine経由で衛星画像を取得し、
        ポリゴン境界を重ねてJPEGとして保存する。

使い方:
    python 1_download_images.py --geojson path/to/farmland.geojson \
                                 --output data/unlabeled \
                                 --zoom 18 \
                                 --max_polygons 5000
"""

import argparse
import json
import os
import sys
import time
import io
import hashlib
from pathlib import Path

import ee
import geopandas as gpd
import numpy as np
from PIL import Image, ImageDraw
from shapely.geometry import shape, mapping
from tqdm import tqdm


# 画像サイズ（ピクセル）
IMG_SIZE = 256

# GEE から取得する衛星画像の設定
COLLECTION = "GOOGLE/DYNAMICWORLD/V1"  # fallback: Sentinel-2
SENTINEL2_COLLECTION = "COPERNICUS/S2_SR_HARMONIZED"


def authenticate_gee():
    """Google Earth Engine 認証。初回は `earthengine authenticate` を実行済みであること。"""
    try:
        ee.Initialize(opt_url="https://earthengine.googleapis.com")
        print("GEE 認証成功")
    except Exception:
        print("GEE 認証が必要です。以下を実行してください:")
        print("  earthengine authenticate")
        sys.exit(1)


def polygon_to_bbox(geom):
    """Shapely geometry から (minx, miny, maxx, maxy) を返す。"""
    return geom.bounds


def fetch_satellite_image(bounds, year=2023):
    """
    GEE から Sentinel-2 の RGB 画像を取得して PIL Image として返す。

    bounds: (minx, miny, maxx, maxy) in WGS84
    """
    minx, miny, maxx, maxy = bounds

    # バウンディングボックスが極端に小さい場合は少し拡張
    margin = 0.0001
    region = ee.Geometry.BBox(minx - margin, miny - margin, maxx + margin, maxy + margin)

    s2 = (
        ee.ImageCollection(SENTINEL2_COLLECTION)
        .filterBounds(region)
        .filterDate(f"{year}-04-01", f"{year}-10-31")  # 農繁期に絞る
        .filter(ee.Filter.lt("CLOUDY_PIXEL_PERCENTAGE", 20))
        .median()
        .select(["B4", "B3", "B2"])  # RGB
    )

    url = s2.getThumbURL(
        {
            "region": region,
            "dimensions": IMG_SIZE,
            "format": "jpg",
            "min": 0,
            "max": 3000,
            "gamma": 1.4,
        }
    )

    import requests

    for attempt in range(3):
        try:
            resp = requests.get(url, timeout=30)
            resp.raise_for_status()
            img = Image.open(io.BytesIO(resp.content)).convert("RGB")
            return img
        except Exception as e:
            if attempt == 2:
                raise RuntimeError(f"画像取得失敗: {e}") from e
            time.sleep(2 ** attempt)


def project_coords_to_pixel(coords, bounds, img_w, img_h):
    """
    WGS84 座標リストを画像ピクセル座標に変換する。

    coords: [(lon, lat), ...]
    bounds: (minx, miny, maxx, maxy)
    """
    minx, miny, maxx, maxy = bounds
    span_x = maxx - minx
    span_y = maxy - miny
    pixels = []
    for lon, lat in coords:
        px = int((lon - minx) / span_x * img_w)
        py = int((maxy - lat) / span_y * img_h)
        pixels.append((px, py))
    return pixels


def draw_polygon_overlay(img, geom, bounds):
    """
    PIL Image の上に農地ポリゴンの境界線を描画する。
    農地=緑の半透明塗りつぶし + 白枠線。
    """
    overlay = Image.new("RGBA", img.size, (0, 0, 0, 0))
    draw = ImageDraw.Draw(overlay)
    img_w, img_h = img.size

    geom_type = geom.geom_type
    if geom_type == "Polygon":
        rings = [geom.exterior] + list(geom.interiors)
    elif geom_type == "MultiPolygon":
        rings = []
        for poly in geom.geoms:
            rings.append(poly.exterior)
            rings.extend(poly.interiors)
    else:
        return img

    for ring in rings:
        coords = list(ring.coords)
        pixels = project_coords_to_pixel(coords, bounds, img_w, img_h)
        if len(pixels) >= 3:
            draw.polygon(pixels, fill=(0, 200, 0, 60))   # 半透明グリーン
            draw.line(pixels + [pixels[0]], fill=(255, 255, 255, 220), width=2)

    result = Image.alpha_composite(img.convert("RGBA"), overlay)
    return result.convert("RGB")


def polygon_uid(row_geom, index):
    """ポリゴンの一意ID（ハッシュベース）。"""
    wkt = row_geom.wkt[:200]
    return hashlib.md5(f"{index}_{wkt}".encode()).hexdigest()[:12]


def download_images(geojson_path, output_dir, zoom=18, max_polygons=None, year=2023):
    output_dir = Path(output_dir)
    output_dir.mkdir(parents=True, exist_ok=True)

    print(f"GeoJSON 読み込み: {geojson_path}")
    gdf = gpd.read_file(geojson_path)

    # WGS84 に統一
    if gdf.crs and gdf.crs.to_epsg() != 4326:
        gdf = gdf.to_crs(epsg=4326)

    # ポリゴンのみ
    gdf = gdf[gdf.geometry.geom_type.isin(["Polygon", "MultiPolygon"])].reset_index(drop=True)
    print(f"有効ポリゴン数: {len(gdf)}")

    if max_polygons:
        gdf = gdf.head(max_polygons)
        print(f"先頭 {max_polygons} 件を処理")

    success, skip, error = 0, 0, 0
    meta_records = []

    for idx, row in tqdm(gdf.iterrows(), total=len(gdf), desc="画像取得"):
        geom = row.geometry
        uid = polygon_uid(geom, idx)
        out_path = output_dir / f"{uid}.jpg"

        if out_path.exists():
            skip += 1
            continue

        bounds = polygon_to_bbox(geom)
        span = max(bounds[2] - bounds[0], bounds[3] - bounds[1])

        # 極端に小さい or 大きいポリゴンはスキップ
        if span < 0.00005 or span > 0.5:
            skip += 1
            continue

        try:
            img = fetch_satellite_image(bounds, year=year)
            img = draw_polygon_overlay(img, geom, bounds)
            img = img.resize((IMG_SIZE, IMG_SIZE), Image.LANCZOS)
            img.save(out_path, "JPEG", quality=90)
            success += 1

            meta_records.append(
                {
                    "uid": uid,
                    "path": str(out_path),
                    "bounds": bounds,
                    "area_deg2": geom.area,
                }
            )

            # GEE の quota 対策
            time.sleep(0.3)

        except Exception as e:
            tqdm.write(f"  [skip] idx={idx} uid={uid}: {e}")
            error += 1

    # メタデータ保存
    import pandas as pd

    pd.DataFrame(meta_records).to_csv(output_dir / "metadata.csv", index=False)

    print(f"\n完了: 成功={success}, スキップ={skip}, エラー={error}")
    print(f"保存先: {output_dir}")


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--geojson", required=True, help="農地GeoJSONファイルパス")
    parser.add_argument("--output", default="data/unlabeled", help="出力ディレクトリ")
    parser.add_argument("--year", type=int, default=2023, help="衛星画像の取得年")
    parser.add_argument("--max_polygons", type=int, default=None, help="処理するポリゴン数の上限")
    args = parser.parse_args()

    authenticate_gee()
    download_images(args.geojson, args.output, year=args.year, max_polygons=args.max_polygons)


if __name__ == "__main__":
    main()
