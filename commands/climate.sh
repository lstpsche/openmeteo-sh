#!/usr/bin/env bash
# commands/climate.sh -- Climate Change API subcommand (CMIP6 projections)

DEFAULT_CLIMATE_TEMPERATURE_UNIT=""
DEFAULT_CLIMATE_WIND_SPEED_UNIT=""
DEFAULT_CLIMATE_PRECIPITATION_UNIT=""

DEFAULT_CLIMATE_DAILY_PARAMS="temperature_2m_max,temperature_2m_min,temperature_2m_mean,precipitation_sum"

# Valid CMIP6 climate model names (HighResMip)
CLIMATE_VALID_MODELS=(
  CMCC_CM2_VHR4
  FGOALS_f3_H
  HiRAM_SIT_HR
  MRI_AGCM3_2_S
  EC_Earth3P_HR
  MPI_ESM1_2_XR
  NICAM16_8S
)

_climate_help() {
  cat <<EOF
openmeteo climate -- Climate change projections (CMIP6 Climate API)

Usage:
  openmeteo climate --start-date=DATE --end-date=DATE --models=MODEL[,...] [options]

Location (one of these is required):
  --lat=NUM         Latitude (WGS84)
  --lon=NUM         Longitude (WGS84)
  --city=NAME       City name (resolved via Geocoding API)
  --country=CODE    Country filter for city resolution (e.g. GB, DE)

Time range (required):
  --start-date=DATE   Start date (YYYY-MM-DD, from 1950-01-01)
  --end-date=DATE     End date (YYYY-MM-DD, up to 2050-12-31)

Model (required):
  --models=LIST     Comma-separated CMIP6 climate model(s):
                    CMCC_CM2_VHR4, FGOALS_f3_H, HiRAM_SIT_HR,
                    MRI_AGCM3_2_S, EC_Earth3P_HR, MPI_ESM1_2_XR,
                    NICAM16_8S

Data selection:
  --daily-params=LIST   Comma-separated daily variables
                        (default: temperature_2m_max,temperature_2m_min,
                         temperature_2m_mean,precipitation_sum)

    Available daily variables:
      temperature_2m_max, temperature_2m_min, temperature_2m_mean
      relative_humidity_2m_max, relative_humidity_2m_min, relative_humidity_2m_mean
      dew_point_2m_max, dew_point_2m_min, dew_point_2m_mean
      precipitation_sum, rain_sum, snowfall_sum
      wind_speed_10m_mean, wind_speed_10m_max
      pressure_msl_mean, cloud_cover_mean
      shortwave_radiation_sum, et0_fao_evapotranspiration
      soil_moisture_0_to_10cm_mean

Units:
  --temperature-unit=UNIT   celsius (default) or fahrenheit
  --wind-speed-unit=UNIT    kmh (default), ms, mph, kn
  --precipitation-unit=UNIT mm (default) or inch

Other:
  --disable-bias-correction   Disable statistical downscaling with ERA5-Land
  --cell-selection=MODE       Grid cell selection: land (default), sea, nearest
  --porcelain                 Machine-parseable key=value output
  --llm                       Compact TSV output for AI agents
  --raw                       Raw JSON from API
  --help                      Show this help

Examples:
  openmeteo climate --city=Berlin --models=MRI_AGCM3_2_S \\
    --start-date=2020-01-01 --end-date=2030-12-31
  openmeteo climate --lat=48.21 --lon=16.37 \\
    --models=CMCC_CM2_VHR4,EC_Earth3P_HR \\
    --start-date=2040-01-01 --end-date=2050-01-01 \\
    --daily-params=temperature_2m_max,precipitation_sum
  openmeteo climate --city=Tokyo --models=EC_Earth3P_HR \\
    --start-date=1950-01-01 --end-date=2050-01-01 \\
    --daily-params=soil_moisture_0_to_10cm_mean --porcelain
EOF
}

# ---------------------------------------------------------------------------
# Input validation
# ---------------------------------------------------------------------------

