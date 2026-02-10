#!/usr/bin/env bash
# commands/ensemble.sh -- Ensemble Models API subcommand

DEFAULT_ENSEMBLE_TIMEZONE="auto"
DEFAULT_ENSEMBLE_TEMPERATURE_UNIT=""
DEFAULT_ENSEMBLE_WIND_SPEED_UNIT=""
DEFAULT_ENSEMBLE_PRECIPITATION_UNIT=""
DEFAULT_ENSEMBLE_FORECAST_DAYS=""
DEFAULT_ENSEMBLE_PAST_DAYS=""

DEFAULT_ENSEMBLE_HOURLY_PARAMS="temperature_2m,precipitation,weather_code,wind_speed_10m"
DEFAULT_ENSEMBLE_DAILY_PARAMS=""

# Valid ensemble model API names (verified against live API)
ENSEMBLE_VALID_MODELS=(
  icon_seamless icon_global icon_eu icon_d2
  gfs_seamless gfs025 gfs05 gfs_graphcast025
  ecmwf_ifs025 ecmwf_aifs025
  gem_global bom_access_global_ensemble
  ukmo_seamless ukmo_global_ensemble_20km ukmo_uk_ensemble_2km
  meteoswiss_icon_ch1 meteoswiss_icon_ch2
)

_ensemble_help() {
  cat <<EOF
openmeteo ensemble -- Ensemble model forecasts (Ensemble API)

Usage:
  openmeteo ensemble --models=MODEL[,MODEL,...] [options]

Location (one of these is required):
  --lat=NUM         Latitude (WGS84)
  --lon=NUM         Longitude (WGS84)
  --city=NAME       City name (resolved via Geocoding API)
  --country=CODE    Country filter for city resolution (e.g. GB, DE)

Model (required):
  --models=LIST     Comma-separated ensemble model(s):
                    icon_seamless, icon_global, icon_eu, icon_d2,
                    gfs_seamless, gfs025, gfs05, gfs_graphcast025,
                    ecmwf_ifs025, ecmwf_aifs025,
                    gem_global, bom_access_global_ensemble,
                    ukmo_seamless, ukmo_global_ensemble_20km, ukmo_uk_ensemble_2km,
                    meteoswiss_icon_ch1, meteoswiss_icon_ch2

Data selection:
  --hourly-params=LIST  Comma-separated hourly variables
                        (default: temperature_2m,precipitation,weather_code,wind_speed_10m)
  --daily-params=LIST   Comma-separated daily variables
  --forecast-days=N     Forecast length in days (0-35, default: 7)
  --past-days=N         Include past days

Time range (alternative to forecast-days/past-days):
  --start-date=DATE   Start date in YYYY-MM-DD format
  --end-date=DATE     End date in YYYY-MM-DD format

Units:
  --temperature-unit=UNIT   celsius (default) or fahrenheit
  --wind-speed-unit=UNIT    kmh (default), ms, mph, kn
  --precipitation-unit=UNIT mm (default) or inch
  --timezone=TZ             IANA timezone or 'auto' (default: auto)

Other:
  --cell-selection=MODE   Grid cell selection: land (default), sea, nearest
  --porcelain             Machine-parseable key=value output
  --raw                   Raw JSON from API
  --help                  Show this help

Examples:
  openmeteo ensemble --city=Berlin --models=icon_seamless
  openmeteo ensemble --lat=52.52 --lon=13.41 --models=gfs_seamless \\
    --hourly-params=temperature_2m,precipitation --forecast-days=10
  openmeteo ensemble --city=Tokyo --models=ecmwf_ifs025 \\
    --daily-params=temperature_2m_max,temperature_2m_min,precipitation_sum
  openmeteo ensemble --city=London --models=icon_seamless --porcelain
EOF
}

# ---------------------------------------------------------------------------
# Input validation
# ---------------------------------------------------------------------------

