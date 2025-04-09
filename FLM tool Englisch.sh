
#!/bin/bash

# LEMP Stack + phpMyAdmin + WordPress Multisite TOP OPTIMIZATION Script v2.15.2-EN for Fedora
# Author: H Dabo (Concept & Base) / AI (Implementation & Refinement) - 2025
# ------------------------------------------------------------------------------------
# - FIX: Main menu color display and command not found error (v2.15.2)
# --- Previous changes ---
# - ADDED: Multisite Enable/Disable toggle menu option
# - FIX: PHP Extension Management - sed command for enabling extensions
# - ADDED: WordPress Cookie Fix/Revert menu options
# - ADDED: Service Restart menu option
# - ADDED: Version information menu option
# - ADDED: Interactive PHP Extension management menu option
# - ADDED: Interactive PHP settings adjustment menu option
# - ADDED: Comprehensive Health Check menu option
# - ADDED: Welcome screen with improved styling
# - FIX: Heredoc syntax for PMA and Nginx config
# - FIX: Log directory creation for Nginx and PHP-FPM
# - FIX: Health check summary logic after auto-fix
# - REMOVED: Redis/Valkey
# - ADDED: Focus on APCu Caching
# - OPT/FIX: Various optimizations and bug fixes
# --- Base Features ---
# - Choice for Default (insecure 'root') or Custom DB Root Password
# - Latest PHP via DNF Module (tries 8.3) + Remi Repo fallback
# - Highly Optimized Nginx (Headers, Gzip, Cache, Security)
# - Automated installation (Asks WP Admin PW & optionally DB Root PW)
#
# 🚨🚨🚨 WARNING: Default DB Root PW option is INSECURE! Choose Custom! 🚨🚨🚨
# 🚨🚨🚨 CHOOSE A STRONG WP ADMIN PASSWORD WHEN PROMPTED!             🚨🚨🚨
# 🚨🚨🚨 FOR LOCAL, NON-PUBLIC TEST ENVIRONMENTS ONLY!        🚨🚨🚨
#
# IMPORTANT: 100% PageSpeed score requires frontend optimization and page caching AFTER this installation!
#
# WARNING: Options 2 and 3 are DESTRUCTIVE and will remove data!

set -uo pipefail

# --- Color Codes ---
C_BLUE='\e[1;34m'     # Blue (Bold)
C_GREEN='\e[1;32m'   # Green (Bold)
C_YELLOW='\e[1;33m'  # Yellow (Bold)
C_RED='\e[1;31m'     # Red (Bold)
C_CYAN='\e[1;36m'    # Cyan (Bold)
C_MAGENTA='\e[1;35m' # Magenta (Bold)
C_WHITE='\e[1;37m'   # White (Bold)
C_GREY='\e[0;37m'    # Grey (Normal)
C_RESET='\e[0m'      # Reset

# --- Menu Styling ---
BORDER_DOUBLE="======================================================================================"
BORDER_SINGLE="--------------------------------------------------------------------------------------"
TITLE_COLOR=$C_WHITE; HEADER_COLOR=$C_BLUE; ACTION_INSTALL_COLOR=$C_GREEN; ACTION_CONFIG_COLOR=$C_MAGENTA
ACTION_INFO_COLOR=$C_CYAN; ACTION_WARN_COLOR=$C_YELLOW; ACTION_DANGER_COLOR=$C_RED; PROMPT_COLOR=$C_WHITE

# --- Variables ---
CALLING_USER=${SUDO_USER:-$(logname)}
# -- Database Credentials --
MARIADB_ROOT_PASSWORD_DEFAULT='root' # INSECURE!
CUSTOM_DB_ROOT_PASSWORD=''; ACTIVE_DB_ROOT_PASSWORD=''; USE_CUSTOM_DB_ROOT_PASSWORD=false
WORDPRESS_DB_NAME="wordpress_ms_opt_db"; WORDPRESS_DB_USER="wordpress_ms_opt_usr"; WORDPRESS_DB_PASSWORD='' # Generated
# -- CUSTOM WP Admin Credentials --
CUSTOM_WP_ADMIN_USER=''; CUSTOM_WP_ADMIN_PASSWORD=''; WP_ADMIN_EMAIL='admin@example.com'; WP_SITE_TITLE='Top Optimized WP Multisite'; WP_SITE_URL='http://localhost'
# -- PHP Settings (Defaults for installation) --
PHP_MEMORY_LIMIT="256M"; PHP_UPLOAD_MAX_FILESIZE="64M"; PHP_POST_MAX_SIZE="64M"; PHP_MAX_EXECUTION_TIME="180";
# -- PHP Settings for adjustment menu --
PHP_SETTINGS_TO_ADJUST=( "memory_limit" "post_max_size" "max_execution_time" "upload_max_filesize" "max_input_time" "max_input_vars" )
# -- PHP Extension Dir --
PHP_EXTENSIONS_DIR="/etc/php.d"
# -- System Paths and Configuration --
WORDPRESS_ROOT="/var/www/wordpress"; WP_CONFIG_PATH="${WORDPRESS_ROOT}/wp-config.php"; WP_CONTENT_DIR="${WORDPRESS_ROOT}/wp-content"; NGINX_CONF_DIR="/etc/nginx/conf.d"; PHP_INI_PATH="/etc/php.ini"; PHP_OPCACHE_CONF_PATH="${PHP_EXTENSIONS_DIR}/99-wp-optimized-opcache.ini"; PHP_APCU_CONF_PATH="${PHP_EXTENSIONS_DIR}/40-apcu.ini"; PHP_FPM_WWW_CONF="/etc/php-fpm.d/www.conf"; PHPMYADMIN_CONFIG="/etc/phpMyAdmin/config.inc.php"; PHPMYADMIN_TMP_DIR="/var/lib/phpmyadmin/tmp"; MARIADB_DATA_DIR="/var/lib/mysql"; MARIADB_OPT_CONF="/etc/my.cnf.d/99-wordpress-optimizations.cnf"; LOG_FILE="/var/log/lemp_wp_ms_optimized_apcu_install.log"; WP_CLI_PATH="/usr/local/bin/wp"
# -- Cookie Fix Variables --
COOKIE_FIX_CONFIG_LINE="define('COOKIE_DOMAIN', \$_SERVER['HTTP_HOST'] );"
COOKIE_FIX_FUNCTIONS_CODE=$(cat <<'EOT'
// START COOKIE FIX SCRIPT - Added by LEMP Script
if ( defined('SITECOOKIEPATH') && defined('COOKIEPATH') && SITECOOKIEPATH != COOKIEPATH && function_exists('setcookie') ) {
    // Use null coalescing operator for COOKIE_DOMAIN for PHP 7+ compatibility
    setcookie(defined('TEST_COOKIE') ? TEST_COOKIE : 'wordpress_test_cookie', 'WP Cookie check', 0, SITECOOKIEPATH, COOKIE_DOMAIN ?? '');
}
// END COOKIE FIX SCRIPT
EOT
); COOKIE_FIX_START_MARKER="// START COOKIE FIX SCRIPT"; COOKIE_FIX_END_MARKER="// END COOKIE FIX SCRIPT"

# --- Logging Function ---
log_message() { local type="$1" message="$2"; echo "[$(date '+%Y-%m-%d %H:%M:%S')] [${type}] ${message}" | tee -a "$LOG_FILE"; }

# --- Package Lists ---
PHP_PACKAGES=( php php-common php-fpm php-mysqlnd php-gd php-json php-mbstring php-xml php-curl php-zip php-intl php-imagick php-opcache php-soap php-bcmath php-sodium php-exif php-fileinfo php-pecl-apcu php-pecl-apcu-devel )
OTHER_PACKAGES=( nginx mariadb-server phpmyadmin curl wget ImageMagick )
CORE_UTILS=( policycoreutils policycoreutils-python-utils util-linux-user openssl dnf-utils )
CERTBOT_PACKAGES=( certbot python3-certbot-nginx )

# --- Helper function for command execution with check ---
run_command() {
    local description="$1"; shift; local suppress_output=false
    if [[ "$1" == "--suppress" ]]; then suppress_output=true; shift; fi
    log_message "INFO" "Starting: ${description}"; if output=$("$@" 2>&1); then
        log_message "INFO" "Success: ${description}"; [[ -n "$output" ]] && echo -e "$output" >> "$LOG_FILE";
        if [[ "$suppress_output" == false ]]; then echo "$output"; fi; return 0;
    else local exit_code=$?; log_message "ERROR" "Failed (Exit Code: $exit_code): ${description}."; log_message "ERROR" "Output:\n$output";
        if [[ "$suppress_output" == false ]]; then echo -e "${C_RED}---- ERROR Output ----${C_RESET}" >&2; echo -e "$output" >&2; echo -e "${C_RED}---------------------${C_RESET}" >&2; fi
        log_message "ERROR" "See log file: ${LOG_FILE}"; return $exit_code; fi
}
# --- Helper function for SQL commands ---
run_mysql_command() { local description="$1"; local sql_command="$2"; run_command "${description}" mysql -u root -p"${ACTIVE_DB_ROOT_PASSWORD}" -e "${sql_command}"; }
# --- Function to ask for CUSTOM WP admin credentials ---
get_custom_wp_credentials() {
    log_message "INFO" "Setting custom WP admin credentials..."; while [[ -z "$CUSTOM_WP_ADMIN_USER" ]]; do read -p "Enter desired WP ADMIN USERNAME: " CUSTOM_WP_ADMIN_USER; if [[ -z "$CUSTOM_WP_ADMIN_USER" ]]; then echo -e "${C_RED}ERROR: Empty username.${C_RESET}"; fi; done; local p1=""; local p2=""; while true; do read -s -p "Enter password for '${CUSTOM_WP_ADMIN_USER}': " p1; echo ""; read -s -p "Confirm password: " p2; echo ""; if [[ "$p1" == "$p2" ]]; then if [[ -z "$p1" ]]; then echo -e "${C_RED}ERROR: Empty password.${C_RESET}"; else CUSTOM_WP_ADMIN_PASSWORD="$p1"; log_message "INFO" "WP password set for '${CUSTOM_WP_ADMIN_USER}'."; break; fi; else echo -e "${C_RED}ERROR: Passwords do not match.${C_RESET}"; fi; done
}
# --- Function to ask for CUSTOM DB root password ---
get_custom_db_root_password() {
    log_message "INFO" "Setting custom DB root password..."; local p1=""; local p2=""; while true; do read -s -p "Enter desired DB 'root' PASSWORD: " p1; echo ""; read -s -p "Confirm password: " p2; echo ""; if [[ "$p1" == "$p2" ]]; then if [[ -z "$p1" ]]; then echo -e "${C_RED}ERROR: Empty password.${C_RESET}"; else CUSTOM_DB_ROOT_PASSWORD="$p1"; USE_CUSTOM_DB_ROOT_PASSWORD=true; log_message "INFO" "Custom DB password set."; break; fi; else echo -e "${C_RED}ERROR: Passwords do not match.${C_RESET}"; fi; done
}

