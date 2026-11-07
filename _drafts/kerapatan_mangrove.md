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

| <h1><b>Analisis Kerapatan Mangrove</b></h1> | ![](files/piksel_logo_small.png) |
|:---------|----------:|
- **Data:** Sentinel-2
- **Lokasi:** Segara Anakan, Kabupaten Cilacap, Provinsi Jawa Tengah
- **Metode:** Indeks Spektral dan Machine Learning (Random Forest)
- **Data lain:**  Titik sampel (`files/mangrove_2019.geojson`, `files/mangrove_2025.geojson`)

+++

# Pendahuluan
Modul ini menganalisis kerapatan dan dinamika mangrove di Segara Anakan, Kabupaten Cilacap, Provinsi Jawa Tengah menggunakan citra satelit Sentinel-2 tahun 2019 dan 2025. Tujuannya ini adalah untuk mengidentifikasi perubahan tutupan mangrove seiring waktu, menganalisis sebaran spasial mangrove, dan mengevaluasi kerapatan mangrove di wilayah studi. Metode yang digunakan menggabungkan analisis indeks spektral (NDVI, NDWI, CMRI, MVI, dan AMMI) dengan klasifikasi machine learning menggunakan algoritma Random Forest untuk menghasilkan peta kerapatan mangrove dan dinamika perubahannya.

Pendekatan metodologi meliputi:
1. preprocessing citra Sentinel-2 L2A termasuk perhitungan indeks spektral dan normalisasi reflektansi,
2. pengumpulan sampel titik melalui interpretasi visual untuk empat kelas tutupan lahan (Mangrove, Non-Vegetasi, Vegetasi Lain, dan Air),
3. pelatihan dan validasi model Random Forest menggunakan data sampel yang diekstraksi, dan
4. klasifikasi keseluruhan citra serta perhitungan luas dan dinamika perubahan mangrove. Hasil analisis diharapkan menghasilkan peta tematik kerapatan mangrove, statistik luas perubahan antarwaktu, dan evaluasi akurasi klasifikasi untuk mendukung pengambilan keputusan dalam pengelolaan ekosistem mangrove.

+++

# Tahapan
Tahapan dalam analisis kerapatan manggrove adalah:
1. Persiapan
2. Perhitungan spektral indeks
3. Klasifikasi tutupan lahan
4. Klasifikasi kerapatan mangrove
***

+++

## 1. Persiapan
Tahap ini dilakukan di awal pemrosesan data.

+++

### a. Memuat library

```{code-cell} ipython3
# library standard python
import warnings
from pathlib import Path
from IPython.display import display
from datacube import Datacube

# analisis data numerik
import numpy as np
import pandas as pd
import xarray as xr
from scipy import ndimage

# pengolahan citra
import matplotlib.pyplot as plt
from matplotlib.colors import ListedColormap, BoundaryNorm

# analisis spasial vektor
import geopandas as gpd
from shapely.geometry import box
from shapely.ops import transform as shapely_transform
from pyproj import Transformer

# analisis raster
import rasterio
from rasterio.io import MemoryFile

# machine learning
from sklearn.ensemble import RandomForestClassifier
from sklearn.metrics import (confusion_matrix, accuracy_score, cohen_kappa_score, f1_score)

# pengaturan umum
warnings.filterwarnings("ignore")
np.set_printoptions(suppress=True, precision=6)
pd.set_option("display.max_columns", None)
pd.set_option("display.width", 200)
```

### b. Konfigurasi
Menentukan parameter penelitian, meliputi: 
- Identitas Penelitian, Tahun Analisis
- Wilayah Kajian (AOI), Sistem Koordinat
- Indeks Spektral, Kelas Klasifikasi Random Forest
- Lokasi Output

```{code-cell} ipython3
STUDY_AREA_NAME = ("Segara Anakan, Kabupaten Cilacap, Provinsi Jawa Tengah")
# Konfigurasi Open Data Cube
PRODUCT_NAME = "s2_l2a"
QUERY_CRS = "EPSG:4326"
OUTPUT_CRS = "EPSG:32749"
RESOLUTION = (-10,10)
RANDOM_STATE = 42
# Tanggal citra yang digunakan
ANALYSIS_DATES = {2019: "2019-05-22", 2025: "2025-07-21"}
ANALYSIS_YEARS = list(ANALYSIS_DATES.keys())
# Band Sentinel-2
SOURCE_MEASUREMENTS = ["blue", "green", "red", "nir08", "swir16", "swir22", "scl"]
SPECTRAL_BANDS = ["blue", "green", "red", "nir08", "swir16", "swir22"]
# Pengaturan resampling
RESAMPLING_METHODS = {"blue": "bilinear", "green": "bilinear", "red": "bilinear", "nir08": "bilinear", "swir16": "bilinear", "swir22": "bilinear", "scl": "nearest"}
```

```{code-cell} ipython3
# Indeks spektral
INDEX_NAMES = ["ndvi", "ndwi", "mvi", "cmri", "ammi"]
# Kelas klasifikasi Random Forest
CLASS_NAMES = {1: "Mangrove", 2: "Non Vegetation", 3: "Other Vegetation", 4: "Water"}
CLASS_IDS = list(CLASS_NAMES.keys())
```

```{code-cell} ipython3
# AOI Segara Anakan
LONGITUDE_MIN = 108.790
LONGITUDE_MAX = 108.900
LATITUDE_MIN = -7.710
LATITUDE_MAX = -7.650
# Dictionary AOI untuk query Open Data Cube
AOI = {"longitude": (LONGITUDE_MIN, LONGITUDE_MAX), "latitude": (LATITUDE_MIN, LATITUDE_MAX), "crs": QUERY_CRS}
# Membentuk geometri bounding box AOI
AOI_GEOMETRY_WGS84 = box(LONGITUDE_MIN, LATITUDE_MIN, LONGITUDE_MAX, LATITUDE_MAX)
# Transformasi AOI ke UTM Zona 49 Selatan
transformer_wgs84_to_utm = Transformer.from_crs(QUERY_CRS, OUTPUT_CRS, always_xy=True)
AOI_GEOMETRY_UTM = shapely_transform(transformer_wgs84_to_utm.transform, AOI_GEOMETRY_WGS84)
# Batas koordinat AOI dalam UTM
(AOI_MIN_X, AOI_MIN_Y, AOI_MAX_X, AOI_MAX_Y) = AOI_GEOMETRY_UTM.bounds
```

```{code-cell} ipython3
# Folder input
INPUT_ROOT = Path("files")
# Berkas titik sampel per tahun (dibaca langsung, tidak ditulis/diproses ulang ke disk)
SAMPLE_INPUT_FILES = {2019: INPUT_ROOT / "mangrove_2019.geojson", 2025: INPUT_ROOT / "mangrove_2025.geojson"}
# Koneksi Open Data Cube
dc = Datacube(app="mangrove_segara_anakan_rf")
# Dictionary penyimpanan hasil
datasets_raw = {}
dataset_indices = {}
rgb_images = {}
available_datasets = {}
```

### c. Persiapan data Sentinel-2
Memastikan produk Sentinel-2 yang digunakan tersedia serta memiliki band spektral yang dibutuhkan untuk visualisasi, perhitungan indeks, dan klasifikasi tutupan lahan.

```{code-cell} ipython3
# Ekstrak band yang tersedia untuk produk s2_l2a
measurements_all_df = dc.list_measurements(with_pandas=True)
if isinstance(measurements_all_df.index, pd.MultiIndex) and "product" in measurements_all_df.index.names:
    product_measurements_df = measurements_all_df.xs(PRODUCT_NAME, level="product").copy()
else:
    product_measurements_df = measurements_all_df[measurements_all_df.get("product", PRODUCT_NAME) == PRODUCT_NAME].copy()

available_measurements = sorted(set(product_measurements_df.index.astype(str).tolist() if "name" not in product_measurements_df.columns 
                                    else product_measurements_df["name"].astype(str).tolist()))
LOAD_MEASUREMENTS = [m for m in SOURCE_MEASUREMENTS if m in available_measurements]

# Tampilkan hasil
print("\n" + "=" * 78)
print("KONFIGURASI PRODUK DAN BAND")
print(f"Produk              : {PRODUCT_NAME}")
print(f"Band tersedia       : {available_measurements}")
print(f"Band yang digunakan : {LOAD_MEASUREMENTS}")
print("=" * 78)
```

Melakukan pemeriksaan terhadap jumlah dataset citra yang tersedia dan tanggal perekaman citra satelit pada setiap tahun

```{code-cell} ipython3
# Cari dataset untuk setiap tahun
available_datasets = {}
for year, acquisition_date in ANALYSIS_DATES.items():
    start_time = pd.Timestamp(acquisition_date)
    end_time = start_time + pd.Timedelta(days=1) - pd.Timedelta(microseconds=1)

    try:
        datasets_found = dc.find_datasets(
            product=PRODUCT_NAME,
            time=(start_time.to_pydatetime(), end_time.to_pydatetime()),
            longitude=AOI["longitude"],
            latitude=AOI["latitude"])
    except Exception as error:
        datasets_found = []
        print(f"Error mencari dataset tahun {year}: {error}")

    available_datasets[year] = datasets_found

    print(f"\nTahun {year} | Tanggal: {acquisition_date} | Dataset: {len(datasets_found)}")
```

### d. Memuat citra 
- Memuat citra Sentinel-2A di setiap tahun pengamatan
- Menampilkan komposit warna alami (RGB) untuk membantu dalam menganalisis kondisi umum tutupan lahan di wilayah penelitian

