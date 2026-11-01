#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# Copyright (c) 2024-2026 Vivek Umrao and SpinDB contributors.
# ==============================================================================
# lib/engine.sh - Platform Detection, Container Engine Runtime & Pre-flight Diagnostics
# ==============================================================================

[[ -n "${_LIB_ENGINE_LOADED:-}" ]] && return 0
_LIB_ENGINE_LOADED=1

detect_os() {
  OS_FAMILY="unknown"
  OS_NAME="Linux"
  OS_VERSION=""
  IS_WSL=false

  if [[ -f /proc/version ]] && grep -qi "microsoft" /proc/version; then
    IS_WSL=true
  fi

  if [[ "$OSTYPE" == "darwin"* ]]; then
    OS_FAMILY="macos"
    OS_NAME="macOS $(sw_vers -productVersion 2>/dev/null || echo '')"
  elif [[ -f /etc/os-release ]]; then
    # shellcheck disable=SC1091
    source /etc/os-release
    OS_NAME="${PRETTY_NAME:-$NAME}"
    OS_VERSION="${VERSION_ID:-}"
    case "${ID,,}" in
      ubuntu|debian|pop|mint|kali|raspbian)
        OS_FAMILY="debian_like"
        ;;
      fedora|rhel|centos|rocky|almalinux)
        OS_FAMILY="rhel_like"
        ;;
      arch|manjaro|endeavouros)
        OS_FAMILY="arch_like"
        ;;
      alpine)
        OS_FAMILY="alpine"
        ;;
      opensuse*|sles)
        OS_FAMILY="suse"
        ;;
      *)
        if [[ "${ID_LIKE,,}" =~ debian ]]; then
          OS_FAMILY="debian_like"
        elif [[ "${ID_LIKE,,}" =~ (rhel|fedora|centos) ]]; then
          OS_FAMILY="rhel_like"
        elif [[ "${ID_LIKE,,}" =~ arch ]]; then
          OS_FAMILY="arch_like"
        else
          OS_FAMILY="linux_generic"
        fi
        ;;
    esac
  fi
}

get_install_command() {
  local package="$1"
  local target_family="${2:-${OS_FAMILY:-unknown}}"
  if [[ "${target_family}" == "unknown" ]]; then
    detect_os
    target_family="${OS_FAMILY}"
  fi

  case "${target_family}" in
    debian_like)
      case "${package}" in
        podman) echo "sudo apt-get update && sudo apt-get install -y podman podman-docker" ;;
        docker) echo "sudo apt-get update && sudo apt-get install -y docker.io docker-buildx" ;;
        *)      echo "sudo apt-get update && sudo apt-get install -y ${package}" ;;
      esac
      ;;
    rhel_like)
      case "${package}" in
        podman) echo "sudo dnf install -y podman" ;;
        docker) echo "sudo dnf install -y docker && sudo systemctl enable --now docker" ;;
        *)      echo "sudo dnf install -y ${package}" ;;
      esac
      ;;
    arch_like)
      case "${package}" in
        podman) echo "sudo pacman -S --noconfirm podman" ;;
        docker) echo "sudo pacman -S --noconfirm docker && sudo systemctl enable --now docker" ;;
        *)      echo "sudo pacman -S --noconfirm ${package}" ;;
      esac
      ;;
    alpine)
      case "${package}" in
        podman) echo "sudo apk add podman" ;;
        docker) echo "sudo apk add docker && sudo rc-update add docker boot && sudo service docker start" ;;
        *)      echo "sudo apk add ${package}" ;;
      esac
      ;;
    macos)
      case "${package}" in
        podman) echo "brew install podman && podman machine init && podman machine start" ;;
        docker) echo "brew install --cask docker" ;;
        *)      echo "brew install ${package}" ;;
      esac
      ;;
    *)
      case "${package}" in
        podman) echo "Install podman via system package manager (e.g. apt, dnf, pacman, brew)" ;;
        docker) echo "Install docker from https://docs.docker.com/engine/install/" ;;
        *)      echo "Install ${package} using your system package manager" ;;
      esac
      ;;
  esac
}

