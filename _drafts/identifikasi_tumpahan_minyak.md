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

| <h1><b>Pendeteksian Tumpahan Minyak</b></h1> | ![](files/piksel_logo_small.png) |
|:---------|----------:|
- **Data:** Sentinel-1, Sentinel-2
- **Lokasi:** Perairan Kabupaten Karawang, Provinsi Jawa Barat
- **Metode:** *Manual Global Threshold* dan Klasifikasi *Support Vector Machine* (SVM)

+++

# Pendahuluan
Kecelakaan kerja pertambangan minyak dan gas di laut terkadang menyebabkan adanya tumpahan minyak di laut. *Notebook* ini ditujukan untuk mendeteksi adanya tumpahan minyak yang terjadi di laut menggunakan intensitas yang dimiliki citra SAR Sentinel-1, dengan bantuan citra Sentinel-2 (kanal *Scene Classification Layer*/SCL) untuk melakukan *masking* wilayah laut.

+++

# Tahapan
Tahapan dalam pendeteksian tumpahan minyak adalah sebagai berikut:
1. Persiapan
2. Penentuan wilayah
3. Mengunduh data Sentinel-1
4. Mengunduh data Sentinel-2
5. *Masking* Wilayah Laut
6. *Speckle Noise Filtering*
7. *Thresholding*
8. Klasifikasi
9. Uji akurasi
10. *Post-processing*
11. Perhitungan luas terdampak

+++

## 1. Persiapan

Tahapan persiapan di mulai dengan melakukan *import library* yang dibutuhkan selama proses pengolahan data.

```{code-cell} ipython3
!pip install imbalanced-learn
```

```{code-cell} ipython3
# 1. Scientific Computing: untuk perhitungan numerik dan pengolahan data multidimensi.
import numpy as np
import xarray as xr
import pandas as pd

# 2. Geospatial Processing: untuk pengolahan data raster, vektor, dan geometri spasial.
import rasterio.enums
import rioxarray
import geopandas as gpd
from shapely.geometry import box, mapping, Point

# 3. Image & Spatial Analysis: untuk filtering, segmentasi, dan analisis pola spasial/citra.
from scipy import ndimage
from scipy.ndimage import uniform_filter

# 4. Machine Learning: untuk klasifikasi, preprocessing, balancing data, dan evaluasi model.
from imblearn.over_sampling import SMOTE
from sklearn.model_selection import train_test_split
from sklearn.preprocessing import StandardScaler
from sklearn.svm import SVC
from sklearn.metrics import confusion_matrix, ConfusionMatrixDisplay

# 5. STAC & Satellite Data: untuk mencari, mengakses, dan memuat data citra satelit melalui STAC.
from pystac_client import Client
from planetary_computer import sign_url
from odc.stac import load

# 6. Visualization: untuk membuat grafik dan menampilkan hasil analisis.
import matplotlib.pyplot as plt
from matplotlib.colors import ListedColormap, BoundaryNorm
from IPython.display import display, HTML, FileLink

# 7. Interactive Mapping: untuk menyediakan komponen peta interaktif dalam notebook.
from ipyleaflet import basemaps

# 8. File & Web Utilities: untuk pengelolaan file, gambar, encoding, ID unik, dan akses API/web.
import base64
from io import BytesIO
import uuid
from PIL import Image
```

## 2. Penentuan wilayah
Area kajian berada di perairan Kabupaten Karawang, Jawa Barat. Penentuan area kajian menggunakan koordinat untuk membentuk *bounding box*.

```{code-cell} ipython3
# Area Studi
aoi = {
    'easting': (765123.555482, 794955.385979),
    'northing': (9314775.39002, 9340836.90048),
    'crs': 'EPSG:32748'}
min_x, max_x = aoi['easting']
min_y, max_y = aoi['northing']
batas_aoi = box(min_x, min_y, max_x, max_y)

#Tampilan Batas Area Studi
aoi_gdf = gpd.GeoDataFrame(
    {"name": ["Area Studi Kabupaten Karawang"]},
    geometry=[batas_aoi],
    crs=aoi["crs"])

# UTM 48S ke WGS 84
aoi_gdf_wgs84 = aoi_gdf.to_crs("EPSG:4326")
aoi_search = mapping(aoi_gdf_wgs84.geometry.iloc[0])

print("Bounds AOI WGS84:")
print(aoi_gdf_wgs84.total_bounds)

aoi_gdf.explore(tiles=basemaps.Esri.WorldImagery)
```

## 3. Mengunduh data Sentinel-1
Citra SAR Sentinel-1 diambil dari *Catalog* Planetary Computer dengan parameter-parameter yang telah disesuaikan berdasarkan tanggal kejadian tumpahan minyak dan mode akuisisi citra SAR.

```{code-cell} ipython3
# Microsoft Planetary Computer STAC Catalog URL
catalog = "https://planetarycomputer.microsoft.com/api/stac/v1"
client = Client.open(catalog)

datetime = "2019-07-15/2019-07-20"
items = client.search(
    collections=["sentinel-1-rtc"],
    intersects=aoi_search,
    datetime=datetime,
).item_collection()

print(f"Found {len(items)} items")
for i, item in enumerate(items):
    print(i, item.datetime)

data = load(
    items,
    geopolygon=aoi_search,
    measurements=["vv"],
    groupby="id",
    patch_url=sign_url)
data
```

Setelah data citra ditemukan, penting untuk mengetahui metadata citra terutama arah dan nomor orbit citra agar saat diperlukan *mosaic* intensitas citra tidak berbeda jauh.

```{code-cell} ipython3
for i, item in enumerate(items):
    print("Index:", i)
    print("Tanggal:", item.datetime)
    print("ID:", item.id)
    print("Orbit state:", item.properties.get("sat:orbit_state"))
    print("Relative orbit:", item.properties.get("sat:relative_orbit"))
    print("-" * 70)
```

Menampilkan data Sentinel-1 pada area studi.

```{code-cell} ipython3
vv_raw = data["vv"]
vv_valid = vv_raw.where((vv_raw > 0) & np.isfinite(vv_raw))
vv_db = 10 * np.log10(vv_valid.isel(time=0))

plt.figure(figsize=(10, 8))
vv_db.plot.imshow(cmap="gray", vmin=-25, vmax=0, robust=True, add_colorbar=True)
plt.title("Citra Sentinel-1")
plt.xlabel("Easting")
plt.ylabel("Northing")
plt.show()
```

Inisialisasi data_merge dari citra Sentinel-1 (dipakai untuk kasus satu scene).

```{code-cell} ipython3
data_merge = vv_valid.isel(time=0).to_dataset(name="vv")
data_merge["vv_db"] = vv_db
```

Apabila ditemukan dua scene citra untuk area kajian maka perlu dilakukan *mosaic* untuk menggabungkan citra tersebut.
```
vv_raw = data["vv"]
vv_valid = vv_raw.where((vv_raw > 0) & np.isfinite(vv_raw))

vv_merge = vv_valid.isel(time=0).combine_first(vv_valid.isel(time=1))
data_merge = vv_merge.to_dataset(name="vv")
data_merge["vv_db"] = 10 * np.log10(data_merge["vv"])

plt.figure(figsize=(10, 8))
data_merge["vv_db"].plot.imshow(
    cmap="gray",
    vmin=-25,
    vmax=0,
    robust=True,
    add_colorbar=True)

plt.title("Mosaic Citra Sentinel-1")
plt.xlabel("Easting")
plt.ylabel("Northing")
plt.show()
```

