#!/bin/bash

# Global constants
readonly SCRIPT_SUFFIX="_backuper_script.sh"
readonly TAG="_backuper."
readonly BACKUP_SUFFIX="${TAG}zip"
readonly DATABASE_SUFFIX="${TAG}sql"
readonly LOGS_SUFFIX="${TAG}log"
readonly VERSION="v0.4.0"
readonly OWNER="@ErfJabs"
readonly SPONSORTEXT="خرید سرور مجازی ایران OkaCloud با تانلینگ اختصاصی رایگان"
readonly SPONSORLINK="https://t.me/OkaCloud"


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
wrong() { echo -e "${COLORS[red]}[WRONG]${COLORS[reset]} $*" >&2; }
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

install_dependencies() {
    local package_manager=$(detect_package_manager)
    local packages=("wget" "zip" "cron" "msmtp" "mutt")

    log "Installing dependencies: ${packages[*]}..."
    
    case $package_manager in
        apt)
            apt-get install -y "${packages[@]}" || error "Failed to install dependencies"
            if ! apt-get install -y default-mysql-client; then
                apt-get install -y mariadb-client || error "Failed to install MySQL/MariaDB client"
            fi
            ;;
        dnf|yum)
            packages+=("mariadb")
            $package_manager install -y "${packages[@]}" || error "Failed to install dependencies"
            ;;
        pacman)
            packages+=("mariadb")
            pacman -Sy --noconfirm "${packages[@]}" || error "Failed to install dependencies"
            ;;
    esac
    success "Dependencies installed successfully"
}

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
    update_os
    install_dependencies
    install_yq
    while true; do
        clear
        print "======== Backuper Menu [$VERSION] ========"
        print ""
        print "1️) Install Backuper"
        print "2) Remove All Backupers"
        print "3) Run All Backup Scripts"
        print "4) Exit"
        print ""
        input "Choose an option:" choice
        case $choice in
            1)
                start_backup
                ;;
            2)
                cleanup_backups
                ;;
            3)
                if compgen -G "/root/*${SCRIPT_SUFFIX}" > /dev/null; then
                    for script in /root/*${SCRIPT_SUFFIX}; do
                        log "Running backup script: $script"
                        bash "$script"
                    done
                else
                    warn "No backup scripts found in /root directory"
                fi
                confirm
                ;;
            4)
                print "Thank you for using @ErfJabs script. Goodbye!"
                exit 0
                ;;
            *)
                wrong "Invalid option, Please select a valid option!"
                ;;
        esac
    done
}

cleanup_backups() {
    print "Removing all backups and cron jobs..."
    
    rm -rf /root/*"$SCRIPT_SUFFIX" /root/*"$TAG"* /root/*_backuper.sh /root/ac-backup*.sh /root/*backuper*.sh
    
    crontab -l | grep -v "$SCRIPT_SUFFIX" | crontab -

    success "All backups and cron jobs have been removed."
    sleep 1
}

start_backup() {
    generate_remark
    generate_timer
    generate_template
    toggle_directories
    generate_platform
    generate_password
    generate_script
}

generate_remark() {
    clear
    print "[REMARK]\n"
    print "We need a remark for the backup file (e.g., Master, panel, ErfJab).\n"

    while true; do
        input "Enter a remark: " REMARK

        if ! [[ "$REMARK" =~ ^[a-zA-Z0-9_]+$ ]]; then
            wrong "Remark must contain only letters, numbers, or underscores."
        elif [ ${#REMARK} -lt 3 ]; then
            wrong "Remark must be at least 3 characters long."
        elif [ -e "${REMARK}${SCRIPT_SUFFIX}" ]; then
            wrong "File ${REMARK}${SCRIPT_SUFFIX} already exists. Choose a different remark."
        else
            success "Backup remark: $REMARK"
            break
        fi
    done
    sleep 1
}

generate_caption() {
    clear
    print "[CAPTION]\n"
    print "You can add a caption for your backup file (e.g., 'The main server of the company').\n"

    input "Enter your caption (Press Enter to skip): " CAPTION

    if [ -z "$CAPTION" ]; then
        success "No caption provided. Skipping..."
        CAPTION=""
    else
        CAPTION+='\n'
        success "Caption set: $CAPTION"
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
            wrong "Please enter a valid number."
        elif [ "$minutes" -lt 1 ] || [ "$minutes" -gt 1440 ]; then
            wrong "Number must be between 1 and 1440."
        else
            break
        fi
    done

    if [ "$minutes" -le 59 ]; then
        TIMER="*/$minutes * * * *"
    elif [ "$minutes" -le 1439 ]; then
        hours=$((minutes / 60))
        remaining_minutes=$((minutes % 60))
        if [ "$remaining_minutes" -eq 0 ]; then
            TIMER="0 */$hours * * *"
        else
            TIMER="*/$remaining_minutes */$hours * * *"
        fi
    else
        TIMER="0 0 * * *" 
    fi
    success "Cron job set to run every $minutes minutes: $TIMER"
    sleep 1
}

