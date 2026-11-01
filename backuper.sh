#!/bin/bash

# Global constants
readonly SCRIPT_SUFFIX="_backuper_script.sh"
readonly TAG="_backuper."
readonly BACKUP_SUFFIX="${TAG}7z"
readonly DATABASE_SUFFIX="${TAG}sql"
readonly LOGS_SUFFIX="${TAG}log"
readonly VERSION="v0.7.0"
readonly OWNER=""
readonly SPONSORTEXT=""
readonly SPONSORLINK=""


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

install_packages() {
    local package_manager=$(detect_package_manager)
    local packages=("$@")

    log "Installing required packages: ${packages[*]}..."
    
    case $package_manager in
        apt)
            apt-get update -y || error "Failed to update package list"
            apt-get install -y "${packages[@]}" || error "Failed to install packages: ${packages[*]}"
            ;;
        dnf|yum)
            $package_manager install -y "${packages[@]}" || error "Failed to install packages: ${packages[*]}"
            ;;
        pacman)
            pacman -Sy --noconfirm "${packages[@]}" || error "Failed to install packages: ${packages[*]}"
            ;;
    esac
    success "Packages installed successfully"
}

install_core_dependencies() {
    local package_manager=$(detect_package_manager)
    case $package_manager in
        apt)
            install_packages "wget" "cron" "p7zip-full"
            ;;
        dnf|yum|pacman)
            install_packages "wget" "cron" "p7zip"
            ;;
    esac
}

menu() {
    while true; do
        clear
        print "======== Backuper Menu [$VERSION] ========"
        print ""
        print "1) Install Backuper"
        print "2) Remove All Backupers"
        print "3) Run All Backup Scripts"
        print "4) Exit"
        print "5) Update an existing backup and its schedules"
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
            5)
                update_existing
                ;;
            *)
                wrong "Invalid option, Please select a valid option!"
                ;;
        esac
    done
}

