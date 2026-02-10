#!/usr/bin/env bash
# commands/weather.sh -- Weather Forecast API subcommand

DEFAULT_FORECAST_DAYS=""  # omit = API default (7)
DEFAULT_PAST_DAYS=""
DEFAULT_TIMEZONE="auto"
DEFAULT_TEMPERATURE_UNIT=""  # omit = API default (celsius)
DEFAULT_WIND_SPEED_UNIT=""   # omit = API default (kmh)
DEFAULT_PRECIPITATION_UNIT="" # omit = API default (mm)

DEFAULT_CURRENT_PARAMS="temperature_2m,relative_humidity_2m,apparent_temperature,is_day,weather_code,cloud_cover,wind_speed_10m,wind_direction_10m,wind_gusts_10m"
DEFAULT_HOURLY_PARAMS="temperature_2m,relative_humidity_2m,apparent_temperature,precipitation_probability,precipitation,weather_code,cloud_cover,wind_speed_10m,wind_direction_10m"
DEFAULT_DAILY_PARAMS="weather_code,temperature_2m_max,temperature_2m_min,apparent_temperature_max,apparent_temperature_min,sunrise,sunset,precipitation_sum,precipitation_probability_max,wind_speed_10m_max,wind_gusts_10m_max"

_weather_help() {
  cat <<EOF
openmeteo weather -- Weather forecast (Forecast API)

Usage:
  openmeteo weather [options]

Location (one of these is required):
  --lat=NUM         Latitude (WGS84)
  --lon=NUM         Longitude (WGS84)
  --city=NAME       City name (resolved via Geocoding API)
  --country=CODE    ISO 3166-1 alpha-2 country filter (e.g. GB, DE, US)

Data selection:
  --current               Include current weather conditions
  --daily                 Include daily forecast (default params)
  --hourly                Include hourly forecast (default params)
  --forecast-days=N       Forecast length in days (0-16, default: 7)
  --past-days=N           Include past days (0-92)
  --start-date=YYYY-MM-DD  Start of custom date range (overrides forecast-days)
  --end-date=YYYY-MM-DD    End of custom date range
  --hourly-params=LIST    Comma-separated hourly variables (has sensible defaults)
  --daily-params=LIST     Comma-separated daily variables (has sensible defaults)
  --current-params=LIST   Comma-separated current variables (has sensible defaults)

Units:
  --temperature-unit=UNIT   celsius (default) or fahrenheit
  --wind-speed-unit=UNIT    kmh (default), ms, mph, kn
  --precipitation-unit=UNIT mm (default) or inch
  --timezone=TZ             IANA timezone or 'auto' (default: auto)

Model:
  --model=MODEL     Weather model (default: best_match)

Output:
  --porcelain       Machine-parseable key=value output
  --llm             Compact TSV output for AI agents (minimal tokens)
  --raw             Raw JSON from API
  --help            Show this help

Examples:
  openmeteo weather --current --city=London
  openmeteo weather --forecast-days=3 --lat=52.52 --lon=13.41
  openmeteo weather --current --forecast-days=2 --city=London --country=GB
  openmeteo weather --daily --city=Vienna                 # daily only, default params
  openmeteo weather --hourly --city=Vienna                # hourly only, default params
  openmeteo weather --daily --hourly --city=Berlin        # both daily and hourly
  openmeteo weather --start-date=2026-02-15 --end-date=2026-02-18 --city=London
  openmeteo weather --forecast-days=2 --city=Vienna \\
    --hourly-params=precipitation,precipitation_probability,weather_code
EOF
}

# ---------------------------------------------------------------------------
# Input validation
# ---------------------------------------------------------------------------

