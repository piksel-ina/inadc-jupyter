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

| <h1><b>Monitoring Suhu Permukaan di Area PLTP</b></h1> | ![](files/piksel_logo_small.png) |
|:---------|----------:|
- **Data:** Landsat 9 (Surface Reflectance & Temperature)
- **Lokasi:** Pembangkit Listrik Tenaga Panas Bumi (PLTP), Kamojang, Jawa Barat
- **Metode:** Normalized Difference Vegetation Index (NDVI) dan Land Surface Temperature (LST)

+++

# Pendahuluan
Modul ini bertujuan untuk memberikan contoh penggunaan metode Normalized Difference Vegetation Index (NDVI) dan Land Surface Temperature (LST) untuk mengetahui kondisi suhu permukaan di sekitar area Pembangkit Listrik Tenaga Panas Bumi (PLTP). Pemahaman terhadap suhu permukaan dapat menunjukkan aktifitas PLTP dan potensi pengembangan PLTP tersebut. Lokasi yang dipilih adalah area PLTP di Kamojang, Jawa Barat [🔗](https://maps.app.goo.gl/iQuVombJCoWtWNGZ9)

+++

# Tahapan

Tahapan dalam analisis suhu permukaan adalah sebagai berikut:
1. Memuat library
2. Koneksi data
3. Menentukan wilayah
4. Memuat data Landsat
5. Membuat geomedian
6. Perhitungan NDVI
7. Perhitungan emisivitas
8. Perhitungan LST
***

+++

## 1. Memuat library
Tahapan awal adalah memuat library yang diperlukan. Karena library pylandtemp belum diinstal, maka perlu di download terlebih dahulu.

```{code-cell} ipython3
!pip install pylandtemp
```

```{code-cell} ipython3
%matplotlib inline

import datacube, folium, os
from odc.geo.geom import point
from odc.stac import configure_s3_access
from piksel.utils import patch_usgs_landsat

# pylandtemp untuk menghitung LST dan emisivitas citra Landsat
from pylandtemp import ndvi
from pylandtemp import emissivity
from pylandtemp.temperature.algorithms.mono_window import MonoWindowLST

import xarray as xr 
import numpy as np 
import matplotlib.pyplot as plt
from folium import plugins
```

## 2. Koneksi data
Melakukan koneksi dengan data Landsat dan Datacube

```{code-cell} ipython3
# Konfigurasi koneksi data Landsat di AWS
os.environ["AWS_DEFAULT_REGION"] = "us-west-2"
if "AWS_NO_SIGN_REQUEST" in os.environ:
    del os.environ["AWS_NO_SIGN_REQUEST"]
configure_s3_access(requester_pays=True)

# Koneksi ke Datacube
dc = datacube.Datacube(app='Land_Surface')
```

## 3. Menentukan wilayah
Koordinat lokasi dari PLTP Kamojang ditentukan dan ditampilkan dalam peta

```{code-cell} ipython3
# Area PLTP Kamojang
lat_range = (-7.16995, -7.11382)
lon_range = (107.76625, 107.81554)

cen_lat = (lat_range[0] + lat_range[1]) / 2
cen_lon = (lon_range[0] + lon_range[1]) / 2
buf_dist = (lon_range[1] - lon_range[0])/2

coords = cen_lat, cen_lon   
aoi_point = point(coords[1], coords[0], crs="EPSG:4326")
bbox = aoi_point.buffer(buf_dist).boundingbox

# Tampilkan area PLTP dalam peta
bbox.explore(zoom=5)
```

## 4. Memuat data Landsat
Data Landsat 9 (Surface dan Thermal Reflectance) dibuka dari storage di AWS.

```{code-cell} ipython3
# Parameter untuk memuat data
meas_refl = ['red', 'nir08']
meas_temp = ['ST_B10']
crs = "EPSG:32750"
resolusi = 30
waktu = ("2024-01", "2024-06")
```

```{code-cell} ipython3
# Memuat data Landsat 9 surface reflectance
refl_2024 = dc.load(
    product='ls9_c2l2_sr',
    measurements=meas_refl,
    output_crs=crs,
    resolution=resolusi,
    time=waktu,
    longitude=(lon_range[0], lon_range[1]),
    latitude=(lat_range[0], lat_range[1]),
    dask_chunks={"time": 1, "x": 1000, "y": 1000},
    group_by="solar_day",
    driver="rio",
    patch_url=patch_usgs_landsat
)

print(refl_2024)
```

```{code-cell} ipython3
# Memuat data Landsat 9 surface temperature
temp_2024 = dc.load(
    product='ls9_c2l2_st',
    measurements=meas_temp,
    output_crs=crs,
    resolution=resolusi,
    time=waktu,
    longitude=(lon_range[0], lon_range[1]),
    latitude=(lat_range[0], lat_range[1]),
    dask_chunks={"time": 1, "x": 1000, "y": 1000},
    group_by="solar_day",
    driver="rio",
)
print(temp_2024)
```

Data Landsat 9 di area PLTP untuk sebagian tahun 2024 ditampilkan untuk mengetahui kondisi data seperti berawan atau ada data kosong.

```{code-cell} ipython3
# Menampilkan data band red
refl_2024.red.plot(col='time', col_wrap=4, robust=True, cmap='gray')
plt.suptitle("Landsat 9 Band Red (2024)", fontsize=16, y=1.05)
plt.show()
```

```{code-cell} ipython3
# Menampilkan data band ST_B10
temp_2024.ST_B10.plot(col='time', col_wrap=4, robust=True, cmap='inferno')
plt.suptitle("Landsat 9 Thermal Band ST_B10 (2024)", fontsize=16, y=1.05)
plt.show()
```

## 5. Membuat geomedian
Geomedian adalah metode statistik untuk membuat citra komposit yang jernih dari data dalam kurun waktu tertentu. Data dengan kondisi baik (tidak banyak awan dan tidak ada data kosong) dipilih untuk pemrosesan geomedian

```{code-cell} ipython3
selected_indices = [1, 19, 21]

# membuat geomedian untuk surface reflectance
selected_images = refl_2024.isel(time=selected_indices)
refl_median = selected_images.median(dim='time').compute()
refl_median
```

```{code-cell} ipython3
# membuat geomedian untuk surface temperature
selected_images = temp_2024.isel(time=selected_indices)
temp_median = selected_images.median(dim='time').compute()
temp_median
```

Menampilkan hasil geomedian

```{code-cell} ipython3
# menampilkan geomedian band red
refl_median['red'].plot.imshow(cmap="Reds", robust=True)
plt.title("Geomedian Band Red")
```

```{code-cell} ipython3
# menampilkan geomedian band ST_B10
temp_median['ST_B10'].plot.imshow(cmap="inferno", robust=True)
plt.title("Geomedian Band ST_B10")
```

## 6. Perhitungan NDVI
Normalized Difference Vegetation Index (NDVI) digunakan untuk mengetahui wilayah yang bervegetasi dan tidak bervegetasi.

```{code-cell} ipython3
# Ekstrak band red dan nir dari xarray Dataset sebagai numpy array
red_band = refl_median['red'].values
nir_band = refl_median['nir08'].values
# Membuat mask untuk area dengan nilai 0 (biasanya area tanpa data/awan)
mask = (red_band == 0) | (nir_band == 0)

# Menghitung NDVI menggunakan pylandtemp
ndvi_result = ndvi(nir_band, red_band, mask=mask)
```

Menampilkan data NDVI

```{code-cell} ipython3
im = plt.imshow(ndvi_result, cmap='RdYlGn')
plt.colorbar(im, label='Nilai NDVI', shrink=0.8)
plt.title('Peta NDVI {}'.format(ndvi_result.shape), fontsize=14)
plt.xlabel('Kolom (Column)')
plt.ylabel('Baris (Row)')

plt.show()
```

## 7. Perhitungan Emisivitas

Emisivitas adalah efektivitas suatu permukaan benda dalam memancarkan energi dalam bentuk radiasi termal. Nilainya berkisar antara 0 dan 1:
- Emisivitas = 1: Benda ini adalah "pemancar sempurna" atau disebut benda hitam (black body). Benda ini memancarkan 100% energi panas yang dimilikinya. 
- Emisivitas = 0: Benda ini adalah "reflektor sempurna". Benda ini tidak memancarkan panas sama sekali, melainkan memantulkan semua energi termal yang datang padanya.

```{code-cell} ipython3
emissivity_10, _ = emissivity(
    ndvi_image=ndvi_result,
    emissivity_method='xiaolei',
    landsat_band_4=red_band
)
print(f"Shape Emisivitas Band 10: {emissivity_10.shape}")
```

Menampilkan peta emisivitas

```{code-cell} ipython3
# Data dalam xarray agar berkoordinat
grid_coords = refl_median.coords
dims = refl_median['red'].dims
emissivity_10_da = xr.DataArray(emissivity_10, coords=grid_coords, dims=dims, name='emissivity_10')

fig, ax = plt.subplots(1, 1, figsize=(15, 7.5))
emissivity_10_da.plot(ax=ax, cmap='viridis', robust=True, vmin=0.9, vmax=1.0)
ax.set_title('Peta Emisivitas untuk Band Termal 10', fontsize=12)
ax.set_xlabel('Longitude')
ax.set_ylabel('Latitude')

fig.suptitle('Emisivitas - Metode Xiaolei (NDVI-Based Emissivity Method/NBEM)', fontsize=16)
plt.tight_layout(rect=[0, 0, 1, 0.95])
plt.show()
```

## 8. Perhitungan LST
LST dihitung dari data emisivitas dengan menerapkan inversi dari hukum radiasi termal pada data citra satelit. Proses ini memerlukan dua input utama: nilai radiansi termal yang telah dikoreksi secara atmosferis dan nilai emisivitas permukaan tersebut. Secara esensial, nilai radiansi "dibagi" oleh nilai emisivitas untuk mengisolasi komponen suhu dari efisiensi pancaran panas benda, sehingga menghasilkan nilai suhu absolut (dalam Kelvin) yang kemudian dapat dikonversi ke Celcius.

```{code-cell} ipython3
# Extraksi DataArray ST_B10 dari Dataset
bt_10_kelvin_mono = temp_median.ST_B10

# Cek jika nilai perlu scaling
print(f"Kisaran nilai raw: {float(bt_10_kelvin_mono.min()):.2f} - {float(bt_10_kelvin_mono.max()):.2f}")

# Band 10 scaling dalam Kelvin dengan scale factor: 0.00341802, Offset: 149.0
bt_10_kelvin_mono = bt_10_kelvin_mono * 0.00341802 + 149.0

print(f"Kisaran suhu: {float(bt_10_kelvin_mono.min()):.2f} - {float(bt_10_kelvin_mono.max()):.2f} K")

# Membuat cloud mask
cloud_mask_mono = bt_10_kelvin_mono < 270

# Konversi ke numpy arrays
bt_10_numpy = bt_10_kelvin_mono.values
emissivity_numpy = emissivity_10  # Already a numpy array
cloud_mask_numpy = cloud_mask_mono.values

# Menghitung LST
mono_calculator = MonoWindowLST()
lst_mono_kelvin = mono_calculator(
    brightness_temperature_10=bt_10_numpy,
    emissivity_10=emissivity_numpy,
    mask=cloud_mask_numpy
)

# Konversi kembali ke xarray DataArray untuk kemudahan
lst_mono_kelvin_xr = xr.DataArray(
    lst_mono_kelvin,
    coords=bt_10_kelvin_mono.coords,
    dims=bt_10_kelvin_mono.dims,
    name='LST'
)

# Konversi ke Celcius
lst_mono_celsius = lst_mono_kelvin_xr - 273.15

print(f"Kisaran LST: {float(np.nanmin(lst_mono_celsius)):.2f} - {float(np.nanmax(lst_mono_celsius)):.2f} °C")
```

Menampilkan peta LST dengan legenda suhunya

```{code-cell} ipython3
# Konversi data ke xarray.DataArray agar berkoordinat untuk plotting
grid_coords = refl_median.coords
dims = refl_median['red'].dims
lst_mono_da = xr.DataArray(lst_mono_celsius, coords=grid_coords, dims=dims, name='LST Mono Window')

plt.figure(figsize=(12, 6))
lst_mono_da.plot(cmap='turbo', robust=True)
plt.title('Peta Land Surface Temperature (LST)', fontsize=16)
plt.xlabel('Longitude')
plt.ylabel('Latitude')
plt.show()
```

Menampilkan peta LST dalam dual map

```{code-cell} ipython3
# Membuat Dual Map
m = plugins.DualMap(location=(cen_lat, cen_lon), zoom_start=14, tiles=None)

# Menambah citra satelit di peta kiri
folium.TileLayer(
    tiles='https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}',
    attr='Esri',
    name='Satellite'
).add_to(m.m1)

# Menambah OpenStreetMap di peta kanan
folium.TileLayer('OpenStreetMap').add_to(m.m2)

# Menambah peta LST di peta kanan
lst_mono_da.odc.add_to(m.m2, cmap="turbo", robust=True, name="LST", opacity=0.8)

folium.LayerControl().add_to(m.m1)
folium.LayerControl().add_to(m.m2)
m
```

# Catatan
Peta Land Surface Temperature (LST) menunjukkan bahwa kawasan PLTP termasuk pemukiman menunjukkan suhu permukaan yang tinggi (warna kuning, oranye dan merah). Sedang wilayah hutan memiliki suhu lebih rendah (berwarna biru)

+++

# Info

- Modul ini dijalankan di platform Piksel dan diadaptasi dari Bayu MN Makarim (Mahasiswa S1 Geografi, Universitas Negeri Jakarta, bayunabiil1365@gmail.com)
- Jika ada pertanyaan atau komentar, silahkan email ke piksel@big.go.id
- **Lisensi:** Skrip dalam notebook ini dilisensikan berdasarkan [Apache License, Version 2.0](https://www.apache.org/licenses/LICENSE-2.0). 
Data Piksel dilisensikan berdasarkan lisensi [Creative Commons by Attribution 4.0](https://creativecommons.org/licenses/by/4.0/).
