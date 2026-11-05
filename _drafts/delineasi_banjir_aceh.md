---
jupytext:
  text_representation:
    extension: .md
    format_name: myst
    format_version: 0.13
    jupytext_version: 1.19.5
kernelspec:
  display_name: Python 3 (ipykernel)
  language: python
  name: python3
---

| <h1><b>Identifikasi Area Banjir</b></h1> | ![](files/piksel-logo-small.png)  |
|:---------|----------:|
- **Data:** Sentinel-1
- **Lokasi:** Kab. Aceh Utara, Provinsi Aceh
- **Metode:** Deteksi perubahan sebelum banjir dan saat banjir

+++

## Pendahuluan

Siklon tropis Senyar dengan hujan yang lebat telah melanda Asia Tenggara mulai November 26, 2025. Citra radar sentinel 1 digunakan untuk mendeteksi genangan banjir berdasarakan perubahan backscatter.

+++

## Tahapan

Tahapan dalam identifikasi area banjir adalah sebagai berikut:
1. Persiapan
2. Menentukan wilayah
3. Memuat data saat banjir
4. Memuat data sebelum banjir
5. Pendeteksian wilayah banjir
6. Visualisasi
7. Validasi data
8. Akurasi data

***

+++

## 1. Persiapan
Library yang diperlukan dimuat adalah sebagai berikut:

```{code-cell} ipython3
import numpy as np
import xarray as xr
from odc.geo.geom import point, box
from odc.stac import load
from planetary_computer import sign_url
from pystac_client import Client

from ipyleaflet import basemaps
from scipy.ndimage import median_filter, uniform_filter, variance, binary_opening, binary_closing, label
from skimage.filters import threshold_mean
import rioxarray, rasterio, folium
from rasterio.enums import Resampling
from folium import plugins
from pyproj import Transformer
from PIL import Image
import matplotlib.pyplot as plt
import matplotlib.colors as mcolors

import geopandas as gpd
from shapely.geometry import shape, shape
from rasterio import features
```

Selain itu, setting untuk akses data Sentinel-1 dibuat

```{code-cell} ipython3
# Microsoft Planetary Computer STAC Catalog URL
catalog = "https://planetarycomputer.microsoft.com/api/stac/v1"

# Membuat STAC Client
client = Client.open(catalog)
```

## 2. Menentukan wilayah
Area yang akan diproses ditentukan.

```{code-cell} ipython3
botlef = [4.996, 97.151]
upprig = [5.049, 97.207]

# Create GeoJSON polygon from bounding box
aoi_geojson = {
    "type": "Polygon",
    "coordinates": [[
        [botlef[1], botlef[0]],  # bottom-left: [lon, lat]
        [upprig[1], botlef[0]],  # bottom-right: [lon, lat]
        [upprig[1], upprig[0]],  # top-right: [lon, lat]
        [botlef[1], upprig[0]],  # top-left: [lon, lat]
        [botlef[1], botlef[0]]   # close the polygon
    ]]
}
datetime = "2025-11-25/2025-11-28"

items = client.search(
    collections=["sentinel-1-rtc"],
    intersects=aoi_geojson,
    datetime=datetime,
).item_collection()

print(f"Found {len(items)} items")
```

## 3. Memuat data saat banjir

Pertama ditentukan tanggal saat kejadian banjir. Lalu pencarian data dilakukan.

Membuka data saat banjir

```{code-cell} ipython3
# Membuka data Sentinel-1
data = load(
    items,
    geopolygon=aoi_geojson,
    measurements=["vv", "vh"],
    groupby="solar_day",
    patch_url=sign_url,
    chunks={"x": 2048, "y": 2048}
).compute()
data
```

Menghilangkan data yang tidak valid. Selanjutnya data dikonversi ke decibel (dB) karena:
1. Mengatasi rentang nilai yang sangat lebar
2. Meningkatkan kontras visual
3. Standar dalam remote sensing SAR
4. Memudahkan deteksi perubahan
5. Mengurangi pengaruh speckle noise
6. Interpretasi fisik yang jelas

```{code-cell} ipython3
# Mask nilai tidak valid (negatives and extreme values)
data['vv_clean'] = data.vv.where((data.vv > 0) & (data.vv < 10))
data['vh_clean'] = data.vh.where((data.vh > 0) & (data.vh < 10))

# Merubah data ke dB
data['vv_db'] = 10 * np.log10(data.vv_clean)
data['vh_db'] = 10 * np.log10(data.vh_clean)

# Plot
data.isel(time=range(0,2)).vv_db.plot(
    cmap="gray",  # or "viridis", "terrain"
    robust=True, 
    col="time", 
    col_wrap=2,
    vmin=-25,
    vmax=0
)
```

## 4. Memuat data sebelum banjir

