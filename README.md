# openmeteo-sh

A fast, lightweight Bash CLI for the entire [Open-Meteo](https://open-meteo.com) API suite ([available APIs](https://open-meteo.com/en/features#available_apis)).

Get weather forecasts, historical data, air quality, marine conditions, flood alerts, elevation, satellite radiation, and more — right from your terminal. No account required.

```
$ openmeteo weather --current --city=London
🌍 London, United Kingdom · 51.51°N, 0.13°W
   Europe/London (GMT+0) · Elevation: 25m

⏱  Now — 2026-02-09T18:45

   🌡  7.1°C (feels like 3.9°C)
   💧 83% humidity
   ☁️  Overcast (99% clouds)
   💨 13.3 km/h ESE, gusts 32.4 km/h
   🌙 Night
```

---

## Features

- **10 API subcommands** covering every Open-Meteo endpoint
- **Four output formats** — human-friendly (default), porcelain (for scripts), LLM (compact TSV for AI agents), raw JSON
- **City name resolution** — use `--city=London` instead of lat/lon
- **Verbose input validation** — helpful error messages before any API call
- **Commercial API key support** — via env var or `--api-key` flag
- **Zero-bloat** — only `bash`, `curl`, and `jq`; no Python, no Node, no compiled binaries
- **`--forecast-since=N`** — skip to day N of the forecast without date math
- **Built-in variable reference** — `openmeteo <cmd> help --daily-params` lists every variable
- **Colored, emoji-rich output** — grouped by day, auto-disabled when piped

---

## Table of Contents

- [Installation](#installation)
- [Quick Start](#quick-start)
- [Commands](#commands)
  - [weather](#weather)
  - [geo](#geo)
  - [history](#history)
  - [ensemble](#ensemble)
  - [climate](#climate)
  - [marine](#marine)
  - [air-quality](#air-quality)
  - [flood](#flood)
  - [elevation](#elevation)
  - [satellite](#satellite)
- [Forecast Window: `--forecast-since`](#forecast-window---forecast-since)
- [Detailed Help](#detailed-help)
- [Output Formats](#output-formats)
- [API Key / Commercial Access](#api-key--commercial-access)
- [Examples Cookbook](#examples-cookbook)
- [Known Quirks & Limitations](#known-quirks--limitations)
- [Troubleshooting](#troubleshooting)
- [Contributing](#contributing)
- [Submitting Issues](#submitting-issues)
- [License](#license)

---

## Installation

### Prerequisites

| Dependency | Required | Usually pre-installed? |
|------------|----------|------------------------|
| bash 3.2+  | Yes      | Yes (macOS / Linux)    |
| curl       | Yes      | Yes (macOS / Linux)    |
| jq         | Yes      | **No** — install it    |

Install `jq` if you don't have it:

```bash
# macOS
brew install jq

# Debian / Ubuntu
sudo apt-get install jq

# Fedora
sudo dnf install jq

# Arch
sudo pacman -S jq
```

### Homebrew (macOS & Linux)

```bash
brew tap lstpsche/tap
brew install openmeteo-sh
```

This also installs bash/zsh tab completions automatically. The CLI command is `openmeteo`.

### Debian / Ubuntu (APT repository)

```bash
# Add the repository
echo "deb [trusted=yes] https://lstpsche.github.io/apt-repo stable main" \
  | sudo tee /etc/apt/sources.list.d/openmeteo-sh.list

# Install
sudo apt update
sudo apt install openmeteo-sh
```

Or download a `.deb` directly from the [latest release](https://github.com/lstpsche/openmeteo-sh/releases/latest):

```bash
curl -LO https://github.com/lstpsche/openmeteo-sh/releases/download/1.3.0/openmeteo-sh_1.3.0-1_all.deb
sudo dpkg -i openmeteo-sh_1.3.0-1_all.deb
sudo apt-get install -f   # install dependencies (jq, curl)
```

### From source

```bash
git clone https://github.com/lstpsche/openmeteo-sh.git
cd openmeteo-sh

# Option A: use the Makefile (recommended — installs completions too)
sudo make install

# Option B: symlink into your PATH (for development)
chmod +x openmeteo
ln -s "$(pwd)/openmeteo" /usr/local/bin/openmeteo
```

To uninstall a Makefile installation: `sudo make uninstall`

### Updating

```bash
# Homebrew
brew update && brew upgrade openmeteo-sh

# Debian / Ubuntu (APT repo)
sudo apt update && sudo apt upgrade openmeteo-sh

# Debian / Ubuntu (manual .deb)
curl -LO https://github.com/lstpsche/openmeteo-sh/releases/download/<VERSION>/openmeteo-sh_<VERSION>-1_all.deb
sudo dpkg -i openmeteo-sh_<VERSION>-1_all.deb

# From source
cd openmeteo-sh && git pull && sudo make install
```

### Uninstalling

```bash
# Homebrew
brew uninstall openmeteo-sh && brew untap lstpsche/tap

# Debian / Ubuntu
sudo apt remove openmeteo-sh

# From source
cd openmeteo-sh && sudo make uninstall
```

---

## Quick Start

```bash
# Current weather for a city
openmeteo weather --current --city=London

# 3-day forecast by coordinates
openmeteo weather --forecast-days=3 --lat=52.52 --lon=13.41

# Search for a location
openmeteo geo --search=Berlin

# Historical weather
openmeteo history --city=Paris --start-date=2024-01-01 --end-date=2024-01-31

# Elevation of a point
openmeteo elevation --lat=47.37 --lon=8.55

# Air quality
openmeteo air-quality --current --city=Tokyo

# Machine-readable output (for scripts/agents)
openmeteo weather --current --city=London --porcelain

# Skip to day 3 of a 7-day forecast
openmeteo weather --forecast-days=7 --forecast-since=3 --city=London

# Compact output for AI agents / LLMs (minimal tokens)
openmeteo weather --current --forecast-days=2 --city=London --llm

# List available daily variables for the weather command
openmeteo weather help --daily-params

# Raw JSON (for piping to jq)
openmeteo weather --current --city=London --raw | jq '.current.temperature_2m'
```

Run `openmeteo --help` for the full command list, or `openmeteo <command> --help` for command-specific help.

---

## Commands

### Global Options

These flags work with every subcommand:

| Flag            | Description                                                 |
|-----------------|-------------------------------------------------------------|
| `--api-key=KEY` | Open-Meteo commercial API key (overrides `OPENMETEO_API_KEY`) |
| `--porcelain`   | Machine-parseable `key=value` output                        |
| `--llm`         | Compact TSV output optimized for AI agents (minimal tokens) |
| `--raw`         | Raw JSON from the API                                       |
| `--verbose`     | Show resolved locations and full request URLs               |
| `--help`        | Show help for the command                                   |
| `--version`     | Show version                                                |

All commands also accept `help` as a positional argument:

```bash
openmeteo weather help                              # same as --help
openmeteo weather help --daily-params               # list available daily variables with descriptions
openmeteo weather help --hourly-params              # list available hourly variables
openmeteo weather help --current-params             # list available current variables
openmeteo weather help --daily-params --porcelain   # machine-parseable name=description
openmeteo weather help --daily-params --llm         # compact TSV for AI agents
```

### weather

Weather forecast — up to 16 days of hourly and daily data, plus current conditions.

```bash
openmeteo weather --current --city=London
openmeteo weather --forecast-days=3 --lat=52.52 --lon=13.41
openmeteo weather --current --forecast-days=2 --city=Vienna \
  --hourly-params=precipitation,precipitation_probability,weather_code

# Forecast starting from day 3 (skip today and tomorrow)
openmeteo weather --forecast-days=7 --forecast-since=3 --city=London

# List all available daily variables
openmeteo weather help --daily-params
```

**Key options:**

| Option                     | Description                          | Default                |
|----------------------------|--------------------------------------|------------------------|
| `--lat=NUM` / `--lon=NUM`  | Coordinates (WGS84)                  | —                      |
| `--city=NAME`              | City name (auto-resolved)            | —                      |
| `--country=CODE`           | Narrow city search (e.g. `GB`)       | —                      |
| `--current`                | Include current conditions           | off                    |
| `--forecast-days=N`        | Days of forecast (0–16)              | 7                      |
| `--forecast-since=N`       | Start from day N (1=today)           | —                      |
| `--past-days=N`            | Include past days (0–92)             | 0                      |
| `--hourly-params=LIST`     | Hourly variables (comma-separated)   | sensible defaults      |
| `--daily-params=LIST`      | Daily variables (comma-separated)    | sensible defaults      |
| `--current-params=LIST`    | Current variables (comma-separated)  | sensible defaults      |
| `--temperature-unit=UNIT`  | `celsius` or `fahrenheit`            | celsius                |
| `--wind-speed-unit=UNIT`   | `kmh`, `ms`, `mph`, `kn`            | kmh                    |
| `--precipitation-unit=UNIT`| `mm` or `inch`                       | mm                     |
| `--timezone=TZ`            | IANA timezone or `auto`              | auto                   |
| `--model=MODEL`            | Weather model                        | best_match             |

> **Tip:** Run `openmeteo weather help --hourly-params` or `--daily-params` to see the full list of available variables with descriptions.

### geo

Geocoding — search locations by name or postal code.

```bash
openmeteo geo --search=London
openmeteo geo --search=Berlin --count=3
openmeteo geo --search=Paris --country=FR --language=fr
```

| Option            | Description                              | Default |
|-------------------|------------------------------------------|---------|
| `--search=NAME`   | Location name or postal code (required)  | —       |
| `--count=N`       | Number of results (1–100)                | 5       |
| `--language=LANG` | Language for results                     | en      |
| `--country=CODE`  | ISO 3166-1 alpha-2 country filter        | —       |

### history

Historical weather — hourly/daily data from 1940 to present (ERA5, CERRA, ECMWF IFS reanalysis).

```bash
openmeteo history --city=Paris --start-date=2024-01-01 --end-date=2024-01-07
openmeteo history --city=Tokyo --start-date=2023-06-01 --end-date=2023-06-30 \
  --daily-params=temperature_2m_max,temperature_2m_min,precipitation_sum
```

| Option             | Description                       | Default    |
|--------------------|-----------------------------------|------------|
| `--start-date=DATE`| Start date, YYYY-MM-DD (required) | —          |
| `--end-date=DATE`  | End date, YYYY-MM-DD (required)   | —          |
| `--hourly-params`  | Hourly variables                  | defaults   |
| `--daily-params`   | Daily variables                   | —          |
| `--model=MODEL`    | `best_match`, `era5`, `era5_land`, `era5_seamless`, `ecmwf_ifs`, `cerra`, etc. | best_match |

### ensemble

Ensemble model forecasts — probabilistic forecasts from multiple ensemble members, up to 35 days.

```bash
openmeteo ensemble --city=Berlin --models=icon_seamless
openmeteo ensemble --lat=52.52 --lon=13.41 --models=gfs_seamless \
  --hourly-params=temperature_2m,precipitation --forecast-days=10
```

| Option               | Description                                 | Default |
|----------------------|---------------------------------------------|---------|
| `--models=LIST`      | Ensemble model(s) — **required**            | —       |
| `--forecast-days=N`  | Days of forecast (0–35)                     | 7       |
| `--forecast-since=N` | Start from day N (1=today)                  | —       |
| `--hourly-params`    | Hourly variables                            | defaults|
| `--daily-params`     | Daily variables                             | —       |

**Available models:** `icon_seamless`, `icon_global`, `icon_eu`, `icon_d2`, `gfs_seamless`, `gfs025`, `gfs05`, `gfs_graphcast025`, `ecmwf_ifs025`, `ecmwf_aifs025`, `gem_global`, `bom_access_global_ensemble`, `ukmo_seamless`, `ukmo_global_ensemble_20km`, `ukmo_uk_ensemble_2km`, `meteoswiss_icon_ch1`, `meteoswiss_icon_ch2`

### climate

Climate change projections — IPCC CMIP6 daily data from 1950 to 2050, downscaled to 10 km.

```bash
openmeteo climate --city=Berlin --models=MRI_AGCM3_2_S \
  --start-date=2020-01-01 --end-date=2030-12-31
openmeteo climate --city=Tokyo --models=EC_Earth3P_HR \
  --start-date=1950-01-01 --end-date=2050-01-01 \
  --daily-params=soil_moisture_0_to_10cm_mean
```

| Option                        | Description                                         | Default |
|-------------------------------|-----------------------------------------------------|---------|
| `--models=LIST`               | CMIP6 model(s) — **required**                       | —       |
| `--start-date` / `--end-date` | Date range — **required** (1950-01-01 to 2050-12-31)| —       |
| `--daily-params=LIST`         | Daily variables                                     | defaults|
| `--disable-bias-correction`   | Disable statistical downscaling with ERA5-Land      | off     |

**Available models:** `CMCC_CM2_VHR4`, `FGOALS_f3_H`, `HiRAM_SIT_HR`, `MRI_AGCM3_2_S`, `EC_Earth3P_HR`, `MPI_ESM1_2_XR`, `NICAM16_8S`

### marine

Marine / wave forecasts — wave height, period, direction, swell, ocean currents, SST.

```bash
openmeteo marine --current --lat=54.54 --lon=10.23
openmeteo marine --forecast-days=3 --city=Hamburg \
  --hourly-params=wave_height,wave_direction,sea_surface_temperature
```

| Option                | Description                    | Default    |
|-----------------------|--------------------------------|------------|
| `--current`           | Include current conditions     | off        |
| `--forecast-days=N`   | Days of forecast (0–16)        | 7          |
| `--forecast-since=N`  | Start from day N (1=today)     | —          |
| `--length-unit=UNIT`  | `metric` or `imperial`         | metric     |
| `--model=MODEL`       | `best_match`, `ecmwf_wam`, `era5_ocean`, etc. | best_match |

**Key variables:** `wave_height`, `wave_direction`, `wave_period`, `swell_wave_height`, `ocean_current_velocity`, `sea_surface_temperature`, `sea_level_height_msl`

### air-quality

Air quality and pollen forecasts — pollutants, European/US AQI, pollen (Europe only).

```bash
openmeteo air-quality --current --city=Berlin
openmeteo air-quality --current --city=Paris \
  --hourly-params=pm10,pm2_5,european_aqi,ozone
```

| Option                | Description                         | Default  |
|-----------------------|-------------------------------------|----------|
| `--current`           | Include current conditions          | off      |
| `--forecast-days=N`   | Days of forecast (0–7)              | 5        |
| `--forecast-since=N`  | Start from day N (1=today)          | —        |
| `--domains=DOMAIN`    | `auto`, `cams_europe`, `cams_global`| auto     |

**Key variables:** `pm10`, `pm2_5`, `ozone`, `nitrogen_dioxide`, `european_aqi`, `us_aqi`, `uv_index`, `alder_pollen`, `birch_pollen`, `grass_pollen`

> **Note:** This API has **no daily variables**. Use `--hourly-params` for time-series data.

### flood

River discharge / flood forecasts — GloFAS simulated discharge at 5 km resolution, from 1984.

```bash
openmeteo flood --city=Oslo --forecast-days=30
openmeteo flood --lat=48.85 --lon=2.35 --daily-params=river_discharge,river_discharge_max
```

| Option                | Description                          | Default      |
|-----------------------|--------------------------------------|--------------|
| `--forecast-days=N`   | Days of forecast (0–210)             | 92           |
| `--forecast-since=N`  | Start from day N (1=today)           | —            |
| `--daily-params`      | Daily variables                      | defaults     |
| `--ensemble`          | Return all 50 ensemble members       | off          |
| `--model=MODEL`       | `seamless_v4`, `forecast_v4`, `consolidated_v4`, etc. | seamless_v4 |

**Variables:** `river_discharge`, `river_discharge_mean`, `river_discharge_median`, `river_discharge_max`, `river_discharge_min`, `river_discharge_p25`, `river_discharge_p75`

### elevation

Terrain elevation lookup — Copernicus DEM at 90 m resolution, up to 100 points per request.

```bash
openmeteo elevation --lat=47.37 --lon=8.55
openmeteo elevation --city=Zurich
openmeteo elevation --lat=52.52,48.85,59.91 --lon=13.41,2.35,10.75
```

| Option      | Description                                   |
|-------------|-----------------------------------------------|
| `--lat=NUM` | Latitude(s), comma-separated for batch lookup |
| `--lon=NUM` | Longitude(s), comma-separated for batch lookup|
| `--city=NAME` | Resolve city to lat/lon first                |

### satellite

Satellite solar radiation data — real-time irradiance from geostationary satellites, data from 1983.

```bash
openmeteo satellite --city=Berlin --past-days=7
openmeteo satellite --lat=48.2 --lon=16.4 --hourly-params=global_tilted_irradiance \
  --tilt=30 --azimuth=0
```

| Option                    | Description                                   | Default                       |
|---------------------------|-----------------------------------------------|-------------------------------|
| `--hourly-params=LIST`    | Hourly variables                              | GHI, direct, diffuse, DNI     |
| `--daily-params=LIST`     | Daily variables                               | —                             |
| `--forecast-days=N`       | 0 or 1 (near-real-time only)                  | 1                             |
| `--past-days=N`           | Past days of satellite archive                | 0                             |
| `--tilt=DEG`              | Solar panel tilt (0–90°)                      | —                             |
| `--azimuth=DEG`           | Solar panel azimuth (-180 to 180°)            | —                             |
| `--temporal-resolution`   | `hourly` or `native` (10/15/30-min)           | hourly                        |
| `--model=MODEL`           | Satellite source or NWP model for comparison  | satellite_radiation_seamless  |

**Key variables:** `shortwave_radiation`, `direct_radiation`, `diffuse_radiation`, `direct_normal_irradiance`, `global_tilted_irradiance` (requires `--tilt` and `--azimuth`), `terrestrial_radiation` — each also available as `*_instant`

> **Note:** NASA GOES is not yet integrated. North American data uses NWP fallback only.

---

## Forecast Window: `--forecast-since`

Skip to any day within the forecast window without doing date math yourself.
Day 1 means **today**, day 2 = tomorrow, and so on.

```bash
# 7-day forecast starting from day 3 (today + 2 days)
openmeteo weather --forecast-days=7 --forecast-since=3 --city=London

# Just day 5 (a single day)
openmeteo weather --forecast-days=5 --forecast-since=5 --city=Berlin

# Works with any forecasting command
openmeteo marine --forecast-days=10 --forecast-since=4 --lat=54.54 --lon=10.23
openmeteo air-quality --forecast-since=2 --city=Paris
openmeteo flood --forecast-days=30 --forecast-since=7 --city=Oslo
openmeteo ensemble --forecast-days=14 --forecast-since=3 --city=Tokyo --models=icon_seamless
```

**Rules:**
- `N` must be ≥ 1 and ≤ `--forecast-days`
- Mutually exclusive with `--start-date`
- Available for: `weather`, `ensemble`, `marine`, `air-quality`, `flood`

Under the hood, `--forecast-since=N` is converted to the API's `start_date` / `end_date` parameters (no data is trimmed client-side).

---

## Detailed Help

Every command supports a `help` subcommand that can show detailed variable lists:

```bash
openmeteo weather help                   # general weather help
openmeteo weather help --daily-params    # list all daily variables with descriptions
openmeteo weather help --hourly-params   # list all hourly variables
openmeteo weather help --current-params  # list all current variables
openmeteo ensemble help --daily-params
openmeteo air-quality help --hourly-params
openmeteo climate help --daily-params
```

The param lists are grouped by category (temperature, wind, precipitation, etc.) and include units where applicable.

Output format flags work with help too:

```bash
openmeteo weather help --daily-params                # human-friendly (default, grouped by category)
openmeteo weather help --daily-params --porcelain    # name=description (one per line)
openmeteo weather help --daily-params --llm          # TSV table (variable → description)
```

---

## Output Formats

### Human-friendly (default)

Colored, emoji-rich output with data grouped by day. Designed for terminal reading. ANSI colors are automatically disabled when output is piped.

```
$ openmeteo weather --forecast-days=2 --city=Vienna \
    --hourly-params=precipitation,precipitation_probability,weather_code

🌍 Vienna, Austria · 48.21°N, 16.37°E
   Europe/Vienna (GMT+1) · Elevation: 196m

📅 Mon Feb 09, 2026

   00:00  0.0mm (0%) · Overcast
   01:00  0.0mm (0%) · Overcast
   ...
   06:00  0.0mm (0%) · Rain showers
   ...

📅 Tue Feb 10, 2026

   00:00  0.0mm (0%) · Overcast
   ...
```

Hourly data is "zipped" — each hour becomes a single line with all its variables, instead of the raw API's separate arrays.

### Porcelain (`--porcelain`)

Flat `key=value` lines, one per line, with dot-separated paths. Designed for parsing with `grep`, `awk`, `cut`, or any scripting language.

```
$ openmeteo weather --current --city=London --porcelain
latitude=51.5
longitude=-0.120000124
timezone=Europe/London
current.time=2026-02-09T18:45
current.temperature_2m=7.1
current.relative_humidity_2m=83
current.apparent_temperature=3.9
current.weather_code=3
current.wind_speed_10m=13.3
current_units.temperature_2m=°C
```

Hourly data is keyed by timestamp:

```
hourly.2026-02-09T00:00.temperature_2m=7.2
hourly.2026-02-09T01:00.temperature_2m=6.8
```

### LLM (`--llm`)

Compact, token-efficient output designed for AI agents and LLM tool use. Uses TSV (tab-separated) tables with a header row — columns are declared once with units, then data streams as rows. This reduces token count by ~90% compared to porcelain for time-series data.

Inspired by [TOON](https://toonformat.dev/) (Token-Oriented Object Notation) principles, but implemented in pure `jq` with no extra dependencies.

```
$ openmeteo weather --current --forecast-days=1 --city=London --llm
# meta
lat:51.5 lon:-0.120000124 elev:23.0m tz:Europe/London(GMT)
location:London,United Kingdom
# current 2026-02-10T18:45
temperature_2m:9.8°C relative_humidity_2m:90% apparent_temperature:8.3°C is_day:0 weather_code:61(Light rain) cloud_cover:100% wind_speed_10m:7.6km/h wind_direction_10m:85° wind_gusts_10m:17.3km/h

# hourly
time	temperature_2m(°C)	relative_humidity_2m(%)	...
2026-02-10T00:00	7.7	88	...
2026-02-10T01:00	7.8	89	...
```

Structure:
- `# meta` — location coordinates, elevation, timezone (single compact line)
- `# current` — current conditions as `key:value` pairs with units
- `# hourly` / `# daily` — TSV table: header row with column names and units, then one data row per time step
- Weather codes are resolved to human-readable text (e.g., `Light rain` instead of `61`)

All commands support `--llm`. Works with `geo` (TSV result table) and `elevation` (TSV lat/lon/elevation table) too.

### Raw JSON (`--raw`)

Unmodified JSON from the Open-Meteo API. Useful for debugging or piping into `jq`.

```bash
openmeteo weather --current --city=London --raw | jq '.current.temperature_2m'
```

---

## API Key / Commercial Access

Open-Meteo's free tier has no API key requirement. For commercial use or higher rate limits, provide your key in one of two ways:

```bash
# Via environment variable
export OPENMETEO_API_KEY="your_key_here"
openmeteo weather --current --city=London

# Via flag (overrides env var)
openmeteo weather --current --city=London --api-key=your_key_here
```

When an API key is set, the tool automatically prefixes API hostnames with `customer-` as required by Open-Meteo (e.g., `https://customer-api.open-meteo.com/...`).

---

## Examples Cookbook

### Get current temperature and humidity for multiple cities

```bash
for city in London Paris Berlin Tokyo; do
  echo "=== $city ==="
  openmeteo weather --current --city="$city" --current-params=temperature_2m,relative_humidity_2m --porcelain \
    | grep "^current\."
done
```

### 7-day precipitation forecast (porcelain → grep)

```bash
openmeteo weather --forecast-days=7 --city=Vienna \
  --hourly-params=precipitation --porcelain \
  | grep "^hourly\." | grep -v "=0$"
```

### Compare two climate models for Berlin, 2040-2050

```bash
openmeteo climate --city=Berlin --models=CMCC_CM2_VHR4 \
  --start-date=2040-01-01 --end-date=2050-12-31 \
  --daily-params=temperature_2m_mean --porcelain > model_a.txt

openmeteo climate --city=Berlin --models=EC_Earth3P_HR \
  --start-date=2040-01-01 --end-date=2050-12-31 \
  --daily-params=temperature_2m_mean --porcelain > model_b.txt
```

### Batch elevation lookup

```bash
openmeteo elevation --lat=27.99,35.68,48.86 --lon=86.93,139.69,2.35 --porcelain
# elevation.0=8714.0
# elevation.1=40.0
# elevation.2=38.0
```

### Solar panel output estimation with GTI

```bash
openmeteo satellite --city=Munich --past-days=30 \
  --hourly-params=global_tilted_irradiance \
  --tilt=35 --azimuth=0
```

### Flood monitoring: check river discharge near Oslo

```bash
openmeteo flood --lat=59.91 --lon=10.75 --forecast-days=30 --porcelain \
  | grep "river_discharge="
```

### Air quality: current PM2.5 and AQI for scripting

```bash
pm25=$(openmeteo air-quality --current --city=Delhi \
  --current-params=pm2_5,us_aqi --porcelain | grep "current.pm2_5=" | cut -d= -f2)
echo "Current PM2.5 in Delhi: ${pm25} µg/m³"
```

### Token-efficient weather summary for an AI agent

```bash
# An LLM agent skill can fetch compact weather context in ~150 tokens:
openmeteo weather --current --forecast-days=1 --city=Berlin --llm
```

### Get raw JSON and process with jq

```bash
openmeteo marine --lat=54.54 --lon=10.23 --forecast-days=1 --raw \
  | jq '.hourly | [.time, .wave_height] | transpose | map({time: .[0], wave_height: .[1]})'
```

---

## Known Quirks & Limitations

### Flood API — 5 km grid resolution

The Flood API uses a 5 km grid. The closest river may not be selected correctly for your coordinates. Try varying `--lat`/`--lon` by ±0.1° to find a more representative discharge value. Ocean and riverless locations return `null` values.

### Satellite API — no North America coverage

NASA GOES satellite data is not yet integrated into Open-Meteo's Satellite API. North American coordinates fall back to NWP model data, which is less accurate for solar irradiance.

### Satellite API — `forecast_days` limited to 0–1

Satellite data is near-real-time, not forecasted. The `--forecast-days` flag only accepts 0 or 1.

### Air Quality API — no daily variables

The Air Quality API only provides hourly and current data. There is no `--daily-params` option. Use `--hourly-params` for time-series.

### Climate API — date range 1950–2050

CMIP6 projections are only available for 1950-01-01 through 2050-12-31. Dates outside this range will be rejected.

### Ensemble models — member aggregation

Ensemble forecasts return data from many members. The human-friendly output shows aggregated statistics (mean, spread, mode for weather codes). Use `--raw` to get all individual members.

### Elevation API — `NaN` values

The API returns `NaN` (IEEE Not-a-Number) for coordinates without DEM data, such as deep ocean or polar regions. The human-friendly output displays these as "No data (NaN)".

### Output encoding

The human-friendly output uses UTF-8 emojis and ANSI escape codes. If your terminal doesn't support these, use `--porcelain` or `--raw` instead. Colors are automatically disabled when output is piped (not a TTY).

### City name resolution

City resolution uses the Open-Meteo Geocoding API and always picks the top result. For ambiguous names (e.g., "Springfield"), narrow results with `--country=US`. A warning is printed to stderr showing which location was resolved.

---

## Troubleshooting

### `command not found: openmeteo`

The `openmeteo` script is not in your `$PATH`. Either:
- Symlink it: `ln -s /path/to/openmeteo-sh/openmeteo /usr/local/bin/openmeteo`
- Or add the directory to your PATH: `export PATH="/path/to/openmeteo-sh:$PATH"`

### `command not found: jq`

Install `jq` — it's the only non-standard dependency:

```bash
brew install jq        # macOS
sudo apt install jq    # Debian/Ubuntu
sudo dnf install jq    # Fedora
```

### `openmeteo: error: API error (HTTP 400): ...`

The Open-Meteo API rejected the request. Common causes:
- **Wrong parameter name for the category.** For example, `--daily-params=precipitation` should be `--daily-params=precipitation_sum` (daily variables use `_sum` / `_max` / `_min` suffixes). The tool validates known cases and suggests corrections.
- **Invalid model name.** Use `--help` to see valid models for each command.
- **Date out of range.** History starts from 1940, climate from 1950 to 2050, flood from 1984.

### `openmeteo: error: network error: could not reach ...`

Check your internet connection. The tool uses `curl` with a 30-second timeout. If you're behind a proxy, ensure `curl` is configured to use it (via `HTTP_PROXY` / `HTTPS_PROXY` env vars).

### `openmeteo: error: location not found: 'XYZ'`

The Geocoding API didn't find a match. Try:
- A more specific name (e.g., "London, UK" → `--city=London --country=GB`)
- Check spelling
- Use coordinates directly with `--lat` / `--lon`

### Output looks garbled / no colors

Your terminal may not support ANSI escape codes or UTF-8 emojis. Use `--porcelain`, `--llm`, or `--raw` for plain output. If piping output, colors are automatically disabled.

### `--daily-params` has no effect (air quality)

The Air Quality API does not support daily variables. This is an upstream API limitation. Use `--hourly-params` instead.

---

## Contributing

Contributions are welcome! Here's how to get started:

### Setup

```bash
git clone https://github.com/lstpsche/openmeteo-sh.git
cd openmeteo-sh
chmod +x openmeteo
```

### Project structure

```
openmeteo-sh/
  openmeteo              # main entrypoint — subcommand dispatch
  Makefile               # install / uninstall targets
  lib/
    core.sh              # shared: arg parsing, curl wrapper, validation, API key
    output.sh            # output formatting, shared jq library
    geo.sh               # internal geocoding helper (--city resolution)
  commands/
    weather.sh           # openmeteo weather
    geo.sh               # openmeteo geo
    history.sh           # openmeteo history
    ensemble.sh          # openmeteo ensemble
    climate.sh           # openmeteo climate
    marine.sh            # openmeteo marine
    air_quality.sh       # openmeteo air-quality
    flood.sh             # openmeteo flood
    elevation.sh         # openmeteo elevation
    satellite.sh         # openmeteo satellite
  completions/
    openmeteo.bash       # bash tab-completion
    openmeteo.zsh        # zsh tab-completion
  debian/                # Debian packaging scaffolding
```

### Conventions

- **Bash 3.2+ compatible.** Use `[[ ]]`, `local`, `set -euo pipefail`.
- **`snake_case`** for variables and functions. Prefix internal functions with `_`.
- **Quote all variable expansions**: `"${var}"`, not `$var`.
- **Each command file** defines a `cmd_<name>` entry function.
- **Error messages** go to stderr. Normal output goes to stdout.
- **Exit codes:** 0 = success, 1 = user error, 2 = API/network error.

### Adding a new subcommand

1. Create `commands/<name>.sh` with a `cmd_<name>` function.
2. Add a `case` entry in the `openmeteo` entrypoint.
3. Add help text to the main `--help` output.
4. Add `help` subcommand dispatch with `_<name>_help_topic()`.
5. Add detailed param help functions (`_<name>_help_hourly_params`, etc.) if the command has variable selection.
6. Implement all four output formats (human, porcelain, llm, raw).
7. Add verbose input validation before API calls.
8. If the command supports forecasts, add `--forecast-since=N` parsing and conversion.
9. Update `completions/openmeteo.bash` and `completions/openmeteo.zsh`.
10. Test all success and failure paths manually.

### Code style

- Prefer `jq` for all JSON manipulation. No other tools for parsing JSON.
- Use the shared `JQ_LIB` (in `lib/output.sh`) for common jq functions. Add command-specific jq functions in the command file.
- Validate user input before sending API requests. Never let clearly invalid input reach the API.
- Error messages should be actionable — tell the user what's wrong **and** how to fix it.

---

## Submitting Issues

Found a bug? Have a feature request? Please [open an issue on GitHub](https://github.com/lstpsche/openmeteo-sh/issues/new).

When reporting bugs, include:

1. **What you ran** — the exact command
2. **What happened** — the error message or incorrect output
3. **What you expected** — the correct behavior
4. **Your environment** — OS, bash version (`bash --version`), jq version (`jq --version`)

Example:

```
**Command:** `openmeteo weather --current --city=Springfield`
**Output:** `openmeteo: error: location not found: 'Springfield'`
**Expected:** Should resolve to Springfield, IL, USA
**Environment:** macOS 15.2, bash 5.2.37, jq 1.7.1
```

---

## License

MIT License. See [LICENSE](LICENSE) for details.

Copyright (c) 2026 Nikita Shkoda

---

*Data provided by [Open-Meteo](https://open-meteo.com). Open-Meteo is free for non-commercial use.*