```{code-cell} ipython3
# Pengaturan resampling
RESAMPLING_METHODS = {band: "bilinear" if band != "scl" else "nearest" for band in LOAD_MEASUREMENTS}

# Muat citra untuk setiap tahun
datasets_raw = {}
for year, acquisition_date in ANALYSIS_DATES.items():
    start_time = pd.Timestamp(acquisition_date)
    end_time = start_time + pd.Timedelta(days=1) - pd.Timedelta(microseconds=1)

    dataset = dc.load(
        product=PRODUCT_NAME,
        measurements=LOAD_MEASUREMENTS,
        time=(start_time.to_pydatetime(), end_time.to_pydatetime()),
        longitude=AOI["longitude"],
        latitude=AOI["latitude"],
        output_crs=OUTPUT_CRS,
        resolution=RESOLUTION,
        group_by="solar_day",
        resampling=RESAMPLING_METHODS)

    if dataset is None or len(dataset.data_vars) == 0:
        raise ValueError(f"Citra tahun {year} gagal dimuat atau kosong.")

    # Pilih time slice terdekat jika ada multiple timesteps
    if "time" in dataset.dims:
        target_time = pd.Timestamp(acquisition_date)
        available_times = pd.to_datetime(dataset["time"].values)
        selected_index = int(np.argmin(np.abs(available_times - target_time)))
        dataset = dataset.isel(time=selected_index, drop=True)

    # Simpan metadata
    dataset.attrs.update({"year": int(year), "analysis_date": acquisition_date})
    datasets_raw[year] = dataset

    h, w = dataset.sizes["y"], dataset.sizes["x"]
    print(f"Tahun {year} | {acquisition_date} | Raster: {h:,}×{w:,} | Band: {list(dataset.data_vars)}")
```

```{code-cell} ipython3
# Siapkan 6 band Sentinel-2 untuk setiap tahun (disimpan di memori, bukan ke disk)
SPECTRAL_BANDS = ["blue", "green", "red", "nir08", "swir16", "swir22"]

def get_2d_band(dataset, band_name):
    """Ambil band sebagai array 2D."""
    data = dataset[band_name].isel(time=0, drop=True) if "time" in dataset[band_name].dims else dataset[band_name]
    return np.asarray(data.values).squeeze().astype("float32")

# Dataset raster reflectance 6 band per tahun, dibuka di memori (rasterio MemoryFile)
reflectance_memfiles = {}
reflectance_rasters = {}

for year, dataset in datasets_raw.items():
    # Siapkan data 6 band
    band_stack = []
    for band_name in SPECTRAL_BANDS:
        band_data = get_2d_band(dataset, band_name)
        band_stack.append(band_data)

    # Stack menjadi array (6, height, width)
    stack_array = np.stack(band_stack, axis=0).astype("float32")

    # Siapkan profil raster
    profile = {
        "driver": "GTiff",
        "dtype": "float32",
        "nodata": -9999.0,
        "width": stack_array.shape[2],
        "height": stack_array.shape[1],
        "count": 6,
        "crs": OUTPUT_CRS,
        "transform": rasterio.transform.from_bounds(
            AOI_MIN_X, AOI_MIN_Y, AOI_MAX_X, AOI_MAX_Y,
            stack_array.shape[2], stack_array.shape[1]
        ),
        "compress": "lzw"
    }

    # Buat raster reflectance 6 band di memori
    memfile = MemoryFile()
    dst = memfile.open(**profile)
    dst.write(stack_array)
    reflectance_memfiles[year] = memfile
    reflectance_rasters[year] = dst

    print(f"Reflectance 6 band tahun {year} siap di memori")

print(f"\n6 band Sentinel-2 siap di memori untuk tahun: {list(reflectance_rasters.keys())}")
```

### e. Visualisasi data
Data Sentinel 2 ditampilkan dalam color composite

```{code-cell} ipython3
# Fungsi helper untuk visualisasi
def to_reflectance(band_array):
    """Konversi ke reflektansi (0-1) jika diperlukan."""
    valid = band_array[np.isfinite(band_array)]
    if valid.size == 0:
        return band_array.astype("float32")
    scale = 10000.0 if np.nanpercentile(valid, 99) > 2 else 1.0
    return (band_array / scale).astype("float32")

def get_display_limits(datasets, bands, lower_pct=2, upper_pct=98):
    """Hitung batas display global untuk semua tahun."""
    limits = {}
    for band in bands:
        values = np.concatenate([to_reflectance(get_2d_band(ds, band))[np.isfinite(to_reflectance(get_2d_band(ds, band)))] 
                                for ds in datasets.values()])
        if values.size == 0:
            raise ValueError(f"Tidak ada nilai valid untuk band '{band}'")
        lo, hi = np.nanpercentile(values, [lower_pct, upper_pct])
        limits[band] = {"min": lo, "max": hi if hi > lo else lo + 0.01}
    return limits

def make_composite(dataset, band_order, limits, gamma=0.90):
    """Buat komposit RGB dengan normalisasi."""
    h, w = get_2d_band(dataset, band_order[0]).shape
    composite = np.zeros((h, w, 3), dtype="float32")
    for i, band in enumerate(band_order):
        data = to_reflectance(get_2d_band(dataset, band))
        data = (data - limits[band]["min"]) / (limits[band]["max"] - limits[band]["min"])
        composite[:, :, i] = np.clip(data, 0, 1)
    composite = np.power(composite, gamma)
    composite = np.nan_to_num(composite, nan=0.0, posinf=1.0, neginf=0.0)
    return np.flipud(composite) if dataset["y"].values[0] < dataset["y"].values[-1] else composite

# Buat dan visualisasi komposit RGB
rgb_limits = get_display_limits(datasets_raw, ["red", "green", "blue"])
rgb_images = {year: make_composite(ds, ["red", "green", "blue"], rgb_limits) 
              for year, ds in datasets_raw.items()}

fig, axes = plt.subplots(len(rgb_images), 1, figsize=(10, 4*len(rgb_images)), dpi=120)
if len(rgb_images) == 1:
    axes = [axes]
for ax, (year, img) in zip(axes, rgb_images.items()):
    ax.imshow(img, interpolation="nearest")
    ax.set_title(f"Tanggal {ANALYSIS_DATES[year]}", fontsize=9)
    ax.set_xticks([])
    ax.set_yticks([])
fig.suptitle("Komposit Warna Alami RGB", fontsize=9, fontweight="bold")
plt.tight_layout()
```

Visualisasi false color (NIR–SWIR1–SWIR2) digunakan untuk membantu membedakan vegetasi, kelembapan, lahan terbuka, dan badan air

```{code-cell} ipython3
# Buat dan visualisasi komposit False Color (NIR-SWIR1-SWIR2)
fc_limits = get_display_limits(datasets_raw, ["nir08", "swir16", "swir22"])
fc_images = {year: make_composite(ds, ["nir08", "swir16", "swir22"], fc_limits) 
             for year, ds in datasets_raw.items()}

fig, axes = plt.subplots(len(fc_images), 1, figsize=(10, 4*len(fc_images)), dpi=120)
if len(fc_images) == 1:
    axes = [axes]
for ax, (year, img) in zip(axes, fc_images.items()):
    ax.imshow(img, interpolation="nearest")
    ax.set_title(f"Tanggal {ANALYSIS_DATES[year]} (NIR-SWIR1-SWIR2)", fontsize=9)
    ax.set_xticks([])
    ax.set_yticks([])
fig.suptitle("Komposit False Color (NIR-SWIR1-SWIR2)", fontsize=9, fontweight="bold")
plt.tight_layout()
plt.show()
```

## 2. Perhitungan spektral indeks
Beberapa spektral index yang digunakan adalah sebagai berikut:
  1. **NDVI (Normalized Difference Vegetation Index)**
$$NDVI = \frac{(NIR - red)}{(NIR + red)}$$
  2. **NDWI (Normalized Difference Water Index)**
$$NDWI = \frac{(GREEN - SWIR_1)}{(GREEN + SWIR_1)}$$
  3. **MVI (Mangrove Vegetation Index)**
$$MVI = \frac{(NIR - GREEN)}{(SWIR_1 - GREEN)}$$
  4. **CMRI (Combined Mangrove Recognition Index)**
$$CMRI = {(NDVI - NDWI)}$$
  5. **AMMI (Automatic Mangrove Map and Index)**
$$AMMI = NDVI \times \frac{(NIR - SWIR)}{(SWIR - 0.65 \times RED)}$$
Selain itu, tabel statistik setiap indeks dibuat.

+++

### a. Perhitunan statistik
Statistik dari setiap spektral indeks dihitung.

```{code-cell} ipython3
# Hitung indeks spektral
def safe_div(num, denom, eps=1e-6):
    """Pembagian aman dengan handling divide-by-zero."""
    return xr.where(np.abs(denom) > eps, num / denom, np.nan)

dataset_indices = {}
stats_records = []

for year in ANALYSIS_YEARS:
    if year not in datasets_raw:
        continue

    ds = datasets_raw[year]
    # Konversi ke float32 dan handle skala (jika masih 0-10000 range)
    r = ds["red"].astype("float32")
    g = ds["green"].astype("float32")
    nir = ds["nir08"].astype("float32")
    swir = ds["swir16"].astype("float32")

    # Cek dan normalisasi ke 0-1 jika diperlukan
    nir_max = float(np.nanpercentile(nir.values, 99))
    if nir_max > 2:
        r = r / 10000.0
        g = g / 10000.0
        nir = nir / 10000.0
        swir = swir / 10000.0

    # Hitung indeks (tanpa clipping)
    ndvi = safe_div(nir - r, nir + r)
    ndwi = safe_div(g - swir, g + swir)
    mvi = safe_div(nir - g, swir - g, 0.001)
    mvi = mvi.where((mvi >= -20)& (mvi <= 20))
    cmri = (ndvi - ndwi)
    ammi = (ndvi * safe_div(nir - swir, swir - (0.65 * r), 0.001))

    # Simpan indeks
    dataset_indices[year] = xr.Dataset({
        "ndvi": ndvi.astype("float32"),
        "ndwi": ndwi.astype("float32"),
        "mvi": mvi.astype("float32"),
        "cmri": cmri.astype("float32"),
        "ammi": ammi.astype("float32")
    })

    # Hitung min/max per indeks
    row = {"Tahun": year}
    for idx_name in INDEX_NAMES:
        values = np.asarray(dataset_indices[year][idx_name].values).ravel()
        values = values[np.isfinite(values)]

        if values.size > 0:
            row[f"{idx_name.upper()}-min"] = float(np.nanmin(values))
            row[f"{idx_name.upper()}-max"] = float(np.nanmax(values))
        else:
            row[f"{idx_name.upper()}-min"] = np.nan
            row[f"{idx_name.upper()}-max"] = np.nan

    stats_records.append(row)

# Buat tabel
stats_df = pd.DataFrame(stats_records)
if not stats_df.empty:
    stats_df = stats_df.set_index("Tahun")
    print("\n" + "=" * 130)
    print("STATISTIK INDEKS SPEKTRAL")
    print("=" * 130)
    print(stats_df.to_string(float_format=lambda x: f"{x:.4f}"))
    print("=" * 130)
```

