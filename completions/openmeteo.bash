# bash completion for openmeteo CLI
# Source this file or place in /etc/bash_completion.d/ or
# $(brew --prefix)/share/bash-completion/completions/

_openmeteo() {
  local cur prev words cword
  _init_completion || return

  local commands="weather geo history ensemble climate marine air-quality flood elevation satellite"
  local global_opts="--api-key= --porcelain --raw --verbose --help --version"

  # Determine the subcommand (first non-option word after "openmeteo")
  local subcmd=""
  local i
  for (( i=1; i < cword; i++ )); do
    case "${words[i]}" in
      -*) ;;
      *)  subcmd="${words[i]}"; break ;;
    esac
  done

  # No subcommand yet — complete commands or global options
  if [[ -z "$subcmd" ]]; then
    if [[ "$cur" == -* ]]; then
      COMPREPLY=( $(compgen -W "$global_opts" -- "$cur") )
    else
      COMPREPLY=( $(compgen -W "$commands" -- "$cur") )
    fi
    return
  fi

  # Per-subcommand flags
  local opts=""
  case "$subcmd" in
    weather)
      opts="--lat= --lon= --city= --country= --current --daily --hourly
            --forecast-days= --past-days= --start-date= --end-date=
            --hourly-params= --daily-params= --current-params=
            --temperature-unit= --wind-speed-unit= --precipitation-unit=
            --timezone= --model= --api-key= --porcelain --raw --help"
      ;;
    geo)
      opts="--search= --count= --language= --country= --api-key= --porcelain --raw --help"
      ;;
    history)
      opts="--lat= --lon= --city= --country= --start-date= --end-date=
            --hourly-params= --daily-params=
            --temperature-unit= --wind-speed-unit= --precipitation-unit=
            --timezone= --model= --cell-selection= --api-key= --porcelain --raw --help"
      ;;
    ensemble)
      opts="--lat= --lon= --city= --country= --models= --hourly-params= --daily-params=
            --forecast-days= --past-days= --start-date= --end-date=
            --temperature-unit= --wind-speed-unit= --precipitation-unit=
            --timezone= --cell-selection= --api-key= --porcelain --raw --help"
      ;;
    climate)
      opts="--lat= --lon= --city= --country= --start-date= --end-date=
            --models= --daily-params=
            --temperature-unit= --wind-speed-unit= --precipitation-unit=
            --cell-selection= --disable-bias-correction --api-key= --porcelain --raw --help"
      ;;
    marine)
      opts="--lat= --lon= --city= --country= --current --forecast-days= --past-days=
            --hourly-params= --daily-params= --current-params=
            --length-unit= --wind-speed-unit= --timezone= --model=
            --cell-selection= --start-date= --end-date= --api-key= --porcelain --raw --help"
      ;;
    air-quality)
      opts="--lat= --lon= --city= --country= --current --forecast-days= --past-days=
            --hourly-params= --daily-params= --current-params=
            --domains= --timezone= --cell-selection= --start-date= --end-date=
            --api-key= --porcelain --raw --help"
      ;;
    flood)
      opts="--lat= --lon= --city= --country= --forecast-days= --past-days=
            --daily-params= --model= --cell-selection= --ensemble
            --start-date= --end-date= --api-key= --porcelain --raw --help"
      ;;
    elevation)
      opts="--lat= --lon= --city= --country= --api-key= --porcelain --raw --help"
      ;;
    satellite)
      opts="--lat= --lon= --city= --country= --forecast-days= --past-days=
            --hourly-params= --daily-params= --model= --timezone=
            --cell-selection= --tilt= --azimuth= --temporal-resolution=
            --start-date= --end-date= --api-key= --porcelain --raw --help"
      ;;
  esac

  COMPREPLY=( $(compgen -W "$opts" -- "$cur") )

  # If the completion ends with '=', don't add a trailing space
  if [[ ${#COMPREPLY[@]} -eq 1 && "${COMPREPLY[0]}" == *= ]]; then
    compopt -o nospace
  fi
} &&
complete -F _openmeteo openmeteo