Data sebelum banjir digunakan untuk dibandingkan dengan data saat banjir. Pertama ditentukan tanggal sebelum kejadian banjir. Lalu pencarian data dilakukan.

```{code-cell} ipython3
datetime_baseline = "2025-10-25/2025-10-30"  

items_pre = client.search(
    collections=["sentinel-1-rtc"],
    intersects=aoi_geojson,
    datetime=datetime_baseline,
).item_collection()

print(f"Ditemukan {len(items_pre)} dataset sebelum banjir")
```

Membuka data sebelum banjir

```{code-cell} ipython3
data_pre = load(
    items_pre,
    geopolygon=aoi_geojson,
    measurements=["vv", "vh"],
    groupby="solar_day",
    patch_url=sign_url,
    chunks={"x": 2048, "y": 2048}
).compute()
data_pre
```

Menghilangkan data yang tidak valid dan konversi data ke decibel (dB)

```{code-cell} ipython3
# mask nilai tidak valid (negatives and extreme values)
data_pre['vv_clean'] = data_pre.vv.where((data_pre.vv > 0) & (data_pre.vv < 10))
data_pre['vh_clean'] = data_pre.vh.where((data_pre.vh > 0) & (data_pre.vh < 10))

# merubah data ke dB
data_pre['vv_db'] = 10 * np.log10(data_pre.vv_clean)
data_pre['vh_db'] = 10 * np.log10(data_pre.vh_clean)

# Plot
data_pre.isel(time=range(0,1)).vv_db.plot(
    cmap="Greys_r", 
    robust=True, 
    col="time", 
    col_wrap=2,
    vmin=-25,
    vmax=0
)
```

## 5. Pendeteksian wilayah banjir

Tahapan dalam pendeteksian wilayah banjir adalah:
1. Reproject/align data sebelum dan saat banjir
2. Speckle filtering
3. Menghitung perubahan
4. Membuat mask banjir awal
5. Post processing:
   - Remove salt-and-pepper noise
   - Fill small gaps
   - Remove small objects
   - Update flood mask

```{code-cell} ipython3
# Step 1: Reproject/align data sebelum dan saat banjir
print("\n[1] Reproject/align data...")
vv_before_aligned = data_pre.vv_db.isel(time=0).rio.reproject_match(
    data.vv_db.isel(time=0),
    resampling=Resampling.bilinear
)
vv_after = data.vv_db.isel(time=0)  # Nov 27
print("✓ Images aligned")

# Step 2: Speckle filtering
print("\n[2] Speckle filter...")

def apply_speckle_filter(data_db, window_size=5):
    """Apply median filter to reduce speckle noise"""
    filtered = xr.apply_ufunc(
        median_filter,
        data_db,
        kwargs={'size': window_size},
        dask='parallelized'
    )
    return filtered

vv_before_filtered = apply_speckle_filter(vv_before_aligned, window_size=5)
vv_after_filtered = apply_speckle_filter(vv_after, window_size=5)
print("✓ Speckle filter applied (5x5 median)")

# Step 3: Menghitung perubahan
print("\n[3] Menghitung perubahan...")
vv_change = vv_after_filtered - vv_before_filtered

mean_change = float(vv_change.mean().values)
std_change = float(vv_change.std().values)
print(f"✓ Mean change: {mean_change:.2f} dB")
print(f"✓ Std dev: {std_change:.2f} dB")

# Step 4: Membuat mask banjir awal
print("\n[4] Membuat mask banjir awal...")
flood_mask_raw = (vv_after_filtered < -12) & (vv_change < -3)
flooded_pixels_raw = int(flood_mask_raw.sum().values)
print(f"✓ Raw classification: {flooded_pixels_raw:,} pixels")

# Step 5: Post processing 
print("\n[5] Post-processing...")
# Step 5a: Remove salt-and-pepper noise (opening)
print("  → Removing isolated noise pixels...")
flood_opened = binary_opening(flood_mask_raw.values, structure=np.ones((3, 3)))
flooded_after_opening = int(flood_opened.sum())
removed_opening = flooded_pixels_raw - flooded_after_opening
print(f"    Removed: {removed_opening:,} pixels")

# Step 5b: Fill small gaps (closing)
print("  → Filling small gaps...")
flood_closed = binary_closing(flood_opened, structure=np.ones((5, 5)))
flooded_after_closing = int(flood_closed.sum())
added_closing = flooded_after_closing - flooded_after_opening
print(f"    Added: {added_closing:,} pixels")

# Step 5c: Remove small objects
print("  → Removing small objects...")
labeled_array, num_features = label(flood_closed)
min_flood_size = 100  # minimum 100 pixels (~0.01 km²)

flood_cleaned = flood_closed.copy()
small_objects_removed = 0

for i in range(1, num_features + 1):
    object_size = np.sum(labeled_array == i)
    if object_size < min_flood_size:
        flood_cleaned[labeled_array == i] = 0
        small_objects_removed += 1

flooded_final = int(flood_cleaned.sum())
removed_small = flooded_after_closing - flooded_final

print(f"    Removed {small_objects_removed} small objects")
print(f"    Removed: {removed_small:,} pixels")

# Step 5d: Update flood mask with cleaned version
flood_mask = flood_mask_raw.copy()
flood_mask.values = flood_cleaned

print(f"\n✓ Post-processing complete!")
print(f"  Before: {flooded_pixels_raw:,} pixels")
print(f"  After:  {flooded_final:,} pixels")
print(f"  Cleaned: {flooded_pixels_raw - flooded_final:,} pixels ({(flooded_pixels_raw - flooded_final)/flooded_pixels_raw*100:.1f}%)")
```