+++

## 4. Mengunduh data Sentinel-2
Data Sentinel-2 digunakan untuk masking wilayah laut

```{code-cell} ipython3
# Pencarian Sentinel-2 pada rentang sempit lalu diperlebar 
# bila tidak ditemukan data dengan tutupan awan rendah.
s2_datetime_candidates = [
    (datetime, 20),
    ("2019-06-15/2019-08-15", 40),
    ("2019-01-01/2019-12-31", 60),
]

s2_item = None
for s2_datetime, max_cloud in s2_datetime_candidates:
    s2_items = client.search(
        collections=["sentinel-2-l2a"],
        intersects=aoi_search,
        datetime=s2_datetime,
        query={"eo:cloud_cover": {"lt": max_cloud}},
    ).item_collection()

    if len(s2_items) > 0:
        # Pilih scene dengan tutupan awan paling rendah
        s2_item = min(s2_items, key=lambda it: it.properties.get("eo:cloud_cover", 100))
        print(f"Rentang '{s2_datetime}' (awan < {max_cloud}%): ditemukan {len(s2_items)} scene")
        break

if s2_item is None:
    raise ValueError("Tidak ditemukan scene Sentinel-2 dengan tutupan awan yang memadai untuk area kajian.")

print("Scene Sentinel-2 terpilih:", s2_item.id)
print("Tanggal:", s2_item.datetime)
print("Cloud cover:", s2_item.properties.get("eo:cloud_cover"), "%")

s2_data = load(
    [s2_item],
    geopolygon=aoi_search,
    measurements=["SCL"],
    resolution=10,
    output_crs=aoi["crs"],
    patch_url=sign_url)

scl = s2_data["SCL"].isel(time=0)
scl
```

## 5. *Masking* wilayah laut
Fokus area kajian berada di wilayah laut sehingga perlu dilakukan *masking* untuk menghilangkan wilayah darat pada sra studi. Data Sentinel-2 digunakan untuk *masking* wilayah laut.

Berikut adalah visualisasi hasil klasifikasi SCL Sentinel-2 sebagai peta kategorikal berwarna per kelas untuk memastikan kelas "Water" terbaca dengan baik sebelum dipakai sebagai dasar masking wilayah laut.

```{code-cell} ipython3
# Kelas SCL Sentinel-2 L2A (Baseline ESA):
# 0 No Data, 1 Saturated/Defective, 2 Dark Area, 3 Cloud Shadow,
# 4 Vegetation, 5 Bare Soil, 6 Water, 7 Cloud Low Prob,
# 8 Cloud Medium Prob, 9 Cloud High Prob, 10 Thin Cirrus, 11 Snow/Ice
scl_labels = {
    0: "No Data", 1: "Saturated/Defective", 2: "Dark Area", 3: "Cloud Shadow",
    4: "Vegetation", 5: "Bare Soil", 6: "Water", 7: "Cloud Low Prob",
    8: "Cloud Medium Prob", 9: "Cloud High Prob", 10: "Thin Cirrus", 11: "Snow/Ice"}
scl_colors = [
    "#000000", "#ff0000", "#404040", "#833c00",
    "#00a600", "#ffe65a", "#0000ff", "#bbbbbb",
    "#7f7f7f", "#ffffff", "#66ccff", "#ff80ff"]

cmap_scl = ListedColormap(scl_colors)
norm_scl = BoundaryNorm(np.arange(-0.5, 12.5, 1), cmap_scl.N)

fig, ax = plt.subplots(figsize=(8, 7))
img = scl.plot.imshow(ax=ax, cmap=cmap_scl, norm=norm_scl, add_colorbar=False)
cbar = fig.colorbar(img, ax=ax, ticks=list(scl_labels.keys()))
cbar.ax.set_yticklabels(list(scl_labels.values()))
ax.set_title(f"Sentinel-2 SCL — {s2_item.id}")
ax.set_xlabel("Easting")
ax.set_ylabel("Northing")
plt.tight_layout()
plt.show()
```

*Masking* wilayah laut dibuat dari kelas *Water* (nilai 6) pada kanal SCL Sentinel-2. Piksel SCL kemudian diresample ke grid citra Sentinel-1 (VV) agar kedua data memiliki resolusi dan posisi piksel yang sama. Sebagai tambahan, dilakukan erosi (*erosion*) pada mask air sejauh 15 meter ke arah laut untuk memastikan wilayah darat/piksel campuran di garis pantai terpotong sempurna.

```{code-cell} ipython3
# Kelas "Water" pada SCL Sentinel-2 L2A
SCL_WATER_CLASS = 6
mask_air_scl_bool = (scl == SCL_WATER_CLASS)

# Resample mask SCL (grid Sentinel-2) ke grid citra Sentinel-1 (vv_db)
# menggunakan reindex nearest-neighbor karena mask bertipe boolean/kategorikal.
mask_air_scl = mask_air_scl_bool.astype("uint8").rio.write_crs(aoi["crs"])
mask_air_regrid = mask_air_scl.rio.reproject_match(
    vv_db.rio.write_crs(aoi["crs"]),
    resampling=rasterio.enums.Resampling.nearest)

buffer_pesisir_m = 15
pixel_size_x = abs(float(vv_db.x[1] - vv_db.x[0]))
pixel_size_y = abs(float(vv_db.y[1] - vv_db.y[0]))
iterasi_erosi = max(1, int(round(buffer_pesisir_m / min(pixel_size_x, pixel_size_y))))

# Mask laut TANPA buffer pesisir (langsung dari SCL water)
mask_laut_s2_tanpa_buffer_bool = mask_air_regrid.values.astype(bool)

mask_laut_s2_tanpa_buffer = xr.DataArray(
    mask_laut_s2_tanpa_buffer_bool,
    coords={
        "y": vv_db.y,
        "x": vv_db.x},
    dims=("y", "x"),
    name="mask_laut_s2_tanpa_buffer")
citra_masking_tanpa_buffer = vv_db.where(mask_laut_s2_tanpa_buffer)

# Mask laut DENGAN buffer pesisir (erosi mask air ke arah laut)
mask_laut_s2_bool = ndimage.binary_erosion(
    mask_laut_s2_tanpa_buffer_bool,
    iterations=iterasi_erosi)

mask_laut_s2 = xr.DataArray(
    mask_laut_s2_bool,
    coords={
        "y": vv_db.y,
        "x": vv_db.x},
    dims=("y", "x"),
    name="mask_laut_s2")

# Simpan mask ke data_merge agar bisa dipakai pada tahap Lee filter dan klasifikasi
data_merge["mask_laut_s2"] = mask_laut_s2

citra_masking = vv_db.where(mask_laut_s2)

# Simpan citra laut dB (sebelum Lee filter) ke data_merge untuk visualisasi perbandingan
data_merge["laut_s2"] = citra_masking

print("Jumlah piksel laut tanpa buffer:", int(mask_laut_s2_tanpa_buffer.sum().item()))
print("Jumlah piksel laut dengan buffer:", int(mask_laut_s2.sum().item()))
```

Hasil *masking* wilayah laut berdasarkan kelas *Water* SCL Sentinel-2, tanpa dan dengan *buffer* pesisir sebesar 15 meter.

