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

| <h1><b>Identifikasi Zona Bahaya Banjir</b></h1> | ![](files/piksel-logo-small.png) |
|:---------|----------:|
- **Data:** DEM, Sentinel-2
- **Lokasi:** Kabupaten Bangka Barat, Prov. Kepulauan Babel
- **Metode:** Zona bahaya banjir berdasarkan data ketinggian [DEM]

+++

## Pendahuluan
Modul ini bertujuan untuk memberikan contoh penggunaan data Digital Elevation Model (DEM) untuk mengidentifikasi area yang berpotensi banjir. DEM adalah representasi digital dari permukaan bumi yang menggambarkan ketinggian atau elevasi setiap titik dalam suatu area. Data DEM biasanya berbentuk grid atau raster, di mana setiap piksel memiliki nilai elevasi tertentu. DEM digunakan dalam berbagai aplikasi seperti pemetaan topografi, analisis hidrologi, perencanaan tata ruang, dan simulasi aliran air. 

DEM yang digunakan adalah dari Copernicus yaitu `cop-dem-glo-30` yang berupa Digital Surface Model (DSM) global dengan resolusi spasial 30 meter yang merepresentasikan permukaan bumi, termasuk bangunan, vegetasi, dan infrastruktur. Dataset ini berasal dari misi radar satelit TanDEM-X (2011–2015) dan telah melalui proses penyuntingan seperti perataan badan air, konsistensi aliran sungai, serta koreksi garis pantai.

