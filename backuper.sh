#!/bin/bash


# Global constants
readonly SCRIPT_SUFFIX="_backuper.sh"
readonly BACKUP_SUFFIX="_backuper.zip"
readonly VERSION="v0.3.0"
readonly OWNER="@ErfJabs"


# ANSI color codes
declare -A COLORS=(
    [red]='\033[1;31m' [pink]='\033[1;35m' [green]='\033[1;92m'
    [spring]='\033[38;5;46m' [orange]='\033[1;38;5;208m' [cyan]='\033[1;36m' [reset]='\033[0m'
)

# Logging & Printing functions
print() { echo -e "${COLORS[cyan]}$*${COLORS[reset]}"; }
log() { echo -e "${COLORS[cyan]}[INFO]${COLORS[reset]} $*"; }
warn() { echo -e "${COLORS[orange]}[WARN]${COLORS[reset]} $*" >&2; }
error() { echo -e "${COLORS[red]}[ERROR]${COLORS[reset]} $*" >&2; exit 1; }
success() { echo -e "${COLORS[spring]}${COLORS[green]}[SUCCESS]${COLORS[reset]} $*"; }

# Interactive functions
input() { read -p "$(echo -e "${COLORS[orange]}▶ $1${COLORS[reset]} ")" "$2"; }
confirm() { read -p "$(echo -e "${COLORS[pink]}Press any key to continue...${COLORS[reset]}")"; }

# Error handling
trap 'error "An error occurred. Exiting..."' ERR

# Utility functions
check_root() {
    [[ $EUID -eq 0 ]] || error "This script must be run as root"
}

# Detect package manager
detect_package_manager() {
    if command -v apt-get &>/dev/null; then
        echo "apt"
    elif command -v dnf &>/dev/null; then
        echo "dnf"
    elif command -v yum &>/dev/null; then
        echo "yum"
    elif command -v pacman &>/dev/null; then
        echo "pacman"
    else
        error "Unsupported package manager"
    fi
}

# Update the OS
update_os() {
    local package_manager=$(detect_package_manager)
    log "Updating the system using $package_manager..."
    
    case $package_manager in
        apt)
            apt-get update -y && apt-get upgrade -y || error "Failed to update the system"
            ;;
        dnf|yum)
            $package_manager update -y || error "Failed to update the system"
            ;;
        pacman)
            pacman -Syu --noconfirm || error "Failed to update the system"
            ;;
    esac
    success "System updated successfully"
}

# Install dependencies
install_dependencies() {
    local package_manager=$(detect_package_manager)
    local packages=("curl" "wget" "zip" "cron")

    # Add MySQL/MariaDB client based on OS
    case $package_manager in
        apt)
            packages+=("mysql-client" "mariadb-client")
            ;;
        dnf|yum)
            packages+=("mysql" "mariadb")
            ;;
        pacman)
            packages+=("mariadb-clients")
            ;;
    esac

    log "Installing dependencies: ${packages[*]}..."
    
    case $package_manager in
        apt)
            apt-get install -y "${packages[@]}" || error "Failed to install dependencies"
            ;;
        dnf|yum)
            $package_manager install -y "${packages[@]}" || error "Failed to install dependencies"
            ;;
        pacman)
            pacman -Sy --noconfirm "${packages[@]}" || error "Failed to install dependencies"
            ;;
    esac
    success "Dependencies installed successfully"
}

# Install yq
install_yq() {
    if command -v yq &>/dev/null; then
        success "yq is already installed."
        return
    fi

    log "Installing yq..."
    local ARCH=$(uname -m)
    local YQ_BINARY="yq_linux_amd64"

    [[ "$ARCH" == "aarch64" || "$ARCH" == "arm64" ]] && YQ_BINARY="yq_linux_arm64"

    wget -q "https://github.com/mikefarah/yq/releases/latest/download/$YQ_BINARY" -O /usr/bin/yq || error "Failed to download yq."
    chmod +x /usr/bin/yq || error "Failed to set execute permissions on yq."

    success "yq installed successfully."
}

menu() {
    while true; do
        clear
        print "======== Backuper Menu [$VERSION] ========"
        print "1️) Install Backuper"
        print "2) Exit"
        print ""
        input "Choose an option:" choice
        case $option in
            1)
                start_backup
                ;;
            2)
                print "Thank you for using @ErfJabs script. Goodbye!"
                exit 0
                ;;
            *)
                error "Invalid option, Please select a valid option!"
                ;;
        esac
    done
}

start_backup() {
    generate_remark
    generate_caption
    generate_timer
}


generate_remark() {
    print "[REMARK]\n"
    print "We need a remark for the backup file (e.g., Master, panel, ErfJab).\n"

    while true; do
        input "Enter a remark: " remark

        if ! [[ "$remark" =~ ^[a-zA-Z0-9_]+$ ]]; then
            error "remark must contain only letters, numbers, or underscores."
        elif [ ${#remark} -lt 3 ]; then
            error "remark must be at least 3 characters long."
        elif [ -e "${remark}_backuper.sh" ]; then
            error "File ${remark}_backuper.sh already exists. Choose a different remark."
        else
            success "Backup remark: $remark"
            break
        fi
    done
    sleep 1
}

generate_caption() {
    clear
    print "[CAPTION]\n"
    print "You can add a caption for your backup file (e.g., 'The main server of the company').\n"

    input "Enter your caption (Press Enter to skip): " caption

    if [ -z "$caption" ]; then
        success "No caption provided. Skipping..."
        caption=""
    else
        caption+='\n'
        success "Caption set: $caption"
    fi

    sleep 1
}


generate_timer() {
    clear
    print "[TIMER]\n"
    print "Enter a time interval in minutes for sending backups."
    print "For example, '10' means backups will be sent every 10 minutes.\n"

    while true; do
        input "Enter the number of minutes (1-1440): " minutes

        if ! [[ "$minutes" =~ ^[0-9]+$ ]]; then
            error "Please enter a valid number."
        elif [ "$minutes" -lt 1 ] || [ "$minutes" -gt 1440 ]; then
            error "Number must be between 1 and 1440."
        else
            break
        fi
    done

    if [ "$minutes" -le 59 ]; then
        cron_timer="*/$minutes * * * *"
    elif [ "$minutes" -le 1439 ]; then
        hours=$((minutes / 60))
        remaining_minutes=$((minutes % 60))
        if [ "$remaining_minutes" -eq 0 ]; then
            cron_timer="0 */$hours * * *"
        else
            cron_timer="*/$remaining_minutes */$hours * * *"
        fi
    else
        cron_timer="0 0 * * *" 
    fi
    success "Cron job set to run every $minutes minutes: $cron_timer"
    sleep 1
}