# --- Functions ---
check_root() {
    > "$LOG_FILE"; chown "${CALLING_USER:-root}":"${CALLING_USER:-root}" "$LOG_FILE" || true; log_message "INFO" "Script started by $(whoami), invoked by ${CALLING_USER}"; if [[ $EUID -ne 0 ]]; then log_message "ERROR" "Root privileges required."; echo -e "${C_RED}ERROR: This script must be run as root (or with sudo).${C_RESET}"; exit 1; fi
}

# --- Welcome Screen Function ---
display_welcome_screen() {
    clear; echo -e "${HEADER_COLOR}${BORDER_DOUBLE}${C_RESET}"; printf "${HEADER_COLOR}== %-82s ==${C_RESET}\n" ""; printf "${HEADER_COLOR}== %-82s ==${C_RESET}\n" "    ${TITLE_COLOR}Fedora LEMP + WordPress Multisite Optimization Script${C_RESET}"; printf "${HEADER_COLOR}== %-82s ==${C_RESET}\n" "                  ${C_YELLOW}(With APCu Object Caching)${C_RESET}"; printf "${HEADER_COLOR}== %-82s ==${C_RESET}\n" ""; printf "${HEADER_COLOR}== %-82s ==${C_RESET}\n" "                    ${C_GREY}Author: H Dabo - 2025${C_RESET}"; echo -e "${HEADER_COLOR}${BORDER_DOUBLE}${C_RESET}"; echo ""; log_message "WARN" "🚨🚨🚨 Default DB Root PW option is INSECURE! Choose Custom! 🚨🚨🚨"; echo ""
}

# --- Helper function: Find active theme functions.php ---
get_active_theme_functions_path() {
    local functions_path=""
    if [[ ! -f "$WP_CLI_PATH" ]]; then log_message "ERROR" "WP-CLI not found at ${WP_CLI_PATH}."; echo -e "${C_RED}ERROR: WP-CLI not found!${C_RESET}"; return 1; fi
    if [[ ! -d "$WORDPRESS_ROOT" ]]; then log_message "ERROR" "WP directory ${WORDPRESS_ROOT} not found."; echo -e "${C_RED}ERROR: WP directory not found!${C_RESET}"; return 1; fi
    log_message "INFO" "Getting active theme via WP-CLI..."; local active_theme_slug
    if ! active_theme_slug=$(sudo -u nginx "$WP_CLI_PATH" theme list --status=active --field=name --path="$WORDPRESS_ROOT" --allow-root 2>>"$LOG_FILE"); then
        log_message "ERROR" "WP-CLI 'theme list' failed (Exit: $?). Check WP install and permissions."; echo -e "${C_RED}ERROR: Could not get active theme via WP-CLI.${C_RESET}"; return 1; fi
    if [[ -z "$active_theme_slug" ]]; then log_message "ERROR" "WP-CLI did not return an active theme slug."; echo -e "${C_RED}ERROR: No active theme found.${C_RESET}"; return 1; fi
    functions_path="${WP_CONTENT_DIR}/themes/${active_theme_slug}/functions.php"; log_message "INFO" "Theme: ${active_theme_slug}. Path: ${functions_path}"
    if [[ ! -f "$functions_path" ]]; then log_message "ERROR" "functions.php not found: ${functions_path}."; echo -e "${C_RED}ERROR: functions.php for theme '${active_theme_slug}' not found!${C_RESET}"; return 1; fi
    echo "$functions_path"; return 0
}

# --- Cookie Fix Function ---
apply_cookie_fixes() {
    log_message "INFO" "Starting apply cookie fixes..."
    echo -e "\n${C_MAGENTA}--- Apply WordPress Cookie Fix ---${C_RESET}"; local changes_made_count=0
    if [[ ! -f "$WP_CONFIG_PATH" ]]; then log_message "ERROR" "wp-config.php not found."; echo -e "${C_RED}ERROR: ${WP_CONFIG_PATH} not found!${C_RESET}";
    else if grep -q "define('COOKIE_DOMAIN'" "$WP_CONFIG_PATH"; then log_message "INFO" "COOKIE_DOMAIN already exists."; echo -e "${C_YELLOW}INFO:${C_RESET} COOKIE_DOMAIN definition already present in ${WP_CONFIG_PATH}.";
        else local backup_file_config="${WP_CONFIG_PATH}.bak_cookie_fix.$(date +%s)"; log_message "INFO" "Backup ${WP_CONFIG_PATH} -> ${backup_file_config}."; cp "$WP_CONFIG_PATH" "$backup_file_config" || { log_message "ERROR" "Backup failed."; echo -e "${C_RED}ERROR: Backup failed.${C_RESET}"; return 1; }; echo -e "Backup created: ${C_GREY}${backup_file_config}${C_RESET}";
             log_message "INFO" "Adding COOKIE_DOMAIN to ${WP_CONFIG_PATH}..."; if sed -i "/\/\* That's all, stop editing!/i ${COOKIE_FIX_CONFIG_LINE}" "$WP_CONFIG_PATH"; then log_message "INFO" "COOKIE_DOMAIN added."; echo -e "${C_GREEN}SUCCESS:${C_RESET} COOKIE_DOMAIN added to ${WP_CONFIG_PATH}."; ((changes_made_count++)); else log_message "ERROR" "Adding COOKIE_DOMAIN failed."; echo -e "${C_RED}ERROR: Could not add COOKIE_DOMAIN.${C_RESET}"; cp "$backup_file_config" "$WP_CONFIG_PATH"; fi; fi; fi; echo ""
    local functions_path; if ! functions_path=$(get_active_theme_functions_path); then return 1; fi
    if grep -Fq "$COOKIE_FIX_START_MARKER" "$functions_path"; then log_message "INFO" "Cookie fix marker already in ${functions_path}."; echo -e "${C_YELLOW}INFO:${C_RESET} Cookie fix code already seems present in ${functions_path}.";
    else local backup_file_func="${functions_path}.bak_cookie_fix.$(date +%s)"; log_message "INFO" "Backup ${functions_path} -> ${backup_file_func}."; cp "$functions_path" "$backup_file_func" || { log_message "ERROR" "Backup functions.php failed."; echo -e "${C_RED}ERROR: Backup functions.php failed.${C_RESET}"; return 1; }; echo -e "Backup created: ${C_GREY}${backup_file_func}${C_RESET}";
         log_message "INFO" "Adding cookie fix code to ${functions_path}..."; if echo -e "\n${COOKIE_FIX_FUNCTIONS_CODE}\n" >> "$functions_path"; then log_message "INFO" "Cookie fix code added."; echo -e "${C_GREEN}SUCCESS:${C_RESET} Cookie fix code added to ${functions_path}."; ((changes_made_count++)); else log_message "ERROR" "Adding cookie fix code failed."; echo -e "${C_RED}ERROR: Could not add cookie fix code.${C_RESET}"; cp "$backup_file_func" "$functions_path"; fi; fi; echo ""
    if [[ $changes_made_count -eq 0 ]]; then echo -e "${C_YELLOW}No changes applied (fixes might already be present).${C_RESET}"; else echo -e "${C_GREEN}Cookie fixes applied. Try logging in again (maybe clear browser cache/cookies).${C_RESET}"; fi
    read -p "Press Enter to return..."; log_message "INFO" "Apply cookie fixes finished."
}

# --- Undo Cookie Fix Function ---
revert_cookie_fixes() {
    log_message "INFO" "Starting revert cookie fixes..."; echo -e "\n${C_MAGENTA}--- Revert WordPress Cookie Fix ---${C_RESET}"; local changes_made_count=0
    if [[ ! -f "$WP_CONFIG_PATH" ]]; then log_message "ERROR" "wp-config.php not found."; echo -e "${C_RED}ERROR: ${WP_CONFIG_PATH} not found!${C_RESET}";
    else if grep -q "define('COOKIE_DOMAIN'" "$WP_CONFIG_PATH"; then local backup_file_config="${WP_CONFIG_PATH}.bak_cookie_revert.$(date +%s)"; log_message "INFO" "Backup ${WP_CONFIG_PATH} -> ${backup_file_config}."; cp "$WP_CONFIG_PATH" "$backup_file_config" || { log_message "ERROR" "Backup failed."; echo -e "${C_RED}ERROR: Backup failed.${C_RESET}"; return 1; }; echo -e "Backup created: ${C_GREY}${backup_file_config}${C_RESET}";
             log_message "INFO" "Removing COOKIE_DOMAIN from ${WP_CONFIG_PATH}..."; if sed -i "\|define('COOKIE_DOMAIN', \$_SERVER\['HTTP_HOST'\] );|d" "$WP_CONFIG_PATH"; then log_message "INFO" "COOKIE_DOMAIN removed."; echo -e "${C_GREEN}SUCCESS:${C_RESET} COOKIE_DOMAIN removed from ${WP_CONFIG_PATH}."; ((changes_made_count++)); else log_message "ERROR" "Removing COOKIE_DOMAIN failed."; echo -e "${C_RED}ERROR: Could not remove COOKIE_DOMAIN.${C_RESET}"; cp "$backup_file_config" "$WP_CONFIG_PATH"; fi
        else log_message "INFO" "COOKIE_DOMAIN not found."; echo -e "${C_YELLOW}INFO:${C_RESET} COOKIE_DOMAIN definition not found in ${WP_CONFIG_PATH}."; fi; fi; echo ""
    local functions_path; if ! functions_path=$(get_active_theme_functions_path); then return 1; fi
    if grep -Fq "$COOKIE_FIX_START_MARKER" "$functions_path"; then local backup_file_func="${functions_path}.bak_cookie_revert.$(date +%s)"; log_message "INFO" "Backup ${functions_path} -> ${backup_file_func}."; cp "$functions_path" "$backup_file_func" || { log_message "ERROR" "Backup failed."; echo -e "${C_RED}ERROR: Backup failed.${C_RESET}"; return 1; }; echo -e "Backup created: ${C_GREY}${backup_file_func}${C_RESET}";
         log_message "INFO" "Removing cookie fix block from ${functions_path}..."; if sed -i "\#${COOKIE_FIX_START_MARKER}#,\#${COOKIE_FIX_END_MARKER}#d" "$functions_path"; then log_message "INFO" "Cookie fix block removed."; echo -e "${C_GREEN}SUCCESS:${C_RESET} Cookie fix code block removed from ${functions_path}."; ((changes_made_count++)); else log_message "ERROR" "Removing cookie fix block failed."; echo -e "${C_RED}ERROR: Could not remove cookie fix block.${C_RESET}"; cp "$backup_file_func" "$functions_path"; fi
    else log_message "INFO" "Cookie fix marker not found."; echo -e "${C_YELLOW}INFO:${C_RESET} Cookie fix code not found in ${functions_path}."; fi; echo ""
    if [[ $changes_made_count -eq 0 ]]; then echo -e "${C_YELLOW}No changes reverted.${C_RESET}"; else echo -e "${C_GREEN}Cookie fixes reverted.${C_RESET}"; fi
    read -p "Press Enter to return..."; log_message "INFO" "Revert cookie fixes finished."
}