```{code-cell} ipython3
cmap = plt.get_cmap("gray").copy()
cmap.set_bad("white")
fig, ax = plt.subplots(1, 2, figsize=(12, 6))

# Plot mask laut tanpa buffer
citra_masking_tanpa_buffer.plot.imshow(
    ax=ax[0],
    cmap=cmap,
    vmin=-25,
    vmax=0,
    robust=True,
    add_colorbar=True,
    cbar_kwargs={"label": ""})
ax[0].set_title("Mask Laut (SCL Sentinel-2)")
ax[0].set_xlabel("x [metre]")
ax[0].set_ylabel("y [metre]")

# Plot mask laut dengan buffer pesisir
citra_masking.plot.imshow(
    ax=ax[1],
    cmap=cmap,
    vmin=-25,
    vmax=0,
    robust=True,
    add_colorbar=True,
    cbar_kwargs={"label": ""})
ax[1].set_title(f"Mask Laut Buffer {buffer_pesisir_m} meter")
ax[1].set_xlabel("x [metre]")
ax[1].set_ylabel("y [metre]")

plt.tight_layout()
plt.show()
```

Berikut plot dari dua histogram untuk membandingkan distribusi nilai backscatter (dB) sebelum dan sesudah masking wilayah laut: panel kiri menampilkan histogram citra VV mentah (vv_db), panel kanan menampilkan histogram citra yang sudah dimasking ke wilayah laut saja (citra_masking), keduanya dengan piksel non-finite dibuang terlebih dahulu.

```{code-cell} ipython3
fig, ax = plt.subplots(1, 2, figsize=(14, 5))

# Histogram Raw Citra
raw_citra = vv_db.values
raw_citra = raw_citra[np.isfinite(raw_citra)]
ax[0].hist(raw_citra, bins=100, range=(-30, 5), color="gray", alpha=0.7, edgecolor="black")
ax[0].set_title("Histogram Raw Citra")
ax[0].set_xlabel("Nilai Backscatter (dB)")
ax[0].set_ylabel("Frekuensi Piksel")
ax[0].grid(axis="y", alpha=0.5)

# Histogram masking laut
piksel_laut = citra_masking.values
piksel_laut = piksel_laut[np.isfinite(piksel_laut)]
ax[1].hist(piksel_laut, bins=100, range=(-30, 5), color="gray", alpha=0.7, edgecolor="black")
ax[1].set_title("Histogram Citra Mask Laut")
ax[1].set_xlabel("Nilai Backscatter (dB)")
ax[1].set_ylabel("Frekuensi Piksel")
ax[1].grid(axis="y", alpha=0.5)

plt.tight_layout()
plt.show()

# Nilai Histogram Raw Citra
counts_rc, bins_rc = np.histogram(raw_citra, bins=100)
idx_puncak_rc = np.argmax(counts_rc)
bin_kiri_rc = bins_rc[idx_puncak_rc]
bin_kanan_rc = bins_rc[idx_puncak_rc + 1]
db_puncak_rc = (bin_kiri_rc + bin_kanan_rc) / 2
frekuensi_puncak_rc = counts_rc[idx_puncak_rc]

print("Nilai dB Puncak Histogram Raw Citra:")
print(f"Rentang bin : {bin_kiri_rc:.3f} sampai {bin_kanan_rc:.3f} dB")
print(f"Titik tengah: {db_puncak_rc:.3f} dB")
print(f"Frekuensi  : {frekuensi_puncak_rc} piksel")

# Nilai Histogram Masking Laut
counts, bins = np.histogram(piksel_laut, bins=100)
idx_puncak = np.argmax(counts)
bin_kiri = bins[idx_puncak]
bin_kanan = bins[idx_puncak + 1]
db_puncak = (bin_kiri + bin_kanan) / 2
frekuensi_puncak = counts[idx_puncak]

print("Nilai dB Puncak Histogram Citra Mask Laut:")
print(f"Rentang bin : {bin_kiri:.3f} sampai {bin_kanan:.3f} dB")
print(f"Titik tengah: {db_puncak:.3f} dB")
print(f"Frekuensi  : {frekuensi_puncak} piksel")
```

## 6. Speckle Noise Filtering

Citra SAR memiliki efek granular (*speckle*) yang berbentuk seperti *salt and pepper* akibat dari adanya *scatter* pada citra SAR. Oleh karena itu, *speckle noise filtering* dilakukan untuk menghilangkan efek *noise* tersebut tanpa menghilangkan informasi citra. Metode *speckle noise filtering* yang digunakan adalah metode Lee Filter dengan *window* berukuran 5x5 piksel yang dinilai stabil untuk citra SAR. 

Metode ini didasarkan pada model derau multiplikatif ($z = x \cdot v$) dan memanfaatkan rerata lokal serta varians lokal piksel dalam jendela pemindaian untuk mengestimasi nilai piksel sesungguhnya.

Estimasi piksel hasil penapisan akhir dirumuskan sebagai:
$$\hat{x} = \bar{x} + b(z - \bar{x})$$

Keterangan:
* $\hat{x}$ : Nilai piksel akhir hasil penapisan.
* $\bar{x}$ : Rerata lokal piksel dalam jendela $5 \times 5$.
* $z$ : Nilai piksel citra SAR yang teramati.
* $b$ : Faktor pembobot Lee filter ($b = \frac{\text{var}(x)}{\text{var}(z)}$) yang dihitung menggunakan parameter ENL (*Equivalent Number of Looks*).

Berikut adalah perhitungan Lee filtering

```{code-cell} ipython3
def lee_filter_2d(img, size=5, enl=4.4):
    img = np.asarray(img, dtype=np.float64)

    # Mask nilai valid
    valid = np.isfinite(img)
    if not valid.any():
        return img.astype(np.float32)

    # Ganti nilai NaN dengan 0
    img_zero = np.where(valid, img, 0)
    valid_f = valid.astype(np.float64)

    # Jumlah piksel valid dalam window
    valid_count = uniform_filter(valid_f, size=size, mode="nearest")
    valid_count = np.maximum(valid_count, 1e-6)

    # Local mean (I_bar)
    local_mean = uniform_filter(img_zero, size=size, mode="nearest") / valid_count

    # Local mean of squares
    local_mean_sq = uniform_filter(img_zero ** 2, size=size, mode="nearest") / valid_count

    # Local variance (var_I)
    local_var = local_mean_sq - local_mean ** 2
    local_var = np.maximum(local_var, 0)

    # --- rumus Lee Filtering ---
    # Koefisien variasi sensor (noise), dari ENL 
    Cu = 1.0 / np.sqrt(enl)
    Cu2 = Cu ** 2

    # Koefisien variasi lokal citra (signal + noise)
    with np.errstate(divide="ignore", invalid="ignore"):
        Ci2 = local_var / (local_mean ** 2)
        Ci2 = np.where(local_mean != 0, Ci2, 0)

    # Bobot Lee filter (W)
    with np.errstate(divide="ignore", invalid="ignore"):
        weight = 1.0 - (Cu2 / Ci2)
        weight = np.where(Ci2 != 0, weight, 0)
    weight = np.clip(weight, 0.0, 1.0)

    # Hasil Lee filter
    filtered = local_mean + weight * (img - local_mean)

    # Balikkan area tidak valid jadi NaN
    filtered = filtered.astype(np.float32)
    filtered[~valid] = np.nan
    return filtered

# Menyiapkan data linier
data_merge["vv_clean"] = data_merge["vv"].where(np.isfinite(data_merge["vv"]) & (data_merge["vv"] > 0))

vv_laut_linear = data_merge["vv_clean"].where(data_merge["mask_laut_s2"])
data_merge["vv_lee"] = xr.apply_ufunc(
    lee_filter_2d,
    vv_laut_linear,
    input_core_dims=[["y", "x"]],
    output_core_dims=[["y", "x"]],
    kwargs={"size": 5, "enl": 4.9},
    output_dtypes=[np.float32],
    vectorize=True)
data_merge["vv_lee_db"] = xr.where(data_merge["vv_lee"] > 0, 10 * np.log10(data_merge["vv_lee"]), np.nan)
```

