#!/usr/bin/env bash
# core.sh -- shared utilities for openmeteo CLI

OPENMETEO_VERSION="1.5.0"

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
# Config file support
# ---------------------------------------------------------------------------

# Config globals (populated by _load_config)
CFG_API_KEY=""
CFG_CITY=""
CFG_COUNTRY=""
CFG_LAT=""
CFG_LON=""
CFG_FORMAT=""
CFG_TEMPERATURE_UNIT=""
CFG_WIND_SPEED_UNIT=""
CFG_PRECIPITATION_UNIT=""
CFG_TIMEZONE=""
CFG_VERBOSE=""

# All valid config keys (space-separated)
_VALID_CONFIG_KEYS="api_key city country lat lon format temperature_unit wind_speed_unit precipitation_unit timezone verbose"

# Return the config file path.
# Priority: $OPENMETEO_CONFIG > $XDG_CONFIG_HOME/openmeteo/config > ~/.config/openmeteo/config
_config_path() {
  if [[ -n "${OPENMETEO_CONFIG:-}" ]]; then
    echo "${OPENMETEO_CONFIG}"
  else
    echo "${XDG_CONFIG_HOME:-$HOME/.config}/openmeteo/config"
  fi
}

# Check if a key is a valid config key.
_is_valid_config_key() {
  local key="$1" k
  for k in ${_VALID_CONFIG_KEYS}; do
    [[ "${k}" == "${key}" ]] && return 0
  done
  return 1
}

# Load config file and populate CFG_* globals.
# Silently does nothing if the file doesn't exist.
_load_config() {
  local config_file
  config_file="$(_config_path)"
  [[ -f "${config_file}" ]] || return 0

  local line key value line_num=0
  while IFS= read -r line || [[ -n "${line}" ]]; do
    line_num=$(( line_num + 1 ))
    # Skip empty lines and comments
    [[ -z "${line}" || "${line}" =~ ^[[:space:]]*# ]] && continue
    # Strip inline comments (only after whitespace + #)
    line="${line%%[[:space:]]#*}"
    # Trim leading/trailing whitespace
    line="${line#"${line%%[![:space:]]*}"}"
    line="${line%"${line##*[![:space:]]}"}"
    [[ -z "${line}" ]] && continue

    if [[ "${line}" =~ ^([a-z_]+)[[:space:]]*=[[:space:]]*(.*) ]]; then
      key="${BASH_REMATCH[1]}"
      value="${BASH_REMATCH[2]}"
      # Strip surrounding quotes if present
      if [[ "${value}" =~ ^\"(.*)\"$ ]] || [[ "${value}" =~ ^\'(.*)\'$ ]]; then
        value="${BASH_REMATCH[1]}"
      fi
      case "${key}" in
        api_key)            CFG_API_KEY="${value}" ;;
        city)               CFG_CITY="${value}" ;;
        country)            CFG_COUNTRY="${value}" ;;
        lat)                CFG_LAT="${value}" ;;
        lon)                CFG_LON="${value}" ;;
        format)             CFG_FORMAT="${value}" ;;
        temperature_unit)   CFG_TEMPERATURE_UNIT="${value}" ;;
        wind_speed_unit)    CFG_WIND_SPEED_UNIT="${value}" ;;
        precipitation_unit) CFG_PRECIPITATION_UNIT="${value}" ;;
        timezone)           CFG_TIMEZONE="${value}" ;;
        verbose)            CFG_VERBOSE="${value}" ;;
        *) _warn "config: unknown key '${key}' at ${config_file}:${line_num} (ignored)" ;;
      esac
    else
      _warn "config: invalid syntax at ${config_file}:${line_num}: ${line}"
    fi
  done < "${config_file}"
}

# Apply config values to global settings (format, verbose).
# Call after _load_config, before command dispatch.
# CLI flags in each command override these later.
_apply_config_globals() {
  if [[ -n "${CFG_FORMAT}" ]]; then
    _validate_enum "config format" "${CFG_FORMAT}" human porcelain llm raw
    OUTPUT_FORMAT="${CFG_FORMAT}"
  fi
  if [[ -z "${OPENMETEO_VERBOSE}" ]]; then
    case "${CFG_VERBOSE}" in
      true|1|yes) OPENMETEO_VERBOSE="true" ;;
    esac
  fi
}

