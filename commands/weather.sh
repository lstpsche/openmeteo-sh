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
  --country=CODE    Country filter for city resolution (e.g. GB, DE)

Data selection:
  --current               Include current weather conditions
  --forecast-days=N       Forecast length in days (0-16, default: 7)
  --past-days=N           Include past days (0-92)
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
  --raw             Raw JSON from API
  --help            Show this help

Examples:
  openmeteo weather --current --city=London
  openmeteo weather --forecast-days=3 --lat=52.52 --lon=13.41
  openmeteo weather --current --forecast-days=2 --city=London --country=GB
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
  local current_params="${10:-}"

  # Numeric values
  [[ -n "${lat}" ]]            && _validate_number "--lat" "${lat}"
  [[ -n "${lon}" ]]            && _validate_number "--lon" "${lon}"
  [[ -n "${forecast_days}" ]]  && _validate_integer "--forecast-days" "${forecast_days}" 0 16
  [[ -n "${past_days}" ]]      && _validate_integer "--past-days" "${past_days}" 0 92

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
  local json="$1"
  local loc_name="${2:-}"
  local loc_country="${3:-}"

  _init_colors

  # Build the jq filter for human output
  local filter
  read -r -d '' filter <<'JQFILTER' || true

[
# ── Location header ──────────────────────────────────────────────────
fmt_loc_header($name; $country),

# ── Current conditions ───────────────────────────────────────────────
(if .current then
  .current as $c | .current_units as $u |
  "\n" + $B + "⏱  Now" + $R + " — \($c.time // "now")\n" +

  (if $c.temperature_2m != null then
    "\n   🌡  " + $B + "\($c.temperature_2m)\($u.temperature_2m // "°C")" + $R +
    (if $c.apparent_temperature != null then
      " (feels like \($c.apparent_temperature)\($u.apparent_temperature // "°C"))"
    else "" end)
  else "" end) +

  (if $c.relative_humidity_2m != null then
    "\n   💧 \($c.relative_humidity_2m)% humidity"
  else "" end) +

  (if $c.weather_code != null then
    "\n   " + ($c.weather_code | wmo_emoji) + " " + $B +
    ($c.weather_code | wmo_text) + $R +
    (if $c.cloud_cover != null then " (\($c.cloud_cover)% clouds)" else "" end)
  elif $c.cloud_cover != null then
    "\n   ☁️  \($c.cloud_cover)% clouds"
  else "" end) +

  (if $c.wind_speed_10m != null then
    "\n   💨 \($c.wind_speed_10m) \($u.wind_speed_10m // "km/h")" +
    (if $c.wind_direction_10m != null then " \($c.wind_direction_10m | wind_dir)" else "" end) +
    (if $c.wind_gusts_10m != null then ", gusts \($c.wind_gusts_10m) \($u.wind_gusts_10m // $u.wind_speed_10m // "km/h")" else "" end)
  else "" end) +

  (if $c.is_day != null then
    "\n   " + (if $c.is_day == 1 then "☀️  Day" else "🌙 Night" end)
  else "" end) +

  (if $c.precipitation != null and ($c.precipitation > 0) then
    "\n   🌧  \($c.precipitation)\($u.precipitation // "mm")" +
    (if $c.rain != null and ($c.rain > 0) then " (rain: \($c.rain)\($u.rain // "mm"))" else "" end) +
    (if $c.snowfall != null and ($c.snowfall > 0) then " (snow: \($c.snowfall)\($u.snowfall // "cm"))" else "" end)
  else "" end) +

  (if $c.surface_pressure != null then
    "\n   📊 \($c.surface_pressure) \($u.surface_pressure // "hPa")"
  elif $c.pressure_msl != null then
    "\n   📊 \($c.pressure_msl) \($u.pressure_msl // "hPa")"
  else "" end) +

  # Catch any remaining current variables not handled above
  ($c | to_entries | map(
    select(.key | IN("time","interval","temperature_2m","apparent_temperature",
      "weather_code","relative_humidity_2m","cloud_cover","wind_speed_10m",
      "wind_direction_10m","wind_gusts_10m","is_day","precipitation","rain",
      "showers","snowfall","pressure_msl","surface_pressure") | not) |
    "\n   \(.key | gsub("_"; " ")): \(.value)"
  ) | join(""))

else "" end),

# ── Hourly forecast (grouped by day) ────────────────────────────────
(if .hourly then
  . as $root | .hourly_units as $units |

  zip_hourly |
  group_by(.time[:10]) |

  map(
    .[0].time[:10] as $date |
    "\n" + $B + $CB + "📅 " + ($date | day_label) + $R + "\n" +
    (map(
      .time[11:16] as $time |
      . as $row |
      "   " + $D + $time + $R + "  " + (
        [
          # Temperature + feels like
          (if $row.temperature_2m != null then
            $B + "\($row.temperature_2m)°" + $R +
            (if $row.apparent_temperature != null then
              " (feels \($row.apparent_temperature)°)"
            else "" end)
          else null end),

          # Weather code
          (if $row.weather_code != null then
            ($row.weather_code | wmo_text)
          else null end),

          # Humidity
          (if $row.relative_humidity_2m != null then
            "💧\($row.relative_humidity_2m)%"
          else null end),

          # Precipitation + probability
          (if $row.precipitation != null then
            "\($row.precipitation)\($units.precipitation // "mm")" +
            (if $row.precipitation_probability != null then
              " (\($row.precipitation_probability)%)"
            else "" end)
          elif $row.precipitation_probability != null then
            "💧\($row.precipitation_probability)% chance"
          else null end),

          # Cloud cover (only when no weather_code present to avoid redundancy)
          (if $row.cloud_cover != null and $row.weather_code == null then
            "☁️\($row.cloud_cover)%"
          else null end),

          # Wind speed + direction
          (if $row.wind_speed_10m != null then
            "💨\($row.wind_speed_10m)" +
            (if $units.wind_speed_10m then " \($units.wind_speed_10m)" else "" end) +
            (if $row.wind_direction_10m != null then
              " \($row.wind_direction_10m | wind_dir)"
            else "" end)
          else null end),

          # Catch-all for any other variables
          ($row | to_entries | map(
            select(.key | IN("time","temperature_2m","apparent_temperature",
              "weather_code","relative_humidity_2m","precipitation",
              "precipitation_probability","cloud_cover","wind_speed_10m",
              "wind_direction_10m") | not) |
            "\(.key | gsub("_"; " ")): \(.value // "—")"
          ) | if length > 0 then join(", ") else null end)

        ] | map(select(. != null and . != "")) | join(" · ")
      )
    ) | join("\n"))
  ) | join("\n")
else "" end),

# ── Daily forecast ──────────────────────────────────────────────────
(if .daily then
  . as $root | .daily_units as $units |

  zip_daily | map(
    .time as $date |
    . as $row |
    "\n" + $B + "📅 " + ($date | day_label) + $R +
    (
      [
        # Temperature range
        (if $row.temperature_2m_max != null and $row.temperature_2m_min != null then
          "🌡  \($row.temperature_2m_min)°→\($row.temperature_2m_max)°"
        elif $row.temperature_2m_max != null then
          "🌡  max \($row.temperature_2m_max)°"
        elif $row.temperature_2m_min != null then
          "🌡  min \($row.temperature_2m_min)°"
        else null end),

        # Weather
        (if $row.weather_code != null then
          ($row.weather_code | wmo_emoji) + " " + ($row.weather_code | wmo_text)
        else null end),

        # Precipitation
        (if $row.precipitation_sum != null then
          "🌧  \($row.precipitation_sum)\($units.precipitation_sum // "mm")" +
          (if $row.precipitation_probability_max != null then
            " (\($row.precipitation_probability_max)%)"
          else "" end)
        else null end),

        # Wind
        (if $row.wind_speed_10m_max != null then
          "💨 max \($row.wind_speed_10m_max)\($units.wind_speed_10m_max // "km/h")" +
          (if $row.wind_gusts_10m_max != null then
            ", gusts \($row.wind_gusts_10m_max)"
          else "" end)
        else null end),

        # Sunrise / sunset
        (if $row.sunrise != null and $row.sunset != null then
          "🌅 \($row.sunrise[11:16])→\($row.sunset[11:16])"
        else null end),

        # Remaining daily vars
        ($row | to_entries | map(
          select(.key | IN("time","temperature_2m_max","temperature_2m_min",
            "apparent_temperature_max","apparent_temperature_min","weather_code",
            "precipitation_sum","precipitation_probability_max",
            "wind_speed_10m_max","wind_gusts_10m_max","sunrise","sunset") | not) |
          "\(.key | gsub("_"; " ")): \(.value // "—")"
        ) | if length > 0 then join(" · ") else null end)

      ] | map(select(. != null and . != "")) | map("   " + .) | join("\n")
    )
  ) | join("\n")
else "" end)

] | map(select(. != null and . != "")) | join("\n")
JQFILTER

  echo "${json}" | jq -r \
    --arg name "${loc_name}" \
    --arg country "${loc_country}" \
    --arg B "${C_BOLD}" \
    --arg D "${C_DIM}" \
    --arg R "${C_RESET}" \
    --arg CB "${C_BLUE}" \
    "${JQ_LIB} ${filter}"
}

