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

| <h1><b>Perubahan Garis Pantai</b></h1> | ![](files/piksel_logo_small.png) |
|:---------|----------:|
- **Data:** Landsat
- **Lokasi:** Pulau Makora, Kab. Nias Utara, Prov. Sumatera Utara
- **Metode:** Analisis multi temporal
- **Data lain:** model pasang surut di `files/tide_models`

+++

# Pendahuluan
Modul ini bertujuan untuk menampilkan hasil analisis perubahan garis pantai. Data yang diperlukan adalah:
1. Data citra satelit Landsat dalam beberapa tahun
2. Model pasang surut, yang digunakan untuk anotasi pada citra berupa informasi ketinggian muka air laut, serta untuk memilih area yang berada di tengah kisaran pasang surut, sehingga dapat ditetapkan garis pantai rata-rata.

Lokasi yang digunakan sebagai contoh adalah di Pulau Makora, Kab. Nias Utara, Prov. Sumatera Utara [🔗](https://maps.app.goo.gl/Nb3C8ZjF8X62wbJy8)

+++

# Tahapan

Tahapan dalam analisis perubahan garis pantai adalah sebagai berikut:
1. Persiapan
2. Menentukan wilayah
3. Memuat data
4. Membuat mask
5. Memisahkan daratan dan lautan
6. Ekstraksi data
7. Menampilkan dan menyimpan hasil
***

+++

## 1. Persiapan
Termasuk dalam tahap awal ini adalah memuat library dan mempersiapkan akses data. Berikut adalah beberapa library yang dimuat.

```{code-cell} ipython3
import os

from coastlines.utils import extract_contours, tide_cutoffs
from coastlines.vector import annual_movements, calculate_regressions
from dask.distributed import Client
from datacube import Datacube
from datacube.utils.masking import create_mask_value, valid_data_mask
from dea_tools.spatial import points_on_line
from eo_tides import pixel_tides
from eo_tides.utils import list_models
from ipyleaflet import basemaps
from odc.geo.geom import point
from odc.stac import configure_s3_access
from piksel.utils import patch_usgs_landsat
```

Berikutnya disiapkan akses data Landsat melalui Element-84 STAC API. Fungsi `configure_s3_access` digunakan untuk akses data Landsat di USGS. Dask digunakan untuk melakukan perhitungan secara paralel.

```{code-cell} ipython3
# Tide data and config
tide_data_location = "files/tide_models"

# Configure AWS
os.environ["AWS_DEFAULT_REGION"] = "us-west-2"

if "AWS_NO_SIGN_REQUEST" in os.environ:
    del os.environ["AWS_NO_SIGN_REQUEST"]

configure_s3_access(requester_pays=True)

# Connect to the Datacube
dc = Datacube(app="coastlines")

# Set up a dask client
dask_client = Client(n_workers=4, threads_per_worker=8)
dask_client
```

## 2. Menentukan wilayah
Area yang akan diproses ditentukan dan ditampilkan.

```{code-cell} ipython3
start_date = "2000"
end_date = "2010"
max_cloud_cover = 10  # Maximum cloud cover percentage

coords = 1.440651, 97.229135
aoi_point = point(coords[1], coords[0], crs="EPSG:4326")
area = aoi_point.buffer(0.01).boundingbox

area.explore(tiles=basemaps.Esri.WorldImagery)
```

## 3. Memuat data

Memuat data Landsat dalam memory dengan menggunakan Dask.

```{code-cell} ipython3
categories_to_mask_landsat = {
    "cloud": "high_confidence",
    "cloud_shadow": "high_confidence",
}

# Find and load Landsat datasets
landsat_datasets = dc.find_datasets(
    product=["ls5_c2l2_sr","ls7_c2l2_sr","ls8_c2l2_sr", "ls9_c2l2_sr"],
    time=(start_date, end_date),
    longitude=(area.left, area.right),
    latitude=(area.bottom, area.top),
    cloud_cover=(0, max_cloud_cover),
)

print(f"Found {len(landsat_datasets)} Landsat datasets")
```

```{code-cell} ipython3
data = dc.load(
    datasets=landsat_datasets,
    longitude=(area.left, area.right),
    latitude=(area.bottom, area.top),
    resolution=30,
    output_crs="EPSG:6933",
    measurements=["red", "green", "blue", "nir08", "swir16", "qa_pixel"],
    group_by="solar_day",
    dask_chunks={"time": 1, "x": 520, "y": 520},
    resampling={
        "*": "cubic",
        "qa_pixel": "nearest",
    },
    patch_url=patch_usgs_landsat,
    driver="rio",
)
data
```

Untuk mengecek data, 6 data awal dibuka dengan fungsi `isel` atau "index select".

```{code-cell} ipython3
subset = data[["red", "green", "blue"]].isel(time=slice(0, 6))
subset.to_array().plot.imshow(col="time", col_wrap=2, size=6, robust=True)
```

## 4. Membuat mask

Pertama, mask untuk awan dibuat sehingga kita mendapatkan hasil analisis yang valid.

```{code-cell} ipython3
# Mask Landsat data
mask_value, _ = create_mask_value(
    landsat_datasets[0].product.measurements["qa_pixel"].flags_definition,
    **categories_to_mask_landsat,
)

cloud_mask = (data.qa_pixel & mask_value) != 0
valid_data = valid_data_mask(data)
mask = cloud_mask | ~valid_data

masked = data.where(~mask).drop_vars("qa_pixel")

# Scale Landsat data, so that values are between 0 and 1
masked = (masked * 0.0000275 - 0.2).clip(0, 1)

masked
```

```{code-cell} ipython3
# menampilkan cloud mask
masked_subset = masked[["red", "green", "blue"]].isel(time=range(0, 6))
masked_subset.to_array().plot.imshow(col="time", col_wrap=2, size=6, robust=True)
```

Mask kedua adalah mask untuk tinggi muka air laut dimana akan mengeliminasi data di luar pertengahan 50% dari observasi.

```{code-cell} ipython3
available_models, supported_models = list_models(
    directory=tide_data_location,
    show_supported=False,
)
print("\nSeluruh model yang didukung:")
print(supported_models)
```

```{code-cell} ipython3
# Add tide height to the data
tides = pixel_tides(
    masked,
    resample=True,
    directory=tide_data_location,
    model="GOT5.6",
    dask_compute=True,
)

# Determine tide cutoff
tide_cutoff_min, tide_cutoff_max = tide_cutoffs(data, tides, tide_centre=0.0)

tide_bool = (tides >= tide_cutoff_min) & (tides <= tide_cutoff_max)
data_filtered = masked.sel(time=tide_bool.sum(dim=["x", "y"]) > 0)

# Apply mask, and load in corresponding tide masked data
data_tide_masked = data_filtered.where(tide_bool)

data_tide_masked
```

## 5. Memisahkan daratan dan lautan

Dua spektral indeks untuk perairan digunakan yang merupakan gabungan antara NDWI (Normalized Difference Water Index) dan MNDWI (Modified Normalized Difference Water Index). Nilai rata-rata dari kedua indeks ini digunakan karena terbukti lebih andal dalam menangani kesalahan data di wilayah laut pada data Landsat.

```{code-cell} ipython3
# Create combined MNDWI/NDWI water index
index_name = "combined"
data_tide_masked["mndwi"] = (data_tide_masked.green - data_tide_masked.swir16) / (
    data_tide_masked.green + data_tide_masked.swir16
)
data_tide_masked["ndwi"] = (data_tide_masked.green - data_tide_masked.nir08) / (
    data_tide_masked.green + data_tide_masked.nir08
)
data_tide_masked["combined"] = (data_tide_masked.mndwi + data_tide_masked.ndwi) / 2


grouped_by_year = (
    data_tide_masked[index_name]
    .groupby("time.year")
    .median()
    .to_dataset(name=index_name)
)
grouped_by_year = grouped_by_year.compute()
grouped_by_year[index_name].plot.imshow(
    col="year", col_wrap=2, size=6, cmap="RdBu", robust=True
)
```

## 6. Ekstraksi data

Kontur atau garis pantai didapatkan dari batas antara daratan dan lautan. Gunakan z_value 0.0 pada indeks `combined`.

```{code-cell} ipython3
z_values = 0.0

contour_gdf = extract_contours(
    grouped_by_year, z_values=z_values, index_name=index_name
)

contour_gdf.reset_index().explore(
    column="year",
    cmap="magma",
    style_kwds={"weight": 3},
    tiles=basemaps.Esri.WorldImagery,
)
```

Berikutnya adalah ekstraksi titik dari kontur dan memberikan anotasi sehingga bisa diketahui berapa nilai akresi atau erosi garis pantai.

```{code-cell} ipython3
# ekstraksi titik setiap 30 meter
points_gdf = points_on_line(contour_gdf, index=2009, distance=30)

# menghitung perubahan tahunan 
points_gdf = annual_movements(
    points_gdf,
    contours_gdf=contour_gdf,
    yearly_ds=grouped_by_year,
    baseline_year=2009,
    water_index=index_name,
)

points_gdf = calculate_regressions(points_gdf=points_gdf)
```

## 7. Menampilkan dan menyimpan hasil

Berikut hasil analisis garis pantai ditampilkan

```{code-cell} ipython3
# Add human-friendly label for plotting
points_gdf["Coastal change"] = points_gdf.apply(
    lambda x: f"<h4>Garis pantai telah {'<b>berkurang</b>' if x.rate_time < 0 else '<b>bertambah</b>'} "
    f"</br><b>{x.rate_time:.2f} m (±{x.se_time:.1f}) setiap tahun</b> sejak "
    f"<b>{contour_gdf.index[0]}</b></h4>",
    axis=1,
)
points_gdf.loc[points_gdf.sig_time > 0.05, "Coastal change"] = (
    "<h4>Perubahan garis pantai sangat kecil</h4>"
)

m = contour_gdf.reset_index().explore(
    column="year",
    cmap="inferno",
    tooltip=False,
    style_kwds={"opacity": 0.5},
    categorical=True,
    tiles="https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}",
    attr="ESRI WorldImagery",
)

points_gdf.explore(
    m=m,
    column="rate_time",
    cmap="RdBu",
    markersize=5,
    tooltip=["Coastal change"],
)
```

Berikut adalah tahapan untuk menyimpan hasil analisis dalam format GeoPackage

```{code-cell} ipython3
points_gdf.to_file("files/garpan_perubahan.gpkg", layer="rate_of_change", driver="GPKG")
contour_gdf.to_file("files/garpan.gpkg", layer="shorelines", driver="GPKG")
```

# Catatan
Modul ini menunjukkan analisis data Landsat untuk menghitung laju abrasi dan akresi tahunan. Hasil ini dapat dijadikan acuan bagaimana garis pantai berubah sesuai dengan berjalannya waktu karena faktor alam atau manusia.

+++

# Info
- Modul ini diadaptasi dari Geoscience Australia di [dea-coastlines](https://github.com/geoscienceAustralia/dea-coastlines).
Versi terbarunya dapat dilihat di [coastlines](https://github.com/auspatious/coastlines).
- Modul ini dijalankan di platform Piksel. Jika ada pertanyaan atau komentar, silahkan email ke piksel@big.go.id
- **Lisensi:** Skrip dalam notebook ini dilisensikan berdasarkan [Apache License, Version 2.0](https://www.apache.org/licenses/LICENSE-2.0). 
Data Piksel dilisensikan berdasarkan lisensi [Creative Commons by Attribution 4.0](https://creativecommons.org/licenses/by/4.0/).