# Apply config location defaults to caller's local variables.
# Uses bash dynamic scoping (caller's locals are visible).
# All-or-nothing: if ANY location arg was provided via CLI, skip config location
# entirely. This prevents config country=BY from polluting --city=London.
_apply_config_location() {
  if [[ -n "${city:-}" || -n "${lat:-}" || -n "${lon:-}" || -n "${country:-}" ]]; then
    return 0
  fi
  city="${CFG_CITY:-}"
  country="${CFG_COUNTRY:-}"
  lat="${CFG_LAT:-}"
  lon="${CFG_LON:-}"
}

# Apply config unit defaults to caller's local variables.
_apply_config_units() {
  [[ -z "${temperature_unit:-}" ]]    && temperature_unit="${CFG_TEMPERATURE_UNIT:-}"
  [[ -z "${wind_speed_unit:-}" ]]     && wind_speed_unit="${CFG_WIND_SPEED_UNIT:-}"
  [[ -z "${precipitation_unit:-}" ]]  && precipitation_unit="${CFG_PRECIPITATION_UNIT:-}"
}

# Apply config timezone default to caller's local variable.
# Falls back to "auto" if neither CLI nor config provides one.
_apply_config_timezone() {
  if [[ -z "${timezone:-}" ]]; then
    timezone="${CFG_TIMEZONE:-auto}"
  fi
}

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

# Resolve API key: --api-key flag > OPENMETEO_API_KEY env var > config file.
# Call after argument parsing has set API_KEY from --api-key if provided.
_resolve_api_key() {
  if [[ -z "${API_KEY}" ]]; then
    API_KEY="${OPENMETEO_API_KEY:-}"
  fi
  if [[ -z "${API_KEY}" ]]; then
    API_KEY="${CFG_API_KEY:-}"
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

# ---------------------------------------------------------------------------
# Date helpers (portable: BSD/macOS + GNU/Linux)
# ---------------------------------------------------------------------------

# Return today's date in YYYY-MM-DD.
_today() {
  date +%Y-%m-%d
}

# Return a date N days from today in YYYY-MM-DD.
# Usage: _date_offset_days 3   →  "2026-02-12" (if today is 2026-02-09)
_date_offset_days() {
  local days="$1"
  if date -v+1d +%Y-%m-%d >/dev/null 2>&1; then
    # BSD date (macOS)
    date -v+"${days}d" +%Y-%m-%d
  else
    # GNU date (Linux)
    date -d "+${days} days" +%Y-%m-%d
  fi
}

# ---------------------------------------------------------------------------
# Forecast-since helper
# ---------------------------------------------------------------------------

# Convert --forecast-since=N + --forecast-days=D into start_date/end_date.
# Sets FORECAST_START_DATE and FORECAST_END_DATE globals.
# Usage: _resolve_forecast_since "$forecast_since" "$forecast_days" "$default_days"
_resolve_forecast_since() {
  local since="$1" days="${2:-}" default_days="${3:-7}"

  local effective_days="${days:-${default_days}}"

  if (( since > effective_days )); then
    _die "--forecast-since=${since} exceeds --forecast-days=${effective_days}"
  fi

  FORECAST_START_DATE=$(_date_offset_days $(( since - 1 )))
  FORECAST_END_DATE=$(_date_offset_days $(( effective_days - 1 )))
}

# ---------------------------------------------------------------------------
# Help-output formatter (format-aware param help)
# ---------------------------------------------------------------------------

# Transform human-friendly param help text into the requested format.
# Reads from stdin. The input format is:
#   Category:
#     variable_name          Description text
#
# Porcelain: variable_name=Description text
# LLM:       variable_name\tDescription text  (TSV, one header line)
# Raw/Human: pass-through
_format_param_help() {
  local fmt="${1:-human}"

  case "${fmt}" in
    porcelain)
      # Extract lines matching "  word_chars   Description" → name=description
      while IFS= read -r line; do
        if [[ "${line}" =~ ^[[:space:]]+([a-z_][a-z0-9_]*)([[:space:]]{2,})(.*) ]]; then
          echo "${BASH_REMATCH[1]}=${BASH_REMATCH[3]}"
        fi
      done
      ;;
    llm)
      echo "variable	description"
      while IFS= read -r line; do
        if [[ "${line}" =~ ^[[:space:]]+([a-z_][a-z0-9_]*)([[:space:]]{2,})(.*) ]]; then
          printf '%s\t%s\n' "${BASH_REMATCH[1]}" "${BASH_REMATCH[3]}"
        fi
      done
      ;;
    *)
      # human / raw — pass-through
      cat
      ;;
  esac
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