_climate_param_suggestion() {
  local param="$1"

  case "${param}" in
    precipitation)
      echo "not a climate daily variable. Use 'precipitation_sum'" ;;
    temperature_2m)
      echo "not a climate daily variable. Use 'temperature_2m_max', 'temperature_2m_min', or 'temperature_2m_mean'" ;;
    rain)
      echo "not a climate daily variable. Use 'rain_sum'" ;;
    snowfall)
      echo "not a climate daily variable. Use 'snowfall_sum'" ;;
    wind_speed_10m)
      echo "not a climate daily variable. Use 'wind_speed_10m_mean' or 'wind_speed_10m_max'" ;;
    relative_humidity_2m)
      echo "not a climate daily variable. Use 'relative_humidity_2m_max', 'relative_humidity_2m_min', or 'relative_humidity_2m_mean'" ;;
    dew_point_2m)
      echo "not a climate daily variable. Use 'dew_point_2m_max', 'dew_point_2m_min', or 'dew_point_2m_mean'" ;;
    cloud_cover)
      echo "not a climate daily variable. Use 'cloud_cover_mean'" ;;
    pressure_msl)
      echo "not a climate daily variable. Use 'pressure_msl_mean'" ;;
    shortwave_radiation)
      echo "not a climate daily variable. Use 'shortwave_radiation_sum'" ;;
    soil_moisture_0_to_10cm)
      echo "not a climate daily variable. Use 'soil_moisture_0_to_10cm_mean'" ;;
    et0_fao_evapotranspiration_sum)
      echo "incorrect suffix. Use 'et0_fao_evapotranspiration'" ;;
    weather_code|is_day|visibility)
      echo "not available in the Climate API" ;;
    cloud_cover_low|cloud_cover_mid|cloud_cover_high)
      echo "not available in the Climate API" ;;
    apparent_temperature|apparent_temperature_max|apparent_temperature_min|apparent_temperature_mean)
      echo "not available in the Climate API" ;;
    wind_direction_10m|wind_direction_10m_dominant)
      echo "not available in the Climate API" ;;
    wind_gusts_10m|wind_gusts_10m_max)
      echo "not available in the Climate API" ;;
    surface_pressure)
      echo "not available in the Climate API. Use 'pressure_msl_mean'" ;;
    precipitation_probability*)
      echo "not available in the Climate API" ;;
    sunrise|sunset|daylight_duration)
      echo "not available in the Climate API" ;;
    wind_speed_10m_min)
      echo "not available. Use 'wind_speed_10m_mean' or 'wind_speed_10m_max'" ;;
  esac
}

_validate_climate_params() {
  local params_csv="$1"
  local has_error="false"

  local old_ifs="${IFS}"
  IFS=','
  for param in ${params_csv}; do
    [[ -z "${param}" ]] && continue
    local suggestion
    suggestion=$(_climate_param_suggestion "${param}")
    if [[ -n "${suggestion}" ]]; then
      _error "--daily-params: '${param}' is ${suggestion}"
      has_error="true"
    fi
  done
  IFS="${old_ifs}"

  if [[ "${has_error}" == "true" ]]; then
    exit 1
  fi
}

_validate_climate_models() {
  local models_csv="$1"
  local has_error="false"

  local valid_list
  valid_list=$(printf '%s, ' "${CLIMATE_VALID_MODELS[@]}")

  local old_ifs="${IFS}"
  IFS=','
  for model in ${models_csv}; do
    [[ -z "${model}" ]] && continue
    local found="false"
    local m
    for m in "${CLIMATE_VALID_MODELS[@]}"; do
      if [[ "${model}" == "${m}" ]]; then
        found="true"
        break
      fi
    done
    if [[ "${found}" == "false" ]]; then
      _error "--models: '${model}' is not a valid climate model"
      _error "  Valid models: ${valid_list%, }"
      has_error="true"
    fi
  done
  IFS="${old_ifs}"

  if [[ "${has_error}" == "true" ]]; then
    exit 1
  fi
}