Berikut adalah visualisasi hasil Lee Filter yang menampilkan perbandingan antara citra yang belum dilakukan *filtering* dan citra yang sudah dilakukan *filtering* sehingga tampak perbedaannya. 

```{code-cell} ipython3
cmap = plt.get_cmap("gray").copy()
cmap.set_bad("white")
fig, ax = plt.subplots(1, 2, figsize=(14, 7))

# Sebelum Lee filter: pakai citra laut dB yang sudah ada
data_merge["laut_s2"].squeeze(drop=True).plot.imshow(
    ax=ax[0],
    cmap=cmap,
    vmin=-25,
    vmax=0,
    robust=True,
    add_colorbar=True,
    cbar_kwargs={"label": ""})
ax[0].set_title("Citra Sebelum Filtering")
ax[0].set_xlabel("Easting")
ax[0].set_ylabel("Northing")

# Sesudah Lee filter
data_merge["vv_lee_db"].squeeze(drop=True).plot.imshow(
    ax=ax[1],
    cmap=cmap,
    vmin=-25,
    vmax=0,
    robust=True,
    add_colorbar=True,
    cbar_kwargs={"label": ""})
ax[1].set_title("Citra Sesudah Filtering")
ax[1].set_xlabel("Easting")
ax[1].set_ylabel("Northing")

plt.tight_layout()
plt.show()
```

Berikut adalah histogram dari hasil Lee filtering

```{code-cell} ipython3
fig, ax = plt.subplots(figsize=(8, 6))

piksel_lee = data_merge["vv_lee_db"].values
piksel_lee = piksel_lee[np.isfinite(piksel_lee)]

ax.hist(piksel_lee, bins=100, range=(-35, 0), color="red", alpha=0.7, edgecolor="black")
ax.set_title("Histogram Citra Hasil Lee Filtering")
ax.set_xlabel("Nilai Backscatter (dB)")
ax.set_ylabel("Frekuensi Piksel")
ax.grid(axis="y", alpha=0.5)

plt.tight_layout()
plt.show()

# Perhitungan Statistik Hasil Lee Filtering
counts, bins = np.histogram(piksel_lee, bins=100, range=(-35, 0))
idx_puncak = np.argmax(counts)
bin_kiri = bins[idx_puncak]
bin_kanan = bins[idx_puncak + 1]
db_puncak = (bin_kiri + bin_kanan) / 2
frekuensi_puncak = counts[idx_puncak]
min_lee = np.min(piksel_lee)
max_lee = np.max(piksel_lee)

print("Nilai dB puncak histogram:")
print(f"Rentang bin : {bin_kiri:.3f} sampai {bin_kanan:.3f} dB")
print(f"Titik tengah: {db_puncak:.3f} dB")
print(f"Frekuensi   : {frekuensi_puncak} piksel")
print("Nilai dB:")
print(f"Nilai minimum : {min_lee:.3f} dB")
print(f"Nilai maksimum : {max_lee:.3f} dB")
```

## 7. *Thresholding*
*Thresholding* dilakukan untuk memisahkan antara tumpahan minyak dengan latar belakang perairan laut melalui nilai ambang batas yang ditentukan secara manual (*Manual Global Thresholding*) disesuaikan dengan kondisi intensitas citra.
Secara matematis, proses *thresholding* dinyatakan sebagai:

$$g(x, y) = \begin{cases} 1, & \text{jika } f(x, y) < T \\ 0, & \text{jika } f(x, y) \ge T \end{cases}$$

Keterangan:
* $f(x, y)$ : Nilai intensitas citra masukan pada koordinat $(x, y)$
* $g(x, y)$ : Nilai piksel citra keluaran biner
* $T$ : Nilai ambang (*threshold*) yang ditentukan

```{code-cell} ipython3
nilai_threshold = -21
vv_manual = data_merge["vv_lee_db"].squeeze(drop=True)

# Membuat mask biner:
oilspill_binary = (
    vv_manual < nilai_threshold).where(
    np.isfinite(vv_manual), 0).astype("uint8")

# Filter Threshold
oilspill_clean_arr = (
    uniform_filter(
        oilspill_binary.values.astype("float32"), size=5,
        mode="nearest") >= 0.5).astype("uint8")

oilspill_clean = xr.DataArray(
    oilspill_clean_arr,
    coords=vv_manual.coords,
    dims=vv_manual.dims,
    name="oilspill_clean")

oilspill_masked = oilspill_clean.where(oilspill_clean == 1)

# Menyimpan hasil ke dalam data_clip
data_merge["oilspill_binary"] = oilspill_binary
data_merge["oilspill_clean"] = oilspill_clean
data_merge["oilspill_masked"] = oilspill_masked
data_merge["oilspill_manual_db"] = vv_manual.where(oilspill_clean == 1)

# Ringkasan hasil
jumlah_piksel_valid = int(np.isfinite(vv_manual.values).sum())
jumlah_kandidat_oil = int(oilspill_clean.sum().item())
persentase_kandidat_oil = (jumlah_kandidat_oil / jumlah_piksel_valid) * 100
print(f"Manual threshold       : {nilai_threshold:.2f} dB")
print(f"Jumlah piksel valid    : {jumlah_piksel_valid}")
print(f"Jumlah kandidat oil    : {jumlah_kandidat_oil}")
print(f"Persentase kandidat    : {persentase_kandidat_oil:.2f}%")

# Histogram
nilai_histogram = vv_manual.values.ravel()
nilai_histogram = nilai_histogram[np.isfinite(nilai_histogram)]
plt.figure(figsize=(8, 6))
plt.hist(nilai_histogram, bins=100, range=(-30, 18), color="red", alpha=0.75, edgecolor="black")

# Garis Threshold 
plt.axvline(
    nilai_threshold,
    color="blue",
    linestyle="--",
    linewidth=1.5,
    label=(
        f"Nilai Threshold = "
        f"{nilai_threshold:.2f} dB"))

plt.axvspan(
    nilai_histogram.min(),
    nilai_threshold,
    color="blue",
    alpha=0.15,
    label="Kandidat oil spill")

plt.title("Histogram Manual Global Threshold")
plt.xlabel("Backscatter Lee Filter (dB)")
plt.ylabel("Jumlah Piksel")
plt.legend()
plt.grid(alpha=0.3)
plt.tight_layout()
plt.show()
```

Visualisasi Hasil *Thresholding*

```{code-cell} ipython3
fig, ax = plt.subplots(figsize=(8, 7))

vv_manual.plot.imshow(ax=ax, cmap=cmap, vmin=-25, vmax=0, robust=True, add_colorbar=True, cbar_kwargs={"label": ""})
oilspill_masked.plot.imshow(ax=ax, cmap="Reds", alpha=1, add_colorbar=False)
ax.set_title("Hasil Thresholding")
ax.set_xlabel("Easting")
ax.set_ylabel("Northing")

plt.tight_layout()
plt.show()
```

