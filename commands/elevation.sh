#!/usr/bin/env bash
# commands/elevation.sh -- Elevation API subcommand

# ---------------------------------------------------------------------------
# Help
# ---------------------------------------------------------------------------

_elevation_help() {
  cat <<EOF
openmeteo elevation -- Terrain elevation lookup (Copernicus DEM, 90 m resolution)

Usage:
  openmeteo elevation [options]

Location (required — pick one):
  --lat=NUM         Latitude (WGS84, -90 to 90)
  --lon=NUM         Longitude (WGS84, -180 to 180)
  --city=NAME       City name (resolved via Geocoding API)
  --country=CODE    Country filter for city resolution

Multiple coordinates:
  --lat=NUM,NUM,... --lon=NUM,NUM,...
  Up to 100 coordinate pairs per request.
  Latitude and longitude lists must have the same number of elements.

Output:
  --porcelain       Machine-parseable key=value output
  --raw             Raw JSON from API
  --help            Show this help

Examples:
  openmeteo elevation --lat=47.37 --lon=8.55
  openmeteo elevation --city=Zurich
  openmeteo elevation --lat=52.52,48.85,59.91 --lon=13.41,2.35,10.75
  openmeteo elevation --city=London --porcelain
  openmeteo elevation --lat=27.9881,86.9250 --lon=86.9250,27.9881 --raw
EOF
}

# ---------------------------------------------------------------------------
# Input validation
# ---------------------------------------------------------------------------

# Validate a comma-separated list of latitudes/longitudes.
# Each value must be a valid number within the specified range.
# Returns the count of values on stdout.
_validate_coord_list() {
  local name="$1" csv="$2" min="$3" max="$4"
  local count=0

  local old_ifs="${IFS}"
  IFS=','
  for val in ${csv}; do
    [[ -z "${val}" ]] && continue
    _validate_number "${name}" "${val}"

    # Range check via awk (bash can't do float comparison natively)
    local in_range
    in_range=$(awk -v v="${val}" -v lo="${min}" -v hi="${max}" \
      'BEGIN { print (v >= lo && v <= hi) ? "1" : "0" }')
    if [[ "${in_range}" != "1" ]]; then
      _die "${name}: ${val} is out of range (${min} to ${max})"
    fi

    (( count++ ))
  done
  IFS="${old_ifs}"

  echo "${count}"
}

_validate_elevation_inputs() {
  local lat="$1" lon="$2"

  if [[ -z "${lat}" || -z "${lon}" ]]; then
    return 0  # will be caught later after city resolution
  fi

  # Validate individual values and get counts
  local lat_count lon_count
  lat_count=$(_validate_coord_list "--lat" "${lat}" -90 90)
  lon_count=$(_validate_coord_list "--lon" "${lon}" -180 180)

  # Counts must match
  if [[ "${lat_count}" -ne "${lon_count}" ]]; then
    _die "--lat has ${lat_count} value(s) but --lon has ${lon_count}. They must have the same number of elements."
  fi

  # Max 100 pairs
  if (( lat_count > 100 )); then
    _die "too many coordinates: ${lat_count} pairs given, maximum is 100"
  fi

  if (( lat_count == 0 )); then
    _die "--lat/--lon values are empty"
  fi
}

# ---------------------------------------------------------------------------
# Elevation-specific jq library
# ---------------------------------------------------------------------------
# shellcheck disable=SC2034
read -r -d '' ELEVATION_JQ_LIB <<'ELEVJQEOF' || true

# Parse comma-separated coordinate string into array of numbers
def parse_coords:
  split(",") | map(tonumber);

# Check if a value is missing (null or NaN -- the API returns nan for ocean/pole)
def elev_missing: . == null or isnan;

# Format a single elevation point
def fmt_elev_point($lat; $lon; $elev):
  "   📍 " +
  "\($lat | if . >= 0 then "\(.)°N" else "\(. * -1)°S" end), " +
  "\($lon | if . >= 0 then "\(.)°E" else "\(. * -1)°W" end)" +
  "  →  " + $B +
  (if ($elev | elev_missing) then
    "N/A"
  else
    "\($elev) m"
  end) + $R;

# Human header for elevation
def fmt_elev_header($name; $country; $n):
  "🏔  " +
  (if $name != "" then
    $B + $name + $R +
    (if $country != "" then ", " + $country else "" end)
  elif $n > 1 then
    "Elevation Lookup — " + $B + "\($n) locations" + $R
  else
    "Elevation Lookup"
  end);

ELEVJQEOF

