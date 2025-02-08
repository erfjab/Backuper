#!/bin/bash

# ANSI color codes
declare -r -A COLORS=(
    [RED]='\033[0;31m'
    [GREEN]='\033[0;32m'
    [YELLOW]='\033[0;33m'
    [BLUE]='\033[0;34m'
    [RESET]='\033[0m'
)


# Logging functions
log() { printf "${COLORS[BLUE]}[INFO]${COLORS[RESET]} %s\n" "$*"; }
warn() { printf "${COLORS[YELLOW]}[WARN]${COLORS[RESET]} %s\n" "$*" >&2; }
error() { printf "${COLORS[RED]}[ERROR]${COLORS[RESET]} %s\n" "$*" >&2; exit 1; }
success() { printf "${COLORS[GREEN]}[SUCCESS]${COLORS[RESET]} %s\n" "$*"; }

