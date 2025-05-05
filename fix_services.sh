#!/bin/bash

# Exit on error, unset vars, and failed pipelines
set -euo pipefail

# Lockfile to prevent concurrent execution
LOCKFILE="/tmp/fix_services.lock"
exec 200>"$LOCKFILE"
flock -n 200 || {
    echo "Another instance of the script is already running."
    exit 1
}

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Default log file
LOG_FILE="/var/log/fix_services.log"
if ! touch "$LOG_FILE" &>/dev/null; then
    LOG_FILE="/tmp/fix_services.log"
    echo -e "${YELLOW}⚠ Log fallback to $LOG_FILE${NC}"
fi

# Trap errors and log
trap 'log_message "Script crashed at line $LINENO" "CRITICAL"' ERR

# Load external config if present
[[ -f /etc/fix_services.conf ]] && source /etc/fix_services.conf

# Root permission check
if [ "$EUID" -ne 0 ]; then
    echo -e "${RED}✗ This script must be run as root${NC}"
    exit 1
fi

# Logging
log_message() {
    local message="$1"
    local level="${2:-INFO}"
    local now
    now=$(date '+%Y-%m-%d %H:%M:%S')
    echo -e "[$now] [$level] $message" | tee -a "$LOG_FILE"
}

print_section() {
    local title="$1"
    echo -e "\n${BLUE}=== $title ===${NC}"
    log_message "Starting section: $title"
}

fix_directory() {
    local dir="$1"
    local user="$2"
    local group="$3"

    if [ ! -d "$dir" ]; then
        log_message "Creating directory: $dir" "FIX"
        mkdir -p "$dir"
    fi

    if [ "$(stat -c '%U:%G' "$dir")" != "$user:$group" ]; then
        log_message "Fixing ownership of $dir to $user:$group" "FIX"
        chown -R "$user:$group" "$dir"
    fi

    if command -v selinuxenabled &>/dev/null && selinuxenabled; then
        log_message "Restoring SELinux context for $dir" "INFO"
        restorecon -Rv "$dir"
    fi
}

check_and_fix_service() {
    local service="$1"

    print_section "Checking $service"

    if ! systemctl list-unit-files | grep -qw "${service}.service"; then
        log_message "$service service unit not found" "WARNING"
        echo -e "${YELLOW}⚠ $service service not found on this system${NC}"
        return
    fi

    if systemctl is-active --quiet "$service"; then
        log_message "$service is running" "SUCCESS"
        echo -e "${GREEN}✓ $service is running${NC}"
    else
        log_message "$service is not running" "ERROR"
        echo -e "${RED}✗ $service is not running${NC}"

        local error_log
        error_log=$(journalctl -u "$service" -n 50 --no-pager)
        log_message "Recent $service errors:\n$error_log" "DEBUG"

        case "$service" in
            nginx)
                fix_directory "/var/log/nginx" "nginx" "nginx"
                ;;
            php-fpm)
                fix_directory "/var/log/php-fpm" "nginx" "nginx"
                if grep -qE "^\s*user\s*=\s*apache" /etc/php-fpm.d/www.conf; then
                    log_message "Fixing PHP-FPM user/group to nginx" "FIX"
                    sed -i 's/^\s*user\s*=.*/user = nginx/' /etc/php-fpm.d/www.conf
                    sed -i 's/^\s*group\s*=.*/group = nginx/' /etc/php-fpm.d/www.conf
                fi
                ;;
            mariadb)
                fix_directory "/var/log/mariadb" "mysql" "mysql"
                fix_directory "/var/lib/mysql" "mysql" "mysql"
                ;;
        esac

        log_message "Restarting $service..." "FIX"
        for attempt in {1..3}; do
            if systemctl restart "$service"; then
                break
            else
                log_message "Retry $attempt failed for $service" "RETRY"
                sleep 2
            fi
        done

        if systemctl is-active --quiet "$service"; then
            log_message "$service successfully restarted" "SUCCESS"
            echo -e "${GREEN}✓ $service has been fixed and is now running${NC}"
        else
            log_message "Failed to restart $service after retries" "ERROR"
            echo -e "${RED}✗ Failed to fix $service${NC}"
        fi
    fi
}

generate_summary() {
    print_section "Service Status Summary"

    local services=("nginx" "php-fpm" "mariadb")
    local all_ok=true

    for service in "${services[@]}"; do
        if systemctl is-active --quiet "$service"; then
            echo -e "${GREEN}✓ $service: Running${NC}"
        else
            echo -e "${RED}✗ $service: Not Running${NC}"
            all_ok=false
        fi
    done

    if $all_ok; then
        echo -e "\n${GREEN}All services are running properly!${NC}"
    else
        echo -e "\n${YELLOW}Some services require attention. See: $LOG_FILE${NC}"
    fi
}

main() {
    print_section "Starting Service Health Check"
    log_message "Beginning full service health check" "INFO"

    check_and_fix_service "nginx"
    check_and_fix_service "php-fpm"
    check_and_fix_service "mariadb"

    generate_summary

    print_section "Service Health Check Complete"
    log_message "All checks complete" "INFO"
}

main
exit 0
