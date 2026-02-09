#!/usr/bin/env bash
# output.sh -- output formatting for openmeteo CLI
#
# Three output modes:
#   human     (default) -- emoji, colors, grouped-by-day, readable
#   porcelain           -- flat key=value, one per line, for scripts/agents
#   raw                 -- unmodified JSON from API

# ---------------------------------------------------------------------------
# Output format global (set by each command from its flags)
# ---------------------------------------------------------------------------
OUTPUT_FORMAT="human"

# ---------------------------------------------------------------------------
# ANSI color support
# ---------------------------------------------------------------------------
C_RESET="" C_BOLD="" C_DIM=""
C_RED="" C_GREEN="" C_YELLOW="" C_BLUE="" C_CYAN="" C_WHITE=""

_init_colors() {
  if [[ -t 1 ]] && [[ "${OUTPUT_FORMAT}" == "human" ]]; then
    C_RESET=$'\033[0m'
    C_BOLD=$'\033[1m'
    C_DIM=$'\033[2m'
    C_RED=$'\033[31m'
    C_GREEN=$'\033[32m'
    C_YELLOW=$'\033[33m'
    C_BLUE=$'\033[34m'
    C_CYAN=$'\033[36m'
    C_WHITE=$'\033[37m'
  fi
}

# ---------------------------------------------------------------------------
# Shared jq function library
# ---------------------------------------------------------------------------
# Injected into jq filters as a prefix: jq -r "${JQ_LIB} <filter>"
# shellcheck disable=SC2034
read -r -d '' JQ_LIB <<'JQEOF' || true
def wmo_text:
  if . == null then "?"
  elif . == 0 then "Clear sky"
  elif . == 1 then "Mainly clear"
  elif . == 2 then "Partly cloudy"
  elif . == 3 then "Overcast"
  elif . == 45 then "Fog"
  elif . == 48 then "Rime fog"
  elif . == 51 then "Light drizzle"
  elif . == 53 then "Drizzle"
  elif . == 55 then "Dense drizzle"
  elif . == 56 then "Lt. freezing drizzle"
  elif . == 57 then "Freezing drizzle"
  elif . == 61 then "Light rain"
  elif . == 63 then "Rain"
  elif . == 65 then "Heavy rain"
  elif . == 66 then "Lt. freezing rain"
  elif . == 67 then "Freezing rain"
  elif . == 71 then "Light snow"
  elif . == 73 then "Snow"
  elif . == 75 then "Heavy snow"
  elif . == 77 then "Snow grains"
  elif . == 80 then "Light showers"
  elif . == 81 then "Showers"
  elif . == 82 then "Heavy showers"
  elif . == 85 then "Light snow showers"
  elif . == 86 then "Heavy snow showers"
  elif . == 95 then "Thunderstorm"
  elif . == 96 then "T-storm, light hail"
  elif . == 99 then "T-storm, heavy hail"
  else "WMO \(.)" end;

def wmo_emoji:
  if . == null then " "
  elif . == 0 then "☀️ "
  elif . == 1 then "🌤 "
  elif . == 2 then "⛅"
  elif . == 3 then "☁️ "
  elif . == 45 or . == 48 then "🌫 "
  elif (. >= 51 and . <= 57) or (. >= 61 and . <= 67) then "🌧 "
  elif (. >= 71 and . <= 77) or (. >= 85 and . <= 86) then "🌨 "
  elif . >= 80 and . <= 82 then "🌦 "
  elif . >= 95 then "⛈ "
  else "❓" end;

def wind_dir:
  if . == null then "?"
  elif . < 22.5 or . >= 337.5 then "N"
  elif . < 67.5 then "NE"
  elif . < 112.5 then "E"
  elif . < 157.5 then "SE"
  elif . < 202.5 then "S"
  elif . < 247.5 then "SW"
  elif . < 292.5 then "W"
  else "NW" end;

def abs: if . < 0 then -. else . end;
def round2: . * 100 | round / 100;

def day_label:
  (try (strptime("%Y-%m-%d") | mktime | strftime("%a %b %d, %Y"))
   catch .);

def zip_hourly:
  .hourly as $h |
  ($h | keys_unsorted | map(select(. != "time"))) as $vars |
  [range(0; ($h.time | length))] | map(. as $i |
    {time: $h.time[$i]} +
    ([$vars[] as $v | {($v): $h[$v][$i]}] | add // {})
  );

def zip_daily:
  .daily as $d |
  ($d | keys_unsorted | map(select(. != "time"))) as $vars |
  [range(0; ($d.time | length))] | map(. as $i |
    {time: $d.time[$i]} +
    ([$vars[] as $v | {($v): $d[$v][$i]}] | add // {})
  );

def fmt_loc_header($name; $country):
  "🌍 " +
  (if $name != "" then
    "\($name)" + (if $country != "" then ", \($country)" else "" end) +
    " · "
  else "" end) +
  "\(.latitude | round2)°\(if .latitude >= 0 then "N" else "S" end), " +
  "\(.longitude | abs | round2)°\(if .longitude >= 0 then "E" else "W" end)" +
  "\n   \(.timezone // "GMT") (\(.timezone_abbreviation // ""))" +
  (if .elevation then " · Elevation: \(.elevation)m" else "" end);
JQEOF

# ---------------------------------------------------------------------------
# Raw output
# ---------------------------------------------------------------------------
_output_raw() {
  echo "$1"
}

# ---------------------------------------------------------------------------
# Pretty JSON (fallback / intermediate)
# ---------------------------------------------------------------------------
_output_json() {
  if [[ -t 1 ]]; then
    echo "$1" | jq -C '.'
  else
    echo "$1" | jq '.'
  fi
}
