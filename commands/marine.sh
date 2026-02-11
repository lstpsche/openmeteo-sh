#!/usr/bin/env bash
# commands/marine.sh -- Marine Weather API subcommand

DEFAULT_MARINE_FORECAST_DAYS=""  # omit = API default (7)
DEFAULT_MARINE_PAST_DAYS=""
DEFAULT_MARINE_TIMEZONE="auto"
DEFAULT_MARINE_LENGTH_UNIT=""       # omit = API default (metric)
DEFAULT_MARINE_WIND_SPEED_UNIT=""   # omit = API default (kmh) -- for ocean current velocity

DEFAULT_MARINE_CURRENT_PARAMS="wave_height,wave_direction,wave_period,wind_wave_height,wind_wave_direction,wind_wave_period,swell_wave_height,swell_wave_direction,swell_wave_period,sea_surface_temperature,ocean_current_velocity,ocean_current_direction"
DEFAULT_MARINE_HOURLY_PARAMS="wave_height,wave_direction,wave_period,wind_wave_height,wind_wave_direction,swell_wave_height,swell_wave_direction,ocean_current_velocity,ocean_current_direction,sea_surface_temperature"
DEFAULT_MARINE_DAILY_PARAMS=""

# Verified model slugs (tested against live API)
MARINE_VALID_MODELS=(
  best_match
  meteofrance_wave
  meteofrance_currents
  ewam
  gwam
  ecmwf_wam
  ecmwf_wam025
  ncep_gfswave025
  ncep_gfswave016
  era5_ocean
)

_marine_help() {
  cat <<EOF
openmeteo marine -- Marine / wave forecasts (Marine API)

Usage:
  openmeteo marine [options]

Location (required):
  --lat=NUM         Latitude (WGS84)
  --lon=NUM         Longitude (WGS84)
  --city=NAME       Coastal city name (resolved via Geocoding API)
  --country=CODE    Country filter for city resolution

Data selection:
  --current               Include current marine conditions
  --forecast-days=N       Forecast length in days (0-16, default: 7)
  --forecast-since=N      Start forecast from day N (1=today, 2=tomorrow, ...)
  --past-days=N           Include past days (0-92)
  --hourly-params=LIST    Comma-separated hourly variables
  --daily-params=LIST     Comma-separated daily variables
  --current-params=LIST   Comma-separated current variables
  --start-date=DATE       Start date (YYYY-MM-DD, alternative to forecast-days)
  --end-date=DATE         End date (YYYY-MM-DD)

Units:
  --length-unit=UNIT      metric (default) or imperial
  --wind-speed-unit=UNIT  kmh (default), ms, mph, kn (for ocean current velocity)
  --timezone=TZ           IANA timezone or 'auto' (default: auto)

Model:
  --model=MODEL     Marine model (default: best_match)
                    Models: best_match, meteofrance_wave, meteofrance_currents,
                    ewam, gwam, ecmwf_wam, ecmwf_wam025,
                    ncep_gfswave025, ncep_gfswave016, era5_ocean

Other:
  --cell-selection=MODE   Grid cell selection: sea (default), land, nearest
  --porcelain             Machine-parseable key=value output
  --llm                   Compact TSV output for AI agents
  --raw                   Raw JSON from API
  --help                  Show this help

Hourly variables:
  wave_height, wave_direction, wave_period, wave_peak_period
  wind_wave_height, wind_wave_direction, wind_wave_period, wind_wave_peak_period
  swell_wave_height, swell_wave_direction, swell_wave_period, swell_wave_peak_period
  secondary_swell_wave_height/direction/period
  tertiary_swell_wave_height/direction/period
  ocean_current_velocity, ocean_current_direction
  sea_surface_temperature, sea_level_height_msl, invert_barometer_height

Daily variables:
  wave_height_max, wave_direction_dominant, wave_period_max
  wind_wave_height_max, wind_wave_direction_dominant, wind_wave_period_max,
    wind_wave_peak_period_max
  swell_wave_height_max, swell_wave_direction_dominant, swell_wave_period_max,
    swell_wave_peak_period_max

Examples:
  openmeteo marine --current --lat=54.54 --lon=10.23
  openmeteo marine --forecast-days=3 --lat=54.54 --lon=10.23
  openmeteo marine --current --city=Hamburg \\
    --hourly-params=wave_height,wave_direction,sea_surface_temperature
  openmeteo marine --forecast-days=5 --lat=28.63 --lon=-80.60 \\
    --daily-params=wave_height_max,wave_direction_dominant,swell_wave_height_max
  openmeteo marine --current --lat=54.54 --lon=10.23 --porcelain

Detailed help:
  openmeteo marine help --hourly-params    List available hourly variables
  openmeteo marine help --daily-params     List available daily variables
  openmeteo marine help --current-params   List available current variables
EOF
}

