#!/usr/bin/env bash
# commands/flood.sh -- Flood API subcommand (GloFAS river discharge)

DEFAULT_FLOOD_FORECAST_DAYS=""   # omit = API default (92)
DEFAULT_FLOOD_PAST_DAYS=""
DEFAULT_FLOOD_MODEL=""           # omit = API default (seamless_v4)
DEFAULT_FLOOD_DAILY_PARAMS="river_discharge"

# Verified model slugs (tested against live API)
FLOOD_VALID_MODELS=(
  seamless_v4
  forecast_v4
  consolidated_v4
  seamless_v3
  forecast_v3
  consolidated_v3
)

_flood_help() {
  cat <<EOF
openmeteo flood -- River discharge / flood forecasts (GloFAS Flood API)

Usage:
  openmeteo flood [options]

Location (required):
  --lat=NUM         Latitude (WGS84)
  --lon=NUM         Longitude (WGS84)
  --city=NAME       City name (resolved via Geocoding API)
  --country=CODE    Country filter for city resolution

Data selection:
  --forecast-days=N       Forecast length in days (0-210, default: 92)
  --past-days=N           Include past days of archived forecasts
  --daily-params=LIST     Comma-separated daily variables
  --start-date=DATE       Start date (YYYY-MM-DD, from 1984-01-01)
  --end-date=DATE         End date (YYYY-MM-DD, up to ~7 months ahead)
  --ensemble              Return all 50 ensemble members

Model:
  --model=MODEL     GloFAS model version (default: seamless_v4)
                    Models: seamless_v4, forecast_v4, consolidated_v4,
                    seamless_v3, forecast_v3, consolidated_v3

Other:
  --cell-selection=MODE   Grid cell selection: nearest (default), land, sea
  --porcelain             Machine-parseable key=value output
  --llm                   Compact TSV output for AI agents
  --raw                   Raw JSON from API
  --help                  Show this help

Daily variables:
  river_discharge          Daily river discharge rate (m³/s)
  river_discharge_mean     Mean from ensemble members
  river_discharge_median   Median from ensemble members
  river_discharge_max      Maximum from ensemble members
  river_discharge_min      Minimum from ensemble members
  river_discharge_p25      25th percentile from ensemble members
  river_discharge_p75      75th percentile from ensemble members

Note: Statistical variables (mean/median/max/min/p25/p75) are only available
for forecasts, not for consolidated historical data. Use --ensemble to get
all 50 individual ensemble members.

The API uses a 5 km grid -- the closest river may not be selected correctly.
Varying coordinates by ±0.1° can help find a more representative discharge.

Examples:
  openmeteo flood --lat=59.91 --lon=10.75
  openmeteo flood --city=Oslo --forecast-days=30
  openmeteo flood --lat=48.85 --lon=2.35 \\
    --daily-params=river_discharge,river_discharge_mean,river_discharge_max
  openmeteo flood --city=London --past-days=30 --forecast-days=7
  openmeteo flood --lat=59.91 --lon=10.75 --ensemble
  openmeteo flood --lat=59.91 --lon=10.75 \\
    --start-date=2024-01-01 --end-date=2024-03-31
  openmeteo flood --city=Oslo --porcelain
EOF
}

# ---------------------------------------------------------------------------
# Input validation
# ---------------------------------------------------------------------------

_flood_param_suggestion() {
  local param="$1"

  case "${param}" in
    # Hourly-style weather variables → wrong API
    temperature_2m*|apparent_temperature*|wind_speed_10m*|wind_direction_10m*|cloud_cover*|precipitation*|snowfall*|rain*|weather_code|is_day|sunrise|sunset|pressure_msl|surface_pressure|relative_humidity_2m*)
      echo "not available in the Flood API. Use 'openmeteo weather' or 'openmeteo history' for weather data"
      ;;
    # Marine variables → wrong API
    wave_height*|wave_direction*|wave_period*|swell_wave_*|ocean_current_*|sea_surface_temperature|sea_level_height_msl)
      echo "not available in the Flood API. Use 'openmeteo marine' for marine data"
      ;;
    # Air quality variables → wrong API
    pm10|pm2_5|european_aqi|us_aqi|ozone|nitrogen_dioxide|carbon_monoxide|sulphur_dioxide|dust|uv_index*)
      echo "not available in the Flood API. Use 'openmeteo air-quality' for air quality data"
      ;;
    # Correct base name used without proper suffix
    river_discharge_average|river_discharge_avg)
      echo "not a valid variable. Use 'river_discharge_mean'"
      ;;
  esac
}