# ---------------------------------------------------------------------------
# Porcelain output
# ---------------------------------------------------------------------------
_weather_output_porcelain() {
  local json="$1"

  local filter
  read -r -d '' filter <<'JQFILTER' || true
[
  # Location metadata
  "latitude=\(.latitude)",
  "longitude=\(.longitude)",
  (if .elevation then "elevation=\(.elevation)" else empty end),
  "timezone=\(.timezone // "GMT")",
  "timezone_abbreviation=\(.timezone_abbreviation // "")",
  "utc_offset_seconds=\(.utc_offset_seconds // 0)",

  # Current conditions
  (if .current then
    (.current | to_entries[] | "current.\(.key)=\(.value)")
  else empty end),

  # Current units
  (if .current_units then
    (.current_units | to_entries[] | "current_units.\(.key)=\(.value)")
  else empty end),

  # Hourly data zipped by timestamp
  (if .hourly then
    .hourly as $h |
    ($h | keys_unsorted | map(select(. != "time"))) as $vars |
    range(0; ($h.time | length)) as $i |
    $vars[] as $v |
    "hourly.\($h.time[$i]).\($v)=\($h[$v][$i])"
  else empty end),

  # Hourly units
  (if .hourly_units then
    (.hourly_units | to_entries[] | "hourly_units.\(.key)=\(.value)")
  else empty end),

  # Daily data zipped by date
  (if .daily then
    .daily as $d |
    ($d | keys_unsorted | map(select(. != "time"))) as $vars |
    range(0; ($d.time | length)) as $i |
    $vars[] as $v |
    "daily.\($d.time[$i]).\($v)=\($d[$v][$i])"
  else empty end),

  # Daily units
  (if .daily_units then
    (.daily_units | to_entries[] | "daily_units.\(.key)=\(.value)")
  else empty end)
] | .[]
JQFILTER

  echo "${json}" | jq -r "${filter}"
}

