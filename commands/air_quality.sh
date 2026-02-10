#!/usr/bin/env bash
# commands/air_quality.sh -- Air Quality API subcommand

DEFAULT_AQ_FORECAST_DAYS=""  # omit = API default (5)
DEFAULT_AQ_PAST_DAYS=""
DEFAULT_AQ_TIMEZONE="auto"
DEFAULT_AQ_DOMAINS=""  # omit = API default (auto)

DEFAULT_AQ_CURRENT_PARAMS="european_aqi,us_aqi,pm10,pm2_5,carbon_monoxide,nitrogen_dioxide,sulphur_dioxide,ozone,uv_index,dust"
DEFAULT_AQ_HOURLY_PARAMS="pm10,pm2_5,european_aqi,us_aqi,ozone,nitrogen_dioxide,uv_index"

_aq_help() {
  cat <<EOF
openmeteo air-quality -- Air quality & pollen forecasts (Air Quality API)

Usage:
  openmeteo air-quality [options]

Location (required):
  --lat=NUM         Latitude (WGS84)
  --lon=NUM         Longitude (WGS84)
  --city=NAME       City name (resolved via Geocoding API)
  --country=CODE    Country filter for city resolution

Data selection:
  --current               Include current air quality conditions
  --forecast-days=N       Forecast length in days (0-7, default: 5)
  --past-days=N           Include past days (0-92)
  --hourly-params=LIST    Comma-separated hourly variables
  --current-params=LIST   Comma-separated current variables
  --start-date=DATE       Start date (YYYY-MM-DD)
  --end-date=DATE         End date (YYYY-MM-DD)

Settings:
  --domains=DOMAIN        auto (default), cams_europe, cams_global
  --timezone=TZ           IANA timezone or 'auto' (default: auto)
  --cell-selection=MODE   Grid cell selection: nearest (default), land, sea

Output:
  --porcelain             Machine-parseable key=value output
  --llm                   Compact TSV output for AI agents
  --raw                   Raw JSON from API
  --help                  Show this help

Hourly/current variables:
  Pollutants: pm10, pm2_5, carbon_monoxide, nitrogen_dioxide, sulphur_dioxide,
              ozone, carbon_dioxide, ammonia, methane
  Indices:    european_aqi, us_aqi, european_aqi_pm2_5, european_aqi_pm10,
              european_aqi_nitrogen_dioxide, european_aqi_ozone,
              european_aqi_sulphur_dioxide, us_aqi_pm2_5, us_aqi_pm10,
              us_aqi_nitrogen_dioxide, us_aqi_ozone, us_aqi_sulphur_dioxide,
              us_aqi_carbon_monoxide
  Other:      aerosol_optical_depth, dust, uv_index, uv_index_clear_sky
  Pollen:     alder_pollen, birch_pollen, grass_pollen, mugwort_pollen,
              olive_pollen, ragweed_pollen  (Europe only, seasonal)

Note: This API does NOT have daily variables. Use --hourly-params for time-series data.

Examples:
  openmeteo air-quality --current --city=Berlin
  openmeteo air-quality --forecast-days=3 --lat=52.52 --lon=13.41
  openmeteo air-quality --current --city=Paris \\
    --hourly-params=pm10,pm2_5,european_aqi,ozone
  openmeteo air-quality --current --city=London --porcelain
  openmeteo air-quality --current --city=Rome \\
    --current-params=european_aqi,pm10,pm2_5,alder_pollen,birch_pollen
EOF
}

# ---------------------------------------------------------------------------
# Input validation
# ---------------------------------------------------------------------------

_aq_param_suggestion() {
  local category="$1" param="$2"

  case "${category}" in
    hourly|current)
      case "${param}" in
        temperature_2m*|apparent_temperature*|wind_speed_10m*|wind_direction_10m*|wind_gusts_10m*|cloud_cover*|precipitation*|snowfall*|rain*|weather_code|is_day|sunrise|sunset|pressure_msl|surface_pressure|relative_humidity_2m*)
          echo "not available in Air Quality API. Use 'openmeteo weather' for weather data"
          ;;
        wave_height*|wave_direction*|wave_period*|swell_wave_*|ocean_current_*|sea_surface_temperature|sea_level_height_msl)
          echo "not available in Air Quality API. Use 'openmeteo marine' for marine data"
          ;;
      esac
      ;;
  esac
}

