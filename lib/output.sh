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

# ── Human: format one hourly row (input: a zipped row object) ────────
def fmt_hourly_row($units):
  .time[11:16] as $time |
  . as $row |
  "   " + $D + $time + $R + "  " + ([
    (if $row.temperature_2m != null then
      $B + "\($row.temperature_2m)°" + $R +
      (if $row.apparent_temperature != null then
        " (feels \($row.apparent_temperature)°)" else "" end)
    else null end),
    (if $row.weather_code != null then
      ($row.weather_code | wmo_text) else null end),
    (if $row.relative_humidity_2m != null then
      "💧\($row.relative_humidity_2m)%" else null end),
    (if $row.precipitation != null then
      "\($row.precipitation)\($units.precipitation // "mm")" +
      (if $row.precipitation_probability != null then
        " (\($row.precipitation_probability)%)" else "" end)
    elif $row.precipitation_probability != null then
      "💧\($row.precipitation_probability)% chance"
    else null end),
    (if $row.cloud_cover != null and $row.weather_code == null then
      "☁️\($row.cloud_cover)%" else null end),
    (if $row.wind_speed_10m != null then
      "💨\($row.wind_speed_10m)" +
      (if $units.wind_speed_10m then " \($units.wind_speed_10m)" else "" end) +
      (if $row.wind_direction_10m != null then
        " \($row.wind_direction_10m | wind_dir)" else "" end)
    else null end),
    ($row | to_entries | map(
      select(.key | IN("time","temperature_2m","apparent_temperature","weather_code",
        "relative_humidity_2m","precipitation","precipitation_probability",
        "cloud_cover","wind_speed_10m","wind_direction_10m") | not) |
      "\(.key | gsub("_"; " ")): \(.value // "—")"
    ) | if length > 0 then join(", ") else null end)
  ] | map(select(. != null and . != "")) | join(" · "));

# ── Human: hourly section grouped by day ─────────────────────────────
def fmt_hourly:
  if .hourly then
    .hourly_units as $units |
    zip_hourly | group_by(.time[:10]) |
    map(
      .[0].time[:10] as $date |
      "\n" + $B + $CB + "📅 " + ($date | day_label) + $R + "\n" +
      (map(fmt_hourly_row($units)) | join("\n"))
    ) | join("\n")
  else "" end;

# ── Human: daily section ─────────────────────────────────────────────
def fmt_daily:
  if .daily then
    .daily_units as $units |
    zip_daily | map(
      .time as $date | . as $row |
      "\n" + $B + "📅 " + ($date | day_label) + $R +
      ([
        (if $row.temperature_2m_max != null and $row.temperature_2m_min != null then
          "🌡  \($row.temperature_2m_min)°→\($row.temperature_2m_max)°" +
          (if $row.temperature_2m_mean != null then
            " (avg \($row.temperature_2m_mean)°)" else "" end)
        elif $row.temperature_2m_max != null then "🌡  max \($row.temperature_2m_max)°"
        elif $row.temperature_2m_min != null then "🌡  min \($row.temperature_2m_min)°"
        elif $row.temperature_2m_mean != null then "🌡  avg \($row.temperature_2m_mean)°"
        else null end),
        (if $row.weather_code != null then
          ($row.weather_code | wmo_emoji) + " " + ($row.weather_code | wmo_text)
        else null end),
        (if $row.precipitation_sum != null then
          "🌧  \($row.precipitation_sum)\($units.precipitation_sum // "mm")" +
          (if $row.precipitation_probability_max != null then
            " (\($row.precipitation_probability_max)%)" else "" end)
        else null end),
        (if $row.wind_speed_10m_max != null then
          "💨 max \($row.wind_speed_10m_max)\($units.wind_speed_10m_max // "km/h")" +
          (if $row.wind_gusts_10m_max != null then
            ", gusts \($row.wind_gusts_10m_max)" else "" end)
        else null end),
        (if $row.sunrise != null and $row.sunset != null then
          "🌅 \($row.sunrise[11:16])→\($row.sunset[11:16])"
        else null end),
        ($row | to_entries | map(
          select(.key | IN("time","temperature_2m_max","temperature_2m_min",
            "temperature_2m_mean","apparent_temperature_max","apparent_temperature_min",
            "apparent_temperature_mean","weather_code","precipitation_sum",
            "precipitation_probability_max","wind_speed_10m_max","wind_gusts_10m_max",
            "sunrise","sunset") | not) |
          "\(.key | gsub("_"; " ")): \(.value // "—")"
        ) | if length > 0 then join(" · ") else null end)
      ] | map(select(. != null and . != "")) | map("   " + .) | join("\n"))
    ) | join("\n")
  else "" end;

