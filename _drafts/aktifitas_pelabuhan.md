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

| <h1><b>Aktifitas Kapal di Sekitar Pelabuhan</b></h1> | ![](files/piksel_logo_small.png) |
|:---------|----------:|
- **Data:** Sentinel-1
- **Lokasi:** Pelabuhan Makassar, Provinsi Sulawesi Selatan
- **Metode:** Penggunaan citra radar

+++

# Pendahuluan
Modul ini bertujuan untuk memberikan contoh penggunaan data Sentinel-1 dalam memantau keberadaan kapal di sekitar pelabuhan. Mampu mendeteksi kapal dan jalur pelayaran dari citra satelit dapat bermanfaat untuk mendapatkan gambaran holistik lalu lintas di pelabuhan. Data radar (Sentinel-1) dapat digunakan untuk mendeteksi keberadaan kapal dari waktu ke waktu, sehingga menyoroti keberadaan jalur pelayaran.

Saat bekerja dengan data radar, air tampak gelap; permukaannya yang relatif halus menghasilkan hamburan balik yang sangat kecil, sehingga intensitas rendah terekam oleh satelit di kedua pita polarisasi. Namun, jika sebuah kapal berada di atas air, hamburan balik di lokasi kapal akan jauh lebih tinggi daripada di air.

