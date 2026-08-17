# Panduan Produk Data

---

> **Status:** Modul ini masih dalam pengembangan.

Panduan Produk Data akan membahas berbagai produk data pengamatan Bumi yang tersedia di Open Data Cube. Panduan ini melanjutkan [Panduan Pemula](../01_Panduan_Pemula/README.md) dengan membahas karakteristik setiap produk dan cara menggunakannya dengan tepat.

## Panduan yang direncanakan

- Reflektansi permukaan Landsat
- Suhu permukaan Landsat
- Hamburan balik radar Sentinel-1
- Reflektansi permukaan Sentinel-2

## Notebook referensi

[Alex Leith](https://github.com/alexgleith) menulis notebook berbahasa Inggris berikut. Seri ini menggunakan notebook tersebut sebagai referensi dan contoh di dalamnya sebagai acuan bagi panduan yang direncanakan.

- [Analisis badan air dengan Sentinel-1](../../English/02_Data_Product_Guides/01_Sentinel-1_Water.ipynb)
- [Reflektansi permukaan Landsat](../../English/02_Data_Product_Guides/03_Landsat_SR_GettingStarted.ipynb)
- [Suhu permukaan Landsat](../../English/02_Data_Product_Guides/03_Landsat_ST_GettingStarted.ipynb)
- [Reflektansi permukaan Sentinel-2](../../English/02_Data_Product_Guides/04_Sentinel-2_GettingStarted.ipynb)

Notebook Sentinel-1 berisi studi kasus analisis badan air dan menjadi acuan untuk menyusun panduan hamburan balik radar Sentinel-1.

Setiap panduan akan membahas:

- produk dan koleksi data yang menjadi sumbernya;
- jenis data (`measurement`) yang tersedia, resolusi spasial, dan satuan;
- faktor skala, ofset, dan nilai tanpa data (`no-data`);
- jenis data untuk menilai kualitas dan menyaring piksel berawan;
- komposit warna alami dan warna semu;
- contoh sederhana penggunaan produk.

Pengetahuan tentang produk data dalam panduan ini menjadi dasar untuk mengikuti [Panduan Analisis](../03_Panduan_Analisis/README.md).