_marine_help_hourly_params() {
  cat <<'EOF'
Hourly variables for 'openmeteo marine':

Waves (combined sea):
  wave_height                   Significant wave height (m)
  wave_direction                Mean wave direction (degrees)
  wave_period                   Mean wave period (s)
  wave_peak_period              Peak wave period (s)

Wind Waves:
  wind_wave_height              Wind-generated wave height (m)
  wind_wave_direction           Wind wave direction (degrees)
  wind_wave_period              Wind wave period (s)
  wind_wave_peak_period         Wind wave peak period (s)

Swell (primary):
  swell_wave_height             Primary swell height (m)
  swell_wave_direction          Primary swell direction (degrees)
  swell_wave_period             Primary swell period (s)
  swell_wave_peak_period        Primary swell peak period (s)

Swell (secondary / tertiary):
  secondary_swell_wave_height   Secondary swell height
  secondary_swell_wave_direction Secondary swell direction
  secondary_swell_wave_period   Secondary swell period
  tertiary_swell_wave_height    Tertiary swell height
  tertiary_swell_wave_direction Tertiary swell direction
  tertiary_swell_wave_period    Tertiary swell period

Ocean:
  ocean_current_velocity        Ocean current speed (km/h)
  ocean_current_direction       Ocean current direction (degrees)
  sea_surface_temperature       Sea surface temperature (°C)
  sea_level_height_msl          Sea level height above MSL (m)
  invert_barometer_height       Inverted barometer effect (m)

Usage: --hourly-params=wave_height,wave_direction,sea_surface_temperature
EOF
}

_marine_help_daily_params() {
  cat <<'EOF'
Daily variables for 'openmeteo marine':

Waves (combined):
  wave_height_max               Max daily wave height (m)
  wave_direction_dominant       Dominant wave direction (degrees)
  wave_period_max               Max daily wave period (s)

Wind Waves:
  wind_wave_height_max          Max daily wind wave height
  wind_wave_direction_dominant  Dominant wind wave direction
  wind_wave_period_max          Max daily wind wave period
  wind_wave_peak_period_max     Max daily wind wave peak period

Swell:
  swell_wave_height_max         Max daily swell height
  swell_wave_direction_dominant Dominant swell direction
  swell_wave_period_max         Max daily swell period
  swell_wave_peak_period_max    Max daily swell peak period

Usage: --daily-params=wave_height_max,wave_direction_dominant
EOF
}

_marine_help_current_params() {
  cat <<'EOF'
Current variables for 'openmeteo marine':

  wave_height                   Current significant wave height
  wave_direction                Current mean wave direction
  wave_period                   Current mean wave period
  wave_peak_period              Current peak wave period
  wind_wave_height              Current wind wave height
  wind_wave_direction           Current wind wave direction
  wind_wave_period              Current wind wave period
  wind_wave_peak_period         Current wind wave peak period
  swell_wave_height             Current swell height
  swell_wave_direction          Current swell direction
  swell_wave_period             Current swell period
  swell_wave_peak_period        Current swell peak period
  ocean_current_velocity        Current ocean current speed
  ocean_current_direction       Current ocean current direction
  sea_surface_temperature       Current sea surface temperature

Usage: --current-params=wave_height,sea_surface_temperature,ocean_current_velocity
EOF
}

_marine_help_topic() {
  local topic="" fmt="human"
  for arg in "$@"; do
    case "${arg}" in
      --porcelain) fmt="porcelain" ;;
      --llm)       fmt="llm" ;;
      --raw)       fmt="raw" ;;
      *)           topic="${arg}" ;;
    esac
  done

  case "${topic}" in
    --hourly-params)  _marine_help_hourly_params  | _format_param_help "${fmt}" ;;
    --daily-params)   _marine_help_daily_params   | _format_param_help "${fmt}" ;;
    --current-params) _marine_help_current_params | _format_param_help "${fmt}" ;;
    "")               _marine_help ;;
    *)                _error "unknown help topic: ${topic}"; echo; _marine_help ;;
  esac
}

