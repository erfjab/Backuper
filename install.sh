#!/bin/bash

colors=( "\033[1;31m" "\033[1;35m" "\033[1;92m" "\033[38;5;46m" "\033[1;38;5;208m" "\033[1;36m" "\033[0m" )
red=${colors[0]} pink=${colors[1]} green=${colors[2]} spring=${colors[3]} orange=${colors[4]} cyan=${colors[5]} reset=${colors[6]}
print() { echo -e "${cyan}$1${reset}"; }
error() { echo -e "${red}✗ $1${reset}"; }
success() { echo -e "${spring}✓ $1${reset}"; }
log() { echo -e "${green}! $1${reset}"; }
input() { read -p "$(echo -e "${orange}▶ $1${reset}")" "$2"; }
confirm() { read -p "$(echo -e "\n${pink}Press any key to continue...${reset}")"; }

trap 'echo -e "\n"; error "Script interrupted! Contact: @ErfJabs"; exit 1' SIGINT

check_needs() {
    log "Checking root..."
    [ "$EUID" -eq 0 ] || { error "Run as root."; exit 1; }

    if command -v apt-get &> /dev/null; then
        PKG_MANAGER="apt-get"
        PKG_UPDATE="$PKG_MANAGER update -y"
        PKG_INSTALL="$PKG_MANAGER install -y"
    elif command -v dnf &> /dev/null; then
        PKG_MANAGER="dnf"
        PKG_UPDATE="$PKG_MANAGER check-update"
        PKG_INSTALL="$PKG_MANAGER install -y"
    elif command -v yum &> /dev/null; then
        PKG_MANAGER="yum"
        PKG_UPDATE="$PKG_MANAGER check-update"
        PKG_INSTALL="$PKG_MANAGER install -y"
    else
        error "No supported package manager found. Please install packages manually."
        exit 1
    fi

    log "Checking for system updates..."
    $PKG_UPDATE || true

    for pkg in curl wget zip; do
        if ! command -v $pkg &> /dev/null; then
            log "Installing $pkg..."
            $PKG_INSTALL $pkg || { error "Install $pkg failed."; exit 1; }
        else
            log "$pkg is already installed."
        fi
    done

    ARCH=$(uname -m)
    if [ "$ARCH" == "x86_64" ]; then
        YQ_BINARY="yq_linux_amd64"
    elif [ "$ARCH" == "aarch64" ]; then
        YQ_BINARY="yq_linux_arm64"
    else
        error "Unsupported architecture: $ARCH"
        exit 1
    fi

    log "Checking for yq..."
    if ! command -v yq &> /dev/null; then
        log "Downloading yq for architecture $ARCH..."
        wget "https://github.com/mikefarah/yq/releases/latest/download/$YQ_BINARY" -O /usr/bin/yq || { error "Failed to download yq."; exit 1; }
        chmod +x /usr/bin/yq || { error "Failed to set execute permissions on yq."; exit 1; }
        log "yq installed successfully."
    else
        log "yq is already installed."
    fi

    log "Checking for p7zip..."
    if ! command -v 7z &> /dev/null; then
        log "Installing p7zip..."
        if [ "$PKG_MANAGER" = "apt-get" ]; then
            $PKG_INSTALL p7zip-full || { error "Install p7zip failed."; exit 1; }
        else
            $PKG_INSTALL p7zip || { error "Install p7zip failed."; exit 1; }
        fi
    else
        log "p7zip is already installed."
    fi

    success "Setup complete."
}

menu() {
    while true; do
        print "\n\t Welcome to Backuper!"
        print "\t\t version 0.1.0 by @ErfJab"
        print "—————————————————————————————————————————————————————————————————————————"
        print "1) install"
        print "2) manage"
        print "0) exit"
        print ""
        input "Enter your option number: " option
        clear
        case $option in
            1)
                select_start_backup_type
                ;;
            2)
                stop_all_backups
                ;;
            0)
                print "Thank you for using @ErfJabs script. Goodbye!"
                exit 0
                ;;
            *)
                error "Invalid option, Please select a valid option!"
                ;;
        esac
    done
}

