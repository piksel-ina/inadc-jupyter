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

| <h1><b>Estimasi Umur Kelapa Sawit</b></h1> | ![](files/piksel_logo_small.png)  |
|:---------|----------:|
- **Data:** Sentinel-2
- **Lokasi:** Kabupaten Gunung Mas, Provinsi Kalimantan Tengah
- **Metode:** Transformasi Citra

+++

# Pendahuluan

Perkebunan kelapa sawit merupakan salah satu sektor strategis yang memiliki peran penting dalam perekonomian, khususnya di Indonesia. Pengelolaan perkebunan yang efektif memerlukan informasi yang akurat mengenai kondisi tanaman, termasuk estimasi umur kelapa sawit. Informasi umur tanaman sangat penting untuk mendukung perencanaan produksi, penentuan waktu panen, serta pengambilan keputusan dalam kegiatan peremajaan (replanting). Seiring dengan perkembangan teknologi, pemanfaatan penginderaan jauh menjadi salah satu pendekatan yang efisien dalam memperoleh informasi terkait kondisi dan karakteristik vegetasi. Citra satelit Sentinel-2 menyediakan data multispektral dengan resolusi spasial dan temporal yang cukup baik, sehingga sangat mendukung analisis vegetasi secara detail dan berkelanjutan.

Dalam analisis ini, metode transformasi citra digunakan untuk mengekstraksi informasi spektral yang berkaitan dengan kondisi fisiologis tanaman. Transformasi seperti indeks vegetasi mampu menggambarkan tingkat kehijauan dan kerapatan kanopi, yang selanjutnya dapat dikaitkan dengan fase pertumbuhan atau umur tanaman kelapa sawit. Dengan mengombinasikan data citra Sentinel-2 dan metode transformasi citra, estimasi umur kelapa sawit dapat dilakukan secara lebih cepat, luas, dan efisien dibandingkan metode konvensional di lapangan. Oleh karena itu, analisis estimasi umur kelapa sawit berbasis citra Sentinel-2 dengan metode transformasi citra menjadi pendekatan yang relevan dan penting untuk mendukung pengelolaan perkebunan yang lebih optimal dan berbasis data.

+++

# Tahapan

Tahapan dalam identifikasi umur pohon kelapa sawit adalah sebagai berikut:
1. Persiapan
2. Menentukan wilayah
3. Memuat data
4. Filter data
5. Ekstraksi nilai reflectance
6. Transformasi citra
7. Klasifikasi umur
8. Visualisasi
9. Perhitungan estimasi luas lahan
***

+++

## 1. Persiapan
Library yang diperlukan adalah sebagai berikut:

```{code-cell} ipython3
from datacube import Datacube
import numpy as np
import xarray as xr
from odc.geo.geom import point
from ipyleaflet import basemaps
import matplotlib.pyplot as plt
from matplotlib.colors import ListedColormap
import matplotlib.patches as mpatches
from pyproj import Transformer
import folium
from folium import plugins
from folium.raster_layers import ImageOverlay

dc = Datacube()
```

## 2. Menentukan wilayah
Langkah selanjutnya yakni menentukan wilayah kajian. Pada kasus ini, lokasi wilayah kajian berada di Kabupaten Gunung Mas, Provinsi Kalimantan Tengah.

```{code-cell} ipython3
coords = -1.563, 113.482
aoi = point(coords[1], coords[0], crs="EPSG:4326")
bbox = aoi.buffer(0.01).boundingbox
region = aoi.buffer(0.01).boundingbox.polygon
region.explore(tiles=basemaps.Esri.WorldImagery)
```

## 3. Memuat data

Tahap ini bertujuan untuk mengidentifikasi dan menentukan data yang diperlukan untuk mendukung analisis.

```{code-cell} ipython3
datetime = ("2018")
data = dc.load(
    product="s2_l2a",
    measurements=["red", "green", "blue", "scl", "nir", "rededge1", "swir16"],
    output_crs="EPSG:32749",
    resolution=10,
    time=datetime,
    longitude=(bbox.left, bbox.right),
    latitude=(bbox.bottom, bbox.top),
    dask_chunks={},
    group_by="solar_day",
    cloud_cover=(0, 60),
)
data
```

