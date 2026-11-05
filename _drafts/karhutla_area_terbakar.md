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

| <h1><b>Identifikasi Area yang Terbakar</b></h1> | ![](files/piksel_logo_small.png) |
|:---------|----------:|
- **Lokasi:** Kawasan Bromo, Prov Jawa Timur
- **Metode:** Penggunaan beberapa citra satelit untuk monitoring karhutla
- **Data:** Sentinel 2

+++

# Pendahuluan
Kebakaran hutan dan lahan (karhutla) dapat menyebabkan perubahan kondisi vegetasi yang terdeteksi melalui citra satelit. Modul ini mendemonstrasikan identifikasi area yang berpotensi terbakar di kawasan Gunung Bromo, Jawa Timur  [🔗](https://maps.app.goo.gl/DnYGMXrB6riAFGkp8), menggunakan data Sentinel-2 Level-2A yang diakses melalui Open Data Cube (ODC) pada platform Piksel. Indeks Normalized Burn Ratio (NBR) dihitung dari kanal NIR dan SWIR2 untuk mengidentifikasi indikasi area terbakar, kemudian nilai NBR di bawah -0,2 digunakan sebagai ambang untuk memetakan area dengan indikasi tingkat keparahan kebakaran tinggi serta menghitung estimasi luasnya.

+++

# Tahapan

Tahapan dalam identifikasi area yang berpotensi terbakar adalah sebagai berikut:
1. Persiapan
2. Memuat data
3. Perhitungan NBR
4. Visualisasi

***

+++

## 1. Persiapan
Tahap persiapan meliputi memuat library dan setting parameter.

### A. Memuat Library

```{code-cell} ipython3
import datacube
import numpy as np
import xarray as xr
import geopandas as gpd
import matplotlib.pyplot as plt

from shapely.geometry import Point
from odc.geo.geom import Geometry
from datetime import datetime
```

### B. Konfigurasi parameter
Berikut adalah parameter yang digunakan untuk konfigurasi modul.

```{code-cell} ipython3
CENTER_LAT = -7.9500
CENTER_LON = 112.9499

RADIUS_DEG = 0.05

BEFORE_DATE = "2026-07-28"
AFTER_DATE = "2026-08-22"
```

## 2. Memuat data
Sebelum memuat data Sentinel 2, maka AOI perlu ditentukan.

```{code-cell} ipython3
center = Point(
    CENTER_LON,
    CENTER_LAT
)
aoi = center.buffer(
    RADIUS_DEG
)
aoi_gdf = gpd.GeoDataFrame(
    {"name": ["Bromo AOI"]},
    geometry=[aoi],
    crs="EPSG:4326"
)
print("AOI:")
print(aoi_gdf)
print("\nAOI bounds:")
print(aoi_gdf.total_bounds)
```

Berikut adalah memuat data Sentinel 2.

```{code-cell} ipython3
dc = datacube.Datacube(
    app="bromo_burn_scar"
)
ds = dc.load(
    product="s2_l2a",
    geopolygon=Geometry(aoi_gdf.geometry.iloc[0], crs=aoi_gdf.crs),
    time=(
        "2026-08-21",
        "2026-08-25"
    ),
    measurements=[
        "red",
        "green",
        "blue",
        "nir",
        "swir22",
        "scl",
    ],
    output_crs="EPSG:32749",
    resolution=(-10, 10),
    group_by="solar_day",
)
print("\nDataset:")
print(ds)
print("\nData yang tersedia:")
for t in ds.time.values:
    print(t)
```

## 3. Perhitungan NBR
Normalized Burn Ratio (NBR) adalah indeks spektral dari citra satelit yang digunakan untuk mendeteksi dan memetakan area bekas kebakaran hutan dan lahan (burned area). NBR memanfaatkan perbedaan respons spektral vegetasi pada kanal Near-Infrared (NIR) dan Shortwave Infrared (SWIR).
NBR menggunakan formula:
$$NBR = \frac{(NIR - SWIR22)}{(NIR + SWIR22)}$$
dimana:
- NIR = Near Infrared (Band 8)
- SWIR = Short Wave Infrared (Band 12)

Interpretasi nilai NBR terlihat dalam tabel berikut. Nilai tersebut merupakan interpretasi umum; kondisi tanah, kelembapan, jenis vegetasi, dan bayangan dapat memengaruhi hasil.

| Nilai NBR        | Interpretasi umum                                                                      |
| ---------------- | -------------------------------------------------------------------------------------- |
| Mendekati +1     | Vegetasi sehat dan rapat                                                               |
| Mendekati 0      | Permukaan tanah atau tutupan lahan campuran                                            |
| Bernilai negatif | Area dengan respons SWIR lebih tinggi, seperti tanah terbuka kering atau area terbakar |


```{code-cell} ipython3
nbr = (ds.nir.astype(float) - ds.swir22.astype(float)) / (
    ds.nir.astype(float) + ds.swir22.astype(float)
)
nbr_aug22 = nbr.isel(time=0)
scl_aug22 = ds.scl.isel(time=0)
print(f"\nNBR for {ds.time.values[0]}:")
print(nbr_aug22)
```

Batas nilai NBR biasanya seperti dalam tabel berikut.
| Nilai NBR         | Interpretasi umum                       |
| ----------------- | ----------------------------------------|
| NBR > 0.1         | Tidak terbakar atau terbakar sedikit    |
| 0.1 > NBR > -0.1  | Terbakar sedikit sampai sedang          |
| -0.1 > NBR > -0.2 | Terbakar sedang sampai berat            |
| NBR < -0.2        | Terbakar berat                          |

Berikut perhitungan luas area yang terbakar.

```{code-cell} ipython3
high_burn = nbr_aug22 < -0.20
n_pixels = int(high_burn.sum().values)
pixel_size = 10  # meters karena menggunakan SWIR
pixel_area_m2 = pixel_size * pixel_size

area_ha = n_pixels * pixel_area_m2 / 10_000
area_km2 = n_pixels * pixel_area_m2 / 1_000_000

print(f"Jumlah piksel terbakar berat (NBR < -0.2): {n_pixels:,}")
print(f"Luas terbakar berat: {area_ha:,.2f} hektar")
print(f"Luas terbakar berat: {area_km2:,.3f} km²")
```

## 4. Visualisasi
Berikut adalah plot dari citra Sentinel, perhitungan NBR dan NBR < -0.2. 

```{code-cell} ipython3
date = ds.time.values[0].astype("datetime64[D]")
fig, axes = plt.subplots(1, 3, figsize=(18, 6))
# Get extent from data coordinates
extent = [
    float(ds.x.min()), float(ds.x.max()),
    float(ds.y.min()), float(ds.y.max())
]
# Plot 1: RGB Imagery
rgb_data = np.stack([
    ds.red.isel(time=0).values,
    ds.green.isel(time=0).values,
    ds.blue.isel(time=0).values
], axis=-1)

rgb_data = np.clip(rgb_data.astype(float) / 3000, 0, 1)

axes[0].imshow(
    rgb_data, extent=extent, origin="upper", aspect="equal"
)
axes[0].set_title(f"RGB Imagery - {date}")
axes[0].set_xlabel("Easting (m)")
axes[0].set_ylabel("Northing (m)")

# Plot 2: NBR
im_nbr = axes[1].imshow(
    nbr_aug22.values,
    cmap="RdYlGn",
    vmin=-1,
    vmax=1,
    extent=extent,
    origin="upper",
    aspect="equal"
)
axes[1].set_title(f"NBR (Normalized Burn Ratio) - {date}")
axes[1].set_xlabel("Easting (m)")
axes[1].set_ylabel("Northing (m)")
plt.colorbar(im_nbr, ax=axes[1], label="NBR")

# Plot 3: High Burn Severity
im_high = axes[2].imshow(
    high_burn.values,
    cmap="Reds",
    extent=extent,
    origin="upper",
    aspect="equal"
)
axes[2].set_title(f"High Burn Severity (NBR < -0.2) - {date}")
axes[2].set_xlabel("Easting (m)")
axes[2].set_ylabel("Northing (m)")
plt.colorbar(im_high, ax=axes[2], label="High Severity")

plt.tight_layout()
plt.savefig("nbr_burn_analysis.png", dpi=150, bbox_inches="tight")
print("\nVisualization saved as 'nbr_burn_analysis.png'")
plt.show()
```

# Catatan
Hasil analisis menunjukkan distribusi spasial nilai NBR dan area yang memenuhi ambang NBR < -0,2 pada citra tanggal 22 Agustus 2026. Luas area dihitung berdasarkan jumlah piksel pada grid beresolusi 10 meter. Hasil ini merupakan estimasi awal area yang berpotensi terbakar, bukan konfirmasi definitif area terbakar atau tingkat keparahan kebakaran. Validasi lebih lanjut diperlukan menggunakan citra sebelum dan sesudah kebakaran, data hotspot, serta informasi lapangan.

+++

# Info

- Modul ini dijalankan di platform Piksel. Jika ada pertanyaan atau komentar, silahkan email ke piksel@big.go.id
- **Lisensi:** Skrip dalam notebook ini dilisensikan berdasarkan [Apache License, Version 2.0](https://www.apache.org/licenses/LICENSE-2.0). 
Data Piksel dilisensikan berdasarkan lisensi [Creative Commons by Attribution 4.0](https://creativecommons.org/licenses/by/4.0/).