# --- Multisite Toggle Function ---
toggle_multisite() {
    log_message "INFO" "Start Multisite toggle..."
    echo -e "\n${C_MAGENTA}--- Toggle WordPress Multisite On/Off ---${C_RESET}"
    if [[ ! -f "$WP_CONFIG_PATH" ]]; then log_message "ERROR" "wp-config.php not found."; echo -e "${C_RED}ERROR: ${WP_CONFIG_PATH} not found!${C_RESET}"; read -p "..."; return 1; fi
    local current_status="unknown"; local multisite_line; multisite_line=$(grep -E "^[[:space:]]*define\( *'MULTISITE' *,.* \);" "$WP_CONFIG_PATH")
    if [[ -z "$multisite_line" ]]; then current_status="disabled"; echo -e "${C_YELLOW}INFO:${C_RESET} No 'MULTISITE' definition found -> Disabled."; log_message "INFO" "MULTISITE not found, assuming disabled."
    elif echo "$multisite_line" | grep -q "true"; then current_status="enabled"; echo -e "${C_YELLOW}INFO:${C_RESET} Multisite is currently ${C_GREEN}ENABLED${C_RESET}."; log_message "INFO" "MULTISITE is true."
    else current_status="disabled"; echo -e "${C_YELLOW}INFO:${C_RESET} Multisite is currently ${C_RED}DISABLED${C_RESET}."; log_message "INFO" "MULTISITE is false/unknown."; fi
    local action; local new_ms_value; local new_subdomain_value
    if [[ "$current_status" == "enabled" ]]; then action="DISABLE"; new_ms_value="false"; new_subdomain_value="false"; else action="ENABLE"; new_ms_value="true"; new_subdomain_value="true"; fi
    read -p "Do you want to ${action} Multisite now? [y/N]: " confirm
    if [[ ! "$confirm" =~ ^[Yy]$ ]]; then echo "Action canceled."; log_message "INFO" "Multisite toggle canceled."; read -p "..."; return 0; fi
    local backup_file_config="${WP_CONFIG_PATH}.bak_ms_toggle.$(date +%s)"; log_message "INFO" "Backup ${WP_CONFIG_PATH} -> ${backup_file_config}."; cp "$WP_CONFIG_PATH" "$backup_file_config" || { log_message "ERROR" "Backup failed."; echo -e "${C_RED}ERROR: Backup failed!${C_RESET}"; read -p "..."; return 1; }; echo -e "Backup created: ${C_GREY}${backup_file_config}${C_RESET}"
    local sed_success=true; log_message "INFO" "Setting MULTISITE -> ${new_ms_value}..."; echo -e "Adjusting ${C_CYAN}MULTISITE${C_RESET} -> ${new_ms_value}..."
    if grep -q "define( *'MULTISITE' *," "$WP_CONFIG_PATH"; then if ! sed -i "s|^[[:space:];]*define( *'MULTISITE' *,.*);|define( 'MULTISITE', ${new_ms_value} );|" "$WP_CONFIG_PATH"; then log_message "ERROR" "Sed modify MULTISITE failed."; echo -e "${C_RED}ERROR.${C_RESET}"; sed_success=false; fi
    elif [[ "$new_ms_value" == "true" ]]; then log_message "INFO" "Adding MULTISITE..."; local stop_editing_line="/* That's all, stop editing!"; if ! sed -i "/$(echo "$stop_editing_line" | sed 's:[/*]:\\&:g')/i define( 'MULTISITE', true );" "$WP_CONFIG_PATH"; then log_message "ERROR" "Sed add MULTISITE failed."; echo -e "${C_RED}ERROR.${C_RESET}"; sed_success=false; fi; fi
    if $sed_success; then log_message "INFO" "Setting SUBDOMAIN_INSTALL -> ${new_subdomain_value}..."; echo -e "Adjusting ${C_CYAN}SUBDOMAIN_INSTALL${C_RESET} -> ${new_subdomain_value}..."
         if grep -q "define( *'SUBDOMAIN_INSTALL' *," "$WP_CONFIG_PATH"; then if ! sed -i "s|^[[:space:];]*define( *'SUBDOMAIN_INSTALL' *,.*);|define( 'SUBDOMAIN_INSTALL', ${new_subdomain_value} );|" "$WP_CONFIG_PATH"; then log_message "ERROR" "Sed modify SUBDOMAIN_INSTALL failed."; echo -e "${C_RED}ERROR.${C_RESET}"; sed_success=false; fi
         elif [[ "$new_ms_value" == "true" ]]; then log_message "INFO" "Adding SUBDOMAIN_INSTALL..."; local stop_editing_line="/* That's all, stop editing!"; if ! sed -i "/$(echo "$stop_editing_line" | sed 's:[/*]:\\&:g')/i define( 'SUBDOMAIN_INSTALL', true );" "$WP_CONFIG_PATH"; then log_message "ERROR" "Sed add SUBDOMAIN_INSTALL failed."; echo -e "${C_RED}ERROR.${C_RESET}"; sed_success=false; fi; fi; fi
    if $sed_success; then log_message "INFO" "Multisite status changed to ${new_ms_value}."; echo -e "${C_GREEN}SUCCESS:${C_RESET} Multisite is now set to ${action}D."; echo -e "${C_YELLOW}Note:${C_RESET} Further steps (e.g., Nginx/htaccess, WP Network Setup) might be required.";
    else log_message "ERROR" "Multisite change failed. Restoring backup."; echo -e "${C_RED}ERROR: Could not modify wp-config.php correctly. Backup restored.${C_RESET}"; cp "$backup_file_config" "$WP_CONFIG_PATH"; fi
    read -p "Press Enter to return..."; log_message "INFO" "Multisite toggle finished."
}


# --- Service Restart Function ---
restart_services() {
    log_message "INFO" "Starting service restart..."
    echo -e "\n${C_YELLOW}--- Restart Services ---${C_RESET}"; local all_restarted=true
    echo -e "Restarting ${C_CYAN}Nginx${C_RESET}..."; if ! run_command "Restart Nginx" systemctl restart nginx.service; then echo -e "${C_RED} FAILED.${C_RESET}"; echo -e "${C_YELLOW} Diagnostics: status/journalctl${C_RESET}"; all_restarted=false; fi; sleep 0.5
    echo -e "Restarting ${C_CYAN}MariaDB${C_RESET}..."; if ! run_command "Restart MariaDB" systemctl restart mariadb.service; then echo -e "${C_RED} FAILED.${C_RESET}"; echo -e "${C_YELLOW} Diagnostics: status/journalctl${C_RESET}"; all_restarted=false; fi; sleep 0.5
    echo -e "Restarting ${C_CYAN}PHP-FPM${C_RESET} (${C_GREY}clears APCu/OPcache${C_RESET})..."; if ! run_command "Restart PHP-FPM" systemctl restart php-fpm.service; then echo -e "${C_RED} FAILED.${C_RESET}"; echo -e "${C_YELLOW} Diagnostics: status/journalctl${C_RESET}"; all_restarted=false; else log_message "INFO" "PHP-FPM OK; Cache cleared."; fi; sleep 0.5
    echo ""; if [[ "$all_restarted" == true ]]; then echo -e "${C_GREEN}All services restarted successfully.${C_RESET}"; log_message "INFO" "Services restart OK."; else echo -e "${C_YELLOW}Not all services could be restarted successfully.${C_RESET}"; log_message "WARN" "Not all services restarted OK."; fi
    echo ""; read -p "Press Enter to return..."; log_message "INFO" "Service restart finished."
}


# --- Version Information Function ---
display_versions() {
    log_message "INFO" "Starting version display..."
    echo -e "\n${C_CYAN}--- Installed Versions ---${C_RESET}"
    echo -en "${C_WHITE}Nginx:${C_RESET}   "; if nginx_version=$(nginx -v 2>&1); then echo -e "${C_GREEN}${nginx_version}${C_RESET}"; log_message "INFO" "Nginx: ${nginx_version}"; else echo -e "${C_RED}Error.${C_RESET}"; log_message "ERROR" "Nginx version FAILED."; fi
    echo -en "${C_WHITE}MariaDB:${C_RESET} "; if mariadb_version=$(mysql --version); then echo -e "${C_GREEN}${mariadb_version}${C_RESET}"; log_message "INFO" "MariaDB: ${mariadb_version}"; else echo -e "${C_RED}Error.${C_RESET}"; log_message "ERROR" "MariaDB version FAILED."; fi
    echo -en "${C_WHITE}PHP:${C_RESET}     "; if php_version=$(php -v 2>/dev/null | head -n 1); then echo -e "${C_GREEN}${php_version}${C_RESET}"; log_message "INFO" "PHP: ${php_version}"; else echo -e "${C_RED}Error.${C_RESET}"; log_message "ERROR" "PHP version FAILED."; fi
    echo ""; read -p "Press Enter to return..."; log_message "INFO" "Version display finished."
}

# --- PHP Settings Adjustment Function ---
adjust_php_settings() {
    log_message "INFO" "Starting PHP settings adjustment..."
    echo -e "\n${C_MAGENTA}--- Adjust PHP Settings (${PHP_INI_PATH}) ---${C_RESET}"
    if [[ ! -f "$PHP_INI_PATH" ]]; then log_message "ERROR" "${PHP_INI_PATH} not found."; echo -e "${C_RED}ERROR: ${PHP_INI_PATH} not found!${C_RESET}"; read -p "..."; return 1; fi
    local backup_file="${PHP_INI_PATH}.bak.$(date +%s)"; log_message "INFO" "Backup -> ${backup_file}"; cp "$PHP_INI_PATH" "$backup_file" || { log_message "ERROR" "Backup failed."; echo -e "${C_RED}ERROR: Backup failed!${C_RESET}"; read -p "..."; return 1; }
    local setting_changed=false; echo -e "Backup created: ${C_GREY}${backup_file}${C_RESET}"; echo -e "Adjust settings (Press ${C_GREEN}Enter${C_RESET} to keep current value):"; echo ""
    for setting_name in "${PHP_SETTINGS_TO_ADJUST[@]}"; do current_value=$(grep -Ei "^[; ]*${setting_name}[ ]*=" "$PHP_INI_PATH" | tail -n 1 | sed -E 's/^[; ]*[^=]+=[ ]*//; s/[; ].*$//'); [[ -z "$current_value" ]] && current_value="<empty>"; echo -e "${C_WHITE}${setting_name}:${C_RESET} (Current: ${C_YELLOW}${current_value}${C_RESET})"; read -p "  New value: " new_value
        if [[ -n "$new_value" ]]; then sed -i -E "/^[; ]*${setting_name}[ ]*=/Id" "$PHP_INI_PATH"; if grep -q '^\s*\[PHP\]' "$PHP_INI_PATH"; then sed -i "/^\s*\[PHP\]/a ${setting_name} = ${new_value}" "$PHP_INI_PATH"; else echo "${setting_name} = ${new_value}" >> "$PHP_INI_PATH"; fi; log_message "INFO" "'${setting_name}' -> '${new_value}'."; echo -e "  -> ${C_GREEN}Set to: ${new_value}${C_RESET}"; setting_changed=true; else echo -e "  -> Kept current value." ; fi; echo "" ; done
    if [[ "$setting_changed" == true ]]; then echo -e "${C_YELLOW}Settings saved to ${PHP_INI_PATH}.${C_RESET}"; echo -e "${C_YELLOW}Restarting PHP-FPM to apply changes...${C_RESET}"; if run_command "Restart PHP-FPM" systemctl restart php-fpm; then echo -e "${C_GREEN}OK.${C_RESET}"; else echo -e "${C_RED}FAILED!${C_RESET}"; echo -e "${C_YELLOW}Check status/logs.${C_RESET}"; fi; else echo -e "No changes made."; log_message "INFO" "No PHP settings adjusted by user."; fi
    echo ""; read -p "Press Enter to return..."; log_message "INFO" "Adjust PHP settings finished."
}