Pada langkah ini spesifik ditentukan waktu perekaman untuk kajian analisis

```{code-cell} ipython3
mask = (data.time.dt.month == 11)
data_nov = data.sel(time=mask)

rgb = data_nov[['red', 'green', 'blue']].to_array(dim='band')
rgb.plot.imshow(
    col="time",
    col_wrap=min(4, data_nov.time.size),
    size=4,
    vmin=0,
    vmax=3000,
    robust=True
)
```

## 4. Filter data

Tahapan ini berfokus pada penentuan waktu secara lebih spesifik hingga pada tingkat tanggal perekaman citra. Selain itu, pada tahap ini juga ditampilkan jumlah scene yang terdapat pada wilayah kajian beserta jumlah band yang digunakan.

```{code-cell} ipython3
# Filter Data
mask_date = (data.time.dt.date == np.datetime64("2018-11-20"))
data_sel = data.sel(time=mask_date)

print(f"📅 Scenes available : {data_sel.time.values}")
print(f"📦 Bands available  : {list(data_sel.data_vars)}")
```

Pada tahap ini apabila scene citra yang digunakan lebih dari satu, maka akan berlaku median. Apabila citra yang digunakan sama dengan satu, maka akan berlaku squeeze.

```{code-cell} ipython3
# Take median if multiple scenes, squeeze if single
if data_sel.time.size > 1:
    scene = data_sel.median(dim="time", skipna=True)
    print(f"   → Median of {data_sel.time.size} scenes used")
else:
    scene = data_sel.squeeze("time", drop=True)
    print(f"   → Single scene used")
```

## 5. Ekstraksi nilai reflectance

Tahapan ini mengkonversi nilai piksel (digital number) menjadi nilai reflectance yang kemudian akan dilakukan perhitungan transformasi citra. Band yang dikonversi meliputi band NIR, merah, biru, rededge, dan SWIR.

```{code-cell} ipython3
# Ekstraksi Nilai Reflectance
nir  = scene["nir"].values.astype(float)      / 10000
red  = scene["red"].values.astype(float)      / 10000
blue = scene["blue"].values.astype(float)     / 10000
rededge = scene["rededge1"].values.astype(float)     / 10000
swir = scene["swir16"].values.astype(float)     / 10000
```

## 6. Transformasi citra

Tahapan ini dilakukan perhitungan transformasi citra. Indeks citra yang dilakukan meliputi NDVI, EVI, NDRE, dan BSI. Tahap ini juga membuat range hasil transformasi citra yang telah dihasilkan.

```{code-cell} ipython3
# Transformasi Citra
ndvi = (nir - red)  / (nir + red  + 1e-10)
evi  = 2.5 * (nir - red) / (nir + 6*red - 7.5*blue + 1 + 1e-10)
ndre = (nir - rededge)   / (nir + rededge   + 1e-10) if rededge   is not None else np.zeros_like(ndvi)
bsi  = ((swir + red) - (nir + blue)) / \
       ((swir + red) + (nir + blue) + 1e-10) if swir is not None else np.zeros_like(ndvi)

print(f"\n📊 Index ranges:")
print(f"   NDVI : {np.nanmin(ndvi):.3f} → {np.nanmax(ndvi):.3f}  (mean: {np.nanmean(ndvi):.3f})")
print(f"   EVI  : {np.nanmin(evi):.3f} → {np.nanmax(evi):.3f}  (mean: {np.nanmean(evi):.3f})")
print(f"   NDRE : {np.nanmin(ndre):.3f} → {np.nanmax(ndre):.3f}  (mean: {np.nanmean(ndre):.3f})")
print(f"   BSI  : {np.nanmin(bsi):.3f} → {np.nanmax(bsi):.3f}  (mean: {np.nanmean(bsi):.3f})")
```

