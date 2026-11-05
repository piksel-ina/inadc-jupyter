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

| <h1><b>Menghitung Luas Area Pertambangan</b></h1> | ![](files/piksel_logo_small.png) |
|:---------|----------:|
- **Data:** Sentinel-2
- **Lokasi:** Pertambangan Nickel di Pulau Gag, Raja Ampat
- **Metode:** Bare Soil Index (BSI)

+++

# Pendahuluan
Modul ini bertujuan untuk memberikan contoh penggunaan metode Bare Soil Index (BSI) untuk menghitung luas wilayah pertambangan. BSI adalah indeks spektral yang memanfaatkan perbedaan reflektansi spektral antara tanah terbuka dengan vegetasi dan air untuk mengidentifikasi area tanah yang tidak tertutup vegetasi. Lokasi yang digunakan sebagai contoh adalah area pertambangan nikel di Pulau Gag, Raja Ampat, Provinsi Papua Barat [🔗](https://maps.app.goo.gl/sBG2JnC5ahp7VgAN6)

+++

# Tahapan

Tahapan dalam perhitungan luas wilayah pertambangan adalah sebagai berikut:
1. Memuat library
2. Menentukan wilayah
3. Memuat indeks data
4. Membuat cloud mask
5. Membuat median
6. Menghitung BSI
7. Menghitung luas wilayah

***

+++

## 1. Memuat library
Library yang diperlukan adalah datacube, odc.geo.geom dan pandas

```{code-cell} ipython3
from datacube import Datacube
from odc.geo.geom import point
import pandas as pd
dc = Datacube()
```

## 2. Menentukan wilayah
Area yang akan diproses ditentukan dan ditampilkan. Kalau area terlihat seperti segitiga tidak apa-apa karena cakupan wilayah nya yang kecil.

```{code-cell} ipython3
# Lokasi Pulau Gag
coords = -0.46, 129.884
aoi_point = point(coords[1], coords[0], crs="EPSG:4326")
bbox = aoi_point.buffer(0.03).boundingbox

# Preview the area
bbox.explore(zoom=8)
```

## 3. Memuat indeks data
Untuk memuat indeks citra satelit (Sentinel-2), maka beberapa parameter digunakan:
- products: menentukan produk/dataset yang akan dimuat
- measurements: band/kanal spektral yang akan dimuat
- output_crs: Coordinate Reference System (CRS) untuk output
- resolution: resolusi spasial output dalam meter
- time: rentang waktu data yang akan dimuat
- longitude: batas bujur (longitude) area yang dimuat
- latitude: batas lintang (latitude) area yang dimuat
- dask_chunks: mengaktifkan lazy loading dengan Dask untuk efisiensi memori
- group_by: mengelompokkan data berdasarkan hari matahari

```{code-cell} ipython3
datetime = ("2025-01-01","2025-06-30")
data = dc.load(
    product="s2_l2a",
    measurements=["red", "green", "blue", "nir", "swir16", "scl"],
    output_crs="EPSG:32750",             # UTM Zone 50S
    resolution=10,
    time=datetime,
    longitude=(bbox.left, bbox.right),
    latitude=(bbox.bottom, bbox.top),
    dask_chunks={},
    group_by="solar_day",
)

data          # menampilkan tabel
```

## 4. Membuat cloud mask

Untuk menggunakan data tanpa awan, bayangan dan no-data, maka kanal SCL dari Sentinel-2.

```{code-cell} ipython3
cloud_and_shadow_mask = (
    (data.scl == 0) |  # No data
    (data.scl == 1) |  # Saturated or defective
    (data.scl == 3) |  # Cloud shadows
    (data.scl == 8) |  # Cloud medium probability
    (data.scl == 9) |  # Cloud high probability
    (data.scl == 10)   # Thin cirrus
)

cloud_free_data = data.where(~cloud_and_shadow_mask)
```

## 5. Membuat median
Median data dibuat dari data yang bagus dalam setahun

```{code-cell} ipython3
median_composite = cloud_free_data.median(dim="time")
median_composite
```

```{code-cell} ipython3
# untuk menampilkan data median [sekitar 2 menit]
vis = median_composite.odc.to_rgba(vmin=0, vmax=3000)
vis.odc.explore()
```

## 6. Menghitung Bare Soil Index (BSI)
BSI menggunakan formula:
$$BSI = \frac{(SWIR + Red) - (NIR + Blue)}{(SWIR + Red) + (NIR + Blue)}$$
dimana:
- SWIR = Short Wave Infrared
- Red = Band merah
- NIR = Near Infrared
- Blue = Band biru

Nilai BSI berkisar antara -1 hingga +1, dimana nilai mendekati +1 menunjukkan area tanah terbuka dan nilai mendekati -1 berarti area bervegetasi atau berair.

Untuk menentukan area tanah terbuka [pertambangan], maka ditentukan batas nilai BSI. Nilai ini dapat disesuaikan. Nilai lebih tinggi berarti lebih menunjukkan area tanah terbuka.

```{code-cell} ipython3
swir1 = median_composite.swir16
red = median_composite.red
nir = median_composite.nir
blue = median_composite.blue

bsi = ((swir1 + red) - (nir + blue)) / ((swir1 + red) + (nir + blue))
bsi_threshold = 0.1
cleared_land_mask = bsi > bsi_threshold
cleared_land_mask
```

```{code-cell} ipython3
# untuk menampilkan data lahan terbuka {warna merah} [sekitar 1:30 menit]
cleared_land_mask.plot.imshow(cmap="Pastel1_r", vmin=0, vmax=1)
```

## 7. Menghitung luas wilayah
Luas area pertambangan dihitung berdasarkan jumlah piksel di area tanah terbuka.

```{code-cell} ipython3
# Menghitung jumlah piksel [sekitar 1:50 menit]
cleared_pixels_count = int(cleared_land_mask.sum())

# Menghitung luas 1 piksel
pixel_area_m2 = abs(data.geobox.transform[0] * data.geobox.transform[4])

# Menghitung luas dalam m2 dan km2
area_m2 = cleared_pixels_count * pixel_area_m2
area_km2 = area_m2 / 1_000_000
area_ha = area_km2 * 100

# Mencetak hasil
print("\n🟢🔵🟣 Analisis Luas Area Pertambangan")
print(f"BSI Threshold: > {bsi_threshold}")
print(f"Jumlah piksel: {cleared_pixels_count}")
print(f"Luas area: {area_km2:.2f} km² atau {area_ha:.2f} hektar")
```

# Catatan
Luas area pertambangan berhasil dihitung menggunakan data Sentinel-2 dan metode Bare Soil Index (BSI). Penggunaan BSI dapat digunakan juga untuk menghitung luas lahan terbuka lain nya.

+++

# Info

- Modul ini dijalankan di platform Piksel. Jika ada pertanyaan atau komentar, silahkan email ke piksel@big.go.id
- **Lisensi:** Skrip dalam notebook ini dilisensikan berdasarkan [Apache License, Version 2.0](https://www.apache.org/licenses/LICENSE-2.0).
Data Piksel dilisensikan berdasarkan lisensi [Creative Commons by Attribution 4.0](https://creativecommons.org/licenses/by/4.0/).