# --- PHP Extension Management Function ---
manage_php_extensions() {
    log_message "INFO" "Starting PHP extension management..."
    echo -e "\n${C_MAGENTA}--- Manage PHP Extensions (${PHP_EXTENSIONS_DIR}) ---${C_RESET}"
    if [[ ! -d "$PHP_EXTENSIONS_DIR" ]]; then log_message "ERROR" "${PHP_EXTENSIONS_DIR} not found."; echo -e "${C_RED}ERROR: Directory ${PHP_EXTENSIONS_DIR} not found!${C_RESET}"; read -p "..."; return 1; fi
    local changes_made=false; local loaded_modules; loaded_modules=$(php -m 2>/dev/null | grep -v '\[PHP Modules\]' | grep -v '\[Zend Modules\]' | tr '[:upper:]' '[:lower:]' | sort | uniq)
    if [[ -z "$loaded_modules" ]]; then log_message "ERROR" "'php -m' failed."; echo -e "${C_RED}ERROR: Could not execute 'php -m'.${C_RESET}"; read -p "..."; return 1; fi; log_message "INFO" "Loaded modules:\n${loaded_modules}"
    while true; do clear; echo -e "\n${C_MAGENTA}--- Manage PHP Extensions (${PHP_EXTENSIONS_DIR}) ---${C_RESET}"; declare -a ini_files; declare -a statuses; declare -a display_names; declare -a toggleable_flags; local counter=1
        echo -e "\n${C_WHITE}Found .ini Files & Status:${C_RESET}"; echo -e "${C_GREY}${BORDER_SINGLE}${C_RESET}"
        while IFS= read -r file; do local filename=$(basename "$file"); local clean_display_name=$(echo "$filename" | sed -E 's/^[0-9]+-//; s/\.ini$//'); local module_name_lc=$(echo "$clean_display_name" | tr '[:upper:]' '[:lower:]'); local current_status="Unknown"; local status_color=$C_YELLOW; local status_symbol="[?]"; local toggleable="no"; local has_active_ext_line=false; local has_inactive_ext_line=false
            if grep -Eq '^[[:space:]]*extension=[^;]*\.so' "$file"; then has_active_ext_line=true; fi; if grep -Eq '^[[:space:]]*;+[[:space:]]*extension=[^;]*\.so' "$file"; then has_inactive_ext_line=true; fi
            if echo "${loaded_modules}" | grep -qw "$module_name_lc"; then current_status="Enabled"; status_color=$C_GREEN; status_symbol="[${C_GREEN}✓${C_RESET}]"; if $has_active_ext_line; then toggleable="yes"; fi; if ! $has_active_ext_line && ! $has_inactive_ext_line; then current_status="Enabled ${C_GREY}(Auto)${status_color}"; fi
            else if $has_inactive_ext_line; then current_status="Disabled"; status_color=$C_RED; status_symbol="[ ]"; toggleable="yes"; else current_status="Unknown"; status_color=$C_YELLOW; status_symbol="[${C_YELLOW}?${C_RESET}]"; toggleable="no"; fi; fi
            if grep -Eq '^[[:space:]]*;*[[:space:]]*zend_extension=' "$file"; then if echo "$filename" | grep -q 'opcache'; then current_status="Enabled ${C_GREY}(Zend)${C_GREEN}"; status_color=$C_GREEN; status_symbol="[${C_GREEN}Z${C_RESET}]"; else current_status="Unknown ${C_GREY}(Zend)${C_YELLOW}"; status_color=$C_YELLOW; status_symbol="[${C_YELLOW}Z${C_RESET}]"; fi; toggleable="no"; fi
            local toggle_indicator=" "; if [[ "$toggleable" == "yes" ]]; then toggle_indicator="${C_YELLOW}*${C_RESET}"; fi
            printf " %-4s %-3s %-20s %-20s %-1s %s\n" "$counter." "$status_symbol" "$clean_display_name" "(${status_color}${current_status}${C_RESET})" "$toggle_indicator" "${C_GREY}${filename}${C_RESET}"
            ini_files+=("$file"); statuses+=("$current_status"); display_names+=("$clean_display_name"); toggleable_flags+=("$toggleable"); ((counter++)); done < <(find "$PHP_EXTENSIONS_DIR" -maxdepth 1 -type f -name '*.ini' | sort); echo -e "${C_GREY}${BORDER_SINGLE}${C_RESET}"
        local num_extensions=${#ini_files[@]}; if [[ $num_extensions -eq 0 ]]; then echo -e "\n${C_YELLOW}No .ini files found.${C_RESET}"; break; fi
        echo -e "\nEnter number to ${C_YELLOW}toggle${C_RESET} status (only with ${C_YELLOW}*${C_RESET})."; echo -e "Enter '${C_GREEN}0${C_RESET}' to Save & Exit."; echo -e "Enter '${C_RED}q${C_RESET}' to Exit without saving."
        read -p "$(echo -e ${PROMPT_COLOR}"Your choice [1-${num_extensions}, 0, q]: "${C_RESET})" choice
        case $choice in q|Q) echo "Exiting without saving."; log_message "INFO" "PHP ext mgmt aborted."; break ;; 0) echo "Saving and exiting."; if [[ "$changes_made" == true ]]; then echo -e "${C_YELLOW}Restarting PHP-FPM...${C_RESET}"; if run_command "Restart PHP-FPM" systemctl restart php-fpm; then echo -e "${C_GREEN}OK.${C_RESET}"; else echo -e "${C_RED}ERROR!${C_RESET}"; echo -e "${C_YELLOW}Check status/logs.${C_RESET}"; fi; else echo "No changes made."; fi; log_message "INFO" "PHP ext mgmt finished."; break ;; *)
            if [[ "$choice" =~ ^[0-9]+$ ]] && [[ "$choice" -ge 1 ]] && [[ "$choice" -le $num_extensions ]]; then local index=$((choice - 1)); local target_file="${ini_files[$index]}"; local current_status_raw="${statuses[$index]}"; local display_name="${display_names[$index]}"; local toggleable="${toggleable_flags[$index]}"; local base_status; if [[ $current_status_raw == *"Enabled"* ]]; then base_status="Enabled"; elif [[ $current_status_raw == *"Disabled"* ]]; then base_status="Disabled"; else base_status="Unknown"; fi
                if [[ "$toggleable" != "yes" ]]; then echo -e "\n${C_YELLOW}Cannot toggle status for '${display_name}'.${C_RESET}"; echo -e "${C_GREY}(Not toggleable via this menu - possibly built-in, Zend, or no 'extension=' line).${C_RESET}"; sleep 3; continue; fi
                local backup_file_ext="${target_file}.bak_ext.$(date +%s)"; log_message "INFO" "Backup ${target_file} -> ${backup_file_ext}"; cp "$target_file" "$backup_file_ext" || { log_message "ERROR" "Backup FAILED."; echo -e "\n${C_RED}ERROR: Backup failed!${C_RESET}"; sleep 3; continue; }
                echo -e "Backup created: ${C_GREY}${backup_file_ext}${C_RESET}"; echo -e "Toggling status for ${C_BLUE}${display_name}${C_RESET}..."
                if [[ "$base_status" == "Enabled" ]]; then log_message "INFO" "Disabling in ${target_file}"; if sed -i -E '0,/^[[:space:]]*extension=.*\.so/{s|^([[:space:]]*)(extension=.*\.so.*)|;\1\2|}' "$target_file"; then echo -e " -> Now ${C_RED}disabled${C_RESET}."; changes_made=true; else echo -e " ${C_RED}ERROR disabling.${C_RESET}"; log_message "ERROR" "sed disable FAILED."; fi
                else log_message "INFO" "Enabling in ${target_file}"; if sed -i -E '0,/^[[:space:]]*;+[[:space:]]*extension=.*\.so/{ s/^[[:space:]]*;+[[:space:]]*// }' "$target_file"; then if grep -Eq '^[[:space:]]*extension=.*\.so' "$target_file"; then echo -e " -> Now ${C_GREEN}enabled${C_RESET}."; changes_made=true; else echo -e " ${C_RED}ERROR: Could not uncomment.${C_RESET}"; log_message "ERROR" "sed uncomment FAILED."; cp "$backup_file_ext" "$target_file"; echo -e " -> Backup restored."; fi; else echo -e " ${C_RED}ERROR enabling (sed error).${C_RESET}"; log_message "ERROR" "sed enable FAILED."; cp "$backup_file_ext" "$target_file"; echo -e " -> Backup restored."; fi; fi; sleep 1.5
            else echo -e "\n${C_RED}Invalid choice '${choice}'.${C_RESET}"; sleep 2; fi;;
        esac; done; echo ""
}