## 8. Klasifikasi
Klasifikasi yang digunakan yaitu *Supervised Classification* dengan algoritma *Support Vector Machine* (SVM) yang berbasis *Machine Learning* (ML). Algoritma SVM akan dikombinasikan dengan teknik *Synthetic Minority Over-sampling Technique* (SMOTE) untuk menyeimbangkan jumlah data *training* sehingga meminimalkan terjadinya *overfitting* pada hasil klasifikasi

+++

### A. Pembuatan Data Sampel
Pembuatan data sampel dilakukan untuk dua kelas, yaitu kelas minyak dan kelas laut. Pemilihan data sampel mengacu pada hasil citra *thresholding* untuk memudahkan interpretasi, namun nilai *backscatter* tetap menggunakan hasil Lee Filter. Hal ini ditujukan agar model yang dijalankan mengklasifikasikan dengan baik tidak berdasarkan hasil biner *thresholding*.

+++

Membuat citra untuk pembuatan data sampel

```{code-cell} ipython3
def buat_gambar_sampling(citra_da, mask_da, vmin=-25, vmax=0, alpha=0.45, max_size=1600):
    citra_da = citra_da.squeeze(drop=True)
    mask_da = mask_da.squeeze(drop=True)

    citra_arr = citra_da.values.astype("float32")
    mask_arr = mask_da.values

    if citra_arr.ndim != 2:
        raise ValueError("citra_da harus 2D, cek hasil squeeze/drop time.")
    if citra_da.y.values[0] < citra_da.y.values[-1]:
        citra_arr = np.flipud(citra_arr)
        mask_arr = np.flipud(mask_arr)

    valid = np.isfinite(citra_arr)

    gray = (citra_arr - vmin) / (vmax - vmin)
    gray = np.clip(gray, 0, 1)
    gray[~valid] = 1

    rgb = np.dstack([gray, gray, gray])

    merah = mask_arr == 1
    rgb[merah, 0] = (1 - alpha) * rgb[merah, 0] + alpha
    rgb[merah, 1] = (1 - alpha) * rgb[merah, 1]
    rgb[merah, 2] = (1 - alpha) * rgb[merah, 2]

    img = Image.fromarray((rgb * 255).astype("uint8"))
    w, h = img.size

    scale = min(max_size / max(w, h), 1.0)
    if scale < 1:
        img = img.resize((int(w * scale), int(h * scale)), Image.Resampling.LANCZOS)
    buf = BytesIO()
    img.save(buf, format="PNG")
    img_base64 = base64.b64encode(buf.getvalue()).decode("utf-8")

    extent = {
        "xmin": float(citra_da.x.values.min()),
        "xmax": float(citra_da.x.values.max()),
        "ymin": float(citra_da.y.values.min()),
        "ymax": float(citra_da.y.values.max())}
    return img_base64, extent

citra_filter = data_merge["vv_lee_db"].squeeze(drop=True)
mask_threshold = data_merge["oilspill_clean"].squeeze(drop=True)
img_base64, extent_sampling = buat_gambar_sampling(citra_filter, mask_threshold, vmin=-25, vmax=0, alpha=0.45)
```

Membuat tampilan *point* untuk mengambil data sampel pada citra

```{code-cell} ipython3
def tampilkan_picker_utm(img_base64, extent, nama_var, judul, warna="red"):
    uid = "picker_" + uuid.uuid4().hex[:8]

    xmin = extent["xmin"]
    xmax = extent["xmax"]
    ymin = extent["ymin"]
    ymax = extent["ymax"]

    kode = f"""
    <div style="font-family:sans-serif;">
        <b>{judul}</b><br>
        Buat sampel pada gambar.<br>
        Setelah selesai, <b>Copy koordinat sampel</b>, lalu paste ke cell baru.<br><br>

        <button id="{uid}_zoom_in">Zoom In</button>
        <button id="{uid}_zoom_out">Zoom Out</button>
        <button id="{uid}_reset_zoom">Reset Zoom</button>
        <button id="{uid}_undo">Undo titik terakhir</button>
        <button id="{uid}_clear">Hapus semua titik</button>
        <button id="{uid}_copy">Copy koordinat</button>

        <p>Zoom: <span id="{uid}_zoom_label">100%</span> | Jumlah titik: <span id="{uid}_count">0</span></p>

        <div id="{uid}_viewer"
             style="width:100%; height:350px; overflow:auto; border:1px solid #999; background:#eee;">
            <div id="{uid}_wrap" style="position:relative; display:inline-block;">
                <img id="{uid}_img"
                     src="data:image/png;base64,{img_base64}"
                     style="display:block; height:auto;">
                <canvas id="{uid}_canvas"
                        style="position:absolute; left:0; top:0; pointer-events:auto;"></canvas>
            </div>
        </div>

        <br>
        <textarea id="{uid}_txt"
                  style="width:100%; height:250px; font-family:monospace;"></textarea>
    </div>

    <script>
    (function() {{
        const img = document.getElementById("{uid}_img");
        const canvas = document.getElementById("{uid}_canvas");
        const ctx = canvas.getContext("2d");
        const txt = document.getElementById("{uid}_txt");
        const count = document.getElementById("{uid}_count");
        const zoomLabel = document.getElementById("{uid}_zoom_label");

        const xmin = {xmin};
        const xmax = {xmax};
        const ymin = {ymin};
        const ymax = {ymax};

        const namaVar = "{nama_var}";
        const warna = "{warna}";

        let points = [];
        let zoom = 1.0;

        function applyZoom() {{
            const naturalW = img.naturalWidth;
            const naturalH = img.naturalHeight;

            img.style.width = Math.round(naturalW * zoom) + "px";
            img.style.height = Math.round(naturalH * zoom) + "px";

            resizeCanvas();
            zoomLabel.textContent = Math.round(zoom * 100) + "%";}}

        function resizeCanvas() {{
            const rect = img.getBoundingClientRect();

            canvas.width = Math.round(rect.width);
            canvas.height = Math.round(rect.height);

            canvas.style.width = rect.width + "px";
            canvas.style.height = rect.height + "px";

            draw();}}

        function draw() {{
            ctx.clearRect(0, 0, canvas.width, canvas.height);

            points.forEach(function(p, i) {{
                const fx = (p[0] - xmin) / (xmax - xmin);
                const fy = (ymax - p[1]) / (ymax - ymin);

                const px = fx * canvas.width;
                const py = fy * canvas.height;

                ctx.beginPath();
                ctx.arc(px, py, 3, 0, 2 * Math.PI);
                ctx.fillStyle = warna;
                ctx.fill();

                ctx.lineWidth = 1;
                ctx.strokeStyle = "white";
                ctx.stroke();

                ctx.font = "10px sans-serif";
                ctx.fillStyle = "white";
                ctx.fillText(String(i + 1), px + 8, py - 8);
            }});
        }}

        function updateText() {{
            let isi = namaVar + " = [\\n";

            points.forEach(function(p) {{
                isi += "    (" + p[0].toFixed(2) + ", " + p[1].toFixed(2) + "),\\n";
            }});

            isi += "]";
            txt.value = isi;
            count.textContent = points.length;

            draw();
        }}

        canvas.addEventListener("click", function(event) {{
            const rect = canvas.getBoundingClientRect();

            const fx = (event.clientX - rect.left) / rect.width;
            const fy = (event.clientY - rect.top) / rect.height;

            const x = xmin + fx * (xmax - xmin);
            const y = ymax - fy * (ymax - ymin);

            points.push([x, y]);
            updateText();
        }});

        document.getElementById("{uid}_zoom_in").onclick = function() {{
            zoom = Math.min(zoom * 1.25, 6.0);
            applyZoom();
        }};

        document.getElementById("{uid}_zoom_out").onclick = function() {{
            zoom = Math.max(zoom / 1.25, 0.5);
            applyZoom();
        }};

        document.getElementById("{uid}_reset_zoom").onclick = function() {{
            zoom = 1.0;
            applyZoom();
        }};

        document.getElementById("{uid}_undo").onclick = function() {{
            points.pop();
            updateText();
        }};

        document.getElementById("{uid}_clear").onclick = function() {{
            points = [];
            updateText();
        }};

        document.getElementById("{uid}_copy").onclick = function() {{
            txt.select();
            document.execCommand("copy");
        }};

        if (img.complete) {{
            applyZoom();
        }} else {{
            img.onload = applyZoom;
        }}

        window.addEventListener("resize", resizeCanvas);
        setTimeout(applyZoom, 500);
        updateText();
    }})();
    </script>
    """

    display(HTML(kode))
```