generate_template() {
    clear
    print "[TEMPLATE]\n"
    print "Choose a backup template. You can add or remove custom DIRECTORIES after selecting.\n"
    print "1) X-ui"
    print "2) S-ui"
    print "3) Hiddify"
    print "4) Marzneshin"
    print "5) Marzneshin Logs"
    print "6) Marzban"
    print "7) Marzban Logs"
    print "8) MirzaBot"
    print "9) WalBot"
    print "10) HolderBot"
    print "11) MarzHelp + Marzban"
    print "0) Custom"
    print ""
    while true; do
        input "Enter your template number: " TEMPLATE
        case $TEMPLATE in
            1)
                xui_template
                break
                ;;
            2)
                sui_template
                break
                ;;
            3)
                hiddify_template
                break
                ;;
            4)
                marzneshin_template
                break
                ;;
            5)
                marzneshin_logs_template
                break
                ;;
            6)
                marzban_template
                break
                ;;
            7)
                marzban_logs_template
                break
                ;;
            8)
                mirzabot_template
                break
                ;;
            9)
                walbot_template
                break
                ;;
            10)
                holderbot_template
                break
                ;;
            11)
                marzhelp_template
                break
                ;;
            0)
                break
                ;;
            *)
                wrong "Invalid option. Please choose a valid number!"
                ;;
        esac
    done
}

add_directories() {
    local base_dir="$1"

    # Check if base directory exists
    [[ ! -d "$base_dir" ]] && { warn "Directory not found: $base_dir"; return; }

    # Find directories and filter based on exclude patterns
    mapfile -t items < <(find "$base_dir" -mindepth 1 -maxdepth 1 -type d \( -name "*mysql*" -prune -o -name "*mariadb*" -prune \) -o -print)

    for item in "${items[@]}"; do
        local exclude_item=false

        # Check if item matches any exclude pattern
        for pattern in "${exclude_patterns[@]}"; do
            if [[ "$item" =~ $pattern ]]; then
                exclude_item=true
                break
            fi
        done

        # Add item to backup list if it doesn't match any exclude pattern
        if ! $exclude_item; then
            success "Added to backup: $item"
            DIRECTORIES+=("$item")
        fi
    done
}

toggle_directories() {
    clear
    print "[TOGGLE DIRECTORIES]\n"
    print "Enter directories to add or remove. Type 'done' when finished.\n"
    
    while true; do
        print "\nCurrent directories:"
        for dir in "${DIRECTORIES[@]}"; do
            [[ -n "$dir" ]] && success "\t- $dir"
        done
        print ""

        input "Enter a path (or 'done' to finish): " path

        if [[ "$path" == "done" ]]; then
            break
        elif [[ ! -e "$path" ]]; then
            wrong "Path does not exist: $path"
        elif [[ " ${DIRECTORIES[*]} " =~ " ${path} " ]]; then
            DIRECTORIES=("${DIRECTORIES[@]/$path}")
            success "Removed from list: $path"
        else
            DIRECTORIES+=("$path")
            success "Added to list: $path"
        fi
    done
    BACKUP_DIRECTORIES="${DIRECTORIES[*]}"
}

holderbot_template() {
    log "Checking HolderBot configuration..."
    
    # Set default value for HOLDER_FOLDER if not set
    local HOLDER_FOLDER="/opt/erfjab/holderbot/"

    # Check if the directory exists
    if [ ! -d "$HOLDER_FOLDER" ]; then
        error "Directory not found: $HOLDER_FOLDER"
        return 1
    fi

    # Add the directory to BACKUP_DIRECTORIES
    add_directories "$HOLDER_FOLDER"

    # Export backup variables
    BACKUP_DIRECTORIES="${DIRECTORIES[*]}"
    log "Complete HolderBot"
    confirm
}

walbot_template() {
    log "Checking WalBot configuration..."
    
    # Set default value for WALDB_FOLDER if not set
    local WALDB_FOLDER="/opt/walbot/"

    # Check if the directory exists
    if [ ! -d "$WALDB_FOLDER" ]; then
        error "Directory not found: $WALDB_FOLDER"
        return 1
    fi

    # Add the directory to BACKUP_DIRECTORIES
    add_directories "$WALDB_FOLDER"

    # Export backup variables
    BACKUP_DIRECTORIES="${DIRECTORIES[*]}"
    log "Complete WalBot"
    confirm
}

