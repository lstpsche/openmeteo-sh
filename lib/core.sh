#!/usr/bin/env bash
# core.sh -- shared utilities for openmeteo CLI

OPENMETEO_VERSION="1.1.0"

# Base URLs (no trailing slash)
BASE_URL_FORECAST="https://api.open-meteo.com/v1/forecast"
BASE_URL_GEOCODING="https://geocoding-api.open-meteo.com/v1/search"
BASE_URL_HISTORICAL="https://archive-api.open-meteo.com/v1/archive"
BASE_URL_ENSEMBLE="https://ensemble-api.open-meteo.com/v1/ensemble"
BASE_URL_CLIMATE="https://climate-api.open-meteo.com/v1/climate"
BASE_URL_MARINE="https://marine-api.open-meteo.com/v1/marine"
BASE_URL_AIR_QUALITY="https://air-quality-api.open-meteo.com/v1/air-quality"
BASE_URL_FLOOD="https://flood-api.open-meteo.com/v1/flood"
BASE_URL_ELEVATION="https://api.open-meteo.com/v1/elevation"
BASE_URL_SATELLITE="https://satellite-api.open-meteo.com/v1/archive"

# Resolved API key (set during arg parsing)
API_KEY=""

# Verbose mode (set via --verbose flag)
OPENMETEO_VERBOSE=""

# ---------------------------------------------------------------------------
# Output helpers
# ---------------------------------------------------------------------------

_error() {
  echo "openmeteo: error: $*" >&2
}

_warn() {
  echo "openmeteo: warning: $*" >&2
}

# Print a verbose/debug message to stderr. Only emits when --verbose is set.
_verbose() {
  [[ -n "${OPENMETEO_VERBOSE}" ]] && echo "openmeteo: $*" >&2
  return 0
}

_die() {
  _error "$@"
  exit 1
}

_die_usage() {
  _error "$@"
  exit 1
}

# ---------------------------------------------------------------------------
# API key resolution
# ---------------------------------------------------------------------------

# Resolve API key: --api-key flag wins over OPENMETEO_API_KEY env var.
# Call after argument parsing has set API_KEY from --api-key if provided.
_resolve_api_key() {
  if [[ -z "${API_KEY}" ]]; then
    API_KEY="${OPENMETEO_API_KEY:-}"
  fi
}

# Apply customer- prefix to a base URL when API key is set.
# Usage: url=$(_apply_api_key_prefix "$BASE_URL_FORECAST")
_apply_api_key_prefix() {
  local url="$1"
  if [[ -n "${API_KEY}" ]]; then
    echo "${url/https:\/\//https://customer-}"
  else
    echo "${url}"
  fi
}

# Append apikey param to query string if API key is set.
# Usage: qs=$(_append_api_key "$qs")
_append_api_key() {
  local qs="$1"
  if [[ -n "${API_KEY}" ]]; then
    if [[ -n "${qs}" ]]; then
      echo "${qs}&apikey=${API_KEY}"
    else
      echo "apikey=${API_KEY}"
    fi
  else
    echo "${qs}"
  fi
}

# ---------------------------------------------------------------------------
# HTTP request
# ---------------------------------------------------------------------------

# Make a GET request and return the body. Exits on HTTP or network errors.
# Usage: _request "$url" "$query_string"
_request() {
  local base_url="$1"
  local query_string="$2"
  local full_url

  base_url=$(_apply_api_key_prefix "${base_url}")
  query_string=$(_append_api_key "${query_string}")

  if [[ -n "${query_string}" ]]; then
    full_url="${base_url}?${query_string}"
  else
    full_url="${base_url}"
  fi

  # Log the full request URL in verbose mode (mask API key)
  if [[ -n "${OPENMETEO_VERBOSE}" ]]; then
    local log_url="${full_url}"
    if [[ -n "${API_KEY}" ]]; then
      log_url="${log_url//${API_KEY}/***}"
    fi
    _verbose "GET ${log_url}"
  fi

  local http_code body tmp_file
  tmp_file=$(mktemp)
  trap "rm -f '${tmp_file}'" RETURN

  http_code=$(curl -s -o "${tmp_file}" -w "%{http_code}" --max-time 30 "${full_url}" 2>/dev/null)

  if [[ $? -ne 0 ]]; then
    _die "network error: could not reach ${base_url}"
  fi

  body=$(<"${tmp_file}")

  if [[ "${http_code}" -ge 400 ]]; then
    local reason
    reason=$(echo "${body}" | jq -r '.reason // empty' 2>/dev/null)
    if [[ -n "${reason}" ]]; then
      _die "API error (HTTP ${http_code}): ${reason}"
    else
      _die "API error (HTTP ${http_code}): ${body}"
    fi
  fi

  echo "${body}"
}