Membuat sampel kelas minyak

```{code-cell} ipython3
tampilkan_picker_utm(
    img_base64=img_base64,
    extent=extent_sampling,
    nama_var="Sampel_Minyak",
    judul="Titik Sampel Kelas Minyak",
    warna="red")
```

Sampel yang dibuat tidak disimpan permanen, saat notebook dibuka ulang atau kernel putus sampel yang dibuat akan hilang. Oleh karena itu, copy hasil koordinat sampel yang didapatkan pada Code Cell baru.

```{code-cell} ipython3
Sampel_Minyak = [
    (797911.18, 9346951.28),
    (798424.26, 9346926.49),
    (798321.65, 9346802.58),
    (798834.73, 9346753.02),
    (773437.10, 9337761.99),
    (774104.11, 9337242.03),
    (776874.76, 9334195.86),
    (778157.46, 9332063.53),
    (777747.00, 9332725.29),
    (778824.47, 9330372.38),
    (779440.17, 9330041.50),
    (790317.54, 9325881.89),
    (789342.68, 9325929.16),
    (788367.83, 9325881.89),
    (787187.73, 9325929.16),
    (786110.26, 9326070.96),
    (785084.09, 9326212.77),
    (783801.38, 9326354.57),
    (783083.07, 9326449.11),
    (782416.06, 9326401.84),
    (781543.82, 9326449.11),
    (781133.35, 9326779.99),
    (780568.96, 9327252.67),
    (783236.99, 9327536.28),
    (797295.48, 9347085.35),
    (773488.41, 9337556.40),
    (778260.08, 9331919.50),
    (779645.41, 9329778.77),
    (779132.32, 9330224.13),
    (780928.12, 9327027.01)]
```

Membuat sampel kelas laut

```{code-cell} ipython3
tampilkan_picker_utm(
    img_base64=img_base64,
    extent=extent_sampling,
    nama_var="Sampel_Laut",
    judul="Titik Sampel Kelas Laut",
    warna="blue")
```

Sampel yang dibuat tidak disimpan permanen, saat *notebook* dibuka ulang atau kernel putus sampel yang dibuat akan hilang. Oleh karena itu, *copy* hasil koordinat sampel yang didapatkan pada *Code Cell* baru.

```{code-cell} ipython3
Sampel_Laut = [
    (742652.09, 9371389.91),
    (773796.26, 9371080.10),
    (797705.94, 9370421.74),
    (757685.43, 9366026.25),
    (770255.98, 9334984.56),
    (767228.79, 9335216.92),
    (783647.46, 9335855.92),
    (797705.94, 9338063.34),
    (797962.49, 9334326.21),
    (773231.86, 9330937.61),
    (777182.61, 9325806.31),
    (789753.15, 9328788.27),
    (798219.03, 9325903.13),
    (786725.96, 9324087.27),
    (791959.41, 9321841.11),
    (798629.50, 9322615.65),
    (779953.26, 9321163.40),
    (790163.62, 9317129.35),
    (803144.63, 9319607.87),
    (801092.30, 9316045.00),
    (801400.15, 9311879.72),
    (795397.07, 9313138.34),
    (742190.31, 9355890.03),
    (741215.45, 9349414.28),
    (786469.42, 9357119.01),
    (802375.00, 9356693.59),
    (772000.46, 9345727.35),
    (763791.13, 9356079.11),
    (786212.88, 9346662.21),
    (788624.37, 9325076.36),
    (792113.34, 9349072.89),
    (756710.58, 9345942.68),
    (800527.90, 9364077.95),
    (735571.54, 9367922.44),
    (735930.69, 9353931.02),
    (779491.48, 9361919.37),
    (777387.84, 9354015.06),
    (764047.67, 9343946.91),
    (791035.86, 9338747.40),
    (753375.53, 9356488.76),
    (745679.28, 9363195.61),
    (742754.70, 9342807.22),
    (768870.65, 9364471.85),
    (790779.32, 9366126.24),
    (785443.25, 9329587.85)]
```

Menggabung dan menyimpan sampel menjadi file GeoJSON.

```{code-cell} ipython3
all_points = {"Minyak": Sampel_Minyak, "Laut": Sampel_Laut}
combined = []

for kelas, pts in all_points.items():
    for x, y in pts:
        combined.append({"kelas": kelas, "label": 1 if kelas == "Minyak" else 0, "geometry": Point(x, y)})
if len(combined) == 0:
    raise ValueError("Belum ada titik training.")

groundtruth_titik = gpd.GeoDataFrame(combined, crs=aoi_gdf.crs)
groundtruth_wgs84 = groundtruth_titik.to_crs("EPSG:4326")
groundtruth_titik.to_file("files/training_points_all_utm.geojson", driver="GeoJSON")
groundtruth_wgs84.to_file( "files/training_points_all_wgs84.geojson", driver="GeoJSON")

print("File data sampel berhasil dibuat")
```

Mengambil nilai *backscatter* Lee Filter berdasarkan titik sampel yang dibuat.

```{code-cell} ipython3
training_points = groundtruth_titik
xs = training_points.geometry.x.values
ys = training_points.geometry.y.values

# Ekstrak nilai raster pada titik terdekat
vv_sample = citra_filter.sel(x=xr.DataArray(xs, dims="points"), y=xr.DataArray(ys, dims="points"), method="nearest").values

# Masukkan ke tabel training
training_points["vv_lee_db"] = vv_sample

# Pastikan label numerik ada
training_points["label"] = training_points["kelas"].map({"Laut": 0, "Minyak": 1})
training_df = training_points.dropna(subset=["vv_lee_db", "label"]).copy()

print("Jumlah data training valid:", len(training_df))
print("Rincian kelas:")
print(training_df["kelas"].value_counts())
training_df.head()
```

Visualisasi hasil persebaran data sampel.

