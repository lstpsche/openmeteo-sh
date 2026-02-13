#!/usr/bin/env bash
# commands/config.sh -- Configuration management subcommand

_config_help() {
  cat <<EOF
openmeteo config -- Manage configuration file

Usage:
  openmeteo config <action> [arguments]

Actions:
  show              Show current configuration (values and sources)
  path              Print config file path
  init              Create config file with commented-out defaults
  set KEY=VALUE     Set a configuration value
  unset KEY         Remove a configuration value
  get KEY           Get a single configuration value
  help              Show this help

Valid keys:
  api_key              OpenMeteo API key for commercial access
  city                 Default city name (e.g. London)
  country              Default country code, ISO 3166-1 alpha-2 (e.g. GB)
  lat                  Default latitude (e.g. 51.5)
  lon                  Default longitude (e.g. -0.12)
  format               Default output format: human, porcelain, llm, raw
  temperature_unit     Default temperature unit: celsius, fahrenheit
  wind_speed_unit      Default wind speed unit: kmh, ms, mph, kn
  precipitation_unit   Default precipitation unit: mm, inch
  timezone             Default timezone: auto, or IANA name (e.g. Europe/London)
  verbose              Enable verbose mode: true, false

Config file location (in order of precedence):
  \$OPENMETEO_CONFIG environment variable
  \$XDG_CONFIG_HOME/openmeteo/config
  ~/.config/openmeteo/config

Precedence: CLI flags > environment variables > config file > built-in defaults

Examples:
  openmeteo config init
  openmeteo config set city=London
  openmeteo config set api_key=your_key_here
  openmeteo config get city
  openmeteo config unset city
  openmeteo config show
EOF
}

# ---------------------------------------------------------------------------
# Config actions
# ---------------------------------------------------------------------------

# Print config file path
_config_path_action() {
  _config_path
}

# Show current effective configuration with sources
_config_show() {
  local config_file
  config_file="$(_config_path)"

  echo "Config file: ${config_file}"
  if [[ -f "${config_file}" ]]; then
    echo "Status: loaded"
  else
    echo "Status: not found (using defaults)"
  fi
  echo ""

  local key display_value source
  for key in ${_VALID_CONFIG_KEYS}; do
    display_value=""
    source="default"

    case "${key}" in
      api_key)
        if [[ -n "${API_KEY}" ]]; then
          # Mask the key for display
          display_value="${API_KEY:0:4}***"
          if [[ -n "${OPENMETEO_API_KEY:-}" ]]; then
            source="env (OPENMETEO_API_KEY)"
          elif [[ -n "${CFG_API_KEY}" ]]; then
            source="config"
          fi
        elif [[ -n "${CFG_API_KEY}" ]]; then
          display_value="${CFG_API_KEY:0:4}***"
          source="config"
        fi
        ;;
      city)
        display_value="${CFG_CITY:-}"
        [[ -n "${display_value}" ]] && source="config"
        ;;
      country)
        display_value="${CFG_COUNTRY:-}"
        [[ -n "${display_value}" ]] && source="config"
        ;;
      lat)
        display_value="${CFG_LAT:-}"
        [[ -n "${display_value}" ]] && source="config"
        ;;
      lon)
        display_value="${CFG_LON:-}"
        [[ -n "${display_value}" ]] && source="config"
        ;;
      format)
        display_value="${CFG_FORMAT:-human}"
        [[ -n "${CFG_FORMAT}" ]] && source="config" || source="default"
        ;;
      temperature_unit)
        display_value="${CFG_TEMPERATURE_UNIT:-celsius}"
        [[ -n "${CFG_TEMPERATURE_UNIT}" ]] && source="config" || source="default"
        ;;
      wind_speed_unit)
        display_value="${CFG_WIND_SPEED_UNIT:-kmh}"
        [[ -n "${CFG_WIND_SPEED_UNIT}" ]] && source="config" || source="default"
        ;;
      precipitation_unit)
        display_value="${CFG_PRECIPITATION_UNIT:-mm}"
        [[ -n "${CFG_PRECIPITATION_UNIT}" ]] && source="config" || source="default"
        ;;
      timezone)
        display_value="${CFG_TIMEZONE:-auto}"
        [[ -n "${CFG_TIMEZONE}" ]] && source="config" || source="default"
        ;;
      verbose)
        display_value="${CFG_VERBOSE:-false}"
        [[ -n "${CFG_VERBOSE}" ]] && source="config" || source="default"
        ;;
    esac

    if [[ -z "${display_value}" ]]; then
      display_value="(not set)"
      source=""
    fi

    if [[ -n "${source}" ]]; then
      printf "  %-22s %s  (%s)\n" "${key}" "${display_value}" "${source}"
    else
      printf "  %-22s %s\n" "${key}" "${display_value}"
    fi
  done
}