# --- Health Check Function ---
health_check() {
    log_message "INFO" "Starting Health Check..."
    echo -e "\n${C_BLUE}--- Starting Health Check ---${C_RESET}"; local all_ok=true; local issues_found=0; local services=("nginx" "mariadb" "php-fpm")
    echo -n "[Check] Nginx log dir: "; if [ ! -d "/var/log/nginx" ]; then echo -e "${C_YELLOW}MISSING.${C_RESET}"; log_message "WARN" "Nginx log dir MISSING."; echo -e "${C_YELLOW} -> Creating...${C_RESET}"; if run_command "Create /var/log/nginx" mkdir -p /var/log/nginx; then echo -e "${C_GREEN}OK.${C_RESET}"; log_message "INFO" "Dir OK."; else echo -e "${C_RED}FAIL.${C_RESET}"; log_message "ERROR" "Dir FAIL."; all_ok=false; issues_found=$((issues_found + 1)); fi; else echo -e "${C_GREEN}OK${C_RESET}"; log_message "INFO" "Nginx log dir OK."; fi
    echo -n "[Check] PHP-FPM log dir: "; if [ ! -d "/var/log/php-fpm" ]; then echo -e "${C_YELLOW}MISSING.${C_RESET}"; log_message "WARN" "PHP-FPM log dir MISSING."; echo -e "${C_YELLOW} -> Creating...${C_RESET}"; if run_command "Create /var/log/php-fpm" mkdir -p /var/log/php-fpm; then echo -e "${C_GREEN}OK.${C_RESET}"; log_message "INFO" "Dir OK."; local fpm_user="nginx"; run_command "Perms /var/log/php-fpm" chown "${fpm_user}:${fpm_user}" /var/log/php-fpm || log_message "WARN" "Perms FAIL."; else echo -e "${C_RED}FAIL.${C_RESET}"; log_message "ERROR" "Dir FAIL."; all_ok=false; issues_found=$((issues_found + 1)); fi; else echo -e "${C_GREEN}OK${C_RESET}"; log_message "INFO" "PHP-FPM log dir OK."; fi
    # Check services
    for service in "${services[@]}"; do
        local service_name="${service}.service"
        echo -n "[Service] ${service_name}: Enabled? "
        if systemctl is-enabled --quiet "${service_name}"; then echo -e "${C_GREEN}Yes${C_RESET}"; log_message "INFO" "${service_name} enabled."
        else echo -e "${C_YELLOW}No${C_RESET}"; log_message "WARN" "${service_name} NOT enabled."; fi
        echo -n "[Service] ${service_name}: Active? "
        if systemctl is-active --quiet "${service_name}"; then echo -e "${C_GREEN}Yes${C_RESET}"; log_message "INFO" "${service_name} active."
        else echo -e "${C_RED}No${C_RESET}"; log_message "WARN" "${service_name} NOT active."
            local can_attempt_restart=true; if [[ "$service" == "nginx" && ! -d "/var/log/nginx" ]]; then can_attempt_restart=false; log_message "WARN" "Restart ${service_name} skip: log dir missing."; elif [[ "$service" == "php-fpm" && ! -d "/var/log/php-fpm" ]]; then can_attempt_restart=false; log_message "WARN" "Restart ${service_name} skip: log dir missing."; fi
            if [[ "$can_attempt_restart" == true ]]; then echo -e "${C_YELLOW} -> Restarting...${C_RESET}"; if run_command "Restart ${service_name}" --suppress systemctl restart "${service_name}"; then echo -e "${C_GREEN}OK.${C_RESET}"; log_message "INFO" "${service_name} restart OK."
                else echo -e "${C_RED}FAIL.${C_RESET}"; log_message "ERROR" "${service_name} restart FAILED."; all_ok=false; issues_found=$((issues_found + 1)); echo -e "${C_YELLOW}  Diagnostics: ${C_CYAN}systemctl status ${service_name} && journalctl -xeu ${service_name}${C_RESET}"; fi
            else all_ok=false; if [[ $can_attempt_restart == false ]]; then : else issues_found=$((issues_found + 1)); fi; echo -e "${C_YELLOW} -> Restart skipped.${C_RESET}"; fi
        fi
    done
    echo -n "[Config] Nginx syntax: "; if run_command "Nginx test" --suppress nginx -t; then echo -e "${C_GREEN}OK${C_RESET}"; log_message "INFO" "Nginx config OK."; else echo -e "${C_RED}FAIL${C_RESET}"; log_message "ERROR" "Nginx config FAILED."; echo -e "${C_RED} -> Error! Check: ${C_CYAN}sudo nginx -t${C_RESET}"; all_ok=false; issues_found=$((issues_found + 1)); fi
    echo -n "[Runtime] PHP CLI: "; if run_command "PHP check" --suppress php -v; then php_version_output=$(php -v 2>/dev/null | head -n 1); echo -e "${C_GREEN}OK (${php_version_output})${C_RESET}"; log_message "INFO" "PHP CLI OK (${php_version_output})."; else echo -e "${C_RED}FAIL${C_RESET}"; log_message "ERROR" "PHP CLI FAIL."; echo -e "${C_RED} -> Error!${C_RESET}"; all_ok=false; issues_found=$((issues_found + 1)); fi
    echo -n "[WordPress] Dir (${WORDPRESS_ROOT}): "; if [[ -d "$WORDPRESS_ROOT" ]] && [[ -n "$(ls -A $WORDPRESS_ROOT)" ]]; then echo -e "${C_GREEN}OK${C_RESET}"; log_message "INFO" "WP dir OK."; echo -n "[WordPress] WP-CLI Check: "; if [[ -f "$WP_CLI_PATH" ]]; then local wp_cli_user="nginx"; if ! id "$wp_cli_user" &>/dev/null; then wp_cli_user="root"; fi; if run_command "WP-CLI core check" --suppress sudo -u "$wp_cli_user" "$WP_CLI_PATH" core is-installed --path="$WORDPRESS_ROOT" --allow-root; then echo -e "${C_GREEN}OK${C_RESET}"; log_message "INFO" "WP-CLI check OK."; if [[ -n "${WP_SITE_URL:-}" ]]; then echo -e "[WordPress] ${C_BLUE}Admin URL:${C_RESET} ${C_CYAN}${WP_SITE_URL}/wp-admin/${C_RESET}"; else echo -e "[WordPress] ${C_YELLOW}Admin URL: N/A${C_RESET}"; log_message "WARN" "WP_SITE_URL empty."; fi; else echo -e "${C_RED}FAIL${C_RESET}"; log_message "ERROR" "WP-CLI check FAILED."; echo -e "${C_RED} -> Error! Check: ${C_CYAN}sudo -u ${wp_cli_user} ${WP_CLI_PATH} core is-installed --path=${WORDPRESS_ROOT} --allow-root --debug${C_RESET}"; all_ok=false; issues_found=$((issues_found + 1)); fi; else echo -e "${C_YELLOW}MISSING${C_RESET}"; log_message "WARN" "WP-CLI not found."; fi; else echo -e "${C_RED}FAIL${C_RESET}"; log_message "ERROR" "WP dir not found/empty."; echo -e "${C_RED} -> Error!${C_RESET}"; all_ok=false; issues_found=$((issues_found + 1)); fi
    echo -e "\n${C_BLUE}--- Health Check Finished ---${C_RESET}"; if [[ "$all_ok" == true ]]; then echo -e "${C_GREEN}All checks seem OK.${C_RESET}"; log_message "INFO" "Health Check: OK."; else if [[ $issues_found -eq 0 && "$all_ok" == false ]]; then issues_found=1; log_message "WARN" "Health: issues=0, all_ok=false"; fi; if [[ $issues_found -gt 0 ]]; then echo -e "${C_YELLOW}${issues_found} issue(s) found.${C_RESET}"; log_message "WARN" "Health Check: ${issues_found} issue(s)."; else echo -e "${C_YELLOW}Issues detected & possibly auto-fixed.${C_RESET}"; log_message "WARN" "Health Check: Issues possibly fixed."; fi; fi
    echo ""; read -p "Press Enter to return..."
}

# --- MariaDB Optimization Function ---
optimize_mariadb_config() {
    log_message "INFO" "Optimizing MariaDB config (${MARIADB_OPT_CONF})..."; local INNODB_BUFFER_POOL="512M"; local INNODB_LOG_FILE_SIZE="256M"; cat <<EOF > "$MARIADB_OPT_CONF"; # WordPress Optimized MariaDB settings by script\n[mysqld]\nquery_cache_type = 0; query_cache_size = 0\ninnodb_buffer_pool_size = ${INNODB_BUFFER_POOL}\ninnodb_log_file_size = ${INNODB_LOG_FILE_SIZE}\ninnodb_flush_method = O_DIRECT\nEOF
    run_command "MariaDB opt config perms" chown root:root "$MARIADB_OPT_CONF" && chmod 644 "$MARIADB_OPT_CONF" || return 1; log_message "INFO" "MariaDB opt config created."; run_command "Restart MariaDB" systemctl restart mariadb || { log_message "ERROR" "MariaDB restart FAILED."; return 1; }; log_message "INFO" "MariaDB restarted OK."; return 0
}