_validate_flood_params() {
  local params_csv="$1"
  local has_error="false"

  local old_ifs="${IFS}"
  IFS=','
  for param in ${params_csv}; do
    [[ -z "${param}" ]] && continue
    local suggestion
    suggestion=$(_flood_param_suggestion "${param}")
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

_validate_flood_models() {
  local models_csv="$1"
  local valid_list
  valid_list=$(printf '%s, ' "${FLOOD_VALID_MODELS[@]}")

  local old_ifs="${IFS}"
  IFS=','
  for model in ${models_csv}; do
    [[ -z "${model}" ]] && continue
    local found="false"
    local m
    for m in "${FLOOD_VALID_MODELS[@]}"; do
      if [[ "${model}" == "${m}" ]]; then
        found="true"
        break
      fi
    done
    if [[ "${found}" == "false" ]]; then
      _die "--model: '${model}' is not a valid flood model. Valid models: ${valid_list%, }"
    fi
  done
  IFS="${old_ifs}"
}

_validate_flood_inputs() {
  local lat="$1" lon="$2" forecast_days="$3" past_days="$4"
  local cell_selection="$5" daily_params="$6" model="$7"
  local start_date="$8" end_date="$9"

  # Numeric
  [[ -n "${lat}" ]] && _validate_number "--lat" "${lat}"
  [[ -n "${lon}" ]] && _validate_number "--lon" "${lon}"
  [[ -n "${forecast_days}" ]] && _validate_integer "--forecast-days" "${forecast_days}" 0 210
  [[ -n "${past_days}" ]]     && _validate_integer "--past-days" "${past_days}" 0

  # Enums
  [[ -n "${cell_selection}" ]] && _validate_enum "--cell-selection" "${cell_selection}" nearest land sea

  # Dates
  [[ -n "${start_date}" ]] && _validate_date "--start-date" "${start_date}"
  [[ -n "${end_date}" ]]   && _validate_date "--end-date" "${end_date}"
  if [[ -n "${start_date}" && -n "${end_date}" ]]; then
    if [[ "${start_date}" > "${end_date}" ]]; then
      _die "--start-date (${start_date}) must not be after --end-date (${end_date})"
    fi
  fi

  # Cross-category param validation
  [[ -n "${daily_params}" ]] && _validate_flood_params "${daily_params}"

  # Model validation
  [[ -n "${model}" ]] && _validate_flood_models "${model}"

  return 0
}

# ---------------------------------------------------------------------------
# Flood-specific jq library
# ---------------------------------------------------------------------------
# shellcheck disable=SC2034
read -r -d '' FLOOD_JQ_LIB <<'FLOODJQEOF' || true

# Flood severity classification based on river discharge magnitude
def flood_severity_emoji($val):
  if $val == null then "❓"
  elif $val <= 0 then "🏜️"
  elif $val < 10 then "🟢"
  elif $val < 100 then "🟡"
  elif $val < 500 then "🟠"
  elif $val < 1000 then "🔴"
  else "🟣" end;

def flood_severity_text($val):
  if $val == null then "No data"
  elif $val <= 0 then "Dry"
  elif $val < 10 then "Low"
  elif $val < 100 then "Moderate"
  elif $val < 500 then "High"
  elif $val < 1000 then "Very high"
  else "Extreme" end;

# Flood location header (river emoji)
def fmt_flood_loc($name; $country):
  "🌊 " +
  (if $name != "" then
    "\($name)" + (if $country != "" then ", \($country)" else "" end) + " · "
  else "" end) +
  "\(.latitude | round2)°\(if .latitude >= 0 then "N" else "S" end), " +
  "\(.longitude | abs | round2)°\(if .longitude >= 0 then "E" else "W" end)" +
  (if .elevation then "\n   Elevation: \(.elevation)m" else "" end);

# Known daily keys for smart formatting
def flood_daily_known_keys:
  ["time",
   "river_discharge",
   "river_discharge_mean","river_discharge_median",
   "river_discharge_max","river_discharge_min",
   "river_discharge_p25","river_discharge_p75"];

# Detect if response contains ensemble members (river_discharge_member01...)
def has_ensemble_members:
  .daily | keys | map(select(startswith("river_discharge_member"))) | length > 0;

# Get ensemble member count
def ensemble_member_count:
  .daily | keys | map(select(startswith("river_discharge_member"))) | length;

# Compute ensemble stats for a given time index
def ensemble_stats($i):
  .daily as $d |
  ($d | keys | map(select(startswith("river_discharge_member"))) |
    map($d[.][$i]) | map(select(. != null))) as $vals |
  if ($vals | length) == 0 then null
  else
    ($vals | sort) as $sorted |
    ($sorted | length) as $n |
    ($sorted | add / $n) as $mean |
    ($sorted[0]) as $min |
    ($sorted[$n - 1]) as $max |
    (if $n % 2 == 0 then ($sorted[$n/2 - 1] + $sorted[$n/2]) / 2
     else $sorted[($n - 1) / 2] end) as $median |
    ($sorted[(($n * 0.25) | floor)]) as $p25 |
    ($sorted[(($n * 0.75) | floor)]) as $p75 |
    { mean: ($mean * 100 | round / 100),
      median: ($median * 100 | round / 100),
      min: $min, max: $max,
      p25: ($p25 * 100 | round / 100),
      p75: ($p75 * 100 | round / 100),
      count: $n }
  end;

# Format one daily row
def fmt_flood_daily_row($units):
  .time as $date |
  . as $row |
  $B + "📅 " + ($date | day_label) + $R + "\n" +
  (
    # Check if any data is present (all river_discharge* fields)
    ($row | to_entries | map(select(.key != "time" and .value != null)) | length) as $nvals |
    if $nvals == 0 then
      "   " + $D + "No river data at this location" + $R
    else
      ([
        # Main discharge
        (if $row.river_discharge != null then
          "   " + flood_severity_emoji($row.river_discharge) +
          " Discharge: " + $B + "\($row.river_discharge) " + ($units.river_discharge // "m³/s") + $R +
          " — " + flood_severity_text($row.river_discharge)
        else null end),
        # Statistical summary (when stats variables are present)
        (if $row.river_discharge_mean != null or $row.river_discharge_median != null then
          "   📊 " +
          ([
            (if $row.river_discharge_mean != null then
              "mean: \($row.river_discharge_mean)" else null end),
            (if $row.river_discharge_median != null then
              "median: \($row.river_discharge_median)" else null end),
            (if $row.river_discharge_min != null and $row.river_discharge_max != null then
              "range: \($row.river_discharge_min)–\($row.river_discharge_max)" else null end),
            (if $row.river_discharge_p25 != null and $row.river_discharge_p75 != null then
              "IQR: \($row.river_discharge_p25)–\($row.river_discharge_p75)" else null end)
          ] | map(select(. != null)) | join(" · ")) +
          " " + ($units.river_discharge // "m³/s")
        else null end),
        # Remaining unknown keys (ensemble members when present, etc.)
        ($row | to_entries | map(
          select(.key | IN(flood_daily_known_keys[]) | not) |
          select(.value != null) |
          "   \(.key | gsub("_"; " ")): \(.value) \($units[.key] // "")"
        ) | if length > 0 then
          if length > 10 then
            # Collapse many ensemble members into a summary
            (map(select(. | test("member"))) | length) as $nmembers |
            if $nmembers > 0 then
              "   👥 \($nmembers) ensemble members present (use --raw or --porcelain for full data)"
            else
              join("\n")
            end
          else
            join("\n")
          end
        else null end)
      ] | map(select(. != null and . != "")) | join("\n"))
    end
  );

# Format entire daily section
def fmt_flood_daily:
  if .daily then
    .daily_units as $units |
    # Check for ensemble members
    (has_ensemble_members) as $is_ensemble |
    (if $is_ensemble then ensemble_member_count else 0 end) as $nmembers |
    (if $is_ensemble then
      "\n" + $D + "📋 Ensemble: \($nmembers) members" + $R + "\n"
    else "" end) +
    (zip_daily | map(fmt_flood_daily_row($units)) | join("\n\n"))
  else "" end;

FLOODJQEOF

# ---------------------------------------------------------------------------
# Human-friendly output
# ---------------------------------------------------------------------------
_flood_output_human() {
  local json="$1" loc_name="${2:-}" loc_country="${3:-}"
  _init_colors

  echo "${json}" | jq -r \
    --arg name "${loc_name}" \
    --arg country "${loc_country}" \
    --arg B "${C_BOLD}" --arg D "${C_DIM}" \
    --arg R "${C_RESET}" --arg CB "${C_BLUE}" \
    "${JQ_LIB} ${FLOOD_JQ_LIB}"'
    [ fmt_flood_loc($name; $country),
      fmt_flood_daily
    ] | map(select(. != null and . != "")) | join("\n")
    '
}

# ---------------------------------------------------------------------------
# LLM output
# ---------------------------------------------------------------------------
_flood_output_llm() {
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
_flood_output_porcelain() {
  local json="$1"
  echo "${json}" | jq -r "${JQ_LIB}"'
    [porcelain_meta, porcelain_daily] | .[]
  '
}

# ---------------------------------------------------------------------------
# Command entry point
# ---------------------------------------------------------------------------
cmd_flood() {
  local lat="" lon="" city="" country=""
  local forecast_days="${DEFAULT_FLOOD_FORECAST_DAYS}"
  local past_days="${DEFAULT_FLOOD_PAST_DAYS}"
  local daily_params="" model="${DEFAULT_FLOOD_MODEL}"
  local cell_selection="" ensemble="false"
  local start_date="" end_date=""

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --lat=*)              lat=$(_extract_value "$1") ;;
      --lon=*)              lon=$(_extract_value "$1") ;;
      --city=*)             city=$(_extract_value "$1") ;;
      --country=*)          country=$(_extract_value "$1") ;;
      --forecast-days=*)    forecast_days=$(_extract_value "$1") ;;
      --past-days=*)        past_days=$(_extract_value "$1") ;;
      --daily-params=*)     daily_params=$(_extract_value "$1") ;;
      --model=*)            model=$(_extract_value "$1") ;;
      --cell-selection=*)   cell_selection=$(_extract_value "$1") ;;
      --ensemble)           ensemble="true" ;;
      --start-date=*)       start_date=$(_extract_value "$1") ;;
      --end-date=*)         end_date=$(_extract_value "$1") ;;
      --api-key=*)          API_KEY=$(_extract_value "$1") ;;
      --porcelain)          OUTPUT_FORMAT="porcelain" ;;
      --llm)                OUTPUT_FORMAT="llm" ;;
      --raw)                OUTPUT_FORMAT="raw" ;;
      --verbose)            OPENMETEO_VERBOSE="true" ;;
      --help)               _flood_help; return 0 ;;
      *)                    _die_usage "flood: unknown option: $1" ;;
    esac
    shift
  done

  _init_api_key

  # -----------------------------------------------------------------------
  # Validate inputs
  # -----------------------------------------------------------------------
  _validate_flood_inputs \
    "${lat}" "${lon}" "${forecast_days}" "${past_days}" \
    "${cell_selection}" "${daily_params}" "${model}" \
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
    _flood_help >&2
    _die_usage "location required: use --lat/--lon or --city"
  fi

  # -----------------------------------------------------------------------
  # Defaults
  # -----------------------------------------------------------------------
  if [[ -z "${daily_params}" ]]; then
    daily_params="${DEFAULT_FLOOD_DAILY_PARAMS}"
  fi

  # -----------------------------------------------------------------------
  # Build query string
  # -----------------------------------------------------------------------
  local qs="latitude=${lat}&longitude=${lon}"

  [[ -n "${daily_params}" ]]    && qs="${qs}&daily=${daily_params}"
  [[ -n "${forecast_days}" ]]   && qs="${qs}&forecast_days=${forecast_days}"
  [[ -n "${past_days}" ]]       && qs="${qs}&past_days=${past_days}"
  [[ -n "${start_date}" ]]      && qs="${qs}&start_date=${start_date}"
  [[ -n "${end_date}" ]]        && qs="${qs}&end_date=${end_date}"
  [[ -n "${model}" ]]           && qs="${qs}&models=${model}"
  [[ -n "${cell_selection}" ]]  && qs="${qs}&cell_selection=${cell_selection}"

  if [[ "${ensemble}" == "true" ]]; then
    qs="${qs}&ensemble=true"
  fi

  # -----------------------------------------------------------------------
  # Request + output
  # -----------------------------------------------------------------------
  local response
  response=$(_request "${BASE_URL_FLOOD}" "${qs}")

  case "${OUTPUT_FORMAT}" in
    raw)       _output_raw "${response}" ;;
    porcelain) _flood_output_porcelain "${response}" ;;
    llm)       _flood_output_llm "${response}" "${loc_name}" "${loc_country}" ;;
    *)         _flood_output_human "${response}" "${loc_name}" "${loc_country}" ;;
  esac
}
