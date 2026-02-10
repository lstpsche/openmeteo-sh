#!/usr/bin/env bash
# commands/satellite.sh -- Satellite Radiation API subcommand

DEFAULT_SATELLITE_FORECAST_DAYS=""   # omit = API default (1)
DEFAULT_SATELLITE_PAST_DAYS=""
DEFAULT_SATELLITE_MODEL=""           # omit = API auto (satellite_radiation_seamless)
DEFAULT_SATELLITE_TIMEZONE="auto"

DEFAULT_SATELLITE_HOURLY_PARAMS="shortwave_radiation,direct_radiation,diffuse_radiation,direct_normal_irradiance"
DEFAULT_SATELLITE_DAILY_PARAMS=""

# Validated model slugs -- satellite source + main NWP comparison models
# (tested against live API)
SATELLITE_VALID_MODELS=(
  satellite_radiation_seamless
  best_match
  ecmwf_ifs
  ecmwf_ifs025
  ecmwf_aifs025
  icon_seamless
  icon_global
  icon_eu
  icon_d2
  gfs_seamless
  gfs025
  gem_seamless
  jma_seamless
  jma_gsm
  jma_msm
  kma_seamless
  kma_gdps
  cma_grapes_global
  bom_access_global
  meteofrance_seamless
  meteofrance_arpege_world
  arpege_world
  metno_seamless
  knmi_seamless
  knmi_harmonie_arome_europe
  dmi_seamless
  dmi_harmonie_arome_europe
  ukmo_seamless
  era5_seamless
  era5
  era5_land
  era5_ensemble
  cerra
)

_satellite_help() {
  cat <<EOF
openmeteo satellite -- Satellite solar radiation data (Solar Irradiance API)

Usage:
  openmeteo satellite [options]

Location (required):
  --lat=NUM         Latitude (WGS84)
  --lon=NUM         Longitude (WGS84)
  --city=NAME       City name (resolved via Geocoding API)
  --country=CODE    Country filter for city resolution

Data selection:
  --hourly-params=LIST    Comma-separated hourly variables (see below)
  --daily-params=LIST     Comma-separated daily variables (see below)
  --forecast-days=N       0-1 (default: 1 = current day)
  --past-days=N           Past days of satellite archive (0-15000+)
  --start-date=DATE       Start date (YYYY-MM-DD, satellite data from 1983)
  --end-date=DATE         End date (YYYY-MM-DD)

Model / source:
  --model=MODEL     Satellite source or NWP model for comparison
                    Default: satellite_radiation_seamless (auto)
                    Satellite: satellite_radiation_seamless
                    NWP (comparison): best_match, ecmwf_ifs, icon_seamless, ...

Solar panel (for global_tilted_irradiance):
  --tilt=DEG        Panel tilt in degrees (0-90, 0=horizontal)
  --azimuth=DEG     Panel azimuth in degrees (0=south, -90=east, 90=west)

Other:
  --timezone=TZ             IANA timezone or 'auto' (default: auto)
  --temporal-resolution=RES 'hourly' (default) or 'native' (10/15/30-min)
  --cell-selection=MODE     Grid cell selection: land (default), sea, nearest
  --porcelain               Machine-parseable key=value output
  --raw                     Raw JSON from API
  --help                    Show this help

Hourly variables:
  shortwave_radiation              GHI — global horizontal irradiance (W/m²)
  direct_radiation                 Direct solar radiation (W/m²)
  diffuse_radiation                DHI — diffuse horizontal irradiance (W/m²)
  direct_normal_irradiance         DNI — direct normal irradiance (W/m²)
  global_tilted_irradiance         GTI — tilted plane (requires --tilt/--azimuth)
  terrestrial_radiation            Top-of-atmosphere radiation (W/m²)
  *_instant                        Instantaneous variants (e.g. shortwave_radiation_instant)
  is_day                           1 = day, 0 = night
  sunshine_duration                Sunshine duration (seconds)

Daily variables:
  sunrise                          Sunrise time (ISO 8601)
  sunset                           Sunset time (ISO 8601)
  daylight_duration                Daylight duration (seconds)
  sunshine_duration                Sunshine duration (seconds)
  shortwave_radiation_sum          Total shortwave radiation (MJ/m²)

Note: Solar radiation data from NASA GOES is not yet integrated.
Data is currently unavailable for North America.
Averaged values are backward-averaged over the preceding hour.
Use *_instant variants for instantaneous values at the indicated time.

Examples:
  openmeteo satellite --lat=52.52 --lon=13.41
  openmeteo satellite --city=Berlin --past-days=7
  openmeteo satellite --lat=48.85 --lon=2.35 \\
    --hourly-params=shortwave_radiation,direct_radiation,diffuse_radiation \\
    --daily-params=sunrise,sunset,sunshine_duration,shortwave_radiation_sum
  openmeteo satellite --city=Tokyo \\
    --hourly-params=global_tilted_irradiance --tilt=35 --azimuth=0
  openmeteo satellite --lat=52.52 --lon=13.41 \\
    --start-date=2025-06-01 --end-date=2025-06-07
  openmeteo satellite --city=London --temporal-resolution=native --raw
  openmeteo satellite --city=Sydney --porcelain
EOF
}

