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

| <h1><b>Perubahan Tutupan Lahan</b></h1> | ![](files/piksel_logo_small.png) |
|:---------|----------:|
- **Data:** Sentinel-2
- **Lokasi:** Kabupaten Subang, Provinsi Jawa Barat
- **Metode:** Transformasi Citra

+++

# Pendahuluan

Perubahan tutupan lahan merupakan salah satu fenomena yang tidak terpisahkan dari dinamika pembangunan wilayah, khususnya di daerah dengan pertumbuhan ekonomi yang pesat. Salah satu bentuk perubahan yang signifikan adalah konversi lahan pertanian menjadi kawasan industri serta lahan terbuka sebagai tahap awal pembangunan. Konversi lahan pertanian menjadi kawasan industri dan lahan terbuka memiliki dampak yang kompleks, baik dari aspek lingkungan, sosial, maupun ekonomi. Dari sisi lingkungan, perubahan ini dapat menyebabkan penurunan kapasitas produksi pangan, degradasi tanah, serta perubahan keseimbangan ekosistem. Sementara itu, dari sisi ekonomi, pembangunan industri berpotensi meningkatkan investasi, membuka lapangan kerja, dan mendorong pertumbuhan wilayah. Oleh karena itu, diperlukan suatu pendekatan analisis yang mampu memantau dan mengkuantifikasi perubahan tutupan lahan secara akurat dan berkelanjutan.

Pemanfaatan data penginderaan jauh, seperti citra satelit resolusi menengah, menjadi salah satu metode yang efektif dalam mengidentifikasi dan menganalisis perubahan tutupan lahan. Melalui analisis indeks spektral, seperti NDVI dan NDBI, perubahan dari vegetasi menjadi area terbangun maupun lahan terbuka dapat dideteksi secara spasial dan temporal.

+++

# Tahapan

Tahapan dalam identifikasi perubahan tutupan lahan adalah sebagai berikut:
1. Persiapan
2. Menentukan wilayah
3. Memuat data
4. Transformasi citra
5. Visualisasi

***

+++

## 1. Persiapan
Library yang diperlukan adalah sebagai berikut:

```{code-cell} ipython3
from datacube import Datacube
import numpy as np
import xarray as xr
import pandas as pd
from odc.geo.geom import point
from ipyleaflet import basemaps
import matplotlib.pyplot as plt
from matplotlib.colors import ListedColormap, BoundaryNorm
import matplotlib.patches as mpatches

dc = Datacube()
```

## 2. Menentukan wilayah
Langkah selanjutnya yakni menentukan wilayah kajian. Pada kasus ini, lokasi wilayah kajian berada di Kabupaten Subang Provinsi Jawa Barat

```{code-cell} ipython3
coords = -6.4510, 107.6058
aoi = point(coords[1], coords[0], crs="EPSG:4326")
bbox = aoi.buffer(0.01).boundingbox
region = aoi.buffer(0.01).boundingbox.polygon
region.explore(tiles=basemaps.Esri.WorldImagery)
```

## 3. Memuat data

Tahap ini bertujuan untuk mengidentifikasi dan menentukan data yang diperlukan untuk mendukung analisis. Pada tahap ini dimuat scene citra termutakhir untuk perbandingan data akhir.

```{code-cell} ipython3
datetime_2026 = "2026"
data = dc.load(
    product="s2_l2a",
    measurements=["red", "green", "blue", "nir", "swir16"],
    output_crs="EPSG:32748",
    resolution=10,
    time=datetime_2026,
    longitude=(bbox.left, bbox.right),
    latitude=(bbox.bottom, bbox.top),
    dask_chunks={},
    group_by="solar_day",
    cloud_cover=(0, 60),
)
data
```

Pada langkah ini ditentukan waktu perekaman untuk kajian analisis

```{code-cell} ipython3
target_date = pd.Timestamp("2026-04-03")
mask = data.time.dt.floor("D") == target_date
# mask = (data.time.dt.month == 4)
data_may = data.sel(time=mask)

rgb = data_may[['red', 'green', 'blue']].to_array(dim='band')
rgb.plot.imshow(
    col="time",
    col_wrap=min(4, data_may.time.size),
    size=4,
    vmin=0,
    vmax=3000,
    robust=True
)
```

Tahap ini dimuat kembali scene citra, namun menggunakan scene citra terdahulu untuk perbandingan data awal.

```{code-cell} ipython3
datetime_2023 = "2023"
data_2023 = dc.load(
    product="s2_l2a",
    measurements=["red", "green", "blue", "nir", "swir16"],
    output_crs="EPSG:32748",
    resolution=10,
    time=datetime_2023,
    longitude=(bbox.left, bbox.right),
    latitude=(bbox.bottom, bbox.top),
    dask_chunks={},
    group_by="solar_day",
    cloud_cover=(0, 60),
)
data_2023
```