xui_template() {
    log "Checking X-ui configuration..."
    
    # Set default value for XUI_DB_FOLDER if not set
    local XUI_DB_FOLDER="${XUI_DB_FOLDER:-/etc/x-ui}"

    # Check if the directory exists
    if [ ! -d "$XUI_DB_FOLDER" ]; then
        error "Directory not found: $XUI_DB_FOLDER"
        return 1
    fi

    # Add the directory to BACKUP_DIRECTORIES
    add_directories "$XUI_DB_FOLDER"

    # Export backup variables
    BACKUP_DIRECTORIES="${DIRECTORIES[*]}"
    log "Complete X-ui"
    confirm
}

sui_template() {
    log "Checking S-ui configuration..."
    
    # Set default value for XUI_DB_FOLDER if not set
    local SUI_DB_FOLDER="${SUI_DB_FOLDER:-/usr/local/s-ui/db}"

    # Check if the directory exists
    if [ ! -d "$SUI_DB_FOLDER" ]; then
        error "Directory not found: $SUI_DB_FOLDER"
        return 1
    fi

    # Add the directory to BACKUP_DIRECTORIES
    add_directories "$SUI_DB_FOLDER"

    # Export backup variables
    BACKUP_DIRECTORIES="${DIRECTORIES[*]}"
    log "Complete S-ui"
    confirm
}

marzneshin_logs_template() {
    log "Checking Marzneshin configuration..."
    local docker_compose_file="/etc/opt/marzneshin/docker-compose.yml"

    # Check if docker-compose file exists
    if [[ ! -f "$docker_compose_file" ]]; then
        error "Docker compose file not found: $docker_compose_file"
        return 1
    fi

    # Define log file path
    local DB_PATH="/root/_${REMARK}${LOGS_SUFFIX}"

    # Check if marzneshin command exists
    if ! command -v marzneshin &> /dev/null; then
        error "marzneshin command not found. Please ensure it is installed."
        return 1
    fi

    # Run marzneshin logs command
    if ! marzneshin logs --no-follow > "$DB_PATH"; then
        error "Failed to export Marzneshin logs to $DB_PATH"
        return 1
    fi

    # Add log file path to DIRECTORIES
    DIRECTORIES=()
    DIRECTORIES+=($DB_PATH)

    # Export backup variables
    BACKUP_DIRECTORIES="${DIRECTORIES[*]}"
    log "Marzneshin logs backup completed successfully."
    confirm
}

marzneshin_template() {
    log "Checking Marzneshin configuration..."
    local docker_compose_file="/etc/opt/marzneshin/docker-compose.yml"

    # Check if docker-compose file exists
    [[ -f "$docker_compose_file" ]] || { error "Docker compose file not found: $docker_compose_file"; return 1; }

    # Extract database configuration
    local db_type db_name db_password db_port
    DB_TYPE=$(yq eval '.services.db.image' "$docker_compose_file")
    DB_NAME=$(yq eval '.services.db.environment.MARIADB_DATABASE // .services.db.environment.MYSQL_DATABASE' "$docker_compose_file")
    DB_PASSWORD=$(yq eval '.services.db.environment.MARIADB_ROOT_PASSWORD // .services.db.environment.MYSQL_ROOT_PASSWORD' "$docker_compose_file")
    DB_PORT=$(yq eval '.services.db.ports[0]' "$docker_compose_file" | cut -d':' -f2)

    # Determine database type
    if [[ "$DB_TYPE" == *"mariadb"* ]]; then
        DB_TYPE="mariadb"
    elif [[ "$DB_TYPE" == *"mysql"* ]]; then
        DB_TYPE="mysql"
    else
        DB_TYPE="sqlite"
    fi

    # Validate database password for non-sqlite databases
    if [[ "$DB_TYPE" != "sqlite" && -z "$DB_PASSWORD" ]]; then
        error "Database password not found"
        return 1
    fi

    # Setup backup configuration
    local DB_PATH="/root/_${REMARK}${DATABASE_SUFFIX}"
    DIRECTORIES=()

    # Scan default DIRECTORIES
    log "Scanning DIRECTORIES..."
    add_directories "/etc/opt/marzneshin"

    # Extract volumes from docker-compose
    log "Extracting volumes from docker-compose..."
    for service in $(yq eval '.services | keys | .[]' "$docker_compose_file"); do
        for volume in $(yq eval ".services.$service.volumes | .[]" "$docker_compose_file" 2>/dev/null | awk -F ':' '{print $1}'); do
            [[ -d "$volume" && ! "$volume" =~ /(mysql|mariadb)$ ]] && add_directories "$volume"
        done
    done

    # Generate backup command for non-sqlite databases
    if [[ "$DB_TYPE" != "sqlite" ]]; then
        BACKUP_DB_COMMAND="mysqldump -h 127.0.0.1 --column-statistics=0 -P $DB_PORT -u root -p'$DB_PASSWORD' '$DB_NAME' > $DB_PATH"
        DIRECTORIES+=($DB_PATH)
    fi

    # Export backup variables
    BACKUP_DIRECTORIES="${DIRECTORIES[*]}"
    log "Complete Marzneshin"
    confirm
}