stop_all_backups() {
    local backup_scripts=($(find /root/ -name "*_backuper.sh" -o -name "ac-backup*.sh"))
    
    if [ ${#backup_scripts[@]} -eq 0 ]; then
        success "No active backup scripts found."
        sleep 1
        return
    fi

    print "\nActive backup scripts:\n"
    for i in "${!backup_scripts[@]}"; do
        print "$((i+1))) ${backup_scripts[$i]}"
    done
    print ""
    
    while true; do
        input "Enter the number of the backup to stop (or 'q' to quit): " choice
        if [[ "$choice" == "q" ]]; then
            return
        elif [[ "$choice" =~ ^[0-9]+$ ]] && [ "$choice" -ge 1 ] && [ "$choice" -le "${#backup_scripts[@]}" ]; then
            local script="${backup_scripts[$((choice-1))]}"
            local script_name=$(basename "$script")
            
            if crontab -l | grep -q "$script_name"; then
                crontab -l | grep -v "$script_name" | crontab -
                success "Stopped backup: $script_name"
            else
                print "No cron job found for: $script_name"
            fi
            
            if rm "$script"; then
                success "Removed script file: $script_name"
            else
                error "Failed to remove script file: $script_name"
            fi
        else
            error "Invalid choice. Enter a number between 1 and ${#backup_scripts[@]}."
        fi
    done
    
    success "Selected backup stopped and script removed."
    sleep 1
    clear
}


select_start_backup_type() {
    clear
    print "[TYPE]\n"
    print "\nWe offer two types of backup installers:\n\n"
    print "1) Advanced - For more customization options."
    print "2) Simple - For a quick and easy setup.\n"

    while true; do
        input "Enter your option number: " backup_type
        case $backup_type in
            1)
                start_advenced_backup
                ;;
            2)
                start_simple_backup
                ;;
            *)
                error "Invalid option. Please select 1 for Simple or 2 for Advanced."
                ;;
        esac
    done
    sleep 1
}


start_simple_backup() {
    check_needs
    backup_template
    backup_name
    backup_cronjob
    send_to
    backup_generate
}

start_advenced_backup() {
    check_needs
    backup_template
    backup_custom_dir
    backup_name
    backup_cronjob
    backup_caption
    backup_password
    backup_compression
    send_to
    backup_generate
}

backup_name() {
    clear
    print "[NAME]\n"
    print "We need a name for the backup file (e.g., Master, panel, ErfJab).\n"

    while true; do
        input "Enter a name: " name

        if ! [[ "$name" =~ ^[a-zA-Z0-9_]+$ ]]; then
            error "Name must contain only letters, numbers, or underscores."
        elif [ ${#name} -lt 3 ]; then
            error "Name must be at least 3 characters long."
        elif [ -e "${name}_backuper.sh" ]; then
            error "File ${name}_backuper.sh already exists. Choose a different name."
        else
            success "Backup name: $name"
            break
        fi
    done
    sleep 1
}


backup_caption() {
    clear
    print "[CAPTION]\n"
    print "You can add a caption for your backup file (e.g., 'The main server of the company').\n"

    input "Enter your caption (Press Enter to skip): " caption

    if [ -z "$caption" ]; then
        success "No caption provided. Skipping..."
        caption=""
    else
        success "Caption set: $caption"
    fi

    sleep 1
}

backup_cronjob() {
    clear
    print "[CRONJOB]\n"
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
        cron_time="*/$minutes * * * *"
    elif [ "$minutes" -le 1439 ]; then
        hours=$((minutes / 60))
        remaining_minutes=$((minutes % 60))
        if [ "$remaining_minutes" -eq 0 ]; then
            cron_time="0 */$hours * * *"
        else
            cron_time="*/$remaining_minutes */$hours * * *"
        fi
    else
        cron_time="0 0 * * *" 
    fi
    success "Cron job set to run every $minutes minutes: $cron_time"
    sleep 1
}


backup_template() {
    clear
    print "[TEMPLATE]\n"
    print "Choose a backup template. You can add or remove custom directories after selecting."
    print "1) Marzban"
    print "2) Custom"
    print ""

    while true; do
        input "Enter your template number: " template
        case $template in
            1)
                marzban_template
                break
                ;;
            2)
                success "You chose Custom."
                break
                ;;
            *)
                error "Invalid option. Please choose a valid number!"
                ;;
        esac
    done
}