# --- Database Setup Function ---
setup_database() {
    log_message "INFO" "Starting DB setup..."; sleep 2; local target_password; local password_source_msg; if [[ "$USE_CUSTOM_DB_ROOT_PASSWORD" == true ]]; then target_password="$CUSTOM_DB_ROOT_PASSWORD"; password_source_msg="custom password"; else target_password="$MARIADB_ROOT_PASSWORD_DEFAULT"; password_source_msg="'root' (INSECURE!)"; fi; ACTIVE_DB_ROOT_PASSWORD="$target_password"; log_message "INFO" "Setting DB root pw: ${password_source_msg}"; if ! mysqladmin -u root password "${target_password}" >> "$LOG_FILE" 2>&1 ; then log_message "WARN" "Initial root pw set failed, trying ALTER..."; if ! mysql -u root -e "ALTER USER 'root'@'localhost' IDENTIFIED BY '${target_password}'; FLUSH PRIVILEGES;" >> "$LOG_FILE" 2>&1 && ! mysql -u root -p"${MARIADB_ROOT_PASSWORD_DEFAULT}" -e "ALTER USER 'root'@'localhost' IDENTIFIED BY '${target_password}'; FLUSH PRIVILEGES;" >> "$LOG_FILE" 2>&1; then if ! run_command "DB root pw set (attempt 3)" mysql -u root -p"${target_password}" -e "ALTER USER 'root'@'localhost' IDENTIFIED BY '${target_password}'; FLUSH PRIVILEGES;"; then log_message "ERROR" "DB root pw set FAILED."; return 1; fi; fi; fi; log_message "INFO" "DB root pw OK."; run_mysql_command "Create WP DB" "CREATE DATABASE IF NOT EXISTS \`${WORDPRESS_DB_NAME}\` DEFAULT CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;" || return 1; log_message "INFO" "Create WP DB user '${WORDPRESS_DB_USER}'..."; run_mysql_command "Create WP DB user" "CREATE USER IF NOT EXISTS '${WORDPRESS_DB_USER}'@'localhost' IDENTIFIED BY '${WORDPRESS_DB_PASSWORD}';" || return 1; run_mysql_command "Grant WP DB privileges" "GRANT ALL PRIVILEGES ON \`${WORDPRESS_DB_NAME}\`.* TO '${WORDPRESS_DB_USER}'@'localhost';" || return 1; run_mysql_command "Flush privileges" "FLUSH PRIVILEGES;" || return 1; log_message "INFO" "DB config OK."
}
# --- WP-CLI Installation Function ---
install_wp_cli() {
    log_message "INFO" "Installing/Updating WP-CLI..."; if [ -f "$WP_CLI_PATH" ]; then log_message "INFO" "WP-CLI > Updating..."; chown root:root "$WP_CLI_PATH" || true; run_command "Update WP-CLI" "$WP_CLI_PATH" cli update --yes --allow-root || log_message "WARN" "WP-CLI update FAILED."; else run_command "Download WP-CLI" curl -fLo /tmp/wp-cli.phar https://raw.githubusercontent.com/wp-cli/builds/gh-pages/phar/wp-cli.phar || return 1; run_command "WP-CLI chmod" chmod +x /tmp/wp-cli.phar || return 1; run_command "WP-CLI move" mv /tmp/wp-cli.phar "$WP_CLI_PATH" || return 1; fi; run_command "WP-CLI check" "$WP_CLI_PATH" --info --allow-root || return 1; log_message "INFO" "WP-CLI OK."
}
# --- PHP & OPcache Optimization Function ---
optimize_php_config() {
    log_message "INFO" "Optimizing PHP config (${PHP_INI_PATH})..."; if [[ ! -f "$PHP_INI_PATH" ]]; then log_message "ERROR" "${PHP_INI_PATH} not found!"; return 1; fi; cp "$PHP_INI_PATH" "${PHP_INI_PATH}.bak.$(date +%s)"; run_command "PHP: memory_limit" sed -i "s/^\s*memory_limit\s*=.*/memory_limit = ${PHP_MEMORY_LIMIT}/" "$PHP_INI_PATH" || log_message "WARN" "...FAILED."; run_command "PHP: upload_max_filesize" sed -i "s/^\s*upload_max_filesize\s*=.*/upload_max_filesize = ${PHP_UPLOAD_MAX_FILESIZE}/" "$PHP_INI_PATH" || log_message "WARN" "...FAILED."; run_command "PHP: post_max_size" sed -i "s/^\s*post_max_size\s*=.*/post_max_size = ${PHP_POST_MAX_SIZE}/" "$PHP_INI_PATH" || log_message "WARN" "...FAILED."; run_command "PHP: max_execution_time" sed -i "s/^\s*max_execution_time\s*=.*/max_execution_time = ${PHP_MAX_EXECUTION_TIME}/" "$PHP_INI_PATH" || log_message "WARN" "...FAILED."
    log_message "INFO" "OPcache config (${PHP_OPCACHE_CONF_PATH})..."; cat <<EOF > "$PHP_OPCACHE_CONF_PATH"; ; Optimized OPcache by script\nopcache.enable=1; opcache.enable_cli=1; opcache.memory_consumption=192\nopcache.interned_strings_buffer=16; opcache.max_accelerated_files=12000\nopcache.revalidate_freq=2; opcache.validate_timestamps=1; opcache.save_comments=1\nEOF; run_command "Perms OPcache" chown root:root "$PHP_OPCACHE_CONF_PATH" && chmod 644 "$PHP_OPCACHE_CONF_PATH" || log_message "WARN" "...FAILED.";
    log_message "INFO" "APCu config (${PHP_APCU_CONF_PATH})..."; if [[ ! -f "$PHP_APCU_CONF_PATH" ]] || ! grep -q "apc.enabled" "$PHP_APCU_CONF_PATH"; then if [[ ! -f "$PHP_APCU_CONF_PATH" ]]; then cat <<EOF > "$PHP_APCU_CONF_PATH"; ; Basic APCu by script\nextension=apcu.so\napc.enabled=1; apc.shm_size=128M; apc.enable_cli=1\nEOF; run_command "Perms APCu" chown root:root "$PHP_APCU_CONF_PATH" && chmod 644 "$PHP_APCU_CONF_PATH" || log_message "WARN" "...FAILED."; log_message "INFO" "APCu config created."; else echo -e "\n; Added by script\napc.enabled=1\napc.shm_size=128M\napc.enable_cli=1" >> "$PHP_APCU_CONF_PATH"; log_message "INFO" "APCu settings added."; fi; else log_message "INFO" "APCu seems configured."; sed -i -E 's/^[; ]*(apc.enabled[ ]*=).*/\11/' "$PHP_APCU_CONF_PATH"; fi; log_message "INFO" "PHP configs OK."
}
# --- Automatic WordPress Multisite Installation Function ---
install_wordpress_multisite_auto() {
    log_message "INFO" "Starting WP Multisite install..."; if ! command -v "$WP_CLI_PATH" &> /dev/null; then log_message "ERROR" "WP-CLI not found."; return 1; fi
    log_message "INFO" "Generating wp-config.php..."; run_command "wp config create" sudo -u nginx "$WP_CLI_PATH" config create --path="${WORDPRESS_ROOT}" --dbname="$WORDPRESS_DB_NAME" --dbuser="$WORDPRESS_DB_USER" --dbpass="$WORDPRESS_DB_PASSWORD" --dbhost="localhost" --allow-root --skip-check --force || return 1
    log_message "INFO" "Adding WP_ALLOW_MULTISITE..."; run_command "wp config set WP_ALLOW_MULTISITE" sudo -u nginx "$WP_CLI_PATH" config set WP_ALLOW_MULTISITE true --raw --path="${WORDPRESS_ROOT}" --anchor="/* That's all, stop editing!" || return 1
    log_message "INFO" "Running WP core multisite-install..."; if ! run_command "wp core multisite-install" sudo -u nginx "$WP_CLI_PATH" core multisite-install --path="${WORDPRESS_ROOT}" --url="${WP_SITE_URL}" --title="${WP_SITE_TITLE}" --admin_user="${CUSTOM_WP_ADMIN_USER}" --admin_password="${CUSTOM_WP_ADMIN_PASSWORD}" --admin_email="${WP_ADMIN_EMAIL}" --subdomains=0 --allow-root --skip-email --skip-config; then log_message "ERROR" "WP core multisite install FAILED."; return 1; fi
    log_message "INFO" "Adding WP_CACHE constant (for APCu)..."; run_command "wp config set WP_CACHE" sudo -u nginx "$WP_CLI_PATH" config set WP_CACHE true --raw --path="${WORDPRESS_ROOT}" --anchor="/* That's all, stop editing!" || return 1
    log_message "INFO" "WP_CACHE set. Activate APCu Object Cache plugin in WP Admin!"; log_message "INFO" "WP Multisite install OK."
}

# --- Main Installation Function ---
install_lemp_wp() {
    local db_setup_choice; while true; do echo ""; echo -e "${C_YELLOW}--- Database Root Password Setup Choice ---${C_RESET}"; echo " A. Default ('root' - INSECURE!)"; echo " B. Custom (Recommended)"; echo ""; read -p " Your choice [A/B]: " db_setup_choice; case $db_setup_choice in a|A) USE_CUSTOM_DB_ROOT_PASSWORD=false; ACTIVE_DB_ROOT_PASSWORD="$MARIADB_ROOT_PASSWORD_DEFAULT"; log_message "WARN" "Choice: Default DB pw."; break ;; b|B) get_custom_db_root_password; ACTIVE_DB_ROOT_PASSWORD="$CUSTOM_DB_ROOT_PASSWORD"; log_message "INFO" "Choice: Custom DB pw."; break ;; *) echo -e "${C_RED}Invalid.${C_RESET}"; ;; esac; done
    log_message "INFO" "================ Starting Installation (MS + APCu) ================"; get_custom_wp_credentials
    run_command "Update system packages" dnf update -y || exit 1; log_message "INFO" "Installing packages..."; run_command "DNF install packages" dnf install -y "${CORE_UTILS[@]}" "${OTHER_PACKAGES[@]}" || exit 1
    log_message "INFO" "Adding Remi repo..."; if ! run_command "Install Remi release" dnf install -y --nogpgcheck https://rpms.remirepo.net/fedora/remi-release-$(rpm -E %fedora).rpm; then log_message "WARN" "Install Remi FAILED."; else log_message "INFO" "Remi repo OK."; fi
    log_message "INFO" "Generating WP DB password..."; WORDPRESS_DB_PASSWORD=$(openssl rand -base64 12); if [[ -z "$WORDPRESS_DB_PASSWORD" ]]; then log_message "ERROR" "Password gen FAILED."; exit 1; fi
    log_message "INFO" "Enabling PHP module stream..."; if ! run_command "Enable PHP ${PHP_MODULE_STREAM}" dnf module enable "${PHP_MODULE_STREAM}" -y; then log_message "WARN" "Enable PHP module FAILED."; fi
    run_command "Install Nginx" dnf install -y nginx || exit 1; run_command "Enable Nginx" systemctl enable nginx || exit 1
    run_command "Start Firewalld" systemctl start firewalld || log_message "WARN" "Firewalld start FAILED."; run_command "Enable Firewalld" systemctl enable firewalld || exit 1; run_command "Allow FW HTTP" firewall-cmd --permanent --add-service=http || exit 1; run_command "Allow FW HTTPS" firewall-cmd --permanent --add-service=https || exit 1; run_command "Reload FW" firewall-cmd --reload || exit 1
    run_command "Install MariaDB" dnf install -y mariadb-server || exit 1; run_command "Enable MariaDB" systemctl enable mariadb || exit 1; run_command "Start MariaDB" systemctl start mariadb || { log_message "ERROR" "MariaDB start FAILED."; exit 1; }
    optimize_mariadb_config || exit 1; setup_database || exit 1
    log_message "INFO" "Installing PHP packages (incl. APCu)..."; run_command "Install PHP packages" dnf install -y "${PHP_PACKAGES[@]}" || { log_message "ERROR" "PHP packages FAILED."; exit 1; }
    optimize_php_config || exit 1; log_message "INFO" "Setting PHP-FPM user/group..."; if [[ -f "$PHP_FPM_WWW_CONF" ]]; then cp "$PHP_FPM_WWW_CONF" "${PHP_FPM_WWW_CONF}.bak.$(date +%s)"; sed -i 's/^user = apache/user = nginx/' "$PHP_FPM_WWW_CONF"; sed -i 's/^group = apache/group = nginx/' "$PHP_FPM_WWW_CONF"; else log_message "WARN" "$PHP_FPM_WWW_CONF not found."; fi
    run_command "Enable PHP-FPM" systemctl enable php-fpm || exit 1; run_command "Create PHP-FPM log dir" mkdir -p /var/log/php-fpm || exit 1; run_command "Set PHP-FPM log perms" chown nginx:nginx /var/log/php-fpm || log_message "WARN" "Perms FAILED."; run_command "Restart PHP-FPM" systemctl restart php-fpm || { log_message "ERROR" "PHP-FPM restart FAILED."; exit 1; }
    run_command "Install phpMyAdmin" dnf install -y phpmyadmin || exit 1; log_message "INFO" "Configuring phpMyAdmin..."; BLOWFISH_SECRET=$(openssl rand -base64 32); PMA_PASSWORD=$(openssl rand -base64 16); mkdir -p "$(dirname "$PHPMYADMIN_CONFIG")"

    # Corrected Heredoc for PMA Config
    cat <<EOF > "$PHPMYADMIN_CONFIG"