# ---------------------------------------------------------------------------
# Input validation
# ---------------------------------------------------------------------------

_satellite_param_suggestion() {
  local category="$1" param="$2"

  case "${category}" in
    hourly)
      case "${param}" in
        # Daily-only variables
        sunrise|sunset)
          echo "only available as a daily variable" ;;
        daylight_duration)
          echo "only available as a daily variable" ;;
        shortwave_radiation_sum)
          echo "a daily variable. Use 'shortwave_radiation' for hourly" ;;
        # Weather variables → wrong API
        temperature_2m*|apparent_temperature*|wind_speed_10m*|wind_direction_10m*|cloud_cover*|precipitation*|snowfall*|rain*|weather_code|pressure_msl|surface_pressure|relative_humidity_2m*|dew_point_2m*)
          echo "not available in the Satellite API. Use 'openmeteo weather' for weather data" ;;
        # Marine variables → wrong API
        wave_height*|wave_direction*|wave_period*|swell_wave_*|ocean_current_*|sea_surface_temperature)
          echo "not available in the Satellite API. Use 'openmeteo marine' for marine data" ;;
        # Air quality → wrong API
        pm10|pm2_5|european_aqi|us_aqi|ozone|nitrogen_dioxide|carbon_monoxide|sulphur_dioxide|dust|uv_index*)
          echo "not available in the Satellite API. Use 'openmeteo air-quality' for air quality data" ;;
        # Flood → wrong API
        river_discharge*)
          echo "not available in the Satellite API. Use 'openmeteo flood' for flood data" ;;
      esac
      ;;
    daily)
      case "${param}" in
        # Hourly-only variables used as daily
        shortwave_radiation|direct_radiation|diffuse_radiation|direct_normal_irradiance|terrestrial_radiation|global_tilted_irradiance)
          echo "an hourly variable, not daily. Use 'shortwave_radiation_sum' for daily totals" ;;
        *_instant)
          echo "an hourly variable. Instant values are not available as daily aggregates" ;;
        is_day)
          echo "only available as an hourly variable" ;;
        # Weather variables → wrong API
        temperature_2m*|apparent_temperature*|wind_speed_10m*|wind_direction_10m*|cloud_cover*|precipitation*|snowfall*|rain*|weather_code)
          echo "not available in the Satellite API. Use 'openmeteo weather' for weather data" ;;
      esac
      ;;
  esac
}

_validate_satellite_params() {
  local category="$1" params_csv="$2"
  local has_error="false"

  local old_ifs="${IFS}"
  IFS=','
  for param in ${params_csv}; do
    [[ -z "${param}" ]] && continue
    local suggestion
    suggestion=$(_satellite_param_suggestion "${category}" "${param}")
    if [[ -n "${suggestion}" ]]; then
      _error "--${category}-params: '${param}' is ${suggestion}"
      has_error="true"
    fi
  done
  IFS="${old_ifs}"

  if [[ "${has_error}" == "true" ]]; then
    exit 1
  fi
}

_validate_satellite_models() {
  local models_csv="$1"
  local valid_list
  valid_list=$(printf '%s, ' "${SATELLITE_VALID_MODELS[@]}")

  local old_ifs="${IFS}"
  IFS=','
  for model in ${models_csv}; do
    [[ -z "${model}" ]] && continue
    local found="false"
    local m
    for m in "${SATELLITE_VALID_MODELS[@]}"; do
      if [[ "${model}" == "${m}" ]]; then
        found="true"
        break
      fi
    done
    if [[ "${found}" == "false" ]]; then
      _die "--model: '${model}' is not a valid satellite/NWP model. Valid models: ${valid_list%, }"
    fi
  done
  IFS="${old_ifs}"
}

