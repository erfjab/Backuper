#!/bin/bash

# Global constants
readonly SCRIPT_SUFFIX="_backuper.sh"
readonly BACKUP_SUFFIX="_backuper.zip"
readonly DATABASE_SUFFIX="_backuper.sql"
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
        
        print "======== Backuper Menu [$VERSION] ========"
        print "1️) Install Backuper"
        print "2) Exit"
        print ""
        input "Choose an option:" choice
        case $choice in
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
    generate_template
    generate_platform
    generate_script
}

generate_remark() {
    print "[REMARK]\n"
    print "We need a remark for the backup file (e.g., Master, panel, ErfJab).\n"

    while true; do
        input "Enter a remark: " REMARK

        if ! [[ "$REMARK" =~ ^[a-zA-Z0-9_]+$ ]]; then
            error "Remark must contain only letters, numbers, or underscores."
        elif [ ${#REMARK} -lt 3 ]; then
            error "Remark must be at least 3 characters long."
        elif [ -e "${REMARK}${SCRIPT_SUFFIX}" ]; then
            error "File ${REMARK}${SCRIPT_SUFFIX} already exists. Choose a different remark."
        else
            success "Backup remark: $REMARK"
            break
        fi
    done
    sleep 1
}

generate_caption() {
    
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
    
    print "[TEMPLATE]\n"
    print "Choose a backup template. You can add or remove custom DIRECTORIES after selecting.\n"
    print "1) Marzneshin"
    print "0) Custom"
    print ""
    while true; do
        input "Enter your template number: " TEMPLATE
        case $TEMPLATE in
            1)
                marzneshin_progress
                break
                ;;
            0)
                success "You Chose Custom"
                break
                ;;
            *)
                error "Invalid option. Please choose a valid number!"
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

marzneshin_progress() {
    log "Checking Marzneshin configuration..."
    local docker_compose_file="/etc/opt/marzneshin/docker-compose.yml"

    # Check if docker-compose file exists
    [[ -f "$docker_compose_file" ]] || { error "Docker compose file not found: $docker_compose_file"; return 1; }

    # Extract database configuration
    local db_type db_name db_password db_port
    db_type=$(yq eval '.services.db.image' "$docker_compose_file")
    db_name=$(yq eval '.services.db.environment.MARIADB_DATABASE // .services.db.environment.MYSQL_DATABASE' "$docker_compose_file")
    db_password=$(yq eval '.services.db.environment.MARIADB_ROOT_PASSWORD // .services.db.environment.MYSQL_ROOT_PASSWORD' "$docker_compose_file")
    db_port=$(yq eval '.services.db.ports[0]' "$docker_compose_file" | cut -d':' -f2)

    # Determine database type
    if [[ "$db_type" == *"mariadb"* ]]; then
        db_type="mariadb"
    elif [[ "$db_type" == *"mysql"* ]]; then
        db_type="mysql"
    else
        db_type="sqlite"
    fi

    # Validate database password for non-sqlite databases
    if [[ "$db_type" != "sqlite" && -z "$db_password" ]]; then
        error "Database password not found"
        return 1
    fi

    # Setup backup configuration
    local db_backup_path="/root/${REMARK}${DATABASE_SUFFIX}"
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
    local backup_command=""
    if [[ "$db_type" != "sqlite" ]]; then
        backup_command="mysqldump -h 127.0.0.1 -P $db_port -u root -p'$db_password' --column-statistics=0 '$db_name' > $db_backup_path"
    fi

    # Log success messages
    success "Backup command generated: $backup_command"
    success "Backup DIRECTORIES saved"

    # Export backup variables
    BACKUP_DIRECTORIES="${DIRECTORIES[*]}"
    BACKUP_DB_COMMAND="$backup_command"
}

generate_platform() {
    print "[PLATFORM]\n"
    print "Select one platform to send your backup.\n"
    print "1) Telegram"

    while true; do
        input "Enter your choice : " choice

        case $choice in
            1)
                telegram_progress
                break
                ;;
            *)
                error "Invalid option, Please select with number."
                ;;
        esac
    done
    sleep 1
}

