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

| <h1><b>Monitoring Kondisi Danau</b></h1> | ![](files/piksel_logo_small.png) |
|:---------|----------:|
- **Data:** Sentinel-2
- **Lokasi:** Danau Kelimutu, Kab. Ende, Provinsi Nusa Tenggara Timur
- **Metode:** Modified Normalized Difference Water Index (MNDWI)

+++

# Pendahuluan
Modul ini bertujuan untuk memberikan contoh penggunaan metode MNDWI (Modified Normalized Difference Water Index) untuk menghitung luas danau sekaligus memonitor kondisi danau. MNDWI adalah indeks spektral yang digunakan untuk membedakan perairan dan daratan dengan menggunakan band Green dan SWIR. Lokasi yang digunakan adalah danau Kelimutu di kabupaten Ende, provinsi Nusa Tenggara Timur [🔗](https://maps.app.goo.gl/ixrREBgMUtMUgAPH8)

+++

# Tahapan

Tahapan dalam monitor danau adalah sebagai berikut:
1. Memuat library
2. Menentukan wilayah
3. Memuat data
4. Menampilkan data
5. Menghitung MNDWI
6. Menghitung luas danau

***

+++

## 1. Memuat library
Library yang diperlukan dimuat ke sistem dan melakukan inisialisasi datacube

```{code-cell} ipython3
from datacube import Datacube
import numpy as np

from ipyleaflet import basemaps
from odc.geo.geom import point
import matplotlib.pyplot as plt
from matplotlib.colors import ListedColormap

dc = Datacube()
```

## 2. Menentukan wilayah
Area di danau Kelimutu, NTT ditentukan dan ditampilkan untuk mengetahui lokasi disekitarnya. Kalau area terlihat seperti segitiga tidak apa-apa karena cakupan wilayahnya yang kecil.

```{code-cell} ipython3
coords = -8.766, 121.813
aoi = point(coords[1], coords[0], crs="EPSG:4326")
bbox = aoi.buffer(0.01).boundingbox
region = aoi.buffer(0.01).boundingbox.polygon
region.explore(tiles=basemaps.Esri.WorldImagery)
```

## 3. Memuat data
Indeks citra satelit (Sentinel-2) untuk tahun 2024 dimuat ke sistem.

```{code-cell} ipython3
time_range = "2024"
data = dc.load(
    product="s2_l2a",
    measurements=["red", "green", "blue", "swir16"],
    output_crs="EPSG:32751",      # UTM zona 51S
    resolution=10,
    time=time_range,
    longitude=(bbox.left, bbox.right),
    latitude=(bbox.bottom, bbox.top),
    dask_chunks={},
    group_by="solar_day",
)
data
```

## 4. Menampilkan data
Data yang terpilih dengan kondisi bersih dari awan ditampilkan.

```{code-cell} ipython3
# Data yang terpilih
target_dates = ["2024-01-21", "2024-02-20", "2024-04-25", "2024-06-14", "2024-07-09", "2024-08-08", "2024-09-07", "2024-10-12"]
data_sel = data.sel(time = target_dates, method="nearest")

# Plot data
rgb = data_sel[['red', 'green', 'blue']].to_array(dim='band')
rgb.plot.imshow(col="time", col_wrap=2, size=4, vmin=0, vmax=3000, robust=True)
```

Terdapat 8 data dengan kondisi yang bebas awan. Data tersebut dapat digunakan untuk melakukan monitoring kondisi danau di tahun 2024. Diskusi terkait kondisi danau akan disampaikan di bagian Catatan.

+++

## 5. Menghitung MNDWI
MNDWI (Modified Normalized Difference Water Index) dihitung dengan formula:
$$MNDWI = \frac{(Green - SWIR1)}{(Green + SWIR1)}$$
dimana:
- SWIR 1 = Short Wave Infrared 1 (Band 11)
- Green = Band hijau

Hasil perhitungan MNDWI dimasukkan sebagai bagian layer dari data_sel

```{code-cell} ipython3
mndwi = (data_sel['green'] - data_sel['swir16']) / (data_sel['green'] + data_sel['swir16'])
data_sel['MNDWI'] = mndwi

data_sel
```

## 6. Menghitung luas danau
Perhitungan luas danau didapatkan dari MNDWI. Perlu dipilih MNDWI terbaik yang memisahkan danau dan daratan dengan menampilkan semua MNDWI.

```{code-cell} ipython3
fig, axes = plt.subplots(4, 2, figsize=(12, 16))
axes = axes.flatten()

for i in range(8):
    data_sel['MNDWI'].isel(time=i).plot(ax=axes[i], cmap='Set2', vmin=-0.5, vmax=0.5,
                                         cbar_kwargs={'label': 'MNDWI'})
    # Get the date for title
    date = str(data_sel['time'].isel(time=i).values)[:10]
    axes[i].set_title(f'MNDWI - {date}')
    axes[i].set_xlabel('X')
    axes[i].set_ylabel('Y')

plt.tight_layout()
plt.show()
```

Data MNDWI yang menggambarkan ketiga danau adalah data tanggal 20 Februari 2024 (indeks 1). Untuk menghitung luas danau, perlu ditetapkan batas (boundary) nilai yang memisahkan danau dan non danau. Setelah dilakukan ujicoba, batas 0.6 digunakan.

```{code-cell} ipython3
# batas nilai MNDWI
boundary = 0.6

# MNDWI pada time=1
mndwi = data_sel['MNDWI'].isel(time=1)

# Membuat mask masked array: 1 untuk danau (<boundary), 0 untuk daratan (>=boundary)
water_mask = np.where(mndwi < boundary, 1, 0)

# Menentukan warna dan bar
colors = ['green', 'blue']  # 0=green (land), 1=blue (water)
cmap = ListedColormap(colors)
fig, ax = plt.subplots(figsize=(10, 8))
im = ax.imshow(water_mask, cmap=cmap, vmin=0, vmax=1)
cbar = plt.colorbar(im, ax=ax, ticks=[0.25, 0.75])
cbar.ax.set_yticklabels([f'Daratan (≤{boundary})', f'Danau (>{boundary})'])

# Tanggal untuk judul peta
date = str(data_sel['time'].isel(time=1).values)[:10]
ax.set_title(f'MNDWI - Tgl {date} (Batas: {boundary})', fontsize=14)
ax.set_xlabel('Koordinat X')
ax.set_ylabel('Koordinat Y')

plt.tight_layout()
plt.show()
```

Peta diatas menunjukkan warna biru adalah danau dan non danau adalah hijau.

Berikutnya adalah perhitungan luas danau berdasarkan jumlah piksel dan luas piksel.

```{code-cell} ipython3
# Menghitung area berair (water_mask = 1)
water_pixels = np.sum(water_mask)

# Mendapatkan resolusi pixel
x_res = abs(float(data_sel.x.diff('x').mean()))
y_res = abs(float(data_sel.y.diff('y').mean()))

# Perhitungan luas per pixel (dalam meter persegi)
pixel_area_m2 = x_res * y_res

# Perhitungan area berair
water_area_m2 = water_pixels * pixel_area_m2
water_area_hectare = water_area_m2 / 10000  # 1 hectare = 10,000 m²
water_area_km2 = water_area_m2 / 1000000    # 1 km² = 1,000,000 m²

print(f"🟢🔵🟣 Perhitungan luas danau (Batas: {boundary})")
print(f"=" * 40)
print(f"▶️ Jumlah piksel: {water_pixels:,}")
print(f"▶️ Luas danau: {water_area_hectare:,.2f} hektar atau {water_area_km2:,.4f} km²")
```

# Catatan
Terdapat 3 danau yang dapat dilihat (dari Utara ke Selatan) yaitu danau Abut, danau Kootainuamuri, dan danau Alapolo. Dari pantauan citra satelit Sentinel-2 pada tahun 2024, dapat disampaikan bahwa:
1. Danau Abut berubah warna menjadi abu-abu di bulan Oktober
2. Danau Kootainuamuri berwarna cyan kecuali di bulan September - Oktober
3. Danau Alapolo mengalami perubahan warna yang dinamis: biru muda, gelap, dan cyan

![](files/kelimutu.jpg)

Luas area danau berhasil dihitung menggunakan data Sentinel-2 dan metode MNDWI (Modified Normalized Difference Water Index). MNDWI dapat mendeteksi wilayah perairan (danau) dengan non perairan.

+++

# Info

- Modul ini dijalankan di platform Piksel. Jika ada pertanyaan atau komentar, silahkan email ke piksel@big.go.id
- **Lisensi:** Skrip dalam notebook ini dilisensikan berdasarkan [Apache License, Version 2.0](https://www.apache.org/licenses/LICENSE-2.0).
Data Piksel dilisensikan berdasarkan lisensi [Creative Commons by Attribution 4.0](https://creativecommons.org/licenses/by/4.0/).
