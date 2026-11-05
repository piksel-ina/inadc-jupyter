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

| <h1><b>Pergerakan Titik Api di Karhutla</b></h1> | ![](files/piksel-logo-small.png) |
|:---------|----------:|
- **Lokasi:** Kawasan Bromo, Prov Jawa Timur
- **Metode:** Penggunaan data VIIRS untuk menampilkan hotspot dalam monitoring karhutla
- **Data:** VIIRS, tersedia di `files/viirs_bromo.parquet`

+++

# Pendahuluan
Kebakaran hutan dan lahan (Karhutla) di Indonesia sering terjadi di musim kering. Citra satelit dapat digunakan untuk memonitor pergerakan api dan dampak kebakaran dari suatu area. Modul ini bertujuan untuk menunjukkan penggunaan data VIIRS (Visible Infrared Imaging Radiometer Suite) untuk memetakan asal mula dan pergerakan titik api (hotaspot). Kebakaran di area gunun Bromo, Provinsi Jawa Timur [🔗](https://maps.app.goo.gl/DnYGMXrB6riAFGkp8) yang terjadi di bulan Agustus 2026. 

+++

# Tahapan

Tahapan dalam identifikasi area berpotensi banjir adalah sebagai berikut:
1. Persiapan
2. Download data VIIRS
3. Verifikasi data
4. Animasi hotspot

***

+++

## 1. Persiapan
Tahap persiapan meliputi memuat library dan setting parameter.

### A. Memuat Library

```{code-cell} ipython3
import os, time, requests, folium
import pandas as pd
import geopandas as gpd
from pathlib import Path
from shapely.geometry import Point
import geopandas as gpd
import matplotlib.pyplot as plt
from branca.element import Element
```

### B. Konfigurasi parameter
Berikut adalah parameter yang digunakan untuk konfigurasi modul.

```{code-cell} ipython3
# AOI
WEST = 112.75; SOUTH = -8.10; EAST = 113.05; NORTH = -7.80
AREA = f"{WEST},{SOUTH},{EAST},{NORTH}"

# Periode waktu
START_DATE = pd.Timestamp("2026-08-01")
END_DATE = pd.Timestamp("2026-08-17")

# Sensor yang digunakan
SOURCES = [
    "VIIRS_NOAA20_NRT",
    "VIIRS_NOAA21_NRT",
]

# FOlder penyimpanan data
OUTPUT_DIR = Path("files")
OUTPUT_DIR.mkdir(parents=True, exist_ok=True)
```

## 2. Download data VIIRS
Data VIIRS (Visible Infrared Imaging Radiometer Suite) dalam NASA FIRMS (Fire Information for Resource Management System) perlu diunduh untuk mendapatkan data hotspot kebakaran. Satelit yang digunakan adalah NOAA-20 dan NOAA-21. Untuk download data perlu mendapatkan MAP_KEY dari situs https://firms.modaps.eosdis.nasa.gov/api/map_key 

Data yang di unduh adalah:
- Area Bromo
- Tanggal 1-17 Agustus 2026

Data yang dihasilkan dalam folder data berisi:
- CSV
- GeoPackage
- GeoParquet
- GeoJSON

<span style="color:red">Skrip berikut memerlukan MAP_KEY. Karena data sudah tersedia di folder `files`, maka skrip ini tidak perlu dijalankan.</span>

```{code-cell} ipython3
---
jupyter:
  source_hidden: true
---
# 1. INISIALISASI
os.environ["FIRMS_MAP_KEY"] = "xxx"  # Gunakan MAP_KEY anda 
FIRMS_MAP_KEY = os.getenv("FIRMS_MAP_KEY")

if not FIRMS_MAP_KEY:
    raise ValueError(
        "FIRMS_MAP_KEY belum tersedia. "
        "Set environment variable FIRMS_MAP_KEY terlebih dahulu."
    )

# 2. FIRMS API FUNCTION
def download_firms(
    map_key,
    source,
    area,
    start_date,
    end_date,
):
    """
    Download FIRMS Area API data in chunks of max 5 days.
    FIRMS API:
    /api/area/csv/[MAP_KEY]/[SOURCE]/[AREA]/[DAY_RANGE]/[DATE]
    """
    base_url = (
        "https://firms.modaps.eosdis.nasa.gov/api/area/csv"
    )
    all_data = []
    current_date = pd.Timestamp(start_date)
    while current_date <= end_date:
        # FIRMS maximum DAY_RANGE = 5
        remaining_days = (
            end_date - current_date
        ).days + 1
        day_range = min(5, remaining_days)
        date_string = current_date.strftime("%Y-%m-%d")
        url = (
            f"{base_url}/"
            f"{map_key}/"
            f"{source}/"
            f"{area}/"
            f"{day_range}/"
            f"{date_string}"
        )
        print()
        print("=" * 70)
        print(f"Source      : {source}")
        print(f"Start date  : {date_string}")
        print(f"Day range   : {day_range}")
        print(f"URL         : {url}")
        print("=" * 70)
        try:
            response = requests.get(
                url,
                timeout=120,
            )
            response.raise_for_status()
            # Check whether response is CSV
            content_type = response.headers.get(
                "Content-Type", ""
            )
            print(
                f"HTTP status : {response.status_code}"
            )
            # Read CSV from response
            from io import StringIO
            df = pd.read_csv(
                StringIO(response.text)
            )
            print(
                f"Records     : {len(df):,}"
            )
            if len(df) > 0:
                all_data.append(df)
        except Exception as e:
            print(
                f"ERROR downloading {source} "
                f"{date_string}: {e}"
            )
        # Move to next chunk
        current_date += pd.Timedelta(
            days=day_range
        )
        # Small delay to avoid unnecessary API load
        time.sleep(1)
    # Combine chunks
    if not all_data:
        print(
            f"No data returned for {source}"
        )
        return pd.DataFrame()
    result = pd.concat(
        all_data,
        ignore_index=True
    )
    # Remove duplicate detections
    result = result.drop_duplicates()
    return result

# 3. DOWNLOAD NOAA-20 + NOAA-21

all_viirs = []
for source in SOURCES:
    df = download_firms(
        map_key=FIRMS_MAP_KEY,
        source=source,
        area=AREA,
        start_date=START_DATE,
        end_date=END_DATE,
    )
    if not df.empty:
        # Add explicit source field
        df["firms_source"] = source
        all_viirs.append(df)

# 4. COMBINE DATA
if not all_viirs:
    raise RuntimeError(
        "Tidak ada data VIIRS yang berhasil diperoleh."
    )
viirs = pd.concat(
    all_viirs,
    ignore_index=True
)
viirs = viirs.drop_duplicates()
print()
print("=" * 70)
print("TOTAL VIIRS RECORDS")
print("=" * 70)
print(
    f"Records: {len(viirs):,}"
)

# 5. CLEAN DATA TYPES

viirs["acq_date"] = pd.to_datetime(
    viirs["acq_date"],
    errors="coerce"
)
# Acquisition time
def parse_acq_time(value):
    if pd.isna(value):
        return None
    # FIRMS acq_time normally HHMM
    value = str(int(float(value))).zfill(4)
    return value
viirs["acq_time_str"] = (
    viirs["acq_time"]
    .apply(parse_acq_time)
)
# 6. CREATE UTC DATETIME
viirs["acq_datetime_utc"] = pd.to_datetime(
    viirs["acq_date"].dt.strftime("%Y-%m-%d")
    + " "
    + viirs["acq_time_str"].fillna("0000"),
    format="%Y-%m-%d %H%M",
    errors="coerce",
)
# Explicitly set UTC
viirs["acq_datetime_utc"] = (
    viirs["acq_datetime_utc"]
    .dt.tz_localize("UTC")
)

# 7. CONVERT UTC -> WIB

viirs["acq_datetime_wib"] = (
    viirs["acq_datetime_utc"]
    .dt.tz_convert("Asia/Jakarta")
)

# 8. CREATE QUALITY / FILTER FIELDS
# Convert numeric columns
numeric_columns = [
    "latitude",
    "longitude",
    "bright_ti4",
    "bright_ti5",
    "scan",
    "track",
    "frp",
]
for col in numeric_columns:
    if col in viirs.columns:
        viirs[col] = pd.to_numeric(
            viirs[col],
            errors="coerce"
        )
# Confidence
if "confidence" in viirs.columns:
    viirs["confidence"] = (
        viirs["confidence"]
        .astype(str)
        .str.lower()
    )

# 9. OPTIONAL QUALITY FILTER
viirs["is_high_confidence"] = (
    viirs["confidence"] == "h"
)
viirs["is_nominal_or_high"] = (
    viirs["confidence"].isin(
        ["n", "h"]
    )
)

# 10. CREATE GEODATAFRAME
geometry = [
    Point(x, y)
    for x, y in zip(
        viirs["longitude"],
        viirs["latitude"]
    )
]
gdf = gpd.GeoDataFrame(
    viirs,
    geometry=geometry,
    crs="EPSG:4326",
)

# 11. SORT DATA
gdf = gdf.sort_values(
    "acq_datetime_utc"
).reset_index(drop=True)


# 12. CREATE UNIQUE FIRE ID
gdf["fire_id"] = (
    "VIIRS_"
    + gdf.index.astype(str).str.zfill(8)
)

# 13. SAVE RAW CSV
csv_file = (
    OUTPUT_DIR
    / "viirs_bromo_raw.csv"
)

gdf.drop(
    columns="geometry"
).to_csv(
    csv_file,
    index=False
)
print()
print(f"Saved CSV: {csv_file}")

# 14. SAVE GEOPACKAGE
gpkg_file = (
    OUTPUT_DIR
    / "viirs_bromo.gpkg"
)
gdf.to_file(
    gpkg_file,
    layer="viirs_active_fire",
    driver="GPKG"
)
print(
    f"Saved GeoPackage: {gpkg_file}"
)

# 15. SAVE GEOPARQUET

parquet_file = (
    OUTPUT_DIR
    / "viirs_bromo.parquet"
)
gdf.to_parquet(
    parquet_file,
    index=False
)
print(
    f"Saved GeoParquet: {parquet_file}"
)

# 16. SAVE GEOJSON

geojson_file = (
    OUTPUT_DIR
    / "viirs_bromo.geojson"
)
gdf.to_file(
    geojson_file,
    driver="GeoJSON"
)
print(
    f"Saved GeoJSON: {geojson_file}"
)

# 17. SUMMARY

print()
print("=" * 70)
print("VIIRS SUMMARY")
print("=" * 70)
print(
    "\nRecords by satellite:"
)
print(
    gdf["satellite"]
    .value_counts()
)
print(
    "\nRecords by date:"
)
print(
    gdf["acq_date"]
    .dt.strftime("%Y-%m-%d")
    .value_counts()
    .sort_index()
)
print(
    "\nRecords by confidence:"
)
print(
    gdf["confidence"]
    .value_counts()
)
print(
    "\nFRP statistics:"
)
print(
    gdf["frp"]
    .describe()
)

# 18. DISPLAY FIRST RECORDS

display_columns = [
    "fire_id",
    "acq_datetime_utc",
    "acq_datetime_wib",
    "latitude",
    "longitude",
    "satellite",
    "confidence",
    "frp",
    "geometry",
]

display_columns = [
    c for c in display_columns
    if c in gdf.columns
]
print()
print(
    gdf[display_columns].head(20)
)
print()
print("=" * 70)
print("DONE")
print("=" * 70)
```

## 3. Verifikasi data
Untuk memastikan kualitas data yang diunduh maka perlu dilakukan kontrol kualitas:
1. Plot tanggal
2. Plot FRP
3. Periode kebakaran
4. Awal kebakaran

+++

### A. Plot tanggal hotspot

```{code-cell} ipython3
fig, ax = plt.subplots(figsize=(10, 10))
fires.plot(
    ax=ax,
    column=fires["acq_datetime_utc"].dt.date,
    categorical=True,
    legend=True,
    markersize=35,
)
ax.set_title("VIIRS Hotspot - Berdasarkan Tanggal")
ax.set_xlabel("Bujur")
ax.set_ylabel("Lintang")
plt.show()
```

### B. Plot FRP hotspot
Fire Radiative Power (FRP) adalah ukuran seberapa besar energi panas yang dipancarkan oleh api pada saat satelit merekamnya. FRP menunjukkan “seberapa kuat/intens” api yang terdeteksi, bukan luas area kebakarannya. FRP biasanya dinyatakan dalam Megawatt (MW). Contoh interpretasi sederhana:

| FRP       | Gambaran umum                                   |
| --------- | ----------------------------------------------- |
| 1–10 MW   | Api relatif kecil / intensitas rendah           |
| 10–50 MW  | Api cukup aktif                                 |
| 50–100 MW | Api aktif dan cukup kuat                        |
| >100 MW   | Api sangat intens / kemungkinan kebakaran besar |

```{code-cell} ipython3
fig, ax = plt.subplots(figsize=(10, 10))
fires.plot(
    ax=ax,
    column="frp",
    cmap="hot_r",
    legend=True,
    markersize=40,
)
ax.set_title("VIIRS Hotspot - Berdasarkan FRP")
ax.set_xlabel("Bujur")
ax.set_ylabel("Lintang")
plt.show()
```

### C. Periode kebakaran
Dalam bentuk tabel.

```{code-cell} ipython3
daily = (
    fires
    .groupby(
        fires["acq_datetime_wib"].dt.date
    )
    .agg(
        fire_count=("fire_id", "count"),
        max_frp=("frp", "max"),
        mean_frp=("frp", "mean"),
        total_frp=("frp", "sum"),
    )
    .reset_index()
)
daily
```

Dalam bentuk bar graph.

```{code-cell} ipython3
ax = daily.plot(
    x="acq_datetime_wib",
    y="fire_count",
    kind="bar",
    figsize=(12, 5),
    legend=False,
)

ax.set_ylabel("Deteksi api")
ax.set_xlabel("Tanggal")
ax.set_title(
    "Periode Kebakaran"
)
plt.show()
```

### D. Awal kebakaran
DEM ditampilkan dalam bentuk peta dan visualisasi 3 dimensi

```{code-cell} ipython3
first_detection = (
    fires
    .sort_values("acq_datetime_utc")
    .iloc[0]
)

first_detection[
    [
        "fire_id",
        "acq_datetime_utc",
        "acq_datetime_wib",
        "latitude",
        "longitude",
        "satellite",
        "confidence",
        "frp",
    ]
]
```

## 4. Animasi hotspot
Animasi hotspot digunakan untuk mendeteksi posisi awal dan arah pergerakan api. Hasil dari tahap ini berupa file `files/peta_VIIRS.html`

```{code-cell} ipython3
# 1. CONFIGURATION
INPUT_FILE = (
    "files/"
    "viirs_bromo.parquet"
)
OUTPUT_FILE = (
    "files/"
    "peta_hotspot.html"
)

# 2. LOAD VIIRS DATA
fires = gpd.read_parquet(
    INPUT_FILE
)
print(
    f"Total VIIRS records: {len(fires)}"
)

# 3. CRS
if fires.crs is None:
    fires = fires.set_crs(
        "EPSG:4326"
    )
elif fires.crs.to_epsg() != 4326:
    fires = fires.to_crs(
        "EPSG:4326"
    )

# 4. PREPARE TIME
fires["acq_datetime_wib"] = pd.to_datetime(
    fires["acq_datetime_wib"]
)
fires["date_wib"] = (
    fires["acq_datetime_wib"]
    .dt.strftime("%Y-%m-%d")
)

fires["time_wib"] = (
    fires["acq_datetime_wib"]
    .dt.strftime("%H:%M")
)

# 5. SORT
fires = fires.sort_values(
    "acq_datetime_wib"
).reset_index(
    drop=True
)

# 6. MAP
center_lat = (
    SOUTH + NORTH
) / 2
center_lon = (
    WEST + EAST
) / 2
m = folium.Map(
    location=[
        center_lat,
        center_lon
    ],
    zoom_start=10,
    tiles=None,
    control_scale=True,
)

# 7. PREPARE DATES FOR SLIDER
# Dates used by slider
dates = sorted(
    fires["date_wib"]
    .unique()
)
dates_js = str(dates).replace(
    "'", '"'
)

# 8. DATE SLIDER PANEL
slider_html = f"""
<div id="date-slider-control"
style="
    position: fixed !important;
    top: 80px !important;
    right: 10px !important;
    width: 50% !important;
    min-width: 200px;
    max-width: 240px;
    z-index: 99999 !important;
    display: block !important;
    visibility: visible !important;
    opacity: 1 !important;
    background: rgba(255,255,255,0.95);
    padding: 15px 20px;
    border-radius: 8px;
    box-shadow:
        0 2px 10px rgba(0,0,0,0.35);
    box-sizing: border-box;
    font-family: Arial, sans-serif;
">
    <!-- TITLE -->
    <div style="
        font-size: 16px;
        font-weight: bold;
        text-align: center;
        margin-bottom: 8px;
    ">
    </div>
    <!-- SELECTED DATE -->
    <div style="
        text-align: center;
        font-size: 14px;
        margin-bottom: 10px;
    ">
        Tanggal:
        <span id="selected-date">
            {dates[0]}
        </span>
    </div>

    <!-- SLIDER -->
    <input
        type="range"
        id="date-slider"
        min="0"
        max="{len(dates)-1}"
        value="0"
        step="1"
        style="
            width: 100%;
            display: block;
            cursor: pointer;
        "
    >

    <!-- DATE RANGE -->
    <div style="
        display: flex;
        justify-content: space-between;
        font-size: 11px;
        margin-top: 5px;
    ">
        <span>{dates[0]}</span>
        <span>{dates[-1]}</span>
    </div>

    <!-- CUMULATIVE -->
    <div style="
        margin-top: 10px;
        text-align: center;
        font-size: 14px;
    ">
        <label>
            <input
                type="checkbox"
                id="cumulative"
                checked
            >
            Cumulative detections
        </label>
    </div>

    <!-- PLAY / STOP -->
    <div style="
        margin-top: 10px;
        text-align: center;
    ">
        <button
            id="play-button"
            style="
                padding: 6px 18px;
                margin-right: 5px;
                cursor: pointer;
                font-size: 14px;
            "
        >
            ▶ Play
        </button>
        <button
            id="stop-button"
            style="
                padding: 6px 18px;
                cursor: pointer;
                font-size: 14px;
            "
        >
            ■ Stop
        </button>
    </div>
</div>
"""
m.get_root().html.add_child(
    Element(slider_html)
)

# 9. LAYER CONTROL POSITIONING

m.get_root().html.add_child(
    Element("""
    <style>
    .leaflet-top.leaflet-right {
        top: 260px !important;
    }
    </style>
    """)
)

# 10. ESRI WORLD IMAGERY

folium.TileLayer(
    tiles=(
        "https://server.arcgisonline.com/"
        "ArcGIS/rest/services/"
        "World_Imagery/"
        "MapServer/tile/{z}/{y}/{x}"
    ),
    attr=(
        "Esri, Maxar, Earthstar Geographics, "
        "and the GIS User Community"
    ),
    name="Esri World Imagery",
    overlay=False,
    control=True,
    show=True,
).add_to(m)

# 11. ESRI STREET MAP

folium.TileLayer(
    tiles=(
        "https://server.arcgisonline.com/"
        "ArcGIS/rest/services/"
        "World_Street_Map/"
        "MapServer/tile/{z}/{y}/{x}"
    ),
    attr="Esri",
    name="Esri World Street Map",
    overlay=False,
    control=True,
    show=False,
).add_to(m)

# 12. CREATE GEOJSON FEATURES

features = []
for _, row in fires.iterrows():
    lat = row.geometry.y
    lon = row.geometry.x
    # Marker size based on FRP
    frp = float(row["frp"])
    radius = max(
        4,
        min(
            15,
            3 + frp * 0.35
        )
    )
    # Popup
    popup_html = f"""
    <div style="
        font-family: Arial;
        font-size: 13px;
    ">
    <b>VIIRS Active Fire</b>
    <hr>
    <b>Fire ID:</b>
    {row["fire_id"]}<br>
    <b>Date WIB:</b>
    {row["date_wib"]}<br>
    <b>Time WIB:</b>
    {row["time_wib"]}<br>
    <b>Satellite:</b>
    {row["satellite"]}<br>
    <b>Confidence:</b>
    {row["confidence"]}<br>
    <b>FRP:</b>
    {frp:.2f} MW<br>
    <b>Latitude:</b>
    {lat:.5f}<br>
    <b>Longitude:</b>
    {lon:.5f}<br>
    </div>
    """

    # GeoJSON feature
    feature = {
        "type": "Feature",
        "geometry": {
            "type": "Point",
            "coordinates": [
                lon,
                lat
            ],
        },

        "properties": {
            "fire_id":
                str(row["fire_id"]),
            "date":
                row["date_wib"],
            "time":
                row["time_wib"],
            "datetime":
                row[
                    "acq_datetime_wib"
                ].isoformat(),
            "satellite":
                str(row["satellite"]),
            "confidence":
                str(row["confidence"]),
            "frp":
                frp,
            "radius":
                radius,
            "popup":
                popup_html,
        },
    }
    features.append(
        feature
    )

# 13. GEOJSON

geojson_data = {
    "type": "FeatureCollection",
    "features": features,
}

# 14. ADD GEOJSON TO MAP
geojson_layer = folium.GeoJson(
    geojson_data,
    name="VIIRS Active Fire",
    style_function=lambda feature: {
        "color": "red",
        "weight": 1,
        "fillColor": "orange",
        "fillOpacity": 0.8,
    },
    marker=folium.CircleMarker(
        radius=5,
        fill=True,
        fillOpacity=0.85,
    ),
)

# 15. JAVASCRIPT
map_name = m.get_name()
javascript = f"""
<script>
document.addEventListener("DOMContentLoaded", function() {{

var fireData =
{geojson_data};
var dates =
{dates_js};
var currentLayer = null;
var animationTimer = null;

// Create markers

function drawFires(selectedIndex)
{{
    var cumulative =
        document.getElementById(
            "cumulative"
        ).checked;
    var selectedDate =
        dates[selectedIndex];
    // Remove previous markers
    if (currentLayer !== null)
    {{
        {map_name}.removeLayer(
            currentLayer
        );
    }}
    var features = [];
    for (
        var i = 0;
        i < fireData.features.length;
        i++
    )
    {{
        var feature =
            fireData.features[i];
        var featureDate =
            feature.properties.date;
        var include = false;
        if (cumulative)
        {{

            if (
                featureDate <=
                selectedDate
            )
            {{
                include = true;
            }}

        }}
        else
        {{

            if (
                featureDate ===
                selectedDate
            )
            {{
                include = true;
            }}

        }}
        if (include)
        {{
            features.push(
                feature
            );
        }}
    }}
    currentLayer =
        L.geoJSON(
            {{
                type:
                    "FeatureCollection",
                features:
                    features
            }},
            {{
                pointToLayer:
                    function(
                        feature,
                        latlng
                    )
                    {{
                        var frp =
                            feature
                            .properties
                            .frp;

                        var radius =
                            Math.max(
                                4,
                                Math.min(
                                    15,
                                    3 +
                                    frp * 0.35
                                )
                            );


                        var marker =
                            L.circleMarker(
                                latlng,
                                {{

                                    radius:
                                        radius,

                                    color:
                                        "red",

                                    weight:
                                        1,

                                    fillColor:
                                        "orange",

                                    fillOpacity:
                                        0.85

                                }}
                            );


                        marker.bindPopup(
                            feature
                            .properties
                            .popup
                        );
                        marker.bindTooltip(
                            feature
                            .properties
                            .date
                            +
                            " "
                            +
                            feature
                            .properties
                            .time
                            +
                            " WIB | "
                            +
                            feature
                            .properties
                            .satellite
                            +
                            " | FRP "
                            +
                            frp.toFixed(2)
                            +
                            " MW"
                        );
                        return marker;
                    }}
            }}
        ).addTo(
            {map_name}
        );
    document.getElementById(
        "selected-date"
    ).innerHTML =
        selectedDate;
}}

// Slider
document.getElementById(
    "date-slider"
).addEventListener(
    "input",
    function()
    {{
        var index =
            parseInt(
                this.value
            );
        drawFires(
            index
        );
    }}
);

// Cumulative checkbox
document.getElementById(
    "cumulative"
).addEventListener(
    "change",
    function()
    {{
        var index =
            parseInt(
                document
                .getElementById(
                    "date-slider"
                )
                .value
            );
        drawFires(
            index
        );
    }}
);

// PLAY
function playAnimation()
{{
    stopAnimation();
    var slider =
        document.getElementById(
            "date-slider"
        );
    animationTimer =
        setInterval(
            function()
            {{
                var value =
                    parseInt(
                        slider.value
                    );
                if (
                    value >=
                    dates.length - 1
                )
                {{
                    value = 0;
                }}
                else
                {{
                    value++;
                }}
                slider.value =
                    value;
                drawFires(
                    value
                );
            }},
            1000
        );
}}

// STOP
function stopAnimation()
{{
    if (
        animationTimer !== null
    )
    {{
        clearInterval(
            animationTimer
        );
        animationTimer =
            null;
    }}
}}

// BUTTON EVENTS
document.getElementById(
    "play-button"
).addEventListener(
    "click",
    playAnimation
);
document.getElementById(
    "stop-button"
).addEventListener(
    "click",
    stopAnimation
);

// Initial display
drawFires(0);
}});
</script>
"""
m.get_root().html.add_child(
    Element(
        javascript
    )
)

# 16. TITLE
title_html = """
<div style="
position: fixed;
top: 10px;
right: 10px;
z-index: 9999;
background-color:
rgba(255,255,255,0.92);
padding: 10px 18px;
border-radius: 5px;
font-family: Arial;
font-size: 16px;
font-weight: bold;
box-shadow:
0 1px 5px rgba(0,0,0,0.3);
">
VIIRS Hotspot
<br>
<span style="
font-size:12px;
font-weight:normal;
">
2-18 Agt 2026 |
NOAA-20 + NOAA-21
</span>
</div>
"""

m.get_root().html.add_child(
    Element(
        title_html
    )
)

# 17. LAYER CONTROL
folium.LayerControl(
    collapsed=False,
    position="topright",
).add_to(m)

# 18. FIT TO AOI
m.fit_bounds(
    [
        [SOUTH, WEST],
        [NORTH, EAST],
    ]
)

# 19. SAVE
output_path = Path(
    OUTPUT_FILE
)
output_path.parent.mkdir(
    parents=True,
    exist_ok=True
)
m.save(
    output_path
)

# 20. SUMMARY
print(
    f"Output peta: {output_path}"
)
```

# Catatan
Pengolahan data VIIRS telah memeberikan gambaran awal mula dan sebaran titik api pada kebakaran di kawasan Bromo. Animasi hotspot lebih bermanfaat untuk memvisualisasi pergerakan titik api. 

+++

# Info

- Modul ini dijalankan di platform Piksel. Jika ada pertanyaan atau komentar, silahkan email ke piksel@big.go.id
- **Lisensi:** Skrip dalam notebook ini dilisensikan berdasarkan [Apache License, Version 2.0](https://www.apache.org/licenses/LICENSE-2.0). 
Data Piksel dilisensikan berdasarkan lisensi [Creative Commons by Attribution 4.0](https://creativecommons.org/licenses/by/4.0/).