_validate_climate_inputs() {
  local lat="$1" lon="$2" start_date="$3" end_date="$4"
  local models="$5" daily_params="$6"
  local temperature_unit="$7" wind_speed_unit="$8" precipitation_unit="$9"
  local cell_selection="${10:-}"

  # Numeric
  [[ -n "${lat}" ]] && _validate_number "--lat" "${lat}"
  [[ -n "${lon}" ]] && _validate_number "--lon" "${lon}"

  # Dates
  [[ -n "${start_date}" ]] && _validate_date "--start-date" "${start_date}"
  [[ -n "${end_date}" ]]   && _validate_date "--end-date" "${end_date}"

  if [[ -n "${start_date}" && -n "${end_date}" ]]; then
    if [[ "${start_date}" > "${end_date}" ]]; then
      _die "--start-date (${start_date}) must not be after --end-date (${end_date})"
    fi
  fi

  # Date range bounds
  if [[ -n "${start_date}" && "${start_date}" < "1950-01-01" ]]; then
    _die "--start-date: ${start_date} is before the available range (1950-01-01)"
  fi
  if [[ -n "${end_date}" && "${end_date}" > "2050-12-31" ]]; then
    _die "--end-date: ${end_date} is after the available range (2050-12-31)"
  fi

  # Model validation
  [[ -n "${models}" ]] && _validate_climate_models "${models}"

  # Enums
  [[ -n "${temperature_unit}" ]]   && _validate_enum "--temperature-unit" "${temperature_unit}" celsius fahrenheit
  [[ -n "${wind_speed_unit}" ]]    && _validate_enum "--wind-speed-unit" "${wind_speed_unit}" kmh ms mph kn
  [[ -n "${precipitation_unit}" ]] && _validate_enum "--precipitation-unit" "${precipitation_unit}" mm inch
  [[ -n "${cell_selection}" ]]     && _validate_enum "--cell-selection" "${cell_selection}" land sea nearest

  # Daily param validation
  [[ -n "${daily_params}" ]] && _validate_climate_params "${daily_params}"

  return 0
}

# ---------------------------------------------------------------------------
# Climate-specific jq library (multi-model aggregation + time grouping)
# ---------------------------------------------------------------------------
# shellcheck disable=SC2034
read -r -d '' CLIMATE_JQ_LIB <<'CJQEOF' || true

# Strip model suffix from variable key
# e.g. "temperature_2m_max_CMCC_CM2_VHR4" → "temperature_2m_max"
def model_base:
  if test("_(CMCC_CM2_VHR4|FGOALS_f3_H|HiRAM_SIT_HR|MRI_AGCM3_2_S|EC_Earth3P_HR|MPI_ESM1_2_XR|NICAM16_8S)$")
  then sub("_(CMCC_CM2_VHR4|FGOALS_f3_H|HiRAM_SIT_HR|MRI_AGCM3_2_S|EC_Earth3P_HR|MPI_ESM1_2_XR|NICAM16_8S)$"; "")
  else . end;

# Group daily variable columns by their base name
def c_var_groups($section):
  $section | keys_unsorted | map(select(. != "time")) |
  map({key: ., base: model_base}) |
  group_by(.base) |
  map({base: .[0].base, cols: map(.key)});

# Clean unit keys to base names
def clean_climate_units($raw):
  [$raw | to_entries[] | {key: (.key | model_base), value: .value}]
  | from_entries;

# Aggregate values across models for one time step
def cstats:
  map(select(. != null)) |
  if length == 0 then null
  else {
    mean: (add / length | . * 10 | round / 10),
    min:  (min  | . * 10 | round / 10),
    max:  (max  | . * 10 | round / 10),
    n:    length
  } end;