Zonasi bahaya banjir secara sederhana adalah mengklasifikasikan wilayah berdasarkan elevasinya. Lokasi yang digunakan adalah di Kabupaten Bangka Barat, Prov. Kepulauan Babel [🔗](https://maps.app.goo.gl/Lxaog8UrewrSoekM7)

+++

## Tahapan

Tahapan dalam identifikasi area berpotensi banjir adalah sebagai berikut:
1. Memuat library
2. Menentukan wilayah
3. Memuat data Sentinel 2
4. Memuat DEM
5. Menampilkan DEM
6. Peta kemiringan lereng
7. Peta zonasi bahaya banjir

***

+++

## 1. Memuat library
Library yang diperlukan dimuat adalah sebagai berikut:

```{code-cell} ipython3
# cell ini dihapus setelah library di install di piksel 
!pip install xarray-spatial plotly
```

```{code-cell} ipython3
import datacube, os, rioxarray, rasterio
from pystac.client import Client
from odc.stac import load
from odc.geo.geom import point, BoundingBox
import xarray as xr
import numpy as np

from ipyleaflet import basemaps
import matplotlib.pyplot as plt
from matplotlib.colors import ListedColormap, BoundaryNorm
from scipy.ndimage import gaussian_filter, zoom 
from xrspatial import slope  
import plotly.graph_objects as go

dc = datacube.Datacube(app='processing DEM')
```

## 2. Menentukan wilayah
Area yang akan diproses ditentukan dan ditampilkan.

```{code-cell} ipython3
aoi = {
    'latitude': (-1.864, -2.158),
    'longitude': (105.088, 105.332),
    'crs': 'EPSG:32748'
}
lat_cent = sum(aoi['latitude'])/2
lon_cent = sum(aoi['longitude'])/2
aBuffer = abs(lat_cent - aoi['latitude'][0])

aoi_point = point(lon_cent, lat_cent, crs="epsg:4326")
bbox = aoi_point.buffer(aBuffer).boundingbox
bbox.explore(tiles=basemaps.Esri.WorldImagery)
```

## 3. Memuat data Sentinel-2

```{code-cell} ipython3
# rentang waktu data
time_range = ('2025-07-19', '2025-07-20')

# Mencari data
sentinel2_datasets = dc.find_datasets(
    product=["s2_l2a"],
    time=(time_range[0], time_range[1]),
    longitude=aoi['longitude'],
    latitude=aoi['latitude'],
    cloud_cover=(0, 80),
)
print(f"Ditemukan {len(sentinel2_datasets)} Sentinel-2 data")
```

```{code-cell} ipython3
# Memuat data
s2 = dc.load(
    datasets=sentinel2_datasets,
    longitude=aoi['longitude'],
    latitude=aoi['latitude'], 
    measurements=['red', 'green', 'blue'],
    dask_chunks={"x": 1000, "y": 1000, "time":-1}, 
    resolution=(-10,10),
    group_by="solar_day",
    output_crs="EPSG:32748",
    driver="rio",
)
s2
```

## 4. Memuat DEM
DEM dari Copernicus yang digunakan adalah `cop-dem-glo-30` dengan resolusi 30 m

```{code-cell} ipython3
# mengecek ketersediaan data
client = Client.open("https://earth-search.aws.element84.com/v1")
collection = "cop-dem-glo-30"
items = client.search(collections=[collection], bbox=list(bbox)).item_collection()

print(f"Ditemukan {len(items)} data DEM")
```

```{code-cell} ipython3
# setting untuk akses DEM di Copernicus
if "AWS_DEFAULT_REGION" in os.environ:
    del os.environ["AWS_DEFAULT_REGION"]

# memuat DEM
dem = load(
    items,
    like=s2.odc.geobox,
).squeeze()
dem
```

## 5. Menampilkan DEM
DEM ditampilkan dalam bentuk peta dan visualisasi 3 dimensi

```{code-cell} ipython3
# menampilkan peta elevasi
dem_data = dem['data']
dem_data.plot(
    cmap='terrain',
    figsize=(8, 6.7),
    robust=True,
    cbar_kwargs={'label': 'Elevasi (m)', 'shrink': 0.8}
)

plt.title('DEM Bangka Barat')
plt.tight_layout()
plt.show()
```

Visualisasi DEM secara 3 dimensi

```{code-cell} ipython3
elevation = dem_data.values 
# Downsample untuk memudahkan proses data (500x500)
downsample_factor = 500 / max(elevation.shape)
elevation_small = zoom(elevation, downsample_factor, order=1)
print(f"▶️ Ukuran setelah downsample: {elevation_small.shape}")
print(f"▶️ Elevassi min: {elevation_small.min()}, max: {elevation_small.max()}")

# Menghitung normalized position dari 0
min_elev = elevation_small.min()
max_elev = elevation_small.max()
zero_norm = (0 - min_elev) / (max_elev - min_elev)
print(f"▶️ Elevasi 0m di normalized position: {zero_norm:.3f}")

# menyiapkan pewarnaaan
colorscale = []
if zero_norm > 0:
    colorscale.extend([
        [0.0, 'rgb(0, 0, 139)'],                    # Deep blue
        [zero_norm * 0.5, 'rgb(0, 100, 200)'],      # Medium blue
        [zero_norm * 0.9, 'rgb(100, 149, 237)'],    # Cornflower blue
    ])
# pada 0 m- LIGHT BLUE (sea level)
colorscale.append([zero_norm, 'rgb(135, 206, 250)'])  # Sky blue (0m)
# diatas 0 m 
if zero_norm < 1:
    remaining = 1 - zero_norm
    colorscale.extend([
        [zero_norm + 0.001, 'rgb(144, 238, 144)'],           # Light green (just above 0m) ← LAND STARTS HERE
        [zero_norm + remaining * 0.2, 'rgb(152, 251, 152)'], # Pale green (lowlands)
        [zero_norm + remaining * 0.4, 'rgb(34, 139, 34)'],   # Forest green (plains)
        [zero_norm + remaining * 0.6, 'rgb(255, 215, 0)'],   # Gold (hills)
        [zero_norm + remaining * 0.75, 'rgb(210, 180, 140)'], # Tan (highlands)
        [zero_norm + remaining * 0.88, 'rgb(139, 69, 19)'],  # Brown (mountains)
        [1.0, 'rgb(255, 250, 250)']                          # Snow white (peaks)
    ])

# plotting
fig = go.Figure(data=[go.Surface(
    z=elevation_small,
    colorscale=colorscale,
    colorbar=dict(
        title="Elevasi (m)",
        tickvals=[min_elev, 0, max_elev],
        ticktext=[f'{min_elev:.0f}m', '0m (Sea Level)', f'{max_elev:.0f}m']
    )
)])
fig.update_layout(
    title='Visualisasi Bangka Barat (3-D)',
    scene=dict(
        xaxis_title='X',
        yaxis_title='Y',
        zaxis_title='Elevasi (m)',
        aspectmode='manual',
        aspectratio=dict(x=2, y=2, z=0.1),
        camera=dict(eye=dict(x=1.87, y=0.88, z=1))
    ),
    width=1000,
    height=700
)
fig.show()
```

## 6. Peta kemiringan lereng
Untuk mengetahui kondisi topografi suatu wilayah, maka peta kemiringan lereng dibuat.

```{code-cell} ipython3
dem_data = dem['data']

# Gaussian smoothing digunakan utk mengurangi noise
dem_smoothed = gaussian_filter(dem_data.values, sigma=1.5)

# membuat xarray DataArray 
dem_smooth_da = xr.DataArray(
    dem_smoothed,
    coords=dem_data.coords,
    dims=dem_data.dims
)
# menghitung slope
slope_deg = slope(dem_smooth_da)
# plot
fig, axes = plt.subplots(1, 2, figsize=(18, 8))
dem_smooth_da.plot(ax=axes[0], cmap='terrain', robust=True)
axes[0].set_title('Peta Ketinggian (m)')

slope_deg.plot(ax=axes[1], cmap='YlOrRd', robust=True,
               cbar_kwargs={'label': 'Kemiringan (º)'})
axes[1].set_title('Peta Kemiringan Lereng (º)')

plt.tight_layout()
plt.show()
```

## 7. Peta zonasi bahaya banjir
Analisis sederhana untuk memetakan area yang memiliki potensi banjir dilakukan dengan menggunakan data DEM. Terapat 4 kelas:
1. Bahaya tinggi (elevasi < 5m)
2. Bahaya sedang (5m <= elevasi <= 20m)
3. Bahaya rendah (elevasi > 20m)

```{code-cell} ipython3
# fungsi untuk klasifikasi daerah bahaya banjir
def classify_flood_risk(dem_array):
    lim_high = 5    
    lim_medium = 10  
    lim_low = 20     
    min_elev = np.nanmin(dem_array)

    risk_map = np.zeros_like(dem_array)
    risk_map[dem_array < lim_high] = 4   
    risk_map[(dem_array >= lim_high) & (dem_array < lim_medium)] = 3  # High Risk
    risk_map[(dem_array >= lim_medium) & (dem_array < lim_low)] = 2  # Medium Risk
    risk_map[(dem_array >= lim_low)] = 1  # Low Risk

    return risk_map, [min_elev, lim_high, lim_medium, lim_low]

flood_risk, thresholds = classify_flood_risk(dem_data.values)
```

```{code-cell} ipython3
# memasukkan flood_risk di DataArray
flood_risk_da = xr.DataArray(
    flood_risk,
    coords=dem_data.coords,
    dims=dem_data.dims,
    name="flood_risk"
)

flood_risk_da = flood_risk_da.rio.write_crs("EPSG:32748")
```

```{code-cell} ipython3
# menampilkan statistik dan peta
print("🟢🟠🔴 Zonasi bahaya banjir")
print(f"   ▶️ Bahaya tinggi (0-5 m) :  {np.sum(flood_risk == 3) / flood_risk.size * 100:.2f} %")
print(f"   ▶️ Bahaya sedang (5-20 m): {np.sum(flood_risk == 2) / flood_risk.size * 100:.2f} %")
print(f"   ▶️ Bahaya rendah (> 20 m): {np.sum(flood_risk == 1) / flood_risk.size * 100:.2f} %")
print(f"   ▶️ Tubuh air             : {np.sum(flood_risk == 4) / flood_risk.size * 100:.2f} %")

# Plot
fig, axes = plt.subplots(1, 2, figsize=(18, 8))

# DEM
dem_data.plot(ax=axes[0], cmap='terrain', robust=True)
axes[0].set_title('Digital Elevation Model', fontsize=12, fontweight='bold')

# Flood Risk Map
colors = ['#2E7D32', '#FDD835', '#D32F2F', '#87CEEB']  
cmap = ListedColormap(colors)
bounds = [0.5, 1.5, 2.5, 3.5, 4.5]
norm = BoundaryNorm(bounds, cmap.N)

# gunakan flood_risk_da (xarray) bukan flood_risk (numpy)
im = flood_risk_da.plot.imshow(
    ax=axes[1],
    cmap=cmap,
    norm=norm,
    add_colorbar=False  # supaya kita bisa custom colorbar
)

axes[1].set_title('Peta Bahaya Banjir', fontsize=12, fontweight='bold')

# Custom colorbar
cbar = plt.colorbar(im, ax=axes[1], ticks=[1, 2, 3, 4])
cbar.ax.set_yticklabels(['Rendah', 'Sedang', 'Tinggi', 'Tubuh air'])

plt.tight_layout()
plt.show()
```

## Catatan
Data DEM dapat digunakan untuk penyusunan zonasi bahaya banjir secara sederhana. Untuk hasil yang lebih akurat, pemodelan spasial dengan menggunakan data curah hujan dan tutupan lahan perlu dilakukan.

+++

## Info

- Modul ini dijalankan di platform Piksel. Jika ada pertanyaan atau komentar, silahkan email ke piksel@big.go.id
- **Lisensi:** Skrip dalam notebook ini dilisensikan berdasarkan [Apache License, Version 2.0](https://www.apache.org/licenses/LICENSE-2.0). 
Data Piksel dilisensikan berdasarkan lisensi [Creative Commons by Attribution 4.0](https://creativecommons.org/licenses/by/4.0/).