_validate_satellite_inputs() {
  local lat="$1" lon="$2" forecast_days="$3" past_days="$4"
  local cell_selection="$5" hourly_params="$6" daily_params="$7"
  local model="$8" start_date="$9" end_date="${10:-}"
  local tilt="${11:-}" azimuth="${12:-}" temporal_resolution="${13:-}"

  # Numeric
  [[ -n "${lat}" ]] && _validate_number "--lat" "${lat}"
  [[ -n "${lon}" ]] && _validate_number "--lon" "${lon}"
  [[ -n "${forecast_days}" ]] && _validate_integer "--forecast-days" "${forecast_days}" 0 1
  [[ -n "${past_days}" ]]     && _validate_integer "--past-days" "${past_days}" 0

  # Tilt / azimuth (floats)
  if [[ -n "${tilt}" ]]; then
    _validate_number "--tilt" "${tilt}"
    # Range: 0-90
    local in_range
    in_range=$(awk -v v="${tilt}" 'BEGIN { print (v >= 0 && v <= 90) ? "1" : "0" }')
    if [[ "${in_range}" != "1" ]]; then
      _die "--tilt: ${tilt} is out of range (0 to 90)"
    fi
  fi
  if [[ -n "${azimuth}" ]]; then
    _validate_number "--azimuth" "${azimuth}"
    # Range: -180 to 180
    local in_range
    in_range=$(awk -v v="${azimuth}" 'BEGIN { print (v >= -180 && v <= 180) ? "1" : "0" }')
    if [[ "${in_range}" != "1" ]]; then
      _die "--azimuth: ${azimuth} is out of range (-180 to 180)"
    fi
  fi

  # GTI requires tilt & azimuth
  if [[ -n "${hourly_params}" ]]; then
    local old_ifs="${IFS}"
    IFS=','
    for p in ${hourly_params}; do
      if [[ "${p}" == "global_tilted_irradiance" || "${p}" == "global_tilted_irradiance_instant" ]]; then
        if [[ -z "${tilt}" || -z "${azimuth}" ]]; then
          _die "'${p}' requires --tilt and --azimuth. Example: --tilt=35 --azimuth=0"
        fi
      fi
    done
    IFS="${old_ifs}"
  fi

  # Enums
  [[ -n "${cell_selection}" ]] && _validate_enum "--cell-selection" "${cell_selection}" land sea nearest
  [[ -n "${temporal_resolution}" ]] && _validate_enum "--temporal-resolution" "${temporal_resolution}" hourly native

  # Dates
  [[ -n "${start_date}" ]] && _validate_date "--start-date" "${start_date}"
  [[ -n "${end_date}" ]]   && _validate_date "--end-date" "${end_date}"
  if [[ -n "${start_date}" && -n "${end_date}" ]]; then
    if [[ "${start_date}" > "${end_date}" ]]; then
      _die "--start-date (${start_date}) must not be after --end-date (${end_date})"
    fi
  fi

  # Cross-category param validation
  [[ -n "${hourly_params}" ]] && _validate_satellite_params "hourly" "${hourly_params}"
  [[ -n "${daily_params}" ]]  && _validate_satellite_params "daily" "${daily_params}"

  # Model validation
  [[ -n "${model}" ]] && _validate_satellite_models "${model}"

  return 0
}

# ---------------------------------------------------------------------------
# Satellite-specific jq library
# ---------------------------------------------------------------------------
# shellcheck disable=SC2034
read -r -d '' SATELLITE_JQ_LIB <<'SATJQEOF' || true

# Radiation intensity classification
def rad_emoji($val):
  if $val == null then " "
  elif $val <= 0 then "🌙"
  elif $val < 100 then "🌤"
  elif $val < 300 then "⛅"
  elif $val < 600 then "☀️ "
  else "🔆" end;

def rad_level($val):
  if $val == null then "—"
  elif $val <= 0 then "Night"
  elif $val < 100 then "Low"
  elif $val < 300 then "Moderate"
  elif $val < 600 then "High"
  else "Very high" end;

# Format duration in seconds to human-readable
def fmt_duration_hm:
  if . == null then "—"
  else
    (. / 3600 | floor) as $h |
    ((. - ($h * 3600)) / 60 | floor) as $m |
    "\($h)h \($m)m"
  end;

# Satellite location header
def fmt_sat_loc($name; $country):
  "🛰  " +
  (if $name != "" then
    "\($name)" + (if $country != "" then ", \($country)" else "" end) + " · "
  else "" end) +
  "\(.latitude | round2)°\(if .latitude >= 0 then "N" else "S" end), " +
  "\(.longitude | abs | round2)°\(if .longitude >= 0 then "E" else "W" end)" +
  "\n   \(.timezone // "GMT") (\(.timezone_abbreviation // ""))" +
  (if .elevation then " · Elevation: \(.elevation)m" else "" end);