## 7. Klasifikasi umur

Tahapan ini dilakukan perhitungan hasil transformasi citra. Kelas umur dibagi menjadi 5 bagian, yakni:
- kelas 0 - lahan setelah panen/ replanting (Cleared/ Replanting, 0-1 tahun)
- kelas 1 - kebun bibit (Immature, 1-3 tahun)
- kelas 2 - masa produktif muda (Young Productive, 3-6 tahun)
- kelas 3 - masa produktif (Prime Productive, 6-15 tahun)
- kelas 4 - kebun kelapa sawit tua (Old/ Senescent, > 15 tahun)

```{code-cell} ipython3
# Klasifikasi Umur
def classify_age(ndvi, evi, ndre, bsi):
    age = np.full(ndvi.shape, -1, dtype=np.int8)

    # Class 0 — Cleared / replanting (0–1 yr)
    age[
        (bsi  >  0.05) &
        (ndvi <  0.25)
    ] = 0

    # Class 1 — Immature (1–3 yr)
    age[
        (ndvi >= 0.25) & (ndvi < 0.45) &
        (evi  <  0.20) &
        (age  == -1)
    ] = 1

    # Class 2 — Young productive (3–6 yr)
    age[
        (ndvi >= 0.45) & (ndvi < 0.65) &
        (evi  >= 0.20) & (evi  < 0.35) &
        (age  == -1)
    ] = 2

    # Class 3 — Prime productive (6–15 yr)
    age[
        (ndvi >= 0.65) &
        (evi  >= 0.35) &
        (ndre >= 0.15) &
        (age  == -1)
    ] = 3

    # Class 4 — Old / senescent (>15 yr)
    age[
        (ndvi >= 0.55) &
        (ndre <  0.12) &
        (age  == -1)
    ] = 4

    return age

age_class = classify_age(ndvi, evi, ndre, bsi)
```

Tahapan ini mencakup pembuatan kelas data error yang bertujuan untuk mengeluarkan data tersebut dari perhitungan estimasi luasan agar tidak masuk dalam proses analisis.

```{code-cell} ipython3
# Masking piksel yang bukan indikasi kelapa sawit
age_masked = age_class.copy()

# Only mask out true no-data pixels (NaN in NIR band)
nodata_mask = np.isnan(nir)
age_masked[nodata_mask] = -1
```

## 8. Visualisasi

Tahap ini merupakan visualisasi data. Visualisasi didasarkan pada kelas umur sawit pada lahan yang telah dihitung sebelumnya.

```{code-cell} ipython3
# Visualisasi
AGE_LABELS = {
    -1: "Non-Palm / No Data",
    0:  "Cleared (0-1 yr)",
    1:  "Immature (1-3 yr)",
    2:  "Young (3-6 yr)",
    3:  "Prime (6-15 yr)",
    4:  "Old (>15 yr)",
}
AGE_COLORS = {
    -1: "#e8e8e8",
    0:  "#d9534f",
    1:  "#f0ad4e",
    2:  "#aad576",
    3:  "#2d6a4f",
    4:  "#6c757d",
}

class_ids = [-1, 0, 1, 2, 3, 4]
cmap      = ListedColormap([AGE_COLORS[c] for c in class_ids])

fig, axes = plt.subplots(1, 2, figsize=(16, 7))

# ── Left: RGB true colour ─────────────────────────────────────────────────────
rgb_display = np.stack([
    np.clip(red   * 3.5, 0, 1),
    np.clip(scene["green"].values.astype(float) / 10000 * 3.5, 0, 1),
    np.clip(blue  * 3.5, 0, 1),
], axis=-1)
axes[0].imshow(rgb_display)
axes[0].set_title("Sentinel-2 RGB (2018-11-20)", fontsize=12)
axes[0].axis("off")

# ── Right: Age class map ──────────────────────────────────────────────────────
axes[1].imshow(age_masked, cmap=cmap, vmin=-1, vmax=4,
               interpolation="nearest")
axes[1].set_title("Palm Oil Age Class Map", fontsize=12)
axes[1].axis("off")

patches = [mpatches.Patch(color=AGE_COLORS[c], label=AGE_LABELS[c])
           for c in class_ids]
axes[1].legend(handles=patches, loc="lower right",
               fontsize=9, framealpha=0.92,
               title="Age Class", title_fontsize=9)

plt.suptitle("Estimasi Umur Kelapa Sawit - Kalimantan Tengah, 2018",
             fontsize=13, fontweight="bold", y=1.01)
plt.tight_layout()
plt.savefig("age_class_map.png", dpi=150, bbox_inches="tight")
plt.show()
```