# ---------------------------------------------------------------------------
# Input validation
# ---------------------------------------------------------------------------

_marine_param_suggestion() {
  local category="$1" param="$2"

  case "${category}" in
    daily)
      case "${param}" in
        wave_height)
          echo "not a daily variable. Use 'wave_height_max'" ;;
        wave_direction)
          echo "not a daily variable. Use 'wave_direction_dominant'" ;;
        wave_period)
          echo "not a daily variable. Use 'wave_period_max'" ;;
        wave_peak_period)
          echo "not a daily variable. Use 'wind_wave_peak_period_max' or 'swell_wave_peak_period_max'" ;;
        wind_wave_height)
          echo "not a daily variable. Use 'wind_wave_height_max'" ;;
        wind_wave_direction)
          echo "not a daily variable. Use 'wind_wave_direction_dominant'" ;;
        wind_wave_period)
          echo "not a daily variable. Use 'wind_wave_period_max'" ;;
        wind_wave_peak_period)
          echo "not a daily variable. Use 'wind_wave_peak_period_max'" ;;
        swell_wave_height)
          echo "not a daily variable. Use 'swell_wave_height_max'" ;;
        swell_wave_direction)
          echo "not a daily variable. Use 'swell_wave_direction_dominant'" ;;
        swell_wave_period)
          echo "not a daily variable. Use 'swell_wave_period_max'" ;;
        swell_wave_peak_period)
          echo "not a daily variable. Use 'swell_wave_peak_period_max'" ;;
        ocean_current_velocity|ocean_current_direction)
          echo "only available as an hourly/current variable, not daily" ;;
        sea_surface_temperature)
          echo "only available as an hourly/current variable, not daily" ;;
        sea_level_height_msl)
          echo "only available as an hourly/current variable, not daily" ;;
        invert_barometer_height)
          echo "only available as an hourly/current variable, not daily" ;;
        secondary_swell_wave_*|tertiary_swell_wave_*)
          echo "only available as an hourly/current variable, not daily" ;;
      esac
      ;;
    hourly)
      case "${param}" in
        wave_height_max)
          echo "a daily variable. Use 'wave_height' for hourly" ;;
        wave_direction_dominant)
          echo "a daily variable. Use 'wave_direction' for hourly" ;;
        wave_period_max)
          echo "a daily variable. Use 'wave_period' for hourly" ;;
        wind_wave_height_max)
          echo "a daily variable. Use 'wind_wave_height' for hourly" ;;
        wind_wave_direction_dominant)
          echo "a daily variable. Use 'wind_wave_direction' for hourly" ;;
        wind_wave_period_max)
          echo "a daily variable. Use 'wind_wave_period' for hourly" ;;
        wind_wave_peak_period_max)
          echo "a daily variable. Use 'wind_wave_peak_period' for hourly" ;;
        swell_wave_height_max)
          echo "a daily variable. Use 'swell_wave_height' for hourly" ;;
        swell_wave_direction_dominant)
          echo "a daily variable. Use 'swell_wave_direction' for hourly" ;;
        swell_wave_period_max)
          echo "a daily variable. Use 'swell_wave_period' for hourly" ;;
        swell_wave_peak_period_max)
          echo "a daily variable. Use 'swell_wave_peak_period' for hourly" ;;
      esac
      ;;
    current)
      case "${param}" in
        wave_height_max|wave_direction_dominant|wave_period_max)
          echo "a daily variable, not available for current conditions" ;;
        wind_wave_height_max|wind_wave_direction_dominant|wind_wave_period_max|wind_wave_peak_period_max)
          echo "a daily variable, not available for current conditions" ;;
        swell_wave_height_max|swell_wave_direction_dominant|swell_wave_period_max|swell_wave_peak_period_max)
          echo "a daily variable, not available for current conditions" ;;
      esac
      ;;
  esac
}

