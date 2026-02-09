#!/usr/bin/env bash
# commands/geo.sh -- Geocoding API subcommand

DEFAULT_GEO_COUNT="5"
DEFAULT_GEO_LANGUAGE="en"

_geo_help() {
  cat <<EOF
openmeteo geo -- Search locations by name (Geocoding API)

Usage:
  openmeteo geo --search=<name> [options]

Options:
  --search=NAME     Location name or postal code to search (required)
  --count=N         Number of results to return (default: ${DEFAULT_GEO_COUNT}, max: 100)
  --language=LANG   Language for results (default: ${DEFAULT_GEO_LANGUAGE})
  --country=CODE    ISO-3166-1 alpha-2 country code filter (e.g. GB, DE, US)

Output:
  --porcelain       Machine-parseable key=value output
  --raw             Raw JSON from API
  --help            Show this help

Examples:
  openmeteo geo --search=London
  openmeteo geo --search=Berlin --count=3
  openmeteo geo --search=Paris --country=FR --language=fr
  openmeteo geo --search=Tokyo --porcelain
EOF
}

# ---------------------------------------------------------------------------
# Human-friendly output
# ---------------------------------------------------------------------------
_geo_output_human() {
  local json="$1"

  _init_colors

  local filter
  read -r -d '' filter <<'JQFILTER' || true
.results | to_entries | map(
  .key as $i | .value |
  (if $i > 0 then "\n" else "" end) +
  $B + "📍 " + .name +
  (if .admin1 then ", \(.admin1)" else "" end) +
  (if .country then ", \(.country)" else "" end) +
  $R +
  (if .country_code then " [\(.country_code)]" else "" end) +
  "\n   " +
  "\(.latitude)°\(if .latitude >= 0 then "N" else "S" end), " +
  "\(.longitude | if . < 0 then -. else . end)°\(if .longitude >= 0 then "E" else "W" end)" +
  (if .elevation then "  ·  \(.elevation)m elev" else "" end) +
  (if .population and .population > 0 then
    "  ·  Pop: \(.population)"
  else "" end) +
  "\n   " + $D + "Timezone: \(.timezone // "?")" + $R +
  (if .postcodes and (.postcodes | length) > 0 then
    "\n   " + $D + "Postcodes: \(.postcodes | join(", "))" + $R
  else "" end) +
  (if .feature_code then
    "\n   " + $D + "Type: \(.feature_code)" + $R
  else "" end)
) | join("\n")
JQFILTER

  echo "${json}" | jq -r \
    --arg B "${C_BOLD}" \
    --arg D "${C_DIM}" \
    --arg R "${C_RESET}" \
    "${filter}"
}

# ---------------------------------------------------------------------------
# Porcelain output
# ---------------------------------------------------------------------------
_geo_output_porcelain() {
  local json="$1"

  local filter
  read -r -d '' filter <<'JQFILTER' || true
[
  .results | to_entries[] | .key as $i | .value |
  to_entries[] |
  "\($i).\(.key)=\(
    .value |
    if type == "array" then (map(tostring) | join(","))
    elif type == "null" then ""
    else tostring end
  )"
] | .[]
JQFILTER

  echo "${json}" | jq -r "${filter}"
}

# ---------------------------------------------------------------------------
# Command entry point
# ---------------------------------------------------------------------------
cmd_geo() {
  local search="" count="${DEFAULT_GEO_COUNT}" language="${DEFAULT_GEO_LANGUAGE}"
  local country=""

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --search=*)   search=$(_extract_value "$1") ;;
      --count=*)    count=$(_extract_value "$1") ;;
      --language=*) language=$(_extract_value "$1") ;;
      --country=*)  country=$(_extract_value "$1") ;;
      --api-key=*)  API_KEY=$(_extract_value "$1") ;;
      --porcelain)  OUTPUT_FORMAT="porcelain" ;;
      --raw)        OUTPUT_FORMAT="raw" ;;
      --help)       _geo_help; return 0 ;;
      *)            _die_usage "geo: unknown option: $1" ;;
    esac
    shift
  done

  _init_api_key

  if [[ -z "${search}" ]]; then
    _geo_help >&2
    _die_usage "missing required argument: --search"
  fi

  # Validate inputs
  _validate_integer "--count" "${count}" 1 100

  # Build query string
  local encoded_search
  encoded_search=$(_urlencode "${search}")

  local qs="name=${encoded_search}&count=${count}&language=${language}&format=json"
  if [[ -n "${country}" ]]; then
    qs="${qs}&countryCode=${country}"
  fi

  # Make request
  local response
  response=$(_request "${BASE_URL_GEOCODING}" "${qs}")

  # Check for empty results
  local results_count
  results_count=$(echo "${response}" | jq '.results | length // 0' 2>/dev/null)
  if [[ "${results_count}" -eq 0 ]]; then
    _error "no results found for '${search}'${country:+ (country: ${country})}"
    exit 1
  fi

  case "${OUTPUT_FORMAT}" in
    raw)       _output_raw "${response}" ;;
    porcelain) _geo_output_porcelain "${response}" ;;
    *)         _geo_output_human "${response}" ;;
  esac
}