# ---------------------------------------------------------------------------
# Human-friendly output
# ---------------------------------------------------------------------------
_elevation_output_human() {
  local json="$1" lat_csv="$2" lon_csv="$3"
  local loc_name="${4:-}" loc_country="${5:-}"
  _init_colors

  echo "${json}" | jq -r \
    --arg lats "${lat_csv}" \
    --arg lons "${lon_csv}" \
    --arg name "${loc_name}" \
    --arg country "${loc_country}" \
    --arg B "${C_BOLD}" --arg D "${C_DIM}" \
    --arg R "${C_RESET}" \
    "${ELEVATION_JQ_LIB}"'
    ($lats | parse_coords) as $lat_arr |
    ($lons | parse_coords) as $lon_arr |
    .elevation as $elevs |
    ($elevs | length) as $n |

    [ fmt_elev_header($name; $country; $n),
      "",
      ( range(0; $n) | fmt_elev_point($lat_arr[.]; $lon_arr[.]; $elevs[.]) )
    ] | join("\n")
    '
}

# ---------------------------------------------------------------------------
# Porcelain output
# ---------------------------------------------------------------------------
_elevation_output_porcelain() {
  local json="$1" lat_csv="$2" lon_csv="$3"

  echo "${json}" | jq -r \
    --arg lats "${lat_csv}" \
    --arg lons "${lon_csv}" \
    '
    ($lats | split(",") | map(tonumber)) as $lat_arr |
    ($lons | split(",") | map(tonumber)) as $lon_arr |
    .elevation as $elevs |
    ($elevs | length) as $n |

    "count=\($n)",
    ( range(0; $n) |
      . as $i |
      "elevation.\($i).latitude=\($lat_arr[$i])",
      "elevation.\($i).longitude=\($lon_arr[$i])",
      "elevation.\($i).elevation=\(if $elevs[$i] == null or ($elevs[$i] | isnan) then "" else $elevs[$i] end)"
    )
    '
}

# ---------------------------------------------------------------------------
# Command entry point
# ---------------------------------------------------------------------------
cmd_elevation() {
  local lat="" lon="" city="" country=""

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --lat=*)       lat=$(_extract_value "$1") ;;
      --lon=*)       lon=$(_extract_value "$1") ;;
      --city=*)      city=$(_extract_value "$1") ;;
      --country=*)   country=$(_extract_value "$1") ;;
      --api-key=*)   API_KEY=$(_extract_value "$1") ;;
      --porcelain)   OUTPUT_FORMAT="porcelain" ;;
      --raw)         OUTPUT_FORMAT="raw" ;;
      --verbose)     OPENMETEO_VERBOSE="true" ;;
      --help)        _elevation_help; return 0 ;;
      *)             _die_usage "elevation: unknown option: $1" ;;
    esac
    shift
  done

  _init_api_key

  # -------------------------------------------------------------------------
  # Validate inputs (pre-resolution)
  # -------------------------------------------------------------------------
  if [[ -n "${lat}" && -n "${lon}" ]]; then
    _validate_elevation_inputs "${lat}" "${lon}"
  fi

  # -------------------------------------------------------------------------
  # Resolve location if --city given
  # -------------------------------------------------------------------------
  local loc_name="" loc_country=""
  if [[ -n "${city}" ]]; then
    if [[ -n "${lat}" || -n "${lon}" ]]; then
      _die "cannot use --city together with --lat/--lon"
    fi
    _resolve_location "${city}" "${country}"
    lat="${RESOLVED_LAT}"
    lon="${RESOLVED_LON}"
    loc_name="${RESOLVED_NAME}"
    loc_country="${RESOLVED_COUNTRY}"
    _verbose "resolved '${city}' → ${RESOLVED_NAME}${RESOLVED_COUNTRY:+, ${RESOLVED_COUNTRY}} (${lat}, ${lon})"
  fi

  if [[ -z "${lat}" || -z "${lon}" ]]; then
    _elevation_help >&2
    _die_usage "location required: use --lat/--lon or --city"
  fi

  # -------------------------------------------------------------------------
  # Build query string
  # -------------------------------------------------------------------------
  local qs="latitude=${lat}&longitude=${lon}"

  # -------------------------------------------------------------------------
  # Request + output
  # -------------------------------------------------------------------------
  local response
  response=$(_request "${BASE_URL_ELEVATION}" "${qs}")

  case "${OUTPUT_FORMAT}" in
    raw)       _output_raw "${response}" ;;
    porcelain) _elevation_output_porcelain "${response}" "${lat}" "${lon}" ;;
    *)         _elevation_output_human "${response}" "${lat}" "${lon}" "${loc_name}" "${loc_country}" ;;
  esac
}