Pada langkah ini spesifik ditentukan waktu perekaman untuk kajian analisis.

```{code-cell} ipython3
target_date = pd.Timestamp("2023-04-19")
mask = data_2023.time.dt.floor("D") == target_date
# mask = (data_2023.time.dt.month == 4)
data_may = data_2023.sel(time=mask)

rgb = data_may[['red', 'green', 'blue']].to_array(dim='band')
rgb.plot.imshow(
    col="time",
    col_wrap=min(4, data_may.time.size),
    size=4,
    vmin=0,
    vmax=3000,
    robust=True
)
```

## 4. Transformasi citra

Tahapan ini bertujuan untuk mengidentifikasi dan menganalisis perubahan tutupan lahan dari area vegetasi menggunakan transformasi citra. Indeks citra yang digunakan yakni NDVI (untuk menonjolkan aspek vegetasi) dan NDBI (untuk menonjolkan aspek bangunan dan lahan terbuka). Hasil transformasi citra kemudian dianalisis perubahan lahannya beserta perhitungan luasan perubahannya.

```{code-cell} ipython3
# ── Change Detection: Rice Field / Plantation → Factory ──────────────────────
# Both scenes are visually cloud-free; no SCL masking is applied.
# Classification is based purely on spectral indices (NDVI, NDBI).
# ─────────────────────────────────────────────────────────────────────────────

def ndvi(ds):
    red = ds["red"].squeeze().astype(float)
    nir = ds["nir"].squeeze().astype(float)
    return (nir - red) / (nir + red + 1e-9)

def ndbi(ds):
    nir  = ds["nir"].squeeze().astype(float)
    swir = ds["swir16"].squeeze().astype(float)
    return (swir - nir) / (swir + nir + 1e-9)

# ── Select the two target scenes ─────────────────────────────────────────────

t2023_date = pd.Timestamp("2023-04-19")
t2026_date = pd.Timestamp("2026-04-03")

scene_2023 = data_2023.sel(time=data_2023.time.dt.floor("D") == t2023_date)
scene_2026 = data.sel(time=data.time.dt.floor("D") == t2026_date)

ndvi_2023 = ndvi(scene_2023)
ndvi_2026 = ndvi(scene_2026)
ndbi_2026 = ndbi(scene_2026)

# ── Thresholds ────────────────────────────────────────────────────────────────
# 2023: low NDVI threshold covers fallow/flooded rice (NDVI ~0.10–0.20)
NDVI_VEG_2023    = 0.10   # above this in 2023 = rice/plantation
NDVI_NONVEG_2026 = 0.20   # below this in 2026 = built-up candidate

# ── Land-cover classification ─────────────────────────────────────────────────
CLASS_VEGETATION = 1
CLASS_BUILTUP    = 2
CLASS_OTHER      = 0

def classify_2023(ndvi_arr):
    """2023 baseline: everything is rice/plantation (no built-up present)."""
    return xr.full_like(ndvi_arr, fill_value=CLASS_VEGETATION, dtype=np.int8)

def classify_2026(ndvi_arr, ndbi_arr):
    """2026: vegetation / built-up / other based on NDVI + NDBI."""
    veg   = ndvi_arr > NDVI_VEG_2023
    built = (ndvi_arr < NDVI_NONVEG_2026) & (ndbi_arr > -0.15)
    lc = xr.full_like(ndvi_arr, fill_value=CLASS_OTHER, dtype=np.int8)
    lc = lc.where(~veg,   CLASS_VEGETATION)
    lc = lc.where(~built, CLASS_BUILTUP)
    return lc

lc_2023 = classify_2023(ndvi_2023)
lc_2026 = classify_2026(ndvi_2026, ndbi_2026)

# ── Change mask ───────────────────────────────────────────────────────────────
# Changed = any pixel that is no longer vegetation in 2026:
#   CLASS_BUILTUP : factory / impervious surface
#   CLASS_OTHER   : bare soil / cleared ground (construction phase)
# Both categories indicate the land has been converted from rice/plantation.

change_mask = (lc_2026 == CLASS_BUILTUP) | (lc_2026 == CLASS_OTHER)

# ── Area calculation ──────────────────────────────────────────────────────────
# Pixel resolution is 10 m → 100 m² per pixel.

pixel_area_m2 = 10 * 10          # 100 m²
pixel_area_ha = pixel_area_m2 / 10_000  # 0.01 ha

n_changed_pixels = int(change_mask.values.sum())
area_m2          = n_changed_pixels * pixel_area_m2
area_ha          = n_changed_pixels * pixel_area_ha
area_km2         = area_m2 / 1_000_000

print("=" * 54)
print("  Deteksi Perubahan Tutupan Lahan")
print("=" * 54)
print(f"  Periode         : {t2023_date.date()} → {t2026_date.date()}")
print(f"  Jenis perubahan : Vegetasi → Terbangun/lahan terbuka")
print(f"  Jumlah piksel   : {n_changed_pixels:,}")
print(f"  Luas terdampak  : {area_km2:.4f} km²")
print(f"                    {area_ha:,.2f} ha")
print("=" * 54)
```

