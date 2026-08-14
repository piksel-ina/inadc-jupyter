# Panduan Pemula

---

Panduan Pemula membahas dasar-dasar pengolahan data pengamatan Bumi dengan Jupyter Notebook, Open Data Cube, dan xarray.
Cukup memahami dasar-dasar Python untuk mengikuti materinya.
Belum pernah menggunakan Open Data Cube juga tidak masalah.

Notebook dalam panduan ini disusun secara berurutan.
Materi dari satu notebook akan dipakai lagi pada notebook berikutnya, jadi mulailah dari notebook pertama.
Jalankan setiap sel dan perhatikan kode beserta outputnya.
Beberapa konsep akan lebih mudah dipahami setelah hasilnya terlihat secara langsung.

## Jalur pembelajaran

1. [Pengenalan Jupyter Notebook](./01_pengenalan_jupyter_notebook.ipynb) mengenalkan lingkungan JupyterLab, jenis sel dalam notebook, cara kerja kernel, dan pengelolaan file.
2. [Pengenalan Open Data Cube](./02_pengenalan_open_data_cube.ipynb) membahas cara menghubungkan notebook ke Open Data Cube serta memeriksa produk dan jenis data yang tersedia di dalamnya. Dalam Open Data Cube, jenis data ini disebut `measurement`.
3. [Memuat Data](./03_memuat_data_dari_open_data_cube.ipynb) membahas cara membuat kueri berdasarkan wilayah dan waktu, memeriksa dataset yang tersedia, lalu memuat citra satelit.
4. [xarray untuk Open Data Cube](./04_xarray_untuk_open_data_cube.ipynb) membahas data hasil pemuatan yang berbentuk `Dataset` dan `DataArray`, termasuk cara memilih data dan melakukan operasi aritmetika.
5. [Visualisasi Data xarray](./05_visualisasi_data_xarray.ipynb) menunjukkan cara membuat plot satu band, komposit warna, dan plot data dari beberapa waktu pengamatan.

## Latihan

Setelah menyelesaikan materi utama, kerjakan [Latihan Panduan Pemula](./LATIHAN_Panduan_Pemula.ipynb) untuk mencoba alur kerja yang sama pada wilayah kajian yang berbeda.
Latihan ini menggabungkan proses memuat data, membaca struktur xarray, membuat visualisasi, dan menghitung indeks spektral.
Kalau perlu, buka bagian **Petunjuk** yang tersedia pada setiap tahap.

Usahakan menyelesaikan latihan terlebih dahulu.
Setelah itu, bandingkan langkah-langkah yang digunakan dengan [Solusi Latihan Panduan Pemula](./SOLUSI_Panduan_Pemula.ipynb).
Solusi tersebut menunjukkan salah satu cara menyelesaikan latihan dan menjelaskan hasil pada setiap tahap.

## Penulis

- [Muhammad Taufik](https://github.com/taufik-shf)

## Kontributor

[Alex G Leith](https://github.com/alexgleith) menyusun materi dan contoh kode awal yang kemudian dikembangkan menjadi panduan ini.

[Matthew Ellis](https://github.com/Matt-dea) turut menyunting dan memperjelas materi tentang Open Data Cube, Landsat, dan Sentinel.

Perubahan pada setiap notebook tercatat dalam riwayat Git.

## Ucapan terima kasih

Materi awal panduan ini juga merujuk pada sumber dari komunitas Open Data Cube, termasuk [Digital Earth Australia](https://www.dea.ga.gov.au/) dan [Digital Earth Africa](https://www.digitalearthafrica.org/).