# Show config in porcelain format
_config_show_porcelain() {
  local key value
  for key in ${_VALID_CONFIG_KEYS}; do
    value=""
    case "${key}" in
      api_key)            value="${CFG_API_KEY:-}" ;;
      city)               value="${CFG_CITY:-}" ;;
      country)            value="${CFG_COUNTRY:-}" ;;
      lat)                value="${CFG_LAT:-}" ;;
      lon)                value="${CFG_LON:-}" ;;
      format)             value="${CFG_FORMAT:-}" ;;
      temperature_unit)   value="${CFG_TEMPERATURE_UNIT:-}" ;;
      wind_speed_unit)    value="${CFG_WIND_SPEED_UNIT:-}" ;;
      precipitation_unit) value="${CFG_PRECIPITATION_UNIT:-}" ;;
      timezone)           value="${CFG_TIMEZONE:-}" ;;
      verbose)            value="${CFG_VERBOSE:-}" ;;
    esac
    [[ -n "${value}" ]] && echo "${key}=${value}"
  done
  return 0
}

# Create config file with commented-out defaults
_config_init() {
  local config_file
  config_file="$(_config_path)"

  if [[ -f "${config_file}" ]]; then
    _die "config file already exists: ${config_file}. Use 'openmeteo config set' to modify it."
  fi

  local config_dir
  config_dir="$(dirname "${config_file}")"
  mkdir -p "${config_dir}" || _die "cannot create directory: ${config_dir}"

  cat > "${config_file}" <<'CONF'
# openmeteo CLI configuration
# Lines starting with '#' are comments.
# Format: key = value
#
# Precedence: CLI flags > environment variables > this file > built-in defaults
#
# Run 'openmeteo config help' for available keys and their descriptions.

# API key for commercial access (overrides OPENMETEO_API_KEY env var)
# api_key =

# Default location
# city = London
# country = GB
# lat = 51.5
# lon = -0.12

# Default output format: human, porcelain, llm, raw
# format = human

# Default units
# temperature_unit = celsius
# wind_speed_unit = kmh
# precipitation_unit = mm

# Default timezone (IANA name or 'auto')
# timezone = auto

# Verbose mode: true or false
# verbose = false
CONF

  echo "Created config file: ${config_file}"
}

# Set a config value
# Usage: _config_set "key=value" or _config_set "key" "value"
_config_set() {
  local input="$1"
  local key value

  if [[ "${input}" =~ ^([a-z_]+)=(.*)$ ]]; then
    key="${BASH_REMATCH[1]}"
    value="${BASH_REMATCH[2]}"
  else
    _die "invalid syntax. Usage: openmeteo config set KEY=VALUE"
  fi

  if ! _is_valid_config_key "${key}"; then
    _die "unknown config key: '${key}'. Run 'openmeteo config help' for valid keys."
  fi

  # Validate specific keys
  case "${key}" in
    format)             _validate_enum "config format" "${value}" human porcelain llm raw ;;
    temperature_unit)   _validate_enum "config temperature_unit" "${value}" celsius fahrenheit ;;
    wind_speed_unit)    _validate_enum "config wind_speed_unit" "${value}" kmh ms mph kn ;;
    precipitation_unit) _validate_enum "config precipitation_unit" "${value}" mm inch ;;
    lat)                _validate_number "config lat" "${value}" ;;
    lon)                _validate_number "config lon" "${value}" ;;
    verbose)            _validate_enum "config verbose" "${value}" true false yes no 1 0 ;;
  esac

  local config_file
  config_file="$(_config_path)"

  # Create the file and directory if needed
  if [[ ! -f "${config_file}" ]]; then
    local config_dir
    config_dir="$(dirname "${config_file}")"
    mkdir -p "${config_dir}" || _die "cannot create directory: ${config_dir}"
    touch "${config_file}"
  fi

  # Check if key already exists (uncommented) — update in place
  if grep -qE "^${key}[[:space:]]*=" "${config_file}" 2>/dev/null; then
    # Replace existing line
    local tmp_file
    tmp_file=$(mktemp)
    while IFS= read -r line || [[ -n "${line}" ]]; do
      if [[ "${line}" =~ ^${key}[[:space:]]*= ]]; then
        echo "${key} = ${value}"
      else
        echo "${line}"
      fi
    done < "${config_file}" > "${tmp_file}"
    mv "${tmp_file}" "${config_file}"
  else
    # Append new key
    echo "${key} = ${value}" >> "${config_file}"
  fi

  echo "Set ${key} = ${value}"
}

