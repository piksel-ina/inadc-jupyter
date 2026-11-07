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

| <h1><b>Identifikasi Perubahan Terumbu Karang</b></h1> | ![](files/piksel_logo_small.png) |
|:---------|----------:|
- **Data:** Sentinel-2
- **Lokasi:** Pulau Boni, Raja Ampat, Provinsi Papua Barat Daya
- **Metode:** Lyzenga Algorithm + Random Forest
- **Data lain:** Titik sampel (`files/sample_points2020.geojson`, `files/sample_points2025.geojson`, `files/training_points.geojson`, `files/validation_points.geojson`)

+++

# Pendahuluan
Modul ini bertujuan mengidentifikasi perubahan luasan dan kondisi terumbu karang di Pulau Boni, Raja Ampat, antara tahun 2020 dan 2025. Data input yang digunakan berupa citra satelit Sentinel-2 pada kedua periode tersebut, yang diolah untuk memisahkan area darat dan laut menggunakan indeks MNDWI, kemudian dikoreksi kolom air melalui Transformasi Lyzenga agar pengaruh kedalaman air terhadap nilai piksel dapat diminimalkan.
 
Hasil transformasi tersebut selanjutnya digunakan sebagai input klasifikasi menggunakan algoritma Random Forest untuk membedakan kelas tutupan dasar perairan, termasuk terumbu karang. Akurasi klasifikasi dievaluasi menggunakan matriks konfusi, sebelum dilakukan analisis luasan per zona dan deteksi perubahan spasiotemporal antar kedua periode. Output akhir dari proses ini berupa peta klasifikasi, estimasi luasan terumbu karang, serta visualisasi perubahan yang tersimpan dalam format siap digunakan untuk analisis maupun pelaporan lebih lanjut.

+++

# Tahapan
Tahapan dalam mendeteksi perubahan terumbu karang adalah sebagai berikut:
1. Persiapan
2. Pemisahan darat dan laut
3. Koreksi pengaruh kedalaman air
4. Klasifikasi citra
5. Analisis perubahan karang
***

+++

## 1. Persiapan
Tahap ini dilakukan di awal pemrosesan data.

+++

### a. Memuat library

```{code-cell} ipython3
# Datacube / geospatial data access
from datacube import Datacube
import odc.geo
from odc.geo.geom import point

# Data array & tabular handling
import xarray as xr
import numpy as np
import pandas as pd

# Vector geometry
from shapely.geometry import shape
import geopandas as gpd

# Raster I/O
import rasterio
from rasterio import features
import rioxarray 

# Machine learning
from sklearn.ensemble import RandomForestClassifier
from sklearn.model_selection import train_test_split
from sklearn.metrics import confusion_matrix
from sklearn.preprocessing import LabelEncoder

# Plotting & visualization
import matplotlib.pyplot as plt
import seaborn as sns
from matplotlib.colors import ListedColormap
from matplotlib.patches import Patch

# Interactive mapping
import folium
from folium import plugins
from ipyleaflet import Map as LeafletMap, ImageOverlay as LeafletImageOverlay, DrawControl, FullScreenControl
import json

# Jupyter display & widgets
from IPython.display import display, clear_output
import ipywidgets as widgets

# I/O & encoding utilities
from io import BytesIO
import base64
import os

# Array utilities
from scipy.ndimage import zoom

dc = Datacube()
```