```{code-cell} ipython3
# Siapkan indeks spektral sebagai raster di memori (bukan ke disk)
index_memfiles = {}
index_rasters = {}

for year in ANALYSIS_YEARS:
    if year not in dataset_indices:
        continue

    dataset_idx = dataset_indices[year]

    # Siapkan profil raster (sama seperti reflectance)
    profile = {
        "driver": "GTiff",
        "dtype": "float32",
        "nodata": -9999.0,
        "width": dataset_idx.sizes["x"],
        "height": dataset_idx.sizes["y"],
        "count": 1,
        "crs": OUTPUT_CRS,
        "transform": rasterio.transform.from_bounds(
            AOI_MIN_X, AOI_MIN_Y, AOI_MAX_X, AOI_MAX_Y,
            dataset_idx.sizes["x"], dataset_idx.sizes["y"]
        ),
        "compress": "lzw"
    }

    index_memfiles[year] = {}
    index_rasters[year] = {}

    # Siapkan setiap indeks di memori
    for idx_name in INDEX_NAMES:
        idx_data = np.asarray(dataset_idx[idx_name].values, dtype="float32").squeeze()

        # Flip jika diperlukan
        if dataset_idx["y"].values[0] < dataset_idx["y"].values[-1]:
            idx_data = np.flipud(idx_data)

        memfile = MemoryFile()
        dst = memfile.open(**profile)
        dst.write(idx_data, 1)
        index_memfiles[year][idx_name] = memfile
        index_rasters[year][idx_name] = dst

print(f"\nIndeks spektral siap di memori untuk tahun: {list(index_rasters.keys())}")
```

### b. Visualisasi spektral indeks
Menampilkan sebaran spasial masing-masing indeks berdasarkan karakteristik indeks untuk mengidentifikasi:
- variasi vegetasi
- perairan
- kondisi mangrove di wilayah penelitian

```{code-cell} ipython3
# Konfigurasi visualisasi indeks dengan range tetap
INDEX_SETTINGS = {
    "ndvi": {"cmap": "RdYlGn", "vmin": -1.0, "vmax": 1.0},
    "ndwi": {"cmap": "RdYlBu", "vmin": -1.0, "vmax": 1.0}, 
    "mvi": {"cmap": "BrBG", "vmin": -1.1310, "vmax": 6.8906},"range_mode": "robust",
    "cmri": {"cmap": "PRGn", "vmin": -2.0, "vmax": 2.0},
    "ammi": {"cmap": "PiYG", "vmin": -0.1123, "vmax": 2.9658}
}

# Visualisasi indeks multitemporal
for idx_name in INDEX_NAMES:
    settings = INDEX_SETTINGS[idx_name]
    vmin, vmax = settings["vmin"], settings["vmax"]
    cmap = plt.get_cmap(settings["cmap"]).copy()
    cmap.set_bad(color="#E5E5E5")

    # Buat figure dengan space untuk colorbar
    fig = plt.figure(figsize=(15, 6), dpi=120)

    # Buat grid: 2 maps + 1 colorbar space
    gs = fig.add_gridspec(1, 3, width_ratios=[1, 1, 0.05], wspace=0.3)

    axes = [fig.add_subplot(gs[0, 0]), fig.add_subplot(gs[0, 1])]
    cbar_ax = fig.add_subplot(gs[0, 2])

    im = None
    for ax, year in zip(axes, ANALYSIS_YEARS):
        if year in dataset_indices:
            img_array = np.asarray(dataset_indices[year][idx_name].values).squeeze()
            if img_array.ndim == 2 and dataset_indices[year]["y"].values[0] < dataset_indices[year]["y"].values[-1]:
                img_array = np.flipud(img_array)

            im = ax.imshow(img_array, cmap=cmap, vmin=vmin, vmax=vmax, interpolation="nearest")
            ax.set_title(f"{year} | {ANALYSIS_DATES[year]}", fontweight="bold", fontsize=11)

        ax.set_xticks([])
        ax.set_yticks([])

    # Colorbar di area khusus
    if im is not None:
        cbar = fig.colorbar(im, cax=cbar_ax, orientation="vertical")
        cbar.set_label(f"{idx_name.upper()}", fontsize=11)

    fig.suptitle(f"Indeks {idx_name.upper()}", 
                 fontsize=14, fontweight="bold", y=0.98)

    plt.show()
    plt.close(fig)

print(f"\nPeta indeks selesai ditampilkan untuk {len(INDEX_NAMES)} indeks")
```

### c. Visualisasi histogram indeks
Menampilkan hasil distribusi dari setiap indeks untuk mengetahui rentang nilai, pola sebaran hingga perbedaan karakteristik setiap indeks antarwaktu

```{code-cell} ipython3
# Histogram indeks
HISTOGRAM_BINS = 100
HISTOGRAM_COLORS = {"ndvi": "forestgreen", "ndwi": "royalblue", "mvi": "darkorange", 
                    "cmri": "purple", "ammi": "crimson"}

for idx_name in INDEX_NAMES:
    # Kumpulkan data per tahun
    data_by_year = {}
    for year in ANALYSIS_YEARS:
        if year in dataset_indices:
            vals = np.asarray(dataset_indices[year][idx_name].values, dtype="float32").ravel()
            vals = vals[np.isfinite(vals)]
            if vals.size > 0:
                data_by_year[year] = vals

    if not data_by_year:
        print(f"Tidak ada data untuk indeks {idx_name.upper()}")
        continue

    # Tentukan range global
    v_min = min(np.nanmin(v) for v in data_by_year.values())
    v_max = max(np.nanmax(v) for v in data_by_year.values())
    if v_max <= v_min:
        v_max = v_min + 0.0001
    bin_edges = np.linspace(v_min, v_max, HISTOGRAM_BINS + 1)

    # Buat histogram
    fig, axes = plt.subplots(1, len(ANALYSIS_YEARS), figsize=(14, 5), dpi=120)
    if len(ANALYSIS_YEARS) == 1:
        axes = [axes]

    for ax, year in zip(axes, ANALYSIS_YEARS):
        if year in data_by_year:
            vals = data_by_year[year]

            # Plot histogram
            ax.hist(vals, bins=bin_edges, color=HISTOGRAM_COLORS[idx_name], 
                   alpha=0.7, edgecolor="black", linewidth=0.5)

            # Garis statistik
            mean_val = np.nanmean(vals)
            median_val = np.nanmedian(vals)
            ax.axvline(mean_val, color="red", linestyle="--", linewidth=2, label=f"Mean: {mean_val:.4f}")
            ax.axvline(median_val, color="black", linestyle="-.", linewidth=2, label=f"Median: {median_val:.4f}")

            # Label dan grid
            ax.set_xlim(v_min, v_max)
            ax.set_title(f"{year} | {ANALYSIS_DATES[year]}", fontweight="bold", fontsize=11)
            ax.set_xlabel(f"Nilai {idx_name.upper()}", fontsize=10)
            ax.set_ylabel("Frekuensi Piksel", fontsize=10)
            ax.grid(axis="y", alpha=0.3)
            ax.legend(fontsize=9)

            # Statistik box
            stats_text = f"Min: {np.nanmin(vals):.4f}\nMax: {np.nanmax(vals):.4f}\nStd: {np.nanstd(vals):.4f}\nN: {vals.size:,}"
            ax.text(0.98, 0.97, stats_text, transform=ax.transAxes, 
                   ha="right", va="top", fontsize=9, 
                   bbox=dict(boxstyle="round", facecolor="white", alpha=0.8))
        else:
            ax.text(0.5, 0.5, "Tidak ada data", ha="center", va="center", fontsize=12)
            ax.axis("off")

    fig.suptitle(f"Histogram {idx_name.upper()}", fontsize=14, fontweight="bold", y=0.98)
    fig.tight_layout()
    plt.show()
    plt.close(fig)

print(f"Histogram selesai untuk {len(INDEX_NAMES)} indeks")
```

## 3. Klasifikasi tutupan lahan
Random forest digunakan untuk melakukan klasifikasi tutupan lahan.

+++

### a. Input titik sampling
Memasukkan sampel titik hasil interpretasi yang telah disimpan dalam format GeoJSON sebagai data training dan validasi untuk empat kelas tutupan lahan.
Titik sampel yang dibuat mewakili area:
- Mangrove
- Non Vegetation
- Other Vegetation
- Water