_ensemble_param_suggestion() {
  local category="$1" param="$2"

  case "${category}" in
    daily)
      case "${param}" in
        precipitation)
          echo "not a daily variable. Use 'precipitation_sum'" ;;
        temperature_2m)
          echo "not a daily variable. Use 'temperature_2m_max', 'temperature_2m_min', or 'temperature_2m_mean'" ;;
        apparent_temperature)
          echo "not a daily variable. Use 'apparent_temperature_max', 'apparent_temperature_min', or 'apparent_temperature_mean'" ;;
        wind_speed_10m)
          echo "not a daily variable. Use 'wind_speed_10m_max', 'wind_speed_10m_min', or 'wind_speed_10m_mean'" ;;
        wind_gusts_10m)
          echo "not a daily variable. Use 'wind_gusts_10m_max', 'wind_gusts_10m_min', or 'wind_gusts_10m_mean'" ;;
        wind_direction_10m)
          echo "not a daily variable. Use 'wind_direction_10m_dominant'" ;;
        rain)      echo "not a daily variable. Use 'rain_sum'" ;;
        snowfall)  echo "not a daily variable. Use 'snowfall_sum'" ;;
        relative_humidity_2m)
          echo "not a daily variable. Use 'relative_humidity_2m_max', 'relative_humidity_2m_min', or 'relative_humidity_2m_mean'" ;;
        dew_point_2m)
          echo "not a daily variable. Use 'dew_point_2m_max', 'dew_point_2m_min', or 'dew_point_2m_mean'" ;;
        cloud_cover)
          echo "not a daily variable. Use 'cloud_cover_max', 'cloud_cover_min', or 'cloud_cover_mean'" ;;
        pressure_msl)
          echo "not a daily variable. Use 'pressure_msl_max', 'pressure_msl_min', or 'pressure_msl_mean'" ;;
        surface_pressure)
          echo "not a daily variable. Use 'surface_pressure_max', 'surface_pressure_min', or 'surface_pressure_mean'" ;;
        cape)
          echo "not a daily variable. Use 'cape_max', 'cape_min', or 'cape_mean'" ;;
        visibility)
          echo "only available as an hourly variable, not daily" ;;
        weather_code)
          echo "only available as an hourly variable in ensemble, not daily" ;;
        is_day)
          echo "not available in the Ensemble API" ;;
      esac
      ;;
    hourly)
      case "${param}" in
        temperature_2m_max|temperature_2m_min|temperature_2m_mean)
          echo "a daily variable. Use 'temperature_2m' for hourly" ;;
        apparent_temperature_max|apparent_temperature_min|apparent_temperature_mean)
          echo "a daily variable. Use 'apparent_temperature' for hourly" ;;
        precipitation_sum)
          echo "a daily variable. Use 'precipitation' for hourly" ;;
        precipitation_hours)
          echo "only available as a daily variable" ;;
        wind_speed_10m_max|wind_speed_10m_min|wind_speed_10m_mean)
          echo "a daily variable. Use 'wind_speed_10m' for hourly" ;;
        wind_gusts_10m_max|wind_gusts_10m_min|wind_gusts_10m_mean)
          echo "a daily variable. Use 'wind_gusts_10m' for hourly" ;;
        wind_direction_10m_dominant)
          echo "a daily variable. Use 'wind_direction_10m' for hourly" ;;
        rain_sum)     echo "a daily variable. Use 'rain' for hourly" ;;
        snowfall_sum) echo "a daily variable. Use 'snowfall' for hourly" ;;
        sunrise|sunset)
          echo "not available in the Ensemble API" ;;
        daylight_duration)
          echo "not available in the Ensemble API" ;;
        is_day)
          echo "not available in the Ensemble API" ;;
      esac
      ;;
  esac
}

