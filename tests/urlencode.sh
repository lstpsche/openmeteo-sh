#!/usr/bin/env bash
set -euo pipefail

utf8_locale=$(locale -a | awk 'tolower($0) ~ /^(c|en_us)\.utf-?8$/ && !found { print; found = 1 }')
if [[ -z "$utf8_locale" ]]; then
  printf '%s\n' 'URL-encoding tests require a UTF-8 locale.' >&2
  exit 1
fi
export LC_ALL="$utf8_locale"

root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
# shellcheck source=lib/core.sh
source "$root/lib/core.sh"

assert_encoding() {
  local input="$1" expected="$2" actual
  actual=$(_urlencode "$input")
  if [[ "$actual" != "$expected" ]]; then
    printf 'Encoding %s: expected %s, got %s\n' "$input" "$expected" "$actual" >&2
    exit 1
  fi
}

assert_encoding 'Минск' '%D0%9C%D0%B8%D0%BD%D1%81%D0%BA'
assert_encoding 'São Paulo' 'S%C3%A3o+Paulo'
assert_encoding "St. John's & Co." 'St.+John%27s+%26+Co.'
assert_encoding '-n' '-n'