```{code-cell} ipython3
# Konfigurasi sampel
SAMPLE_CLASS_MAP = {"mangrove": 1, "n-mangrove": 2, "non mangrove": 2, "non-mangrove": 2, "non vegetation": 2, 
                     "nonvegetation": 2, "o-vege": 3, "other vegetation": 3, "othervegetation": 3, "water": 4}
SAMPLE_TYPE_MAP = {"t": "training", "training": "training", "train": "training", "v": "validation", 
                    "validation": "validation", "validasi": "validation", "test": "validation", "testing": "validation"}

def find_column(df, candidates):
    """Cari kolom dengan nama yang fleksibel."""
    norm_cols = {str(c).strip().lower(): c for c in df.columns}
    for candidate in candidates:
        if str(candidate).strip().lower() in norm_cols:
            return norm_cols[str(candidate).strip().lower()]
    raise KeyError(f"Kolom tidak ditemukan. Kandidat: {candidates}")

# Standarisasi sampel setiap tahun
standard_samples_by_year = {}
standardization_records = []

for year in ANALYSIS_YEARS:
    input_path = SAMPLE_INPUT_FILES[year]
    if not input_path.exists():
        print(f"Peringatan: File sampel {year} tidak ditemukan di {input_path}")
        continue

    # Baca dan bersihkan
    gdf = gpd.read_file(input_path)
    if gdf.empty or gdf.crs is None:
        continue

    # Hapus geometri invalid
    gdf = gdf[gdf.geometry.notna() & ~gdf.geometry.is_empty & gdf.geometry.is_valid]
    gdf = gdf.explode(index_parts=False, ignore_index=True).reset_index(drop=True)

    if not (gdf.geometry.geom_type == "Point").all():
        print(f"Peringatan: Sampel {year} ada non-Point geometry, dihapus")
        gdf = gdf[gdf.geometry.geom_type == "Point"].reset_index(drop=True)

    # Standardisasi kolom
    id_col = find_column(gdf, ["Kode", "kode", "id", "sample_id"])
    type_col = find_column(gdf, ["Jenis", "jenis", "type", "sample_type"])
    class_col = find_column(gdf, ["Kelas", "kelas", "class", "class_name"])

    # Buat GeoDataFrame standar
    std_gdf = gdf[[id_col, type_col, class_col, "geometry"]].copy()
    std_gdf["sample_id"] = gdf[id_col].astype(str).str.strip()
    std_gdf["sample_id"] = std_gdf["sample_id"].replace(["", "nan", "None", "none"], "").fillna("")
    std_gdf.loc[std_gdf["sample_id"] == "", "sample_id"] = [f"{year}_s{i:04d}" for i in range(len(std_gdf[std_gdf["sample_id"] == ""]))]

    std_gdf["sample_type"] = gdf[type_col].astype(str).str.strip().str.lower().map(SAMPLE_TYPE_MAP)
    std_gdf["class_id"] = gdf[class_col].astype(str).str.strip().str.lower().map(SAMPLE_CLASS_MAP)
    std_gdf["year"] = year

    # Validasi
    if std_gdf["sample_type"].isna().any() or std_gdf["class_id"].isna().any():
        print(f"Peringatan: Sampel {year} ada label invalid, dihapus")
        std_gdf = std_gdf[std_gdf["sample_type"].notna() & std_gdf["class_id"].notna()]

    std_gdf["class_id"] = std_gdf["class_id"].astype(int)
    std_gdf["class_name"] = std_gdf["class_id"].map(CLASS_NAMES)
    std_gdf = std_gdf.to_crs("EPSG:4326")[["sample_id", "year", "sample_type", "class_id", "class_name", "geometry"]].reset_index(drop=True)
    std_gdf["longitude"] = std_gdf.geometry.x
    std_gdf["latitude"] = std_gdf.geometry.y

    standard_samples_by_year[year] = std_gdf

    # Hitung statistik
    for stype in ["training", "validation"]:
        for cid in CLASS_IDS:
            count = ((std_gdf["sample_type"] == stype) & (std_gdf["class_id"] == cid)).sum()
            standardization_records.append({"Tahun": year, "Jenis": stype, "Kelas ID": cid, 
                                           "Kelas": CLASS_NAMES[cid], "Jumlah": count})

# Tampilkan ringkasan
summary_df = pd.DataFrame(standardization_records)
if not summary_df.empty:
    print("\n" + "=" * 80)
    print("RINGKASAN STANDARDISASI SAMPEL")
    print("=" * 80)
    print(summary_df.to_string(index=False))
    print("=" * 80)

print(f"Standardisasi sampel selesai untuk tahun: {list(standard_samples_by_year.keys())}")
```

### b. Ekstraksi nilai band
Mengambil nilai band spektral dan indeks pada setiap lokasi sampel untuk membentuk dataset atribut yang digunakan dalam pelatihan dan pengujian model Random Forest.

```{code-cell} ipython3
# Pemeriksaan variabel
SPECTRAL_FEATURES = ["blue", "green", "red", "nir08", "swir16", "swir22"]
INDEX_FEATURES = ["ndvi", "ndwi", "mvi", "cmri", "ammi"]
# Fungsi pemeriksaan grid
def grids_are_equal(reference_profile, comparison_profile):
    return all([reference_profile["width"] == comparison_profile["width"], reference_profile["height"] == comparison_profile["height"], reference_profile["crs"] == 
                comparison_profile["crs"], reference_profile["transform"].almost_equals(comparison_profile["transform"])])
# Fungsi pemeriksaan titik terhadap raster
def point_inside_raster_bounds(point_geometry, raster_bounds):
    if point_geometry is None:
        return False
    if point_geometry.is_empty:
        return False
    return (raster_bounds.left <= point_geometry.x <= raster_bounds.right and raster_bounds.bottom <= point_geometry.y <= raster_bounds.top)
# Fungsi sampling raster (menerima dataset rasterio yang sudah terbuka di memori)
def sample_raster_values(raster_source, point_gdf, band_numbers):
    if isinstance(band_numbers, int):
        band_numbers = [band_numbers]
    source = raster_source
    point_gdf_raster_crs = (point_gdf .to_crs(source.crs) .copy())
    inside_mask = (point_gdf_raster_crs.geometry .apply(lambda geometry: point_inside_raster_bounds(geometry, source.bounds)) .to_numpy(dtype=bool))
    result_array = np.full((len(point_gdf_raster_crs), len(band_numbers)), np.nan, dtype="float32")
    inside_indices = np.flatnonzero(inside_mask)
    if len(inside_indices) > 0:
        coordinates = [(point_gdf_raster_crs.geometry.iloc[row_index].x, point_gdf_raster_crs.geometry.iloc[row_index].y) for row_index in inside_indices]
        sampled_rows = list(source.sample(coordinates, indexes=band_numbers, masked=True))
        sampled_array = np.asarray([np.ma.filled(sampled_row, np.nan) for sampled_row in sampled_rows], dtype="float32")
        if sampled_array.ndim == 1:
            sampled_array = (sampled_array.reshape(-1, 1))
        result_array[inside_indices, :] = sampled_array
    return {"values": result_array, "inside_mask": inside_mask, "profile": source.profile.copy(), "transform": source.transform, "crs": source.crs, "bounds": source.bounds}
# Variabel hasil
sample_feature_tables = {}
training_tables = {}
validation_tables = {}
raster_catalog = {}
raster_profiles = {}
sample_extraction_records = []
sample_class_count_records = []
outside_raster_records = []
# Ekstraksi setiap tahun
for year in ANALYSIS_YEARS:
    if year not in reflectance_rasters:
        raise FileNotFoundError(f"Raster reflectance tahun {year} tidak tersedia di memori.")
    reflectance_source = reflectance_rasters[year]
    index_sources = index_rasters.get(year, {})
    raster_catalog[year] = {"reflectance": reflectance_source, **index_sources}
    if year not in standard_samples_by_year:
        raise FileNotFoundError(f"Sampel standar tahun {year} tidak tersedia.")
    sample_gdf = standard_samples_by_year[year]
    if sample_gdf.empty:
        raise ValueError(f"Sampel standar tahun {year} kosong.")
    if sample_gdf.crs is None:
        raise ValueError(f"CRS sampel standar tahun {year} tidak tersedia.")
    expected_columns = ["sample_id", "year", "sample_type", "class_id", "class_name", "geometry"]
    missing_columns = [column_name for column_name in expected_columns if column_name not in sample_gdf.columns]
    if missing_columns:
        raise KeyError(f"Kolom sampel tahun {year} belum lengkap: " f"{missing_columns}")
    if not sample_gdf.geometry.geom_type.eq("Point").all():
        invalid_types = (sample_gdf.geometry.geom_type .value_counts(dropna=False) .to_dict())
        raise ValueError(f"Geometri sampel standar tahun {year} " f"bukan seluruhnya Point: {invalid_types}. " "Jalankan Cell Sebelumnya.")
    reflectance_result = sample_raster_values(raster_source=reflectance_source, point_gdf=sample_gdf, band_numbers=[1, 2, 3, 4, 5, 6])
    reflectance_values = (reflectance_result["values"])
    reflectance_inside_mask = (reflectance_result["inside_mask"])
    reflectance_profile = (reflectance_result["profile"])
    if reflectance_values.shape[1] != 6:
        raise ValueError(f"Raster reflectance tahun {year} " "tidak memiliki enam band.")
    raster_profiles[year] = reflectance_profile
    feature_df = pd.DataFrame({"sample_id": (sample_gdf["sample_id"].astype(str)), "year": int(year), "sample_type": (sample_gdf["sample_type"].astype(str)), "class_id": (sample_gdf["class_id"].astype(int)), "class_name": (sample_gdf["class_name"].astype(str)), "longitude": (sample_gdf.geometry.x), "latitude": (sample_gdf.geometry.y), "inside_reflectance_raster": (reflectance_inside_mask)})
    for feature_position, feature_name in enumerate(SPECTRAL_FEATURES):
        feature_df[feature_name] = (reflectance_values[:, feature_position])
    for index_name, index_source in (index_sources.items()):
        if not grids_are_equal(reflectance_profile, index_source.profile):
            raise ValueError(f"Grid raster {index_name.upper()} " f"tahun {year} berbeda dari reflectance.")
        index_result = sample_raster_values(raster_source=index_source, point_gdf=sample_gdf, band_numbers=1)
        index_values = (index_result["values"] .reshape(-1))
        feature_df[index_name] = index_values
    feature_df["spectral_valid"] = np.all(np.isfinite(feature_df[SPECTRAL_FEATURES] .to_numpy(dtype="float64")), axis=1)
    outside_mask = (~feature_df["inside_reflectance_raster"])
    invalid_spectral_mask = (feature_df["inside_reflectance_raster"] & ~feature_df["spectral_valid"])
    for row_index in feature_df.index[outside_mask]:
        outside_raster_records.append({"Tahun": year, "Sample ID": (feature_df.loc[row_index, "sample_id"]), "Jenis Sampel": (feature_df.loc[row_index, "sample_type"]), "Kelas": (feature_df.loc[row_index, "class_name"]), "Masalah": "Titik di luar batas raster"})
    for row_index in feature_df.index[invalid_spectral_mask]:
        outside_raster_records.append({"Tahun": year, "Sample ID": (feature_df.loc[row_index, "sample_id"]), "Jenis Sampel": (feature_df.loc[row_index, "sample_type"]), "Kelas": (feature_df.loc[row_index, "class_name"]), "Masalah": "Nilai band spektral tidak valid"})
    valid_feature_df = (feature_df[feature_df["inside_reflectance_raster"] & feature_df["spectral_valid"]] .copy() .reset_index(drop=True))
    if valid_feature_df.empty:
        raise ValueError(f"Tidak ada sampel valid pada raster tahun {year}.")
    training_df = (valid_feature_df[valid_feature_df["sample_type"] == "training"] .copy() .reset_index(drop=True))
    validation_df = (valid_feature_df[valid_feature_df["sample_type"] == "validation"] .copy() .reset_index(drop=True))
    if training_df.empty:
        raise ValueError(f"Data training tahun {year} kosong.")
    if validation_df.empty:
        raise ValueError(f"Data validation tahun {year} kosong.")
    expected_class_set = {1, 2, 3, 4}
    training_class_set = set(training_df["class_id"].unique())
    validation_class_set = set(validation_df["class_id"].unique())
    if training_class_set != expected_class_set:
        raise ValueError(f"Training tahun {year} belum mencakup " f"seluruh kelas: {training_class_set}")
    if validation_class_set != expected_class_set:
        raise ValueError(f"Validation tahun {year} belum mencakup " f"seluruh kelas: {validation_class_set}")
# Pemeriksaan koordinat yang sama antara training dan validation.
    training_coordinate_set = set(zip(training_df["longitude"].round(8), training_df["latitude"].round(8)))
    validation_coordinate_set = set(zip(validation_df["longitude"].round(8), validation_df["latitude"].round(8)))
    overlapping_coordinates = (training_coordinate_set & validation_coordinate_set)
    if overlapping_coordinates:
        raise ValueError(f"Ditemukan {len(overlapping_coordinates)} koordinat " f"yang sama pada training dan validation tahun {year}. " "Pisahkan titik tersebut agar tidak terjadi data leakage.")
    sample_feature_tables[year] = valid_feature_df
    training_tables[year] = training_df
    validation_tables[year] = validation_df
    sample_extraction_records.append({"Tahun": year, "Jumlah Sampel Input": int(len(feature_df)), "Di Dalam Raster": int(reflectance_inside_mask.sum()), "Di Luar Raster": int((~reflectance_inside_mask).sum()), "Nilai Spektral Valid": int(feature_df["spectral_valid"].sum()), "Jumlah Training Valid": int(len(training_df)), "Jumlah Validation Valid": int(len(validation_df))})
    for sample_type, sample_table in [("training", training_df), ("validation", validation_df)]:
        for class_id in [1, 2, 3, 4]:
            sample_count = int((sample_table["class_id"] == class_id).sum())
            sample_class_count_records.append({"Tahun": year, "Jenis Sampel": sample_type, "ID Kelas": class_id, "Kelas": CLASS_NAMES[class_id], "Jumlah Titik Valid": (sample_count)})
# Tabel ringkasan
sample_extraction_summary_df = pd.DataFrame(sample_extraction_records)
sample_valid_class_count_df = pd.DataFrame(sample_class_count_records)
outside_raster_df = pd.DataFrame(outside_raster_records, columns=["Tahun", "Sample ID", "Jenis Sampel", "Kelas", "Masalah"])
print("\n" + "=" * 78)
print("EKSTRAKSI SELESAI")
print("=" * 78)
```

