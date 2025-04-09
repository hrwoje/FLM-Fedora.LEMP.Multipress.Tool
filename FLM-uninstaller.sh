#!/bin/bash

# FLM Uninstaller Script (Fedora LEMP Multisite) v1.1
# Companion uninstaller for LEMP + WP Multisite Script (v2.14.x series)
# Author: H Dabo (Concept) / AI (Implementation) - 2025
# ------------------------------------------------------------------------------------
# - ADD: Confirmation menu before starting removal (v1.1)
# - FIX: Variable definition order for BORDER_DOUBLE error (v1.1)
# --- Previous ---
# - ADD: System cleanup and update at the end
# - WARNING: THIS SCRIPT IS EXTREMELY DESTRUCTIVE AND WILL REMOVE PACKAGES,
#          CONFIGURATIONS, DATABASES, AND WEBSITE FILES INSTALLED BY THE
#          COMPANION INSTALLATION SCRIPT. USE WITH EXTREME CAUTION.
#          THERE IS NO UNDO FUNCTIONALITY.
# ------------------------------------------------------------------------------------

set -uo pipefail

# --- Color Codes & Menu Styling (Define BEFORE use!) ---
C_BLUE='\e[1;34m'; C_GREEN='\e[1;32m'; C_YELLOW='\e[1;33m'; C_RED='\e[1;31m'
C_CYAN='\e[1;36m'; C_MAGENTA='\e[1;35m'; C_WHITE='\e[1;37m'; C_GREY='\e[0;37m'; C_RESET='\e[0m'
BORDER_DOUBLE="======================================================================================"
BORDER_SINGLE="--------------------------------------------------------------------------------------"
PROMPT_COLOR=$C_WHITE

# --- Variables (Should match the main installation script) ---
WORDPRESS_ROOT="/var/www/wordpress"
WP_CONTENT_DIR="${WORDPRESS_ROOT}/wp-content"
NGINX_CONF_DIR="/etc/nginx/conf.d"
PHP_INI_PATH="/etc/php.ini"
PHP_EXTENSIONS_DIR="/etc/php.d"
PHP_OPCACHE_CONF_PATH="${PHP_EXTENSIONS_DIR}/99-wp-optimized-opcache.ini"
PHP_APCU_CONF_PATH="${PHP_EXTENSIONS_DIR}/40-apcu.ini"
MARIADB_DATA_DIR="/var/lib/mysql"
MARIADB_OPT_CONF="/etc/my.cnf.d/99-wordpress-optimizations.cnf"
PHPMYADMIN_CONFIG_DIR="/etc/phpMyAdmin"
PHPMYADMIN_LIB_DIR="/var/lib/phpmyadmin"
WP_CLI_PATH="/usr/local/bin/wp"
MAIN_LOG_FILE="/var/log/lemp_wp_ms_optimized_apcu_install.log"
UNINSTALL_LOG_FILE="/var/log/flm_uninstaller.log"

# --- Package Lists ---
PHP_PACKAGES=( php php-common php-fpm php-mysqlnd php-gd php-json php-mbstring php-xml php-curl php-zip php-intl php-imagick php-opcache php-soap php-bcmath php-sodium php-exif php-fileinfo php-pecl-apcu php-pecl-apcu-devel )
OTHER_PACKAGES=( nginx mariadb-server phpmyadmin curl wget ImageMagick )
CORE_UTILS=( policycoreutils policycoreutils-python-utils util-linux-user openssl dnf-utils )
CERTBOT_PACKAGES=( certbot python3-certbot-nginx )

# --- Logging Function ---
log_message() { local type="$1" message="$2"; echo "[$(date '+%Y-%m-%d %H:%M:%S')] [${type}] ${message}" | tee -a "$UNINSTALL_LOG_FILE"; }