<?php /* PMA config */
declare(strict_types=1);
\$cfg['blowfish_secret'] = '${BLOWFISH_SECRET}';
\$i=0;
\$i++;
\$cfg['Servers'][\$i]['auth_type'] = 'cookie';
\$cfg['Servers'][\$i]['host'] = 'localhost';
\$cfg['Servers'][\$i]['compress'] = false;
\$cfg['Servers'][\$i]['AllowNoPassword'] = false;
\$cfg['Servers'][\$i]['AllowRoot'] = true;
\$cfg['Servers'][\$i]['controlhost'] = 'localhost';
\$cfg['Servers'][\$i]['controluser'] = 'pma';
\$cfg['Servers'][\$i]['controlpass'] = '${PMA_PASSWORD}';
\$cfg['Servers'][\$i]['pmadb'] = 'phpmyadmin';
\$cfg['Servers'][\$i]['bookmarktable'] = 'pma__bookmark';
\$cfg['Servers'][\$i]['relation'] = 'pma__relation';
\$cfg['Servers'][\$i]['table_info'] = 'pma__table_info';
\$cfg['Servers'][\$i]['table_coords'] = 'pma__table_coords';
\$cfg['Servers'][\$i]['pdf_pages'] = 'pma__pdf_pages';
\$cfg['Servers'][\$i]['column_info'] = 'pma__column_info';
\$cfg['Servers'][\$i]['history'] = 'pma__history';
\$cfg['Servers'][\$i]['table_uiprefs'] = 'pma__table_uiprefs';
\$cfg['Servers'][\$i]['tracking'] = 'pma__tracking';
\$cfg['Servers'][\$i]['userconfig'] = 'pma__userconfig';
\$cfg['Servers'][\$i]['recent'] = 'pma__recent';
\$cfg['Servers'][\$i]['favorite'] = 'pma__favorite';
\$cfg['Servers'][\$i]['users'] = 'pma__users';
\$cfg['Servers'][\$i]['usergroups'] = 'pma__usergroups';
\$cfg['Servers'][\$i]['navigationhiding'] = 'pma__navigationhiding';
\$cfg['Servers'][\$i]['savedsearches'] = 'pma__savedsearches';
\$cfg['Servers'][\$i]['central_columns'] = 'pma__central_columns';
\$cfg['Servers'][\$i]['designer_settings'] = 'pma__designer_settings';
\$cfg['Servers'][\$i]['export_templates'] = 'pma__export_templates';
\$cfg['UploadDir'] = '';
\$cfg['SaveDir'] = '';
\$cfg['TempDir'] = '${PHPMYADMIN_TMP_DIR}';
\$cfg['PmaAbsoluteUri'] = '/phpmyadmin/';
\$cfg['Setup']['disabled'] = true;
?>
EOF
    # End of PMA Heredoc correction

    run_command "PMA temp dir" mkdir -p "$PHPMYADMIN_TMP_DIR" || exit 1; run_command "PMA lib perms" chown -R nginx:nginx "$(dirname "$PHPMYADMIN_TMP_DIR")" || exit 1; run_command "PMA temp chmod" chmod 770 "$PHPMYADMIN_TMP_DIR" || exit 1; log_message "INFO" "PMA DB setup..."; run_mysql_command "PMA DB" "CREATE DATABASE IF NOT EXISTS phpmyadmin DEFAULT CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;" || log_message "WARN" "...FAILED."; run_mysql_command "PMA User" "CREATE USER IF NOT EXISTS 'pma'@'localhost' IDENTIFIED BY '${PMA_PASSWORD}';" || log_message "WARN" "...FAILED."; run_mysql_command "PMA Grant" "GRANT ALL PRIVILEGES ON phpmyadmin.* TO 'pma'@'localhost';" || log_message "WARN" "...FAILED."; run_mysql_command "PMA Flush" "FLUSH PRIVILEGES;" || log_message "WARN" "...FAILED."; SQL_SCHEMA_GZ="/usr/share/phpmyadmin/sql/create_tables.sql.gz"; SQL_SCHEMA="/tmp/create_tables.sql"; if [[ -f "$SQL_SCHEMA_GZ" ]]; then gunzip < "$SQL_SCHEMA_GZ" > "$SQL_SCHEMA"; if run_mysql_command "PMA import" "USE phpmyadmin; SOURCE ${SQL_SCHEMA}"; then log_message "INFO" "PMA schema OK."; rm "$SQL_SCHEMA"; else log_message "WARN" "PMA import FAILED."; fi; else log_message "WARN" "PMA SQL schema not found."; fi
    install_wp_cli || exit 1; run_command "Create WP dir" mkdir -p "$WORDPRESS_ROOT" || exit 1; cd /tmp || exit 1; run_command "Download WP" curl -fLO https://wordpress.org/latest.tar.gz || exit 1; run_command "Extract WP" tar -xzf latest.tar.gz -C "$(dirname "$WORDPRESS_ROOT")" || exit 1; if [[ ! -d "$WORDPRESS_ROOT" ]] && [[ -d "$(dirname "$WORDPRESS_ROOT")/wordpress" ]]; then run_command "Rename WP dir" mv "$(dirname "$WORDPRESS_ROOT")/wordpress" "$WORDPRESS_ROOT" || exit 1; fi; run_command "Set WP perms" chown -R nginx:nginx "$WORDPRESS_ROOT" || exit 1; find "$WORDPRESS_ROOT" -type d -exec chmod 755 {} \; && find "$WORDPRESS_ROOT" -type f -exec chmod 644 {} \; ; rm -f /tmp/latest.tar.gz; log_message "INFO" "WP files OK."
    log_message "INFO" "SELinux adjustments..."; if ! run_command "SELinux fcontext" semanage fcontext -a -t httpd_sys_rw_content_t "${WP_CONTENT_DIR}(/.*)?"; then log_message "WARN" "fcontext FAILED."; fi; run_command "SELinux restorecon" restorecon -Rv "${WORDPRESS_ROOT}" || log_message "WARN" "restorecon FAILED."; run_command "SELinux httpd_can_network_connect" setsebool -P httpd_can_network_connect 1 || exit 1; run_command "SELinux httpd_can_network_relay" setsebool -P httpd_can_network_relay 1 || exit 1; log_message "INFO" "SELinux OK."
    install_wordpress_multisite_auto || exit 1
    log_message "INFO" "Configuring Nginx...";

    # Corrected Heredoc for Nginx Config
    cat <<EOF > "${NGINX_CONF_DIR}/wordpress.conf"
# Nginx config by script
server {
    listen 80 default_server;
    listen [::]:80 default_server;
    server_name ${WP_SITE_URL#http://};
    root ${WORDPRESS_ROOT};
    index index.php;
    access_log /var/log/nginx/wordpress.access.log;
    error_log /var/log/nginx/wordpress.error.log warn;
    client_max_body_size ${PHP_UPLOAD_MAX_FILESIZE};

    server_tokens off;
    keepalive_timeout 65;
    add_header X-Frame-Options "SAMEORIGIN" always;
    add_header X-Content-Type-Options "nosniff" always;
    add_header Referrer-Policy "strict-origin-when-cross-origin" always;
    add_header Permissions-Policy "geolocation=(),midi=(),sync-xhr=(),microphone=(),camera=(),magnetometer=(),gyroscope=(),fullscreen=(self),payment=()" always;

    gzip on;
    gzip_vary on;
    gzip_proxied any;
    gzip_comp_level 6;
    gzip_min_length 256;
    gzip_types application/atom+xml application/javascript application/json application/ld+json application/manifest+json application/rss+xml application/vnd.geo+json application/vnd.ms-fontobject application/x-font-ttf application/x-web-app-manifest+json application/xhtml+xml application/xml font/opentype image/bmp image/svg+xml image/x-icon text/cache-manifest text/css text/plain text/vcard text/vnd.rim.location.xloc text/vtt text/x-component text/x-cross-domain-policy;

    location / {
        try_files \$uri \$uri/ /index.php?\$args;
    }

    location ~ \.php$ {
        if (\$request_uri ~* ^/(wp-includes|wp-content)/.*\.php$) { return 403; }
        if (\$request_uri ~* ^/wp-content/uploads/.*\.php$) { return 403; }
        try_files \$uri =404;
        include fastcgi_params;
        fastcgi_pass unix:/run/php-fpm/www.sock;
        fastcgi_index index.php;
        fastcgi_param SCRIPT_FILENAME \$document_root\$fastcgi_script_name;
        fastcgi_intercept_errors off;
        fastcgi_buffer_size 16k;
        fastcgi_buffers 4 16k;
        fastcgi_connect_timeout 60;
        fastcgi_send_timeout 180;
        fastcgi_read_timeout 180;
    }

    location ^~ /phpmyadmin {
        alias /usr/share/phpmyadmin;
        index index.php;
        location ~ ^/phpmyadmin/(.+\.php)$ {
            try_files \$uri =404;
            include fastcgi_params;
            fastcgi_pass unix:/run/php-fpm/www.sock;
            fastcgi_index index.php;
            fastcgi_param SCRIPT_FILENAME \$request_filename;
        }
        location ~ ^/phpmyadmin/(.+\.(?:css|js|gif|jpe?g|png|ico|svg|woff2?|ttf|eot))$ {
            expires 1M;
            add_header Cache-Control "public";
            access_log off;
        }
        location ~ ^/phpmyadmin/(?:README|INSTALL|LICENSE|ChangeLog|composer\.json|phpunit\.xml\.dist|setup/.*)$ {
            deny all;
        }
    }

    location ~ /\.ht { deny all; }
    location = /wp-config.php { deny all; }
    location = /xmlrpc.php { deny all; }
    location ~* \.(?:bak|conf|dist|fla|in[ci]|log|psd|sh|sql|sw[op]|tar|gz|bz2|zip)$ { deny all; }
    location ~* \.(?:css(\.map)?|js(\.map)?|jpe?g|png|gif|ico|cur|heic|webp|tiff?|mp3|m4a|aac|ogg|midi?|wav|mp4|mov|webm|mpe?g|avi|ogv|flv|wmv|svgz?|ttf|ttc|otf|eot|woff2?)$ {
        expires 1M;
        access_log off;
        add_header Cache-Control "public";
    }
    location = /favicon.ico { log_not_found off; access_log off; }
    location = /robots.txt { allow all; log_not_found off; access_log off; }
}
EOF
    # End of Nginx Heredoc correction

    log_message "INFO" "Nginx config written OK."; run_command "Create Nginx log dir" mkdir -p /var/log/nginx || exit 1; log_message "INFO" "Testing Nginx config..."; if ! nginx -t >> "$LOG_FILE" 2>&1; then log_message "ERROR" "Nginx config test FAILED!"; exit 1; fi; log_message "INFO" "Nginx test OK."; run_command "Restart Nginx" systemctl restart nginx || { log_message "ERROR" "Nginx restart FAILED."; exit 1; }
    log_message "INFO" "================ Installation Finished Successfully ================"; echo ""; echo -e "${C_GREEN}${BORDER_DOUBLE}${C_RESET}"; echo -e " ✅ ${C_GREEN}Installation Complete: LEMP + PMA + WP Multisite + APCu${C_RESET}"; echo -e "${C_GREEN}${BORDER_DOUBLE}${C_RESET}"; echo " ${C_YELLOW}IMPORTANT DETAILS:${C_RESET}"; echo -e "${C_GREY}${BORDER_SINGLE}${C_RESET}"; echo "   ${C_BLUE}WP Network Admin:${C_RESET} ${C_CYAN}${WP_SITE_URL}/wp-admin/network/${C_RESET} (User: ${CUSTOM_WP_ADMIN_USER}, PW: ${C_YELLOW}${CUSTOM_WP_ADMIN_PASSWORD}${C_RESET})"; echo "   ${C_BLUE}WP Main Site Admin:${C_RESET} ${C_CYAN}${WP_SITE_URL}/wp-admin/${C_RESET} (User: ${CUSTOM_WP_ADMIN_USER}, PW: ${CUSTOM_WP_ADMIN_PASSWORD})"; echo "   ${C_BLUE}phpMyAdmin:${C_RESET}       ${C_CYAN}${WP_SITE_URL}/phpmyadmin/${C_RESET} (User: root, PW: ${C_YELLOW}${ACTIVE_DB_ROOT_PASSWORD}${C_RESET}) ${([[ "$USE_CUSTOM_DB_ROOT_PASSWORD" == false ]] && echo -e "${C_RED}(INSECURE!)${C_RESET}")}"; echo "   ${C_BLUE}DB Details:${C_RESET}       (Name: ${WORDPRESS_DB_NAME}, User: ${WORDPRESS_DB_USER}, PW: ${WORDPRESS_DB_PASSWORD})"; echo "   ${C_BLUE}Log File:${C_RESET}          ${LOG_FILE}"; echo -e "${C_GREY}${BORDER_SINGLE}${C_RESET}"; echo " ${C_YELLOW}NEXT STEPS:${C_RESET}"; echo -e " 🔥 ${C_GREEN}APCu Object Cache:${C_RESET} ${C_YELLOW}ACTIVATE 'APCu Object Cache Backend' plugin in WP Admin!${C_RESET}"; echo -e " 🚀 ${C_GREEN}Performance:${C_RESET}      Tune MariaDB (${MARIADB_OPT_CONF}), PHP-FPM (${PHP_FPM_WWW_CONF}), OPcache/APCu. ${C_YELLOW}Install a Page Cache plugin!${C_RESET}"; echo -e " 👉 ${C_GREEN}HTTPS:${C_RESET}            ${C_CYAN}sudo dnf install -y ${CERTBOT_PACKAGES[*]} && sudo certbot --nginx${C_RESET}"; echo -e "${C_GREEN}${BORDER_DOUBLE}${C_RESET}"
}