### c. Perbandingan indeks dan uji akurasi
Membandingkan kinerja skenario band spektral dan kombinasi indeks serta mencari indeks terbaik dalam pengamatan mangrove dari hasil pengolahan

```{code-cell} ipython3
# Validasi jumlah sampel
min_train_per_class = 10
min_valid_per_class = 5

print(f"Training tables: {list(training_tables.keys())}")
print(f"Validation tables: {list(validation_tables.keys())}")

for year in ANALYSIS_YEARS:
    if year not in training_tables or year not in validation_tables:
        print(f"Peringatan: Data {year} tidak tersedia")
        continue
    train_df = training_tables[year]
    valid_df = validation_tables[year]

    for cid in CLASS_IDS:
        train_count = (train_df["class_id"] == cid).sum()
        valid_count = (valid_df["class_id"] == cid).sum()

        if train_count < min_train_per_class:
            print(f"Peringatan: Training {CLASS_NAMES[cid]} tahun {year}: {train_count} < {min_train_per_class}")
        if valid_count < min_valid_per_class:
            print(f"Peringatan: Validation {CLASS_NAMES[cid]} tahun {year}: {valid_count} < {min_valid_per_class}")

# Skenario model Random Forest
RF_SCENARIOS = {
    "BAND_ONLY": SPECTRAL_FEATURES,
    "BAND_NDVI": SPECTRAL_FEATURES + ["ndvi"],
    "BAND_ALL": SPECTRAL_FEATURES + INDEX_NAMES
}

RF_LABELS = {
    "BAND_ONLY": "Band Spektral",
    "BAND_NDVI": "Band + NDVI",
    "BAND_ALL": "Band + Semua Indeks"
}

# Simpan model dan hasil
perf_records = []
class_acc_records = []
feat_imp_records = []
model_packages = {}

# Latih dan validasi model
for year in ANALYSIS_YEARS:
    if year not in training_tables:
        print(f"Skip {year}: tidak ada training data")
        continue

    model_packages[year] = {}
    train_df = training_tables[year].copy()
    valid_df = validation_tables[year].copy()

    if train_df.empty or valid_df.empty:
        print(f"Skip {year}: training atau validation kosong")
        continue

    y_train = train_df["class_id"].to_numpy(dtype="int64")
    y_valid = valid_df["class_id"].to_numpy(dtype="int64")

    for scenario, features in RF_SCENARIOS.items():
        # Siapkan data
        X_train = train_df[features].fillna(train_df[features].median()).astype("float32")
        X_valid = valid_df[features].fillna(train_df[features].median()).astype("float32")

        # Latih model
        rf = RandomForestClassifier(n_estimators=500, criterion="gini", max_features="sqrt", 
                                   min_samples_leaf=2, class_weight="balanced_subsample", 
                                   oob_score=True, random_state=RANDOM_STATE, n_jobs=-1)
        rf.fit(X_train, y_train)

        # Prediksi
        y_pred = rf.predict(X_valid)

        # Hitung metrik
        acc = accuracy_score(y_valid, y_pred)
        kappa = cohen_kappa_score(y_valid, y_pred)
        f1 = f1_score(y_valid, y_pred, average="macro", zero_division=0)

        # Simpan hasil
        perf_records.append({
            "Tahun": year,
            "Skenario": scenario,
            "Model": RF_LABELS[scenario],
            "Overall Accuracy": float(acc),
            "Kappa": float(kappa),
            "Macro F1": float(f1),
            "OOB Score": float(rf.oob_score_),
            "Training": len(train_df),
            "Validation": len(valid_df)
        })

        # Feature importance
        for feat, imp in zip(features, rf.feature_importances_):
            feat_imp_records.append({
                "Tahun": year,
                "Skenario": scenario,
                "Fitur": feat,
                "Importance": float(imp)
            })

        # Per-class metrics
        cm = confusion_matrix(y_valid, y_pred, labels=CLASS_IDS)
        for i, cid in enumerate(CLASS_IDS):
            tp = cm[i, i]
            fn = cm[i, :].sum() - tp
            fp = cm[:, i].sum() - tp

            precision = tp / (tp + fp) if (tp + fp) > 0 else 0
            recall = tp / (tp + fn) if (tp + fn) > 0 else 0
            f1_cls = 2 * (precision * recall) / (precision + recall) if (precision + recall) > 0 else 0

            class_acc_records.append({
                "Tahun": year,
                "Skenario": scenario,
                "Kelas": CLASS_NAMES[cid],
                "Precision": float(precision),
                "Recall": float(recall),
                "F1": float(f1_cls),
                "Support": int(cm[i, :].sum())
            })

        # Simpan model (di memori)
        model_pkg = {
            "model": rf,
            "features": list(features),
            "medians": X_train.median().to_dict(),
            "scenario": scenario
        }
        model_packages[year][scenario] = model_pkg

# Simpan hasil
if perf_records:
    perf_df = pd.DataFrame(perf_records).sort_values(["Tahun", "Macro F1"], ascending=[True, False])
    class_acc_df = pd.DataFrame(class_acc_records) if class_acc_records else pd.DataFrame()
    feat_imp_df = pd.DataFrame(feat_imp_records) if feat_imp_records else pd.DataFrame()

    print("HASIL TRAINING MODEL RANDOM FOREST")
    print("=" * 103)
    print(perf_df.to_string(index=False, float_format=lambda x: f"{x:.4f}"))
    print("=" * 103)
else:
    print("Peringatan: Tidak ada data untuk training model")
```

### d. Random forest
Model Random Forest digunakan untuk klasifikasi tutupan lahan tahun 2019 dan 2025.