_validate_aq_params() {
  local category="$1" params_csv="$2"
  local has_error="false"

  local old_ifs="${IFS}"
  IFS=','
  for param in ${params_csv}; do
    [[ -z "${param}" ]] && continue
    local suggestion
    suggestion=$(_aq_param_suggestion "${category}" "${param}")
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

_validate_aq_inputs() {
  local lat="$1" lon="$2" forecast_days="$3" past_days="$4"
  local domains="$5" cell_selection="$6"
  local hourly_params="$7" current_params="$8"
  local daily_params="$9"
  local start_date="${10:-}" end_date="${11:-}"

  # Air Quality API has NO daily variables
  if [[ -n "${daily_params}" ]]; then
    _die "--daily-params: Air Quality API does not have daily variables. Use --hourly-params instead"
  fi

  # Numeric
  [[ -n "${lat}" ]] && _validate_number "--lat" "${lat}"
  [[ -n "${lon}" ]] && _validate_number "--lon" "${lon}"
  [[ -n "${forecast_days}" ]] && _validate_integer "--forecast-days" "${forecast_days}" 0 7
  [[ -n "${past_days}" ]]     && _validate_integer "--past-days" "${past_days}" 0 92

  # Enums
  [[ -n "${domains}" ]]        && _validate_enum "--domains" "${domains}" auto cams_europe cams_global
  [[ -n "${cell_selection}" ]] && _validate_enum "--cell-selection" "${cell_selection}" land sea nearest

  # Dates
  [[ -n "${start_date}" ]] && _validate_date "--start-date" "${start_date}"
  [[ -n "${end_date}" ]]   && _validate_date "--end-date" "${end_date}"
  if [[ -n "${start_date}" && -n "${end_date}" ]]; then
    if [[ "${start_date}" > "${end_date}" ]]; then
      _die "--start-date (${start_date}) must not be after --end-date (${end_date})"
    fi
  fi

  # Cross-category param validation
  [[ -n "${hourly_params}" ]]  && _validate_aq_params "hourly" "${hourly_params}"
  [[ -n "${current_params}" ]] && _validate_aq_params "current" "${current_params}"

  return 0
}

# ---------------------------------------------------------------------------
# Air Quality jq library
# ---------------------------------------------------------------------------
# shellcheck disable=SC2034
read -r -d '' AQ_JQ_LIB <<'AQJQEOF' || true

# European AQI quality text
def eu_aqi_text:
  if . == null then "?"
  elif . <= 20 then "Good"
  elif . <= 40 then "Fair"
  elif . <= 60 then "Moderate"
  elif . <= 80 then "Poor"
  elif . <= 100 then "Very poor"
  else "Extremely poor" end;

# US AQI quality text
def us_aqi_text:
  if . == null then "?"
  elif . <= 50 then "Good"
  elif . <= 100 then "Moderate"
  elif . <= 150 then "Unhealthy (sensitive)"
  elif . <= 200 then "Unhealthy"
  elif . <= 300 then "Very unhealthy"
  else "Hazardous" end;

# AQI emoji badges
def eu_aqi_emoji:
  if . == null then "❓"
  elif . <= 20 then "🟢"
  elif . <= 40 then "🟡"
  elif . <= 60 then "🟠"
  elif . <= 80 then "🔴"
  elif . <= 100 then "🟣"
  else "⛔" end;

def us_aqi_emoji:
  if . == null then "❓"
  elif . <= 50 then "🟢"
  elif . <= 100 then "🟡"
  elif . <= 150 then "🟠"
  elif . <= 200 then "🔴"
  elif . <= 300 then "🟣"
  else "⛔" end;

# Nice human-readable variable names
def aq_label:
  if . == "pm10" then "PM\u2081\u2080"
  elif . == "pm2_5" then "PM\u2082.\u2085"
  elif . == "carbon_monoxide" then "CO"
  elif . == "nitrogen_dioxide" then "NO\u2082"
  elif . == "sulphur_dioxide" then "SO\u2082"
  elif . == "ozone" then "O\u2083"
  elif . == "carbon_dioxide" then "CO\u2082"
  elif . == "ammonia" then "NH\u2083"
  elif . == "methane" then "CH\u2084"
  elif . == "uv_index" then "UV"
  elif . == "uv_index_clear_sky" then "UV\u2600"
  elif . == "dust" then "Dust"
  elif . == "aerosol_optical_depth" then "AOD"
  elif . == "european_aqi" then "EU AQI"
  elif . == "european_aqi_pm2_5" then "EU PM\u2082.\u2085"
  elif . == "european_aqi_pm10" then "EU PM\u2081\u2080"
  elif . == "european_aqi_nitrogen_dioxide" then "EU NO\u2082"
  elif . == "european_aqi_ozone" then "EU O\u2083"
  elif . == "european_aqi_sulphur_dioxide" then "EU SO\u2082"
  elif . == "us_aqi" then "US AQI"
  elif . == "us_aqi_pm2_5" then "US PM\u2082.\u2085"
  elif . == "us_aqi_pm10" then "US PM\u2081\u2080"
  elif . == "us_aqi_nitrogen_dioxide" then "US NO\u2082"
  elif . == "us_aqi_ozone" then "US O\u2083"
  elif . == "us_aqi_sulphur_dioxide" then "US SO\u2082"
  elif . == "us_aqi_carbon_monoxide" then "US CO"
  elif . == "alder_pollen" then "Alder\ud83c\udf3f"
  elif . == "birch_pollen" then "Birch\ud83c\udf3f"
  elif . == "grass_pollen" then "Grass\ud83c\udf3f"
  elif . == "mugwort_pollen" then "Mugwort\ud83c\udf3f"
  elif . == "olive_pollen" then "Olive\ud83c\udf3f"
  elif . == "ragweed_pollen" then "Ragweed\ud83c\udf3f"
  elif . == "formaldehyde" then "CH\u2082O"
  elif . == "nitrogen_monoxide" then "NO"
  elif . == "peroxyacyl_nitrates" then "PAN"
  elif . == "non_methane_volatile_organic_compounds" then "NMVOC"
  elif . == "pm10_wildfires" then "PM\u2081\u2080\ud83d\udd25"
  elif . == "sea_salt_aerosol" then "Sea salt"
  else (. | gsub("_"; " ")) end;

# Keys handled by smart formatting in current section
def aq_current_known_keys:
  ["time","interval",
   "european_aqi","us_aqi",
   "pm10","pm2_5",
   "carbon_monoxide","nitrogen_dioxide","sulphur_dioxide","ozone",
   "carbon_dioxide","ammonia","methane",
   "uv_index","uv_index_clear_sky","dust","aerosol_optical_depth",
   "alder_pollen","birch_pollen","grass_pollen","mugwort_pollen","olive_pollen","ragweed_pollen",
   "european_aqi_pm2_5","european_aqi_pm10","european_aqi_nitrogen_dioxide","european_aqi_ozone","european_aqi_sulphur_dioxide",
   "us_aqi_pm2_5","us_aqi_pm10","us_aqi_nitrogen_dioxide","us_aqi_ozone","us_aqi_sulphur_dioxide","us_aqi_carbon_monoxide"];

# Keys that get compact formatting in hourly rows
def aq_hourly_known_keys:
  ["time",
   "european_aqi","us_aqi",
   "pm10","pm2_5",
   "ozone","nitrogen_dioxide","carbon_monoxide","sulphur_dioxide",
   "uv_index"];

# Format current air quality conditions
def fmt_aq_current:
  if .current then
    .current as $c | .current_units as $u |
    ($c | to_entries | map(select(.key | IN("time","interval") | not) | select(.value != null)) | length) as $nvals |
    "\n" + $B + "💨 Air Quality" + $R + " — \($c.time // "now")\n" +
    if $nvals == 0 then
      "\n   " + $D + "No air quality data at this location" + $R
    else
      # AQI indices (prominent)
      (if $c.european_aqi != null then
        "\n   " + ($c.european_aqi | eu_aqi_emoji) + " EU AQI: " + $B + "\($c.european_aqi)" + $R + " — " + ($c.european_aqi | eu_aqi_text)
      else "" end) +
      (if $c.us_aqi != null then
        "\n   " + ($c.us_aqi | us_aqi_emoji) + " US AQI: " + $B + "\($c.us_aqi)" + $R + " — " + ($c.us_aqi | us_aqi_text)
      else "" end) +
      # Particulate matter
      (([
        (if $c.pm10 != null then "PM\u2081\u2080 \($c.pm10) \($u.pm10 // "\u03bcg/m\u00b3")" else null end),
        (if $c.pm2_5 != null then "PM\u2082.\u2085 \($c.pm2_5) \($u.pm2_5 // "\u03bcg/m\u00b3")" else null end)
      ] | map(select(. != null))) as $pm |
      if ($pm | length) > 0 then "\n   " + ($pm | join(" \u00b7 ")) else "" end) +
      # Primary gases
      (([
        (if $c.ozone != null then "O\u2083 \($c.ozone) \($u.ozone // "\u03bcg/m\u00b3")" else null end),
        (if $c.nitrogen_dioxide != null then "NO\u2082 \($c.nitrogen_dioxide) \($u.nitrogen_dioxide // "\u03bcg/m\u00b3")" else null end),
        (if $c.carbon_monoxide != null then "CO \($c.carbon_monoxide) \($u.carbon_monoxide // "\u03bcg/m\u00b3")" else null end),
        (if $c.sulphur_dioxide != null then "SO\u2082 \($c.sulphur_dioxide) \($u.sulphur_dioxide // "\u03bcg/m\u00b3")" else null end)
      ] | map(select(. != null))) as $gases |
      if ($gases | length) > 0 then "\n   " + ($gases | join(" \u00b7 ")) else "" end) +
      # Secondary gases (CO2, NH3, CH4)
      (([
        (if $c.carbon_dioxide != null then "CO\u2082 \($c.carbon_dioxide) \($u.carbon_dioxide // "ppm")" else null end),
        (if $c.ammonia != null then "NH\u2083 \($c.ammonia) \($u.ammonia // "\u03bcg/m\u00b3")" else null end),
        (if $c.methane != null then "CH\u2084 \($c.methane) \($u.methane // "\u03bcg/m\u00b3")" else null end)
      ] | map(select(. != null))) as $sec |
      if ($sec | length) > 0 then "\n   " + ($sec | join(" \u00b7 ")) else "" end) +
      # UV + dust + AOD
      (([
        (if $c.uv_index != null then "\u2600\ufe0f  UV \($c.uv_index)" +
          (if $c.uv_index_clear_sky != null then " (clear sky: \($c.uv_index_clear_sky))" else "" end)
        else null end),
        (if $c.dust != null then "Dust \($c.dust) \($u.dust // "\u03bcg/m\u00b3")" else null end),
        (if $c.aerosol_optical_depth != null then "AOD \($c.aerosol_optical_depth)" else null end)
      ] | map(select(. != null))) as $other |
      if ($other | length) > 0 then "\n   " + ($other | join(" \u00b7 ")) else "" end) +
      # Pollen
      (([
        (if $c.alder_pollen != null then "Alder \($c.alder_pollen)" else null end),
        (if $c.birch_pollen != null then "Birch \($c.birch_pollen)" else null end),
        (if $c.grass_pollen != null then "Grass \($c.grass_pollen)" else null end),
        (if $c.mugwort_pollen != null then "Mugwort \($c.mugwort_pollen)" else null end),
        (if $c.olive_pollen != null then "Olive \($c.olive_pollen)" else null end),
        (if $c.ragweed_pollen != null then "Ragweed \($c.ragweed_pollen)" else null end)
      ] | map(select(. != null))) as $pollen |
      if ($pollen | length) > 0 then "\n   \ud83c\udf3f Pollen (grains/m\u00b3): " + ($pollen | join(" \u00b7 ")) else "" end) +
      # EU AQI breakdown
      (([
        (if $c.european_aqi_pm2_5 != null then "PM\u2082.\u2085:\($c.european_aqi_pm2_5)" else null end),
        (if $c.european_aqi_pm10 != null then "PM\u2081\u2080:\($c.european_aqi_pm10)" else null end),
        (if $c.european_aqi_nitrogen_dioxide != null then "NO\u2082:\($c.european_aqi_nitrogen_dioxide)" else null end),
        (if $c.european_aqi_ozone != null then "O\u2083:\($c.european_aqi_ozone)" else null end),
        (if $c.european_aqi_sulphur_dioxide != null then "SO\u2082:\($c.european_aqi_sulphur_dioxide)" else null end)
      ] | map(select(. != null))) as $eu_sub |
      if ($eu_sub | length) > 0 then "\n   " + $D + "EU breakdown: " + ($eu_sub | join(" \u00b7 ")) + $R else "" end) +
      # US AQI breakdown
      (([
        (if $c.us_aqi_pm2_5 != null then "PM\u2082.\u2085:\($c.us_aqi_pm2_5)" else null end),
        (if $c.us_aqi_pm10 != null then "PM\u2081\u2080:\($c.us_aqi_pm10)" else null end),
        (if $c.us_aqi_nitrogen_dioxide != null then "NO\u2082:\($c.us_aqi_nitrogen_dioxide)" else null end),
        (if $c.us_aqi_ozone != null then "O\u2083:\($c.us_aqi_ozone)" else null end),
        (if $c.us_aqi_sulphur_dioxide != null then "SO\u2082:\($c.us_aqi_sulphur_dioxide)" else null end),
        (if $c.us_aqi_carbon_monoxide != null then "CO:\($c.us_aqi_carbon_monoxide)" else null end)
      ] | map(select(. != null))) as $us_sub |
      if ($us_sub | length) > 0 then "\n   " + $D + "US breakdown: " + ($us_sub | join(" \u00b7 ")) + $R else "" end) +
      # Remaining unknown keys
      ($c | to_entries | map(
        select(.key | IN(aq_current_known_keys[]) | not) |
        select(.value != null) |
        "\n   \(.key | aq_label): \(.value)"
      ) | join(""))
    end
  else "" end;

# Format one hourly row (returns null if all values are null)
def fmt_aq_hourly_row($units):
  .time[11:16] as $time |
  . as $r |
  ([
    # AQI badges (compact)
    (if $r.european_aqi != null then
      ($r.european_aqi | eu_aqi_emoji) + "\($r.european_aqi)EU"
    else null end),
    (if $r.us_aqi != null then
      ($r.us_aqi | us_aqi_emoji) + "\($r.us_aqi)US"
    else null end),
    # PM
    (if $r.pm10 != null then "PM\u2081\u2080 \($r.pm10)" else null end),
    (if $r.pm2_5 != null then "PM\u2082.\u2085 \($r.pm2_5)" else null end),
    # Key gases
    (if $r.ozone != null then "O\u2083 \($r.ozone)" else null end),
    (if $r.nitrogen_dioxide != null then "NO\u2082 \($r.nitrogen_dioxide)" else null end),
    (if $r.carbon_monoxide != null then "CO \($r.carbon_monoxide)" else null end),
    (if $r.sulphur_dioxide != null then "SO\u2082 \($r.sulphur_dioxide)" else null end),
    # UV
    (if $r.uv_index != null then "UV \($r.uv_index)" else null end),
    # Remaining (pollen, sub-AQIs, other)
    ($r | to_entries | map(
      select(.key | IN(aq_hourly_known_keys[]) | not) |
      select(.value != null) |
      "\(.key | aq_label) \(.value)"
    ) | if length > 0 then join(" \u00b7 ") else null end)
  ] | map(select(. != null and . != "")) | join(" \u00b7 ")) as $content |
  if ($content | length) > 0 then
    "   " + $D + $time + $R + "  " + $content
  else null end;

# Hourly section grouped by day
def fmt_aq_hourly:
  if .hourly then
    .hourly_units as $units |
    zip_hourly | group_by(.time[:10]) |
    map(
      .[0].time[:10] as $date |
      (map(fmt_aq_hourly_row($units)) | map(select(. != null))) as $rows |
      if ($rows | length) > 0 then
        "\n" + $B + $CB + "\ud83d\udcc5 " + ($date | day_label) + $R + "\n" +
        ($rows | join("\n"))
      else
        "\n" + $B + $CB + "\ud83d\udcc5 " + ($date | day_label) + $R + "\n" +
        "   " + $D + "No air quality data" + $R
      end
    ) | join("\n")
  else "" end;

AQJQEOF

# ---------------------------------------------------------------------------
# Human-friendly output
# ---------------------------------------------------------------------------
_aq_output_human() {
  local json="$1" loc_name="${2:-}" loc_country="${3:-}"
  _init_colors

  echo "${json}" | jq -r \
    --arg name "${loc_name}" \
    --arg country "${loc_country}" \
    --arg B "${C_BOLD}" --arg D "${C_DIM}" \
    --arg R "${C_RESET}" --arg CB "${C_BLUE}" \
    "${JQ_LIB} ${AQ_JQ_LIB}"'
    [ fmt_loc_header($name; $country),
      fmt_aq_current,
      fmt_aq_hourly
    ] | map(select(. != null and . != "")) | join("\n")
    '
}

# ---------------------------------------------------------------------------
# LLM output
# ---------------------------------------------------------------------------
_aq_output_llm() {
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
    llm_hourly
  '
}

# ---------------------------------------------------------------------------
# Porcelain output
# ---------------------------------------------------------------------------
_aq_output_porcelain() {
  local json="$1"
  echo "${json}" | jq -r "${JQ_LIB}"'
    [porcelain_meta, porcelain_current, porcelain_hourly] | .[]
  '
}

# ---------------------------------------------------------------------------
# Command entry point
# ---------------------------------------------------------------------------
cmd_air_quality() {
  local lat="" lon="" city="" country=""
  local current="false" forecast_days="${DEFAULT_AQ_FORECAST_DAYS}"
  local past_days="${DEFAULT_AQ_PAST_DAYS}"
  local hourly_params="" daily_params="" current_params=""
  local domains="${DEFAULT_AQ_DOMAINS}"
  local timezone="${DEFAULT_AQ_TIMEZONE}"
  local cell_selection=""
  local start_date="" end_date=""

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
      --domains=*)          domains=$(_extract_value "$1") ;;
      --timezone=*)         timezone=$(_extract_value "$1") ;;
      --cell-selection=*)   cell_selection=$(_extract_value "$1") ;;
      --start-date=*)       start_date=$(_extract_value "$1") ;;
      --end-date=*)         end_date=$(_extract_value "$1") ;;
      --api-key=*)          API_KEY=$(_extract_value "$1") ;;
      --porcelain)          OUTPUT_FORMAT="porcelain" ;;
      --llm)                OUTPUT_FORMAT="llm" ;;
      --raw)                OUTPUT_FORMAT="raw" ;;
      --verbose)            OPENMETEO_VERBOSE="true" ;;
      --help)               _aq_help; return 0 ;;
      *)                    _die_usage "air-quality: unknown option: $1" ;;
    esac
    shift
  done

  _init_api_key

  # -----------------------------------------------------------------------
  # Validate inputs
  # -----------------------------------------------------------------------
  _validate_aq_inputs \
    "${lat}" "${lon}" "${forecast_days}" "${past_days}" \
    "${domains}" "${cell_selection}" \
    "${hourly_params}" "${current_params}" "${daily_params}" \
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
    _aq_help >&2
    _die_usage "location required: use --lat/--lon or --city"
  fi

  # -----------------------------------------------------------------------
  # Determine what data to fetch
  # -----------------------------------------------------------------------
  local has_data_selection="false"
  if [[ "${current}" == "true" || -n "${hourly_params}" || -n "${forecast_days}" || -n "${start_date}" ]]; then
    has_data_selection="true"
  fi

  if [[ "${current}" == "true" && -z "${current_params}" ]]; then
    current_params="${DEFAULT_AQ_CURRENT_PARAMS}"
  fi

  if [[ -z "${hourly_params}" ]]; then
    if [[ "${current}" == "true" && -z "${forecast_days}" && -z "${start_date}" && "${has_data_selection}" == "true" ]]; then
      : # current-only request
    else
      hourly_params="${DEFAULT_AQ_HOURLY_PARAMS}"
    fi
  fi

  # -----------------------------------------------------------------------
  # Build query string
  # -----------------------------------------------------------------------
  local qs="latitude=${lat}&longitude=${lon}"

  [[ -n "${current_params}" ]]    && qs="${qs}&current=${current_params}"
  [[ -n "${hourly_params}" ]]     && qs="${qs}&hourly=${hourly_params}"
  [[ -n "${forecast_days}" ]]     && qs="${qs}&forecast_days=${forecast_days}"
  [[ -n "${past_days}" ]]         && qs="${qs}&past_days=${past_days}"
  [[ -n "${start_date}" ]]        && qs="${qs}&start_date=${start_date}"
  [[ -n "${end_date}" ]]          && qs="${qs}&end_date=${end_date}"
  [[ -n "${timezone}" ]]          && qs="${qs}&timezone=${timezone}"
  [[ -n "${domains}" ]]           && qs="${qs}&domains=${domains}"
  [[ -n "${cell_selection}" ]]    && qs="${qs}&cell_selection=${cell_selection}"

  # -----------------------------------------------------------------------
  # Request + output
  # -----------------------------------------------------------------------
  local response
  response=$(_request "${BASE_URL_AIR_QUALITY}" "${qs}")

  case "${OUTPUT_FORMAT}" in
    raw)       _output_raw "${response}" ;;
    porcelain) _aq_output_porcelain "${response}" ;;
    llm)       _aq_output_llm "${response}" "${loc_name}" "${loc_country}" ;;
    *)         _aq_output_human "${response}" "${loc_name}" "${loc_country}" ;;
  esac
}