# --- Uninstall Function ---
uninstall_lemp_wp() {
    log_message "INFO" "================ Starting Uninstallation ================"; echo -e " ${C_RED}WARNING: DESTRUCTIVE ACTION!${C_RESET}"; read -p "--> Type 'YES' to proceed: " confirm_uninstall; if [[ "${confirm_uninstall}" != "YES" ]]; then log_message "INFO" "Uninstallation canceled."; return 1; fi
    log_message "INFO" "Stopping/disabling services..."; run_command "Stop Nginx" systemctl stop nginx ||:; run_command "Disable Nginx" systemctl disable nginx ||:; run_command "Stop MariaDB" systemctl stop mariadb ||:; run_command "Disable MariaDB" systemctl disable mariadb ||:; run_command "Stop PHP-FPM" systemctl stop php-fpm ||:; run_command "Disable PHP-FPM" systemctl disable php-fpm ||:
    log_message "INFO" "Removing firewall rules..."; run_command "FW Remove HTTP" firewall-cmd --permanent --remove-service=http ||:; run_command "FW Remove HTTPS" firewall-cmd --permanent --remove-service=https ||:; run_command "FW Reload" firewall-cmd --reload ||:
    echo ""; log_message "WARN" "!! DATABASE DELETION !! Directory: ${MARIADB_DATA_DIR} !!"; echo ""; read -p "--> Type 'DELETE DB': " confirm_db_delete; if [[ "${confirm_db_delete}" == "DELETE DB" ]]; then run_command "Delete DB data" rm -rf "${MARIADB_DATA_DIR}"; else log_message "INFO" "DB deletion skipped."; fi
    log_message "INFO" "Removing packages..."; local ALL_PACKAGES=("${OTHER_PACKAGES[@]}" "${PHP_PACKAGES[@]}" "${CERTBOT_PACKAGES[@]}" "${CORE_UTILS[@]}"); if rpm -q remi-release &>/dev/null; then ALL_PACKAGES+=("remi-release"); fi
    log_message "INFO" "Removing: ${ALL_PACKAGES[*]}"; run_command "Remove packages" dnf remove -y "${ALL_PACKAGES[@]}" || log_message "WARN" "Package remove FAILED."; run_command "Autoremove" dnf autoremove -y || log_message "WARN" "Autoremove FAILED."
    log_message "INFO" "Removing configurations, logs & WP-CLI..."; run_command "Remove Nginx conf" rm -f "${NGINX_CONF_DIR}/wordpress.conf"; run_command "Remove MariaDB conf" rm -f "${MARIADB_OPT_CONF}"; run_command "Remove PMA conf" rm -rf /etc/phpMyAdmin; run_command "Remove PMA lib" rm -rf /var/lib/phpmyadmin; run_command "Remove OPcache conf" rm -f "$PHP_OPCACHE_CONF_PATH"; run_command "Remove APCu conf" rm -f "$PHP_APCU_CONF_PATH"; run_command "Remove php.ini backups" rm -f "${PHP_INI_PATH}.bak.*"; run_command "Remove ext .ini backups" find "$PHP_EXTENSIONS_DIR" -name '*.ini.bak*' -delete; run_command "Remove WP-CLI" rm -f "$WP_CLI_PATH"; run_command "Remove logs" rm -f /var/log/nginx/wordpress.*.log "$LOG_FILE"; run_command "Remove log dirs" rmdir /var/log/nginx /var/log/php-fpm 2>/dev/null || true
    echo ""; log_message "WARN" "!! WORDPRESS FILES DELETION !! Directory: ${WORDPRESS_ROOT} !!"; echo ""; read -p "--> Type 'DELETE WP': " confirm_wp_delete; if [[ "${confirm_wp_delete}" == "DELETE WP" ]]; then run_command "Delete WP directory" rm -rf "${WORDPRESS_ROOT}"; else log_message "INFO" "WP deletion skipped."; fi
    log_message "INFO" "Removing SELinux fcontext..."; run_command "SELinux fcontext delete" semanage fcontext -d "${WP_CONTENT_DIR}(/.*)?" || log_message "WARN" "SELinux fcontext delete FAILED."
    log_message "INFO" "================ Uninstallation Complete ================"; return 0
}

# --- Main Menu Function (v2.15.1 - English + Color Fix) ---
main_menu() {
     while true; do
        display_welcome_screen

        echo -e "${HEADER_COLOR}${BORDER_DOUBLE}${C_RESET}"
        printf "${HEADER_COLOR}== %-82s ==${C_RESET}\n" " ${TITLE_COLOR}Main Menu${C_RESET} ${C_GREY}(LEMP + WP Multisite + APCu)${C_RESET}"
        echo -e "${HEADER_COLOR}${BORDER_SINGLE}${C_RESET}"

        # Installation / Uninstallation Section
        printf "   %b %-20s %s\n" "${ACTION_INSTALL_COLOR}[1]${C_RESET}" "Install" "Install everything (Optimal, Auto)"
        printf "   %b %-20s %s\n" "${ACTION_WARN_COLOR}[2]${C_RESET}" "Reinstall" "Remove everything & install again"
        printf "   %b %-20s %s\n" "${ACTION_DANGER_COLOR}[3]${C_RESET}" "Uninstall" "Remove everything ${C_RED}(INCL. DATA!)${C_RESET}"
        echo -e "${HEADER_COLOR}${BORDER_SINGLE}${C_RESET}"

        # Configuration Section
        printf "   %b %-20s %s\n" "${ACTION_CONFIG_COLOR}[P]${C_RESET}" "PHP Settings" "Adjust php.ini values"
        printf "   %b %-20s %s\n" "${ACTION_CONFIG_COLOR}[E]${C_RESET}" "PHP Extensions" "Manage PHP extensions (on/off)"
        printf "   %b %-20s %s\n" "${ACTION_CONFIG_COLOR}[M]${C_RESET}" "Multisite Toggle" "Enable/disable Multisite in wp-config"
        printf "   %b %-20s %s\n" "${ACTION_CONFIG_COLOR}[C]${C_RESET}" "Cookie Fix" "Apply WordPress cookie fixes"
        printf "   %b %-20s %s\n" "${ACTION_CONFIG_COLOR}[U]${C_RESET}" "Undo Cookie Fix" "Revert WordPress cookie fixes"
        echo -e "${HEADER_COLOR}${BORDER_SINGLE}${C_RESET}"

        # Information & Tools Section
        printf "   %b %-20s %s\n" "${ACTION_INFO_COLOR}[V]${C_RESET}" "Versions" "Show Nginx, MariaDB, PHP versions"
        printf "   %b %-20s %s\n" "${ACTION_INFO_COLOR}[H]${C_RESET}" "Health Check" "Check services & configuration"
        printf "   %b %-20s %s\n" "${ACTION_INFO_COLOR}[R]${C_RESET}" "Restart Services" "Restart Nginx, MariaDB, PHP-FPM"
        printf "   %b %-20s %s (%s%s%s)\n" "${ACTION_INFO_COLOR}[L]${C_RESET}" "Log File" "View" "${C_GREY}" "${LOG_FILE}" "${C_RESET}"
        echo -e "${HEADER_COLOR}${BORDER_SINGLE}${C_RESET}"

        # Exit
        printf "   %b %-20s %s\n" "${C_GREY}[0]${C_RESET}" "Exit" "Exit the script"
        echo -e "${HEADER_COLOR}${BORDER_DOUBLE}${C_RESET}"

        # Prompt - Print prompt text separately before read for better compatibility
        echo -en "${PROMPT_COLOR}   Your choice [1,2,3,P,E,M,C,U,V,H,R,L,0]: ${C_RESET}"
        read choice

        # Process choice
        case $choice in
            1) install_lemp_wp; log_message "INFO" "Installation finished."; break ;;
            2) if uninstall_lemp_wp; then log_message "INFO" "Removal OK. Starting reinstall..."; install_lemp_wp; log_message "INFO" "Reinstallation finished."; else log_message "ERROR" "Removal failed/cancelled."; fi; break ;;
            3) uninstall_lemp_wp; log_message "INFO" "Removal finished."; break ;;
            P|p) adjust_php_settings ;;
            E|e) manage_php_extensions ;;
            M|m) toggle_multisite ;;
            C|c) apply_cookie_fixes ;;
            U|u) revert_cookie_fixes ;;
            V|v) display_versions ;;
            H|h) health_check ;;
            R|r) restart_services ;;
            L|l) log_message "INFO" "Opening log file..."; less "$LOG_FILE";;
            0) log_message "INFO" "Script exited."; echo -e "\n${C_BLUE}Script exited.${C_RESET}"; exit 0;;
            *) log_message "WARN" "Invalid choice: ${choice}"; echo -e "\n${C_RED}ERROR: Invalid choice '${choice}'. Please try again.${C_RESET}"; sleep 2;;
        esac
    done
}

# --- Script Execution ---
check_root
main_menu

exit 0