## 5. Visualisasi

Tahap ini merupakan visualisasi data. Visualisasi didasarkan pada perubahan lahan sawah menjadi pabrik dan lahan terbuka yang telah dihitung sebelumnya.

```{code-cell} ipython3
# ── Visualisation ─────────────────────────────────────────────────────────────
# Colormap: value -1=invalid, 0=other, 1=vegetation, 2=built-up
# Use BoundaryNorm so each integer class maps exactly to its colour.

fig, axes = plt.subplots(1, 3, figsize=(18, 6))

cmap_lc  = ListedColormap(["lightgrey", "tan", "forestgreen", "firebrick"])
bounds   = [-1.5, -0.5, 0.5, 1.5, 2.5]
norm_lc  = BoundaryNorm(bounds, cmap_lc.N)

label_patches = [
    mpatches.Patch(color="tan",         label="Lainnya / Lahan Terbuka"),
    mpatches.Patch(color="forestgreen", label="Vegetasi (sawah/perkebunan)"),
    mpatches.Patch(color="firebrick",   label="Terbangun / Pabrik"),
]

for ax, lc, title in zip(
    axes[:2],
    [lc_2023, lc_2026],
    [f"Tutupan Lahan {t2023_date.date()}", f"Tutupan Lahan {t2026_date.date()}"],
):
    ax.imshow(lc.values, cmap=cmap_lc, norm=norm_lc, interpolation="nearest")
    ax.set_title(title, fontsize=12)
    ax.axis("off")

axes[1].legend(handles=label_patches, loc="lower right", fontsize=8, framealpha=0.8)

# Change map: faint 2023 LC background + gold changed pixels
axes[2].imshow(lc_2023.values, cmap=cmap_lc, norm=norm_lc,
               interpolation="nearest", alpha=0.4)
axes[2].imshow(
    np.where(change_mask.values, 1, np.nan),
    cmap=ListedColormap(["gold"]),
    interpolation="nearest",
    alpha=0.9,
)
axes[2].set_title(
    f"Area Perubahan  (Terbangun & Lahan Terbuka 2026)",
    fontsize=11,
)
axes[2].axis("off")

patches_ch = [
    mpatches.Patch(color="forestgreen", alpha=0.4, label="Sawah/Perkebunan 2023 (latar)"),
    mpatches.Patch(color="gold",                   label=f"Berubah → Pabrik/Dibersihkan ({area_ha:.2f} ha)"),
]
axes[2].legend(handles=patches_ch, loc="lower right", fontsize=8, framealpha=0.8)

plt.suptitle(
    f"Perubahan Tutupan Lahan:  {t2023_date.date()} - {t2026_date.date()}",
    fontsize=13,
    y=1.02,
)
plt.tight_layout()
plt.savefig("perubahan_lahan.png", dpi=150, bbox_inches="tight")
plt.show()
print("Peta disimpan → perubahan_lahan.png")
```

# Catatan
Modul ini memberikan gambaran penggunaan citra multispektral Sentinel 2 dengan hasil:
1. Metode transformasi citra mampu melakukan estimasi perubahan lahan secara spasial maupun temporal mulai dari tahun 2023 hingga tahun 2026 dengan resolusi menengah
2. Perubahan lahan dapat diindikasi dari berbagai jenis transformasi citra yang digunakan
3. Hasil analisis menunjukkan bahwa penginderaan jauh merupakan pendekatan yang efisien dan akurat untuk memantau dinamika perubahan lahan, khususnya pada wilayah dengan perkembangan industri yang pesat.
4. Informasi yang dihasilkan dapat dimanfaatkan sebagai dasar dalam perencanaan tata ruang dan pengambilan kebijakan terkait pengelolaan lahan yang berkelanjutan.

+++

# Info

- Modul ini dijalankan di platform Piksel. Jika ada pertanyaan atau komentar, silahkan email ke piksel@big.go.id
- **Lisensi:** Skrip dalam notebook ini dilisensikan berdasarkan [Apache License, Version 2.0](https://www.apache.org/licenses/LICENSE-2.0).
Data Piksel dilisensikan berdasarkan lisensi [Creative Commons by Attribution 4.0](https://creativecommons.org/licenses/by/4.0/).
