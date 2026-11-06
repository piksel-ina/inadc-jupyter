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

| <h1><b>Monitoring Penanaman Padi</b></h1> | ![](files/piksel_logo_small.png) |
|:---------|----------:|
- **Data:** Sentinel-2
- **Lokasi:** Kecamatan Telagasari, Kabupaten Karawang, Provinsi Jawa Barat
- **Metode:** Menggunakan indeks NDVI dan LSWI

+++

# Pendahuluan
Modul ini bertujuan untuk memberikan contoh penggunaan data Sentinel-2 untuk memonitor pertumbuhan padi dalam setahun. Empat spektral indeks yang digunakan adalah:
1. Normalized Difference Vegetation Index (NDVI)
2. Land Surface Water Index (LSWI)
3. Enhanced Vegetation Index (EVI)
4. Normalized Difference Red Edge (NDRE)

Selain itu, modul ini menghasilkan juga kualitas peta fenologi, tanaman padi, estimasi hasil panen, dan dashboard pemantauan nya. Periode yang dianalisis adalah antara bulan Mei dan November 2025
Lokasi yang digunakan adalah di Kecamatan Telagasari, Kabupaten Karawang, Provinsi Jawa Barat [🔗](https://maps.app.goo.gl/VybygWDVC4UXijNd6)

+++

# Tahapan

Tahapan dalam memonitor penanaman padi adalah sebagai berikut:
1. Persiapan data
2. Menghitung indeks spektral
3. Identifikasi lahan sawah
4. Membuat data time series
5. Mendeteksi tahap pertumbuhan padi
6. Membuat peta fenologi
7. Memonitor kondisi padi
8. Prediksi panen
9. Dashboard untuk monitoring

***

+++

## 1. Persiapan data

Beberapa library dibuka untuk keperluan modul ini.

```{code-cell} ipython3
import datacube
import pandas as pd
import xarray as xr
import numpy as np
import matplotlib.pyplot as plt

# Memulai datacube
dc = datacube.Datacube()
```

Menentukan lokasi dan periode untuk pemrosesan data sebelum membuka data.

```{code-cell} ipython3
# Lokasi [sekitar 5:25 menit]
latitude = (-6.315, -6.290)
longitude = (107.390, 107.440)

# periode
time_range = ('2025-05-15', '2025-11-25')

# Membuka Sentinel-2 data
data = dc.load(
    product='s2_l2a',
    x=longitude,
    y=latitude,
    time=time_range,
    measurements=['blue', 'green', 'red', 'red_edge_1', 'nir', 'swir_1', 'scl'],
    resolution=(-10, 10),
    group_by="solar_day",
    output_crs="EPSG:32748",
    driver="rio",
)
print(data)
```

Membuat data yang bebas awan.

```{code-cell} ipython3
# Membuat cloud-free mask 
good_quality = [4, 5, 6, 7]  # Vegetation, Not Vegetated, Water, Unclassified
cloud_free_mask = data.scl.isin(good_quality)

# Apply mask ke semua kanal
data = data.where(cloud_free_mask)
```

## 2. Menghitung indeks spektral

Untuk memonitor tenaman padi, maka digunakan 4 indeks spektral:
1. NDVI (Normalized Difference Vegetation Index): mengukur tingkat kehijauan/ kesehatan vegetasi; semakin tinggi nilainya, semakin rapat dan sehat vegetasi.
$$NDVI = \frac{(NIR - red)}{(NIR + red)}$$
2. EVI (Enhanced Vegetation Index): mendapatkan kerapatan vegetasi.
$$EVI = 2.5 * \frac{(NIR - red)}{(NIR + 6 * red - 7.5 * blue + 1)}$$
3. LSWI (Land Surface Water Index): mendeteksi genangan air.
$$LSWI = \frac{(NIR - SWIR1)}{(NIR + SWIR1)}$$
4. NDRE (Normalized Difference Red Edge): mendeteksi kondisi nitrogen dan chlorofil.
$$NDRE = \frac{(NIR - rededge1)}{(NIR + rededge1)}$$
dimana:
- red = Band merah
- blue = Band biru
- NIR = Near Infrared 
- SWIR1 = Short Wave Infrared 1
- rededge1 = Red edge 1 (705 nm)

```{code-cell} ipython3
def calculate_ndvi(data):
    ndvi = (data.nir - data.red) / (data.nir + data.red)
    return ndvi
def calculate_evi(data):
    evi = 2.5 * ((data.nir - data.red) / 
                 (data.nir + 6 * data.red - 7.5 * data.blue + 1))
    return evi
def calculate_lswi(data):
    lswi = (data.nir - data.swir_1) / (data.nir + data.swir_1)
    return lswi
def calculate_ndre(data):
    ndre = (data.nir - data.red_edge_1) / (data.nir + data.red_edge_1)
    return ndre

# Menghitung indeks
ndvi = calculate_ndvi(data)
evi = calculate_evi(data)
lswi = calculate_lswi(data)
ndre = calculate_ndre(data)
```

## 3. Identifikasi lahan sawah

Lahan sawah dideteksi dengan area sawah yang tergenang.

```{code-cell} ipython3
# Dalam masa tanam: LSWI tinggi, NDVI rendah
def detect_paddy_flooding(ndvi, lswi, evi):
    # Conditions for flooded paddy:
    # - LSWI > NDVI (more water than vegetation)
    # - LSWI > 0.05 (water present)
    # - EVI < 0.3 (low vegetation)
    paddy_mask = (lswi > ndvi) & (lswi > 0.05) & (evi < 0.3)
    return paddy_mask

# deteksi sawah pada tahap awal
early_season = data.isel(time=slice(0, 5))
ndvi_early = calculate_ndvi(early_season)
lswi_early = calculate_lswi(early_season)
evi_early = calculate_evi(early_season)

# membuat mask lahan sawah
paddy_mask = detect_paddy_flooding(ndvi_early, lswi_early, evi_early)
paddy_fields = paddy_mask.max(dim='time')
```

## 4. Membuat data time series

Untuk mengetahui perubahan indeks spektral terhadap waktu maka dibuat data selama tahun 2025.

```{code-cell} ipython3
# menghitung time series pada area sawah
ndvi_paddy = ndvi.where(paddy_fields)
evi_paddy = evi.where(paddy_fields)
lswi_paddy = lswi.where(paddy_fields)
ndre_paddy = ndre.where(paddy_fields)

# menghitung spatial mean untuk setiap waktu 
ndvi_ts = ndvi_paddy.mean(dim=['x', 'y'])
evi_ts = evi_paddy.mean(dim=['x', 'y'])
lswi_ts = lswi_paddy.mean(dim=['x', 'y'])
ndre_ts = ndre_paddy.mean(dim=['x', 'y'])

# interpolasi agar data yang kosong terisi
ndvi_ts = ndvi_ts.interpolate_na(dim="time", method="linear")
evi_ts  = evi_ts.interpolate_na(dim="time", method="linear")
lswi_ts = lswi_ts.interpolate_na(dim="time", method="linear")
ndre_ts = ndre_ts.interpolate_na(dim="time", method="linear")

# plot data
plt.figure(figsize=(18, 5))

plt.subplot(1, 2, 1)
ndvi_ts.plot(marker='o', color='green')
plt.title('NDVI')
plt.xlabel('Bulan'); plt.ylabel('NDVI')
plt.grid(True)

plt.subplot(1, 2, 2)
lswi_ts.plot(marker='o', color='blue')
plt.title('LSWI')
plt.xlabel('Bulan'); plt.ylabel('LSWI')
plt.grid(True)

plt.tight_layout()
plt.show()
```

## 5. Mendeteksi tahap pertumbuhan padi

Berikut adalah tahapan dalam menentukan pertumbuhan padi yang terdiri dari:
1. Transplanting
2. Peak Vegetation
3. Vegetative Growth
4. Heading
5. Maturity
6. Harvest

```{code-cell} ipython3
def detect_growth_stages_robust(ndvi_ts, evi_ts, lswi_ts):
    # merubah data ke numpy arrays dan menghapus NaN
    ndvi_values = ndvi_ts.values
    evi_values = evi_ts.values
    lswi_values = lswi_ts.values
    time_values = ndvi_ts.time.values
    
    # cek jumlah data yang valid
    valid_ndvi = ~np.isnan(ndvi_values)
    valid_evi = ~np.isnan(evi_values)
    valid_lswi = ~np.isnan(lswi_values)
    
    print("\n" + "="*65)
    print("🔵 VALIDASI DATA")
    print("="*65)
    print(f"Valid NDVI points: {valid_ndvi.sum()}/{len(ndvi_values)}")
    print(f"Valid EVI points: {valid_evi.sum()}/{len(evi_values)}")
    print(f"Valid LSWI points: {valid_lswi.sum()}/{len(lswi_values)}")
    
    if valid_ndvi.sum() < 5:
        print("❌ ERROR: Not enough valid NDVI data points (need at least 5)")
        return None
    
    stages = {}
    
    # dilanjutkan dengan data yang valid
    valid_indices = np.where(valid_ndvi)[0]
    valid_ndvi_vals = ndvi_values[valid_indices]
    valid_times = time_values[valid_indices]
    
    print(f"NDVI range: {valid_ndvi_vals.min():.3f} to {valid_ndvi_vals.max():.3f}\n")
    
    # 1. TRANSPLANTING: Awal penanaman dengan mengairi lahan (LSWI yang tinggi)
    try:
        valid_lswi_indices = np.where(valid_lswi)[0]
        if len(valid_lswi_indices) > 0:
            valid_lswi_vals = lswi_values[valid_lswi_indices]
            valid_lswi_times = time_values[valid_lswi_indices]
            
            # mencari puncak LSWI dalam sepertiga waktu tanam
            early_period = len(valid_lswi_vals) // 3
            if early_period > 0:
                transplanting_idx = np.argmax(valid_lswi_vals[:early_period])
                stages['transplanting'] = valid_lswi_times[transplanting_idx]
                print(f"✔️ Transplanting detected: {str(stages['transplanting'])[:10]}")
            else:
                # observasi pertama sebagai proxy
                stages['transplanting'] = valid_lswi_times[0]
                print(f"⚠ Transplanting estimated (first obs): {str(stages['transplanting'])[:10]}")
        else:
            stages['transplanting'] = valid_times[0]
            print(f"⚠ Transplanting estimated (first NDVI obs): {str(stages['transplanting'])[:10]}")
    except Exception as e:
        stages['transplanting'] = valid_times[0]
        print(f"⚠ Transplanting detection failed, using first observation: {str(stages['transplanting'])[:10]}")
    
    # 2. PEAK VEGETATION: NDVI maximum
    try:
        peak_idx_in_valid = np.argmax(valid_ndvi_vals)
        peak_idx = valid_indices[peak_idx_in_valid]
        stages['peak_vegetation'] = time_values[peak_idx]
        peak_ndvi_value = ndvi_values[peak_idx]
        print(f"✔️ Peak vegetation detected: {str(stages['peak_vegetation'])[:10]} (NDVI={peak_ndvi_value:.3f})")
    except Exception as e:
        print(f"❌ Peak vegetation detection failed: {e}")
        return None
    
    # 3. VEGETATIVE GROWTH: 50% dari puncak NDVI (setelah transplanting)
    try:
        threshold_50 = 0.5 * peak_ndvi_value
        # menentukan nilai indeks sebelum puncak
        before_peak_mask = valid_indices < peak_idx
        before_peak_indices = valid_indices[before_peak_mask]
        before_peak_values = valid_ndvi_vals[before_peak_mask]
        
        # menentukan saat ketika NDVI melebihi batas 50%
        above_threshold = before_peak_values >= threshold_50
        if above_threshold.any():
            vegetative_idx_in_before = np.where(above_threshold)[0][0]
            vegetative_idx = before_peak_indices[vegetative_idx_in_before]
            stages['vegetative_growth'] = time_values[vegetative_idx]
            print(f"✔️ Vegetative growth detected: {str(stages['vegetative_growth'])[:10]} (NDVI≥{threshold_50:.3f})")
        else:
            # gunakan nilai tengah antara transplanting dam puncak
            if 'transplanting' in stages:
                transplant_time = pd.to_datetime(stages['transplanting'])
                peak_time = pd.to_datetime(stages['peak_vegetation'])
                mid_time = transplant_time + (peak_time - transplant_time) / 2
                # Find closest observation to midpoint
                time_diffs = np.abs(pd.to_datetime(valid_times) - mid_time)
                mid_idx = np.argmin(time_diffs)
                stages['vegetative_growth'] = valid_times[mid_idx]
                print(f"⚠ Vegetative growth estimated (midpoint): {str(stages['vegetative_growth'])[:10]}")
    except Exception as e:
        print(f"⚠ Vegetative growth detection failed: {e}")
    
    # 4. HEADING/FLOWERING: 70-80% dari puncak NDVI (sebelum puncak)
    try:
        threshold_75 = 0.75 * peak_ndvi_value
        before_peak_mask = valid_indices < peak_idx
        before_peak_indices = valid_indices[before_peak_mask]
        before_peak_values = valid_ndvi_vals[before_peak_mask]
        
        above_threshold = before_peak_values >= threshold_75
        if above_threshold.any():
            heading_idx_in_before = np.where(above_threshold)[0][0]
            heading_idx = before_peak_indices[heading_idx_in_before]
            stages['heading'] = time_values[heading_idx]
            print(f"✔️ Heading detected: {str(stages['heading'])[:10]} (NDVI≥{threshold_75:.3f})")
        else:
            # gunakan nilai sebelum puncak
            if len(before_peak_indices) > 0:
                stages['heading'] = time_values[before_peak_indices[-1]]
                print(f"⚠ Heading estimated (before peak): {str(stages['heading'])[:10]}")
    except Exception as e:
        print(f"⚠ Heading detection failed: {e}")
    
    # 5. MATURITY/SENESCENCE: NDVI turun ke 70% dari puncak
    try:
        threshold_70 = 0.7 * peak_ndvi_value
        after_peak_mask = valid_indices > peak_idx
        after_peak_indices = valid_indices[after_peak_mask]
        after_peak_values = valid_ndvi_vals[after_peak_mask]
        
        if len(after_peak_values) > 0:
            below_threshold = after_peak_values <= threshold_70
            if below_threshold.any():
                maturity_idx_in_after = np.where(below_threshold)[0][0]
                maturity_idx = after_peak_indices[maturity_idx_in_after]
                stages['maturity'] = time_values[maturity_idx]
                print(f"✔️ Maturity detected: {str(stages['maturity'])[:10]} (NDVI≤{threshold_70:.3f})")
            else:
                # Use last observation
                stages['maturity'] = valid_times[-1]
                print(f"⚠ Maturity estimated (last obs): {str(stages['maturity'])[:10]}")
        else:
            stages['maturity'] = valid_times[-1]
            print(f"⚠ Maturity estimated (last obs): {str(stages['maturity'])[:10]}")
    except Exception as e:
        print(f"⚠ Maturity detection failed: {e}")
    
    # 6. HARVEST: penurunan NDVI yang drastis (dibawah 50% dari puncak)
    try:
        threshold_50_harvest = 0.5 * peak_ndvi_value
        after_peak_mask = valid_indices > peak_idx
        after_peak_indices = valid_indices[after_peak_mask]
        after_peak_values = valid_ndvi_vals[after_peak_mask]
        
        if len(after_peak_values) > 0:
            below_threshold = after_peak_values <= threshold_50_harvest
            if below_threshold.any():
                harvest_idx_in_after = np.where(below_threshold)[0][0]
                harvest_idx = after_peak_indices[harvest_idx_in_after]
                stages['harvest'] = time_values[harvest_idx]
                print(f"✔️ Harvest detected: {str(stages['harvest'])[:10]} (NDVI≤{threshold_50_harvest:.3f})")
    except Exception as e:
        print(f"⚠ Harvest detection not possible: {e}")
    print("="*65)
    return stages

stages = detect_growth_stages_robust(ndvi_ts, evi_ts, lswi_ts)

if stages is None:
    print("\n❌ Growth stage detection failed. Please check your data quality.")
else:
    print("\n" + "="*65)
    print("🟢 TAHAPAN PERTUMBUHAN PADI")
    print("="*65)
    for stage, date in stages.items():
        print(f"{stage.replace('_', ' ').title():25s}: {str(date)[:10]}")
    print("="*65)
```

Menghitung lama periode dalam setiap tahapan.

```{code-cell} ipython3
def calculate_stage_durations(stages):
    if stages is None or len(stages) < 2:
        print("Not enough stages detected")
        return
    
    # Convert to pandas datetime
    stage_dates = {k: pd.to_datetime(v) for k, v in stages.items()}
    
    # Sort by date
    sorted_stages = sorted(stage_dates.items(), key=lambda x: x[1])
    
    print("\n" + "="*65)
    print("⏳ PERIODE PERTUMBUHAN PADI")
    print("="*65)
    
    total_duration = (sorted_stages[-1][1] - sorted_stages[0][1]).days
    
    for i in range(len(sorted_stages) - 1):
        stage1_name, stage1_date = sorted_stages[i]
        stage2_name, stage2_date = sorted_stages[i + 1]
        
        duration = (stage2_date - stage1_date).days
        
        print(f"{stage1_name.replace('_', ' ').title():25s} → "
              f"{stage2_name.replace('_', ' ').title():25s}: "
              f"{duration:3d} days")
    
    print("="*65)
    print(f"{'⏳ TOTAL PERTUMBUHAN PADI':50s}: {total_duration:3d} days")
    print("="*65)
    
    # Typical rice growth durations for comparison
    print("\n📊 PERBANDINGAN DENGAN PERIODE UMUM:")
    print("-"*65)
    print("Typical durations:")
    print("  Transplanting → Vegetative: 20-40 days")
    print("  Vegetative → Heading:       30-50 days")
    print("  Heading → Maturity:         30-40 days")
    print("  Total season:               90-130 days (varies by variety)")
    print("-"*65)

# Calculate durations
if stages is not None:
    calculate_stage_durations(stages)
```

Plot perubahan indeks spektral dan tahapan pertumbuhan padi

```{code-cell} ipython3
def plot_growth_stages(ndvi_ts, evi_ts, lswi_ts, stages):
    if stages is None:
        print("No stages to plot")
        return
    fig, axes = plt.subplots(2, 1, figsize=(16, 10))
    stage_colors = {
        'transplanting': 'blue',
        'vegetative_growth': 'lightgreen',
        'heading': 'orange',
        'peak_vegetation': 'darkgreen',
        'maturity': 'brown',
        'harvest': 'red'
    }
    
    # Plot 1: NDVI dengan tahapan
    axes[0].plot(ndvi_ts.time, ndvi_ts, 'o-', color='green', 
                 linewidth=2, markersize=6, label='NDVI', alpha=0.7)
    axes[0].set_ylabel('NDVI', fontsize=12)
    axes[0].set_xlabel('Bulan', fontsize=12)
    axes[0].set_title('Tahap Pertumbuhan Padi - NDVI', fontsize=14, fontweight='bold')
    axes[0].grid(True, alpha=0.3)
    axes[0].set_ylim([0, max(0.6, np.nanmax(ndvi_ts.values) * 1.1)])
    
    # menandai tahapan
    for stage, date in stages.items():
        date_dt = pd.to_datetime(date)
        # Find closest NDVI value
        time_diffs = np.abs(pd.to_datetime(ndvi_ts.time.values) - date_dt)
        closest_idx = np.argmin(time_diffs)
        ndvi_val = ndvi_ts.values[closest_idx]
        
        if not np.isnan(ndvi_val):
            axes[0].axvline(date_dt, color=stage_colors.get(stage, 'gray'), 
                           linestyle='--', linewidth=2, alpha=0.7)
            axes[0].plot(date_dt, ndvi_val, 'o', 
                        color=stage_colors.get(stage, 'gray'), 
                        markersize=12, markeredgewidth=2, markeredgecolor='black',
                        label=stage.replace('_', ' ').title())
    
    axes[0].legend(loc='best', fontsize=9, ncol=2)
    
    # Plot 2: LSWI dengan tahapan
    axes[1].plot(lswi_ts.time, lswi_ts, 'o-', color='blue', 
                 linewidth=2, markersize=6, label='LSWI', alpha=0.7)
    axes[1].set_ylabel('LSWI', fontsize=12)
    axes[1].set_xlabel('Bulan', fontsize=12)
    axes[1].set_title('Kondisi air - LSWI', fontsize=14, fontweight='bold')
    axes[1].grid(True, alpha=0.3)
    
    for stage, date in stages.items():
        axes[1].axvline(pd.to_datetime(date), 
                       color=stage_colors.get(stage, 'gray'), 
                       linestyle='--', linewidth=2, alpha=0.5)
    plt.tight_layout()
    plt.show()

# membuat plot
if stages is not None:
    plot_growth_stages(ndvi_ts, evi_ts, lswi_ts, stages)
```

## 6. Membuat peta fenologi

Peta fenologi adalah representasi visual yang menunjukkan pola fenologi (peristiwa biologis berulang seperti berbunga, berbuah, dan migrasi)

```{code-cell} ipython3
# smoothing data
ndvi_smooth = ndvi_ts.rolling(time=3, center=True).mean()
evi_smooth  = evi_ts.rolling(time=3, center=True).mean()
lswi_smooth = lswi_ts.rolling(time=3, center=True).mean()

# cek jika tahap pertumbuhan dideteksi
if 'stages' not in locals() or stages is None:
    print("\n❌ ERROR: Growth stages not detected!")
    print("Please run 'detect_growth_stages_robust.py' first to detect growth stages.")
    print("The 'stages' variable should be available in your workspace.")
else:
    print("\n✓ Using pre-detected growth stages:")
    print("-" * 70)
    for stage, date in stages.items():
        print(f"  {stage.replace('_', ' ').title():25s}: {str(date)[:10]}")
    print("-" * 70)

# buat peta fenologi
def create_phenology_map(ndvi_stack, stage_date, window_days=10):
    stage_date = pd.to_datetime(stage_date)
    
    # menemukan images
    time_diff = np.abs((pd.to_datetime(ndvi_stack.time.values) - stage_date).total_seconds() / 86400)
    
    within_window = time_diff <= window_days
    
    if within_window.sum() == 0:
        print(f"  ⚠ Warning: No images found within {window_days} days of {stage_date.strftime('%Y-%m-%d')}")
        # Find closest image
        closest_idx = np.argmin(time_diff)
        print(f"    Using closest image ({time_diff[closest_idx]:.1f} days away)")
        return ndvi_stack.isel(time=closest_idx)
    
    # rerata image
    phenology_map = ndvi_stack.isel(time=within_window).mean(dim='time')
    print(f"  ✓ Averaged {within_window.sum()} images within {window_days} days")
    
    return phenology_map

# membuat peta fenologi untuk setiap tahapan
if 'stages' in locals() and stages is not None:
    print("\nGenerating phenology maps...")
    print("-" * 70)
    
    phenology_maps = {}
    
    stage_titles = {
        'transplanting': 'Transplanting',
        'vegetative_growth': 'Vegetative Growth',
        'heading': 'Heading/Flowering',
        'peak_vegetation': 'Peak Vegetation',
        'maturity': 'Maturity/Senescence',
        'harvest': 'Harvest'
    }
    
    for stage_name, stage_date in stages.items():
        print(f"\nProcessing {stage_name.replace('_', ' ').title()}...")
        phenology_maps[stage_name] = create_phenology_map(ndvi, stage_date, window_days=10)
    
    print("\n" + "-" * 70)
    print("✓ Phenology maps created for all detected stages")
    
    # mengurut tahapan berdasarkan waktu
    sorted_stages = sorted(stages.items(), key=lambda x: pd.to_datetime(x[1]))
    
    print("\n✓ Stages sorted chronologically:")
    for stage_name, stage_date in sorted_stages:
        print(f"  {stage_name.replace('_', ' ').title():25s}: {str(stage_date)[:10]}")
    
    # plot peta fenologi dengan dimensi yang proposional 
    print("\nCreating phenology map visualization...")

    try:
        x_range = float(ndvi.x.max() - ndvi.x.min())
        y_range = float(ndvi.y.max() - ndvi.y.min())
        aspect_ratio = x_range / y_range
    except:
        # Fallback to pixel dimensions
        aspect_ratio = ndvi.sizes['x'] / ndvi.sizes['y']
    
    subplot_width = 5
    subplot_height = subplot_width / aspect_ratio
    
    n_stages = len(sorted_stages)
    n_cols = 3
    n_rows = int(np.ceil(n_stages / n_cols))
    
    fig_width = subplot_width * n_cols
    fig_height = subplot_height * n_rows
    fig, axes = plt.subplots(n_rows, n_cols, figsize=(fig_width, fig_height))
    
    if n_rows == 1:
        axes = axes.reshape(1, -1)
    axes = axes.flatten()
    cmap = plt.cm.YlGn
    
    for idx, (stage_name, stage_date) in enumerate(sorted_stages):
        if idx >= len(axes):
            break
        ax = axes[idx]
        phen_map = phenology_maps[stage_name]
        
        if 'paddy_fields' in locals():
            phen_map_masked = phen_map.where(paddy_fields)
        else:
            phen_map_masked = phen_map
        
        im = phen_map_masked.plot(ax=ax, cmap=cmap, vmin=0, vmax=0.8,
                                   add_colorbar=False)
        ax.set_aspect('auto')
        cbar = plt.colorbar(im, ax=ax, fraction=0.046, pad=0.04)
        cbar.set_label('NDVI', fontsize=10)
        date_str = pd.to_datetime(stage_date).strftime('%Y-%m-%d')
        title = stage_titles.get(stage_name, stage_name.replace('_', ' ').title())
        ax.set_title(f"{title}\n{date_str}", 
                     fontsize=11, fontweight='bold')
        ax.set_xlabel('x (m)', fontsize=9)
        ax.set_ylabel('y (m)', fontsize=9)
    for idx in range(len(sorted_stages), len(axes)):
        fig.delaxes(axes[idx])
    plt.tight_layout()
    plt.show()
    
    # membuat timeline fenologi
    print("\nCreating phenology timeline...")
    
    fig, ax = plt.subplots(figsize=(14, 6))
    ax.plot(ndvi_smooth.time, ndvi_smooth, '-', linewidth=2.5, 
            color='darkgreen', label='NDVI (Smoothed)', zorder=1)
    stage_colors = {
        'transplanting': '#1f77b4',      # Blue
        'vegetative_growth': '#2ca02c',  # Green
        'heading': '#ff7f0e',            # Orange
        'peak_vegetation': '#d62728',    # Red
        'maturity': '#9467bd',           # Purple
        'harvest': '#8c564b'             # Brown
    }
    for stage_name, stage_date in sorted_stages:
        stage_date_pd = pd.to_datetime(stage_date)
        
        # mendapatkan nilai NDVI 
        time_diffs = np.abs((pd.to_datetime(ndvi_smooth.time.values) - stage_date_pd).total_seconds())
        closest_idx = np.argmin(time_diffs)
        ndvi_value = float(ndvi_smooth.values[closest_idx])
        
        # plot garis tegak
        color = stage_colors.get(stage_name, 'gray')
        ax.axvline(stage_date_pd, color=color, 
                   linestyle='--', linewidth=2, alpha=0.7, zorder=2)
        
        # Add marker
        ax.scatter(stage_date_pd, ndvi_value, s=100, color=color, 
                   edgecolors='black', linewidths=1.5, zorder=3)
        label = stage_titles.get(stage_name, stage_name.replace('_', ' ').title())
        ax.text(stage_date_pd, ndvi_value + 0.03, label, 
                rotation=45, verticalalignment='bottom', horizontalalignment='left',
                fontsize=9, color=color, fontweight='bold')
    
    ax.set_title('Rice Phenology Timeline', fontsize=14, fontweight='bold')
    ax.set_xlabel('Date', fontsize=12)
    ax.set_ylabel('NDVI', fontsize=12)
    ax.grid(True, alpha=0.3, zorder=0)
    ax.legend(loc='best', fontsize=10)
    
    y_min = float(ndvi_smooth.min()) - 0.05
    y_max = float(ndvi_smooth.max()) + 0.15
    ax.set_ylim(y_min, y_max)
    
    plt.tight_layout()
    plt.show()
    
    # ringkasan statistik
    print("\n" + "="*65)
    print("RINGKASAN PETA FENOLOGI")
    print("="*65)
    print(f"Total growth stages detected: {len(stages)}")
    print(f"Phenology maps generated: {len(phenology_maps)}")
    
    # menghitung periode masa pertumbuhan
    if 'transplanting' in stages and 'harvest' in stages:
        season_start = pd.to_datetime(stages['transplanting'])
        season_end = pd.to_datetime(stages['harvest'])
        season_length = (season_end - season_start).days
        print(f"Growing season length: {season_length} days")
    elif 'transplanting' in stages and 'maturity' in stages:
        season_start = pd.to_datetime(stages['transplanting'])
        season_end = pd.to_datetime(stages['maturity'])
        season_length = (season_end - season_start).days
        print(f"Growing season length (to maturity): {season_length} days")
    
    print("\nChronological order of stages:")
    for idx, (stage_name, stage_date) in enumerate(sorted_stages, 1):
        print(f"  {idx}. {stage_name.replace('_', ' ').title():25s}: {str(stage_date)[:10]}")
    print("="*65)
```

## 7. Memonitor kondisi padi

Tahapan ini untuk mengetahui kesehatan tanaman antara healthy dan stressed.

```{code-cell} ipython3
def assess_crop_health(ndvi_ts, evi_ts, ndre_ts, stages):
    health_report = {}
    
    expected_ranges = {
        'tillering': {'ndvi': (0.3, 0.6), 'evi': (0.2, 0.5)},
        'peak_vegetation': {'ndvi': (0.6, 0.9), 'evi': (0.5, 0.8)},
        'heading': {'ndvi': (0.6, 0.85), 'evi': (0.5, 0.75)}
    }
    
    for stage, date in stages.items():
        if stage in expected_ranges:
            # menemukan indeks waktu terdekat
            time_idx = np.argmin(np.abs(ndvi_ts.time.values - date))
            
            ndvi_val = float(ndvi_ts.isel(time=time_idx))
            evi_val = float(evi_ts.isel(time=time_idx))
            
            # cek apakah dalam keadaan sehat
            ndvi_range = expected_ranges[stage]['ndvi']
            evi_range = expected_ranges[stage]['evi']
            ndvi_healthy = ndvi_range[0] <= ndvi_val <= ndvi_range[1]
            evi_healthy = evi_range[0] <= evi_val <= evi_range[1]
            health_status = 'Healthy' if (ndvi_healthy and evi_healthy) else 'Stressed'
            health_report[stage] = {
                'date': date,
                'ndvi': ndvi_val,
                'evi': evi_val,
                'status': health_status
            }
    return health_report

health_report = assess_crop_health(ndvi_ts, evi_ts, ndre_ts, stages)
print("\n🌱 KONDISI TANAMAN")
for stage, info in health_report.items():
    print(f"\n{stage.capitalize()}:")
    print(f"  Date: {info['date']}")
    print(f"  NDVI: {info['ndvi']:.3f}")
    print(f"  EVI: {info['evi']:.3f}")
    print(f"  Status: {info['status']}")
```

## 8. Prediksi panen
Hasil panen diprediksi dengan estimasi estimasi sebagai berikut:

| Yield Index | Interpretation | Expected Yield | Status |
|-------------|----------------|----------------|--------|
| **80-100** | Excellent | >6 tons/ha | 🟢 Healthy |
| **60-80** | Good | 4-6 tons/ha | 🟢 Normal |
| **40-60** | Fair | 3-4 tons/ha | 🟡 Below average |
| **20-40** | Poor | 2-3 tons/ha | 🟠 Stressed |
| **0-20** | Very Poor | <2 tons/ha | 🔴 Severe stress |

```{code-cell} ipython3
def predict_yield(ndvi_ts, evi_ts, stages):
    # puncak NDVI berkorelasi dengan panen
    peak_ndvi = float(ndvi_ts.max())
    peak_evi = float(evi_ts.max())
    
    if 'heading' in stages and 'maturity' in stages:
        heading_date = stages['heading']
        maturity_date = stages['maturity']
        # memilih periode
        reproductive_ndvi = ndvi_ts.sel(time=slice(heading_date, maturity_date))
        integrated_ndvi = float(reproductive_ndvi.mean())
        # model linear sederhana (perlu kalibrasi dgn survei lapangan)
        yield_index = (peak_ndvi * 0.4 + integrated_ndvi * 0.6) * 100
        return {
            'peak_ndvi': peak_ndvi,
            'integrated_ndvi': integrated_ndvi,
            'yield_index': yield_index,
            'note': 'Relative yield indicator (0-100), needs calibration'
        }
    return None

yield_prediction = predict_yield(ndvi_ts, evi_ts, stages)
if yield_prediction:
    print("\n 🌱 PREDIKSI PANEN")
    print(f"  Peak NDVI: {yield_prediction['peak_ndvi']:.3f}")
    print(f"  Integrated NDVI: {yield_prediction['integrated_ndvi']:.3f}")
    print(f"  Yield Index: {yield_prediction['yield_index']:.1f}")
    print(f"  {yield_prediction['note']}")
```

## 9. Dashboard untuk monitoring

Berikut adalah membuat dashboard monitoring pertumbuhan tanaman yang menampilkan beberapa informasi.

```{code-cell} ipython3
def create_monitoring_dashboard(data, paddy_fields, stages, ndvi_ts, evi_ts, lswi_ts):
    fig = plt.figure(figsize=(20, 12))
    
    # 1. peta lahan sawah
    ax1 = plt.subplot(3, 3, 1)
    paddy_fields.plot(ax=ax1, cmap='Greens')
    plt.title('Identified Paddy Fields', fontsize=12, fontweight='bold')
    ax1.set_xlabel('x (m)')
    ax1.set_ylabel('y (m)')
    
    def create_rgb_composite(data_slice, paddy_mask=None):
        red = data_slice.red.values
        green = data_slice.green.values
        blue = data_slice.blue.values
        rgb = np.stack([red, green, blue], axis=-1)
        rgb = np.nan_to_num(rgb, nan=0)
        
        # Sentinel-2 L2A is typically scaled to 0-10000
        # Scale to 0-1 range
        if rgb.max() > 1:
            rgb = rgb / 10000.0
        
        # Clip to valid range
        rgb = np.clip(rgb, 0, 1)
        
        # Apply gamma correction for better visualization
        gamma = 2.2
        rgb = np.power(rgb, 1/gamma)
        
        # Enhance contrast
        percentile_2 = np.percentile(rgb[rgb > 0], 2)
        percentile_98 = np.percentile(rgb[rgb > 0], 98)
        rgb = (rgb - percentile_2) / (percentile_98 - percentile_2)
        rgb = np.clip(rgb, 0, 1)
        
        # Apply mask if provided
        if paddy_mask is not None:
            mask_3d = np.stack([paddy_mask.values] * 3, axis=-1)
            rgb = np.where(mask_3d, rgb, np.nan)
        
        return rgb
    
    # 2. RGB composite ketika transplanting
    if 'transplanting' in stages:
        trans_date = stages['transplanting']
        ax2 = plt.subplot(3, 3, 2)
        try:
            trans_data = data.sel(time=trans_date, method='nearest')
            rgb = create_rgb_composite(trans_data, paddy_fields)
            
            # Create extent for proper coordinate display
            extent = [float(trans_data.x.min()), float(trans_data.x.max()),
                     float(trans_data.y.min()), float(trans_data.y.max())]
            
            ax2.imshow(rgb, extent=extent, origin='upper', interpolation='nearest')
            ax2.set_title(f'RGB at Transplanting\n{str(trans_date)[:10]}', 
                         fontsize=11, fontweight='bold')
            ax2.set_xlabel('x [metre]')
            ax2.set_ylabel('y [metre]')
        except Exception as e:
            ax2.text(0.5, 0.5, f'Error loading RGB:\n{str(e)}', 
                    ha='center', va='center', transform=ax2.transAxes)
            print(f"⚠ Error creating transplanting RGB: {e}")
    
    # 3. RGB saat peak vegetation
    if 'peak_vegetation' in stages:
        peak_date = stages['peak_vegetation']
        ax3 = plt.subplot(3, 3, 3)
        try:
            peak_data = data.sel(time=peak_date, method='nearest')
            rgb = create_rgb_composite(peak_data, paddy_fields)
            
            extent = [float(peak_data.x.min()), float(peak_data.x.max()),
                     float(peak_data.y.min()), float(peak_data.y.max())]
            
            ax3.imshow(rgb, extent=extent, origin='upper', interpolation='nearest')
            ax3.set_title(f'RGB at Peak Vegetation\n{str(peak_date)[:10]}', 
                         fontsize=11, fontweight='bold')
            ax3.set_xlabel('x [metre]')
            ax3.set_ylabel('y [metre]')
        except Exception as e:
            ax3.text(0.5, 0.5, f'Error loading RGB:\n{str(e)}', 
                    ha='center', va='center', transform=ax3.transAxes)
            print(f"⚠ Error creating peak RGB: {e}")
    
    # 4. NDVI dengan tahapan pertumbuhan
    ax4 = plt.subplot(3, 3, 4)
    ndvi_ts.plot(ax=ax4, marker='o', linewidth=2, color='darkgreen', markersize=6)
    
    # Define colors for each stage
    stage_colors = {
        'transplanting': '#1f77b4',
        'vegetative_growth': '#2ca02c',
        'heading': '#ff7f0e',
        'peak_vegetation': '#d62728',
        'maturity': '#9467bd',
        'harvest': '#8c564b'
    }
    
    y_max = float(ndvi_ts.max())
    for idx, (stage, date) in enumerate(stages.items()):
        color = stage_colors.get(stage, 'gray')
        ax4.axvline(date, color=color, linestyle='--', alpha=0.7, linewidth=2)
        # Stagger text heights to avoid overlap
        y_pos = y_max * (0.85 - (idx % 3) * 0.1)
        ax4.text(date, y_pos, stage.replace('_', '\n'), 
                rotation=0, fontsize=7, ha='center', color=color, fontweight='bold',
                bbox=dict(boxstyle='round,pad=0.3', facecolor='white', alpha=0.7))
    
    plt.title('NDVI Time Series with Growth Stages', fontsize=12, fontweight='bold')
    plt.ylabel('NDVI')
    plt.xlabel('Date')
    plt.grid(True, alpha=0.3)
    
    # 5. EVI time series
    ax5 = plt.subplot(3, 3, 5)
    evi_ts.plot(ax=ax5, marker='o', linewidth=2, color='green', markersize=6)
    plt.title('EVI Time Series', fontsize=12, fontweight='bold')
    plt.ylabel('EVI')
    plt.xlabel('Date')
    plt.grid(True, alpha=0.3)
    
    # 6. LSWI time series
    ax6 = plt.subplot(3, 3, 6)
    lswi_ts.plot(ax=ax6, marker='o', linewidth=2, color='blue', markersize=6)
    plt.title('LSWI Time Series (Water Content)', fontsize=12, fontweight='bold')
    plt.ylabel('LSWI')
    plt.xlabel('Date')
    plt.grid(True, alpha=0.3)
    
    # 7. peta puncak NDVI
    if 'peak_vegetation' in stages:
        ax7 = plt.subplot(3, 3, 7)
        peak_date = stages['peak_vegetation']
        peak_data = data.sel(time=peak_date, method='nearest')
        peak_ndvi = calculate_ndvi(peak_data)
        peak_ndvi_masked = peak_ndvi.where(paddy_fields)
        
        im = peak_ndvi_masked.plot(ax=ax7, cmap='RdYlGn', vmin=0, vmax=0.8, 
                                    add_colorbar=False)
        plt.colorbar(im, ax=ax7, label='NDVI')
        plt.title(f'NDVI at Peak Vegetation\n{str(peak_date)[:10]}', 
                 fontsize=11, fontweight='bold')
        ax7.set_xlabel('x (m)')
        ax7.set_ylabel('y (m)')
    
    # 8. Periode pertumbuhan
    ax8 = plt.subplot(3, 3, 8)
    if len(stages) >= 2:
        # Sort stages by date
        sorted_stages = sorted(stages.items(), key=lambda x: pd.to_datetime(x[1]))
        stage_names = [s[0] for s in sorted_stages]
        stage_dates = [pd.to_datetime(s[1]) for s in sorted_stages]
        
        durations = [(stage_dates[i+1] - stage_dates[i]).days 
                     for i in range(len(stage_dates)-1)]
        
        colors_list = [stage_colors.get(stage_names[i], 'gray') 
                      for i in range(len(durations))]
        
        bars = ax8.bar(range(len(durations)), durations, color=colors_list, alpha=0.7)
        ax8.set_xticks(range(len(durations)))
        
        # Create labels
        labels = [f"{stage_names[i].replace('_', ' ').title()}\nto\n{stage_names[i+1].replace('_', ' ').title()}" 
                 for i in range(len(durations))]
        ax8.set_xticklabels(labels, rotation=45, ha='right', fontsize=8)
        
        plt.title('Duration Between Growth Stages', fontsize=12, fontweight='bold')
        plt.ylabel('Days')
        plt.grid(True, alpha=0.3, axis='y')
        
        # Add value labels on bars
        for i, (bar, duration) in enumerate(zip(bars, durations)):
            height = bar.get_height()
            ax8.text(bar.get_x() + bar.get_width()/2., height,
                    f'{duration}d', ha='center', va='bottom', fontsize=9, fontweight='bold')
    
    # 9. Ringkasan statistik
    ax9 = plt.subplot(3, 3, 9)
    ax9.axis('off')
    
    # Calculate statistics
    paddy_area_ha = float(paddy_fields.sum()) * 100  # Assuming 10m pixels
    peak_ndvi = float(ndvi_ts.max())
    peak_evi = float(evi_ts.max())
    
    # Calculate growing season length
    if 'transplanting' in stages and 'harvest' in stages:
        season_start = pd.to_datetime(stages['transplanting'])
        season_end = pd.to_datetime(stages['harvest'])
        season_length = (season_end - season_start).days
    elif 'transplanting' in stages and 'maturity' in stages:
        season_start = pd.to_datetime(stages['transplanting'])
        season_end = pd.to_datetime(stages['maturity'])
        season_length = (season_end - season_start).days
    else:
        season_length = None
    
    summary_text = "MONITORING SUMMARY\n" + "="*35 + "\n\n"
    summary_text += f"Paddy Area: {paddy_area_ha:.2f} ha\n\n"
    
    if season_length:
        summary_text += f"Season Length: {season_length} days\n\n"
    
    summary_text += "Growth Stages:\n" + "-"*35 + "\n"
    
    # Sort stages chronologically for display
    sorted_stages = sorted(stages.items(), key=lambda x: pd.to_datetime(x[1]))
    for idx, (stage, date) in enumerate(sorted_stages, 1):
        stage_display = stage.replace('_', ' ').title()
        summary_text += f"{idx}. {stage_display:20s}\n   {str(date)[:10]}\n"
    
    summary_text += "\n" + "-"*35 + "\n"
    summary_text += f"Peak NDVI: {peak_ndvi:.3f}\n"
    summary_text += f"Peak EVI:  {peak_evi:.3f}\n"
    
    ax9.text(0.05, 0.95, summary_text, transform=ax9.transAxes, 
             fontsize=9, verticalalignment='top', family='monospace',
             bbox=dict(boxstyle='round', facecolor='lightblue', alpha=0.3, pad=1))
    
    plt.tight_layout()
    plt.show()

print("\n" + "="*95)
print("🟧 DASHBOARD MONITORING")
print("="*95)

create_monitoring_dashboard(data, paddy_fields, stages, ndvi_ts, evi_ts, lswi_ts)
```

# Catatan
Modul ini menyajikan metode pemantauan pertumbuhan padi melalui pembuatan dashboard interaktif yang menggabungkan data spasial dan temporal, termasuk luas area sawah, indeks vegetasi (NDVI dan EVI), serta tahapan pertumbuhan yang diurutkan secara kronologis. Hasil yang dicapai berupa visualisasi durasi antar tahap pertumbuhan, ringkasan statistik musim tanam (panjang musim, puncak NDVI/EVI), dan informasi luas lahan, sehingga memberikan gambaran komprehensif tentang dinamika pertumbuhan padi sekaligus memudahkan analisis perkembangan tanaman secara kuantitatif dan visual.

+++

# Info

- Modul ini dijalankan di platform Piksel. Jika ada pertanyaan atau komentar, silahkan email ke piksel@big.go.id
- **Lisensi:** Skrip dalam notebook ini dilisensikan berdasarkan [Apache License, Version 2.0](https://www.apache.org/licenses/LICENSE-2.0). 
Data Piksel dilisensikan berdasarkan lisensi [Creative Commons by Attribution 4.0](https://creativecommons.org/licenses/by/4.0/).