Visualisasi dapat dilakukan dengan melakukan overlay data citra maupun peta klasifikasi dengan basemap yang tersedia. Contoh pada gambar kiri merupakan overlay antara scene citra Sentinel-2 dengan basemap citra satelit Esri dan gambar kanan merupakan overlay peta hasil kelasifikasi dengan open street map. Overlay dapat diubah sesuai dengan kebutuhan.

```{code-cell} ipython3
# ── Step A: Transformer UTM 49S → WGS84 ──────────────────────────────────────
transformer = Transformer.from_crs("EPSG:32749", "EPSG:4326", always_xy=True)

# ── Step B: Centre ────────────────────────────────────────────────────────────
cen_lon, cen_lat = transformer.transform(
    float(scene.x.mean()),
    float(scene.y.mean())
)

# ── Step C: Bounds for ImageOverlay ──────────────────────────────────────────
lon_min, lat_min = transformer.transform(float(scene.x.min()), float(scene.y.min()))
lon_max, lat_max = transformer.transform(float(scene.x.max()), float(scene.y.max()))
bounds = [[lat_min, lon_min], [lat_max, lon_max]]

# ── Step D: Convert x/y arrays to WGS84 for age_da coords ────────────────────
x_wgs = np.array([transformer.transform(x, float(scene.y.mean()))[0]
                  for x in scene.x.values])
y_wgs = np.array([transformer.transform(float(scene.x.mean()), y)[1]
                  for y in scene.y.values])

from odc.geo.xr import assign_crs

# ── Step E: Build age_da with CRS attached ────────────────────────────────────
age_da = xr.DataArray(
    age_masked.astype(float),
    dims=["y", "x"],
    coords={"y": y_wgs, "x": x_wgs}
)
age_da = age_da.where(age_da >= 0)

# Attach CRS so odc.add_to() can read it
age_da = assign_crs(age_da, crs="EPSG:4326")

# ── Step F: RGB PNG for ImageOverlay ─────────────────────────────────────────
rgb_display_clipped = np.stack([
    np.clip(scene["red"].values.astype(float)   / 10000 * 3.5, 0, 1),
    np.clip(scene["green"].values.astype(float) / 10000 * 3.5, 0, 1),
    np.clip(scene["blue"].values.astype(float)  / 10000 * 3.5, 0, 1),
], axis=0)

fig, ax = plt.subplots(figsize=(8, 8))
ax.imshow(np.transpose(rgb_display_clipped, (1, 2, 0)))
ax.axis("off")
plt.savefig("rgb_temp.png", dpi=150, bbox_inches="tight", pad_inches=0)
plt.close()

# ── Step G: Colormap ──────────────────────────────────────────────────────────
AGE_COLORS_LIST = ["#d9534f", "#f0ad4e", "#aad576", "#2d6a4f", "#6c757d"]
age_cmap = ListedColormap(AGE_COLORS_LIST)

# ── Step H: Dual Map ──────────────────────────────────────────────────────────
m = plugins.DualMap(location=(cen_lat, cen_lon), zoom_start=14, tiles=None)

# Left — Satellite + RGB
folium.TileLayer(
    tiles='https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}',
    attr='Esri',
    name='Satellite'
).add_to(m.m1)

ImageOverlay(
    image="rgb_temp.png",
    bounds=bounds,
    opacity=0.9,
    name="Sentinel-2 RGB"
).add_to(m.m1)

# Right — OSM + Age class
folium.TileLayer('OpenStreetMap').add_to(m.m2)

age_da.odc.add_to(
    m.m2,
    cmap=age_cmap,
    vmin=0,
    vmax=4,
    name="Palm Age Class",
    opacity=0.8
)

# ── Step I: Legend ────────────────────────────────────────────────────────────
legend_html = """
<div style="position:fixed; bottom:30px; right:30px; background:white;
     border:2px solid #aaa; border-radius:8px; padding:12px 16px;
     font-size:13px; font-family:Arial,sans-serif;
     z-index:9999; box-shadow:2px 2px 6px rgba(0,0,0,0.3);">
  <b style="font-size:14px;">Palm Age Class</b><br><br>
  <i style="background:#d9534f;width:14px;height:14px;display:inline-block;margin-right:6px;border-radius:2px;"></i>Cleared (0-1 yr)<br>
  <i style="background:#f0ad4e;width:14px;height:14px;display:inline-block;margin-right:6px;border-radius:2px;"></i>Immature (1-3 yr)<br>
  <i style="background:#aad576;width:14px;height:14px;display:inline-block;margin-right:6px;border-radius:2px;"></i>Young (3-6 yr)<br>
  <i style="background:#2d6a4f;width:14px;height:14px;display:inline-block;margin-right:6px;border-radius:2px;"></i>Prime (6-15 yr)<br>
  <i style="background:#6c757d;width:14px;height:14px;display:inline-block;margin-right:6px;border-radius:2px;"></i>Old (&gt;15 yr)<br>
</div>
"""
m.m2.get_root().html.add_child(folium.Element(legend_html))
folium.LayerControl().add_to(m.m1)
folium.LayerControl().add_to(m.m2)
m
```

