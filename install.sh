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

    packages_to_install=()
    for pkg in curl wget zip cron; do
        if ! command -v $pkg &> /dev/null; then
            log "Need to install $pkg"
            packages_to_install+=($pkg)
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

    if ! command -v yq &> /dev/null; then
        log "Need to install yq"
        need_yq=true
    else
        log "yq is already installed."
    fi

    if ! command -v 7z &> /dev/null; then
        log "Need to install p7zip"
        if [ "$PKG_MANAGER" = "apt-get" ]; then
            packages_to_install+=(p7zip-full)
        else
            packages_to_install+=(p7zip)
        fi
    else
        log "p7zip is already installed."
    fi

    if [ ${#packages_to_install[@]} -ne 0 ]; then
        log "Installing missing packages: ${packages_to_install[*]}"
        $PKG_INSTALL "${packages_to_install[@]}" || { error "Package installation failed."; exit 1; }
    fi

    if [ "$need_yq" = true ]; then
        log "Downloading yq for architecture $ARCH..."
        wget "https://github.com/mikefarah/yq/releases/latest/download/$YQ_BINARY" -O /usr/bin/yq || { error "Failed to download yq."; exit 1; }
        chmod +x /usr/bin/yq || { error "Failed to set execute permissions on yq."; exit 1; }
        log "yq installed successfully."
    fi

    if ! systemctl is-active --quiet cron; then
        log "Starting cron service..."
        systemctl start cron || { error "Failed to start cron service."; exit 1; }
    fi
    if ! systemctl is-enabled --quiet cron; then
        log "Enabling cron service to start on boot..."
        systemctl enable cron || { error "Failed to enable cron service."; exit 1; }
    fi

    success "All necessary packages are installed and cron service is running."
    sleep 1
}

menu() {
    while true; do
        print "\n\t Welcome to Backuper!"
        print "\t\t version 0.2.0 by @ErfJab"
        print "—————————————————————————————————————————————————————————————————————————"
        print "1) Install"
        print "2) Manage"
        print "0) Exit"
        print ""
        input "Enter your option number: " option
        clear
        case $option in
            1)
                start_advenced_backup
                ;;
            2)
                manage_backups
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

manage_backups() {
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
    print "We offer two types of backup installers:\n"
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

backup_template() {
    clear
    print "[TEMPLATE]\n"
    print "Choose a backup template. You can add or remove custom directories after selecting.\n"
    print "1) Marzban"
    print "2) Marzban Logs"
    print "3) All X-ui's"
    print "4) Hiddify Manager"
    print "0) Custom"
    print ""

    while true; do
        input "Enter your template number: " template
        case $template in
            1)
                marzban_template
                break
                ;;
            2)
                success "You chose marzban logs."
                marzban_logs=true
                break
                ;;
            3)
                xui_template
                break
                ;;
            4)
                hiddify_template
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

hiddify_template() {
    log "Checking hiddify backup..."
    local hiddify_file="/opt/hiddify-manager/hiddify-panel/backup.sh"

    if [ ! -f "$hiddify_file" ]; then
        error "Backup file does not exist."
        exit 1
    else
        success "$hiddify_file Backup file exists."
        hiddify_backup=true
    fi
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
                local env_file="/opt/marzban/$env_file"
                if [[ -f "$env_file" ]]; then
                    SQLALCHEMY_DATABASE_URL=$(grep -v '^#' "$env_file" | grep 'SQLALCHEMY_DATABASE_URL' | cut -d '=' -f2- | tr -d ' ')
                    MYSQL_ROOT_PASSWORD=$(grep -v '^#' "$env_file" | grep 'MYSQL_ROOT_PASSWORD' | cut -d '=' -f2- | tr -d ' ')
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

xui_template() {
    log "Checking x-ui db..."
    directories=()
    local db_path="/root/x-ui/x-ui.db"
    if [ ! -f "$db_path" ]; then
        error "Database file not found: $db_path"
        exit 1
    else
        success "Database file found: $db_path"
        directories+=("$db_path")
    fi

    log "Adding directories for x-ui"
    
    local xui_directory="/root/x-ui"
    mapfile -t items < <(find "$xui_directory" -mindepth 1 -maxdepth 1 -type d)
    for item in "${items[@]}"; do
        success "$item"
        directories+=("$item")
    done

    for dir in "${directories[@]}"; do
        success "Directory found: $dir"
    done
    sleep 2
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
    send_to
    backup_compression
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

send_to() {
    clear
    print "[PLATFORM]\n"
    print "Select one platform to send your backup.\n"
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
                compression_ext=".zip"
                compression_cmd="zip -9 -r"
                compression_update="zip -9 -u"
                break
                ;;
            2)
                compression_ext=".7z"
                compression_cmd="7z a -mx=9 -mhe=on -t7z"
                compression_update="7z u -mx=9 -mhe=on"
                break
                ;;
            *)
                error "Invalid choice. Please select 1 or 2."
                ;;
        esac
    done

    while true; do
        input "Do you want to password protect the archive? (y/n): " use_password
        case $use_password in
            [Yy]*)
                while true; do
                    input "Enter the password for the archive: " archive_password
                    input "Confirm the password: " confirm_password
                    
                    if [ "$archive_password" == "$confirm_password" ]; then
                        echo "Password confirmed."
                        if [ "$compression_ext" == ".zip" ]; then
                            compression_cmd="$compression_cmd -e -P $archive_password"
                            compression_update="$compression_update -e -P $archive_password"
                        elif [ "$compression_ext" == ".7z" ]; then
                            compression_cmd="$compression_cmd -p$archive_password"
                            compression_update="$compression_update -p$archive_password"
                        fi
                        break 2  # Exit both loops
                    else
                        echo "Passwords do not match. Please try again."
                    fi
                done
                ;;
            [Nn]*)
                break
                ;;
            *)
                error "Please answer y or n."
                ;;
        esac
    done

    if [ "$send_to_option" == "1" ]; then  # Telegram
        max_file_size=49
    elif [ "$send_to_option" == "2" ]; then  # Discord
        max_file_size=24
    fi

    # Construct the full compression command
    if [ "$compression_ext" == ".zip" ]; then
        compression_full_cmd="$compression_cmd -s ${max_file_size}m"
        compression_update_cmd="$compression_update -s ${max_file_size}m"
    elif [ "$compression_ext" == ".7z" ]; then
        compression_full_cmd="$compression_cmd -v${max_file_size}m"
        compression_update_cmd="$compression_update -v${max_file_size}m"
    fi
    sleep 1


}