```{code-cell} ipython3
# Tentukan model terbaik jika belum ditentukan
if 'BEST_INDEX_SCENARIO' not in locals() and perf_records:
    perf_df_temp = pd.DataFrame(perf_records).sort_values(["Tahun", "Macro F1"], ascending=[True, False])
    best_row = perf_df_temp.loc[perf_df_temp.groupby("Tahun")["Macro F1"].idxmax()].iloc[0]
    BEST_INDEX_SCENARIO = best_row["Skenario"]
    BEST_INDEX_NAME = best_row["Model"]
    print(f"Model terbaik (dari perf_records): {BEST_INDEX_SCENARIO} ({BEST_INDEX_NAME})")
elif 'BEST_INDEX_SCENARIO' not in locals():
    BEST_INDEX_SCENARIO = list(model_packages[ANALYSIS_YEARS[0]].keys())[0] if model_packages else "BAND_ONLY"
    BEST_INDEX_NAME = "Model Default"
    print(f"Menggunakan model default: {BEST_INDEX_SCENARIO}")

RF_CLASS_COLORS_HEX = {1: "#006400", 2: "#D2691E", 3: "#7CB342", 4: "#1565C0"}
PREDICTION_CHUNK_SIZE = 150000

def read_float_band(source, band_number):
    """Baca band raster dan set nodata ke NaN."""
    array = source.read(band_number).astype("float32")
    if source.nodata is not None:
        array[np.isclose(array, float(source.nodata))] = np.nan
    array[~np.isfinite(array)] = np.nan
    return array

def stretch_channel(array, low_percentile=2, high_percentile=98):
    """Normalisasi channel 0-1 dengan percentile clipping."""
    valid_mask = np.isfinite(array)
    if not valid_mask.any():
        return np.zeros_like(array, dtype="float32")
    valid_values = array[valid_mask]
    vmin = float(np.percentile(valid_values, low_percentile))
    vmax = float(np.percentile(valid_values, high_percentile))
    if vmax <= vmin:
        vmax = vmin + 1e-6
    output = np.zeros_like(array, dtype="float32")
    output[valid_mask] = np.clip((array[valid_mask] - vmin) / (vmax - vmin), 0, 1)
    return output

# Storage untuk hasil klasifikasi
rf_classification_maps = {}
rf_rgb_maps = {}

# Validasi data sebelum klasifikasi
if not model_packages:
    print("Error: Tidak ada model yang dilatih. Jalankan sel training model terlebih dahulu.")
    print("model_packages kosong, tidak bisa melanjutkan klasifikasi.")
else:
    print(f"Model tersedia untuk tahun: {list(model_packages.keys())}")
    print(f"Skenario tersedia: {list(model_packages[ANALYSIS_YEARS[0]].keys()) if ANALYSIS_YEARS else 'Tidak ada'}")

# Klasifikasi setiap tahun
for year in ANALYSIS_YEARS:
    if year not in model_packages or not model_packages[year]:
        print(f"Skip {year}: Tidak ada model trained untuk tahun ini")
        continue

    if BEST_INDEX_SCENARIO not in model_packages[year]:
        print(f"Skip {year}: Skenario {BEST_INDEX_SCENARIO} tidak tersedia, gunakan {list(model_packages[year].keys())[0]}")
        BEST_INDEX_SCENARIO = list(model_packages[year].keys())[0]

    model_pkg = model_packages[year][BEST_INDEX_SCENARIO]
    model, selected_features, feature_medians = model_pkg["model"], model_pkg["features"], model_pkg["medians"]

    # Baca reflectance (dari raster di memori)
    refl_src = raster_catalog[year]["reflectance"]
    raster_profile, transform, crs = refl_src.profile.copy(), refl_src.transform, refl_src.crs
    height, width, bounds = refl_src.height, refl_src.width, refl_src.bounds
    spec_arrays = {band: read_float_band(refl_src, i+1) for i, band in enumerate(["blue", "green", "red", "nir08", "swir16", "swir22"])}

    # Baca indeks (dari raster di memori)
    idx_arrays = {}
    for feat in selected_features:
        if feat not in INDEX_FEATURES:
            continue
        idx_src = raster_catalog[year][feat]
        if not (idx_src.width == width and idx_src.height == height and idx_src.crs == crs):
            raise ValueError(f"Grid {feat.upper()} {year} berbeda dari reflectance")
        idx_arrays[feat] = read_float_band(idx_src, 1)

    # Siapkan fitur stack
    feat_arrays = []
    for feat in selected_features:
        if feat in spec_arrays:
            feat_arr = spec_arrays[feat].copy()
        elif feat in idx_arrays:
            feat_arr = idx_arrays[feat].copy()
            feat_arr[~np.isfinite(feat_arr)] = float(feature_medians[feat])
        else:
            raise KeyError(f"Fitur {feat} tidak tersedia")
        feat_arrays.append(feat_arr)

    feat_stack = np.stack(feat_arrays, axis=-1).astype("float32")
    flat_feat = feat_stack.reshape(-1, len(selected_features))

    # Prediksi dengan chunking
    valid_mask = np.all(np.isfinite(flat_feat), axis=1)
    valid_idx = np.flatnonzero(valid_mask)
    class_flat = np.zeros(flat_feat.shape[0], dtype="uint8")

    for i in range(0, len(valid_idx), PREDICTION_CHUNK_SIZE):
        j = min(i + PREDICTION_CHUNK_SIZE, len(valid_idx))
        chunk_idx = valid_idx[i:j]
        class_flat[chunk_idx] = model.predict(flat_feat[chunk_idx]).astype("uint8")

    class_array = class_flat.reshape(height, width)
    rgb_image = np.dstack([stretch_channel(spec_arrays[c]) for c in ["red", "green", "blue"]])

    rf_classification_maps[year] = class_array
    rf_rgb_maps[year] = rgb_image
```

### e. Perhitungan luas
Mengurangi piksel-piksel terisolasi pada hasil klasifikasi serta menghitung jumlah piksel, luas, dan persentase setiap kelas tutupan lahan.

```{code-cell} ipython3
# Inisialisasi dictionary untuk hasil
rf_classification_filtered_maps = {}
rf_classification_profiles = {}

# Regularisasi: hapus piksel terisolasi
def regularize_classification(class_array, max_same=2, min_majority=6, iterations=2):
    """Hapus piksel terisolasi dengan majority filtering."""
    work = np.asarray(class_array, dtype="uint8").copy()
    valid = (work > 0)
    kernel = np.ones((3, 3), dtype="uint8")

    for _ in range(iterations):
        counts = np.stack([ndimage.convolve((work == cid).astype("uint8"), kernel, mode="constant") for cid in [1, 2, 3, 4]], axis=0)
        majority_class = np.take(np.asarray([1, 2, 3, 4], dtype="uint8"), np.argmax(counts, axis=0))

        # Ganti piksel terisolasi dengan kelas mayoritas
        mask = valid & (np.max(counts, axis=0) <= max_same) & (np.max(counts, axis=0) >= min_majority) & (majority_class != work)
        changed = np.count_nonzero(mask)
        work[mask] = majority_class[mask]
        if changed == 0:
            break
    return work

# Regularisasi setiap tahun dan hitung luas
class_area_records = []
reg_records = []

for year in ANALYSIS_YEARS:
    raw = rf_classification_maps[year].astype("uint8")
    final = regularize_classification(raw)
    rf_classification_filtered_maps[year] = final

    # Get raster profile from classification source (di memori)
    refl_src = raster_catalog[year]["reflectance"]
    bounds = refl_src.bounds
    prof = refl_src.profile.copy()
    transform = refl_src.transform

    rf_classification_profiles[year] = {"bounds": bounds, "profile": prof, "transform": transform}

    # Hitung perubahan
    valid_px = np.count_nonzero(raw > 0)
    changed_px = np.count_nonzero(raw != final)
    reg_records.append({
        "Tahun": year, 
        "Piksel Valid": int(valid_px), 
        "Piksel Diubah": int(changed_px), 
        "Persentase Diubah": (changed_px / valid_px * 100) if valid_px > 0 else np.nan
    })

    # Hitung luas per kelas
    px_ha = abs(transform.a * transform.e) / 10000
    total_classified = np.count_nonzero(final > 0)

    for cid in [1, 2, 3, 4]:
        px_count = np.count_nonzero(final == cid)
        class_area_records.append({
            "Tahun": year,
            "ID Kelas": cid,
            "Kelas": CLASS_NAMES[cid],
            "Jumlah Piksel": int(px_count),
            "Luas Hektare": float(px_count * px_ha),
            "Persentase Kelas": (px_count / total_classified * 100) if total_classified > 0 else np.nan
        })

# Simpan tabel luas
class_area_df = pd.DataFrame(class_area_records)
reg_df = pd.DataFrame(reg_records)

# Ringkasan antar tahun
pivot_df = class_area_df.pivot(index="Tahun", columns="Kelas", values="Luas Hektare").reset_index()
pivot_df = pivot_df[["Tahun"] + [c for c in ["Mangrove", "Non Vegetation", "Other Vegetation", "Water"] if c in pivot_df.columns]]
print("\nRINGKASAN LUAS ANTAR TAHUN")
print("=" * 80)
display(pivot_df.style.format({c: "{:,.2f}" for c in pivot_df.columns if c != "Tahun"}).set_properties(**{"text-align": "center"}))

# Peta sebaran final (1 kolom, N baris untuk 2 tahun)
class_cmap = ListedColormap([RF_CLASS_COLORS_HEX[c] for c in [1, 2, 3, 4]])
class_norm = BoundaryNorm([0.5, 1.5, 2.5, 3.5, 4.5], class_cmap.N)
class_legend = [plt.matplotlib.patches.Patch(facecolor=RF_CLASS_COLORS_HEX[c], edgecolor="black", label=CLASS_NAMES[c]) for c in [1, 2, 3, 4]]

years_list = sorted(rf_classification_filtered_maps.keys())
fig, axes = plt.subplots(len(years_list), 1, figsize=(12, 6*len(years_list)), dpi=140)
if len(years_list) == 1:
    axes = np.array([axes])

for row, year in enumerate(years_list):
    extent = [rf_classification_profiles[year]["bounds"].left, rf_classification_profiles[year]["bounds"].right, 
              rf_classification_profiles[year]["bounds"].bottom, rf_classification_profiles[year]["bounds"].top]
    axes[row].imshow(np.ma.masked_equal(rf_classification_filtered_maps[year], 0), cmap=class_cmap, norm=class_norm, extent=extent, origin="upper")
    mgr_area = float(class_area_df[(class_area_df["Tahun"] == year) & (class_area_df["ID Kelas"] == 1)]["Luas Hektare"].iloc[0])
    axes[row].set_title(f"Tahun {year}", fontsize=13)
    axes[row].set_xlabel("Easting (m)")
    axes[row].set_ylabel("Northing (m)")
    axes[row].ticklabel_format(style="plain", axis="both", useOffset=False)

fig.legend(handles=class_legend, loc="lower center", ncol=4, bbox_to_anchor=(0.5, -0.02), frameon=True)
fig.tight_layout(rect=[0, 0.05, 1, 0.96])
plt.show()
plt.close(fig)
```