marzban_logs_template() {
    log "Checking Marzban configuration..."
    local docker_compose_file="/opt/marzban/docker-compose.yml"

    # Check if docker-compose file exists
    if [[ ! -f "$docker_compose_file" ]]; then
        error "Docker compose file not found: $docker_compose_file"
        return 1
    fi

    # Define log file path
    local DB_PATH="/root/_${REMARK}${LOGS_SUFFIX}"

    # Check if marzban command exists
    if ! command -v marzban &> /dev/null; then
        error "marzban command not found. Please ensure it is installed."
        return 1
    fi

    # Run marzban logs command
    if ! marzban logs --no-follow > "$DB_PATH"; then
        error "Failed to export marzban logs to $DB_PATH"
        return 1
    fi

    # Add log file path to DIRECTORIES
    DIRECTORIES=()
    DIRECTORIES+=($DB_PATH)

    # Export backup variables
    BACKUP_DIRECTORIES="${DIRECTORIES[*]}"
    log "marzban logs backup completed successfully."
    confirm
}

marzban_template() {
    log "Checking environment file..."
    local env_file="/opt/marzban/.env"

    [[ -f "$env_file" ]] || { error "Environment file not found: $env_file"; return 1; }

    local db_type db_name db_user db_password db_host db_port
    local BACKUP_DIRECTORIES=("/var/lib/marzban")  # Add default volume

    # Extract SQLALCHEMY_DATABASE_URL from .env file
    local SQLALCHEMY_DATABASE_URL=$(grep -v '^#' "$env_file" | grep 'SQLALCHEMY_DATABASE_URL' | awk -F '=' '{print $2}' | tr -d ' ' | tr -d '"' | tr -d "'")

    if [[ -z "$SQLALCHEMY_DATABASE_URL" || "$SQLALCHEMY_DATABASE_URL" == *"sqlite3"* ]]; then
        db_type="sqlite3"
        db_name=""
        db_user=""
        db_password=""
        db_host=""
        db_port=""
    else
        # Parse SQLALCHEMY_DATABASE_URL to extract database details
        if [[ "$SQLALCHEMY_DATABASE_URL" =~ ^(mysql\+pymysql|mariadb\+pymysql)://([^:]+):([^@]+)@([^:]+):([0-9]+)/(.+)$ ]]; then
            db_type="${BASH_REMATCH[1]%%+*}"  # Extract mysql or mariadb
            db_user="${BASH_REMATCH[2]}"
            db_password="${BASH_REMATCH[3]}"
            db_host="${BASH_REMATCH[4]}"
            db_port="${BASH_REMATCH[5]}"
            db_name="${BASH_REMATCH[6]}"
        elif [[ "$SQLALCHEMY_DATABASE_URL" =~ ^(mysql\+pymysql|mariadb\+pymysql)://([^:]+):([^@]+)@([0-9.]+)/(.+)$ ]]; then
            db_type="${BASH_REMATCH[1]%%+*}"  # Extract mysql or mariadb
            db_user="${BASH_REMATCH[2]}"
            db_password="${BASH_REMATCH[3]}"
            db_host="${BASH_REMATCH[4]}"
            db_port="3306"  # Default MySQL/MariaDB port
            db_name="${BASH_REMATCH[5]}"
        else
            error "Invalid SQLALCHEMY_DATABASE_URL format in $env_file."
            return 1
        fi
    fi
    add_directories "/opt/marzban"
    add_directories "/var/lib/marzban"
    success "Database type: $db_type"
    success "Database user: $db_user"
    success "Database password: $db_password"
    success "Database host: $db_host"
    success "Database port: $db_port"
    success "Database name: $db_name"

    local DB_PATH="/root/_${REMARK}${DATABASE_SUFFIX}"
    # Generate backup command for MySQL/MariaDB
    if [[ "$db_type" != "sqlite3" ]]; then
        BACKUP_DB_COMMAND="mysqldump -h $db_host -P $db_port -u $db_user -p'$db_password' '$db_name' > $DB_PATH"
        DIRECTORIES+=($DB_PATH)
    fi

    # Export backup variables
    BACKUP_DIRECTORIES="${DIRECTORIES[*]}"
    log "Complete Marzban"
    confirm
}


marzhelp_template() {
    log "Checking environment file..."
    local env_file="/opt/marzban/.env"

    [[ -f "$env_file" ]] || { error "Environment file not found: $env_file"; exit 1; }

    # Check for MYSQL_ROOT_PASSWORD in .env
    local MYSQL_ROOT_PASSWORD=$(grep -v '^#' "$env_file" | grep 'MYSQL_ROOT_PASSWORD' | awk -F '=' '{print $2}' | tr -d ' ' | tr -d '"' | tr -d "'")
    if [[ -z "$MYSQL_ROOT_PASSWORD" ]]; then
        error "MYSQL_ROOT_PASSWORD not found in $env_file. Please add it to the Marzban env file."
        exit 1
    fi

    local db_type db_name db_user db_password db_host db_port
    local BACKUP_DIRECTORIES=("/var/lib/marzban")  # Add default volume

    # Extract SQLALCHEMY_DATABASE_URL from .env file
    local SQLALCHEMY_DATABASE_URL=$(grep -v '^#' "$env_file" | grep 'SQLALCHEMY_DATABASE_URL' | awk -F '=' '{print $2}' | tr -d ' ' | tr -d '"' | tr -d "'")

    if [[ -z "$SQLALCHEMY_DATABASE_URL" || "$SQLALCHEMY_DATABASE_URL" == *"sqlite3"* ]]; then
        error "SQLite database detected. This script only supports MySQL/MariaDB databases."
        exit 1
    fi

    # Parse SQLALCHEMY_DATABASE_URL to extract database details
    if [[ "$SQLALCHEMY_DATABASE_URL" =~ ^(mysql\+pymysql|mariadb\+pymysql)://([^:]+):([^@]+)@([^:]+):([0-9]+)/(.+)$ ]]; then
        db_type="${BASH_REMATCH[1]%%+*}"  # Extract mysql or mariadb
        db_user="${BASH_REMATCH[2]}"
        db_password="${BASH_REMATCH[3]}"
        db_host="${BASH_REMATCH[4]}"
        db_port="${BASH_REMATCH[5]}"
        db_name="${BASH_REMATCH[6]}"
    elif [[ "$SQLALCHEMY_DATABASE_URL" =~ ^(mysql\+pymysql|mariadb\+pymysql)://([^:]+):([^@]+)@([0-9.]+)/(.+)$ ]]; then
        db_type="${BASH_REMATCH[1]%%+*}"  # Extract mysql or mariadb
        db_user="${BASH_REMATCH[2]}"
        db_password="${BASH_REMATCH[3]}"
        db_host="${BASH_REMATCH[4]}"
        db_port="3306"  # Default MySQL/MariaDB port
        db_name="${BASH_REMATCH[5]}"
    else
        error "Invalid SQLALCHEMY_DATABASE_URL format in $env_file."
        exit 1
    fi

    # Check if marzhelp database exists
    log "Checking if marzhelp database exists..."
    if ! mysqlshow -h "$db_host" -P "$db_port" -u root -p"$MYSQL_ROOT_PASSWORD" marzhelp &>/dev/null; then
        error "marzhelp database not found or not accessible. Please ensure it exists and you have proper permissions."
        exit 1
    fi
    
    local MARZHELP_DB_PATH="/root/__${REMARK}${DATABASE_SUFFIX}"
    local MARZHELP_BACKUP_COMMAND="mysqldump -h $db_host -P $db_port -u root -p'$MYSQL_ROOT_PASSWORD' 'marzhelp' > $MARZHELP_DB_PATH"
    BACKUP_COMMANDS+=("$MARZHELP_BACKUP_COMMAND")
    DIRECTORIES+=("$MARZHELP_DB_PATH")

    add_directories "/opt/marzban"
    DIRECTORIES+=("/root/marzhelp.txt")
    add_directories "/var/lib/marzban"
    success "Database type: $db_type"
    success "Database user: $db_user"
    success "Database password: $db_password"
    success "Database host: $db_host"
    success "Database port: $db_port"
    success "Database name: $db_name"
    success "MarzHelp database exists and is accessible"

    local DB_PATH="/root/_${REMARK}${DATABASE_SUFFIX}"
    # Generate backup command for MySQL/MariaDB
    BACKUP_DB_COMMAND="mysqldump -h $db_host -P $db_port -u $db_user -p'$db_password' '$db_name' > $DB_PATH"
    DIRECTORIES+=($DB_PATH)

    # Export backup variables
    BACKUP_DIRECTORIES="${DIRECTORIES[*]}"
    BACKUP_DB_COMMAND="$BACKUP_DB_COMMAND && $MARZHELP_BACKUP_COMMAND"  # Combine both commands
    log "Complete Marzban + MarzHelp"
    confirm
}

mirzabot_template() {
    log "Checking MirzaBot file..."
    local mirzabot_file='/var/www/html/mirzabotconfig/config.php'
    
    [[ -f "$mirzabot_file" ]] || { error "MirzaBot file not found: $mirzabot_file"; return 1; }

    # Extract database values from config.php
    db_name=$(grep -m 1 "\$dbname" $mirzabot_file | sed -E "s/.*dbname\s*=\s*'([^']+)'.*/\1/")
    db_user=$(grep -m 1 "\$usernamedb" $mirzabot_file | sed -E "s/.*usernamedb\s*=\s*'([^']+)'.*/\1/")
    db_password=$(grep -m 1 "\$passworddb" $mirzabot_file | sed -E "s/.*passworddb\s*=\s*'([^']+)'.*/\1/")

    # Check if the values are extracted correctly
    if [ -z "$db_name" ] || [ -z "$db_password" ] || [ -z "$db_user" ]; then
        error "Failed to extract database values from $mirzabot_file."
        exit 1
    fi

    # Generate backup command for MySQL/MariaDB
    local DB_PATH="/root/_${REMARK}${DATABASE_SUFFIX}"
    BACKUP_DB_COMMAND="mysqldump -u $db_user -p'$db_password' '$db_name' > $DB_PATH"
    DIRECTORIES+=($DB_PATH)

    # Export backup variables
    BACKUP_DIRECTORIES="${DIRECTORIES[*]}"
    log "Complete MirzaBot"
    confirm
}

hiddify_template() {
    log "Checking Hiddify configuration..."
    
    # Set default value for HIDDIFY_DB_FOLDER if not set
    local HIDDIFY_DB_FOLDER="/opt/hiddify-manager/hiddify-panel/backup.sh"
    local BACKUP_FOLDER="/opt/hiddify-manager/hiddify-panel/backup"

    # Check if the backup script exists
    if [ ! -f "$HIDDIFY_DB_FOLDER" ]; then
        error "Backup script not found: $HIDDIFY_DB_FOLDER"
        return 1
    fi

    # Create backup directory if it doesn't exist
    if [ ! -d "$BACKUP_FOLDER" ]; then
        log "Creating backup directory: $BACKUP_FOLDER"
        mkdir -p "$BACKUP_FOLDER"
        if [ $? -ne 0 ]; then
            error "Failed to create backup directory: $BACKUP_FOLDER"
            return 1
        fi
    fi

    # Set full access permissions to the backup directory and script
    log "Setting permissions for backup directory and script..."
    chmod -R 755 "$BACKUP_FOLDER"
    chmod 755 "$HIDDIFY_DB_FOLDER"

    # Add the directory to BACKUP_DIRECTORIES
    add_directories "$BACKUP_FOLDER"

    # Set the backup command
    BACKUP_DB_COMMAND="bash $HIDDIFY_DB_FOLDER"

    # Export backup variables
    BACKUP_DIRECTORIES="${DIRECTORIES[*]}"
    log "Hiddify configuration completed successfully."
    confirm
}

generate_password() {
    clear
    print "[PASSWORD PROTECTION]\n"
    print "You can set a password for the archive. The password must contain both letters and numbers, and be at least 8 characters long.\n"
    print "If you don't want a password, just press Enter.\n"

    COMPRESS="zip -9 -r"
    while true; do
        input "Enter the password for the archive (or press Enter to skip): " PASSWORD
        
        # If password is empty, skip password protection
        if [ -z "$PASSWORD" ]; then
            success "No password will be set for the archive."
            COMPRESS="zip -9 -r -s ${LIMITSIZE}m"
            break
        fi

        # Validate password
        if [[ ! "$PASSWORD" =~ ^[a-zA-Z0-9]{8,}$ ]]; then
            wrong "Password must be at least 8 characters long and contain only letters and numbers. Please try again."
            continue
        fi

        input "Confirm the password: " CONFIRM_PASSWORD
        
        if [ "$PASSWORD" == "$CONFIRM_PASSWORD" ]; then
            success "Password confirmed."
            COMPRESS="$COMPRESS -e -P $PASSWORD -s ${LIMITSIZE}m"
            break
        else
            wrong "Passwords do not match. Please try again."
        fi
    done
}

generate_platform() {
    clear
    print "[PLATFORM]\n"
    print "Select one platform to send your backup.\n"
    print "1) Telegram"
    print "2) Discord"
    print "3) Gmail"
    print ""

    while true; do
        input "Enter your choice : " choice

        case $choice in
            1)
                PLATFORM="telegram"
                telegram_progress
                break
                ;;
            2)
                PLATFORM="discord"
                discord_progress
                break
                ;;
            3)
                PLATFORM="gmail"
                gmail_progress
                break
                ;;
            *)
                wrong "Invalid option, Please select with number."
                ;;
        esac
    done
    sleep 1
}

telegram_progress() {
    clear
    print "[TELEGRAM]\n"
    print "To use Telegram, you need to provide a bot token and a chat ID.\n"

    while true; do
        # Get bot token
        while true; do
            input "Enter the bot token: " BOT_TOKEN
            if [[ -z "$BOT_TOKEN" ]]; then
                wrong "Bot token cannot be empty!"
            elif [[ ! "$BOT_TOKEN" =~ ^[0-9]+:[a-zA-Z0-9_-]{35}$ ]]; then
                wrong "Invalid bot token format!"
            else
                break
            fi
        done

        # Get chat ID
        while true; do
            input "Enter the chat ID: " CHAT_ID
            if [[ -z "$CHAT_ID" ]]; then
                wrong "Chat ID cannot be empty!"
            elif [[ ! "$CHAT_ID" =~ ^-?[0-9]+$ ]]; then
                wrong "Invalid chat ID format!"
            else
                break
            fi
        done

        # Validate bot token and chat ID
        log "Checking Telegram bot..."
        response=$(curl -s -o /dev/null -w "%{http_code}" -X POST "https://api.telegram.org/bot$BOT_TOKEN/sendMessage" -d chat_id="$CHAT_ID" -d text="Hi, Backuper Test Message!")
        if [[ "$response" -ne 200 ]]; then
            wrong "Invalid bot token or chat ID, or Telegram API error! [tip: start bot]"
        else
            success "Bot token and chat ID are valid."
            break
        fi
    done

    # Set the platform command for sending files
    PLATFORM_COMMAND="curl -s -F \"chat_id=$CHAT_ID\" -F \"document=@\$FILE\" -F \"caption=\$CAPTION\" -F \"parse_mode=HTML\" \"https://api.telegram.org/bot$BOT_TOKEN/sendDocument\""
    CAPTION="
📦 <b>From </b><code>\${ip}</code> [By <b><a href='https://t.me/erfjabs'>@ErfJabs</a></b>]
<b>➖➖➖➖Sponsor➖➖➖➖</b>
<a href='${SPONSORLINK}'>${SPONSORTEXT}</a>"
    success "Telegram configuration completed successfully."
    LIMITSIZE=49
    sleep 1
}

discord_progress() {
    clear
    print "[DISCORD]\n"
    print "To use Discord, you need to provide a Webhook URL.\n"

    while true; do
        # Get Discord Webhook URL
        while true; do
            input "Enter the Discord Webhook URL: " DISCORD_WEBHOOK
            if [[ -z "$DISCORD_WEBHOOK" ]]; then
                wrong "Webhook URL cannot be empty!"
            elif [[ ! "$DISCORD_WEBHOOK" =~ ^https://discord\.com/api/webhooks/ ]]; then
                wrong "Invalid Discord Webhook URL format!"
            else
                break
            fi
        done
        # Validate Webhook
        log "Checking Discord Webhook..."
        response=$(curl -s -o /dev/null -w "%{http_code}" -X POST "$DISCORD_WEBHOOK" -H "Content-Type: application/json" -d '{"content": "Hi, Backuper Test Message!"}')
        
        if [[ "$response" -ne 204 ]]; then
            wrong "Invalid Webhook URL or Discord API error!"
        else
            success "Webhook URL is valid."
            break
        fi
    done

    # Set the platform command for sending files
    PLATFORM_COMMAND="curl -s -F \"file=@\$FILE\" -F \"payload_json={\\\"content\\\": \\\"\$CAPTION\\\"}\" \"$DISCORD_WEBHOOK\""
    CAPTION="📦 **From** \`${ip}\` [by **[@ErfJabs](https://t.me/erfjabs)**]\n➖➖➖➖**Sponsor**➖➖➖➖\n[${SPONSORTEXT}](${SPONSORLINK})"
    LIMITSIZE=24
    success "Discord configuration completed successfully."
    sleep 1
}


gmail_progress() {
    clear
    print "[GMAIL]\n"
    print "To use Gmail, you need to provide your email and an app password.\n"
    print "🔴 Do NOT use your real password! Generate an 'App Password' from Google settings.\n"

    while true; do
        while true; do
            input "Enter your Gmail address: " GMAIL_ADDRESS
            if [[ -z "$GMAIL_ADDRESS" ]]; then
                wrong "Email cannot be empty!"
            elif [[ ! "$GMAIL_ADDRESS" =~ ^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$ ]]; then
                wrong "Invalid email format!"
            else
                break
            fi
        done

        while true; do
            input "Enter your Gmail app password: " GMAIL_PASSWORD
            if [[ -z "$GMAIL_PASSWORD" ]]; then
                wrong "Password cannot be empty!"
            else
                break
            fi
        done

        log "Testing Gmail SMTP authentication..."

        echo -e "Subject: Test Email\n\nThis is a test message." | msmtp \
            --host=smtp.gmail.com \
            --port=587 \
            --tls=on \
            --auth=on \
            --user="$GMAIL_ADDRESS" \
            --passwordeval="echo '$GMAIL_PASSWORD'" \
            -f "$GMAIL_ADDRESS" \
            "$GMAIL_ADDRESS"

        if [[ $? -eq 0 ]]; then
            success "Authentication successful! Configuring msmtp and mutt..."

            cat > ~/.msmtprc <<EOF
account gmail
host smtp.gmail.com
port 587
auth on
tls on
tls_starttls on
user $GMAIL_ADDRESS
password $GMAIL_PASSWORD
from $GMAIL_ADDRESS
logfile ~/.msmtp.log
account default : gmail
EOF

            chmod 600 ~/.msmtprc  

            cat > ~/.muttrc <<EOF
set sendmail="/usr/bin/msmtp"
set use_from=yes
set realname="Backup System"
set from="$GMAIL_ADDRESS"
set envelope_from=yes
EOF

            chmod 600 ~/.muttrc
            CAPTION="<html><body><p><b>📦 From </b><code>\${ip}</code> [by <b><a href='https://t.me/erfjabs'>@ErfJabs</a></b>]</p><p><b>➖➖➖➖Sponsor➖➖➖➖</b></p><p><a href='${SPONSORLINK}'>${SPONSORTEXT}</a></p></body></html>"
            PLATFORM_COMMAND="echo \$CAPTION | mutt -e 'set content_type=text/html' -s 'Backuper' -a \"\$FILE\" -- \"$GMAIL_ADDRESS\""
            LIMITSIZE=24
            break
        else
            wrong "Authentication failed! Check your email or app password and try again."
            sleep 3
            clear
        fi
    done

    sleep 1
}


generate_script() {
    clear
    local BACKUP_PATH="/root/_${REMARK}${SCRIPT_SUFFIX}"
    log "Generating backup script: $BACKUP_PATH"
    DB_CLEANUP=""
    if [[ -n "$DB_PATH" ]]; then
        DB_CLEANUP="rm -rf "$DB_PATH" 2>/dev/null || true"
    fi
    
    # Create the backup script
    cat <<EOL > "$BACKUP_PATH"
#!/bin/bash
set -e 

# Variables
ip=\$(hostname -I | awk '{print \$1}')
timestamp=\$(TZ='Asia/Tehran' date +%m%d-%H%M)
CAPTION="${CAPTION}"
backup_name="/root/\${timestamp}_${REMARK}${BACKUP_SUFFIX}"
base_name="/root/\${timestamp}_${REMARK}${TAG}"

# Clean up old backup files (only specific backup files)
rm -rf *"${REMARK}${TAG}"* 2>/dev/null || true
$DB_CLEANUP

# Backup database
$BACKUP_DB_COMMAND

# Compress files
if ! $COMPRESS "\$backup_name" ${BACKUP_DIRECTORIES[@]}; then
    message="Failed to compress ${REMARK} files. Please check the server."
    echo "\$message"
    exit 1
fi

# Send backup files
if ls \${base_name}* > /dev/null 2>&1; then
    for FILE in \${base_name}*; do
        echo "Sending file: \$FILE"
        if $PLATFORM_COMMAND; then
            echo "Backup part sent successfully: \$FILE"
        else
            message="Failed to send ${REMARK} backup part: \$FILE. Please check the server."
            echo "\$message"
            exit 1
        fi
    done
    echo "All backup parts sent successfully"
else
    message="Backup file not found: \$backup_name. Please check the server."
    echo "\$message"
    exit 1
fi

rm -rf *"${REMARK}${TAG}"* 2>/dev/null || true
EOL

    # Make the script executable
    chmod +x "$BACKUP_PATH"
    success "Backup script created: $BACKUP_PATH"
    
    # Run the backup script with realtime output
    log "Running the backup script..."
    if bash "$BACKUP_PATH" 2>&1 | tee /tmp/backup.log; then
        success "Backup script run successfully."
        
        # Set up cron job
        log "Setting up cron job..."
        if (crontab -l 2>/dev/null; echo "$TIMER $BACKUP_PATH") | crontab -; then
            success "Cron job set up successfully. Backups will run every $minutes minutes."
        else
            error "Failed to set up cron job. Set it up manually: $TIMER $BACKUP_PATH"
            exit 1
        fi
        
        # Final success message
        success "🎉 Your backup system is set up and running!"
        success "Backup script location: $BACKUP_PATH"
        success "Cron job: Every $minutes minutes"
        success "First backup created and sent."
        success "Thank you for using @ErfJabs backup script. Enjoy automated backups!"
        exit 0
    else
        error "Failed to run backup script. Full output:"
        cat /tmp/backup.log
        message="Backup script failed to run. Please check the server."
        eval "$PLATFORM_COMMAND"
        rm -f /tmp/backup.log
        exit 1
    fi
}

main() {
    clear
    check_root
    menu
}

main