# --- Helper function for command execution with check ---
run_command() {
    local description="$1"; shift; local suppress_output=false
    if [[ "$1" == "--suppress" ]]; then suppress_output=true; shift; fi
    log_message "INFO" "Starting: ${description}"; if output=$("$@" 2>&1); then
        log_message "INFO" "Success: ${description}"; [[ -n "$output" ]] && echo -e "$output" >> "$UNINSTALL_LOG_FILE";
        if [[ "$suppress_output" == false ]]; then echo "$output"; fi; return 0;
    else local exit_code=$?; log_message "ERROR" "Failed (Exit Code: $exit_code): ${description}."; log_message "ERROR" "Output:\n$output";
        if [[ "$suppress_output" == false ]]; then echo -e "${C_RED}---- ERROR Output ----${C_RESET}" >&2; echo -e "$output" >&2; echo -e "${C_RED}---------------------${C_RESET}" >&2; fi
        log_message "ERROR" "See log file: ${UNINSTALL_LOG_FILE}"; return $exit_code; fi
}

# --- Root Check ---
check_root() {
    > "$UNINSTALL_LOG_FILE"; # Create/clear log file
     CALLING_USER=${SUDO_USER:-$(logname)}
     chown "${CALLING_USER:-root}":"${CALLING_USER:-root}" "$UNINSTALL_LOG_FILE" || true
     log_message "INFO" "FLM Uninstaller started by $(whoami), invoked by ${CALLING_USER}"
     if [[ $EUID -ne 0 ]]; then log_message "ERROR" "Root privileges required."; echo -e "${C_RED}ERROR: This script must be run as root (or with sudo).${C_RESET}"; exit 1; fi
}