## 4. Klasifikasi kerapatan mangrove
Pad tahap ini, area yang  yang teridentifikasi sebagai mangrove dikelaskan berdasarkan rentang nilai NDVI
1. Mangrove Jarang
2. Mangrove Sedang
3. Mangrove Rapat

Untuk kelas lainnya ditetapkan sebagai Non Mangrove

+++

### a. Klasifikasi

```{code-cell} ipython3
# Konstanta kerapatan mangrove
DENSITY_NAMES = {1: "Non Mangrove", 2: "Mangrove Jarang", 3: "Mangrove Sedang", 4: "Mangrove Rapat"}
DENSITY_COLORS_HEX = {1: "#D9D9D9", 2: "#FFFFB2", 3: "#78C679", 4: "#006837"}

# NDVI threshold untuk kerapatan
NDVI_SPARSE_MAX = 0.32
NDVI_MODERATE_MIN, NDVI_MODERATE_MAX = 0.33, 0.42
NDVI_DENSE_MIN = 0.43

# Storage hasil
mangrove_density_maps = {}
mangrove_density_ndvi_maps = {}
density_area_records = []
density_qc_records = []

# Klasifikasi kerapatan setiap tahun
for year in ANALYSIS_YEARS:
    # Baca data (dari raster di memori)
    ndvi_src = raster_catalog[year]["ndvi"]
    final_class = rf_classification_filtered_maps[year].astype("uint8")
    prof_info = rf_classification_profiles[year]

    if not (ndvi_src.width == final_class.shape[1] and ndvi_src.height == final_class.shape[0]):
        raise ValueError(f"Grid NDVI {year} berbeda dengan klasifikasi")
    ndvi = ndvi_src.read(1).astype("float32")
    if ndvi_src.nodata is not None:
        ndvi[np.isclose(ndvi, float(ndvi_src.nodata))] = np.nan

    ndvi[~np.isfinite(ndvi)] = np.nan
    ndvi_rounded = np.round(ndvi, 2)

    # Mask untuk klasifikasi
    valid_class = (final_class > 0)
    valid_ndvi = np.isfinite(ndvi_rounded)
    is_mangrove = (final_class == 1)
    valid_mgr = (is_mangrove & valid_ndvi)

    # Buat map kerapatan
    density = np.zeros_like(final_class)
    density[valid_class & (final_class != 1)] = 1  # Non Mangrove
    density[valid_mgr & (ndvi_rounded <= NDVI_SPARSE_MAX)] = 2  # Jarang
    density[valid_mgr & (ndvi_rounded >= NDVI_MODERATE_MIN) & (ndvi_rounded <= NDVI_MODERATE_MAX)] = 3  # Sedang
    density[valid_mgr & (ndvi_rounded >= NDVI_DENSE_MIN)] = 4  # Rapat

    # Validasi
    uncl = np.count_nonzero(valid_mgr & (density == 0))
    if uncl > 0:
        raise ValueError(f"{uncl:,} piksel mangrove {year} tidak terklasifikasi")

    mangrove_density_maps[year] = density
    mangrove_density_ndvi_maps[year] = ndvi

    # Hitung luas
    px_ha = abs(prof_info["transform"].a * prof_info["transform"].e) / 10000
    total_mapped = np.count_nonzero(density > 0)
    total_mgr = np.count_nonzero(np.isin(density, [2, 3, 4]))

    for did in [1, 2, 3, 4]:
        px_cnt = np.count_nonzero(density == did)
        pct_area = (px_cnt / total_mapped * 100) if total_mapped > 0 else np.nan
        pct_mgr = (px_cnt / total_mgr * 100) if (total_mgr > 0 and did > 1) else np.nan

        density_area_records.append({
            "Tahun": year,
            "ID Kerapatan": did,
            "Kelas Kerapatan": DENSITY_NAMES[did],
            "Jumlah Piksel": int(px_cnt),
            "Luas Hektare": float(px_cnt * px_ha),
            "Persentase Area": float(pct_area) if not np.isnan(pct_area) else np.nan,
            "Persentase Mangrove": float(pct_mgr) if not np.isnan(pct_mgr) else np.nan
        })

    # QC
    density_qc_records.append({
        "Tahun": year,
        "Piksel Mangrove RF": int(np.count_nonzero(is_mangrove)),
        "NDVI Valid": int(np.count_nonzero(valid_mgr)),
        "NDVI Tidak Valid": int(np.count_nonzero(is_mangrove & ~valid_ndvi)),
        "Jarang": int(np.count_nonzero(density == 2)),
        "Sedang": int(np.count_nonzero(density == 3)),
        "Rapat": int(np.count_nonzero(density == 4))
    })

# Simpan tabel
density_df = pd.DataFrame(density_area_records)
qc_df = pd.DataFrame(density_qc_records)

# Tampilkan QC
print("\nQC NDVI KERAPATAN MANGROVE")
print("=" * 80)
display(qc_df.style.hide(axis="index").format({c: "{:,.0f}" for c in qc_df.columns if c != "Tahun"}))
```

### b. Peta kerapatan mangrove
Menampilkan sebaran spasial kelas kerapatan mangrove pada setiap tahun serta menyajikan luas masing-masing kelas kerapatan.

```{code-cell} ipython3
# Peta kerapatan multitemporal
density_colormap = plt.matplotlib.colors.ListedColormap([DENSITY_COLORS_HEX[1], DENSITY_COLORS_HEX[2], DENSITY_COLORS_HEX[3], DENSITY_COLORS_HEX[4]])
density_colormap.set_bad(color="white")
density_norm = plt.matplotlib.colors.BoundaryNorm([0.5, 1.5, 2.5, 3.5, 4.5], density_colormap.N)
density_legend = [plt.matplotlib.patches.Patch(facecolor=DENSITY_COLORS_HEX[density_id], edgecolor="black", label=DENSITY_NAMES[density_id]) for density_id in [1, 2, 3, 4]]
available_years = sorted(mangrove_density_maps.keys())
figure, axes = plt.subplots(nrows=1, ncols=len(available_years), figsize=(14, 6), dpi=140)
if len(available_years) == 1:
    axes = np.array([axes])

for panel_position, year in enumerate(available_years):
    axis = axes[panel_position]
    bounds = rf_classification_profiles[year]["bounds"]
    extent = (bounds.left, bounds.right, bounds.bottom, bounds.top)
    axis.imshow(np.ma.masked_equal(mangrove_density_maps[year], 0), cmap=density_colormap, norm=density_norm, extent=extent, origin="upper", interpolation="nearest")
    mgr_total = float(density_df.loc[(density_df["Tahun"] == year) & (density_df["ID Kerapatan"].isin([2, 3, 4])), "Luas Hektare"].sum())
    axis.set_title((f"Tahun {year}"), fontsize=14, fontweight="bold")
    axis.set_xlabel("Easting (m)")
    axis.set_ylabel("Northing (m)")
    axis.ticklabel_format(style="plain", axis="both", useOffset=False)
figure.suptitle("Peta Kerapatan Mangrove", fontsize=18, fontweight="bold", y=0.99)
figure.legend(handles=density_legend, loc="lower center", ncol=4, bbox_to_anchor=(0.5, 0.015), frameon=True)
figure.tight_layout(rect=[0, 0.06, 1, 0.95])
plt.show()
plt.close(figure)
# Grafik luas kelas kerapatan mangrove
mangrove_only_density_df = (density_df[density_df["ID Kerapatan"].isin([2, 3, 4])].copy())
density_pivot_df = (mangrove_only_density_df.pivot(index="Tahun", columns="ID Kerapatan", values="Luas Hektare").sort_index())
for density_id in [2, 3, 4]:
    if density_id not in density_pivot_df.columns:
        density_pivot_df[density_id] = 0.0
density_pivot_df = density_pivot_df[[2, 3, 4]]
years = density_pivot_df.index.astype(int).tolist()
bar_positions = np.arange(len(years))
bar_width = 0.24
density_bar_figure, density_bar_axis = plt.subplots(figsize=(12, 7), dpi=140)
for position, density_id in enumerate([2, 3, 4]):
    horizontal_offset = (position - 1) * bar_width
    density_bar_axis.bar(bar_positions + horizontal_offset, density_pivot_df[density_id].to_numpy(dtype="float64"), width=bar_width, label=DENSITY_NAMES[density_id], 
                         color=DENSITY_COLORS_HEX[density_id])
density_bar_axis.set_title("Luas Kelas Kerapatan Mangrove", fontsize=15, fontweight="bold", pad=12)
density_bar_axis.set_xlabel("Tahun")
density_bar_axis.set_ylabel("Luas (ha)")
density_bar_axis.set_xticks(bar_positions)
density_bar_axis.set_xticklabels(years)
density_bar_axis.grid(axis="y", alpha=0.25)
density_bar_axis.legend(frameon=True)
density_bar_figure.tight_layout()
plt.show()
plt.close(density_bar_figure)
```