## 9. Perhitungan estimasi luas lahan

Tahap ini merupakan perhitungan statistik luasan pada lahan. Pendekatan yang dilakukan yakni dengan resolusi spasial citra (Sentinel = 10 m) kemudian di konversi dengan luasan area metrik. Hasil tersebut kemudian dapat di persentase dalam satu cakupan wilayah.

```{code-cell} ipython3
# Perhitungan Estimasi Luas Lahan
total_valid = (age_masked >= 0).sum()

print("\n📊 Age Class Distribution (all valid pixels):")
print(f"   {'Class':<25} {'Pixels':>8}   {'Area (ha)':>10}   {'%':>6}")
print("   " + "-" * 55)
for c in class_ids[1:]:
    count   = (age_masked == c).sum()
    area_ha = count * 100 / 10000
    pct     = count / total_valid * 100 if total_valid > 0 else 0
    print(f"   {AGE_LABELS[c]:<25} {count:>8,}   {area_ha:>10.1f}   {pct:>5.1f}%")
print(f"\n   {'TOTAL VALID':<25} {total_valid:>8,}   "
      f"{total_valid * 100 / 10000:>10.1f}   100.0%")
```

# Catatan
Modul ini memberikan gambaran penggunaan citra multispektral Sentinel 2 dengan hasil:
1. Metode transformasi citra mampu melakukan estimasi perhitungan umur sawit dengan resolusi menengah
2. Umur kelapa sawit dapat diindikasi dari berbagai jenis transformasi citra yang digunakan
3. Distribusi data menunjukkan mayoritas area merupakan umur sawit 6-15 tahun

+++

# Info

- Modul ini dijalankan di platform Piksel. Jika ada pertanyaan atau komentar, silahkan email ke piksel@big.go.id
- **Lisensi:** Skrip dalam notebook ini dilisensikan berdasarkan [Apache License, Version 2.0](https://www.apache.org/licenses/LICENSE-2.0). 
Data Piksel dilisensikan berdasarkan lisensi [Creative Commons by Attribution 4.0](https://creativecommons.org/licenses/by/4.0/).
