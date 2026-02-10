#!/usr/bin/env bash
# commands/history.sh -- Historical Weather API subcommand

DEFAULT_HISTORY_TIMEZONE="auto"
DEFAULT_HISTORY_TEMPERATURE_UNIT=""
DEFAULT_HISTORY_WIND_SPEED_UNIT=""
DEFAULT_HISTORY_PRECIPITATION_UNIT=""

DEFAULT_HISTORY_HOURLY_PARAMS="temperature_2m,relative_humidity_2m,apparent_temperature,precipitation,weather_code,cloud_cover,wind_speed_10m,wind_direction_10m"
DEFAULT_HISTORY_DAILY_PARAMS=""

_history_help() {
  cat <<EOF
openmeteo history -- Historical weather data (Archive API)

Usage:
  openmeteo history --start-date=DATE --end-date=DATE [options]

Location (one of these is required):
  --lat=NUM         Latitude (WGS84)
  --lon=NUM         Longitude (WGS84)
  --city=NAME       City name (resolved via Geocoding API)
  --country=CODE    Country filter for city resolution (e.g. GB, DE)

Time range (required):
  --start-date=DATE   Start date in YYYY-MM-DD format (data from 1940)
  --end-date=DATE     End date in YYYY-MM-DD format

Data selection:
  --hourly-params=LIST  Comma-separated hourly variables (has sensible defaults)
  --daily-params=LIST   Comma-separated daily variables

Units:
  --temperature-unit=UNIT   celsius (default) or fahrenheit
  --wind-speed-unit=UNIT    kmh (default), ms, mph, kn
  --precipitation-unit=UNIT mm (default) or inch
  --timezone=TZ             IANA timezone or 'auto' (default: auto)

Model:
  --model=MODEL     Reanalysis model (default: best_match)
                    Options: best_match, ecmwf_ifs, ecmwf_ifs_analysis_long_window,
                    era5_seamless, era5, era5_land, era5_ensemble, cerra

Other:
  --cell-selection=MODE   Grid cell selection: land (default), sea, nearest
  --porcelain             Machine-parseable key=value output
  --llm                   Compact TSV output for AI agents
  --raw                   Raw JSON from API
  --help                  Show this help

Examples:
  openmeteo history --city=Paris --start-date=2024-01-01 --end-date=2024-01-07
  openmeteo history --city=Tokyo --start-date=2023-06-01 --end-date=2023-06-30 \\
    --daily-params=temperature_2m_max,temperature_2m_min,precipitation_sum
  openmeteo history --lat=52.52 --lon=13.41 --start-date=2020-12-25 --end-date=2020-12-31 \\
    --hourly-params=temperature_2m,snowfall,wind_speed_10m --model=era5
  openmeteo history --city=London --start-date=2024-07-01 --end-date=2024-07-01 --porcelain
EOF
}

# ---------------------------------------------------------------------------
# Input validation
# ---------------------------------------------------------------------------

_history_param_suggestion() {
  local category="$1" param="$2"

  case "${category}" in
    daily)
      case "${param}" in
        precipitation)
          echo "not a daily variable. Use 'precipitation_sum'" ;;
        precipitation_probability|precipitation_probability_max|precipitation_probability_min|precipitation_probability_mean)
          echo "not available in the Historical Weather API" ;;
        temperature_2m)
          echo "not a daily variable. Use 'temperature_2m_max', 'temperature_2m_min', or 'temperature_2m_mean'" ;;
        apparent_temperature)
          echo "not a daily variable. Use 'apparent_temperature_max', 'apparent_temperature_min', or 'apparent_temperature_mean'" ;;
        wind_speed_10m)
          echo "not a daily variable. Use 'wind_speed_10m_max'" ;;
        wind_gusts_10m)
          echo "not a daily variable. Use 'wind_gusts_10m_max'" ;;
        wind_direction_10m)
          echo "not a daily variable. Use 'wind_direction_10m_dominant'" ;;
        rain)      echo "not a daily variable. Use 'rain_sum'" ;;
        showers)   echo "not a daily variable. Use 'showers_sum'" ;;
        snowfall)  echo "not a daily variable. Use 'snowfall_sum'" ;;
        relative_humidity_2m)
          echo "not a daily variable. Use 'relative_humidity_2m_max', 'relative_humidity_2m_min', or 'relative_humidity_2m_mean'" ;;
        dew_point_2m)
          echo "not a daily variable. Use 'dew_point_2m_max', 'dew_point_2m_min', or 'dew_point_2m_mean'" ;;
        cloud_cover)
          echo "not a daily variable. Use 'cloud_cover_max', 'cloud_cover_min', or 'cloud_cover_mean'" ;;
        pressure_msl|surface_pressure)
          echo "only available as an hourly variable, not daily" ;;
        visibility)
          echo "only available as an hourly variable, not daily" ;;
        is_day)
          echo "only available as an hourly variable, not daily" ;;
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
        wind_speed_10m_max)
          echo "a daily variable. Use 'wind_speed_10m' for hourly" ;;
        wind_gusts_10m_max)
          echo "a daily variable. Use 'wind_gusts_10m' for hourly" ;;
        wind_direction_10m_dominant)
          echo "a daily variable. Use 'wind_direction_10m' for hourly" ;;
        rain_sum)     echo "a daily variable. Use 'rain' for hourly" ;;
        snowfall_sum) echo "a daily variable. Use 'snowfall' for hourly" ;;
        sunrise|sunset)
          echo "only available as a daily variable" ;;
        daylight_duration)
          echo "only available as a daily variable" ;;
      esac
      ;;
  esac
}