## 5. Analisis perubahan mangrove
Analisis dilakukan terhadap hasil klasifikasi antarperiode dengan memperhatikan dinamika perubahan mangrove secara spasial dan temporal yang difokuskan menjadi 3 kelas utama 
1. Mangrove Tetap
2. Mangrove Menjadi Non Mangrove
3. Non Mangrove Menjadi Mangrove

+++

### a. Perhitungan

```{code-cell} ipython3
# Analisis dinamika: hanya 2019 → 2025
CHANGE_PERIOD = (2019, 2025)
DYNAMICS_NAMES = {1: "Mangrove Tetap", 2: "Mangrove → Non Mangrove", 3: "Non Mangrove → Mangrove"}
DYNAMICS_COLORS_HEX = {1: "#006837", 2: "#D7191C", 3: "#FFD92F"}

# Hitung dinamika
start_year, end_year = CHANGE_PERIOD
start_arr = rf_classification_filtered_maps[start_year].astype("uint8")
end_arr = rf_classification_filtered_maps[end_year].astype("uint8")

if start_arr.shape != end_arr.shape:
    raise ValueError(f"Ukuran raster {start_year} dan {end_year} berbeda")

# Buat map dinamika
dynamics_arr = np.zeros_like(start_arr)
dynamics_arr[(start_arr == 1) & (end_arr == 1)] = 1  # Tetap
dynamics_arr[(start_arr == 1) & (end_arr != 1) & (end_arr > 0)] = 2  # Loss
dynamics_arr[(start_arr != 1) & (start_arr > 0) & (end_arr == 1)] = 3  # Gain

# Hitung luas transisi
prof_info = rf_classification_profiles[start_year]
px_ha = abs(prof_info["transform"].a * prof_info["transform"].e) / 10000

trans_records = []
for start_cid in [1, 2, 3, 4]:
    for end_cid in [1, 2, 3, 4]:
        px_cnt = np.count_nonzero((start_arr == start_cid) & (end_arr == end_cid))
        if px_cnt > 0:
            trans_records.append({
                "Tahun Awal": start_year,
                "Tahun Akhir": end_year,
                "Kelas Awal": CLASS_NAMES[start_cid],
                "Kelas Akhir": CLASS_NAMES[end_cid],
                "Jumlah Piksel": int(px_cnt),
                "Luas Hektare": float(px_cnt * px_ha)
            })

# Ringkasan dinamika mangrove
mgr_start = np.count_nonzero(start_arr == 1)
mgr_end = np.count_nonzero(end_arr == 1)
stable = np.count_nonzero(dynamics_arr == 1)
loss = np.count_nonzero(dynamics_arr == 2)
gain = np.count_nonzero(dynamics_arr == 3)

change_record = {
    "Periode": f"{start_year}–{end_year}",
    "Mangrove Awal (ha)": float(mgr_start * px_ha),
    "Mangrove Akhir (ha)": float(mgr_end * px_ha),
    "Tetap (ha)": float(stable * px_ha),
    "Hilang (ha)": float(loss * px_ha),
    "Bertambah (ha)": float(gain * px_ha),
    "Perubahan Bersih (ha)": float((gain - loss) * px_ha)
}

trans_df = pd.DataFrame(trans_records)
change_df = pd.DataFrame([change_record])

# Tampilkan ringkasan
print("\nRINGKASAN DINAMIKA MANGROVE")
print("=" * 90)
display(change_df.style.hide(axis="index").format({c: "{:,.2f}" for c in change_df.columns if c != "Periode"}))

# Tabel perbandingan luas 4 kelas tutupan lahan
print("\nPERBANDINGAN LUAS 4 KELAS TUTUPAN LAHAN")
print("=" * 90)
class_2019 = class_area_df[class_area_df["Tahun"] == 2019][["Kelas", "Luas Hektare"]].set_index("Kelas")
class_2025 = class_area_df[class_area_df["Tahun"] == 2025][["Kelas", "Luas Hektare"]].set_index("Kelas")
class_2025.columns = ["Luas Hektare 2025"]
class_2019.columns = ["Luas Hektare 2019"]
comparison_df = class_2019.join(class_2025, how="outer").reset_index()
comparison_df["Perubahan (ha)"] = comparison_df["Luas Hektare 2025"] - comparison_df["Luas Hektare 2019"]
comparison_df["Perubahan (%)"] = (comparison_df["Perubahan (ha)"] / comparison_df["Luas Hektare 2019"] * 100)
display(comparison_df.style.hide(axis="index").format({"Luas Hektare 2019": "{:,.2f}", "Luas Hektare 2025": "{:,.2f}", "Perubahan (ha)": "{:+,.2f}", "Perubahan (%)": "{:+.2f}%"}))
```

### b. Visualisasi peta perubahan mangrove
Menampilkan peta dinamika mangrove setiap periode dan grafik perubahan luas seluruh kelas tutupan lahan sebagai dasar analisis spasio-temporal.

```{code-cell} ipython3
# Visualisasi dinamika
# Map dinamika
dyn_cmap = ListedColormap([DYNAMICS_COLORS_HEX[c] for c in [1, 2, 3]])
dyn_norm = BoundaryNorm([0.5, 1.5, 2.5, 3.5], dyn_cmap.N)
dyn_legend = [plt.matplotlib.patches.Patch(facecolor=DYNAMICS_COLORS_HEX[c], edgecolor="black", label=DYNAMICS_NAMES[c]) for c in [1, 2, 3]]

fig, ax = plt.subplots(1, 1, figsize=(12, 10), dpi=140)
bounds = rf_classification_profiles[start_year]["bounds"]
extent = [bounds.left, bounds.right, bounds.bottom, bounds.top]
ax.imshow(np.ma.masked_equal(dynamics_arr, 0), cmap=dyn_cmap, norm=dyn_norm, extent=extent, origin="upper")
ax.set_title(f"Dinamika Mangrove {start_year}–{end_year}\nGain: {gain * px_ha:,.2f} ha | Loss: {loss * px_ha:,.2f} ha | Net: {(gain - loss) * px_ha:+,.2f} ha", fontsize=13, fontweight="bold")
ax.set_xlabel("Easting (m)")
ax.set_ylabel("Northing (m)")
ax.ticklabel_format(style="plain", axis="both", useOffset=False)

fig.legend(handles=dyn_legend, loc="lower center", ncol=3, bbox_to_anchor=(0.5, -0.02), frameon=True)
fig.tight_layout(rect=[0, 0.05, 1, 0.95])
plt.show()
plt.close(fig)

# Grafik tren luas 4 kelas
trend_pivot = class_area_df.pivot(index="Tahun", columns="Kelas", values="Luas Hektare")[["Mangrove", "Non Vegetation", "Other Vegetation", "Water"]]

fig, ax = plt.subplots(figsize=(11, 6), dpi=140)
years = trend_pivot.index.astype(int).to_numpy()
for kelas in ["Mangrove", "Non Vegetation", "Other Vegetation", "Water"]:
    cid = list(CLASS_NAMES.values()).index(kelas) + 1
    vals = trend_pivot[kelas].to_numpy()
    ax.plot(years, vals, marker="o", linewidth=2.5, markersize=8, label=kelas, color=RF_CLASS_COLORS_HEX[cid])
    for y, v in zip(years, vals):
        ax.annotate(f"{v:,.0f}", (y, v), xytext=(0, 8), textcoords="offset points", ha="center", fontsize=9)

ax.set_title("Tren Luas 4 Kelas Tutupan Lahan 2019–2025", fontsize=14, fontweight="bold")
ax.set_xlabel("Tahun")
ax.set_ylabel("Luas (ha)")
ax.set_xticks(years)
ax.ticklabel_format(style="plain", axis="y", useOffset=False)
ax.grid(alpha=0.3)
ax.legend(title="Kelas", frameon=True, ncol=2)
fig.tight_layout()
plt.show()
plt.close(fig)

# Tampilkan tabel
print("\nTABEL LUAS TREN KELAS")
print("=" * 80)
display(trend_pivot.reset_index().style.hide(axis="index").format({c: "{:,.2f}" for c in trend_pivot.columns}))
```

### c. Matriks Konfusi
Dilakukan untuk mengetahui dan menguji akurasi dari hasil kinerja metode yang digunakan, dan tingkat kecocokan antar metode.

```{code-cell} ipython3
# Akurasi model: Overall Accuracy dan Kappa
print("\nRINGKASAN AKURASI MODEL")
print("=" * 80)

if perf_records:
    acc_df = pd.DataFrame(perf_records)[["Tahun", "Skenario", "Model", "Overall Accuracy", "Kappa", "Training", "Validation"]]
    display(acc_df.style.hide(axis="index").format({
        "Overall Accuracy": "{:.4f}",
        "Kappa": "{:.4f}",
        "Training": "{:,}",
        "Validation": "{:,}"
    }))
else:
    print("Tidak ada data akurasi tersedia")
print("=" * 80)
```

# Catatan
Modul ini telah menunjukkan proses klasifikasi kerapatan mangrove di Segara Anakan. Metode yang digunakan menggunakan Indeks Spektral dan Machine Learning (Random Forest). Tren perubahan luasan mangrove telah diidentifikasi dari tahun 2019 ke tahun 2025.

+++

# Info

- Skrip ini dikembangkan oleh **Nur Afrizal Maulana** [nurafrizalmaulana@students.undip.ac.id](mailto:nurafrizalmaulana@students.undip.ac.id)
- Jika ada pertanyaan atau komentar, silahkan email ke piksel@big.go.id
- **Lisensi:** Skrip dalam notebook ini dilisensikan berdasarkan [Apache License, Version 2.0](https://www.apache.org/licenses/LICENSE-2.0). 
Data Piksel dilisensikan berdasarkan lisensi [Creative Commons by Attribution 4.0](https://creativecommons.org/licenses/by/4.0/).

```{code-cell} ipython3

```