# Check a single param against the wrong-category map for weather.
# Returns a non-empty suggestion string if the param is misplaced; empty if OK.
_weather_param_suggestion() {
  local category="$1" param="$2"

  case "${category}" in
    daily)
      case "${param}" in
        precipitation)
          echo "not a daily variable. Use 'precipitation_sum'" ;;
        precipitation_probability)
          echo "not a daily variable. Use 'precipitation_probability_max', 'precipitation_probability_min', or 'precipitation_probability_mean'" ;;
        temperature_2m)
          echo "not a daily variable. Use 'temperature_2m_max' and/or 'temperature_2m_min'" ;;
        apparent_temperature)
          echo "not a daily variable. Use 'apparent_temperature_max' and/or 'apparent_temperature_min'" ;;
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
          echo "only available as an hourly/current variable, not daily" ;;
        dew_point_2m)
          echo "only available as an hourly variable, not daily" ;;
        cloud_cover|cloud_cover_low|cloud_cover_mid|cloud_cover_high)
          echo "only available as an hourly/current variable, not daily" ;;
        pressure_msl|surface_pressure)
          echo "only available as an hourly/current variable, not daily" ;;
        visibility)
          echo "only available as an hourly variable, not daily" ;;
        is_day)
          echo "only available as an hourly/current variable, not daily" ;;
      esac
      ;;
    hourly)
      case "${param}" in
        temperature_2m_max|temperature_2m_min)
          echo "a daily variable. Use 'temperature_2m' for hourly" ;;
        apparent_temperature_max|apparent_temperature_min)
          echo "a daily variable. Use 'apparent_temperature' for hourly" ;;
        precipitation_sum)
          echo "a daily variable. Use 'precipitation' for hourly" ;;
        precipitation_probability_max|precipitation_probability_min|precipitation_probability_mean)
          echo "a daily variable. Use 'precipitation_probability' for hourly" ;;
        precipitation_hours)
          echo "only available as a daily variable" ;;
        wind_speed_10m_max)
          echo "a daily variable. Use 'wind_speed_10m' for hourly" ;;
        wind_gusts_10m_max)
          echo "a daily variable. Use 'wind_gusts_10m' for hourly" ;;
        wind_direction_10m_dominant)
          echo "a daily variable. Use 'wind_direction_10m' for hourly" ;;
        rain_sum)     echo "a daily variable. Use 'rain' for hourly" ;;
        showers_sum)  echo "a daily variable. Use 'showers' for hourly" ;;
        snowfall_sum) echo "a daily variable. Use 'snowfall' for hourly" ;;
        sunrise|sunset)
          echo "only available as a daily variable" ;;
        daylight_duration)
          echo "only available as a daily variable" ;;
      esac
      ;;
    current)
      case "${param}" in
        temperature_2m_max|temperature_2m_min|apparent_temperature_max|apparent_temperature_min)
          echo "a daily variable, not available for current conditions" ;;
        precipitation_sum|rain_sum|showers_sum|snowfall_sum)
          echo "a daily variable. Use '${param%_sum}' for current" ;;
        precipitation_probability*)
          echo "not available for current conditions" ;;
        sunrise|sunset|daylight_duration)
          echo "only available as a daily variable" ;;
        precipitation_hours)
          echo "only available as a daily variable" ;;
      esac
      ;;
  esac
}

