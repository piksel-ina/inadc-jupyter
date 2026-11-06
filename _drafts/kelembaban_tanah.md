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

| <h1><b>Pemetaan Kelembaban Tanah</b></h1> | ![](files/piksel_logo_small.png) |
|:---------|----------:|
- **Data:** Sentinel-1, Sentinel-2
- **Lokasi:** Kabupaten Bantaeng, Prov Sulawesi Selatan
- **Metode:** Penggunaan citra radar

+++

# Pendahuluan
Modul ini bertujuan untuk memberikan contoh penggunaan data Sentinel-1 untuk menentukan tingkat kelembaban tanah. Citra Sentinel-1 menggunakan teknologi radar SAR (Synthetic Aperture Radar) yang dapat menembus awan dan beroperasi siang-malam untuk memantau kelembaban tanah. Gelombang radar yang dipancarkan akan dipantulkan berbeda oleh permukaan tanah tergantung kandungan airnya - tanah yang lebih lembab memiliki nilai backscatter yang lebih tinggi karena air meningkatkan konstanta dielektrik tanah. Data backscatter ini kemudian diolah menggunakan berbagai algoritma dan model untuk menghasilkan peta kelembaban tanah yang berguna untuk pertanian, hidrologi, dan manajemen bencana kekeringan atau banjir.

