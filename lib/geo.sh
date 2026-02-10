#!/usr/bin/env bash
# geo.sh -- internal geocoding helper (resolve --city/--country to lat/lon)

# Resolve a city name (and optional country code) to latitude/longitude
# using the OpenMeteo Geocoding API. Returns the top result.
#
# Sets global variables: RESOLVED_LAT, RESOLVED_LON, RESOLVED_NAME, RESOLVED_COUNTRY
#
# Usage: _resolve_location "London" "GB"
_resolve_location() {
  local city="$1"
  local country="${2:-}"

  if [[ -z "${city}" ]]; then
    _die "cannot resolve location: no city name provided"
  fi

  local encoded_city
  encoded_city=$(_urlencode "${city}")

  local qs="name=${encoded_city}&count=1&language=en&format=json"
  if [[ -n "${country}" ]]; then
    qs="${qs}&countryCode=${country}"
  fi

  local response
  response=$(_request "${BASE_URL_GEOCODING}" "${qs}")

  local results_count
  results_count=$(echo "${response}" | jq '.results | length' 2>/dev/null)

  # Fallback: if country was provided but no results found, retry without it.
  # The Geocoding API expects ISO 3166-1 alpha-2 codes (e.g. BY, GB);
  # full country names like "Belarus" won't match.
  if [[ -z "${results_count}" || "${results_count}" -eq 0 ]] && [[ -n "${country}" ]]; then
    _verbose "no results for '${city}' with country '${country}', retrying without country filter"
    local fallback_qs="name=${encoded_city}&count=1&language=en&format=json"
    response=$(_request "${BASE_URL_GEOCODING}" "${fallback_qs}")
    results_count=$(echo "${response}" | jq '.results | length' 2>/dev/null)

    if [[ -n "${results_count}" && "${results_count}" -gt 0 ]]; then
      _warn "country '${country}' did not match; showing best result without country filter"
      _warn "hint: --country expects an ISO 3166-1 alpha-2 code (e.g. BY, GB, DE, US)"
    fi
  fi

  if [[ -z "${results_count}" || "${results_count}" -eq 0 ]]; then
    _die "location not found: '${city}'${country:+ (country: ${country})}"
  fi

  RESOLVED_LAT=$(echo "${response}" | jq -r '.results[0].latitude')
  RESOLVED_LON=$(echo "${response}" | jq -r '.results[0].longitude')
  RESOLVED_NAME=$(echo "${response}" | jq -r '.results[0].name')
  RESOLVED_COUNTRY=$(echo "${response}" | jq -r '.results[0].country // empty')

  if [[ -z "${RESOLVED_LAT}" || "${RESOLVED_LAT}" == "null" ]]; then
    _die "failed to resolve coordinates for '${city}'"
  fi
}