### b. Menentukan wilayah
Tahap ini bertujuan menentukan lokasi pengamatan menggunakan satu titik referensi dalam bentuk decimal degree. Lokasi pengamatan dapat diganti nilai buffer-nya agar area cakupan sesuai dengan tujuan. Lokasi yang dipilih adalah Pulau Boni, Kabupaten Raja Ampat.  [🔗](https://maps.app.goo.gl/cjxEoGHdUQzPopGc6).

```{code-cell} ipython3
coords = - 0.032, 131.08 #Input Koordinat Acuan (Decimal Degree)
output_crs = "EPSG:4326"
aoi_point = point(coords[1], coords[0], crs=output_crs)
bbox = aoi_point.buffer(0.0225).boundingbox #Atur buffer (Decimal Degree) dan sesuaikan dengan Area Studi
study_area_bbox = (bbox.left, bbox.bottom, bbox.right, bbox.top)
min_lon, min_lat, max_lon, max_lat = study_area_bbox
max_cloud_cover = 40 #Atur tutupan awan maksimal
measurements = ['red', 'green', 'blue', 'swir_1']

bbox.explore(zoom=8)
```

### c. Pemilihan citra
Tahap ini bertujuan untuk memuat citra Sentinel-2 dari Datacube. Hasil dari tahapan ini berupa 1 pasang citra yang akan digunakan dalam pemrosesan lebih lanjut.

```{code-cell} ipython3
resolusi_deg = (-0.00009, 0.00009) 
def cari_dan_muat_citra(time_range, label):
    datasets = dc.find_datasets(product='s2_l2a', lon=(min_lon, max_lon), lat=(min_lat, max_lat), time=time_range)
    print(f"[{label}] Total dataset ditemukan: {len(datasets)}")
    filtered = [(ds, ds.metadata.cloud_cover) for ds in datasets if ds.metadata.cloud_cover <= max_cloud_cover]
    print(f"[{label}] Dataset dengan cloud cover <= {max_cloud_cover}%: {len(filtered)}")
    if not filtered:
        print(f"[{label}] Tidak ada dataset lolos filter.")
        return None
        
    ds_loaded = dc.load(product='s2_l2a',lon=(min_lon, max_lon), lat=(min_lat, max_lat), time=time_range, measurements=measurements, output_crs=output_crs, resolution=resolusi_deg, datasets=[d for d, _ in filtered])
    print(f"[{label}] {len(ds_loaded.time)} scene dimuat.")
    return ds_loaded
    
def plot_semua_scene(ds_loaded, label):
    if ds_loaded is None or len(ds_loaded.time) == 0:
        print(f"[{label}] Tidak ada data")
        return
    n = len(ds_loaded.time)
    cols = 3
    rows = (n + cols - 1) // cols
    fig, axes = plt.subplots(rows, cols, figsize=(15, 5 * rows))
    axes = np.array(axes).flatten() if n > 1 else [axes]
    for i in range(n):
        rgb = ds_loaded.isel(time=i).odc.to_rgba(bands=['red', 'green', 'blue'], vmin=0, vmax=2000)
        rgb.plot.imshow(ax=axes[i], add_colorbar=False)
        axes[i].set_title(str(ds_loaded.isel(time=i).time.values)[:10], fontsize=10)
        axes[i].axis('off')
    for j in range(i + 1, len(axes)):
        axes[j].axis('off')
    plt.suptitle(f'Scene Tersedia — {label}')
    plt.tight_layout()
    plt.show()

time_range2020 = ('2020-07-10', '2020-07-12') # Sesuaikan Rentang Tanggal di Tahun Pertama yang akan diamati
time_range2025 = ('2025-08-10', '2025-09-10') # Sesuaikan Rentang Tanggal di Tahun Kedua yang akan diamati

ds_loaded2020 = cari_dan_muat_citra(time_range2020, '2020') 
ds_loaded2025 = cari_dan_muat_citra(time_range2025, '2025')

plot_semua_scene(ds_loaded2020, '2020')
plot_semua_scene(ds_loaded2025, '2025')
```

Berdasarkan beberapa citra yang telah dimuat, selanjutnya memilih citra bersih dan memiliki visual yang mirip.

```{code-cell} ipython3
fig, axes = plt.subplots(1, 2, figsize=(10, 5))

def preview_tanggal(ds_loaded, tanggal_fix, ax):
    citra = ds_loaded.sel(time=tanggal_fix)
    if 'time' in citra.dims and citra.sizes['time'] > 1:
        citra = citra.isel(time=0)
    citra = citra.squeeze()
    rgb = citra.odc.to_rgba(bands=['red', 'green', 'blue'], vmin=0, vmax=3000)
    ax.imshow(rgb.values)
    ax.set_title(f"{tanggal_fix}")
    ax.axis('off')
    return citra

tanggal_fix2020 = '2020-07-11'  # Pilih Tanggal yang Sesuai
tanggal_fix2025 = '2025-08-14'  # Pilih Tanggal yang Sesuai

citra2020 = preview_tanggal(ds_loaded2020, tanggal_fix2020, axes[0])
citra2025 = preview_tanggal(ds_loaded2025, tanggal_fix2025, axes[1])

plt.tight_layout()
plt.show()
```

## 2. Pemisahan darat dan laut
Untuk memisahkan darat dan laut, digunakan metode MNDWI

+++

### a. Perhitungan MNDWI
Modified Normalized Difference Water Index (MNDWI) digunakan untuk memperjelas batas darat dan laut berdasarkan karakteristik band GREEN dan SWIR. Berikut adalah rumus MNDWI.
$$MNDWI = \frac{(green - SWIR)}{(green + SWIR1)}$$
di mana:
- green = Green band
- SWIR_1 = Short-Wave Infrared 1

```{code-cell} ipython3
def hitung_mndwi(ds_loaded, tanggal_fix):
    citra_fix = ds_loaded.sel(time=tanggal_fix)
    if 'time' in citra_fix.dims and citra_fix.sizes['time'] > 1:
        citra_fix = citra_fix.isel(time=0)
    citra_fix = citra_fix.squeeze()
    print(f"Band tersedia:", list(citra_fix.data_vars))
    green = citra_fix.green / 10000
    swir_1 = citra_fix.swir_1 / 10000
    mndwi = (green - swir_1) / (green + swir_1 + 1e-10)
    return citra_fix, mndwi
    
def plot_mndwi(mndwi, tanggal_fix):
    fig, axes = plt.subplots(1, 2, figsize=(10, 4.5))
    axes[0].hist(mndwi.values.flatten(), bins=100, color='steelblue', alpha=0.7)
    axes[0].axvline(0, color='red', linestyle='--')
    axes[0].set_title(f'Histogram MNDWI - ({tanggal_fix})')
    axes[0].set_xlabel('MNDWI'); axes[0].set_ylabel('Frekuensi')
    im = axes[1].imshow(mndwi.values, cmap='RdYlGn', vmin=-1, vmax=1)
    plt.colorbar(im, ax=axes[1])
    axes[1].set_title(f'Peta MNDWI - ({tanggal_fix})')
    axes[1].axis('off')
    plt.tight_layout()
    plt.show()

citra_fix2020, mndwi2020 = hitung_mndwi(ds_loaded2020, tanggal_fix2020)
citra_fix2025, mndwi2025 = hitung_mndwi(ds_loaded2025, tanggal_fix2025)
plot_mndwi(mndwi2020, tanggal_fix2020)
```

### b. Otsu Thresholding
Menggunakan nilai hasil perhitungan MNDWI, region darat dan laut dipisahkan dengan Otsu Thresholding. Metode ini menentukan nilai batasan paling maksimal dalam pemisahan berdasarkan nilai variansi indeks. Berikut adalah rumus Otsu Thresholding. 
$$
\begin{cases}
\sigma^2 = P_{nw}(M_{nw}-M)^2 + P_w(M_w-M)^2 \\
M = P_{nw}M_{nw} + P_wM_w \\
P_{nw} + P_w = 1
\end{cases}
$$

$$
t^* = \underset{t \in [a,b]}{\operatorname{arg\,max}}
\left\{
P_{nw}(M_{nw}-M)^2
+
P_w(M_w-M)^2
\right\}
$$

di mana:
- s2 =varian di dalam kelas badan air maupun non-badan air
- Pnw= probabilitas nilai piksel untuk masuk kelas non-badan air
- Pw= probabilitas nilai piksel untuk masuk kelas badan air
- Mnw= rata-rata nilai piksel kelas non-badan air
- Mw= rata-rata nilai piksel kelas badan air
- M= rata-rata nilai piksel citra MNDWI
- t*= nilai threshold

```{code-cell} ipython3
def otsu_threshold(mndwi):
    vals = mndwi.values.flatten()
    vals = vals[np.isfinite(vals)]
    t_vals = [-0.1, 0.0, 0.1, 0.2, 0.3, 0.4, 0.5, 0.6]
    results = []
    for t in t_vals:
        w, nw = vals > t, vals <= t
        Pw, Pnw = w.sum() / len(vals), nw.sum() / len(vals)
        Mw, Mnw = vals[w].mean(), vals[nw].mean()
        M = Pw * Mw + Pnw * Mnw
        var = Pw * (Mw - M) ** 2 + Pnw * (Mnw - M) ** 2
        results.append((t, var))
    df = pd.DataFrame(results, columns=['t', 'var'])
    optimal_t = df.loc[df['var'].idxmax(), 't']
    return optimal_t, df

def plot_otsu(df, optimal_t, label):
    plt.figure(figsize=(6, 3.5))
    plt.plot(df['t'], df['var'], 'bo-')
    plt.axvline(optimal_t, color='red', linestyle='--')
    plt.xlabel('t'); plt.ylabel('Varians antar kelas')
    plt.title(f'Otsu Thresholding - {label} (optimal t={optimal_t:.2f})')
    plt.grid(True)
    plt.show()

optimal_t2020, df_otsu2020 = otsu_threshold(mndwi2020)
plot_otsu(df_otsu2020, optimal_t2020, '2020')
```

Selanjutnya nilai batasan maksimal dengan variansi tertinggi diterapkan untuk masking citra. Hasil masking juga diterapkan buffer ke arah laut untuk meminimalisir hilangnya informasi yang ada di perbatasan laut dalam.

```{code-cell} ipython3
def buat_mask_air_otsu(citra_fix, mndwi, optimal_t, buffer_m=0.00135):
    mask_darat = mndwi < 0
    mask_air = mndwi > optimal_t
    t = citra_fix.odc.geobox.transform
    shapes = [(shape(geom), 1) for geom, val in features.shapes(mask_air.astype("uint8").values, transform=t) if val == 1]
    gdf = gpd.GeoDataFrame(geometry=[geom for geom, _ in shapes], crs=citra_fix.odc.geobox.crs).dissolve()
    mask_air = features.rasterize([(geom, 1) for geom in gdf.buffer(buffer_m).geometry], out_shape=mask_air.shape, transform=t, fill=0).astype(bool)
    citra_air = citra_fix.where(mask_air)
    citra_air_potong = citra_air.where(~mask_darat)
    return citra_air_potong

def plot_rgb(citra, title, vmax=3000):
    rgb = citra.odc.to_rgba(bands=['red', 'green', 'blue'], vmin=0, vmax=vmax)
    plt.figure(figsize=(5, 5))
    plt.imshow(rgb.values)
    plt.title(title)
    plt.axis('off')
    plt.show()

citra_air_potong2020 = buat_mask_air_otsu(citra_fix2020, mndwi2020, optimal_t2020)
citra_air_potong2025 = buat_mask_air_otsu(citra_fix2025, mndwi2020, optimal_t2020)
plot_rgb(citra_air_potong2020, 'Masked - 2020') 
plot_rgb(citra_air_potong2025, 'Masked - 2025') 

base_air2020 = citra_air_potong2020 
base_air2025 = citra_air_potong2025  
```

## 3. Koreksi pengaruh kedalaman air
Koreksi pengaruh kedalaman air dilakukan untuk mengurangi pengaruh kolom air terhadap nilai spektral citra satelit. Proses ini membantu memperjelas karakteristik objek dasar perairan, seperti terumbu karang, lamun, dan pasir, sehingga hasil pemetaan habitat perairan dangkal menjadi lebih akurat.

+++

### a. Pembuatan sampel untuk transformasi Lyzenga
Pembuatan sampel lyzenga dilakukan sebagai input perhitungan lyzenga. Sampel yang digunakan merupakan objek homogen dengan kedalaman yang berbeda. Gunakan objek pasir yang mudah diidentifikasi sebagai sampel. Pasir pada citra terlihat halus tanpa adanya pola lain yang kasar dan memiliki warna biru yang lebih gelap untuk objek yang makin dalam. Buat sampel lyzenga pada dua tahun yang berbeda di peta interaktif. Output dari tahap ini adalah dua file berformat geojson yang menyimpan informasi koordinat titik sampel.

Sudah tersedia file titik sampel `files/sample_points2020.geojson` dan `files/sample_points2025.geojson`. Tetapi jika ingin menggunakan peta interaktif untuk membuat sampel, berikut skrip nya:
```
os.makedirs('files', exist_ok=True)

def buat_peta_folium(citra, label, vmax=3000):
    rgb = citra.odc.to_rgba(bands=['red', 'green', 'blue'], vmin=0, vmax=vmax)
    fig, ax = plt.subplots(figsize=(8, 8))
    ax.imshow(rgb.values)
    ax.axis('off')
    buf = BytesIO()
    plt.savefig(buf, format='png', bbox_inches='tight', pad_inches=0, dpi=100, transparent=True)
    plt.close()
    img_base64 = base64.b64encode(buf.getvalue()).decode('utf-8')
    buf = BytesIO()

    bbox = citra.odc.geobox.geographic_extent.boundingbox
    bounds = [[bbox.bottom, bbox.left], [bbox.top, bbox.right]]
    center = [(bbox.bottom + bbox.top) / 2, (bbox.left + bbox.right) / 2]

    out_path = f'files/sample_points{label}.geojson'
    feature_collection = {'type': 'FeatureCollection', 'features': []}

    m = LeafletMap(center=center, zoom=13)
    m.add(LeafletImageOverlay(url=f'data:image/png;base64,{img_base64}', bounds=bounds, name=f'Citra {label}'))
    m.add(FullScreenControl())

    draw_control = DrawControl(
        polyline={}, polygon={}, rectangle={}, circle={}, circlemarker={},
        marker={'shapeOptions': {}},
    )

    def handle_draw(target, action, geo_json):
        if action == 'created':
            feature_collection['features'].append(geo_json)
        elif action == 'deleted':
            feature_collection['features'][:] = [
                f for f in feature_collection['features'] if f['geometry'] != geo_json['geometry']
            ]
    draw_control.on_draw(handle_draw)
    m.add(draw_control)

    tombol_simpan = widgets.Button(description="Simpan Sampel", button_style='success')
    status_area = widgets.Output()

    def on_simpan_click(b):
        with status_area:
            clear_output(wait=True)
            if feature_collection['features']:
                with open(out_path, 'w') as f:
                    json.dump(feature_collection, f)
                print(f"{out_path} tersimpan ({len(feature_collection['features'])} titik)")
            else:
                print("Belum ada titik sampel yang dibuat.")
    tombol_simpan.on_click(on_simpan_click)

    display(m, tombol_simpan, status_area)
```

lalu jalankan
```buat_peta_folium(base_air2020, '2020')```
Buat sampel di atas hasil masking citra tahun 2020. Klik tombol 'Simpan Sampel' untuk menyimpan file di `files/sample_points2020.geojson`

jalankan
```buat_peta_folium(base_air2025, '2025')```
Buat sampel di atas hasil masking citra tahun 2025. Klik tombol 'Simpan Sampel' untuk menyimpan file di `files/sample_points2025.geojson`

+++

### b. Ekstraksi Nilai Piksel
Berdasarkan sampel yang telah dibuat, kemudian dilakukan ekstraksi nilai linearisasi pada band red, green, dan blue. Output dari tahap ini adalah dua file berformat csv yang berisi koordinat sampel beserta nilai ekstraksi.

```{code-cell} ipython3
def ekstraksi_ln(base_air, sample_file, label):
    citra = base_air.squeeze()
    eps = 1e-10
    ln_red = np.log(citra.red + eps)
    ln_green = np.log(citra.green + eps)
    ln_blue = np.log(citra.blue + eps)
    print(f"[{label}] ln_red min/max = {ln_red.min().values:.4f}/{ln_red.max().values:.4f}")
    gdf_wgs84 = gpd.read_file(sample_file)
    data = []
    for _, row in gdf_wgs84.iterrows():
        lon, lat = row.geometry.x, row.geometry.y
        r = float(ln_red.sel(longitude=lon, latitude=lat, method='nearest').values)
        g = float(ln_green.sel(longitude=lon, latitude=lat, method='nearest').values)
        b = float(ln_blue.sel(longitude=lon, latitude=lat, method='nearest').values)
        data.append([lon, lat, r, g, b])
    out_csv = f'files/ekstraksi_rgb{label}.csv'
    pd.DataFrame(data, columns=['longitude', 'latitude', 'red', 'green', 'blue']).to_csv(out_csv, index=False)
    print(f"{out_csv}")
    return ln_red, ln_green, ln_blue, out_csv

ln_red2020, ln_green2020, ln_blue2020, csv2020 = ekstraksi_ln(base_air2020, 'files/sample_points2020.geojson', '2020')
ln_red2025, ln_green2025, ln_blue2025, csv2025 = ekstraksi_ln(base_air2025, 'files/sample_points2025.geojson', '2025')
```

### c. Transformasi Lyzenga
Transformasi Lyzenga bertujuan untuk melakukan koreksi terhadap kolom air berdasarkan konsep pelemahan cahaya terhadap air. Output dari tahap ini adalah citra Depth Invariant Index (DII) yang mana lebih menunjukkan objek di perairan. Berikut adalah berbagai rumus dalam transformasi lyzenga.

1. Rumus variansi digunakan untuk mengukur seberapa besar penyebaran nilai piksel terhadap nilai rata-rata piksel tiap band.
$$variance = \frac{\sum (x-\bar{x})^2}{n-1}$$
2. Rumus kovariansi digunakan untuk mengukur kekuatan dan arah hubungan linear antara dua kombinasi band yaitu blue-green, blue-red, dan green-red. 
$$\operatorname{covariance}(x,y) = \frac{\operatorname{Cov}(x,y)}{\sigma_x \times \sigma_y}$$
3. Rumus nilai a digunakan untuk menentukan koefisien berdasarkan perbedaan varians antara dua band dan kovarians keduanya.
$$a_{ij} = \frac{\operatorname{variance}_i-\operatorname{variance}_j}{2\times\operatorname{covariance}_{ij}}$$
4. Rumus ini digunakan untuk memperoleh rasio koefisien pelemahan cahaya antar 2 band berdasarkan nilai a.
$$\frac{k_i}{k_j} = a+\sqrt{a^2+1}$$
5. Rumus ini merupakan rumus transformasi lyzenga yang dihitung berdasarkan rasio atenuasi antar band dan nilai piksel terlinearisasi setiap band.
$$Y = \ln(L_i)-\left(\frac{k_i}{k_j}\times\ln(L_j)\right)$$

```{code-cell} ipython3
def transformasi_lyzenga(csv_file, ln_red, ln_green, ln_blue, label):
    df = pd.read_csv(csv_file)

    N = len(df)
    meanR, meanG, meanB = df['red'].mean(), df['green'].mean(), df['blue'].mean()
    S2R = ((df['red'] - meanR) ** 2).sum() / (N - 1)
    S2G = ((df['green'] - meanG) ** 2).sum() / (N - 1)
    S2B = ((df['blue'] - meanB) ** 2).sum() / (N - 1)

    devR, devG, devB = df['red'] - meanR, df['green'] - meanG, df['blue'] - meanB
    CovBG = (devB * devG).sum() / (N - 1)
    CovBR = (devB * devR).sum() / (N - 1)
    CovGR = (devG * devR).sum() / (N - 1)

    aBG = (S2B - S2G) / (2 * CovBG)
    aBR = (S2B - S2R) / (2 * CovBR)
    aGR = (S2G - S2R) / (2 * CovGR)

    KBKG = aBG + np.sqrt(aBG ** 2 + 1)
    KBKR = aBR + np.sqrt(aBR ** 2 + 1)
    KGKR = aGR + np.sqrt(aGR ** 2 + 1)
    print(N)
    print(f"[{label}] S2R={S2R:.4f}  S2G={S2G:.4f}  S2B={S2B:.4f}")
    print(f"[{label}] CovBG={CovBG:.4f}  CovBR={CovBR:.4f}  CovGR={CovGR:.4f}")
    print(f"[{label}] aBG={aBG:.4f}  aBR={aBR:.4f}  aGR={aGR:.4f}")
    print(f"[{label}] KB/KG={KBKG:.4f}  KB/KR={KBKR:.4f}  KG/KR={KGKR:.4f}")
    
    DII_GR = ln_green - KGKR * ln_red
    DII_BR = ln_blue - KBKR * ln_red
    DII_BG = ln_blue - KBKG * ln_green

    def normalize(data):
        vals = data.values.flatten()
        vals = vals[np.isfinite(vals)]
        vmin, vmax = np.percentile(vals, 2), np.percentile(vals, 98)
        if vmax - vmin < 1e-10:
            return np.zeros_like(data.values)
        return np.clip((data.values - vmin) / (vmax - vmin), 0, 1)
    rgb_composite = np.stack([normalize(DII_GR), normalize(DII_BR), normalize(DII_BG)], axis=-1)
    plt.figure(figsize=(5, 5))
    plt.imshow(rgb_composite)
    plt.title(f'Komposit Lyzenga (R=DII_GR, G=DII_BR, B=DII_BG)\n{label}')
    plt.axis('off')
    plt.show()
    return DII_GR, DII_BR, DII_BG, rgb_composite

DII_GR2020, DII_BR2020, DII_BG2020, rgb_composite2020 = transformasi_lyzenga(
    csv2020, ln_red2020, ln_green2020, ln_blue2020, '2020')
DII_GR2025, DII_BR2025, DII_BG2025, rgb_composite2025 = transformasi_lyzenga(
    csv2025, ln_red2025, ln_green2025, ln_blue2025, '2025')
```

## 4. Klasifikasi citra
Klasifikasi citra dilakukan dengan:
- pembuatan training sample
- klasifikasi random forest
- evaluasi hasil klasifikasi

+++

### a. Pembuatan sampel pelatihan klasifikasi
Pembuatan sampel pelatihan klasifikasi dilakukan sebagai input dalam klasifikasi random forest. Sampel dibuat untuk masing-masing kelas dengan karakteristik piksel yang mirip. Pembuatan sampel dilakukan pada kelas karang, lamun, substrat, dan laut dalam. Output dari tahap ini adalah empat file berformat geojson yang menyimpan informasi koordinat titik sampel tiap kelas.

Titik training sudah tersedia di `files/training_points.geojson`. Tetapi jika ingin membuat menggunakan peta interaktif, gunakan skrip berikut:
```
def sampling_klasifikasi_folium_lyzenga(rgb_composite, base_citra, label):
    fig, ax = plt.subplots(figsize=(8, 8))
    ax.imshow(rgb_composite) 
    ax.axis('off')
    buf = BytesIO()
    plt.savefig(buf, format='png', bbox_inches='tight', pad_inches=0, dpi=100, transparent=True)
    plt.close()
    img_base64 = base64.b64encode(buf.getvalue()).decode('utf-8')

    bbox = base_citra.odc.geobox.geographic_extent.boundingbox
    bounds = [[bbox.bottom, bbox.left], [bbox.top, bbox.right]]
    center = [(bbox.bottom + bbox.top) / 2, (bbox.left + bbox.right) / 2]

    dropdown = widgets.Dropdown(options=['substrat', 'lamun', 'karang', 'laut_dalam'],value='substrat',description='Kelas:')
    tombol_buat = widgets.Button(description="Buat Sampel", button_style='success')
    tombol_simpan = widgets.Button(description="Simpan Sampel", button_style='info')
    output_area = widgets.Output()

    state = {'items': []}

    m = LeafletMap(center=center, zoom=13)
    m.add(LeafletImageOverlay(url=f'data:image/png;base64,{img_base64}', bounds=bounds, name=f'Citra Lyzenga {label}'))
    m.add(FullScreenControl())

    draw_control = DrawControl(
        polyline={}, polygon={}, rectangle={}, circle={}, circlemarker={},
        marker={'shapeOptions': {}},
    )

    def handle_draw(target, action, geo_json):
        if action == 'created':
            state['items'].append({'kelas': dropdown.value, 'geo_json': geo_json})
        elif action == 'deleted':
            geom = geo_json['geometry']
            for i in range(len(state['items']) - 1, -1, -1):
                if state['items'][i]['geo_json']['geometry'] == geom:
                    del state['items'][i]
                    break
    draw_control.on_draw(handle_draw)
    m.add(draw_control)

    def on_buat_click(b):
        with output_area:
            clear_output(wait=True)
            print(f"Kelas aktif: {dropdown.value}. Gambar titik sampel menggunakan tombol marker pada peta.")
    tombol_buat.on_click(on_buat_click)

    def on_simpan_click(b):
        with output_area:
            k = dropdown.value
            nama_file = f'files/sample_{k}.geojson'
            fitur = [it['geo_json'] for it in state['items'] if it['kelas'] == k]
            if fitur:
                fc = {'type': 'FeatureCollection', 'features': fitur}
                with open(nama_file, 'w') as f:
                    json.dump(fc, f)
                print(f"{nama_file} tersimpan ({len(fitur)} titik)")
            else:
                print(f"Belum ada titik sampel untuk kelas '{k}'. Pastikan kelas sudah dipilih sebelum menggambar titik.")
    tombol_simpan.on_click(on_simpan_click)

    display(m, widgets.HBox([dropdown, tombol_buat, tombol_simpan]), output_area)
```
Pembuatan sampel dilakukan di atas citra Depth Invariant Index dalam peta interaktif berikut. 
- Klik "Buat Sampel" untuk membuat sampel di kelas pertama.
- Klik "Simpan Sampel" untuk menyimpan file hasil sampling yang berformat geojson.
- Selanjutnya buat sampel untuk kelas lain dengan memilih kelas di dropdown "Kelas". Jangan lupa untuk menghapus titik sampel yang dibuat pada kelas sebelumnya.
- Untuk setiap kelas, minimal dibuat 8 titik sampel

Jalankan skrip `sampling_klasifikasi_folium_lyzenga(rgb_composite2020, citra_air_potong2020, '2020')`. Lalu gabungkan keempat file:
```
def gabung_file_klasifikasi(label):
    kelas_list = ['substrat', 'lamun', 'karang', 'laut_dalam']
    gdfs = []
    for k in kelas_list:
        file_name = f'files/sample_{k}.geojson'
        if os.path.exists(file_name):
            gdf = gpd.read_file(file_name)
            gdf['kelas'] = k
            gdfs.append(gdf)
        else:
            print(f"Peringatan: {file_name} belum ada di folder.")
    if gdfs:
        gabungan = pd.concat(gdfs, ignore_index=True)
        file_output = f'files/training_points.geojson'
        gabungan.to_file(file_output, driver='GeoJSON')
        print(f"{file_output} tersimpan")
        print(f"total titik sampel pelatihan : {len(gabungan)}")
    else:
        print(f"[{label}] Tidak ada file sample yang ditemukan.")

gabung_file_klasifikasi('')
```

+++

### b. Klasifikasi Random Forest

+++

Tahap ini bertujuan untuk melakukan pengelompokkan piksel berdasarkan sampel pelatihan yang dibuat. Random Forest merupakan salah satu algoritma dalam Supervised Classification yang berisi gabungan dari beberapa Decision Tree untuk melakukan klasifikasi. Setiap pohon keputusan dalam Random Forest melakukan prediksi secara independen, dan hasil prediksi dari setiap pohon digabungkan untuk menghasilkan prediksi akhir.

```{code-cell} ipython3
training_points='files/training_points.geojson'
color_lists = ['#ff6161', '#668438', '#1f78b4', '#ffffbe']

def klasifikasi_rf(train_file, DII_GR, DII_BR, DII_BG, base_air, label):
    gdf = gpd.read_file(train_file)
    le = LabelEncoder()
    y = le.fit_transform(gdf['kelas'])
    print(f"[{label}] Kelas terdeteksi:", le.classes_)

    jumlah_per_kelas = gdf['kelas'].value_counts()
    print(f"[{label}] Jumlah sampel per kelas:\n{jumlah_per_kelas}")
    n_kelas = len(le.classes_)
    minimal_total = int(np.ceil(n_kelas / 0.3))
    if len(gdf) < minimal_total or jumlah_per_kelas.min() < 2:
        raise ValueError(
            f"[{label}] Sampel pelatihan terlalu sedikit (total {len(gdf)} titik untuk {n_kelas} kelas). "
            f"Tambahkan minimal {minimal_total} titik sampel (idealnya 8-10 per kelas), "
            "lalu jalankan ulang gabung_file_klasifikasi() sebelum klasifikasi."
        )

    bands = [DII_GR, DII_BR, DII_BG]
    X = []
    for _, row in gdf.iterrows():
        lon, lat = row.geometry.x, row.geometry.y
        vals = [float(b.sel(longitude=lon, latitude=lat, method='nearest').values) for b in bands]
        X.append(vals)
    X = np.array(X)

    X_train, X_val, y_train, y_val = train_test_split(X, y, test_size=0.3, random_state=42, stratify=y)

    rf = RandomForestClassifier(n_estimators=100, oob_score=True, n_jobs=-1, random_state=42)
    rf.fit(X_train, y_train)
    y_pred = rf.predict(X_val)

    cm = confusion_matrix(y_val, y_pred)
    plt.figure(figsize=(5, 5))
    sns.heatmap(cm, annot=True, fmt='d', cmap='Blues', xticklabels=le.classes_, yticklabels=le.classes_)
    plt.xlabel('Prediksi'); plt.ylabel('Aktual'); plt.title(f'Matriks Konfusi - {label}')
    plt.show()

    img_stack = np.stack([b.values for b in bands], axis=-1)
    rows, cols, _ = img_stack.shape
    img_flat = img_stack.reshape(-1, 3)
    valid = ~np.isnan(img_flat).any(axis=1)
    pred_flat = rf.predict(img_flat[valid])
    class_map = np.full(img_flat.shape[0], np.nan)
    class_map[valid] = pred_flat
    class_map = class_map.reshape(rows, cols)
    fig, ax = plt.subplots(figsize=(8, 8))
    im = ax.imshow(class_map, cmap=ListedColormap(color_lists), interpolation='nearest', vmin=0, vmax=3)
    ax.set_title(f'Hasil Klasifikasi - {label}'); ax.axis('off')
    cbar = plt.colorbar(im, ax=ax, ticks=[0, 1, 2, 3])
    cbar.set_ticklabels(le.classes_); cbar.set_label('Kelas')
    plt.tight_layout(); plt.show()
    return rf, le, class_map

rf2020, le2020, class_map2020 = klasifikasi_rf(training_points, DII_GR2020, DII_BR2020, DII_BG2020, base_air2020, '2020')
rf2025, le2025, class_map2025 = klasifikasi_rf(training_points, DII_GR2025, DII_BR2025, DII_BG2025, base_air2025, '2025')
```

### c. Evaluasi akurasi hasil klasifikasi

+++

Matriks konfusi digunakan untuk mengevaluasi tingkat akurasi hasil klasifikasi dengan membandingkan hasil klasifikasi terhadap referensi. Pada pemrosesan kali ini, referensi yang digunakan adalah Peta Habitat Bentik yang diperoleh dari website Allen Coral ATLAS [🔗](https://allencoralatlas.org/atlas/#14.59/-0.0279/131.0751). Output dari tahap ini berupa nilai akurasi keseluruhan dan matriks konfusi yang menunjukkan jumlah data yang diklasifikasikan dengan benar maupun salah pada setiap kelas. 

File titik validasi sudah tersedia di `files/validation_points.geojson`

```{code-cell} ipython3
def validasi(class_map, le, base_air, label, val_file='files/validation_points.geojson'):
    gdf_val = gpd.read_file(val_file)
    true, pred = [], []
    for _, row in gdf_val.iterrows():
        lon, lat = row.geometry.x, row.geometry.y
        xi = np.abs(base_air.longitude.values - lon).argmin()
        yi = np.abs(base_air.latitude.values - lat).argmin()
        p = class_map[yi, xi]
        if not np.isnan(p):
            true.append(row['kelas']); pred.append(int(p))

    true_enc = le.transform(true)
    pred_enc = np.array(pred)
    n_classes = len(le.classes_)
    cm = np.zeros((n_classes, n_classes), dtype=int)
    for t, p in zip(true_enc, pred_enc):
        cm[t, p] += 1

    N = cm.sum()
    row_sum, col_sum = cm.sum(axis=1), cm.sum(axis=0)
    ua = np.diag(cm) / row_sum
    pa = np.diag(cm) / col_sum
    oa = np.trace(cm) / N
    pe = np.sum(row_sum * col_sum) / (N * N)
    kappa = (oa - pe) / (1 - pe)

    print(f"HASIL VALIDASI - {label}")
    print(f"Overall Accuracy : {oa:.4f} ({oa * 100:.2f}%)")
    print(f"Kappa Accuracy   : {kappa:.4f}")
    print("\nUser's Accuracy (per kelas):")
    for i, name in enumerate(le.classes_):
        print(f"  {name:12} : {ua[i]:.4f} ({ua[i] * 100:.2f}%)")
    print("\nProducer's Accuracy (per kelas):")
    for i, name in enumerate(le.classes_):
        print(f"  {name:12} : {pa[i]:.4f} ({pa[i] * 100:.2f}%)")

    plt.figure(figsize=(5, 4))
    sns.heatmap(cm, annot=True, fmt='d', cmap='Blues', xticklabels=le.classes_, yticklabels=le.classes_)
    plt.title(f'Matriks Konfusi - ({label})')
    plt.xlabel('Prediksi'); plt.ylabel('Aktual')
    plt.tight_layout(); plt.show()
    return oa, kappa

oa2020, kappa2020 = validasi(class_map2020, le2020, base_air2020, '2020')
oa2025, kappa2025 = validasi(class_map2025, le2025, base_air2025, '2025')
```

## 5. Analisis perubahan karang
Dalam tahapan analisis data dilakukan:
- Pembagian area dalam 4 zona
- Perhitungan luas
- Deteksi perubahan
- Visualisasi
- Menyimpan hasil

+++

### a. Pembagian area dalam 4 zona
Pembagian wilayah menjadi empat blok zona dilakukan untuk mempersempit area analisis sehingga proses identifikasi objek dapat dilakukan secara lebih detail.

```{code-cell} ipython3
def buat_zona(dims):
    h, w = dims
    mh, mw = h // 2, w // 2
    zona = np.zeros(dims, dtype=int)
    zona[:mh, :mw] = 1
    zona[:mh, mw:] = 2
    zona[mh:, :mw] = 3
    zona[mh:, mw:] = 4
    return zona

def plot_zona(class_map, label):
    h, w = class_map.shape
    mh, mw = h // 2, w // 2
    fig, ax = plt.subplots(figsize=(5, 5))
    ax.imshow(class_map, cmap=ListedColormap(color_lists), vmin=0, vmax=3)
    ax.axvline(mw, color='black', linewidth=2, linestyle='--')
    ax.axhline(mh, color='black', linewidth=2, linestyle='--')
    for txt, x, y in [('Zona 1\nBarat Laut', 30, 30), ('Zona 2\nTimur Laut', w - 30, 30), ('Zona 3\nBarat Daya', 30, h - 30), ('Zona 4\nTenggara', w - 30, h - 30)]:
        ax.text(x, y, txt, color='white', ha='right' if x > w / 2 else 'left', va='bottom' if y > h / 2 else 'top', bbox=dict(boxstyle='round,pad=0.3', facecolor='black', alpha=0.7))
    ax.axis('off'); ax.set_title(label)
    plt.tight_layout(); plt.show()

plot_zona(class_map2020, '')
```

### b. Perhitungan luas
Perhitungan luasan terumbu karang dilakukan untuk mengetahui luas area terumbu karang pada setiap zona berdasarkan hasil klasifikasi citra. Perhitungan dilakukan berdasarkan jumlah piksel yang dikalikan dengan luas piksel citra Sentinel-2 (resolusi 10 meter).

```{code-cell} ipython3
pixel_area=100
def hitung_luas_identik(class_map, le, label, pixel_area):
    zona = buat_zona(class_map.shape)
    rows = []
    for z in range(1, 5):
        m = (zona == z)
        row = {'Zona': f'Zona {z}'}
        for k, nama in enumerate(le.classes_):
            row[nama] = np.sum((class_map == k) & m) * pixel_area / 10000
        rows.append(row)
    df = pd.DataFrame(rows).set_index('Zona')
    total_per_kelas = df.sum(axis=0)
    total_keseluruhan = total_per_kelas.sum()
    df.loc['Total'] = total_per_kelas
    print("=" * 60)
    print(f"LUAS PER ZONA (Hektar) - {label}")
    print("=" * 60)
    print(df.to_string(float_format=lambda x: f"{x:.2f}"))
    print("-" * 60)
    print(f"{'Total Keseluruhan':20}: {total_keseluruhan:.2f} ha\n")
    return df

piksel_teridentifikasi2020 = ~np.isnan(class_map2020)
piksel_teridentifikasi2025 = ~np.isnan(class_map2025)
piksel_teridentifikasi = piksel_teridentifikasi2020 & piksel_teridentifikasi2025
classmap2020 = np.where(piksel_teridentifikasi, class_map2020, np.nan)
classmap2025 = np.where(piksel_teridentifikasi, class_map2025, np.nan)

df_luas2020 = hitung_luas_identik(classmap2020, le2020, '2020', pixel_area)
df_luas2025 = hitung_luas_identik(classmap2025, le2025, '2025', pixel_area)
```

### c. Deteksi perubahan
Deteksi perubahan terumbu karang tahun 2020–2025 dilakukan dengan membandingkan hasil klasifikasi terumbu karang pada kedua tahun untuk mengidentifikasi perubahan luasan dan lokasi terumbu karang. Output dari tahap ini berupa peta perubahan terumbu karang yang menunjukkan tiga kategori perubahan, yaitu tetap, berkurang, dan bertambah.

```{code-cell} ipython3
if class_map2020.shape != class_map2025.shape:
    class_map2020 = zoom(class_map2020, (class_map2025.shape[0]/class_map2020.shape[0], class_map2025.shape[1]/class_map2020.shape[1]), order=0)
cls = list(le2020.classes_)
karang_idx = cls.index('karang')
pixel_area = 100
ha_per_pixel = pixel_area / 10000
karang_tetap = (class_map2020 == karang_idx) & (class_map2025 == karang_idx) & piksel_teridentifikasi
karang_berkurang = (class_map2020 == karang_idx) & (class_map2025 != karang_idx) & piksel_teridentifikasi
karang_bertambah = (class_map2020 != karang_idx) & (class_map2025 == karang_idx) & piksel_teridentifikasi
luas_tetap = np.sum(karang_tetap) * ha_per_pixel
luas_berkurang = np.sum(karang_berkurang) * ha_per_pixel
luas_bertambah = np.sum(karang_bertambah) * ha_per_pixel
print("=== PERUBAHAN TERUMBU KARANG ===")
print(f"Karang tetap      : {luas_tetap:.2f} ha")
print(f"Karang berkurang  : {luas_berkurang:.2f} ha")
print(f"Karang bertambah  : {luas_bertambah:.2f} ha")
change_map = np.zeros_like(class_map2020, dtype=np.uint8)
change_map[karang_tetap] = 1
change_map[karang_berkurang] = 2
change_map[karang_bertambah] = 3
colors_change = ['#00000000','#1f78b4','#e31a1c','#33a02c']  # transparan untuk kelas lain
legend = [Patch(facecolor='white', edgecolor='black', label='Kelas lain'), Patch(facecolor='#1f78b4', edgecolor='black', label=f'Karang tetap ({luas_tetap:.2f} ha)'), Patch(facecolor='#e31a1c', edgecolor='black', label=f'Karang berkurang ({luas_berkurang:.2f} ha)'), Patch(facecolor='#33a02c', edgecolor='black', label=f'Karang bertambah ({luas_bertambah:.2f} ha)')]
fig, ax = plt.subplots(figsize=(5,5), dpi=150)
ax.imshow(change_map, cmap=ListedColormap(colors_change), interpolation='nearest')
ax.set_title('Perubahan Tutupan Terumbu Karang 2020–2025')
ax.axis('off')
ax.legend(handles=legend, bbox_to_anchor=(0.1, 0.01), loc='upper left', title='Legenda')
plt.tight_layout()
plt.show()
```

### d. Visualisasi
Visualisasi dilakukan untuk menampilkan seluruh hasil dari setiap tahapan analisis dalam bentuk peta dan informasi pendukung yang mudah diinterpretasikan. Tahap ini menghasilkan tampilan interaktif yang mencakup citra hasil klasifikasi, dan visualisasi perubahan terumbu karang pada tahun 2020-2025.

```{code-cell} ipython3
def peta_layer(class_map, label, min_lon, min_lat, max_lon, max_lat, colors, show=False):
    fig, ax = plt.subplots(figsize=(8, 8), frameon=False)
    ax.imshow(class_map, cmap=ListedColormap(colors), vmin=0, vmax=3)
    ax.axis('off')
    plt.tight_layout(pad=0)
    buf = BytesIO()
    plt.savefig(buf, format='png', bbox_inches='tight', pad_inches=0, dpi=150)
    plt.close()
    buf.seek(0)
    img_base64 = base64.b64encode(buf.read()).decode('utf-8')
    buf.close()
    return folium.raster_layers.ImageOverlay(image='data:image/png;base64,' + img_base64, bounds=[[min_lat, min_lon], [max_lat, max_lon]], opacity=1, name=f' {label}', show=show)
colors = color_lists
m = folium.Map(location=[(min_lat + max_lat) / 2, (min_lon + max_lon) / 2], zoom_start=12, tiles='https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}', attr='Esri')
layer_2020 = peta_layer(class_map2020, 'Klasifikasi 2020', min_lon, min_lat, max_lon, max_lat, colors, show=True)
layer_2020.add_to(m)
layer_2025 = peta_layer(class_map2025, 'Klasifikasi 2025', min_lon, min_lat, max_lon, max_lat, colors, show=False)
layer_2025.add_to(m)
layer_change = peta_layer(change_map, 'Perubahan Terumbu Karang 2020-2025', min_lon, min_lat, max_lon, max_lat, colors_change, show=False)
layer_change.add_to(m)
folium.LayerControl().add_to(m)
plugins.Fullscreen().add_to(m)
display(m)
```

### e. Menyimpan hasil
Hasil pemrosesan akan muncul di folder tempat notebook berada dengan format GeoTIFF.

+++

Simpan Hasil Depth Invariant Index 2020 dan 2025

```{code-cell} ipython3
def export_rgb(DII_GR, DII_BR, DII_BG, filename):
    def normalize(data):
        vals = data.values
        vmin = np.nanpercentile(vals, 2)
        vmax = np.nanpercentile(vals, 98)
        return np.clip((vals-vmin)/(vmax-vmin),0,1)
    R = normalize(DII_GR)
    G = normalize(DII_BR)
    B = normalize(DII_BG)
    rgb = xr.concat([
        xr.DataArray(R, coords=DII_GR.coords, dims=DII_GR.dims),
        xr.DataArray(G, coords=DII_GR.coords, dims=DII_GR.dims),
        xr.DataArray(B, coords=DII_GR.coords, dims=DII_GR.dims)
    ], dim="band")
    rgb = rgb.assign_coords(band=[1,2,3])
    rgb = rgb.rio.write_crs(output_crs, inplace=False)
    rgb.rio.to_raster(filename)

export_rgb(DII_GR2020,DII_BR2020,DII_BG2020,"files/DII_RGB_2020.tif")
export_rgb(DII_GR2025,DII_BR2025,DII_BG2025,"files/DII_RGB_2025.tif")
```

Simpan hasil klasifikasi 2020, 2025, dan perubahannya

```{code-cell} ipython3
def simpan_geotiff(array, geobox, output):
    meta = {'driver': 'GTiff','height': array.shape[0],'width': array.shape[1],'count': 1,'dtype': rasterio.uint8,'crs': geobox.crs,'transform': geobox.affine,'nodata': 0}
    with rasterio.open(output, 'w', **meta) as dst:
        dst.write(array.astype(rasterio.uint8), 1)
class_map2020_clean = np.nan_to_num(class_map2020, nan=0).astype(np.uint8)
class_map2025_clean = np.nan_to_num(class_map2025, nan=0).astype(np.uint8)

# Hasil Klasifikasi 2020
simpan_geotiff(class_map2020_clean, base_air2020.odc.geobox, 'files/klasifikasi_2020.tif')
# Hasil Klasifikasi 2025
simpan_geotiff(class_map2025_clean, base_air2025.odc.geobox, 'files/klasifikasi_2025.tif')
# Perubahan Terumbu Karang 2020 dan 2025
simpan_geotiff(change_map, base_air2020.odc.geobox, "files/perubahan_karang_2020_2025.tif")
```

# Catatan

Modul ini mengidentifikasi perubahan luasan dan kondisi terumbu karang di Pulau Boni, Raja Ampat, dengan membandingkan citra Sentinel-2 tahun 2020 dan 2025. Metode yang diterapkan dimulai dari pemisahan darat-laut, pembuatan sampel titik secara interaktif untuk mengoreksi pengaruh kolom air melalui Transformasi Lyzenga sehingga diperoleh citra Depth Invariant Index (DII). Citra DII tersebut kemudian menjadi input klasifikasi Random Forest untuk memetakan empat kelas tutupan dasar perairan (substrat, lamun, karang, laut dalam) pada masing-masing periode, dengan akurasi klasifikasi diukur melalui matriks konfusi serta dilakukan validasi.

Hasil pemrosesan mencakup peta klasifikasi tutupan dasar perairan untuk tahun 2020 dan 2025, estimasi luasan terumbu karang, serta peta deteksi perubahan spasiotemporal yang menunjukkan area karang yang tetap maupun berkurang antar dua periode. Seluruh keluaran utama berupa citra komposit DII, peta klasifikasi, dan peta perubahan disimpan dalam format GeoTIFF di folder files/, sehingga hasil identifikasi perubahan terumbu karang ini dapat diverifikasi ulang, dibagikan, maupun diintegrasikan ke dalam pelaporan atau sistem informasi geospasial lainnya.

+++

# Info

- Skrip ini dikembangkan oleh **Muhammad Arva Akhadi** [arvaakhadi@students.undip.ac.id](mailto:arvaakhadi@students.undip.ac.id)
- Jika ada pertanyaan atau komentar, silahkan email ke piksel@big.go.id
- **Lisensi:** Skrip dalam notebook ini dilisensikan berdasarkan [Apache License, Version 2.0](https://www.apache.org/licenses/LICENSE-2.0). 
Data Piksel dilisensikan berdasarkan lisensi [Creative Commons by Attribution 4.0](https://creativecommons.org/licenses/by/4.0/).
