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

| <h1><b>Klasifikasi Mangrove dengan _Machine Learning_</b></h1> | ![](files/piksel_logo_small.png) |
|:---------|----------:|
- **Data:** Sentinel-2
- **Lokasi:** Kota Denpasar, Provinsi Bali
- **Metode:** Penggunaan indeks spektral dan machine learning (random forest)

+++

# Pendahuluan
Modul ini bertujuan untuk memberikan contoh penggunaan data Sentinel-2 dalam delineasi area mangrove. Beberapa spektral indeks digunakan untuk cakupan area mangrove. Metode _machine learning_ dengan menggunakan _random forest_ digunakan untuk mengklasifikasikan mangrove dan tutupan lahan di sekitarnya. Lokasi mangrove yang dipilih adalah di selatan Kota Denpasar, provinsi Bali [🔗](https://maps.app.goo.gl/5KtuDPMr4G4T9vpB8).

+++

# Tahapan

Tahapan dalam klasifikasi mangrove adalah sebagai berikut:
1. Memuat library
2. Memuat data
3. Persiapan data
4. Menghitung indeks spektral
5. Membuat training data
6. Melatih _random forest classifier_
7. Analisa fitur
8. Klasifikasi mangrove
9. _Confusion matrix_ & validasi model
10. Menyimpan hasil
***

+++

## 1. Memuat library
Library yang diperlukan dimuat ke sistem dan melakukan inisialisasi datacube.

```{code-cell} ipython3
import datacube, os, json, rasterio
from datacube.utils import masking
from odc.geo import CRS
from datetime import datetime
import numpy as np
import pandas as pd
import matplotlib.pyplot as plt
import matplotlib.colors as mcolors
import xarray as xr
from rasterio.plot import show
import seaborn as sns

# library untuk machine learning
from sklearn.ensemble import RandomForestClassifier
from sklearn.model_selection import train_test_split
from sklearn.metrics import classification_report, confusion_matrix, accuracy_score
from sklearn.preprocessing import StandardScaler
```

Selanjutnya adalah inisialisasi datacube

```{code-cell} ipython3
dc = datacube.Datacube(app='klasifikasi_mangrove')
```

## 2. Memuat data
Sebelum memuat data, Wilayah dan waktu yang digunakan untuk studi ini ditetapkan.

```{code-cell} ipython3
aoi = {
    'latitude': (-8.716, -8.748),
    'longitude': (115.189, 115.213),
    'crs': 'EPSG:32750'
}
# rentang waktu data
time_range = ('2024-03-01', '2024-06-30')
```

Selanjutnya adalah memuat data Sentinel-2

```{code-cell} ipython3
# [sekitar 5:50 menit]
query = {
    'product': 's2_l2a',  
    'x': aoi['longitude'],
    'y': aoi['latitude'],
    'time': time_range,
    'measurements': ['red', 'blue', 'green', 'nir_1', 'swir_1'],
    'output_crs': 'EPSG:32750',        # UTM zone 50 Selatan
    'resolution': (-10, 10)
}
# Memuat data
ds = dc.load(**query)
print(f"Data yang dimuat  : {ds.dims}")
print(f"Band yang tersedia: {list(ds.data_vars)}")
```

## 3. Persiapan data
Sebelum memroses data, maka perlu dilakukan:
1. Membuat mask awan
2. Membuat median
3. Menampilkan data

```{code-cell} ipython3
# Membuat mask awan
if 'fmask' in ds.data_vars:
    cloud_free = masking.make_mask(ds.fmask, fmask='valid')
    ds = ds.where(cloud_free)
# Membuat median composite 
ds_median = ds.median('time', keep_attrs=True)
# Menampilkan data
fig, axes = plt.subplots(2, 3, figsize=(15, 10))
axes = axes.flatten()
bands_to_plot = ['red', 'green', 'blue', 'nir_1', 'swir_1']
for i, band in enumerate(bands_to_plot):
    if band in ds_median.data_vars:
        ds_median[band].plot(ax=axes[i], cmap='viridis')
        axes[i].set_title(f'{band}')
        axes[i].set_aspect('equal')

plt.tight_layout()
plt.show()
```

## 4. Menghitung index spektral
Untuk mendeteksi mangrove dan obyek di sekitarnya, maka digunakan 3 spektral indeks:
1. MVI (Mangrove Vegetation Index): untuk menyoroti mangrove, memanfaatkan perbedaan spektral antara NIR dan SWIR agar mangrove lebih mudah dipisahkan dari vegetasi lain.
$$MVI = \frac{(NIR1 - SWIR1)}{(NIR1 + SWIR1)}$$
2. NDVI (Normalized Difference Vegetation Index): mengukur tingkat kehijauan/ kesehatan vegetasi; semakin tinggi nilainya, semakin rapat dan sehat vegetasi.
$$NDVI = \frac{(NIR1 - red)}{(NIR1 + red)}$$
3. UI (Urban Index): membantu membedakan area terbangun/permukiman dari vegetasi dan air, sehingga berguna untuk mendeteksi non-vegetasi.
$$UI = \frac{(SWIR1 + red)}{(NIR1 + blue)}$$
dimana:
- red = Band merah
- blue = Band biru
- NIR1 = Near Infrared 1 
- SWIR1 = Short Wave Infrared 1

```{code-cell} ipython3
def calculate_indices(ds):
    # MVI (Mangrove Vegetation Index)
    mvi = (ds.nir_1 - ds.swir_1) / (ds.nir_1 + ds.swir_1)
    # NDVI (Normalized Difference Vegetation Index)
    ndvi = (ds.nir_1 - ds.red) / (ds.nir_1 + ds.red)
    # UI (Urban Index)
    ui = (ds.swir_1 + ds.red) / (ds.nir_1 + ds.blue)
    return {
        'mvi' : mvi,
        'ndvi': ndvi,
        'ui' : ui,
        'nir' : ds.nir_1
    }
# Menghitung index
indices = calculate_indices(ds_median)
# Menambah index ke dataset
for name, index in indices.items():
    ds_median[name] = index
print("Spektral indeks yang dihitung:")
for name in indices.keys():
    print(f"- {name.upper()}")
```

Berikutnya adalah menampilkan index spektral tersebut

```{code-cell} ipython3
fig, axes = plt.subplots(2, 2, figsize=(18, 12))
axes = axes.flatten()
index_names = list(indices.keys())
for i, index_name in enumerate(index_names):
    im = ds_median[index_name].plot(ax=axes[i], cmap='RdYlGn', add_colorbar=False)
    axes[i].set_title(f'{index_name.upper()}')
    axes[i].set_aspect('equal')
    plt.colorbar(im, ax=axes[i], shrink=0.6)
plt.tight_layout()
plt.show()
```

## 5. Membuat training data
Training data digunakan untuk klasifikasi. Training data dibuat berdasarkan karakteristik spektral. Ini adalah cara sederhana. Seharusnya melakukan survei lapangan.

```{code-cell} ipython3
def create_training_samples(ds, n_samples=1000):
    # mendapatkan piksel yang valid
    valid_mask = ~np.isnan(ds.ndvi.values)
    # membuat mangrove mask
    mangrove_mask = (
        (ds.mvi > 0.22) & 
        valid_mask
    )
    # membuat water mask
    water_mask = (
        (ds.nir < 1600) &
        valid_mask
    )
    # membuat non-vegetation mask
    non_veg_mask = (
        (ds.ui > 0.85) &
        (~mangrove_mask) &
        (~water_mask) &
        valid_mask
    )
    # Membuat other vegetation mask
    other_veg_mask = (
        (~mangrove_mask) &
        (~water_mask) &
        (~non_veg_mask) &
        (ds.ndvi > 0.4) & 
        valid_mask
    )
    return {
        'mangrove': mangrove_mask,
        'water': water_mask,
        'other_vegetation': other_veg_mask,
        'non_vegetation': non_veg_mask
    }
# membuat training masks
training_masks = create_training_samples(ds_median)
# menampilkan training areas
fig, axes = plt.subplots(2, 2, figsize=(12, 10))
axes = axes.flatten()
for i, (class_name, mask) in enumerate(training_masks.items()):
    mask.plot(ax=axes[i], cmap='Blues', add_colorbar=False)
    axes[i].set_title(f'{class_name.replace("_", " ").title()} Area')
    axes[i].set_aspect('equal')
plt.tight_layout()
plt.show()
```

Sebelum dilakukan klasifikasi dengan menggunakan _machine learning_, maka perlu dilakukan persiapan training data dalam _feature matrix_ yaitu array yang terstruktur yang digunakan untuk klasifikasi. Pada dasarnya adalah nilai setiap piksel terkait dengan indeks yang sudah dibuat.

```{code-cell} ipython3
# Function untuk menyiapkan training data
def prepare_training_data(ds, masks, sample_size=100):
    features = ['blue', 'green', 'red', 'nir_1', 'swir_1', 'ndvi', 'ndwi', 'mvi', 'ui']
    X_list = []; y_list = []
    
    for class_id, (class_name, mask) in enumerate(masks.items()):
        # Mendapatkan koordinat dimana ada mask
        coords = np.where(mask.values)
        if len(coords[0]) > 0:
            # Sample random points untuk kelas
            n_points = min(sample_size, len(coords[0]))
            indices = np.random.choice(len(coords[0]), n_points, replace=False)
            selected_y = coords[0][indices]
            selected_x = coords[1][indices]
            # Mendapatkan nilai feature
            class_features = []
            for feature in features:
                if feature in ds.data_vars:
                    values = ds[feature].values[selected_y, selected_x]
                    class_features.append(values)
            if class_features:
                class_features = np.column_stack(class_features)
                # Menghilangkan NaN values
                valid_idx = ~np.isnan(class_features).any(axis=1)
                class_features = class_features[valid_idx]
                if len(class_features) > 0:
                    X_list.append(class_features)
                    y_list.append(np.full(len(class_features), class_id))
    if X_list:
        X = np.vstack(X_list)
        y = np.hstack(y_list)
        return X, y, features, list(masks.keys())
    else:
        return None, None, features, list(masks.keys())

# Mempersiapkan training data
X, y, feature_names, class_names = prepare_training_data(ds_median, training_masks)
if X is not None:
    print(f"🟠 Training data shape: {X.shape}")
    print(f"🟠 Jumlah kelas: {len(np.unique(y))}")
    print(f"🟠 Distribusi kelas:")
    for i, class_name in enumerate(class_names):
        count = np.sum(y == i)
        print(f"   ▶️ {class_name}: {count} samples")
else:
    print("Tidak ada training data yang valid!")
```

## 6. Melatih _random forest classifier_
Beberapa tahapan dalam melatih _random forest classifier_ adalah:
1. Data sampel dipisahkan yaitu 70% untuk training dan 30% untuk testing.
2. Scale feature digunakan untuk normalisasi data.
3. Melatih _random forest_
4. Melakukan prediksi dan evaluasi terhadap akurasi klasifikasi

```{code-cell} ipython3
if X is not None and len(X) > 0:
    # Split data
    X_train, X_test, y_train, y_test = train_test_split(
        X, y, test_size=0.3, random_state=42, stratify=y
    )
    # Scale feature (opsional untuk Random Forest, tetapi dapat menolong)
    scaler = StandardScaler()
    X_train_scaled = scaler.fit_transform(X_train)
    X_test_scaled = scaler.transform(X_test)
    # Train Random Forest
    rf_classifier = RandomForestClassifier(
        n_estimators=100,
        max_depth=20,
        min_samples_split=5,
        min_samples_leaf=2,
        random_state=42,
        n_jobs=-1
    )
    rf_classifier.fit(X_train_scaled, y_train)
    # Membuat prediksi
    y_pred = rf_classifier.predict(X_test_scaled)
    accuracy = accuracy_score(y_test, y_pred)
    print(f"🟢 Akurasi Random Forest: {accuracy:.3f}")
    print("\n🔵 Laporan klasifikasi:")
    print(classification_report(y_test, y_pred, target_names=class_names))
else:
    print("Tidak dapat train classifier - tidak ada training data yang valid")
```

Akurasi sebesar 1.0 menunjukkan bahwa klasifier memprediksi sampel tes secara benar atau tidak ada mis klasifikasi. Hal ini dikarenakan fitur (bands dan index spektral) terpisah di area ini.

+++

## 7. Analisa Fitur
Tujuan dari analisa fitur adalah untuk mengetahui fitur mana yang paling berpengaruh dalam membedakan kelas (mangrove, water, vegetasi lain, non-vegetasi). Tahapan nya adalah:
1. Membuat fungsi _analyze_feature_importance_: untuk mengecek apakah classifier sudah dilatih dan memiliki atribut feature_importances_.
2. Ekstraksi nilai importance: Mengambil bobot kepentingan tiap fitur, membuat DataFrame berisi pasangan feature dan importance, serta mengurutkan dari yang paling penting ke yang paling rendah.
3. Output teks: Menampilkan jumlah fitur yang dipakai, memberi peringatan jika ada ketidaksesuaian jumlah nama fitur vs importance, dan menampilkan tabel ranking fitur.
4. Visualisasi: Membuat plot untuk memperlihatkan ranking fitur secara visual dan menyediakan statistik ringkas

```{code-cell} ipython3
# Fungsi untuk analisis fitur
def analyze_feature_importance(classifier, feature_names):
    if classifier is None:
        print("No trained classifier available")
        return None
    if not hasattr(classifier, 'feature_importances_'):
        print("Classifier doesn't have feature importance information")
        return None
    # Mendapatkan feature importance
    importance = classifier.feature_importances_
    print(f"Number of features in classifier: {len(importance)}")
    print(f"Number of feature names: {len(feature_names)}")
    # Jika ada mismatch
    if len(importance) != len(feature_names):
        print("Peringatan: Feature names dan importance array memiliki panjang yang berbeda")
        print("Hal ini terjadi jika ada fitur yang tidak digunakan dalam training")
        # Menggunakan generic name
        if len(importance) < len(feature_names):
            # Jika feature names lebih dari importance - kurangi feature names
            feature_names_to_use = feature_names[:len(importance)]
            print(f"Menggunakan {len(importance)} feature names")
        else:
            # Jika importance lebih dari feature names - buat generic names
            feature_names_to_use = [f'Feature_{i}' for i in range(len(importance))]
            print(f"Menggunakan generic feature names untuk {len(importance)} features")
    else:
        feature_names_to_use = feature_names
    # Membuat feature importance dataframe
    feature_importance_df = pd.DataFrame({
        'feature': feature_names_to_use,
        'importance': importance
    }).sort_values('importance', ascending=False)
    return feature_importance_df
# Cek jika ada trained classifier dan analyze feature importance
if 'rf_classifier' in locals() and rf_classifier is not None:
    print("🔵 Analisa feature importance...")
    feature_importance_df = analyze_feature_importance(rf_classifier, feature_names)
    if feature_importance_df is not None:
        print("\n🔴 Ranking Feature Importance:")
        print(feature_importance_df)
        # Plot feature importance
        plt.figure(figsize=(12, 8))
        # Membuat two subplots
        fig, (ax1, ax2) = plt.subplots(1, 2, figsize=(16, 6))
        # Bar plot
        bars = ax1.bar(range(len(feature_importance_df)), 
                      feature_importance_df['importance'], 
                      color='skyblue', alpha=0.7)
        ax1.set_xlabel('Features')
        ax1.set_ylabel('Importance')
        ax1.set_title('Feature Importance - Random Forest')
        ax1.set_xticks(range(len(feature_importance_df)))
        ax1.set_xticklabels(feature_importance_df['feature'], rotation=45, ha='right')
        # Menambah value labels
        for i, bar in enumerate(bars):
            height = bar.get_height()
            ax1.text(bar.get_x() + bar.get_width()/2., height + 0.001,
                    f'{height:.3f}', ha='center', va='bottom', fontsize=9)
        # Horizontal bar plot
        ax2.barh(range(len(feature_importance_df)), 
                feature_importance_df['importance'], 
                color='lightcoral', alpha=0.7)
        ax2.set_xlabel('Importance')
        ax2.set_ylabel('Features')
        ax2.set_title('Feature Importance - Horizontal View')
        ax2.set_yticks(range(len(feature_importance_df)))
        ax2.set_yticklabels(feature_importance_df['feature'])
        # Add value labels
        for i, importance in enumerate(feature_importance_df['importance']):
            ax2.text(importance + 0.005, i, f'{importance:.3f}', 
                    va='center', fontsize=9)
        plt.tight_layout()
        plt.show()
        # Print top features
        print(f"\n🟢 Top 5 Important Features:")
        for i, row in feature_importance_df.head().iterrows():
            print(f"{row['feature']}: {row['importance']:.4f}")
        # Feature importance statistics
        print(f"\n🟠 Statistik Feature Importance:")
        print(f"Rerata importance: {feature_importance_df['importance'].mean():.4f}")
        print(f"Std importance: {feature_importance_df['importance'].std():.4f}")
        print(f"Max importance: {feature_importance_df['importance'].max():.4f}")
        print(f"Min importance: {feature_importance_df['importance'].min():.4f}")
    else:
        print("Could not analyze feature importance")
else:
    print("No trained Random Forest classifier found.")
    print("Please run step 8 (model training) first.")
    # Check what variables are available
    if 'X' in locals() and X is not None:
        print(f"Training data is available with shape: {X.shape}")
    else:
        print("No training data available")
    if 'feature_names' in locals():
        print(f"Feature names available: {len(feature_names)} features")
        print(f"Features: {feature_names}")
    else:
        print("No feature names available")
```

Dari data feature importance, dapat disampaikan bahwa:
1. Indeks spektral (MVI, NDWI, NDVI) dan band inframerah (NIR, SWIR) adalah fitur paling informatif untuk membedakan kelas mangrove, air, vegetasi lain, dan non-vegetasi.
2. Band visual (Red, Green, Blue) tetap berkontribusi, tapi relatif lebih kecil.

+++

## 8. Klasifikasi mangrove

Tahapan dalam klasifikasi mangrove adalah sebagai berikut:
1. Ekstraksi fitur: setiap band/indeks diambil dan disusun jadi array.
2. Masking NaN: hanya piksel valid yang dipakai.
3. Scaling & Prediksi:  data valid ditransformasi lalu diprediksi kelasnya oleh Random Forest.
4. Reshape hasil: prediksi dikembalikan ke bentuk citra 2D sesuai koordinat.
5. Visualisasi hasil: True Color (RGB), False Color (NIR–Red–Green), dan Peta klasifikasi (mangrove, water, other veg, non-veg)
6. Menghitung statistik ringkas: jumlah piksel, luas hektar, dan persentase tiap kelas.

```{code-cell} ipython3
# Fungsi untuk klasifikasi mangrove 
def classify_image(ds, classifier, scaler, feature_names):
    # Menyiapkan feature array
    features_list = []
    for feature in feature_names:
        if feature in ds.data_vars:
            feature_data = ds[feature].values.flatten()
            features_list.append(feature_data)
    if not features_list:
        return None
    # Stack features
    X_image = np.column_stack(features_list)
    # Jika ada NaN values
    valid_mask = ~np.isnan(X_image).any(axis=1)
    # Inisialisasi prediction array
    predictions = np.full(X_image.shape[0], -1, dtype=int)
    if np.any(valid_mask):
        # Scale dan predict
        X_valid = scaler.transform(X_image[valid_mask])
        predictions[valid_mask] = classifier.predict(X_valid)
    # Reshape ke dimensi original image
    height, width = ds.dims['y'], ds.dims['x']
    prediction_image = predictions.reshape(height, width)
    return prediction_image

if 'rf_classifier' in locals():
    # Melakukan klasifikasi
    classification_result = classify_image(ds_median, rf_classifier, scaler, feature_names)
    if classification_result is not None:
        # Membuat xarray DataArray untuk hasil klasifikasi
        classified_da = xr.DataArray(
            classification_result,
            coords={'y': ds_median.y, 'x': ds_median.x},
            dims=['y', 'x'],
            name='classification'
        )
        # Plot hasil
        fig, (ax1, ax2, ax3) = plt.subplots(1, 3, figsize=(18, 6))
        # --- True Color (RGB) ---
        if all(band in ds_median.data_vars for band in ['red', 'green', 'blue']):
            red = ds_median.red.values
            green = ds_median.green.values
            blue = ds_median.blue.values
            rgb = np.dstack([red, green, blue])
            p2, p98 = np.percentile(rgb, (2, 98))
            rgb_norm = np.clip((rgb - p2) / (p98 - p2), 0, 1)
            ax1.imshow(rgb_norm,
                       extent=[ds_median.x.min(), ds_median.x.max(),
                               ds_median.y.min(), ds_median.y.max()])
            ax1.set_title("True Color (RGB)")
            ax1.set_aspect("equal")
        # --- False Color (NIR-Red-Green) ---
        if all(band in ds_median.data_vars for band in ['nir_1', 'red', 'green']):
            nir = ds_median.nir_1.values
            red = ds_median.red.values
            green = ds_median.green.values
            false_rgb = np.dstack([nir, red, green])
            p2, p98 = np.percentile(false_rgb, (2, 98))
            false_rgb_norm = np.clip((false_rgb - p2) / (p98 - p2), 0, 1)
            ax2.imshow(false_rgb_norm,
                       extent=[ds_median.x.min(), ds_median.x.max(),
                               ds_median.y.min(), ds_median.y.max()])
            ax2.set_title("False Color (NIR-Red-Green)")
            ax2.set_aspect("equal")
        # --- Hasil Klasifikasi ---
        custom_colors = ['#006400',  # mangrove - hijau tua
                 '#87CEFA',  # water - biru muda
                 '#90EE90',  # other vegetation - hijau muda
                 '#D3D3D3']  # non vegetation - abu-abu muda
        cmap_custom = mcolors.ListedColormap(custom_colors)
        im = ax3.imshow(classification_result,
                extent=[ds_median.x.min(), ds_median.x.max(),
                        ds_median.y.min(), ds_median.y.max()],
                cmap=cmap_custom, vmin=0, vmax=len(class_names)-1)
        ax3.set_title("Klasifikasi Mangrove")
        ax3.set_aspect("equal")
        # Menambah colorbar
        cbar = plt.colorbar(im, ax=ax3, shrink=0.6)
        cbar.set_ticks(range(len(class_names)))
        cbar.set_ticklabels(class_names)
        plt.tight_layout()
        plt.show()
        # Menghitung statistik
        pixel_area = 10 * 10  # 10m x 10m pixels (adjust based on your resolution)
        
        print("\n🟣 Statistik klasifikasi:")
        for i, class_name in enumerate(class_names):
            pixel_count = np.sum(classification_result == i)
            area_ha = (pixel_count * pixel_area) / 10000  # Convert to hectares
            percentage = (pixel_count / np.sum(classification_result >= 0)) * 100
            print(f"   ▶️ {class_name}: {pixel_count:,} pixels ({area_ha:.1f} ha, {percentage:.1f}%)")
```

Peta di atas menunjukkan sebaran mangrove yang jelas di citra false color composite dan berhasil diklasifikasikan dengan baik. Mangrove yang dipetakan seluas 320,2 hektar.

+++

## 9. _Confusion matrix_ & validasi model
_Confusion Matrix_ digunakan untuk memberikan gambaran seberapa baik model memprediksi tiap kelas (mangrove, water, other vegetation, non-vegetation). Tidak hanya melihat akurasi global, tapi juga memeriksa distribusi prediksi benar/salah per kelas. Hal ini akan membantu mendeteksi jika ada kelas tertentu yang tertukar dengan kelas lain.

```{code-cell} ipython3
if 'y_test' in locals() and 'y_pred' in locals():
    # Plot confusion matrix
    cm = confusion_matrix(y_test, y_pred)
    
    plt.figure(figsize=(8, 6))
    sns.heatmap(cm, annot=True, fmt='d', cmap='Blues',
                xticklabels=class_names, yticklabels=class_names)
    plt.title('Confusion Matrix - Klasifikasi Mangrove')
    plt.xlabel('Prediksi')
    plt.ylabel('Kenyataan')
    plt.tight_layout()
    plt.show()
```

_Confusion Matrix_ menunjukkan tidak ada angka signifikan di luar diagonal yang berarti model sangat akurat. Jika ada angka di luar diagonal → menunjukkan misclassifications (contoh: mangrove sering diprediksi sebagai other vegetation).

Selanjutnya, model perlu divalidasi dengan menggunakan metode cross-validation. Metode cross-validation adalah teknik evaluasi model yang digunakan untuk menguji kestabilan dan kemampuan generalisasi suatu algoritma pembelajaran mesin.

```{code-cell} ipython3
# Fungsi untuk melakukan validasi model
def cross_validate_model(X, y, cv_folds=5):
    from sklearn.model_selection import cross_val_score, StratifiedKFold
    skf = StratifiedKFold(n_splits=cv_folds, shuffle=True, random_state=42)
    rf_cv = RandomForestClassifier(
        n_estimators=100,
        max_depth=20,
        min_samples_split=5,
        min_samples_leaf=2,
        random_state=42,
        n_jobs=-1
    )
    cv_scores = cross_val_score(rf_cv, X, y, cv=skf, scoring='accuracy')
    print(f"🟢🟠🔵 Hasil cross-validation ({cv_folds}-fold):")
    print(f"  ▶️ Akurasi rerata: {cv_scores.mean():.3f} (+/- {cv_scores.std() * 2:.3f})")
    print(f"  ▶️ Individual fold scores: {cv_scores}")
    return cv_scores

if X is not None and len(X) > 0:
    cv_scores = cross_validate_model(X, y)
```

Hasil dari cross-validation menunjukkan:
1. Akurasi rerata = 0.999: Model hampir sempurna dalam memprediksi data pada semua lipatan.
2. Standar deviasi ±0.002: Variasi antar lipatan sangat kecil → model stabil, tidak tergantung pada subset data tertentu.
3. Skor tiap fold: Semua fold berada di atas 99.7%, artinya tidak ada lipatan yang gagal.

+++

## 10. Menyimpan hasil
Hasil dari analisa mangrove disimpan di folder `hasil_klas_mangrove`:
1. Array klasifikasi
2. Informasi koordinat
3. Array klasifikasi
4. Laporan klasifikasi
5. Feature importance
6. Peta klasifikasi mangrove

```{code-cell} ipython3
# Fungsi untuk menyimpan hasil
def export_classification_results(output_dir, classified_da, feature_importance_df=None, class_names=None):
    os.makedirs(output_dir, exist_ok=True)
    
    # Metode 1: Menggunakan rioxarray
    try:
        import rioxarray as rxr
        # Cek jika DataArray mempunyai spatial reference
        if hasattr(classified_da, 'rio') and classified_da.rio.crs is not None:
            output_path = os.path.join(output_dir, 'mangrove_classification.tif')
            classified_da.rio.to_raster(output_path)
            print(f"✓ Hasil klasifikasi disimpan di '{output_path}' dengan rioxarray")
            return output_path
        else:
            raise AttributeError("No rio accessor or CRS information")
    except (ImportError, AttributeError) as e:
        # Method 2: Use xarray's to_netcdf (preserves all metadata)
        try:
            output_path = os.path.join(output_dir, 'mangrove_classification.nc')
            classified_da.to_netcdf(output_path)
            # Also save as numpy array with metadata
            np_output_path = os.path.join(output_dir, 'mangrove_classification.npy')
            np.save(np_output_path, classified_da.values)
            # Save coordinate information
            coords_path = os.path.join(output_dir, 'coordinates.json')
            coords_info = {
                'x_coords': classified_da.x.values.tolist(),
                'y_coords': classified_da.y.values.tolist(),
                'shape': list(classified_da.shape),
                'dims': list(classified_da.dims)
            }
            with open(coords_path, 'w') as f:
                json.dump(coords_info, f, indent=2)
            return output_path
        except Exception as e2:
            print(f"NetCDF export gagal: {e2}")
            # Method 3: Basic numpy save as fallback
            try:
                output_path = os.path.join(output_dir, 'mangrove_classification_array.npy')
                np.save(output_path, classified_da.values)
                return output_path
            except Exception as e3:
                print(f"Semua metode ekspor gagal: {e3}")
                return None

# Fungi untuk menghitung klasifikasi
def create_classification_report(output_dir, classified_da, class_names, feature_importance_df=None):
    # Statistik klasifikasi
    unique_values, counts = np.unique(classified_da.values[~np.isnan(classified_da.values)], 
                                     return_counts=True)
    total_pixels = np.sum(counts)
    report = {
        'classification_summary': {
            'total_classified_pixels': int(total_pixels),
            'number_of_classes': len(unique_values),
            'classification_date': datetime.now().isoformat(),
        },
        'class_statistics': {}
    }
    print("\n🟢 Ringkasan klasifikasi:")
    print(f"  ▶️ Jumlah piksel yang diklasifikasi: {total_pixels:,}")
    print(f"  ▶️ Jumlah kelas: {len(unique_values)}")
    print("\n🟢 Distribusi kelas:")
    for i, (class_id, count) in enumerate(zip(unique_values, counts)):
        class_id = int(class_id)
        percentage = (count / total_pixels) * 100
        area_km2 = count * 0.0009  # Assuming 30m pixels (900 m² each)
        if class_names and class_id < len(class_names):
            class_name = class_names[class_id]
        else:
            class_name = f"Class_{class_id}"
        print(f"  ▶️ {class_name}: {count:,} pixels ({percentage:.2f}%) - ~{area_km2:.2f} km²")
        report['class_statistics'][class_name] = {
            'class_id': class_id,
            'pixel_count': int(count),
            'percentage': round(percentage, 2),
            'estimated_area_km2': round(area_km2, 2)
        }
    # Menyimpan laporan dalam JSON
    report_path = os.path.join(output_dir, 'classification_report.json')
    with open(report_path, 'w') as f:
        json.dump(report, f, indent=2)
    # Menyimpan feature importance 
    if feature_importance_df is not None:
        importance_path = os.path.join(output_dir, 'feature_importance.csv')
        feature_importance_df.to_csv(importance_path, index=False)
    return report

# Membuat output directory 
output_dir = "hasil_klas_mangrove"

# Export hasil klasifikasi
if 'classified_da' in locals() and classified_da is not None:
    # Export raster
    export_path = export_classification_results(output_dir, classified_da, 
                                               feature_importance_df if 'feature_importance_df' in locals() else None,
                                               class_names if 'class_names' in locals() else None)
    if export_path:
        # Buat laporan
        report = create_classification_report(output_dir, classified_da, 
                                            class_names if 'class_names' in locals() else None,
                                            feature_importance_df if 'feature_importance_df' in locals() else None)
        plt.figure(figsize=(12, 8))
        # Peta klasifikasi
        # Definisikan warna sesuai urutan class_names
        custom_colors = ['#006400',  # mangrove - hijau tua
                         '#87CEFA',  # water - biru muda
                         '#90EE90',  # other vegetation - hijau muda
                         '#D3D3D3']  # non vegetation - abu-abu muda
        
        cmap_custom = mcolors.ListedColormap(custom_colors)
        
        # Peta klasifikasi dengan warna kustom
        plt.subplot(1, 2, 1)
        im = plt.imshow(classified_da.values,
                        cmap=cmap_custom,
                        vmin=0, vmax=len(class_names)-1,
                        interpolation='nearest')
        plt.title('Klasifikasi Mangrove')
        plt.axis('off')
        
        # Tambahkan colorbar dengan label kelas
        if class_names:
            unique_vals = np.unique(classified_da.values[~np.isnan(classified_da.values)])
            cbar = plt.colorbar(im, ticks=unique_vals, shrink=0.8)
            if len(unique_vals) <= len(class_names):
                cbar.ax.set_yticklabels([class_names[int(val)] for val in unique_vals])        
        # Feature importance (if available)
        if 'feature_importance_df' in locals() and feature_importance_df is not None:
            plt.subplot(1, 2, 2)
            plt.barh(range(len(feature_importance_df)), feature_importance_df['importance'])
            plt.yticks(range(len(feature_importance_df)), feature_importance_df['feature'])
            plt.xlabel('Importance')
            plt.title('Feature Importance')
            plt.gca().invert_yaxis()
        plt.tight_layout()
        # Menyimpan peta
        viz_path = os.path.join(output_dir, 'classification_visualization.png')
        plt.savefig(viz_path, dpi=300, bbox_inches='tight')
        plt.show()
        print(f"📂 Semua data disimpan di folder: {output_dir}")
    else:
        print("Export failed - could not save classification results")
else:
    print("No classification results available to export")
    print("Please run the classification step (step 8) first")
    available_vars = []
    for var_name in ['ds_median', 'training_masks', 'rf_classifier', 'X', 'y']:
        if var_name in locals():
            available_vars.append(var_name)
    if available_vars:
        print(f"Available variables: {available_vars}")
    else:
        print("No analysis variables found - please run previous steps")
```

# Catatan
Notebook ini menyajikan alur lengkap pengolahan citra satelit untuk klasifikasi mangrove, mulai dari perhitungan indeks spektral, pelatihan dan validasi model Random Forest, hingga visualisasi hasil klasifikasi. Evaluasi model dilakukan dengan cross-validation dan confusion matrix, yang menunjukkan performa sangat tinggi serta kestabilan prediksi antar kelas.

Sebagai hasil akhir, notebook menghasilkan peta distribusi mangrove beserta statistik luas tiap kelas, serta menyimpan seluruh keluaran analisis dalam folder khusus. Dengan demikian, workflow ini memberikan gambaran spasial dan kuantitatif yang siap digunakan untuk penelitian ekologi maupun perencanaan wilayah pesisir.

+++

# Info

- Modul ini dijalankan di platform Piksel. Jika ada pertanyaan atau komentar, silahkan email ke piksel@big.go.id
- **Lisensi:** Skrip dalam notebook ini dilisensikan berdasarkan [Apache License, Version 2.0](https://www.apache.org/licenses/LICENSE-2.0). 
Data Piksel dilisensikan berdasarkan lisensi [Creative Commons by Attribution 4.0](https://creativecommons.org/licenses/by/4.0/).

```{code-cell} ipython3

```