run_preflight_check() {
  detect_os
  local missing_tools=()
  local podman_present=false
  local docker_present=false
  local podman_version=""
  local docker_version=""

  log_header "HOST ENVIRONMENT & PRE-FLIGHT SYSTEM CHECKUP"
  printf "  ${CLR_BOLD}Operating System:${CLR_RESET} %s" "${OS_NAME}"
  if [[ "${IS_WSL}" == "true" ]]; then
    printf " [WSL2 Environment]"
  fi
  printf "\n"
  printf "  ${CLR_BOLD}OS Family / Arch:${CLR_RESET} %s (%s)\n" "${OS_FAMILY}" "$(uname -m)"
  printf "  ${CLR_BOLD}Kernel Release:${CLR_RESET}   %s\n" "$(uname -r)"

  # Check Shell version
  local bash_version="${BASH_VERSION:-unknown}"
  if [[ "${BASH_VERSINFO[0]:-0}" -ge 4 ]]; then
    printf "  ${CLR_BOLD}Shell Version:${CLR_RESET}    GNU Bash %s ${CLR_GREEN}[PASS]${CLR_RESET}\n" "${bash_version}"
  else
    printf "  ${CLR_BOLD}Shell Version:${CLR_RESET}    GNU Bash %s ${CLR_RED}[FAIL - Bash >= 4.0 required]${CLR_RESET}\n" "${bash_version}"
    missing_tools+=("bash")
  fi

  # Check required POSIX utilities
  local required_tools=("awk" "sed" "grep" "cut" "tr" "mktemp" "mkdir" "cp" "chmod" "curl")
  local tool_failures=()

  for tool in "${required_tools[@]}"; do
    if ! command -v "${tool}" >/dev/null 2>&1; then
      tool_failures+=("${tool}")
      missing_tools+=("${tool}")
    fi
  done

  if [[ ${#tool_failures[@]} -eq 0 ]]; then
    printf "  ${CLR_BOLD}Core Utilities:${CLR_RESET}   awk, sed, grep, cut, tr, mktemp, curl ${CLR_GREEN}[ALL AVAILABLE]${CLR_RESET}\n"
  else
    printf "  ${CLR_BOLD}Core Utilities:${CLR_RESET}   ${CLR_RED}[MISSING: %s]${CLR_RESET}\n" "${tool_failures[*]}"
  fi

  # Container Engines Checkup
  local podman_operational=false
  local docker_operational=false

  if command -v podman >/dev/null 2>&1; then
    podman_present=true
    podman_version="$(podman --version 2>/dev/null || echo 'available')"
    if podman info >/dev/null 2>&1; then
      podman_operational=true
    fi
  fi

  if command -v docker >/dev/null 2>&1; then
    docker_present=true
    docker_version="$(docker --version 2>/dev/null || echo 'available')"
    if docker info >/dev/null 2>&1; then
      docker_operational=true
    fi
  fi

  printf -- "-------------------------------------------------------------------------------\n"
  printf "  ${CLR_BOLD}Container Engines:${CLR_RESET}\n"

  if [[ "${podman_present}" == "true" ]]; then
    if [[ "${podman_operational}" == "true" ]]; then
      printf "    * Podman (Primary):  ${CLR_GREEN}%s [ACTIVE]${CLR_RESET}\n" "${podman_version}"
    else
      printf "    * Podman (Primary):  ${CLR_YELLOW}%s [NON-OPERATIONAL: Rootless subuid/subgid or socket unavailable]${CLR_RESET}\n" "${podman_version}"
    fi
  else
    printf "    * Podman (Primary):  ${CLR_YELLOW}NOT INSTALLED (Recommended for rootless execution)${CLR_RESET}\n"
  fi

  if [[ "${docker_present}" == "true" ]]; then
    if [[ "${docker_operational}" == "true" ]]; then
      local docker_state="[STANDBY]"
      if [[ "${podman_operational}" != "true" ]]; then
        docker_state="[ACTIVE AS PRIMARY/FALLBACK]"
      fi
      printf "    * Docker (Engine):   ${CLR_GREEN}%s %s${CLR_RESET}\n" "${docker_version}" "${docker_state}"
    else
      printf "    * Docker (Engine):   ${CLR_YELLOW}%s [INSTALLED BUT DAEMON NOT RESPONDING]${CLR_RESET}\n" "${docker_version}"
    fi
  else
    printf "    * Docker (Fallback): ${CLR_YELLOW}NOT INSTALLED${CLR_RESET}\n"
  fi

  printf "${CLR_BOLD}${CLR_CYAN}===============================================================================${CLR_RESET}\n"

  # Report missing core tools
  if [[ ${#tool_failures[@]} -gt 0 ]]; then
    log_error "Required system utilities are missing on your host!"
    printf "Please install them by executing:\n\n"
    for tool in "${tool_failures[@]}"; do
      printf "  ${CLR_BOLD}%s${CLR_RESET}\n" "$(get_install_command "${tool}")"
    done
    printf "\n"
    exit 1
  fi

  # Determine active container engine
  if [[ -n "${CONTAINER_ENGINE}" ]]; then
    if ! command -v "${CONTAINER_ENGINE}" >/dev/null 2>&1; then
      log_error "Explicitly requested engine '${CONTAINER_ENGINE}' is not installed!"
      printf "Run this command to install it for your %s system:\n\n" "${OS_NAME}"
      printf "  ${CLR_BOLD}${CLR_GREEN}%s${CLR_RESET}\n\n" "$(get_install_command "${CONTAINER_ENGINE}")"
      exit 1
    elif ! "${CONTAINER_ENGINE}" info >/dev/null 2>&1; then
      log_error "Engine '${CONTAINER_ENGINE}' is installed on PATH but its runtime daemon or namespace is not operational!"
      exit 1
    fi
  elif [[ "${podman_operational}" == "true" ]]; then
    CONTAINER_ENGINE="podman"
  elif [[ "${docker_operational}" == "true" ]]; then
    CONTAINER_ENGINE="docker"
    if [[ "${podman_present}" == "true" ]]; then
      printf "\n"
      printf "${CLR_BOLD}${CLR_YELLOW}+-----------------------------------------------------------------------------+${CLR_RESET}\n"
      printf "${CLR_BOLD}${CLR_YELLOW}| [NOTICE] Podman is installed but its rootless namespace/socket is inactive. |${CLR_RESET}\n"
      printf "${CLR_BOLD}${CLR_YELLOW}| Automatically utilizing operational Docker runtime.                         |${CLR_RESET}\n"
      printf "${CLR_BOLD}${CLR_YELLOW}+-----------------------------------------------------------------------------+${CLR_RESET}\n"
    else
      printf "\n"
      printf "${CLR_BOLD}${CLR_YELLOW}+-----------------------------------------------------------------------------+${CLR_RESET}\n"
      printf "${CLR_BOLD}${CLR_YELLOW}| [WARNING] Podman is not installed on this system.                           |${CLR_RESET}\n"
      printf "${CLR_BOLD}${CLR_YELLOW}| Falling back to Docker engine.                                              |${CLR_RESET}\n"
      printf "${CLR_BOLD}${CLR_YELLOW}| For enhanced security (rootless, daemonless), migrating to Podman is advised.|${CLR_RESET}\n"
      printf "${CLR_BOLD}${CLR_YELLOW}+-----------------------------------------------------------------------------+${CLR_RESET}\n"
      printf "To install Podman on your %s host, simply run:\n\n" "${OS_NAME}"
      printf "  ${CLR_BOLD}${CLR_GREEN}%s${CLR_RESET}\n\n" "$(get_install_command 'podman')"
    fi
  else
    printf "\n"
    printf "${CLR_BOLD}${CLR_RED}+-----------------------------------------------------------------------------+${CLR_RESET}\n"
    printf "${CLR_BOLD}${CLR_RED}| [ERROR] No operational container engine found on your host!                 |${CLR_RESET}\n"
    printf "${CLR_BOLD}${CLR_RED}| Neither Podman nor Docker is running or accessible without root.            |${CLR_RESET}\n"
    printf "${CLR_BOLD}${CLR_RED}+-----------------------------------------------------------------------------+${CLR_RESET}\n"
    printf "Please ensure Docker service is started or install Podman on %s:\n\n" "${OS_NAME}"
    printf "  ${CLR_BOLD}${CLR_GREEN}%s${CLR_RESET}\n\n" "$(get_install_command 'podman')"
    printf "Alternative: Install/start Docker:\n"
    printf "  ${CLR_BOLD}%s${CLR_RESET}\n\n" "$(get_install_command 'docker')"
    exit 1
  fi

  if [[ "${PREFLIGHT_ONLY:-false}" == "true" ]]; then
    log_success "Pre-flight check complete. System is ready to run containers with '${CONTAINER_ENGINE}'."
    exit 0
  fi
}