# ---------------------------------------------------------------------------
# Command entry point
# ---------------------------------------------------------------------------
cmd_weather() {
  local lat="" lon="" city="" country=""
  local current="false" forecast_days="${DEFAULT_FORECAST_DAYS}"
  local past_days="${DEFAULT_PAST_DAYS}"
  local hourly_params="" daily_params="" current_params=""
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
      --forecast-days=*)    forecast_days=$(_extract_value "$1") ;;
      --past-days=*)        past_days=$(_extract_value "$1") ;;
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
      --raw)                OUTPUT_FORMAT="raw" ;;
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
    "${hourly_params}" "${daily_params}" "${current_params}"

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
    if [[ "${OUTPUT_FORMAT}" == "human" ]]; then
      _warn "resolved '${city}' → ${RESOLVED_NAME}${RESOLVED_COUNTRY:+, ${RESOLVED_COUNTRY}} (${lat}, ${lon})"
    fi
  fi

  if [[ -z "${lat}" || -z "${lon}" ]]; then
    _weather_help >&2
    _die_usage "location required: use --lat/--lon or --city"
  fi

  # -----------------------------------------------------------------------
  # Determine what data to fetch
  # -----------------------------------------------------------------------
  local has_data_selection="false"
  if [[ "${current}" == "true" || -n "${hourly_params}" || -n "${daily_params}" || -n "${forecast_days}" ]]; then
    has_data_selection="true"
  fi

  if [[ "${current}" == "true" && -z "${current_params}" ]]; then
    current_params="${DEFAULT_CURRENT_PARAMS}"
  fi

  if [[ -z "${hourly_params}" && -z "${daily_params}" ]]; then
    if [[ "${current}" == "true" && -z "${forecast_days}" && "${has_data_selection}" == "true" ]]; then
      : # current-only request
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
    *)         _weather_output_human "${response}" "${loc_name}" "${loc_country}" ;;
  esac
}