backup_generate() {
    local backup_script="/root/${name}_backuper.sh"
    log "Generating backup script: $backup_script..."

    local DB=""
    if [ ${#mysql_database[@]} -gt 0 ]; then
        for database in "${mysql_database[@]}"; do
            IFS=':' read -r service_name db_name db_password <<< "$database"
            local db_address="/root/${name}_${db_name}_backuper.sql"
            local dump_command="if ! docker exec marzban-mysql-1 mysqldump -u root -p'${db_password}' '${db_name}' > '${db_address}'; then
    message=\"Failed to backup database ${db_name}. Please check the server.\"
    $send_notification_command
    exit 1
fi"
            DB+="${dump_command}\n"
            directories+=("$db_address")
        done
    fi

    local LOGS=""
    if [ "$marzban_logs" = true ]; then
        LOGS+="
if ! marzban logs --no-follow > \"marzban_logs_backuper.log\"; then
    message=\"Failed to generate logs. Please check the server.\"
    \$send_notification_command
    exit 1
fi
"
        directories+=("marzban_logs_backuper.log")
    fi

    local COMMANDS=""
    if [ "$hiddify_backup" = true ]; then
        COMMANDS+="
if ! bash /opt/hiddify-manager/hiddify-panel/backup.sh;then
    message=\"Failed to generate hiddify backup. Please check the server.\"
    \$send_notification_command
    exit 1
fi
"
        directories+=("/opt/hiddify-manager/hiddify-panel/backup/*.json")
    fi

    local send_file_command
    local send_notification_command
    if [ "$send_to_option" == "1" ]; then  # Telegram
        send_file_command="curl -s -F \"chat_id=$chat_id\" -F \"document=@\$file_to_send\" -F \"caption=\$caption\" \"https://api.telegram.org/bot$bot_token/sendDocument\""
        send_notification_command="curl -s -X POST \"https://api.telegram.org/bot$bot_token/sendMessage\" -d \"chat_id=$chat_id\" -d \"text=\$message\""
    elif [ "$send_to_option" == "2" ]; then  # Discord
        send_file_command="curl -s -H \"Content-Type: multipart/form-data\" -F \"payload_json={\\\"content\\\":\"\$caption\"}\" -F \"file=@\$file_to_send\" \"$webhook_url\""
        send_notification_command="curl -s -H \"Content-Type: application/json\" -X POST -d \"{\\\"content\\\": \"\$message\"}\" \"$webhook_url\""
    fi

    cat <<EOL > "$backup_script"
#!/bin/bash

ip=\$(hostname -I | awk '{print \$1}')
timestamp=\$(TZ='Asia/Tehran' date +%m%d-%H%M)
base_name="/root/${name}_\${timestamp}."
backup_name="/root/${name}_\${timestamp}${compression_ext}"
caption="$caption

📦  from \$ip
⚡️  by @ErfJabs"

rm -f "\$backup_name"*

$(echo -e "$DB")

$(echo -e "$LOGS")

$(echo -e "$COMMANDS")

if ! $compression_full_cmd "\$backup_name" ${directories[@]}; then
    message="Failed to compress files. Please check the server."
    $send_notification_command
    exit 1
fi

if ls \${base_name}* > /dev/null 2>&1; then
    for file_to_send in \${base_name}*; do
        if $send_file_command; then
            echo "Backup part sent successfully: $file_to_send"
        else
            message="Failed to send backup part: $file_to_send. Please check the server."
            $send_notification_command
            exit 1
        fi
    done
    echo "All backup parts sent successfully"
else
    message="Backup file not found: $base_name. Please check the server."
    $send_notification_command
    exit 1
fi

rm -f "\$base_name"*
rm -f *"_backuper.sql"
rm -f *"_backuper.log"
rm -f "/opt/hiddify-manager/hiddify-panel/backup/"*
EOL

    chmod +x "$backup_script"
    success "Backup script created: $backup_script"

    log "Running the backup script..."
    if output=$(bash "$backup_script"); then
        success "Backup script run successfully."
        log "Setting up cron job..."
        if (crontab -l 2>/dev/null; echo "$cron_time $backup_script") | crontab -; then
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
        exit 1
    else
        error "Failed to run backup script. Output:"
        error "$output"
        message="Backup script failed to run. Please check the server."
        eval "$send_notification_command"
        exit 1
    fi
}

run() {
    cd
    clear
    menu
}

run