## 6. Visualisasi

Ada dua jenis visualisasi hasil peta genangan banjir.
1. Menampilkan perbandingan data

```{code-cell} ipython3
# Step 1: Visualisasi peta
print("\nMembuat peta ...")
fig, axes = plt.subplots(2, 2, figsize=(14, 12))

# sebelum banjir
vv_before_filtered.plot(ax=axes[0,0], cmap="gray", vmin=-25, vmax=0)
axes[0,0].set_title('Sebelum Banjir (28 Okt 2025)', fontsize=12, fontweight='bold')

# saat banjir
vv_after_filtered.plot(ax=axes[0,1], cmap="gray", vmin=-25, vmax=0)
axes[0,1].set_title('Saat Banjir (27 Nov 2025)', fontsize=12, fontweight='bold')

# deteksi perubahan
vv_change.plot(ax=axes[1,0], cmap="RdBu_r", vmin=-10, vmax=10)
axes[1,0].set_title('Perubahan Backscatter (dB)\nBlue = Decrease (Potential Flood)', 
                     fontsize=12, fontweight='bold')

# peta banjir
flood_mask.plot(ax=axes[1,1], cmap="Blues", add_colorbar=False)
axes[1,1].set_title(f'Genangan Banjir\n{flooded_final:,} pixels', 
                     fontsize=12, fontweight='bold')
plt.tight_layout()
plt.show()

# Step 2: menghitung area terdampak
print("\nMenghitung area terdampak ...")
pixel_area = abs(data.x[1] - data.x[0]) * abs(data.y[1] - data.y[0])  # m²
flooded_pixels = flood_mask.sum().values
flooded_area_km2 = (flooded_pixels * pixel_area) / 1_000_000

print(f"\n{'='*60}")
print(f"HASIL PETA GENANGAN BANJIR")
print(f"{'='*60}")
print(f"Date comparison: 28 Okt → 27 Nov, 2025")
print(f"Time difference: 24 days")
print(f"")
print(f"Flooded area: {flooded_area_km2:.2f} km²")
print(f"Flooded pixels: {flooded_pixels:,}")
print(f"Pixel resolution: {np.sqrt(pixel_area):.1f} m")
print(f"")
print(f"Processing steps:")
print(f"  ✓ Speckle filtering (5x5 median)")
print(f"  ✓ Change detection (before vs after)")
print(f"  ✓ Dual threshold (-12 dB & -3 dB change)")
print(f"  ✓ Morphological cleaning")
print(f"  ✓ Small object removal (< 100 pixels)")
print(f"{'='*60}\n")
```

## 7. Validasi data

Peta genangan banjir perlu divalidasi untuk mengetahui perubahan hasil ketika parameter diubah.