# Validate a comma-separated list of weather params for the given category.
# Dies with helpful messages if any params are clearly wrong.
# Usage: _validate_weather_params "daily" "$daily_params"
_validate_weather_params() {
  local category="$1" params_csv="$2"
  local has_error="false"

  local old_ifs="${IFS}"
  IFS=','
  for param in ${params_csv}; do
    # skip empty tokens (trailing commas, etc.)
    [[ -z "${param}" ]] && continue

    local suggestion
    suggestion=$(_weather_param_suggestion "${category}" "${param}")
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

# Validate all weather command inputs after arg parsing.
_validate_weather_inputs() {
  local lat="$1" lon="$2" forecast_days="$3" past_days="$4"
  local temperature_unit="$5" wind_speed_unit="$6" precipitation_unit="$7"
  local hourly_params="$8" daily_params="$9"
  local current_params="${10:-}" start_date="${11:-}" end_date="${12:-}"

  # Numeric values
  [[ -n "${lat}" ]]            && _validate_number "--lat" "${lat}"
  [[ -n "${lon}" ]]            && _validate_number "--lon" "${lon}"
  [[ -n "${forecast_days}" ]]  && _validate_integer "--forecast-days" "${forecast_days}" 0 16
  [[ -n "${past_days}" ]]      && _validate_integer "--past-days" "${past_days}" 0 92

  # Date values
  [[ -n "${start_date}" ]]     && _validate_date "--start-date" "${start_date}"
  [[ -n "${end_date}" ]]       && _validate_date "--end-date" "${end_date}"

  # Enum values
  [[ -n "${temperature_unit}" ]]   && _validate_enum "--temperature-unit" "${temperature_unit}" celsius fahrenheit
  [[ -n "${wind_speed_unit}" ]]    && _validate_enum "--wind-speed-unit" "${wind_speed_unit}" kmh ms mph kn
  [[ -n "${precipitation_unit}" ]] && _validate_enum "--precipitation-unit" "${precipitation_unit}" mm inch

  # Cross-category param validation
  [[ -n "${hourly_params}" ]]  && _validate_weather_params "hourly" "${hourly_params}"
  [[ -n "${daily_params}" ]]   && _validate_weather_params "daily" "${daily_params}"
  [[ -n "${current_params}" ]] && _validate_weather_params "current" "${current_params}"

  return 0
}

# ---------------------------------------------------------------------------
# Human-friendly output
# ---------------------------------------------------------------------------
_weather_output_human() {
  local json="$1" loc_name="${2:-}" loc_country="${3:-}"
  _init_colors

  echo "${json}" | jq -r \
    --arg name "${loc_name}" \
    --arg country "${loc_country}" \
    --arg B "${C_BOLD}" --arg D "${C_DIM}" \
    --arg R "${C_RESET}" --arg CB "${C_BLUE}" \
    "${JQ_LIB}"'
    [ fmt_loc_header($name; $country),
      fmt_current,
      fmt_hourly,
      fmt_daily
    ] | map(select(. != null and . != "")) | join("\n")
    '
}

# ---------------------------------------------------------------------------
# LLM output (compact TSV for AI agents)
# ---------------------------------------------------------------------------
_weather_output_llm() {
  local json="$1" loc_name="${2:-}" loc_country="${3:-}"
  echo "${json}" | jq -r \
    --arg name "${loc_name}" \
    --arg country "${loc_country}" \
    "${JQ_LIB}"'
    llm_meta,
    (if $name != "" then
      "location:" + $name + (if $country != "" then "," + $country else "" end)
    else empty end),
    llm_current,
    llm_hourly,
    llm_daily
  '
}

# ---------------------------------------------------------------------------
# Porcelain output
# ---------------------------------------------------------------------------
_weather_output_porcelain() {
  local json="$1"
  echo "${json}" | jq -r "${JQ_LIB}"'
    [porcelain_meta, porcelain_current, porcelain_hourly, porcelain_daily] | .[]
  '
}

# ---------------------------------------------------------------------------
# Command entry point
# ---------------------------------------------------------------------------
cmd_weather() {
  local lat="" lon="" city="" country=""
  local current="false" forecast_days="${DEFAULT_FORECAST_DAYS}"
  local past_days="${DEFAULT_PAST_DAYS}"
  local include_daily="false" include_hourly="false"
  local hourly_params="" daily_params="" current_params=""
  local start_date="" end_date=""
  local temperature_unit="${DEFAULT_TEMPERATURE_UNIT}"
  local wind_speed_unit="${DEFAULT_WIND_SPEED_UNIT}"
  local precipitation_unit="${DEFAULT_PRECIPITATION_UNIT}"
  local timezone="${DEFAULT_TIMEZONE}"
  local model=""

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --lat=*)              lat=$(_extract_value "$1") ;;
      --lon=*)              lon=$(_extract_value "$1") ;;
      --city=*)             city=$(_extract_value "$1") ;;
      --country=*)          country=$(_extract_value "$1") ;;
      --current)            current="true" ;;
      --daily)              include_daily="true" ;;
      --hourly)             include_hourly="true" ;;
      --forecast-days=*)    forecast_days=$(_extract_value "$1") ;;
      --past-days=*)        past_days=$(_extract_value "$1") ;;
      --start-date=*)       start_date=$(_extract_value "$1") ;;
      --end-date=*)         end_date=$(_extract_value "$1") ;;
      --hourly-params=*)    hourly_params=$(_extract_value "$1") ;;
      --daily-params=*)     daily_params=$(_extract_value "$1") ;;
      --current-params=*)   current_params=$(_extract_value "$1") ;;
      --temperature-unit=*) temperature_unit=$(_extract_value "$1") ;;
      --wind-speed-unit=*)  wind_speed_unit=$(_extract_value "$1") ;;
      --precipitation-unit=*) precipitation_unit=$(_extract_value "$1") ;;
      --timezone=*)         timezone=$(_extract_value "$1") ;;
      --model=*)            model=$(_extract_value "$1") ;;
      --api-key=*)          API_KEY=$(_extract_value "$1") ;;
      --porcelain)          OUTPUT_FORMAT="porcelain" ;;
      --llm)                OUTPUT_FORMAT="llm" ;;
      --raw)                OUTPUT_FORMAT="raw" ;;
      --verbose)            OPENMETEO_VERBOSE="true" ;;
      --help)               _weather_help; return 0 ;;
      *)                    _die_usage "weather: unknown option: $1" ;;
    esac
    shift
  done

  _init_api_key

  # -----------------------------------------------------------------------
  # Validate inputs
  # -----------------------------------------------------------------------
  _validate_weather_inputs \
    "${lat}" "${lon}" "${forecast_days}" "${past_days}" \
    "${temperature_unit}" "${wind_speed_unit}" "${precipitation_unit}" \
    "${hourly_params}" "${daily_params}" "${current_params}" \
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
    _weather_help >&2
    _die_usage "location required: use --lat/--lon or --city"
  fi

  # -----------------------------------------------------------------------
  # Determine what data to fetch
  # -----------------------------------------------------------------------

  # --daily flag → default daily params (unless custom --daily-params given)
  if [[ "${include_daily}" == "true" && -z "${daily_params}" ]]; then
    daily_params="${DEFAULT_DAILY_PARAMS}"
  fi

  # --hourly flag → default hourly params (unless custom --hourly-params given)
  if [[ "${include_hourly}" == "true" && -z "${hourly_params}" ]]; then
    hourly_params="${DEFAULT_HOURLY_PARAMS}"
  fi

  # --current → default current params
  if [[ "${current}" == "true" && -z "${current_params}" ]]; then
    current_params="${DEFAULT_CURRENT_PARAMS}"
  fi

  # If no explicit data selection was made, default to hourly forecast
  # (unless it's a current-only request with no date/forecast args)
  if [[ -z "${hourly_params}" && -z "${daily_params}" ]]; then
    if [[ "${current}" == "true" && -z "${forecast_days}" && -z "${start_date}" ]]; then
      : # current-only request — don't add forecast data
    else
      hourly_params="${DEFAULT_HOURLY_PARAMS}"
    fi
  fi

  # -----------------------------------------------------------------------
  # Build query string
  # -----------------------------------------------------------------------
  local qs="latitude=${lat}&longitude=${lon}"

  [[ -n "${current_params}" ]]      && qs="${qs}&current=${current_params}"
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
  [[ -n "${model}" ]]               && qs="${qs}&models=${model}"

  # -----------------------------------------------------------------------
  # Request + output
  # -----------------------------------------------------------------------
  local response
  response=$(_request "${BASE_URL_FORECAST}" "${qs}")

  case "${OUTPUT_FORMAT}" in
    raw)       _output_raw "${response}" ;;
    porcelain) _weather_output_porcelain "${response}" ;;
    llm)       _weather_output_llm "${response}" "${loc_name}" "${loc_country}" ;;
    *)         _weather_output_human "${response}" "${loc_name}" "${loc_country}" ;;
  esac
}