```{code-cell} ipython3
fig, ax = plt.subplots(figsize=(12, 6))

data_merge["vv_lee_db"].squeeze(drop=True).plot.imshow(ax=ax, cmap="gray", vmin=-25, vmax=0, robust=True, add_colorbar=False)
data_merge["oilspill_clean"].where(data_merge["oilspill_clean"] == 1).squeeze(drop=True).plot.imshow(ax=ax, cmap="Reds", alpha=0.35, add_colorbar=False)
groundtruth_titik[groundtruth_titik["label"] == 1].plot(ax=ax, color="red", markersize=15, label="Minyak")
groundtruth_titik[groundtruth_titik["label"] == 0].plot(ax=ax, color="blue", markersize=15, label="Laut")

ax.set_title("Data Sampel Klasifikasi SVM")
ax.set_xlabel("Easting")
ax.set_ylabel("Northing")
ax.legend()
plt.show()
```

### B. *Split* data sampel
Data sampel yang dibuat akan dibagi menjadi *data training* dan *data testing* untuk model klasifikasi dengan perbandingan 80% dan 20%.

```{code-cell} ipython3
fitur_svm = ["vv_lee_db"]
X = training_df[fitur_svm]
y = training_df["label"].astype(int)

X_train, X_test, y_train, y_test = train_test_split(X, y, test_size=0.2, random_state=42, stratify=y)
tabel_distribusi = pd.DataFrame({
    "Seluruh Data": y.value_counts(),
    "Data Training": y_train.value_counts(),
    "Data Testing": y_test.value_counts()}).fillna(0).astype(int)

tabel_distribusi.index.name = "Label"
display(tabel_distribusi)
scaler = StandardScaler()
X_train_scaled = scaler.fit_transform(X_train)
X_test_scaled = scaler.transform(X_test)
```

### C. Penerapan Teknik SMOTE
Teknik SMOTE (*Synthetic Minority Over-sampling Technique*) digunakan untuk menyeimbangkan *data training* yang akan digunakan dalam model klasifikasi agar hasil tidak mengalami *overfitting* untuk kelas yang memiliki sampel lebih banyak. Penyeimbangan data training pada kelas minoritas dilakukan
dengan cara membuat sampel sintetis baru di antara titik-titik minoritas yang ada.

```{code-cell} ipython3
smote = SMOTE(random_state=42, k_neighbors=5)
X_train_smote, y_train_smote = smote.fit_resample(X_train_scaled, y_train)

tabel_distribusi_smote = (
    pd.Series(y_train_smote)
    .value_counts()
    .rename_axis("Label")
    .reset_index(name="Jumlah Data"))
display(tabel_distribusi_smote)

# MEMBUAT DATAFRAME HASIL SMOTE
X_train_smote_df = pd.DataFrame(X_train_smote, columns=fitur_svm)
y_train_smote_series = pd.Series(y_train_smote, name="label")
data_smote = pd.concat([X_train_smote_df, y_train_smote_series], axis=1)
display(data_smote.head(10))
```

### D. Klasifikasi SVM (*Support Vector Machine*)

SVM adalah algoritma yang bekerja dengan mencari *hyperplane* terbaik untuk memisahkan dua kelas data dengan memaksimalkan margin antara kelas-kelas yang ada sehingga akan menghasilkan hasil klasifikasi yang jelas.

```{code-cell} ipython3
svm_smote = SVC(kernel="linear", random_state=42)
svm_smote.fit(X_train_smote, y_train_smote)
print("Model SVM Linear dengan SMOTE berhasil dilatih.")
```

Menguji model dengan data testing

```{code-cell} ipython3
y_pred_smote = svm_smote.predict(X_test_scaled)
print("Prediksi data testing selesai.")

# Raster input untuk klasifikasi seluruh area laut
vv_arr = citra_filter.values
valid = np.isfinite(vv_arr)

# Batasi hanya area laut
if "mask_laut_garis_pantai" in data_merge:
    mask_laut = data_merge["mask_laut_garis_pantai"].squeeze(drop=True).values.astype(bool)
    valid = valid & mask_laut
print("Jumlah piksel valid untuk klasifikasi:", int(valid.sum()))

# Susun fitur raster sesuai urutan fitur waktu training
X_raster = pd.DataFrame({"vv_lee_db": vv_arr[valid]})
X_raster = X_raster[fitur_svm]

# Scaling pakai scaler dari training
X_raster_scaled = scaler.transform(X_raster)

# Prediksi seluruh piksel valid
pred_raster = svm_smote.predict(X_raster_scaled)

# Masukkan hasil ke array raster
svm_smote_arr = np.full(
    vv_arr.shape,
    np.nan,
    dtype="float32")
svm_smote_arr[valid] = pred_raster.astype("float32")
data_merge["svm_smote"] = xr.DataArray(
    svm_smote_arr,
    coords=citra_filter.coords,
    dims=citra_filter.dims,
    name="svm_smote")
print("Prediksi SVM seluruh raster selesai.")
print(pd.Series(pred_raster).value_counts())
```

Visualisasi hasil SVM dengan SMOTE

```{code-cell} ipython3
cmap_gray = plt.get_cmap("gray").copy()
fig, ax = plt.subplots(figsize=(8, 7))

data_merge["vv_lee_db"].squeeze(drop=True).plot.imshow(ax=ax, cmap=cmap_gray, vmin=-25, vmax=0, robust=True, add_colorbar=True, cbar_kwargs={"label": ""})
data_merge["svm_smote"].where(data_merge["svm_smote"] == 1).squeeze(drop=True).plot.imshow( ax=ax, cmap="Reds", alpha=1, add_colorbar=False)

ax.set_title("Hasil Klasifikasi")
ax.set_xlabel("Easting")
ax.set_ylabel("Northing")
plt.tight_layout()
plt.show()
```

## 9. Uji akurasi
Uji akurasi model klasifikasi menggunakan Confusion Matrix berdasarkan data training yang diujikan terhadap data testing. Confusion Matrix menggunakan empat variabel yaitu:
- TP (True Positive)  : Minyak diprediksi sebagai minyak
- TN (True Negative)  : Laut diprediksi sebagai laut
- FP (false positive) : Laut diprediksi sebagai minyak
- FN (false negative) : Minyak diprediksi sebagai laut

Dari keempat variabel tersebut akan dihitung menjadi beberapa model akurasi yang meliputi:
- Accuracy : Mengukur proporsi keseluruhan prediksi benar yang dihasilkan oleh model.
$$Accuracy = \frac{TP + TN}{TP + TN + FP + FN}$$
- Precision : Mempresentasikan proporsi piksel positif yang berhasil diklasifikasikan secara benar oleh model dibandingkan dengan keseluruhan piksel yang diprediksi sebagai kelas positif.
$$Precision = \frac{TP}{TP + FP}$$
- Specificity : Mengukur proporsi piksel negatif sebenarnya yang berhasil dikenali secara benar oleh model.
$$Specificity = \frac{TN}{TN + FP}$$
- Recall :  Rasio antara jumlah piksel positif yang terdeteksi dengan benar terhadap jumlah keseluruhan piksel yang sebenarnya positif.
$$Recall = \frac{TP}{TP + FN}$$
- F1-Score : Nilai rata-rata harmonik dari presisi dan sensitivitas.
$$\text{F1-score} = \frac{2 \times TP}{(2 \times TP) + FP + FN}$$
- Intersection over Union (IoU) : Mengukur tingkat kesesuaian spasial antara area hasil prediksi model dengan area anotasi *ground truth* yang dihitung berdasarkan rasio antara irisan (*intersection*) dan gabungan (*union*) dari kedua area tersebut.
$$\text{IoU} = \frac{TP}{TP + FP + FN}$$