# Known hourly keys for smart formatting
def sat_hourly_known_keys:
  ["time", "is_day",
   "shortwave_radiation", "direct_radiation", "diffuse_radiation",
   "direct_normal_irradiance", "global_tilted_irradiance", "terrestrial_radiation",
   "shortwave_radiation_instant", "direct_radiation_instant", "diffuse_radiation_instant",
   "direct_normal_irradiance_instant", "global_tilted_irradiance_instant",
   "terrestrial_radiation_instant", "sunshine_duration"];

# Format one hourly row for satellite data
def fmt_sat_hourly_row($units):
  .time[11:16] as $time |
  . as $row |
  # Determine if we have any non-null data in this row
  ($row | to_entries | map(select(.key != "time" and .value != null)) | length) as $any_data |
  ([$row.shortwave_radiation, $row.direct_radiation, $row.diffuse_radiation,
    $row.direct_normal_irradiance, $row.terrestrial_radiation,
    $row.global_tilted_irradiance] | map(select(. != null)) | length) as $nvals |
  "   " + $D + $time + $R + "  " +
  (if $any_data == 0 then
    $D + "—" + $R
  else
    ([
      (if $row.shortwave_radiation != null then
        rad_emoji($row.shortwave_radiation) + " GHI: " +
        $B + "\($row.shortwave_radiation)" + $R + " " + ($units.shortwave_radiation // "W/m²")
      else null end),
      (if $row.direct_radiation != null then
        "DNI: \($row.direct_normal_irradiance // $row.direct_radiation)" + " " +
        ($units.direct_normal_irradiance // $units.direct_radiation // "W/m²")
      elif $row.direct_normal_irradiance != null then
        "DNI: \($row.direct_normal_irradiance)" + " " +
        ($units.direct_normal_irradiance // "W/m²")
      else null end),
      (if $row.diffuse_radiation != null then
        "DHI: \($row.diffuse_radiation)" + " " +
        ($units.diffuse_radiation // "W/m²")
      else null end),
      (if $row.global_tilted_irradiance != null then
        "GTI: \($row.global_tilted_irradiance)" + " " +
        ($units.global_tilted_irradiance // "W/m²")
      else null end),
      (if $row.terrestrial_radiation != null and
          $row.shortwave_radiation == null and $row.direct_radiation == null then
        "Terr: \($row.terrestrial_radiation)" + " " +
        ($units.terrestrial_radiation // "W/m²")
      else null end),
      # Instant variants (shown when their non-instant counterpart is absent)
      (if $row.shortwave_radiation_instant != null and $row.shortwave_radiation == null then
        rad_emoji($row.shortwave_radiation_instant) + " GHI⚡: " +
        $B + "\($row.shortwave_radiation_instant)" + $R + " " +
        ($units.shortwave_radiation_instant // "W/m²")
      else null end),
      (if $row.direct_radiation_instant != null and $row.direct_radiation == null then
        "Direct⚡: \($row.direct_radiation_instant)" + " " +
        ($units.direct_radiation_instant // "W/m²")
      elif $row.direct_normal_irradiance_instant != null and $row.direct_normal_irradiance == null then
        "DNI⚡: \($row.direct_normal_irradiance_instant)" + " " +
        ($units.direct_normal_irradiance_instant // "W/m²")
      else null end),
      (if $row.diffuse_radiation_instant != null and $row.diffuse_radiation == null then
        "DHI⚡: \($row.diffuse_radiation_instant)" + " " +
        ($units.diffuse_radiation_instant // "W/m²")
      else null end),
      (if $row.global_tilted_irradiance_instant != null and $row.global_tilted_irradiance == null then
        "GTI⚡: \($row.global_tilted_irradiance_instant)" + " " +
        ($units.global_tilted_irradiance_instant // "W/m²")
      else null end),
      (if $row.terrestrial_radiation_instant != null and $row.terrestrial_radiation == null then
        "Terr⚡: \($row.terrestrial_radiation_instant)" + " " +
        ($units.terrestrial_radiation_instant // "W/m²")
      else null end),
      (if $row.sunshine_duration != null then
        "☀️  \($row.sunshine_duration | fmt_duration_hm)"
      else null end),
      (if $row.is_day != null then
        (if $row.is_day == 1 then "Day" else "Night" end)
      else null end),
      # Instant variants and any other vars
      ($row | to_entries | map(
        select(.key | IN(sat_hourly_known_keys[]) | not) |
        select(.value != null) |
        "\(.key | gsub("_"; " ")): \(.value)"
      ) | if length > 0 then join(", ") else null end)
    ] | map(select(. != null and . != "")) | join(" · "))
  end);

# Hourly section grouped by day for satellite
def fmt_sat_hourly:
  if .hourly then
    .hourly_units as $units |
    zip_hourly | group_by(.time[:10]) |
    map(
      .[0].time[:10] as $date |
      "\n" + $B + $CB + "📅 " + ($date | day_label) + $R + "\n" +
      (map(fmt_sat_hourly_row($units)) | join("\n"))
    ) | join("\n")
  else "" end;

# Daily section for satellite
def fmt_sat_daily:
  if .daily then
    .daily_units as $units |
    zip_daily | map(
      .time as $date | . as $row |
      "\n" + $B + "📅 " + ($date | day_label) + $R +
      ([
        (if $row.sunrise != null and $row.sunset != null then
          "🌅 " + $row.sunrise[11:16] + " → " + $row.sunset[11:16]
        elif $row.sunrise != null then "🌅 Rise: " + $row.sunrise[11:16]
        elif $row.sunset != null then  "🌇 Set: " + $row.sunset[11:16]
        else null end),
        (if $row.daylight_duration != null then
          "💡 Daylight: " + ($row.daylight_duration | fmt_duration_hm)
        else null end),
        (if $row.sunshine_duration != null then
          "☀️  Sunshine: " + ($row.sunshine_duration | fmt_duration_hm)
        else null end),
        (if $row.shortwave_radiation_sum != null then
          "⚡ Total GHI: " + $B + "\($row.shortwave_radiation_sum) " +
          ($units.shortwave_radiation_sum // "MJ/m²") + $R
        else null end),
        ($row | to_entries | map(
          select(.key | IN("time","sunrise","sunset","daylight_duration",
            "sunshine_duration","shortwave_radiation_sum") | not) |
          select(.value != null) |
          "\(.key | gsub("_"; " ")): \(.value)"
        ) | if length > 0 then join(" · ") else null end)
      ] | map(select(. != null and . != "")) | map("   " + .) | join("\n"))
    ) | join("\n")
  else "" end;

SATJQEOF

# ---------------------------------------------------------------------------
# Human-friendly output
# ---------------------------------------------------------------------------
_satellite_output_human() {
  local json="$1" loc_name="${2:-}" loc_country="${3:-}"
  _init_colors

  echo "${json}" | jq -r \
    --arg name "${loc_name}" \
    --arg country "${loc_country}" \
    --arg B "${C_BOLD}" --arg D "${C_DIM}" \
    --arg R "${C_RESET}" --arg CB "${C_BLUE}" \
    "${JQ_LIB} ${SATELLITE_JQ_LIB}"'
    [ fmt_sat_loc($name; $country),
      fmt_sat_hourly,
      fmt_sat_daily
    ] | map(select(. != null and . != "")) | join("\n")
    '
}

# ---------------------------------------------------------------------------
# Porcelain output
# ---------------------------------------------------------------------------
_satellite_output_porcelain() {
  local json="$1"
  echo "${json}" | jq -r "${JQ_LIB}"'
    [porcelain_meta, porcelain_hourly, porcelain_daily] | .[]
  '
}

# ---------------------------------------------------------------------------
# Command entry point
# ---------------------------------------------------------------------------
cmd_satellite() {
  local lat="" lon="" city="" country=""
  local forecast_days="${DEFAULT_SATELLITE_FORECAST_DAYS}"
  local past_days="${DEFAULT_SATELLITE_PAST_DAYS}"
  local hourly_params="" daily_params=""
  local model="${DEFAULT_SATELLITE_MODEL}"
  local timezone="${DEFAULT_SATELLITE_TIMEZONE}"
  local cell_selection="" tilt="" azimuth=""
  local temporal_resolution=""
  local start_date="" end_date=""

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --lat=*)                   lat=$(_extract_value "$1") ;;
      --lon=*)                   lon=$(_extract_value "$1") ;;
      --city=*)                  city=$(_extract_value "$1") ;;
      --country=*)               country=$(_extract_value "$1") ;;
      --forecast-days=*)         forecast_days=$(_extract_value "$1") ;;
      --past-days=*)             past_days=$(_extract_value "$1") ;;
      --hourly-params=*)         hourly_params=$(_extract_value "$1") ;;
      --daily-params=*)          daily_params=$(_extract_value "$1") ;;
      --model=*)                 model=$(_extract_value "$1") ;;
      --timezone=*)              timezone=$(_extract_value "$1") ;;
      --cell-selection=*)        cell_selection=$(_extract_value "$1") ;;
      --tilt=*)                  tilt=$(_extract_value "$1") ;;
      --azimuth=*)               azimuth=$(_extract_value "$1") ;;
      --temporal-resolution=*)   temporal_resolution=$(_extract_value "$1") ;;
      --start-date=*)            start_date=$(_extract_value "$1") ;;
      --end-date=*)              end_date=$(_extract_value "$1") ;;
      --api-key=*)               API_KEY=$(_extract_value "$1") ;;
      --porcelain)               OUTPUT_FORMAT="porcelain" ;;
      --raw)                     OUTPUT_FORMAT="raw" ;;
      --verbose)                 OPENMETEO_VERBOSE="true" ;;
      --help)                    _satellite_help; return 0 ;;
      *)                         _die_usage "satellite: unknown option: $1" ;;
    esac
    shift
  done

  _init_api_key

  # -----------------------------------------------------------------------
  # Validate inputs
  # -----------------------------------------------------------------------
  _validate_satellite_inputs \
    "${lat}" "${lon}" "${forecast_days}" "${past_days}" \
    "${cell_selection}" "${hourly_params}" "${daily_params}" \
    "${model}" "${start_date}" "${end_date}" \
    "${tilt}" "${azimuth}" "${temporal_resolution}"

  # -----------------------------------------------------------------------
  # Resolve location
  # -----------------------------------------------------------------------
  local loc_name="" loc_country=""
  if [[ -n "${city}" ]]; then
    _resolve_location "${city}" "${country}"
    lat="${RESOLVED_LAT}"
    lon="${RESOLVED_LON}"
    loc_name="${RESOLVED_NAME}"
    loc_country="${RESOLVED_COUNTRY}"
    _verbose "resolved '${city}' → ${RESOLVED_NAME}${RESOLVED_COUNTRY:+, ${RESOLVED_COUNTRY}} (${lat}, ${lon})"
  fi

  if [[ -z "${lat}" || -z "${lon}" ]]; then
    _satellite_help >&2
    _die_usage "location required: use --lat/--lon or --city"
  fi

  # -----------------------------------------------------------------------
  # Defaults
  # -----------------------------------------------------------------------
  if [[ -z "${hourly_params}" && -z "${daily_params}" ]]; then
    hourly_params="${DEFAULT_SATELLITE_HOURLY_PARAMS}"
  fi

  # -----------------------------------------------------------------------
  # Build query string
  # -----------------------------------------------------------------------
  local qs="latitude=${lat}&longitude=${lon}"

  [[ -n "${hourly_params}" ]]        && qs="${qs}&hourly=${hourly_params}"
  [[ -n "${daily_params}" ]]         && qs="${qs}&daily=${daily_params}"
  [[ -n "${forecast_days}" ]]        && qs="${qs}&forecast_days=${forecast_days}"
  [[ -n "${past_days}" ]]            && qs="${qs}&past_days=${past_days}"
  [[ -n "${start_date}" ]]           && qs="${qs}&start_date=${start_date}"
  [[ -n "${end_date}" ]]             && qs="${qs}&end_date=${end_date}"
  [[ -n "${model}" ]]                && qs="${qs}&models=${model}"
  [[ -n "${timezone}" ]]             && qs="${qs}&timezone=${timezone}"
  [[ -n "${tilt}" ]]                 && qs="${qs}&tilt=${tilt}"
  [[ -n "${azimuth}" ]]              && qs="${qs}&azimuth=${azimuth}"
  [[ -n "${temporal_resolution}" ]]  && qs="${qs}&temporal_resolution=${temporal_resolution}"
  [[ -n "${cell_selection}" ]]       && qs="${qs}&cell_selection=${cell_selection}"

  # -----------------------------------------------------------------------
  # Request + output
  # -----------------------------------------------------------------------
  local response
  response=$(_request "${BASE_URL_SATELLITE}" "${qs}")

  case "${OUTPUT_FORMAT}" in
    raw)       _output_raw "${response}" ;;
    porcelain) _satellite_output_porcelain "${response}" ;;
    *)         _satellite_output_human "${response}" "${loc_name}" "${loc_country}" ;;
  esac
}
