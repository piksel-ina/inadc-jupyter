# Studi Kasus

---

> **Status:** Modul ini masih dalam pengembangan.

Studi Kasus menyajikan alur kerja analisis data pengamatan Bumi yang menerapkan materi dari [Panduan Pemula](../01_Panduan_Pemula/README.md), [Panduan Produk Data](../02_Panduan_Produk_Data/README.md), dan [Panduan Analisis](../03_Panduan_Analisis/README.md).

## Notebook referensi

[Alex Leith](https://github.com/alexgleith) menyusun notebook berbahasa Inggris berikut. Alur kerjanya menjadi acuan bagi studi kasus yang akan ditambahkan ke seri ini.

- [Coba sendiri](../../English/04_Case_Studies/00_Do_It_Yourself.ipynb)
- [Analisis badan air dengan Sentinel-1](../../English/04_Case_Studies/01_Sentinel-1_Water.ipynb)
- [GeoMAD bebas awan dari Landsat](../../English/04_Case_Studies/02_Landsat_CloudFree_GeoMAD.ipynb)
- [Perubahan pesisir dengan Landsat](../../English/04_Case_Studies/03_Landsat_CoastalChange.ipynb)
- [Pembelajaran mesin dengan Sentinel-2](../../English/04_Case_Studies/04_Sentinel-2_MachineLearning.ipynb)
- [Interoperabilitas data](../../English/04_Case_Studies/05_Data_Interoperability.ipynb)

## Studi kasus

Berikut adalah ringkasan studi kasus yang disusun untuk platform Piksel, dikelompokkan berdasarkan topik.

### Bencana

- [Identifikasi Area Banjir](bencana/delineasi_banjir_aceh.ipynb) -- Mendeteksi genangan banjir akibat siklon tropis Senyar di Kab. Aceh Utara menggunakan citra radar Sentinel-1 melalui analisis perubahan backscatter sebelum dan saat banjir.
- [Identifikasi Zona Bahaya Banjir](bencana/zona_bahaya_banjir.ipynb) -- Menggunakan data DEM Copernicus dan Sentinel-2 untuk mengklasifikasikan zona bahaya banjir berdasarkan elevasi dan kemiringan lereng di Kabupaten Bangka Barat.
- [Pergerakan Titik Api di Karhutla](bencana/karhutla_hotspot.ipynb) -- Memanfaatkan data hotspot VIIRS untuk memetakan asal mula dan pergerakan titik api kebakaran hutan dan lahan di kawasan Gunung Bromo, Jawa Timur.
- [Identifikasi Area yang Terbakar](bencana/karhutla_area_terbakar.ipynb) -- Menghitung indeks Normalized Burn Ratio (NBR) dari citra Sentinel-2 untuk memetakan area dan estimasi luas lahan terbakar akibat karhutla di kawasan Gunung Bromo.

### Lahan

- [Menghitung Luas Area Pertambangan](lahan/delineasi_area_tambang.ipynb) -- Menggunakan Bare Soil Index (BSI) dari citra Sentinel-2 untuk mengidentifikasi dan menghitung luas area pertambangan nikel di Pulau Gag, Raja Ampat.
- [Perubahan Tutupan Lahan](lahan/perubahan_sawah.ipynb) -- Menganalisis perubahan tutupan lahan pertanian menjadi kawasan industri dan lahan terbuka di Kabupaten Subang menggunakan indeks spektral NDVI dan NDBI dari Sentinel-2.

### Lingkungan

- [Monitoring Kondisi Danau](lingkungan/monitor_danau.ipynb) -- Menerapkan indeks MNDWI pada citra Sentinel-2 untuk menghitung luas dan memantau kondisi Danau Kelimutu, Kab. Ende, Nusa Tenggara Timur.
- [Pemetaan Kelembaban Tanah](lingkungan/kelembaban_tanah.ipynb) -- Mengolah data backscatter radar Sentinel-1, diverifikasi dengan Sentinel-2, untuk memetakan tingkat kelembaban tanah di Kabupaten Bantaeng, Sulawesi Selatan.
- [Monitoring Suhu Permukaan di Area PLTP](lingkungan/monitor_suhu_permukaan.ipynb) -- Menggunakan NDVI dan Land Surface Temperature dari Landsat 9 untuk memantau suhu permukaan di sekitar Pembangkit Listrik Tenaga Panas Bumi Kamojang, Jawa Barat.

### Pangan

- [Monitoring Penanaman Padi](pangan/monitor_padi.ipynb) -- Menggunakan indeks spektral NDVI, LSWI, EVI, dan NDRE dari Sentinel-2 untuk memantau fenologi dan estimasi hasil panen padi di Kecamatan Telagasari, Karawang.
- [Estimasi Umur Kelapa Sawit](pangan/umur_sawit.ipynb) -- Menerapkan transformasi citra pada data Sentinel-2 untuk mengestimasi umur tanaman kelapa sawit di Kabupaten Gunung Mas, Kalimantan Tengah.

### Pesisir

- [Aktifitas Kapal di Sekitar Pelabuhan](pesisir/aktifitas_pelabuhan.ipynb) -- Memanfaatkan citra radar Sentinel-1 untuk mendeteksi keberadaan kapal dan jalur pelayaran di sekitar Pelabuhan Makassar, Sulawesi Selatan.
- [Pendeteksian Tumpahan Minyak](pesisir/identifikasi_tumpahan_minyak.ipynb) -- Menggabungkan manual global threshold pada citra SAR Sentinel-1 dengan klasifikasi SVM dan masking laut dari Sentinel-2 untuk mendeteksi tumpahan minyak di perairan Karawang.
- [Analisis Kerapatan Mangrove](pesisir/kerapatan_mangrove.ipynb) -- Menggabungkan indeks spektral dan klasifikasi Random Forest pada citra Sentinel-2 tahun 2019 dan 2025 untuk menganalisis kerapatan dan perubahan tutupan mangrove di Segara Anakan, Cilacap.
- [Klasifikasi Mangrove dengan Machine Learning](pesisir/klasifikasi_mangrove_ML.ipynb) -- Menggunakan indeks spektral dan klasifikasi Random Forest pada citra Sentinel-2 untuk mendelineasi area mangrove di selatan Kota Denpasar, Bali.
- [Perubahan Garis Pantai](pesisir/perubahan_garpan.ipynb) -- Menganalisis perubahan garis pantai multi temporal dari citra Landsat yang dikombinasikan dengan model pasang surut di Pulau Makora, Nias Utara, Sumatera Utara.
- [Identifikasi Perubahan Terumbu Karang](pesisir/perubahan_terumbu_karang.ipynb) -- Menggunakan koreksi kolom air Lyzenga dan klasifikasi Random Forest pada citra Sentinel-2 tahun 2020 dan 2025 untuk mengidentifikasi perubahan luasan dan kondisi terumbu karang di Pulau Boni, Raja Ampat.