# Remove a config value
_config_unset() {
  local key="$1"

  if ! _is_valid_config_key "${key}"; then
    _die "unknown config key: '${key}'. Run 'openmeteo config help' for valid keys."
  fi

  local config_file
  config_file="$(_config_path)"

  if [[ ! -f "${config_file}" ]]; then
    _die "config file not found: ${config_file}"
  fi

  if ! grep -qE "^${key}[[:space:]]*=" "${config_file}" 2>/dev/null; then
    _error "'${key}' is not set in config"
    return 1
  fi

  # Remove the line
  local tmp_file
  tmp_file=$(mktemp)
  while IFS= read -r line || [[ -n "${line}" ]]; do
    if [[ ! "${line}" =~ ^${key}[[:space:]]*= ]]; then
      echo "${line}"
    fi
  done < "${config_file}" > "${tmp_file}"
  mv "${tmp_file}" "${config_file}"

  echo "Removed ${key}"
}

# Get a single config value
_config_get() {
  local key="$1"

  if ! _is_valid_config_key "${key}"; then
    _die "unknown config key: '${key}'. Run 'openmeteo config help' for valid keys."
  fi

  local value=""
  case "${key}" in
    api_key)            value="${CFG_API_KEY:-}" ;;
    city)               value="${CFG_CITY:-}" ;;
    country)            value="${CFG_COUNTRY:-}" ;;
    lat)                value="${CFG_LAT:-}" ;;
    lon)                value="${CFG_LON:-}" ;;
    format)             value="${CFG_FORMAT:-}" ;;
    temperature_unit)   value="${CFG_TEMPERATURE_UNIT:-}" ;;
    wind_speed_unit)    value="${CFG_WIND_SPEED_UNIT:-}" ;;
    precipitation_unit) value="${CFG_PRECIPITATION_UNIT:-}" ;;
    timezone)           value="${CFG_TIMEZONE:-}" ;;
    verbose)            value="${CFG_VERBOSE:-}" ;;
  esac

  if [[ -n "${value}" ]]; then
    echo "${value}"
  fi
}

# ---------------------------------------------------------------------------
# Entry point
# ---------------------------------------------------------------------------
cmd_config() {
  if [[ $# -eq 0 ]]; then
    _config_help
    return 0
  fi

  local action="$1"
  shift

  # Parse global format flags from remaining args
  local args=()
  for arg in "$@"; do
    case "${arg}" in
      --human)    OUTPUT_FORMAT="human" ;;
      --porcelain) OUTPUT_FORMAT="porcelain" ;;
      --llm)      OUTPUT_FORMAT="llm" ;;
      --raw)      OUTPUT_FORMAT="raw" ;;
      *)          args+=("${arg}") ;;
    esac
  done
  set -- "${args[@]+"${args[@]}"}"

  case "${action}" in
    help|--help)
      _config_help
      ;;
    path)
      _config_path_action
      ;;
    init)
      _config_init
      ;;
    show)
      case "${OUTPUT_FORMAT}" in
        porcelain|llm) _config_show_porcelain ;;
        *)             _config_show ;;
      esac
      ;;
    set)
      [[ $# -lt 1 ]] && _die "usage: openmeteo config set KEY=VALUE"
      _config_set "$1"
      ;;
    unset)
      [[ $# -lt 1 ]] && _die "usage: openmeteo config unset KEY"
      _config_unset "$1"
      ;;
    get)
      [[ $# -lt 1 ]] && _die "usage: openmeteo config get KEY"
      _config_get "$1"
      ;;
    *)
      _error "unknown config action: '${action}'"
      echo
      _config_help
      exit 1
      ;;
  esac
}