telegram_progress() {
    print "[TELEGRAM]\n"
    print "To use Telegram, you need to provide a bot token and a chat ID.\n"

    while true; do
        input "Enter the bot token: " bot_token
        if [[ -z "$bot_token" ]]; then
            error "Bot token cannot be empty!"
        elif [[ ! "$bot_token" =~ ^[0-9]+:[a-zA-Z0-9_-]{35}$ ]]; then
            error "Invalid bot token format!"
        else
            break
        fi
    done

    while true; do
        input "Enter the chat ID: " chat_id
        if [[ -z "$chat_id" ]]; then
            error "Chat ID cannot be empty!"
        elif [[ ! "$chat_id" =~ ^-?[0-9]+$ ]]; then
            error "Invalid chat ID format!"
        else
            log "Checking Telegram bot..."
            response=$(curl -s -o /dev/null -w "%{http_code}" -X POST "https://api.telegram.org/bot$bot_token/sendMessage" -d chat_id="$chat_id" -d text="Hi, Backuper Test Message!")
            if [[ "$response" -ne 200 ]]; then
                error "Invalid bot token or chat ID, or Telegram API error!"
            else
                success "Bot token and chat ID are valid."
                sleep 1
                break
            fi
        fi
    done
    PLATFORM_COMMAND="curl -s -F \"chat_id=$chat_id\" -F \"document=@\$file_to_send\" -F \"caption=\$caption\" -F \"parse_mode=HTML\" \"https://api.telegram.org/bot$bot_token/sendDocument\""
    sleep 1
}

generate_script() {
    local BACKUP_PATH="/root/${REMARK}${SCRIPT_SUFFIX}"
    log "Generating backup script: $BACKUP_PATH..."

    cat <<EOL > "$BACKUP_PATH"
#!/bin/bash

set -e 

ip=\$(hostname -I | awk '{print \$1}')
timestamp=\$(TZ='Asia/Tehran' date +%m%d-%H%M)
backup_name="/root/${REMARK}_\${timestamp}${BACKUP_SUFFIX}"
caption="${CAPTION}"

rm -f "\$backup_name"*
rm -f *"${DATABASE_SUFFIX}"

$(echo -e "$BACKUP_DB_COMMAND")

if ! zip -9 -r "\$backup_name" ${BACKUP_DIRECTORIES[@]}; then
    message="Failed to compress ${REMARK} files. Please check the server."
    echo "\$message"
    exit 1
fi

if ls \${backup_name}* > /dev/null 2>&1; then
    for file_to_send in \${backup_name}*; do
        echo "Sending file: \$file_to_send"
        if $PLATFORM_COMMAND; then
            echo "Backup part sent successfully: \$file_to_send"
        else
            message="Failed to send ${REMARK} backup part: \$file_to_send. Please check the server."
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

rm -f "\$backup_name"*

EOL

    chmod +x "$BACKUP_PATH"
    success "Backup script created: $BACKUP_PATH"

    log "Running the backup script..."
    if output=$(bash "$BACKUP_PATH"); then
        success "Backup script run successfully."
        log "Setting up cron job..."
        if (crontab -l 2>/dev/null; echo "$TIMER $BACKUP_PATH") | crontab -; then
            success "Cron job set up successfully. Backups will run every $minutes minutes."
        else
            error "Failed to set up cron job. Set it up manually: $TIMER $BACKUP_PATH"
            exit 1
        fi

        success "🎉 Your backup system is set up and running!"
        success "Backup script location: $BACKUP_PATH"
        success "Cron job: Every $minutes minutes"
        success "First backup created and sent."
        success "Thank you for using @ErfJabs backup script. Enjoy automated backups!"
        exit 1
    else
        error "Failed to run backup script. Output:"
        error "$output"
        message="Backup script failed to run. Please check the server."
        eval "$PLATFORM_COMMAND"
        exit 1
    fi
}

# Main execution
check_root
menu