_validate_history_params() {
  local category="$1" params_csv="$2"
  local has_error="false"

  local old_ifs="${IFS}"
  IFS=','
  for param in ${params_csv}; do
    [[ -z "${param}" ]] && continue
    local suggestion
    suggestion=$(_history_param_suggestion "${category}" "${param}")
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

_validate_history_inputs() {
  local lat="$1" lon="$2" start_date="$3" end_date="$4"
  local temperature_unit="$5" wind_speed_unit="$6" precipitation_unit="$7"
  local cell_selection="$8" hourly_params="$9" daily_params="${10:-}"

  # Numeric
  [[ -n "${lat}" ]] && _validate_number "--lat" "${lat}"
  [[ -n "${lon}" ]] && _validate_number "--lon" "${lon}"

  # Dates (required -- checked for presence by caller)
  [[ -n "${start_date}" ]] && _validate_date "--start-date" "${start_date}"
  [[ -n "${end_date}" ]]   && _validate_date "--end-date" "${end_date}"

  # Date ordering
  if [[ -n "${start_date}" && -n "${end_date}" ]]; then
    if [[ "${start_date}" > "${end_date}" ]]; then
      _die "--start-date (${start_date}) must not be after --end-date (${end_date})"
    fi
  fi

  # Enums
  [[ -n "${temperature_unit}" ]]   && _validate_enum "--temperature-unit" "${temperature_unit}" celsius fahrenheit
  [[ -n "${wind_speed_unit}" ]]    && _validate_enum "--wind-speed-unit" "${wind_speed_unit}" kmh ms mph kn
  [[ -n "${precipitation_unit}" ]] && _validate_enum "--precipitation-unit" "${precipitation_unit}" mm inch
  [[ -n "${cell_selection}" ]]     && _validate_enum "--cell-selection" "${cell_selection}" land sea nearest

  # Cross-category param validation
  [[ -n "${hourly_params}" ]] && _validate_history_params "hourly" "${hourly_params}"
  [[ -n "${daily_params}" ]]  && _validate_history_params "daily" "${daily_params}"

  return 0
}

# ---------------------------------------------------------------------------
# Human-friendly output
# ---------------------------------------------------------------------------
_history_output_human() {
  local json="$1" loc_name="${2:-}" loc_country="${3:-}"
  local start_date="$4" end_date="$5"
  _init_colors

  echo "${json}" | jq -r \
    --arg name "${loc_name}" \
    --arg country "${loc_country}" \
    --arg sdate "${start_date}" \
    --arg edate "${end_date}" \
    --arg B "${C_BOLD}" --arg D "${C_DIM}" \
    --arg R "${C_RESET}" --arg CB "${C_BLUE}" \
    "${JQ_LIB}"'
    [ fmt_loc_header($name; $country),
      ("\n   📅 Historical: " + $B + $sdate + $R + " → " + $B + $edate + $R),
      fmt_hourly,
      fmt_daily
    ] | map(select(. != null and . != "")) | join("\n")
    '
}

# ---------------------------------------------------------------------------
# LLM output
# ---------------------------------------------------------------------------
_history_output_llm() {
  local json="$1" loc_name="${2:-}" loc_country="${3:-}"
  echo "${json}" | jq -r \
    --arg name "${loc_name}" \
    --arg country "${loc_country}" \
    "${JQ_LIB}"'
    llm_meta,
    (if $name != "" then
      "location:" + $name + (if $country != "" then "," + $country else "" end)
    else empty end),
    llm_hourly,
    llm_daily
  '
}

# ---------------------------------------------------------------------------
# Porcelain output
# ---------------------------------------------------------------------------
_history_output_porcelain() {
  local json="$1"
  echo "${json}" | jq -r "${JQ_LIB}"'
    [porcelain_meta, porcelain_hourly, porcelain_daily] | .[]
  '
}

# ---------------------------------------------------------------------------
# Command entry point
# ---------------------------------------------------------------------------
cmd_history() {
  local lat="" lon="" city="" country=""
  local start_date="" end_date=""
  local hourly_params="" daily_params=""
  local temperature_unit="${DEFAULT_HISTORY_TEMPERATURE_UNIT}"
  local wind_speed_unit="${DEFAULT_HISTORY_WIND_SPEED_UNIT}"
  local precipitation_unit="${DEFAULT_HISTORY_PRECIPITATION_UNIT}"
  local timezone="${DEFAULT_HISTORY_TIMEZONE}"
  local model="" cell_selection=""

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --lat=*)              lat=$(_extract_value "$1") ;;
      --lon=*)              lon=$(_extract_value "$1") ;;
      --city=*)             city=$(_extract_value "$1") ;;
      --country=*)          country=$(_extract_value "$1") ;;
      --start-date=*)       start_date=$(_extract_value "$1") ;;
      --end-date=*)         end_date=$(_extract_value "$1") ;;
      --hourly-params=*)    hourly_params=$(_extract_value "$1") ;;
      --daily-params=*)     daily_params=$(_extract_value "$1") ;;
      --temperature-unit=*) temperature_unit=$(_extract_value "$1") ;;
      --wind-speed-unit=*)  wind_speed_unit=$(_extract_value "$1") ;;
      --precipitation-unit=*) precipitation_unit=$(_extract_value "$1") ;;
      --timezone=*)         timezone=$(_extract_value "$1") ;;
      --model=*)            model=$(_extract_value "$1") ;;
      --cell-selection=*)   cell_selection=$(_extract_value "$1") ;;
      --api-key=*)          API_KEY=$(_extract_value "$1") ;;
      --porcelain)          OUTPUT_FORMAT="porcelain" ;;
      --llm)                OUTPUT_FORMAT="llm" ;;
      --raw)                OUTPUT_FORMAT="raw" ;;
      --verbose)            OPENMETEO_VERBOSE="true" ;;
      --help)               _history_help; return 0 ;;
      *)                    _die_usage "history: unknown option: $1" ;;
    esac
    shift
  done

  _init_api_key

  # -----------------------------------------------------------------------
  # Validate inputs
  # -----------------------------------------------------------------------
  if [[ -z "${start_date}" ]]; then
    _history_help >&2
    _die_usage "missing required argument: --start-date"
  fi
  if [[ -z "${end_date}" ]]; then
    _history_help >&2
    _die_usage "missing required argument: --end-date"
  fi

  _validate_history_inputs \
    "${lat}" "${lon}" "${start_date}" "${end_date}" \
    "${temperature_unit}" "${wind_speed_unit}" "${precipitation_unit}" \
    "${cell_selection}" "${hourly_params}" "${daily_params}"

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
    _history_help >&2
    _die_usage "location required: use --lat/--lon or --city"
  fi

  # -----------------------------------------------------------------------
  # Default params
  # -----------------------------------------------------------------------
  if [[ -z "${hourly_params}" && -z "${daily_params}" ]]; then
    hourly_params="${DEFAULT_HISTORY_HOURLY_PARAMS}"
  fi

  # -----------------------------------------------------------------------
  # Build query string
  # -----------------------------------------------------------------------
  local qs="latitude=${lat}&longitude=${lon}"
  qs="${qs}&start_date=${start_date}&end_date=${end_date}"

  [[ -n "${hourly_params}" ]]       && qs="${qs}&hourly=${hourly_params}"
  [[ -n "${daily_params}" ]]        && qs="${qs}&daily=${daily_params}"
  [[ -n "${timezone}" ]]            && qs="${qs}&timezone=${timezone}"
  [[ -n "${temperature_unit}" ]]    && qs="${qs}&temperature_unit=${temperature_unit}"
  [[ -n "${wind_speed_unit}" ]]     && qs="${qs}&wind_speed_unit=${wind_speed_unit}"
  [[ -n "${precipitation_unit}" ]]  && qs="${qs}&precipitation_unit=${precipitation_unit}"
  [[ -n "${model}" ]]               && qs="${qs}&models=${model}"
  [[ -n "${cell_selection}" ]]      && qs="${qs}&cell_selection=${cell_selection}"

  # -----------------------------------------------------------------------
  # Request + output
  # -----------------------------------------------------------------------
  local response
  response=$(_request "${BASE_URL_HISTORICAL}" "${qs}")

  case "${OUTPUT_FORMAT}" in
    raw)       _output_raw "${response}" ;;
    porcelain) _history_output_porcelain "${response}" ;;
    llm)       _history_output_llm "${response}" "${loc_name}" "${loc_country}" ;;
    *)         _history_output_human "${response}" "${loc_name}" "${loc_country}" "${start_date}" "${end_date}" ;;
  esac
}