backup_custom_dir() {
    clear
    print "[CUSTOM DIR]\n"
    print "Add custom directories or files to the backup (e.g., /etc/haproxy or /root/ErfJab/holderbot.db)."
    
    while true; do
        sleep 1
        print "\nCurrent directories:"
        for dir in "${directories[@]}"; do
            [[ -n "$dir" ]] && success "\t- $dir"
        done
        print ""

        input "Enter a path (or 'done' to finish): " path

        if [[ "$path" == "done" ]]; then
            break
        elif [[ ! -e "$path" ]]; then
            error "Path does not exist: $path"
        elif [[ " ${directories[*]} " =~ " ${path} " ]]; then
            directories=("${directories[@]/$path}")
            success "Removed from list: $path"
        else
            directories+=("$path")
            success "Added to list: $path"
        fi
    done
}


backup_compression() {
    clear
    print "[COMPRESSION]\n"
    print "Select a compression method for your backup:"
    print "1) ZIP (.zip)    | Compression: Normal (✗) - Size: Normal  (✗) - CPU: Low  (✓)"
    print "2) 7z  (.7z)     | Compression: High   (✓) - Size: Minimum (✓) - CPU: High (✗)\n"
    while true; do
        input "Enter your choice (1 or 2): " compression
        case $compression in
            1)
                compression_=".zip"
                compression_add="zip -9 -r"
                compression_update="zip -9 -u"
                break
                ;;
            2)
                compression_=".7z"
                compression_add="7z a -spf -mx=9 -t7z -mmt"
                compression_update="7z u -spf -mx=9 -mmt1"
                break
                ;;
            *)
                error "Invalid choice. Please select 1 or 2."
                ;;
        esac
    done
    sleep 1
}


send_to() {
    clear
    print "[PLATFORM]\n"
    print "Select one platform to send your backup."
    print "1) Telegram"
    print "2) Discord\n"

    while true; do
        input "Enter your choice (1 or 2): " send_to_option

        case $send_to_option in
            1)
                send_to_telegram
                break
                ;;
            2)
                send_to_discord
                break
                ;;
            *)
                error "Invalid option. Please select 1 for Telegram or 2 for Discord."
                ;;
        esac
    done
    sleep 1
}

send_to_telegram() {
    clear
    print "[TELEGRAM]\n"
    print "To use Telegram, you need to provide a bot token and a chat ID."

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
            response=$(curl -s -o /dev/null -w "%{http_code}" -X POST "https://api.telegram.org/bot$bot_token/sendMessage" -d chat_id="$chat_id" -d text="Hi Bro! (test bot)")
            if [[ "$response" -ne 200 ]]; then
                error "Invalid bot token or chat ID, or Telegram API error!"
            else
                success "Bot token and chat ID are valid."
                sleep 1
                break
            fi
        fi
    done
    sleep 1
}