# --- Main Uninstall Logic ---
perform_uninstall() {
    # Stop and Disable Services
    log_message "INFO" "Stopping and disabling services..."
    echo -e "\n${C_BLUE}Stopping and disabling services...${C_RESET}"
    run_command "Stop Nginx" --suppress systemctl stop nginx.service ||:
    run_command "Disable Nginx" --suppress systemctl disable nginx.service ||:
    run_command "Stop MariaDB" --suppress systemctl stop mariadb.service ||:
    run_command "Disable MariaDB" --suppress systemctl disable mariadb.service ||:
    run_command "Stop PHP-FPM" --suppress systemctl stop php-fpm.service ||:
    run_command "Disable PHP-FPM" --suppress systemctl disable php-fpm.service ||:
    log_message "INFO" "Services stopped/disabled."
    echo "Services stopped/disabled."

    # Remove Firewall Rules
    log_message "INFO" "Removing firewall rules..."
    echo -e "\n${C_BLUE}Removing firewall rules...${C_RESET}"
    run_command "Remove FW HTTP" --suppress firewall-cmd --permanent --remove-service=http ||:
    run_command "Remove FW HTTPS" --suppress firewall-cmd --permanent --remove-service=https ||:
    run_command "Reload FW" --suppress firewall-cmd --reload ||:
    log_message "INFO" "Firewall rules removed."
    echo "Firewall rules removed."

    # Critical Data Removal Confirmation - WordPress Files
    echo ""
    log_message "WARN" "Prompting for WordPress files removal confirmation."
    echo -e "${C_RED}${BORDER_SINGLE}${C_RESET}"
    echo -e "${C_RED}!! WARNING: WORDPRESS FILES DELETION !!${C_RESET}"
    echo -e "This will permanently delete all files in: ${C_CYAN}${WORDPRESS_ROOT}${C_RESET}"
    read -p "--> To confirm, type 'DELETE WP FILES' (all caps): " confirm_wp_delete
    if [[ "${confirm_wp_delete}" == "DELETE WP FILES" ]]; then
        log_message "WARN" "User confirmed WordPress files deletion."
        run_command "Removing WordPress directory" rm -rf "${WORDPRESS_ROOT}"
        echo -e "${C_YELLOW}WordPress directory removed.${C_RESET}"
    else
        log_message "INFO" "WordPress files deletion skipped by user."
        echo -e "${C_GREEN}Skipping WordPress files deletion.${C_RESET}"
    fi
    echo -e "${C_RED}${BORDER_SINGLE}${C_RESET}"

    # Critical Data Removal Confirmation - MariaDB Data
    echo ""
    log_message "WARN" "Prompting for MariaDB data removal confirmation."
    echo -e "${C_RED}${BORDER_SINGLE}${C_RESET}"
    echo -e "${C_RED}!! WARNING: DATABASE DELETION !!${C_RESET}"
    echo -e "This will permanently delete all databases and data in: ${C_CYAN}${MARIADB_DATA_DIR}${C_RESET}"
    read -p "--> To confirm, type 'DELETE DATABASES' (all caps): " confirm_db_delete
    if [[ "${confirm_db_delete}" == "DELETE DATABASES" ]]; then
        log_message "WARN" "User confirmed MariaDB data deletion."
        run_command "Removing MariaDB data directory" rm -rf "${MARIADB_DATA_DIR}"
        echo -e "${C_YELLOW}MariaDB data directory removed.${C_RESET}"
    else
        log_message "INFO" "MariaDB data deletion skipped by user."
        echo -e "${C_GREEN}Skipping MariaDB data deletion.${C_RESET}"
    fi
    echo -e "${C_RED}${BORDER_SINGLE}${C_RESET}"

    # Remove Packages
    log_message "INFO" "Removing packages..."
    echo -e "\n${C_BLUE}Removing installed packages...${C_RESET}"
    local ALL_PACKAGES=("${OTHER_PACKAGES[@]}" "${PHP_PACKAGES[@]}" "${CERTBOT_PACKAGES[@]}" "${CORE_UTILS[@]}")
    if rpm -q remi-release &>/dev/null; then log_message "INFO" "Adding remi-release to removal list."; ALL_PACKAGES+=("remi-release"); fi
    log_message "INFO" "Packages to remove: ${ALL_PACKAGES[*]}"
    run_command "Remove packages via DNF" dnf remove -y "${ALL_PACKAGES[@]}"
    run_command "Autoremove dependencies" dnf autoremove -y
    log_message "INFO" "Package removal process finished."
    echo "Packages removed."

    # Remove Configuration Files, Logs & Other Data
    log_message "INFO" "Removing configuration files, remaining data, logs..."
    echo -e "\n${C_BLUE}Removing configuration files and remaining data...${C_RESET}"
    run_command "Remove Nginx WP conf" rm -f "${NGINX_CONF_DIR}/wordpress.conf"
    run_command "Remove MariaDB opt conf" rm -f "${MARIADB_OPT_CONF}"
    run_command "Remove phpMyAdmin config dir" rm -rf "${PHPMYADMIN_CONFIG_DIR}"
    run_command "Remove phpMyAdmin lib dir" rm -rf "${PHPMYADMIN_LIB_DIR}"
    run_command "Remove custom OPcache conf" rm -f "$PHP_OPCACHE_CONF_PATH"
    run_command "Remove custom APCu conf" rm -f "$PHP_APCU_CONF_PATH"
    run_command "Remove php.ini backups" find /etc -name 'php.ini.bak.*' -delete
    run_command "Remove ext .ini backups" find "$PHP_EXTENSIONS_DIR" -name '*.ini.bak*' -delete
    run_command "Remove WP-CLI" rm -f "$WP_CLI_PATH"
    run_command "Remove Nginx WP logs" rm -f "/var/log/nginx/wordpress.access.log" "/var/log/nginx/wordpress.error.log"
    run_command "Remove PHP-FPM error log" rm -f "/var/log/php-fpm/error.log"
    run_command "Remove Nginx log dir (if empty)" rmdir /var/log/nginx 2>/dev/null || log_message "INFO" "/var/log/nginx not empty or doesn't exist."
    run_command "Remove PHP-FPM log dir (if empty)" rmdir /var/log/php-fpm 2>/dev/null || log_message "INFO" "/var/log/php-fpm not empty or doesn't exist."
    run_command "Remove main script log" rm -f "$MAIN_LOG_FILE"
    log_message "INFO" "Configuration and data removal finished."
    echo "Configuration files and remaining data removed."

    # Remove SELinux Context
    if command -v semanage &> /dev/null; then
        log_message "INFO" "Removing SELinux file context..."
        echo -e "\n${C_BLUE}Removing SELinux file context...${C_RESET}"
        run_command "Remove SELinux fcontext for wp-content" --suppress semanage fcontext -d "${WP_CONTENT_DIR}(/.*)?" || log_message "WARN" "Failed to remove SELinux context (might not have existed)."
        echo "SELinux context removal attempted."
    else
        log_message "WARN" "semanage command not found, skipping SELinux context removal."
    fi

    # System Cleanup and Update
    log_message "INFO" "Starting system cleanup and update..."
    echo -e "\n${C_BLUE}Cleaning DNF cache...${C_RESET}"
    run_command "DNF Clean All" dnf clean all
    echo -e "\n${C_BLUE}Updating system packages...${C_RESET}"
    run_command "DNF Update System" dnf update -y
    log_message "INFO" "System cleanup and update finished."

    # Final Message
    echo -e "\n${C_GREEN}${BORDER_DOUBLE}${C_RESET}"
    echo -e "${C_GREEN}== ${C_WHITE} FLM Uninstallation Complete ${C_GREEN}                                      =="
    echo -e "${C_GREEN}${BORDER_DOUBLE}${C_RESET}"
    echo -e "${C_YELLOW}The script has attempted to remove all installed components and data.${C_RESET}"
    echo -e "System cleanup and update have been performed."
    echo -e "Please review the output above and the log file (${C_GREY}${UNINSTALL_LOG_FILE}${C_RESET}) for any errors."
    echo -e "${C_YELLOW}It's strongly recommended to ${C_WHITE}reboot the server now${C_YELLOW} for a completely clean state.${C_RESET}"
    log_message "INFO" "================ Uninstallation Process Finished ================"
    # Remove self log at the very end
    rm -f "$UNINSTALL_LOG_FILE"
}