_validate_ensemble_params() {
  local category="$1" params_csv="$2"
  local has_error="false"

  local old_ifs="${IFS}"
  IFS=','
  for param in ${params_csv}; do
    [[ -z "${param}" ]] && continue
    local suggestion
    suggestion=$(_ensemble_param_suggestion "${category}" "${param}")
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

_validate_ensemble_models() {
  local models_csv="$1"
  local has_error="false"

  local old_ifs="${IFS}"
  IFS=','
  for model in ${models_csv}; do
    [[ -z "${model}" ]] && continue
    local found="false"
    local m
    for m in "${ENSEMBLE_VALID_MODELS[@]}"; do
      if [[ "${model}" == "${m}" ]]; then
        found="true"
        break
      fi
    done
    if [[ "${found}" == "false" ]]; then
      local valid_list
      valid_list=$(printf '%s, ' "${ENSEMBLE_VALID_MODELS[@]}")
      _error "--models: '${model}' is not a valid ensemble model"
      _error "  Valid models: ${valid_list%, }"
      has_error="true"
    fi
  done
  IFS="${old_ifs}"

  if [[ "${has_error}" == "true" ]]; then
    exit 1
  fi
}

_validate_ensemble_inputs() {
  local lat="$1" lon="$2" models="$3" forecast_days="$4" past_days="$5"
  local temperature_unit="$6" wind_speed_unit="$7" precipitation_unit="$8"
  local cell_selection="$9" hourly_params="${10:-}" daily_params="${11:-}"
  local start_date="${12:-}" end_date="${13:-}"

  # Numeric
  [[ -n "${lat}" ]]            && _validate_number "--lat" "${lat}"
  [[ -n "${lon}" ]]            && _validate_number "--lon" "${lon}"
  [[ -n "${forecast_days}" ]]  && _validate_integer "--forecast-days" "${forecast_days}" 0 35
  [[ -n "${past_days}" ]]      && _validate_integer "--past-days" "${past_days}" 0 92

  # Dates
  [[ -n "${start_date}" ]] && _validate_date "--start-date" "${start_date}"
  [[ -n "${end_date}" ]]   && _validate_date "--end-date" "${end_date}"
  if [[ -n "${start_date}" && -n "${end_date}" ]]; then
    if [[ "${start_date}" > "${end_date}" ]]; then
      _die "--start-date (${start_date}) must not be after --end-date (${end_date})"
    fi
  fi

  # Model validation
  [[ -n "${models}" ]] && _validate_ensemble_models "${models}"

  # Enums
  [[ -n "${temperature_unit}" ]]   && _validate_enum "--temperature-unit" "${temperature_unit}" celsius fahrenheit
  [[ -n "${wind_speed_unit}" ]]    && _validate_enum "--wind-speed-unit" "${wind_speed_unit}" kmh ms mph kn
  [[ -n "${precipitation_unit}" ]] && _validate_enum "--precipitation-unit" "${precipitation_unit}" mm inch
  [[ -n "${cell_selection}" ]]     && _validate_enum "--cell-selection" "${cell_selection}" land sea nearest

  # Cross-category param validation
  [[ -n "${hourly_params}" ]] && _validate_ensemble_params "hourly" "${hourly_params}"
  [[ -n "${daily_params}" ]]  && _validate_ensemble_params "daily" "${daily_params}"

  return 0
}

# ---------------------------------------------------------------------------
# Ensemble-specific jq library (member aggregation)
# ---------------------------------------------------------------------------
# shellcheck disable=SC2034
read -r -d '' ENSEMBLE_JQ_LIB <<'EJQEOF' || true

def member_base:
  if test("_member[0-9]+$") then sub("_member[0-9]+$"; "") else . end;

def e_var_groups($section):
  $section | keys_unsorted | map(select(. != "time")) |
  map({key: ., base: member_base}) |
  group_by(.base) |
  map({base: .[0].base, cols: map(.key)});

def clean_units($raw):
  [$raw | to_entries[] | {key: (.key | member_base), value: .value}]
  | from_entries;

def estats:
  if length == 0 then null
  else {
    mean: (add / length | . * 10 | round / 10),
    min:  (min  | . * 10 | round / 10),
    max:  (max  | . * 10 | round / 10),
    mode: (group_by(.) | max_by(length) | .[0]),
    n:    length
  } end;

def ensemble_stat_row($sec; $groups; $i):
  {time: $sec.time[$i]} +
  ([$groups[] | {
    (.base): ([.cols[] | $sec[.][$i] | select(. != null)] | estats)
  }] | add // {});

def fmt_e_spread($s):
  if $s.n > 1 then " " + $D + "(" + "\($s.min)–\($s.max)" + ")" + $R
  else "" end;

def fmt_e_hourly_row($units):
  .time[11:16] as $time |
  . as $row |
  "   " + $D + $time + $R + "  " + ([
    (if $row.temperature_2m then
      $B + "\($row.temperature_2m.mean)°" + $R +
      (fmt_e_spread($row.temperature_2m)) +
      (if $row.apparent_temperature then
        " feels \($row.apparent_temperature.mean)°"
      else "" end)
    else null end),
    (if $row.weather_code then
      ($row.weather_code.mode | wmo_emoji) + ($row.weather_code.mode | wmo_text)
    else null end),
    (if $row.relative_humidity_2m then
      "💧\($row.relative_humidity_2m.mean)%"
    else null end),
    (if $row.precipitation then
      "🌧 \($row.precipitation.mean)\($units.precipitation // "mm")" +
      (fmt_e_spread($row.precipitation))
    else null end),
    (if $row.wind_speed_10m then
      "💨\($row.wind_speed_10m.mean) " + ($units.wind_speed_10m // "km/h") +
      (fmt_e_spread($row.wind_speed_10m)) +
      (if $row.wind_direction_10m then
        " " + ($row.wind_direction_10m.mean | round | wind_dir)
      else "" end)
    else null end),
    ($row | to_entries | map(
      select(.key | IN("time","temperature_2m","apparent_temperature","weather_code",
        "relative_humidity_2m","precipitation","wind_speed_10m","wind_direction_10m",
        "cloud_cover","wind_gusts_10m","rain","snowfall","snow_depth") | not) |
      select(.value != null and (.value | type) == "object") |
      "\(.key | gsub("_"; " ")): \(.value.mean)" +
      (if .value.n > 1 then " (\(.value.min)–\(.value.max))" else "" end)
    ) | if length > 0 then join(" · ") else null end)
  ] | map(select(. != null and . != "")) | join(" · "));

def fmt_ensemble_hourly:
  if .hourly then
    e_var_groups(.hourly) as $groups |
    .hourly as $h |
    clean_units(.hourly_units // {}) as $units |
    ($groups | if length > 0 then .[0].cols | length else 1 end) as $mc |
    [range(0; ($h.time | length))] |
    map(ensemble_stat_row($h; $groups; .)) |
    group_by(.time[:10]) |
    map(
      .[0].time[:10] as $date |
      "\n" + $B + $CB + "📅 " + ($date | day_label) + $R +
      " " + $D + "(" + ($mc | tostring) + " members)" + $R + "\n" +
      (map(fmt_e_hourly_row($units)) | join("\n"))
    ) | join("\n")
  else "" end;

def fmt_ensemble_daily:
  if .daily then
    e_var_groups(.daily) as $groups |
    .daily as $d |
    clean_units(.daily_units // {}) as $units |
    ($groups | if length > 0 then .[0].cols | length else 1 end) as $mc |
    [range(0; ($d.time | length))] |
    map(ensemble_stat_row($d; $groups; .)) |
    map(
      .time as $date | . as $row |
      "\n" + $B + "📅 " + ($date | day_label) + $R +
      " " + $D + "(" + ($mc | tostring) + " members)" + $R +
      ([
        (if $row.temperature_2m_max and $row.temperature_2m_min then
          "🌡  \($row.temperature_2m_min.mean)°→\($row.temperature_2m_max.mean)°" +
          (if $row.temperature_2m_max.n > 1 then
            " " + $D + "(spread: \($row.temperature_2m_min.min)°–\($row.temperature_2m_max.max)°)" + $R
          else "" end) +
          (if $row.temperature_2m_mean then
            " avg \($row.temperature_2m_mean.mean)°"
          else "" end)
        elif $row.temperature_2m_mean then
          "🌡  avg \($row.temperature_2m_mean.mean)°"
        else null end),
        (if $row.precipitation_sum then
          "🌧  \($row.precipitation_sum.mean)\($units.precipitation_sum // "mm")" +
          (if $row.precipitation_sum.n > 1 then
            " " + $D + "(\($row.precipitation_sum.min)–\($row.precipitation_sum.max))" + $R
          else "" end)
        else null end),
        (if $row.wind_speed_10m_max then
          "💨 max \($row.wind_speed_10m_max.mean) " + ($units.wind_speed_10m_max // "km/h") +
          (if $row.wind_speed_10m_max.n > 1 then
            " " + $D + "(\($row.wind_speed_10m_max.min)–\($row.wind_speed_10m_max.max))" + $R
          else "" end)
        else null end),
        ($row | to_entries | map(
          select(.key | IN("time","temperature_2m_max","temperature_2m_min","temperature_2m_mean",
            "apparent_temperature_max","apparent_temperature_min","apparent_temperature_mean",
            "precipitation_sum","wind_speed_10m_max","wind_speed_10m_mean","wind_speed_10m_min",
            "wind_gusts_10m_max","wind_gusts_10m_mean","wind_gusts_10m_min",
            "wind_direction_10m_dominant","wind_direction_100m_dominant") | not) |
          select(.value != null and (.value | type) == "object") |
          "\(.key | gsub("_"; " ")): \(.value.mean)" +
          (if .value.n > 1 then " (\(.value.min)–\(.value.max))" else "" end)
        ) | if length > 0 then join(" · ") else null end)
      ] | map(select(. != null and . != "")) | map("   " + .) | join("\n"))
    ) | join("\n")
  else "" end;
EJQEOF

# ---------------------------------------------------------------------------
# Human-friendly output
# ---------------------------------------------------------------------------
_ensemble_output_human() {
  local json="$1" loc_name="${2:-}" loc_country="${3:-}" models="${4:-}"
  _init_colors

  echo "${json}" | jq -r \
    --arg name "${loc_name}" \
    --arg country "${loc_country}" \
    --arg models "${models}" \
    --arg B "${C_BOLD}" --arg D "${C_DIM}" \
    --arg R "${C_RESET}" --arg CB "${C_BLUE}" \
    "${JQ_LIB}${ENSEMBLE_JQ_LIB}"'
    [ fmt_loc_header($name; $country),
      ("   📊 Ensemble: " + $B + $models + $R),
      fmt_ensemble_hourly,
      fmt_ensemble_daily
    ] | map(select(. != null and . != "")) | join("\n")
    '
}

# ---------------------------------------------------------------------------
# Porcelain output
# ---------------------------------------------------------------------------
_ensemble_output_porcelain() {
  local json="$1"
  echo "${json}" | jq -r "${JQ_LIB}"'
    [porcelain_meta, porcelain_hourly, porcelain_daily] | .[]
  '
}

# ---------------------------------------------------------------------------
# Command entry point
# ---------------------------------------------------------------------------
cmd_ensemble() {
  local lat="" lon="" city="" country=""
  local models=""
  local hourly_params="" daily_params=""
  local forecast_days="${DEFAULT_ENSEMBLE_FORECAST_DAYS}"
  local past_days="${DEFAULT_ENSEMBLE_PAST_DAYS}"
  local start_date="" end_date=""
  local temperature_unit="${DEFAULT_ENSEMBLE_TEMPERATURE_UNIT}"
  local wind_speed_unit="${DEFAULT_ENSEMBLE_WIND_SPEED_UNIT}"
  local precipitation_unit="${DEFAULT_ENSEMBLE_PRECIPITATION_UNIT}"
  local timezone="${DEFAULT_ENSEMBLE_TIMEZONE}"
  local cell_selection=""

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --lat=*)              lat=$(_extract_value "$1") ;;
      --lon=*)              lon=$(_extract_value "$1") ;;
      --city=*)             city=$(_extract_value "$1") ;;
      --country=*)          country=$(_extract_value "$1") ;;
      --models=*)           models=$(_extract_value "$1") ;;
      --hourly-params=*)    hourly_params=$(_extract_value "$1") ;;
      --daily-params=*)     daily_params=$(_extract_value "$1") ;;
      --forecast-days=*)    forecast_days=$(_extract_value "$1") ;;
      --past-days=*)        past_days=$(_extract_value "$1") ;;
      --start-date=*)       start_date=$(_extract_value "$1") ;;
      --end-date=*)         end_date=$(_extract_value "$1") ;;
      --temperature-unit=*) temperature_unit=$(_extract_value "$1") ;;
      --wind-speed-unit=*)  wind_speed_unit=$(_extract_value "$1") ;;
      --precipitation-unit=*) precipitation_unit=$(_extract_value "$1") ;;
      --timezone=*)         timezone=$(_extract_value "$1") ;;
      --cell-selection=*)   cell_selection=$(_extract_value "$1") ;;
      --api-key=*)          API_KEY=$(_extract_value "$1") ;;
      --porcelain)          OUTPUT_FORMAT="porcelain" ;;
      --raw)                OUTPUT_FORMAT="raw" ;;
      --verbose)            OPENMETEO_VERBOSE="true" ;;
      --help)               _ensemble_help; return 0 ;;
      *)                    _die_usage "ensemble: unknown option: $1" ;;
    esac
    shift
  done

  _init_api_key

  # -----------------------------------------------------------------------
  # Validate inputs
  # -----------------------------------------------------------------------
  if [[ -z "${models}" ]]; then
    _ensemble_help >&2
    _die_usage "missing required argument: --models"
  fi

  _validate_ensemble_inputs \
    "${lat}" "${lon}" "${models}" "${forecast_days}" "${past_days}" \
    "${temperature_unit}" "${wind_speed_unit}" "${precipitation_unit}" \
    "${cell_selection}" "${hourly_params}" "${daily_params}" \
    "${start_date}" "${end_date}"

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
    _ensemble_help >&2
    _die_usage "location required: use --lat/--lon or --city"
  fi

  # -----------------------------------------------------------------------
  # Default params
  # -----------------------------------------------------------------------
  if [[ -z "${hourly_params}" && -z "${daily_params}" ]]; then
    hourly_params="${DEFAULT_ENSEMBLE_HOURLY_PARAMS}"
  fi

  # -----------------------------------------------------------------------
  # Build query string
  # -----------------------------------------------------------------------
  local qs="latitude=${lat}&longitude=${lon}&models=${models}"

  [[ -n "${hourly_params}" ]]       && qs="${qs}&hourly=${hourly_params}"
  [[ -n "${daily_params}" ]]        && qs="${qs}&daily=${daily_params}"
  [[ -n "${forecast_days}" ]]       && qs="${qs}&forecast_days=${forecast_days}"
  [[ -n "${past_days}" ]]           && qs="${qs}&past_days=${past_days}"
  [[ -n "${start_date}" ]]          && qs="${qs}&start_date=${start_date}"
  [[ -n "${end_date}" ]]            && qs="${qs}&end_date=${end_date}"
  [[ -n "${timezone}" ]]            && qs="${qs}&timezone=${timezone}"
  [[ -n "${temperature_unit}" ]]    && qs="${qs}&temperature_unit=${temperature_unit}"
  [[ -n "${wind_speed_unit}" ]]     && qs="${qs}&wind_speed_unit=${wind_speed_unit}"
  [[ -n "${precipitation_unit}" ]]  && qs="${qs}&precipitation_unit=${precipitation_unit}"
  [[ -n "${cell_selection}" ]]      && qs="${qs}&cell_selection=${cell_selection}"

  # -----------------------------------------------------------------------
  # Request + output
  # -----------------------------------------------------------------------
  local response
  response=$(_request "${BASE_URL_ENSEMBLE}" "${qs}")

  case "${OUTPUT_FORMAT}" in
    raw)       _output_raw "${response}" ;;
    porcelain) _ensemble_output_porcelain "${response}" ;;
    *)         _ensemble_output_human "${response}" "${loc_name}" "${loc_country}" "${models}" ;;
  esac
}