Data Sentinel-2 juga dimuat untuk verifikasi hasil analisis dengan keadaan sebenarnya. Lokasi yang digunakan adalah di Kabupaten Bantaeng, Prov. Sulawesi Selatan [🔗](https://maps.app.goo.gl/UtXeQQBmq6CqzpKF7)

+++

# Tahapan

Tahapan dalam analisis kelembaban tanah adalah sebagai berikut:
1. Memuat library
2. Menggunakan _distributed computing_
3. Menentukan wilayah
4. Memuat data
5. Memroses data
6. Menampilkan peta
***

+++

## 1. Memuat library
Library yang diperlukan dimuat ke sistem dan melakukan inisialisasi datacube.

```{code-cell} ipython3
import datacube, io, base64
from planetary_computer import sign_url
from pystac_client import Client as pClient
from dask.distributed import Client, LocalCluster
from odc.stac import load
from odc.geo.geom import point
from pyproj import Transformer
import numpy as np
from PIL import Image

import matplotlib.pyplot as plt
from matplotlib.colors import ListedColormap, BoundaryNorm
from ipyleaflet import basemaps
import folium
from folium import plugins

# Initialize Open Data Cube
dc = datacube.Datacube(app='pemetaan kelembaban tanah')
```

Selain itu, dibuat setting untuk akses data Sentinel-1.

```{code-cell} ipython3
# Microsoft Planetary Computer STAC Catalog URL
catalog = "https://planetarycomputer.microsoft.com/api/stac/v1"

# Membuat STAC Client
client = pClient.open(catalog)
```

## 2. Menggunakan _distributed computing_
Menghitung nilai maksimum untuk setiap piksel dalam sebuah gambar dapat memakan banyak komputasi. Namun, waktu komputasi dapat dikurangi dengan memparalelkan proses melalui Dask [🔗](https://docs.dask.org/en/stable/index.html)

Untuk menyiapkan _distributed computing_ dengan Dask, Anda perlu menyiapkan klien Dask terlebih dahulu menggunakan fungsi di bawah ini:

```{code-cell} ipython3
def create_local_dask_cluster():
    cluster = LocalCluster()
    client = Client(cluster)
    print(f"✅ Dask cluster berjalan di {client.dashboard_link}")
    return client

create_local_dask_cluster()
```

## 3. Menentukan wilayah
Area yang akan diproses yaitu di Kabupaten Bantaeng ditentukan dan ditampilkan.

```{code-cell} ipython3
# Koordinat lokasi
latitude = (-5.510, -5.590)
longitude = (120.020, 120.100) 
lat = (latitude[0] + latitude[1])/2
lon = (longitude[0] + longitude[1])/2
aoi = point(lon, lat, crs="epsg:4326")
time_range = ('2025-02-01', '2025-03-31')
aBuffer = abs(lat - latitude[0])

# Membuat bounding box 
region = aoi.buffer(aBuffer).boundingbox.polygon
region.explore(tiles=basemaps.Esri.WorldImagery)
```

## 4. Memuat data
Data yang dimuat adalah Sentinel-2 untuk tampilan color composite dan data Sentinel-1 untuk analisis kelembaban tanah. Data di bulan Februari-Maret 2025 dimuat untuk digunakan dalam analisis.

+++

### Memuat data Sentinel-2

```{code-cell} ipython3
# mencari data
sentinel2_datasets = dc.find_datasets(
    product=["s2_l2a"],
    time=(time_range[0], time_range[1]),
    longitude=longitude,
    latitude=latitude,
    cloud_cover=(0, 80),
)
print(f"Ditemukan {len(sentinel2_datasets)} Sentinel-2 data")
```

```{code-cell} ipython3
# Load data
data_s2 = dc.load(
    datasets=sentinel2_datasets,
    longitude=longitude,
    latitude=latitude, 
    measurements=['red', 'green', 'blue'],
    dask_chunks={"x": 1000, "y": 1000, "time":-1}, 
    resolution=(-10,10),
    group_by="solar_day",
    output_crs="EPSG:32748",
    driver="rio",
)
print(data_s2)
```

```{code-cell} ipython3
# Data terpilih dengan awan paling sedikit
target_dates = ["2025-03-31"]
data_s2_sel = data_s2.sel(time = target_dates, method="nearest")

# Plot data
rgb = data_s2_sel[['red', 'green', 'blue']].to_array(dim='band')
rgb.plot.imshow(col="time", col_wrap=2, size=4, vmin=0, vmax=3000, robust=True)
```

### Memuat data Sentinel-1

```{code-cell} ipython3
# mencari data
items = client.search(
    collections=["sentinel-1-rtc"],
    intersects=region,
    datetime=time_range,
).item_collection()

print(f"Ditemukan {len(items)} data S-1")
```

```{code-cell} ipython3
# memuat data Sentinel-1
data_s1 = load(
    items,
    geopolygon=region,
    measurements=["vv", "vh"],
    groupby="solar_day",
    patch_url=sign_url,
    chunks={"x": 2048, "y": 2048}
).compute()
```

## 5. Memroses data

Menghitung koefisien backscatter (dB) dan disimpan dalam `data`

```{code-cell} ipython3
data_s1['vv_db'] = 10 * np.log10(data_s1['vv'])
data_s1['vh_db'] = 10 * np.log10(data_s1['vh'])
data_s1
```

```{code-cell} ipython3
# menghitung cross-polarization ratio
data_s1['vh_vv_ratio'] = data_s1['vh_db'] - data_s1['vv_db']
data_s1
```

Perhitungan _soil moisture index_ dari nilai backscatter. Nilai backscatter yang tinggi menunjukan kelembaban yang tinggi.

```{code-cell} ipython3
# fungsi untuk menghitung soil moisture index 
def calculate_soil_moisture_index(vv_db):
    # Normalize backscatter values
    smi = (vv_db - vv_db.min()) / (vv_db.max() - vv_db.min())
    return smi

data_s1['soil_moisture_index'] = calculate_soil_moisture_index(data_s1['vv_db'])
soil_moisture_mean = data_s1['soil_moisture_index'].mean(dim='time')
```

## 6. Menampilkan peta
Data ditampilkan dalam bentuk peta dan dual map untuk membandingkan dengan kondisi sesungguhnya.

```{code-cell} ipython3
# menentukan moisture threshold dan warnanya
bounds = [0, 0.3, 0.35, 0.42, 1.0]
colors = ['blue', 'sandybrown', 'yellow', 'forestgreen']  # tubuh air, tanah kering, sedang, lembab
labels = ['Tubuh Air', 'Tanah Kering', 'Tanah Sedang', 'Tanah Lembab']

# membuat colormap dan normalisasi
cmap = ListedColormap(colors)
norm = BoundaryNorm(bounds, ncolors=len(colors))
dpi = 300
fig_width = 893/300
fig_height = 890/300
plt.figure(figsize=(fig_width, fig_height), dpi=dpi)
im = soil_moisture_mean.plot(cmap=cmap, norm=norm, add_colorbar=False)

# colorbar
bounds_tick = bounds[1:]
cbar = plt.colorbar(im, ticks=bounds_tick)
cbar.ax.set_yticklabels(labels, fontsize=5)
plt.tick_params(axis='both', labelsize=5)

plt.title('Peta Kelembaban Tanah', fontsize=7)
plt.xlabel('meter', fontsize=5)
plt.ylabel('meter', fontsize=5)
plt.grid(False)
plt.tight_layout()
```

Berikut adalah menampilkan data kondisi sesungguhnya dan kelembaban tanah untuk memudahkan analisis. 

```{code-cell} ipython3
target_dates = ["2025-03-31"]
data_sel = data_s2.sel(time=target_dates, method="nearest").isel(time=0)

# membuat RGB array
rgb_da = data_sel[['red', 'green', 'blue']].to_array(dim='band')
rgb_computed = rgb_da.compute()  # dimuat ke memori

# Normalisasi 0-255 untuk tampilan
rgb_normalized = []
for i in range(3):
    band = rgb_computed[i].values
    valid_data = band[~np.isnan(band)]
    # untuk contrast
    vmin, vmax = np.percentile(valid_data, [1, 99])
    # untuk brightness
    gamma = 2.2
    band_norm = ((band - vmin) / (vmax - vmin)) ** (1/gamma)
    band_norm = np.clip(band_norm * 255, 0, 255).astype(np.uint8)
    rgb_normalized.append(band_norm)
# menumpuk data 
rgb_image = np.stack(rgb_normalized, axis=-1)

crs = rgb_da.spatial_ref.attrs.get('crs_wkt', f'EPSG:{rgb_da.spatial_ref.item()}')
transformer = Transformer.from_crs(crs, "EPSG:4326", always_xy=True)
x_min, x_max = float(rgb_da.x.min()), float(rgb_da.x.max())
y_min, y_max = float(rgb_da.y.min()), float(rgb_da.y.max())
lon_min, lat_min = transformer.transform(x_min, y_min)
lon_max, lat_max = transformer.transform(x_max, y_max)
map_bounds = [[lat_min, lon_min], [lat_max, lon_max]]

# Membuat peta
m = plugins.DualMap(location=(lat, lon), zoom_start=14, tiles=None)
img = Image.fromarray(rgb_image, mode='RGB')
img_buffer = io.BytesIO()
img.save(img_buffer, format='PNG')
img_str = base64.b64encode(img_buffer.getvalue()).decode()

folium.raster_layers.ImageOverlay(
    image=f'data:image/png;base64,{img_str}',
    bounds=map_bounds,
    opacity=1.0,
    name='RGB Composite'
).add_to(m.m1)

folium.TileLayer('OpenStreetMap').add_to(m.m1)
folium.TileLayer('OpenStreetMap').add_to(m.m2)
soil_moisture_mean.odc.add_to(m.m2, cmap=cmap, name="kelembaban tanah", opacity=0.8)

folium.LayerControl().add_to(m.m1)
folium.LayerControl().add_to(m.m2)
m
```

# Catatan
Secara umum, Sentinel-1 dapat digunakan untuk mendapatkan kelembaban tanah walaupun masih terdapat beberapa kekurangan. Verifikasi lapangan perlu dilakukan untuk memastikan validitas data.

+++

# Info

- Modul ini dijalankan di platform Piksel. Jika ada pertanyaan atau komentar, silahkan email ke piksel@big.go.id
- **Lisensi:** Skrip dalam notebook ini dilisensikan berdasarkan [Apache License, Version 2.0](https://www.apache.org/licenses/LICENSE-2.0). 
Data Piksel dilisensikan berdasarkan lisensi [Creative Commons by Attribution 4.0](https://creativecommons.org/licenses/by/4.0/).