# --- Confirmation Menu ---
display_confirmation_menu() {
    clear
    echo -e "\n${C_RED}${BORDER_DOUBLE}${C_RESET}"
    echo -e "${C_RED}== ${C_WHITE}          FLM Uninstaller Confirmation          ${C_RED}==${C_RESET}"
    echo -e "${C_RED}${BORDER_DOUBLE}${C_RESET}"
    echo -e "\n${C_YELLOW}This script will permanently remove the LEMP stack, WordPress files,${C_RESET}"
    echo -e "${C_YELLOW}databases, and related configurations installed by the companion script.${C_RESET}"
    echo -e "\n${C_RED}THIS ACTION IS IRREVERSIBLE AND DESTRUCTIVE.${C_RESET}"
    echo ""
    echo -e "   ${C_GREEN}[1]${C_RESET} Proceed with Full Uninstallation"
    echo -e "   ${C_RED}[2]${C_RESET} Exit Uninstaller Now"
    echo ""
    echo -e "${C_RED}${BORDER_SINGLE}${C_RESET}"

    local choice
    while true; do
        read -p "$(echo -e ${PROMPT_COLOR}"Your choice [1 or 2]: "${C_RESET})" choice
        case $choice in
            1)
                log_message "INFO" "User chose to proceed with uninstallation."
                perform_uninstall # Start the actual removal process
                break # Exit the loop after uninstall
                ;;
            2)
                log_message "INFO" "User chose to exit the uninstaller."
                echo -e "${C_GREEN}Uninstaller exited. No changes were made.${C_RESET}"
                exit 0
                ;;
            *)
                log_message "WARN" "Invalid choice in confirmation menu: ${choice}"
                echo -e "${C_RED}Invalid choice. Please enter 1 or 2.${C_RESET}"
                ;;
        esac
    done
}

# --- Script Execution ---
check_root
display_confirmation_menu # Show confirmation menu first

exit 0