```{code-cell} ipython3
fig, axes = plt.subplots(2, 3, figsize=(18, 12))

# Method 1: Your current method
flood_mask.plot(ax=axes[0, 0], cmap='Blues', add_colorbar=False)
axes[0, 0].set_title(f'Current Method\n{flood_mask.sum().values:,} pixels', 
                     fontsize=11, fontweight='bold')

# Method 2: Conservative
flood_conservative = (vv_after < -15) & (vv_change < -4)
flood_conservative.plot(ax=axes[0, 1], cmap='Blues', add_colorbar=False)
axes[0, 1].set_title(f'Conservative\n{flood_conservative.sum().values:,} pixels', 
                     fontsize=11, fontweight='bold')

# Method 3: Sensitive
flood_sensitive = (vv_after < -10) & (vv_change < -2.5)
flood_sensitive.plot(ax=axes[0, 2], cmap='Blues', add_colorbar=False)
axes[0, 2].set_title(f'Sensitive\n{flood_sensitive.sum().values:,} pixels', 
                     fontsize=11, fontweight='bold')

# Method 4: With speckle filter
vv_after_filt = apply_speckle_filter(vv_after, 5)
vv_change_filt = vv_after_filt - apply_speckle_filter(vv_before_aligned, 5)
flood_filtered = (vv_after_filt < -13) & (vv_change_filt < -3)
flood_filtered.plot(ax=axes[1, 0], cmap='Blues', add_colorbar=False)
axes[1, 0].set_title(f'With Speckle Filter\n{flood_filtered.sum().values:,} pixels', 
                     fontsize=11, fontweight='bold')

# Method 5: With post-processing
flood_cleaned = flood_filtered.copy()
flood_cleaned.values = binary_opening(flood_filtered.values, np.ones((3,3)))
flood_cleaned.values = binary_closing(flood_cleaned.values, np.ones((5,5)))
flood_cleaned.plot(ax=axes[1, 1], cmap='Blues', add_colorbar=False)
axes[1, 1].set_title(f'With Post-Processing\n{flood_cleaned.sum().values:,} pixels', 
                     fontsize=11, fontweight='bold')

# Method 6: Overlay on satellite
vv_after.plot(ax=axes[1, 2], cmap='gray', vmin=-25, vmax=0)
axes[1, 2].contour(flood_cleaned.values, colors='red', linewidths=2, levels=[0.5])
axes[1, 2].set_title('Final Result on Backscatter', fontsize=11, fontweight='bold')

plt.tight_layout()
plt.show()
```

## 8. Akurasi data

Akurasi peta perlu diketahui untuk mendapatkan kualitas peta yang dihasilkan.

```{code-cell} ipython3
# membuat histogram perubahan backscatter
fig, axes = plt.subplots(1, 2, figsize=(14, 5))
vv_change_flat = vv_change.values[~np.isnan(vv_change.values)]
axes[0].hist(vv_change_flat, bins=100, color='steelblue', edgecolor='black', alpha=0.7)
axes[0].axvline(-3, color='red', linestyle='--', linewidth=2, label='Threshold: -3 dB')
axes[0].axvline(vv_change.mean().values, color='green', linestyle='--', 
                linewidth=2, label=f'Mean: {vv_change.mean().values:.2f} dB')
axes[0].set_xlabel('Perubahan Backscatter (dB)', fontsize=12)
axes[0].set_ylabel('Frekuensi', fontsize=12)
axes[0].set_title('Frekuensi Perubahan Backscatter', fontsize=12, fontweight='bold')
axes[0].legend()
axes[0].grid(True, alpha=0.3)

# Scatter plot: sebelum dan saat banjir
sample_size = 10000
indices = np.random.choice(len(vv_before_aligned.values.flatten()), sample_size, replace=False)
before_sample = vv_before_aligned.values.flatten()[indices]
after_sample = vv_after.values.flatten()[indices]
flood_sample = flood_mask.values.flatten()[indices]

axes[1].scatter(before_sample[~flood_sample], after_sample[~flood_sample], 
                alpha=0.3, s=1, c='gray', label='Bukan banjir')
axes[1].scatter(before_sample[flood_sample], after_sample[flood_sample], 
                alpha=0.5, s=2, c='red', label='Banjir')
axes[1].plot([-30, 5], [-30, 5], 'k--', linewidth=1, label='Tidak berubah')
axes[1].plot([-30, 5], [-33, 2], 'b--', linewidth=1, label='Perubahan -3 dB')
axes[1].set_xlabel('Sebelum banjir (dB)', fontsize=12)
axes[1].set_ylabel('Saat banjir (dB)', fontsize=12)
axes[1].set_title('Backscatter [Sebelum & Saat Banjir]', fontsize=12, fontweight='bold')
axes[1].legend()
axes[1].grid(True, alpha=0.3)
axes[1].set_xlim(-25, 0)
axes[1].set_ylim(-25, 0)

plt.tight_layout()
plt.show()
```

## Catatan
Modul ini memberikan gambaran penggunaan citra radar Sentinel 1 dengan hasil:
1. Metode threshold -3 dB berhasil memisahkan area banjir dari non-banjir
2. Area banjir terdeteksi sebagai piksel dengan penurunan backscatter ≥ 3 dB
3. Distribusi data menunjukkan mayoritas area tidak tergenang, dengan sebagian kecil area mengalami banjir
4. Hasil ini valid karena air menyebabkan specular reflection yang mengurangi backscatter radar SAR

+++

## Info

- Modul ini dijalankan di platform Piksel. Jika ada pertanyaan atau komentar, silahkan email ke piksel@big.go.id
- **Lisensi:** Skrip dalam notebook ini dilisensikan berdasarkan [Apache License, Version 2.0](https://www.apache.org/licenses/LICENSE-2.0). 
Data Piksel dilisensikan berdasarkan lisensi [Creative Commons by Attribution 4.0](https://creativecommons.org/licenses/by/4.0/).

```{code-cell} ipython3

```