cleanup_backups() {
    clear
    print "[REMOVE BACKUPERS & CRON JOBS]\n"
    print "1) Delete a specific backup script & its cron job"
    print "2) Delete ALL backup scripts & cron jobs"
    print "3) Full Uninstall (Delete all scripts, cron jobs & this installer)"
    print "0) Back to main menu"
    print ""
    input "Choose an option:" remove_choice

    case $remove_choice in
        1)
            local scripts=(/root/*"${SCRIPT_SUFFIX}")
            if [ ! -e "${scripts[0]}" ]; then
                warn "No backup scripts found."
                confirm
                return
            fi

            print "\nAvailable backup scripts:"
            local i=1
            for script in "${scripts[@]}"; do
                print "$i) $(basename "$script")"
                ((i++))
            done
            print ""

            input "Enter script number to remove:" script_num
            if [[ "$script_num" =~ ^[0-9]+$ ]] && [ "$script_num" -ge 1 ] && [ "$script_num" -le "${#scripts[@]}" ]; then
                local selected_script="${scripts[$((script_num-1))]}"
                local remark_name=$(basename "$selected_script" "$SCRIPT_SUFFIX" | sed 's/^_//')

                rm -f "$selected_script"
                rm -rf /root/*"${remark_name}${TAG}"* 2>/dev/null || true
                (crontab -l 2>/dev/null | grep -v "$selected_script" || true) | crontab -

                success "Removed backup script: $selected_script and its cron job."
            else
                wrong "Invalid selection."
            fi
            confirm
            ;;
        2)
            print "Removing all backups and cron jobs..."
            rm -rf /root/*"$SCRIPT_SUFFIX" /root/*"$TAG"* /root/*_backuper.sh /root/ac-backup*.sh /root/*backuper*.sh
            (crontab -l 2>/dev/null | grep -v "$SCRIPT_SUFFIX" || true) | crontab -
            success "All backups and cron jobs have been removed."
            confirm
            ;;
        3)
            print "Performing full cleanup..."
            rm -rf /root/*"$SCRIPT_SUFFIX" /root/*"$TAG"* /root/*_backuper.sh /root/ac-backup*.sh /root/*backuper*.sh
            (crontab -l 2>/dev/null | grep -v "$SCRIPT_SUFFIX" || true) | crontab -
            success "All backups and cron jobs removed."
            log "Removing this installer script..."
            rm -f "$0"
            exit 0
            ;;
        0)
            return
            ;;
        *)
            wrong "Invalid option!"
            confirm
            ;;
    esac
}

start_backup() {
    install_core_dependencies
    generate_remark
    generate_schedules
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
        elif [ -e "/root/_${REMARK}${SCRIPT_SUFFIX}" ]; then
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

# Cron uses the server's local timezone.
schedule_prompt() {
    local label="$1" result="$2" frequency time hour minute day
    print "[$label SCHEDULE]" >&2
    while true; do
        input "1) Daily  2) Weekly: " frequency
        [[ "$frequency" == 1 || "$frequency" == 2 ]] && break
        wrong "Choose 1 or 2."
    done
    while true; do
        input "Time (HH:MM, server local time): " time
        if [[ "$time" =~ ^([0-9]{2}):([0-9]{2})$ ]]; then
            hour=$((10#${BASH_REMATCH[1]})); minute=$((10#${BASH_REMATCH[2]}))
            (( hour < 24 && minute < 60 )) && break
        fi
        wrong "Enter a valid time, for example 03:30."
    done
    day='*'
    if [[ "$frequency" == 2 ]]; then
        while true; do
            input "Day of week (1=Monday ... 7=Sunday): " day
            [[ "$day" =~ ^[1-7]$ ]] && break
            wrong "Choose a day from 1 to 7."
        done
        [[ "$day" == 7 ]] && day=0
    fi
    printf -v "$result" '%s %s * * %s' "$minute" "$hour" "$day"
}

generate_schedules() {
    schedule_prompt "BACKUP" BACKUP_TIMER
    schedule_prompt "SEND" SEND_TIMER
}

# Replace only jobs invoking this exact script, including legacy jobs.
install_schedules() {
    local script="$1" current filtered
    current=$(crontab -l 2>/dev/null) || current=''
    filtered=$(printf '%s\n' "$current" | awk -v path="$script" '
        index($0, path) {
            rest = substr($0, index($0, path) + length(path), 1)
            if (rest == "" || rest ~ /[[:space:]]/) next
        }
        NF { print }
    ')
    { [[ -z "$filtered" ]] || printf '%s\n' "$filtered"; printf '%s %s backup\n%s %s send\n' "$BACKUP_TIMER" "$script" "$SEND_TIMER" "$script"; } | crontab -
}

# Convert scripts produced by the previous installer without asking for secrets again.
upgrade_script() {
    local script="$1" remark="$2" tmp command notice_command version
    grep -q '^# Backuper separated schedules v2$' "$script" && return 0
    version=legacy
    if grep -q '^# Backuper separated schedules v1$' "$script"; then
        version=v1
    else
        for marker in '# Variables' '# Backup database' '# Compress files' '# Send backup files'; do
            grep -Fxq "$marker" "$script" || { warn "Unsupported script format: $script (missing $marker). No changes made."; return 1; }
        done
    fi
    command=$(sed -n '/^[[:space:]]*if .*\(document=@\|file=@\|mutt .* -a \)/{ s/^[[:space:]]*if //; s/; then[[:space:]]*$//; p; }' "$script")
    [[ -n "$command" && "$command" != *$'\n'* ]] || { warn "Unsupported delivery command in $script. No changes made."; return 1; }
    case "$command" in
        *'document=@$FILE'*)
            notice_command=${command/'-F "document=@$FILE"'/}
            notice_command=${notice_command/'-F "caption=$CAPTION"'/'-F "text=$notice"'}
            notice_command=${notice_command/'/sendDocument"'/'/sendMessage"'}
            ;;
        *'file=@$FILE'*)
            notice_command=${command/'-F "file=@$FILE"'/}
            notice_command=${notice_command/'$CAPTION'/'$notice'}
            ;;
        *'mutt '*)
            notice_command=${command/'-a "$FILE"'/}
            notice_command=${notice_command/'$CAPTION'/'$notice'}
            ;;
        *) warn "Unsupported delivery command in $script. No changes made."; return 1 ;;
    esac
    [[ "$notice_command" != "$command" ]] || { warn "Could not prepare notification. No changes made."; return 1; }
    command=${command/'curl -s '/'curl -fsS '}
    notice_command=${notice_command/'curl -s '/'curl -fsS '}
    tmp=$(mktemp "${script}.XXXXXX") || return 1
    {
        if [[ "$version" == v1 ]]; then
            sed '/^send)$/,$d; s/^# Backuper separated schedules v1$/# Backuper separated schedules v2/' "$script"
        else
        cat <<'RUNTIME'
#!/bin/bash
# Backuper separated schedules v2
set -e
umask 077
RUNTIME
        # Preserve the caption and all existing platform/database commands verbatim.
        sed -n '/^ip=/p; /^CAPTION=/p' "$script"
        printf 'remark=%q\n' "$remark"
        cat <<'RUNTIME'
store="/root/._backuper_${remark}_archives"
mkdir -p "$store"
exec 9>"$store/.lock"
flock 9
case "${1:-backup}" in
backup)
    work=$(mktemp -d "$store/.pending.XXXXXX")
    trap 'rm -rf -- "$work"' EXIT
    timestamp=$(date +%Y%m%d-%H%M%S)
    backup_name="$work/${timestamp}_${remark}_backuper.7z"
RUNTIME
        sed -n '/^# Backup database$/,/^# Send backup files$/{ /^# Backup database$/d; /^# Send backup files$/d; p; }' "$script"
        cat <<'RUNTIME'
    compgen -G "$backup_name*" >/dev/null || { echo "Archive was not created" >&2; exit 1; }
    destination="$store/$timestamp"
    [[ ! -e "$destination" ]] || destination="$destination-$$"
    mv -- "$work" "$destination"
    trap - EXIT
    echo "Backup saved: $destination"
    ;;
RUNTIME
        fi
        cat <<'RUNTIME'
send)
    latest=$(find "$store" -mindepth 1 -maxdepth 1 -type d ! -name '.*' -printf '%f\n' | LC_ALL=C sort | tail -n 1)
    [[ -n "$latest" ]] || { echo "No completed backups found" >&2; exit 1; }
    first=$(find "$store/$latest" -maxdepth 1 -type f -name '*_backuper.7z*' -print | LC_ALL=C sort | head -n 1)
    [[ -n "$first" ]] || { echo "No archive parts found" >&2; exit 1; }
    base_name="${first%%.7z*}."
    shopt -s nullglob
    parts=("${base_name}"7z*)
    (( ${#parts[@]} > 0 )) || { echo "No archive parts found" >&2; exit 1; }
    bytes=0
    for FILE in "${parts[@]}"; do
        size=$(stat -c %s -- "$FILE")
        bytes=$((bytes + size))
    done
    if (( bytes > 10 * 1024 * 1024 )); then
        notice="Backup ${remark} is too large to send (over 10 MiB). It remains on the server."
RUNTIME
        printf '        %s\n' "$notice_command"
        cat <<'RUNTIME'
        echo "Size notification sent."
    else
        for FILE in "${parts[@]}"; do
            echo "Sending file: $FILE"
RUNTIME
        printf '            %s\n' "$command"
        cat <<'RUNTIME'
        done
        echo "All backup parts sent successfully."
    fi
    # Do not remove older backups if delivery or notification failed.
    find "$store" -mindepth 1 -maxdepth 1 -type d ! -name '.*' ! -name "$latest" -exec rm -rf -- {} +
    ;;
*) echo "Usage: $0 {backup|send}" >&2; exit 2 ;;
esac
RUNTIME
    } > "$tmp"
    if ! bash -n "$tmp"; then rm -f "$tmp"; warn "Conversion failed; original script was not changed."; return 1; fi
    chmod 700 "$tmp"
    cp -p -- "$script" "${script}.before-separated-schedules" || { rm -f "$tmp"; return 1; }
    chmod 600 "${script}.before-separated-schedules"
    mv -f -- "$tmp" "$script"
}

update_existing() {
    local scripts=(/root/*"$SCRIPT_SUFFIX") selected remark number
    [[ -e "${scripts[0]}" ]] || { warn "No backup scripts found."; confirm; return; }
    local i=1
    for selected in "${scripts[@]}"; do print "$i) $(basename "$selected")"; ((i++)); done
    input "Select a backup to update: " number
    [[ "$number" =~ ^[0-9]+$ ]] && (( number >= 1 && number <= ${#scripts[@]} )) || { wrong "Invalid selection."; return; }
    selected="${scripts[number-1]}"
    remark=$(basename "$selected" "$SCRIPT_SUFFIX"); remark="${remark#_}"
    generate_schedules
    upgrade_script "$selected" "$remark" || return
    install_schedules "$selected" || { warn "Could not update crontab."; return 1; }
    success "Updated $selected. Backup: $BACKUP_TIMER; send: $SEND_TIMER"
    confirm
}

generate_template() {
    clear
    print "[TEMPLATE]\n"
    print "Choose a backup template. You can add or remove custom DIRECTORIES after selecting.\n"
    print "1) X-ui"
    print "2) Remnawave"
    print "3) Marzban"
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
                remnawave_template
                break
                ;;
            3)
                marzban_template
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

remnawave_template() {
    log "Checking Remnawave configuration..."

    local REMNAWAVE_DR="/opt/remnawave"
    if [ ! -d "$REMNAWAVE_DR" ]; then
        error "Directory not found: $REMNAWAVE_DR"
        return 1
    fi

    env_file="/opt/remnawave/.env"
    if [ ! -f "$env_file" ]; then
        error "Environment file not found: $env_file"
        return 1
    fi

    # Extract SQLALCHEMY_DATABASE_URL from .env file
    local SQLALCHEMY_DATABASE_URL=$(grep -v '^#' "$env_file" | grep 'DATABASE_URL' | awk -F '=' '{print $2}' | tr -d ' ' | tr -d '"' | tr -d "'")

    if [[ "$SQLALCHEMY_DATABASE_URL" =~ ^postgresql://([^:]+):([^@]+)@([^:]+):([0-9]+)/(.+)$ ]]; then
        db_user="${BASH_REMATCH[1]}"
        db_password="${BASH_REMATCH[2]}"
        db_name="${BASH_REMATCH[5]}"
    else
        error "Invalid DATABASE_URL format in $env_file."
        return 1
    fi

    # Install postgresql-client on-demand
    local package_manager=$(detect_package_manager)
    if [[ "$package_manager" == "apt" ]]; then
        install_packages "postgresql-client"
    fi

    add_directories "$REMNAWAVE_DR"
    success "Database user: $db_user"
    success "Database password: $db_password"
    success "Database name: $db_name"

    local DB_PATH="/root/_${REMARK}_${db_name}.sql"

    BACKUP_DB_COMMAND="docker exec -e PGPASSWORD='$db_password' \$(docker ps --filter 'publish=6767' --format '{{.Names}}' | head -n 1) pg_dump -U $db_user '$db_name' > $DB_PATH"
    DIRECTORIES+=($DB_PATH)

    # Export backup variables
    BACKUP_DIRECTORIES="${DIRECTORIES[*]}"
    log "Complete Remnawave"
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

    # Install mysql/mariadb client on-demand if non-sqlite
    if [[ "$db_type" != "sqlite3" ]]; then
        local package_manager=$(detect_package_manager)
        if [[ "$package_manager" == "apt" ]]; then
            if ! apt-get install -y default-mysql-client 2>/dev/null; then
                install_packages "mariadb-client"
            fi
        else
            install_packages "mariadb"
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
        BACKUP_DB_COMMAND="mysqldump --column-statistics=0 -h $db_host -P $db_port -u $db_user -p'$db_password' '$db_name' > $DB_PATH"
        DIRECTORIES+=($DB_PATH)
    fi

    # Export backup variables
    BACKUP_DIRECTORIES="${DIRECTORIES[*]}"
    log "Complete Marzban"
    confirm
}

generate_password() {
    clear
    print "[PASSWORD PROTECTION]\n"
    print "Set a password for the 7z archive. The password must contain both letters and numbers, and be at least 8 characters long.\n"

    while true; do
        input "Enter the password for the archive: " PASSWORD

        if [ -z "$PASSWORD" ]; then
            wrong "Password cannot be empty! Please enter a password."
            continue
        fi

        # Validate password
        if [[ ! "$PASSWORD" =~ ^[a-zA-Z0-9]{8,}$ ]]; then
            wrong "Password must be at least 8 characters long and contain only letters and numbers. Please try again."
            continue
        fi

        input "Confirm the password: " CONFIRM_PASSWORD
        
        if [ "$PASSWORD" == "$CONFIRM_PASSWORD" ]; then
            success "Password confirmed."
            COMPRESS="7z a -t7z -mx=9 -p'$PASSWORD' -v${LIMITSIZE}m"
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
    install_packages "curl"
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

        while true; do
            input "Enter the topic ID (Press Enter to skip): " TOPIC_ID
            if [[ -z "$TOPIC_ID" ]]; then
                success "No topic ID provided. Messages will be sent to the main chat."
                TOPIC_ID=""
                break
            elif [[ ! "$TOPIC_ID" =~ ^[0-9]+$ ]]; then
                wrong "Invalid topic ID format! Must be a number."
            else
                success "Topic ID set: $TOPIC_ID"
                break
            fi
        done

        # Validate bot token and chat ID
        log "Checking Telegram bot..."
        if [[ -n "$TOPIC_ID" ]]; then
            response=$(curl -s -o /dev/null -w "%{http_code}" -X POST "https://api.telegram.org/bot$BOT_TOKEN/sendMessage" -d chat_id="$CHAT_ID" -d message_thread_id="$TOPIC_ID" -d text="Hi, Backuper Test Message!")
        else
            response=$(curl -s -o /dev/null -w "%{http_code}" -X POST "https://api.telegram.org/bot$BOT_TOKEN/sendMessage" -d chat_id="$CHAT_ID" -d text="Hi, Backuper Test Message!")
        fi
        
        if [[ "$response" -ne 200 ]]; then
            wrong "Invalid bot token, chat ID, topic ID, or Telegram API error! [tip: start bot]"
        else
            success "Bot token and chat ID are valid."
            break
        fi
    done

    # Set the platform command for sending files
    if [[ -n "$TOPIC_ID" ]]; then
        PLATFORM_COMMAND="curl -s -F \"chat_id=$CHAT_ID\" -F \"message_thread_id=$TOPIC_ID\" -F \"document=@\$FILE\" -F \"caption=\$CAPTION\" -F \"parse_mode=HTML\" \"https://api.telegram.org/bot$BOT_TOKEN/sendDocument\""
    else
        PLATFORM_COMMAND="curl -s -F \"chat_id=$CHAT_ID\" -F \"document=@\$FILE\" -F \"caption=\$CAPTION\" -F \"parse_mode=HTML\" \"https://api.telegram.org/bot$BOT_TOKEN/sendDocument\""
    fi
    
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
    install_packages "curl"
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
    install_packages "msmtp" "mutt"
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
            CAPTION=""
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
    umask 077
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
timestamp=\$(TZ='Europe/Moscow' date +%m%d-%H%M)
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

    chmod 700 "$BACKUP_PATH"
    upgrade_script "$BACKUP_PATH" "$REMARK" || return 1
    install_schedules "$BACKUP_PATH" || error "Failed to install cron jobs"
    success "Backup schedule: $BACKUP_TIMER; send schedule: $SEND_TIMER"
    log "Creating the first backup..."
    if bash "$BACKUP_PATH" backup; then
        success "First backup created. It will be sent on the send schedule."
    else
        warn "First backup failed. Check the output above; cron jobs remain installed."
    fi
    confirm
}

main() {
    clear
    check_root
    menu
}

main