# ---------------------------------------------------------------------------
# Argument parsing helpers
# ---------------------------------------------------------------------------

# Handle --api-key=... and resolve the final API key.
# Call at the start of each command after parsing its own args.
# Usage: _init_api_key
_init_api_key() {
  _resolve_api_key
}

# Extract value from --key=value argument.
# Usage: value=$(_extract_value "$1")
_extract_value() {
  echo "${1#*=}"
}

# ---------------------------------------------------------------------------
# Input validation helpers
# ---------------------------------------------------------------------------

# Validate that a value is a number (integer or decimal, optionally negative).
# Usage: _validate_number "--lat" "$lat"
_validate_number() {
  local name="$1" value="$2"
  if ! [[ "${value}" =~ ^-?[0-9]+\.?[0-9]*$ ]]; then
    _die "${name}: '${value}' is not a valid number"
  fi
}

# Validate that a value is a non-negative integer, optionally within [min, max].
# Usage: _validate_integer "--forecast-days" "$forecast_days" 0 16
_validate_integer() {
  local name="$1" value="$2"
  local min="${3:-}" max="${4:-}"

  if ! [[ "${value}" =~ ^[0-9]+$ ]]; then
    _die "${name}: '${value}' is not a valid integer"
  fi

  if [[ -n "${min}" ]] && (( value < min )); then
    _die "${name}: ${value} is below minimum (${min})"
  fi

  if [[ -n "${max}" ]] && (( value > max )); then
    _die "${name}: ${value} is above maximum (${max})"
  fi
}

# Validate that a value is one of the allowed enum values.
# Usage: _validate_enum "--temperature-unit" "$unit" celsius fahrenheit
_validate_enum() {
  local name="$1" value="$2"
  shift 2

  local v
  for v in "$@"; do
    if [[ "${value}" == "${v}" ]]; then
      return 0
    fi
  done

  local allowed
  allowed=$(printf '%s, ' "$@")
  _die "${name}: '${value}' is not valid. Must be one of: ${allowed%, }"
}

# Validate ISO 8601 date format (YYYY-MM-DD).
# Usage: _validate_date "--start-date" "$start_date"
_validate_date() {
  local name="$1" value="$2"
  if ! [[ "${value}" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]]; then
    _die "${name}: '${value}' is not a valid date. Use YYYY-MM-DD format (e.g. 2024-01-15)"
  fi
  # Basic range check on month/day
  local month="${value:5:2}" day="${value:8:2}"
  if (( 10#${month} < 1 || 10#${month} > 12 )); then
    _die "${name}: invalid month '${month}' in '${value}'"
  fi
  if (( 10#${day} < 1 || 10#${day} > 31 )); then
    _die "${name}: invalid day '${day}' in '${value}'"
  fi
}

# URL-encode a string (minimal: spaces and special chars).
_urlencode() {
  local string="$1"
  local encoded=""
  local i char
  for (( i=0; i<${#string}; i++ )); do
    char="${string:$i:1}"
    case "${char}" in
      [a-zA-Z0-9.~_-]) encoded+="${char}" ;;
      ' ') encoded+='+' ;;
      *) encoded+=$(printf '%%%02X' "'${char}") ;;
    esac
  done
  echo "${encoded}"
}