+++

- Menghitung variabel yang akan digunakan untuk pengujian akurasi.

```{code-cell} ipython3
y_true = y_test
y_pred = y_pred_smote

# Confusion matrix dengan urutan label:
cm = confusion_matrix(y_true, y_pred, labels=[0, 1])
TN, FP, FN, TP = cm.ravel()

print("TP:", TP)
print("TN:", TN)
print("FP:", FP)
print("FN:", FN)
```

- Menghitung model uji akurasi

```{code-cell} ipython3
accuracy = (TP + TN) / (TP + TN + FP + FN) if (TP + TN + FP + FN) != 0 else 0
precision = TP / (TP + FP) if (TP + FP) != 0 else 0
specificity = TN / (TN + FP) if (TN + FP) != 0 else 0
recall = TP / (TP + FN) if (TP + FN) != 0 else 0
f1_score = (2 * TP) / ((2 * TP) + FP + FN) if ((2 * TP) + FP + FN) != 0 else 0
iou = TP / (TP + FP + FN) if (TP + FP + FN) != 0 else 0

hasil_evaluasi = pd.DataFrame({
    "TP": [TP],
    "TN": [TN],
    "FP": [FP],
    "FN": [FN],
    "Accuracy": [accuracy],
    "Precision": [precision],
    "Specificity": [specificity],
    "Recall": [recall],
    "F1-score": [f1_score],
    "IoU": [iou]})

for kolom in hasil_evaluasi:
    hasil_evaluasi[kolom] = (hasil_evaluasi[kolom] * 100).round(3)
hasil_evaluasi
```

- Visualisasi Confusion Matrix

```{code-cell} ipython3
disp = ConfusionMatrixDisplay(
    confusion_matrix=cm,
    display_labels=["Laut", "Minyak"])
disp.plot()
plt.title("Confusion Matrix")
plt.show()
```

## 10. *Post-Processing*

*Post-processing* ditujukan untuk menghasilkan visualisasi yang lebih baik dan menghilangkan *noise* dalam hasil klasifikasi. Dengan demikian, objek tumpahan minyak tervisualisasi dengan karakteristik spasial yang mengelompok.

```{code-cell} ipython3
# MAJORITY FILTER SVM
classification = data_merge["svm_smote"].squeeze(drop=True)
arr = classification.fillna(0).values.astype("uint8")
valid = np.isfinite(classification.values)

classification_clean_arr = ndimage.median_filter(arr, size=5, mode="nearest")
classification_clean_arr = np.where(valid, classification_clean_arr, np.nan)
data_merge["svm_majority"] = xr.DataArray(
    classification_clean_arr,
    coords=classification.coords,
    dims=classification.dims,
    name="svm_majority")

# CONNECTED PIXEL COUNT
oil_mask = data_merge["svm_majority"].values == 1
struktur_8 = np.ones((3, 3), dtype="uint8")
label_objek, jumlah_objek = ndimage.label(
    oil_mask, structure=struktur_8)

jumlah_piksel_objek = np.bincount(label_objek.ravel())
min_piksel = 35
objek_besar = jumlah_piksel_objek >= min_piksel
objek_besar[0] = False

oilspill_filtered_arr = objek_besar[label_objek]
oilspill_filtered_arr = np.where(
    oilspill_filtered_arr, 1, np.nan)

data_merge["svm_filtered"] = xr.DataArray(
    oilspill_filtered_arr,
    coords=classification.coords,
    dims=classification.dims,
    name="svm_filtered")

print("Connected pixel filtering selesai.")
print("Jumlah objek sebelum filter:", jumlah_objek)
print("Jumlah piksel oil setelah filter:", int(np.nansum(data_merge["svm_filtered"].values == 1)))
```

- Visualisasi Klasifikasi Setelah *Post-processing*.

```{code-cell} ipython3
cmap_gray = plt.get_cmap("gray").copy()
fig, ax = plt.subplots(figsize=(8, 7))

data_merge["vv_lee_db"].squeeze(drop=True).plot.imshow(ax=ax, cmap=cmap_gray, vmin=-25, vmax=0, robust=True, add_colorbar=True, cbar_kwargs={"label": ""})
data_merge["svm_filtered"].where(data_merge["svm_filtered"] == 1).squeeze(drop=True).plot.imshow(ax=ax, cmap="Reds", alpha=1, add_colorbar=False)

ax.set_title("Hasil Akhir Klasifikasi")
ax.set_xlabel("Easting")
ax.set_ylabel("Northing")
plt.tight_layout()
plt.show()
```

## 11. Perhitungan luas terdampak

Luas area tumpahan minyak dihitung berdasarkan hasil klasifikasi setelah *post-processing*.

```{code-cell} ipython3
mask_oil = data_merge["svm_filtered"].squeeze(drop=True)

pixel_size_x = abs(float(mask_oil.x.values[1] - mask_oil.x.values[0]))
pixel_size_y = abs(float(mask_oil.y.values[1] - mask_oil.y.values[0]))

luas_piksel_m2 = pixel_size_x * pixel_size_y

mask_oil_arr = mask_oil.values
jumlah_piksel_oil = int(np.sum(mask_oil_arr == 1))
luas_oil_m2 = jumlah_piksel_oil * luas_piksel_m2
luas_oil_ha = luas_oil_m2 / 10_000

hasil_luas_oil_svm = pd.DataFrame({
    "Jumlah Piksel Oil": [jumlah_piksel_oil],
    "Luas Oil Spill (ha)": [luas_oil_ha]})
display(hasil_luas_oil_svm)
```

- Menyimpan data hasil klasifikasi dan uji akurasi di folder `files`

```{code-cell} ipython3
svm_export = data_merge["svm_filtered"].squeeze(drop=True).astype("float32")
svm_export = svm_export.rio.write_crs(aoi_gdf.crs)
svm_export = svm_export.rio.write_nodata(-9999)

svm_export.where(np.isfinite(svm_export),
    -9999).rio.to_raster("files/hasil_akhir_klasifikasi.tif")

hasil_evaluasi.to_csv("files/hasil_uji_akurasi.csv", index=False)
```

# Catatan

Modul ini menyajikan gambaran umum mengenai penggunaan citra radar Sentinel-1 untuk deteksi tumpahan minyak di perairan, dengan hasil sebagai berikut:
1. *Thresholding* dengan -21 dB berhasil membedakan antara tumpahan minyak dengan perairan laut.
2. Area tumpahan minyak terdeteksi sebagai piksel dengan nilai *backscatter* kurang dari sama dengan -21 dB.
3. Hasil distribusi data menunjukkan bahwa tumpahan minyak tidak tersebar secara merata dan berbentuk bercak di citra.
4. Hasil ini terbukti valid karena permukaan minyak mereduksi hamburan balik lebih tinggi dibandingkan permukaan air pada citra SAR.

+++

# Info

- Skrip ini dikembangkan oleh **Laili Nisa** [lailinisa@students.undip.ac.id](mailto:lailinisa@students.undip.ac.id)
- Jika ada pertanyaan atau komentar, silahkan email ke piksel@big.go.id
- **Lisensi:** Skrip dalam notebook ini dilisensikan berdasarkan [Apache License, Version 2.0](https://www.apache.org/licenses/LICENSE-2.0). 
Data Piksel dilisensikan berdasarkan lisensi [Creative Commons by Attribution 4.0](https://creativecommons.org/licenses/by/4.0/).