send_to_discord() {
    clear
    print "[DISCORD]\n"
    print "To use Discord, you need to provide a webhook URL."
    print "If you don't know how to get this, check: www.google.com/how_to_create_discord_webhook\n"

    while true; do
        input "Enter the webhook URL: " webhook_url
        if [[ -z "$webhook_url" ]]; then
            error "Webhook URL cannot be empty!"
        elif [[ ! "$webhook_url" =~ ^https://discord.com/api/webhooks/[0-9]+/[a-zA-Z0-9_-]+$ ]]; then
            error "Invalid webhook URL format!"
        else
            log "Checking Discord webhook..."
            response=$(curl -s -o /dev/null -w "%{http_code}" -X POST -H "Content-Type: application/json" -d '{"content": "Hi Bro! (test message)"}' "$webhook_url")
            if [[ "$response" -ne 204 ]]; then
                error "Invalid webhook URL or Discord API error!"
            else
                success "Webhook URL is valid."
                sleep 1
                break
            fi
        fi
    done
    sleep 1
}

marzban_template() {
    log "Checking docker-compose file..."
    local docker_compose_file="/opt/marzban/docker-compose.yml"

    if ! grep -q "^services:" "$docker_compose_file"; then
        error "Docker compose file not found or invalid format: $docker_compose_file"
        exit 1
    else
        success "Docker compose file found."
    fi

    log "Reviewing services..."
    services=$(yq eval '.services | keys | .[]' "$docker_compose_file")

    if [ -z "$services" ]; then
        error "No services found in the docker-compose file."
        exit 1
    fi

    for service in $services; do
        depends_on=$(yq eval ".services.$service.depends_on | .[]" "$docker_compose_file" 2>/dev/null)

        if [ -z "$depends_on" ]; then
            dependent_services=$(grep -E "^\s+[a-zA-Z0-9_-]+:" "$docker_compose_file" | awk -F ':' '{print $1}' | awk '{$1=$1};1' | grep -v "^$service$")
            if [ -n "$dependent_services" ]; then
                for dependent_service in $dependent_services; do
                    dependencies=$(yq eval ".services.$dependent_service.depends_on | .[]" "$docker_compose_file" 2>/dev/null)
                    if [[ "$dependencies" =~ (^|[[:space:]])"$service"($|[[:space:]]) ]]; then
                        depends_on="$dependent_service"
                        break
                    fi
                done
            fi
        fi

        if [ -z "$depends_on" ]; then
            db_type="SQLite"
            db_name="sqlite.db"
        else
            db_type="mysql"
            db_name=$(yq eval ".services.$depends_on.environment.MYSQL_DATABASE" "$docker_compose_file" 2>/dev/null)
            if [ -z "$db_name" ]; then
                continue
            fi
        fi

        env_file=$(yq eval ".services.$service.env_file" "$docker_compose_file" 2>/dev/null)
        volumes=$(yq eval ".services.$service.volumes | .[]" "$docker_compose_file" 2>/dev/null | awk -F ':' '{print $1}')

        if [ "$service" != "phpmyadmin" ] && [ "$db_name" != "null" ]; then
            success "Service: $service"
            success "Env file: $env_file"
            success "Volumes: $volumes"
            success "Database type: $db_type"
            success "Database name: $db_name"
            service_info["$service"]="${service}:${volumes}"

            if [[ "$db_type" == "mysql" ]]; then
                local env_file="/opt/marzban/.env"
                if [[ -f "$env_file" ]]; then
                    source <(grep -v '^#' "$env_file" | grep -E 'SQLALCHEMY_DATABASE_URL|MYSQL_ROOT_PASSWORD' | sed 's/^/export /')
                    if [ -z "$SQLALCHEMY_DATABASE_URL" ] || [ -z "$MYSQL_ROOT_PASSWORD" ]; then
                        error "Missing parameters in $env_file."
                        exit 1
                    else
                        db_url="$SQLALCHEMY_DATABASE_URL"
                        db_password="$MYSQL_ROOT_PASSWORD"
                    fi
                else
                    error "Environment file not found: $env_file"
                    exit 1
                fi
                success "Database URL: $db_url"
                success "Database password: $db_password"
                mysql_database["$service"]="${service}:${db_name}:${MYSQL_ROOT_PASSWORD}"
            fi
        fi
    done

    log "Listing volumes..."
    directories=()
    log "Scanning volume: /opt/marzban"
    mapfile -t items < <(find "/opt/marzban" -mindepth 1 -maxdepth 1 -type d \( -name "*mysql*" -prune \) -o -print)
    for item in "${items[@]}"; do
        success "$item"
        directories+=("$item")
    done

    for service in "${!service_info[@]}"; do
        IFS=':' read -r name volume <<< "${service_info[$service]}"
        if [[ -d "$volume" ]]; then
            log "Scanning volume: $volume for service: $name"
            mapfile -t items < <(find "$volume" -mindepth 1 -maxdepth 1 -type d \( -name "*mysql*" -prune \) -o -print)
            for item in "${items[@]}"; do
                success "$item"
                directories+=("$item")
            done
        else
            error "Volume $volume for service $name does not exist or is not a directory."
            exit 1
        fi
    done
    sleep 2
}

backup_generate() {

    : "${compression_:=.zip}"
    : "${compression_update:=zip -9 -u}"
    : "${compression_add:=zip -9 -r}"

    local backup_script="/root/${name}_backuper.sh"
    log "Generating backup script: $backup_script..."

    local DB=""
    if [ ${#mysql_database[@]} -gt 0 ]; then
        log "Checking DB..."
        for database in "${mysql_database[@]}"; do
            IFS=':' read -r service_name db_name db_password <<< "$database"
            log "Testing connection to $service_name database: $db_password..."
            local db_address="/root/${name}_${db_name}.sql"
            local dump_command="docker exec marzban-mysql-1 mysqldump -u root -p'${db_password}' '${db_name}' > '${db_address}'"
            local compress_command="$compression_update \"\$backup_name\" \"$db_address\""
            local remove_command="rm -f \"$db_address\""
            DB+="${dump_command}\n${compress_command}\n${remove_command}\n\n"
        done
    fi

    local send_limit send_caption send_file
    if [ "$send_to_option" == "1" ]; then  # Telegram
        send_limit=49000000
        send_caption="curl -F \"chat_id=$chat_id\" -F \"text=\$caption\" \"https://api.telegram.org/bot$bot_token/sendMessage\""
        send_file="curl -F \"chat_id=$chat_id\" -F \"document=@\$file\" -F \"caption=\$caption\" \"https://api.telegram.org/bot$bot_token/sendDocument\""
    elif [ "$send_to_option" == "2" ]; then  # Discord
        send_limit=24000000
        send_caption="curl -H \"Content-Type: application/json\" -X POST -d '{\"content\": \"\$caption\"}' \"$webhook_url\""
        send_file="curl -H \"Content-Type: multipart/form-data\" -F \"payload_json={\\\"content\\\":\"\$caption\"}\" -F \"file=@\$file\" \"$webhook_url\""
    else
        error "Invalid send method selected."
        exit 1
    fi

    # Generate script
    cat <<EOL > "$backup_script"
#!/bin/bash

# Base info
ip=\$(hostname -I | awk '{print \$1}')

# Function to get current timestamp
get_timestamp() {
    TZ='Asia/Tehran' date +%Y-%m-%d-%H-%M
}

# Function to create backup name
get_backup_name() {
    local current_timestamp=\$(get_timestamp)
    echo "${name}_\${current_timestamp}$compression_"
}

# Function to create caption
get_caption() {
    local current_timestamp=\$(get_timestamp)
    echo "$caption

📦  from \$ip
⚡️  by @ErfJabs"
}

# Function to send file
send_file() {
    local file="\$1"
    local caption="\$(get_caption)"
    $send_file
}

# Archive directories
directories=(${directories[@]})
backup_name=\$(get_backup_name)
$compression_add "\${backup_name}" "\${directories[@]}"

# Add database backup commands (if any)
$(echo -e "$DB")

# Check archive size and send
archive_size=\$(stat -c %s "\${backup_name}")
if (( archive_size > $send_limit )); then
    split_prefix="\${backup_name}.part"
    split -b $send_limit -d "\${backup_name}" "\${split_prefix}"
    $send_caption
    for file in \${split_prefix}*; do
        send_file "\$file"
        rm "\$file"
    done
else 
    send_file "\${backup_name}"
fi

# Delete backup
rm -f "\${backup_name}"

EOL

    chmod +x "$backup_script"
    success "Backup script created: $backup_script"

    log "Running the backup script..."
    if bash "$backup_script"; then
        success "Backup script run successfully."

        log "Setting up cron job..."
        (crontab -l 2>/dev/null; echo "$cron_time $backup_script") | crontab -
        if [ $? -eq 0 ]; then
            success "Cron job set up successfully. Backups will run every $minutes minutes."
        else
            error "Failed to set up cron job. Set it up manually: $cron_time $backup_script"
            exit 1
        fi

        success "🎉 Your backup system is set up and running!"
        success "Backup script location: $backup_script"
        success "Cron job: Every $minutes minutes"
        success "First backup created and sent."
        success "Thank you for using @ErfJabs backup script. Enjoy automated backups!"
        exit 0
    else
        error "Failed to run backup script. Check the script and try again."
        exit 1
    fi
}

run() {
    clear
    menu
}

run