# ── Human: current conditions ────────────────────────────────────────
def fmt_current:
  if .current then
    .current as $c | .current_units as $u |
    "\n" + $B + "⏱  Now" + $R + " — \($c.time // "now")\n" +
    (if $c.temperature_2m != null then
      "\n   🌡  " + $B + "\($c.temperature_2m)\($u.temperature_2m // "°C")" + $R +
      (if $c.apparent_temperature != null then
        " (feels like \($c.apparent_temperature)\($u.apparent_temperature // "°C"))"
      else "" end) else "" end) +
    (if $c.relative_humidity_2m != null then
      "\n   💧 \($c.relative_humidity_2m)% humidity" else "" end) +
    (if $c.weather_code != null then
      "\n   " + ($c.weather_code | wmo_emoji) + " " + $B +
      ($c.weather_code | wmo_text) + $R +
      (if $c.cloud_cover != null then " (\($c.cloud_cover)% clouds)" else "" end)
    elif $c.cloud_cover != null then
      "\n   ☁️  \($c.cloud_cover)% clouds" else "" end) +
    (if $c.wind_speed_10m != null then
      "\n   💨 \($c.wind_speed_10m) \($u.wind_speed_10m // "km/h")" +
      (if $c.wind_direction_10m != null then
        " \($c.wind_direction_10m | wind_dir)" else "" end) +
      (if $c.wind_gusts_10m != null then
        ", gusts \($c.wind_gusts_10m) \($u.wind_gusts_10m // $u.wind_speed_10m // "km/h")"
      else "" end) else "" end) +
    (if $c.is_day != null then
      "\n   " + (if $c.is_day == 1 then "☀️  Day" else "🌙 Night" end)
    else "" end) +
    (if $c.precipitation != null and ($c.precipitation > 0) then
      "\n   🌧  \($c.precipitation)\($u.precipitation // "mm")" +
      (if $c.rain != null and ($c.rain > 0) then
        " (rain: \($c.rain)\($u.rain // "mm"))" else "" end) +
      (if $c.snowfall != null and ($c.snowfall > 0) then
        " (snow: \($c.snowfall)\($u.snowfall // "cm"))" else "" end)
    else "" end) +
    (if $c.surface_pressure != null then
      "\n   📊 \($c.surface_pressure) \($u.surface_pressure // "hPa")"
    elif $c.pressure_msl != null then
      "\n   📊 \($c.pressure_msl) \($u.pressure_msl // "hPa")"
    else "" end) +
    ($c | to_entries | map(
      select(.key | IN("time","interval","temperature_2m","apparent_temperature",
        "weather_code","relative_humidity_2m","cloud_cover","wind_speed_10m",
        "wind_direction_10m","wind_gusts_10m","is_day","precipitation","rain",
        "showers","snowfall","pressure_msl","surface_pressure") | not) |
      "\n   \(.key | gsub("_"; " ")): \(.value)"
    ) | join(""))
  else "" end;

# ── Porcelain: location metadata ─────────────────────────────────────
def porcelain_meta:
  "latitude=\(.latitude)",
  "longitude=\(.longitude)",
  (if .elevation then "elevation=\(.elevation)" else empty end),
  "timezone=\(.timezone // "GMT")",
  "timezone_abbreviation=\(.timezone_abbreviation // "")",
  "utc_offset_seconds=\(.utc_offset_seconds // 0)";

# ── Porcelain: current conditions ────────────────────────────────────
def porcelain_current:
  (if .current then
    (.current | to_entries[] | "current.\(.key)=\(.value)")
  else empty end),
  (if .current_units then
    (.current_units | to_entries[] | "current_units.\(.key)=\(.value)")
  else empty end);

# ── Porcelain: hourly data + units ───────────────────────────────────
def porcelain_hourly:
  (if .hourly then
    .hourly as $h |
    ($h | keys_unsorted | map(select(. != "time"))) as $vars |
    range(0; ($h.time | length)) as $i |
    $vars[] as $v |
    "hourly.\($h.time[$i]).\($v)=\($h[$v][$i])"
  else empty end),
  (if .hourly_units then
    (.hourly_units | to_entries[] | "hourly_units.\(.key)=\(.value)")
  else empty end);

# ── Porcelain: daily data + units ────────────────────────────────────
def porcelain_daily:
  (if .daily then
    .daily as $d |
    ($d | keys_unsorted | map(select(. != "time"))) as $vars |
    range(0; ($d.time | length)) as $i |
    $vars[] as $v |
    "daily.\($d.time[$i]).\($v)=\($d[$v][$i])"
  else empty end),
  (if .daily_units then
    (.daily_units | to_entries[] | "daily_units.\(.key)=\(.value)")
  else empty end);
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