# Build a stat row for one time step (aggregated across models)
def climate_stat_row($sec; $groups; $i):
  {time: $sec.time[$i]} +
  ([$groups[] | {
    (.base): ([.cols[] | $sec[.][$i]] | cstats)
  }] | add // {});

# Aggregate an array of stat rows into a period summary.
# _sum variables are totaled; others are averaged with min/max extremes.
def aggregate_period:
  . as $rows |
  ($rows[0] | keys_unsorted | map(select(. != "time"))) as $vars |
  [$vars[] as $v |
    ($rows | map(.[$v]) | map(select(. != null))) as $vals |
    if ($vals | length) == 0 then null
    elif ($v | test("_sum$")) then
      {($v): {
        mean: ($vals | map(.mean) | add | . * 10 | round / 10),
        min:  ($vals | map(.min)  | add | . * 10 | round / 10),
        max:  ($vals | map(.max)  | add | . * 10 | round / 10),
        n:    ($vals[0].n)
      }}
    else
      {($v): {
        mean: ($vals | map(.mean) | add / length | . * 10 | round / 10),
        min:  ($vals | map(.min) | min  | . * 10 | round / 10),
        max:  ($vals | map(.max) | max  | . * 10 | round / 10),
        n:    ($vals[0].n)
      }}
    end
  ] | map(select(. != null)) | add // {};

# Format "YYYY-MM" as "January 2020" etc.
def month_label:
  {
    "01": "January", "02": "February", "03": "March",
    "04": "April", "05": "May", "06": "June",
    "07": "July", "08": "August", "09": "September",
    "10": "October", "11": "November", "12": "December"
  } as $months |
  ($months[.[5:7]] // .[5:7]) + " " + .[:4];

# Format one row of climate data for human output
def fmt_climate_row($units; $mc):
  . as $row |
  ([
    (if $row.temperature_2m_max and $row.temperature_2m_min then
      "🌡  \($row.temperature_2m_min.mean)°→\($row.temperature_2m_max.mean)°" +
      (if $mc > 1 then
        " " + $D + "(spread: \($row.temperature_2m_min.min)°–\($row.temperature_2m_max.max)°)" + $R
      else "" end) +
      (if $row.temperature_2m_mean then
        " avg \($row.temperature_2m_mean.mean)°"
      else "" end)
    elif $row.temperature_2m_mean then
      "🌡  avg \($row.temperature_2m_mean.mean)°" +
      (if $mc > 1 then
        " " + $D + "(\($row.temperature_2m_mean.min)°–\($row.temperature_2m_mean.max)°)" + $R
      else "" end)
    elif $row.temperature_2m_max then
      "🌡  max \($row.temperature_2m_max.mean)°"
    elif $row.temperature_2m_min then
      "🌡  min \($row.temperature_2m_min.mean)°"
    else null end),
    (if $row.precipitation_sum then
      "🌧  \($row.precipitation_sum.mean)\($units.precipitation_sum // "mm")" +
      (if $mc > 1 then
        " " + $D + "(\($row.precipitation_sum.min)–\($row.precipitation_sum.max))" + $R
      else "" end)
    else null end),
    (if $row.rain_sum then
      "🌧  rain: \($row.rain_sum.mean)\($units.rain_sum // "mm")"
    else null end),
    (if $row.snowfall_sum then
      "🌨  snow: \($row.snowfall_sum.mean)\($units.snowfall_sum // "cm")"
    else null end),
    (if $row.wind_speed_10m_max then
      "💨 max \($row.wind_speed_10m_max.mean) " + ($units.wind_speed_10m_max // "km/h") +
      (if $row.wind_speed_10m_mean then
        " (avg \($row.wind_speed_10m_mean.mean))" else "" end)
    elif $row.wind_speed_10m_mean then
      "💨 avg \($row.wind_speed_10m_mean.mean) " + ($units.wind_speed_10m_mean // "km/h")
    else null end),
    (if $row.relative_humidity_2m_mean then
      "💧 \($row.relative_humidity_2m_mean.mean)%" +
      (if $row.relative_humidity_2m_min and $row.relative_humidity_2m_max then
        " (\($row.relative_humidity_2m_min.mean)%–\($row.relative_humidity_2m_max.mean)%)"
      else "" end)
    else null end),
    (if $row.cloud_cover_mean then
      "☁️  \($row.cloud_cover_mean.mean)%"
    else null end),
    (if $row.pressure_msl_mean then
      "📊 \($row.pressure_msl_mean.mean) hPa"
    else null end),
    (if $row.shortwave_radiation_sum then
      "☀️  \($row.shortwave_radiation_sum.mean) \($units.shortwave_radiation_sum // "MJ/m²")"
    else null end),
    (if $row.et0_fao_evapotranspiration then
      "💦 ET₀: \($row.et0_fao_evapotranspiration.mean)\($units.et0_fao_evapotranspiration // "mm")"
    else null end),
    (if $row.soil_moisture_0_to_10cm_mean then
      "🌱 soil: \($row.soil_moisture_0_to_10cm_mean.mean) \($units.soil_moisture_0_to_10cm_mean // "m³/m³")"
    else null end),
    (if $row.dew_point_2m_mean then
      "💧 dew: \($row.dew_point_2m_mean.mean)°" +
      (if $row.dew_point_2m_min and $row.dew_point_2m_max then
        " (\($row.dew_point_2m_min.mean)°–\($row.dew_point_2m_max.mean)°)"
      else "" end)
    else null end),
    # Catch-all for any remaining variables
    ($row | to_entries | map(
      select(.key | IN("time","temperature_2m_max","temperature_2m_min","temperature_2m_mean",
        "precipitation_sum","rain_sum","snowfall_sum","wind_speed_10m_max","wind_speed_10m_mean",
        "relative_humidity_2m_max","relative_humidity_2m_min","relative_humidity_2m_mean",
        "cloud_cover_mean","pressure_msl_mean","shortwave_radiation_sum",
        "et0_fao_evapotranspiration","soil_moisture_0_to_10cm_mean",
        "dew_point_2m_max","dew_point_2m_min","dew_point_2m_mean") | not) |
      select(.value != null and (.value | type) == "object") |
      "\(.key | gsub("_"; " ")): \(.value.mean)" +
      (if .value.n > 1 then " (\(.value.min)–\(.value.max))" else "" end)
    ) | if length > 0 then join(" · ") else null end)
  ] | map(select(. != null and . != "")) | map("   " + .) | join("\n"));

# Format climate daily data with smart time grouping:
#   ≤31 days: individual days, ≤730 days: by month, else: by year
def fmt_climate_daily:
  if .daily then
    c_var_groups(.daily) as $groups |
    .daily as $d |
    clean_climate_units(.daily_units // {}) as $units |
    ($groups | if length > 0 then .[0].cols | length else 1 end) as $mc |
    [range(0; ($d.time | length))] |
    map(climate_stat_row($d; $groups; .)) |
    . as $all_rows |
    if ($all_rows | length) <= 31 then
      # Short range: individual days
      map(
        .time as $date | . as $row |
        "\n" + $B + "📅 " + ($date | day_label) + $R +
        (if $mc > 1 then " " + $D + "(" + ($mc | tostring) + " models)" + $R else "" end) +
        "\n" + (fmt_climate_row($units; $mc))
      ) | join("\n")
    elif ($all_rows | length) <= 730 then
      # Medium range: by month
      group_by(.time[:7]) |
      map(
        .[0].time[:7] as $ym |
        . as $rows |
        (aggregate_period) as $agg |
        "\n" + $B + "📅 " + ($ym | month_label) + $R +
        (if $mc > 1 then " " + $D + "(" + ($mc | tostring) + " models)" + $R else "" end) +
        " " + $D + "(" + ($rows | length | tostring) + " days)" + $R +
        "\n" + ($agg | fmt_climate_row($units; $mc))
      ) | join("\n")
    else
      # Long range: by year
      group_by(.time[:4]) |
      map(
        .[0].time[:4] as $year |
        . as $rows |
        (aggregate_period) as $agg |
        "\n" + $B + "📅 " + $year + $R +
        (if $mc > 1 then " " + $D + "(" + ($mc | tostring) + " models)" + $R else "" end) +
        " " + $D + "(" + ($rows | length | tostring) + " days)" + $R +
        "\n" + ($agg | fmt_climate_row($units; $mc))
      ) | join("\n")
    end
  else "" end;
CJQEOF

# ---------------------------------------------------------------------------
# Human-friendly output
# ---------------------------------------------------------------------------
_climate_output_human() {
  local json="$1" loc_name="${2:-}" loc_country="${3:-}"
  local models="${4:-}" start_date="${5:-}" end_date="${6:-}"
  _init_colors

  echo "${json}" | jq -r \
    --arg name "${loc_name}" \
    --arg country "${loc_country}" \
    --arg models "${models}" \
    --arg sdate "${start_date}" \
    --arg edate "${end_date}" \
    --arg B "${C_BOLD}" --arg D "${C_DIM}" \
    --arg R "${C_RESET}" --arg CB "${C_BLUE}" \
    "${JQ_LIB}${CLIMATE_JQ_LIB}"'
    [ fmt_loc_header($name; $country),
      ("   🔬 Climate: " + $B + ($models | gsub(","; ", ")) + $R),
      ("   📅 " + $sdate + " → " + $edate),
      fmt_climate_daily
    ] | map(select(. != null and . != "")) | join("\n")
    '
}

# ---------------------------------------------------------------------------
# LLM output
# ---------------------------------------------------------------------------
_climate_output_llm() {
  local json="$1" loc_name="${2:-}" loc_country="${3:-}"
  echo "${json}" | jq -r \
    --arg name "${loc_name}" \
    --arg country "${loc_country}" \
    "${JQ_LIB}"'
    llm_meta,
    (if $name != "" then
      "location:" + $name + (if $country != "" then "," + $country else "" end)
    else empty end),
    llm_daily
  '
}

# ---------------------------------------------------------------------------
# Porcelain output
# ---------------------------------------------------------------------------
_climate_output_porcelain() {
  local json="$1"
  echo "${json}" | jq -r "${JQ_LIB}"'
    [porcelain_meta, porcelain_daily] | .[]
  '
}

# ---------------------------------------------------------------------------
# Command entry point
# ---------------------------------------------------------------------------
cmd_climate() {
  local lat="" lon="" city="" country=""
  local start_date="" end_date=""
  local models=""
  local daily_params=""
  local temperature_unit="${DEFAULT_CLIMATE_TEMPERATURE_UNIT}"
  local wind_speed_unit="${DEFAULT_CLIMATE_WIND_SPEED_UNIT}"
  local precipitation_unit="${DEFAULT_CLIMATE_PRECIPITATION_UNIT}"
  local cell_selection=""
  local disable_bias_correction="false"

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --lat=*)              lat=$(_extract_value "$1") ;;
      --lon=*)              lon=$(_extract_value "$1") ;;
      --city=*)             city=$(_extract_value "$1") ;;
      --country=*)          country=$(_extract_value "$1") ;;
      --start-date=*)       start_date=$(_extract_value "$1") ;;
      --end-date=*)         end_date=$(_extract_value "$1") ;;
      --models=*)           models=$(_extract_value "$1") ;;
      --daily-params=*)     daily_params=$(_extract_value "$1") ;;
      --temperature-unit=*) temperature_unit=$(_extract_value "$1") ;;
      --wind-speed-unit=*)  wind_speed_unit=$(_extract_value "$1") ;;
      --precipitation-unit=*) precipitation_unit=$(_extract_value "$1") ;;
      --cell-selection=*)   cell_selection=$(_extract_value "$1") ;;
      --disable-bias-correction) disable_bias_correction="true" ;;
      --api-key=*)          API_KEY=$(_extract_value "$1") ;;
      --porcelain)          OUTPUT_FORMAT="porcelain" ;;
      --llm)                OUTPUT_FORMAT="llm" ;;
      --raw)                OUTPUT_FORMAT="raw" ;;
      --verbose)            OPENMETEO_VERBOSE="true" ;;
      --help)               _climate_help; return 0 ;;
      *)                    _die_usage "climate: unknown option: $1" ;;
    esac
    shift
  done

  _init_api_key

  # -----------------------------------------------------------------------
  # Validate required arguments
  # -----------------------------------------------------------------------
  if [[ -z "${start_date}" ]]; then
    _climate_help >&2
    _die_usage "missing required argument: --start-date"
  fi
  if [[ -z "${end_date}" ]]; then
    _climate_help >&2
    _die_usage "missing required argument: --end-date"
  fi
  if [[ -z "${models}" ]]; then
    _climate_help >&2
    _die_usage "missing required argument: --models"
  fi

  # -----------------------------------------------------------------------
  # Validate inputs
  # -----------------------------------------------------------------------
  if [[ -z "${daily_params}" ]]; then
    daily_params="${DEFAULT_CLIMATE_DAILY_PARAMS}"
  fi

  _validate_climate_inputs \
    "${lat}" "${lon}" "${start_date}" "${end_date}" \
    "${models}" "${daily_params}" \
    "${temperature_unit}" "${wind_speed_unit}" "${precipitation_unit}" \
    "${cell_selection}"

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
    _climate_help >&2
    _die_usage "location required: use --lat/--lon or --city"
  fi

  # -----------------------------------------------------------------------
  # Build query string
  # -----------------------------------------------------------------------
  local qs="latitude=${lat}&longitude=${lon}"
  qs="${qs}&start_date=${start_date}&end_date=${end_date}"
  qs="${qs}&models=${models}"
  qs="${qs}&daily=${daily_params}"

  [[ -n "${temperature_unit}" ]]    && qs="${qs}&temperature_unit=${temperature_unit}"
  [[ -n "${wind_speed_unit}" ]]     && qs="${qs}&wind_speed_unit=${wind_speed_unit}"
  [[ -n "${precipitation_unit}" ]]  && qs="${qs}&precipitation_unit=${precipitation_unit}"
  [[ -n "${cell_selection}" ]]      && qs="${qs}&cell_selection=${cell_selection}"
  [[ "${disable_bias_correction}" == "true" ]] && qs="${qs}&disable_bias_correction=true"

  # -----------------------------------------------------------------------
  # Request + output
  # -----------------------------------------------------------------------
  local response
  response=$(_request "${BASE_URL_CLIMATE}" "${qs}")

  case "${OUTPUT_FORMAT}" in
    raw)       _output_raw "${response}" ;;
    porcelain) _climate_output_porcelain "${response}" ;;
    llm)       _climate_output_llm "${response}" "${loc_name}" "${loc_country}" ;;
    *)         _climate_output_human "${response}" "${loc_name}" "${loc_country}" "${models}" "${start_date}" "${end_date}" ;;
  esac
}