Lokasi yang digunakan adalah di Pelabuhan Makassar, provinsi Sulawesi Selatan [🔗](https://maps.app.goo.gl/JBweGfqdr4SGs9YE6) pada bulan Januari 2025.

+++

# Tahapan

Tahapan dalam monitor kapal di pelabuhan Makassar adalah sebagai berikut:
1. Memuat library
2. Menggunakan _distributed computing_
3. Menentukan wilayah
4. Memuat data
5. Konversi data ke decibel
6. Menghitung nilai maksimum

***

+++

## 1. Memuat library
Library yang diperlukan dimuat ke sistem dan melakukan inisialisasi datacube.

```{code-cell} ipython3
%matplotlib inline

import datacube
import numpy as np
from planetary_computer import sign_url
from pystac_client import Client as pClient

from dask.distributed import Client, LocalCluster
from odc.stac import load
from odc.geo.geom import point
import matplotlib.pyplot as plt
from ipyleaflet import basemaps

dc = datacube.Datacube(app="Monitoring_kapal")
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

Untuk menyiapkan *distributed computing* dengan Dask, Anda perlu menyiapkan klien Dask terlebih dahulu menggunakan fungsi di bawah ini:

```{code-cell} ipython3
def create_local_dask_cluster():
    cluster = LocalCluster()
    client = Client(cluster)
    print(f"✅ Dask cluster started at: {client.dashboard_link}")
    return client

create_local_dask_cluster()
```

## 3. Menentukan wilayah
Area yang akan diproses yaitu Pelabuhan Makassar ditentukan dan ditampilkan.

```{code-cell} ipython3
# Koordinat lokasi
latitude = (-5.156, -5.076)
longitude = (119.300, 119.423)
lat = (latitude[0] + latitude[1])/2
lon = (longitude[0] + longitude[1])/2
aoi = point(lon, lat, crs="epsg:4326")

# Membuat bounding box 
region = aoi.buffer(0.07).boundingbox.polygon
region.explore(tiles=basemaps.Esri.WorldImagery)
```

## 4. Memuat data
Data di bulan Januari tahun 2025 dimuat untuk digunakan dalam analisis.

```{code-cell} ipython3
time_range = "2025-01-01/2025-01-31"

items = client.search(
    collections=["sentinel-1-rtc"],
    intersects=region,
    datetime=time_range,
).item_collection()

print(f"Ditemukan {len(items)} data")
```

```{code-cell} ipython3
# Membuka data Sentinel-1
data = load(
    items,
    geopolygon=region,
    measurements=["vv", "vh"],
    groupby="solar_day",
    patch_url=sign_url,
    chunks={"x": 2048, "y": 2048}
).compute()

data
```

Sebanyak 6 data ditampilkan untuk pengukuran VH. Data menunjukkan sebaran obyek putih di lepas pantai pelabuhan Makassar yang menunjukkan posisi kapal.

```{code-cell} ipython3
# Plot polarisasi VH
data.isel(time=range(0,6)).vh.plot(cmap="Greys_r", robust=True, col="time", col_wrap=2)
```

## 5. Konversi data ke decibel
Data _backscatter_ Sentinel-1 memiliki dua pengukuran yaitu VV dan VH yang berhubungan dengan polarisasi cahaya yang dikirim dan diterima oleh satelit. VV mengacu pada satelit yang mengirimkan cahaya terpolarisasi vertikal dan menerima kembali cahaya terpolarisasi vertikal, sedangkan VH mengacu pada satelit yang mengirimkan cahaya terpolarisasi vertikal dan menerima kembali cahaya terpolarisasi horizontal. Kedua pita pengukuran ini dapat memberikan informasi yang berbeda tentang area yang kita teliti.

Saat bekerja dengan _backscatter_ radar, umumnya digunakan dalam satuan desibel (dB), sebagai angka digital (DN) seperti yang diukur oleh satelit. Untuk mengonversi dari DN ke dB, kita menggunakan rumus berikut:
$$dB = 10 \times \log_{10}(\text{DN})$$

dimana:
- dB = data dalam satuan decibel
- DN = Digital Number

```{code-cell} ipython3
# konversi data ke decibels
data["vh_dB"] = 10 * np.log10(data.vh)
data
```

Terlihat bahwa dalam `data` ditambahkan _measurement_ `vh_dB`. Berikut adalah plotting dari `vh_dB` dimana terlihat sebaran kapal.

```{code-cell} ipython3
# plotting data
data.isel(time=range(0,6)).vh_dB.plot(cmap="Greys_r", robust=True, col="time", col_wrap=2)
```

## 6. Menghitung nilai maksimum
Nilai maksimum dari setiap piksel yang diukur digunakan untuk mengetahui posisi kapal dalam sebulan. Perhatikan bahwa operasi Dask digunakan untuk memplot data vh_dB pada sel di bawah ini.

```{code-cell} ipython3
max_vh = data.vh_dB.max(dim="time")

max_vh.plot.imshow(size=10, cmap="Greys_r", robust=True)
plt.title("Data maksimum VH")
plt.show()
```

# Catatan
Terdapat 3 danau yang dapat dilihat (dari Utara ke Selatan) yaitu danau Abut, danau Kootainuamuri, dan danau Alapolo. Dari pantauan citra satelit Sentinel-2 pada tahun 2024, dapat disampaikan bahwa:
1. Danau Abut berubah warna menjadi abu-abu di bulan Oktober
2. Danau Kootainuamuri berwarnac cyan kecuali di bulan September - Oktober 
3. Danau Alapolo mengalami perubahan warna yang dinamis: biru muda, gelap, dan cyan

Luas area danau berhasil dihitung menggunakan data Sentinel-2 dan metode MNDWI (Modified Normalized Difference Water Index). MNDWI dapat mendeteksi wilayah perairan (danau) dengan non perairan.

+++

# Info

- Krause, C., Dunn, B., Bishop-Taylor, R., Adams, C., Burton, C., Alger, M., Chua, S., Phillips, C., Newey, V., Kouzoubov, K., Leith, A., Ayers, D., Hicks, A., DEA Notebooks contributors 2021. Digital Earth Australia notebooks and tools repository. Geoscience Australia, Canberra. https://doi.org/10.26186/145234
- Jika ada pertanyaan atau komentar, silahkan email ke piksel@big.go.id
- **Lisensi:** Skrip dalam notebook ini dilisensikan berdasarkan [Apache License, Version 2.0](https://www.apache.org/licenses/LICENSE-2.0).
Data Piksel dilisensikan berdasarkan lisensi [Creative Commons by Attribution 4.0](https://creativecommons.org/licenses/by/4.0/).