_validate_marine_params() {
  local category="$1" params_csv="$2"
  local has_error="false"

  local old_ifs="${IFS}"
  IFS=','
  for param in ${params_csv}; do
    [[ -z "${param}" ]] && continue
    local suggestion
    suggestion=$(_marine_param_suggestion "${category}" "${param}")
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

_validate_marine_models() {
  local models_csv="$1"
  local valid_list
  valid_list=$(printf '%s, ' "${MARINE_VALID_MODELS[@]}")

  local old_ifs="${IFS}"
  IFS=','
  for model in ${models_csv}; do
    [[ -z "${model}" ]] && continue
    local found="false"
    local m
    for m in "${MARINE_VALID_MODELS[@]}"; do
      if [[ "${model}" == "${m}" ]]; then
        found="true"
        break
      fi
    done
    if [[ "${found}" == "false" ]]; then
      _die "--model: '${model}' is not a valid marine model. Valid models: ${valid_list%, }"
    fi
  done
  IFS="${old_ifs}"
}

_validate_marine_inputs() {
  local lat="$1" lon="$2" forecast_days="$3" past_days="$4"
  local length_unit="$5" wind_speed_unit="$6" cell_selection="$7"
  local hourly_params="$8" daily_params="$9"
  local current_params="${10:-}" model="${11:-}"
  local start_date="${12:-}" end_date="${13:-}"

  # Numeric
  [[ -n "${lat}" ]] && _validate_number "--lat" "${lat}"
  [[ -n "${lon}" ]] && _validate_number "--lon" "${lon}"
  [[ -n "${forecast_days}" ]] && _validate_integer "--forecast-days" "${forecast_days}" 0 16
  [[ -n "${past_days}" ]]     && _validate_integer "--past-days" "${past_days}" 0 92

  # Enums
  [[ -n "${length_unit}" ]]     && _validate_enum "--length-unit" "${length_unit}" metric imperial
  [[ -n "${wind_speed_unit}" ]] && _validate_enum "--wind-speed-unit" "${wind_speed_unit}" kmh ms mph kn
  [[ -n "${cell_selection}" ]]  && _validate_enum "--cell-selection" "${cell_selection}" land sea nearest

  # Dates
  [[ -n "${start_date}" ]] && _validate_date "--start-date" "${start_date}"
  [[ -n "${end_date}" ]]   && _validate_date "--end-date" "${end_date}"
  if [[ -n "${start_date}" && -n "${end_date}" ]]; then
    if [[ "${start_date}" > "${end_date}" ]]; then
      _die "--start-date (${start_date}) must not be after --end-date (${end_date})"
    fi
  fi

  # Cross-category param validation
  [[ -n "${hourly_params}" ]]  && _validate_marine_params "hourly" "${hourly_params}"
  [[ -n "${daily_params}" ]]   && _validate_marine_params "daily" "${daily_params}"
  [[ -n "${current_params}" ]] && _validate_marine_params "current" "${current_params}"

  # Model validation
  [[ -n "${model}" ]] && _validate_marine_models "${model}"

  return 0
}

# ---------------------------------------------------------------------------
# Marine-specific jq library
# ---------------------------------------------------------------------------
# shellcheck disable=SC2034
read -r -d '' MARINE_JQ_LIB <<'MJQEOF' || true

# Marine location header (wave emoji, no elevation)
def fmt_marine_loc($name; $country):
  "🌊 " +
  (if $name != "" then
    "\($name)" + (if $country != "" then ", \($country)" else "" end) + " · "
  else "" end) +
  "\(.latitude | round2)°\(if .latitude >= 0 then "N" else "S" end), " +
  "\(.longitude | abs | round2)°\(if .longitude >= 0 then "E" else "W" end)" +
  "\n   \(.timezone // "GMT") (\(.timezone_abbreviation // ""))";

# Keys handled by smart formatting (excluded from catch-all)
def marine_known_keys:
  ["time","interval",
   "wave_height","wave_direction","wave_period","wave_peak_period",
   "wind_wave_height","wind_wave_direction","wind_wave_period","wind_wave_peak_period",
   "swell_wave_height","swell_wave_direction","swell_wave_period","swell_wave_peak_period",
   "secondary_swell_wave_height","secondary_swell_wave_direction","secondary_swell_wave_period",
   "tertiary_swell_wave_height","tertiary_swell_wave_direction","tertiary_swell_wave_period",
   "ocean_current_velocity","ocean_current_direction",
   "sea_surface_temperature","sea_level_height_msl","invert_barometer_height"];

# Daily keys handled by smart formatting
def marine_daily_known_keys:
  ["time",
   "wave_height_max","wave_direction_dominant","wave_period_max",
   "wind_wave_height_max","wind_wave_direction_dominant","wind_wave_period_max","wind_wave_peak_period_max",
   "swell_wave_height_max","swell_wave_direction_dominant","swell_wave_period_max","swell_wave_peak_period_max"];

# Format current marine conditions
def fmt_marine_current:
  if .current then
    .current as $c | .current_units as $u |
    # Check if any data values exist (skip time/interval)
    ($c | to_entries | map(select(.key | IN("time","interval") | not) | select(.value != null)) | length) as $nvals |
    "\n" + $B + "⏱  Now" + $R + " — \($c.time // "now")\n" +
    if $nvals == 0 then
      "\n   " + $D + "No marine data at this location" + $R
    else
      # Mean waves
      (if $c.wave_height != null then
        "\n   🌊 Waves: " + $B + "\($c.wave_height)\($u.wave_height // "m")" + $R +
        (if $c.wave_direction != null then " ← " + ($c.wave_direction | wind_dir) else "" end) +
        (if $c.wave_period != null then " (\($c.wave_period)s" +
          (if $c.wave_peak_period != null then ", peak \($c.wave_peak_period)s)" else ")" end)
        else "" end)
      else "" end) +
      # Wind waves
      (if $c.wind_wave_height != null then
        "\n   💨 Wind waves: \($c.wind_wave_height)\($u.wind_wave_height // "m")" +
        (if $c.wind_wave_direction != null then " ← " + ($c.wind_wave_direction | wind_dir) else "" end) +
        (if $c.wind_wave_period != null then " (\($c.wind_wave_period)s" +
          (if $c.wind_wave_peak_period != null then ", peak \($c.wind_wave_peak_period)s)" else ")" end)
        else "" end)
      else "" end) +
      # Swell
      (if $c.swell_wave_height != null then
        "\n   🏄 Swell: \($c.swell_wave_height)\($u.swell_wave_height // "m")" +
        (if $c.swell_wave_direction != null then " ← " + ($c.swell_wave_direction | wind_dir) else "" end) +
        (if $c.swell_wave_period != null then " (\($c.swell_wave_period)s" +
          (if $c.swell_wave_peak_period != null then ", peak \($c.swell_wave_peak_period)s)" else ")" end)
        else "" end)
      else "" end) +
      # Secondary swell
      (if $c.secondary_swell_wave_height != null then
        "\n   🏄 2nd swell: \($c.secondary_swell_wave_height)\($u.secondary_swell_wave_height // "m")" +
        (if $c.secondary_swell_wave_direction != null then " ← " + ($c.secondary_swell_wave_direction | wind_dir) else "" end) +
        (if $c.secondary_swell_wave_period != null then " (\($c.secondary_swell_wave_period)s)" else "" end)
      else "" end) +
      # Tertiary swell
      (if $c.tertiary_swell_wave_height != null then
        "\n   🏄 3rd swell: \($c.tertiary_swell_wave_height)\($u.tertiary_swell_wave_height // "m")" +
        (if $c.tertiary_swell_wave_direction != null then " ← " + ($c.tertiary_swell_wave_direction | wind_dir) else "" end) +
        (if $c.tertiary_swell_wave_period != null then " (\($c.tertiary_swell_wave_period)s)" else "" end)
      else "" end) +
      # SST
      (if $c.sea_surface_temperature != null then
        "\n   🌡  SST: " + $B + "\($c.sea_surface_temperature)\($u.sea_surface_temperature // "°C")" + $R
      else "" end) +
      # Ocean current
      (if $c.ocean_current_velocity != null then
        "\n   🌀 Current: \($c.ocean_current_velocity)\($u.ocean_current_velocity // "km/h")" +
        (if $c.ocean_current_direction != null then " → " + ($c.ocean_current_direction | wind_dir) else "" end)
      else "" end) +
      # Sea level
      (if $c.sea_level_height_msl != null then
        "\n   📏 Sea level: \($c.sea_level_height_msl)\($u.sea_level_height_msl // "m") MSL"
      else "" end) +
      # Inverted barometer
      (if $c.invert_barometer_height != null then
        "\n   📊 IB effect: \($c.invert_barometer_height)\($u.invert_barometer_height // "m")"
      else "" end) +
      # Remaining keys
      ($c | to_entries | map(
        select(.key | IN(marine_known_keys[]) | not) |
        select(.value != null) |
        "\n   \(.key | gsub("_"; " ")): \(.value)"
      ) | join(""))
    end
  else "" end;

# Format one hourly row for marine data (returns null if all values are null)
def fmt_marine_hourly_row($units):
  .time[11:16] as $time |
  . as $r |
  ([
    # Mean waves
    (if $r.wave_height != null then
      "🌊 " + ($r.wave_height | tostring) + ($units.wave_height // "m") +
      (if $r.wave_direction != null then " ←" + ($r.wave_direction | wind_dir) else "" end) +
      (if $r.wave_period != null then " " + ($r.wave_period | tostring) + "s" else "" end)
    else null end),
    # Wind waves
    (if $r.wind_wave_height != null then
      "💨 " + ($r.wind_wave_height | tostring) + ($units.wind_wave_height // "m") +
      (if $r.wind_wave_direction != null then " ←" + ($r.wind_wave_direction | wind_dir) else "" end)
    else null end),
    # Swell
    (if $r.swell_wave_height != null then
      "🏄 " + ($r.swell_wave_height | tostring) + ($units.swell_wave_height // "m") +
      (if $r.swell_wave_direction != null then " ←" + ($r.swell_wave_direction | wind_dir) else "" end)
    else null end),
    # SST
    (if $r.sea_surface_temperature != null then
      "🌡 " + ($r.sea_surface_temperature | tostring) + ($units.sea_surface_temperature // "°C")
    else null end),
    # Ocean current
    (if $r.ocean_current_velocity != null then
      "🌀 " + ($r.ocean_current_velocity | tostring) + ($units.ocean_current_velocity // "km/h") +
      (if $r.ocean_current_direction != null then " →" + ($r.ocean_current_direction | wind_dir) else "" end)
    else null end),
    # Sea level
    (if $r.sea_level_height_msl != null then
      "📏 " + ($r.sea_level_height_msl | tostring) + ($units.sea_level_height_msl // "m")
    else null end),
    # Remaining (secondary/tertiary swell, invert_barometer, etc.)
    ($r | to_entries | map(
      select(.key | IN(marine_known_keys[]) | not) |
      select(.value != null) |
      "\(.key | gsub("_"; " ")): \(.value)"
    ) | if length > 0 then join(", ") else null end)
  ] | map(select(. != null and . != "")) | join(" · ")) as $content |
  if ($content | length) > 0 then
    "   " + $D + $time + $R + "  " + $content
  else null end;

# Hourly section grouped by day (skips rows with all-null data)
def fmt_marine_hourly:
  if .hourly then
    .hourly_units as $units |
    zip_hourly | group_by(.time[:10]) |
    map(
      .[0].time[:10] as $date |
      (map(fmt_marine_hourly_row($units)) | map(select(. != null))) as $rows |
      if ($rows | length) > 0 then
        "\n" + $B + $CB + "📅 " + ($date | day_label) + $R + "\n" +
        ($rows | join("\n"))
      else
        "\n" + $B + $CB + "📅 " + ($date | day_label) + $R + "\n" +
        "   " + $D + "No marine data at this location" + $R
      end
    ) | join("\n")
  else "" end;

# Daily section
def fmt_marine_daily:
  if .daily then
    .daily_units as $units |
    zip_daily | map(
      .time as $date | . as $row |
      "\n" + $B + "📅 " + ($date | day_label) + $R +
      ([
        # Mean waves
        (if $row.wave_height_max != null then
          "🌊 max " + ($row.wave_height_max | tostring) + ($units.wave_height_max // "m") +
          (if $row.wave_direction_dominant != null then " ← " + ($row.wave_direction_dominant | wind_dir) else "" end) +
          (if $row.wave_period_max != null then " (period max " + ($row.wave_period_max | tostring) + "s)" else "" end)
        else null end),
        # Wind waves
        (if $row.wind_wave_height_max != null then
          "💨 Wind: max " + ($row.wind_wave_height_max | tostring) + ($units.wind_wave_height_max // "m") +
          (if $row.wind_wave_direction_dominant != null then " ← " + ($row.wind_wave_direction_dominant | wind_dir) else "" end) +
          (if $row.wind_wave_period_max != null then " (period max " + ($row.wind_wave_period_max | tostring) + "s" +
            (if $row.wind_wave_peak_period_max != null then ", peak " + ($row.wind_wave_peak_period_max | tostring) + "s" else "" end) + ")"
          else "" end)
        else null end),
        # Swell
        (if $row.swell_wave_height_max != null then
          "🏄 Swell: max " + ($row.swell_wave_height_max | tostring) + ($units.swell_wave_height_max // "m") +
          (if $row.swell_wave_direction_dominant != null then " ← " + ($row.swell_wave_direction_dominant | wind_dir) else "" end) +
          (if $row.swell_wave_period_max != null then " (period max " + ($row.swell_wave_period_max | tostring) + "s" +
            (if $row.swell_wave_peak_period_max != null then ", peak " + ($row.swell_wave_peak_period_max | tostring) + "s" else "" end) + ")"
          else "" end)
        else null end),
        # Remaining daily variables
        ($row | to_entries | map(
          select(.key | IN(marine_daily_known_keys[]) | not) |
          "\(.key | gsub("_"; " ")): \(.value // "—")"
        ) | if length > 0 then join(" · ") else null end)
      ] | map(select(. != null and . != "")) | map("   " + .) | join("\n"))
    ) | join("\n")
  else "" end;
MJQEOF

# ---------------------------------------------------------------------------
# Human-friendly output
# ---------------------------------------------------------------------------
_marine_output_human() {
  local json="$1" loc_name="${2:-}" loc_country="${3:-}"
  _init_colors

  echo "${json}" | jq -r \
    --arg name "${loc_name}" \
    --arg country "${loc_country}" \
    --arg B "${C_BOLD}" --arg D "${C_DIM}" \
    --arg R "${C_RESET}" --arg CB "${C_BLUE}" \
    "${JQ_LIB} ${MARINE_JQ_LIB}"'
    [ fmt_marine_loc($name; $country),
      fmt_marine_current,
      fmt_marine_hourly,
      fmt_marine_daily
    ] | map(select(. != null and . != "")) | join("\n")
    '
}

# ---------------------------------------------------------------------------
# LLM output
# ---------------------------------------------------------------------------
_marine_output_llm() {
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
_marine_output_porcelain() {
  local json="$1"
  echo "${json}" | jq -r "${JQ_LIB}"'
    [porcelain_meta, porcelain_current, porcelain_hourly, porcelain_daily] | .[]
  '
}

# ---------------------------------------------------------------------------
# Command entry point
# ---------------------------------------------------------------------------
cmd_marine() {
  # Handle 'help' subcommand
  if [[ "${1:-}" == "help" ]]; then
    shift; _marine_help_topic "$@"; return 0
  fi

  local lat="" lon="" city="" country=""
  local current="false" forecast_days="${DEFAULT_MARINE_FORECAST_DAYS}"
  local forecast_since=""
  local past_days="${DEFAULT_MARINE_PAST_DAYS}"
  local hourly_params="" daily_params="" current_params=""
  local length_unit="${DEFAULT_MARINE_LENGTH_UNIT}"
  local wind_speed_unit="${DEFAULT_MARINE_WIND_SPEED_UNIT}"
  local timezone="${DEFAULT_MARINE_TIMEZONE}"
  local model="" cell_selection=""
  local start_date="" end_date=""

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --lat=*)              lat=$(_extract_value "$1") ;;
      --lon=*)              lon=$(_extract_value "$1") ;;
      --city=*)             city=$(_extract_value "$1") ;;
      --country=*)          country=$(_extract_value "$1") ;;
      --current)            current="true" ;;
      --forecast-days=*)    forecast_days=$(_extract_value "$1") ;;
      --forecast-since=*)   forecast_since=$(_extract_value "$1") ;;
      --past-days=*)        past_days=$(_extract_value "$1") ;;
      --hourly-params=*)    hourly_params=$(_extract_value "$1") ;;
      --daily-params=*)     daily_params=$(_extract_value "$1") ;;
      --current-params=*)   current_params=$(_extract_value "$1") ;;
      --length-unit=*)      length_unit=$(_extract_value "$1") ;;
      --wind-speed-unit=*)  wind_speed_unit=$(_extract_value "$1") ;;
      --timezone=*)         timezone=$(_extract_value "$1") ;;
      --model=*)            model=$(_extract_value "$1") ;;
      --cell-selection=*)   cell_selection=$(_extract_value "$1") ;;
      --start-date=*)       start_date=$(_extract_value "$1") ;;
      --end-date=*)         end_date=$(_extract_value "$1") ;;
      --api-key=*)          API_KEY=$(_extract_value "$1") ;;
      --porcelain)          OUTPUT_FORMAT="porcelain" ;;
      --llm)                OUTPUT_FORMAT="llm" ;;
      --raw)                OUTPUT_FORMAT="raw" ;;
      --verbose)            OPENMETEO_VERBOSE="true" ;;
      --help)               _marine_help; return 0 ;;
      *)                    _die_usage "marine: unknown option: $1" ;;
    esac
    shift
  done

  _init_api_key

  # -----------------------------------------------------------------------
  # Validate inputs
  # -----------------------------------------------------------------------
  if [[ -n "${forecast_since}" ]]; then
    _validate_integer "--forecast-since" "${forecast_since}" 1
    if [[ -n "${start_date}" ]]; then
      _die "--forecast-since and --start-date are mutually exclusive"
    fi
  fi

  _validate_marine_inputs \
    "${lat}" "${lon}" "${forecast_days}" "${past_days}" \
    "${length_unit}" "${wind_speed_unit}" "${cell_selection}" \
    "${hourly_params}" "${daily_params}" "${current_params}" \
    "${model}" "${start_date}" "${end_date}"

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
    _marine_help >&2
    _die_usage "location required: use --lat/--lon or --city"
  fi

  # -----------------------------------------------------------------------
  # Determine what data to fetch
  # -----------------------------------------------------------------------
  local has_data_selection="false"
  if [[ "${current}" == "true" || -n "${hourly_params}" || -n "${daily_params}" || -n "${forecast_days}" || -n "${start_date}" ]]; then
    has_data_selection="true"
  fi

  if [[ "${current}" == "true" && -z "${current_params}" ]]; then
    current_params="${DEFAULT_MARINE_CURRENT_PARAMS}"
  fi

  if [[ -z "${hourly_params}" && -z "${daily_params}" ]]; then
    if [[ "${current}" == "true" && -z "${forecast_days}" && -z "${start_date}" && "${has_data_selection}" == "true" ]]; then
      : # current-only request
    else
      hourly_params="${DEFAULT_MARINE_HOURLY_PARAMS}"
    fi
  fi

  # -----------------------------------------------------------------------
  # Resolve --forecast-since into start_date/end_date
  # -----------------------------------------------------------------------
  if [[ -n "${forecast_since}" ]]; then
    _resolve_forecast_since "${forecast_since}" "${forecast_days}" 7
    start_date="${FORECAST_START_DATE}"
    end_date="${FORECAST_END_DATE}"
    forecast_days=""
  fi

  # -----------------------------------------------------------------------
  # Build query string
  # -----------------------------------------------------------------------
  local qs="latitude=${lat}&longitude=${lon}"

  [[ -n "${current_params}" ]]    && qs="${qs}&current=${current_params}"
  [[ -n "${hourly_params}" ]]     && qs="${qs}&hourly=${hourly_params}"
  [[ -n "${daily_params}" ]]      && qs="${qs}&daily=${daily_params}"
  [[ -n "${forecast_days}" ]]     && qs="${qs}&forecast_days=${forecast_days}"
  [[ -n "${past_days}" ]]         && qs="${qs}&past_days=${past_days}"
  [[ -n "${start_date}" ]]        && qs="${qs}&start_date=${start_date}"
  [[ -n "${end_date}" ]]          && qs="${qs}&end_date=${end_date}"
  [[ -n "${timezone}" ]]          && qs="${qs}&timezone=${timezone}"
  [[ -n "${length_unit}" ]]       && qs="${qs}&length_unit=${length_unit}"
  [[ -n "${wind_speed_unit}" ]]   && qs="${qs}&wind_speed_unit=${wind_speed_unit}"
  [[ -n "${model}" ]]             && qs="${qs}&models=${model}"
  [[ -n "${cell_selection}" ]]    && qs="${qs}&cell_selection=${cell_selection}"

  # -----------------------------------------------------------------------
  # Request + output
  # -----------------------------------------------------------------------
  local response
  response=$(_request "${BASE_URL_MARINE}" "${qs}")

  case "${OUTPUT_FORMAT}" in
    raw)       _output_raw "${response}" ;;
    porcelain) _marine_output_porcelain "${response}" ;;
    llm)       _marine_output_llm "${response}" "${loc_name}" "${loc_country}" ;;
    *)         _marine_output_human "${response}" "${loc_name}" "${loc_country}" ;;
  esac
}
