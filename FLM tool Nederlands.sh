#!/bin/bash

# LEMP Stack + phpMyAdmin + WordPress Multisite TOP OPTIMALISATIE Script v2.14.2 voor Fedora
# Auteur: H Dabo (Concept & Basis) / AI (Implementatie & Verfijning) - 2025
# ------------------------------------------------------------------------------------
# - FIX: Heredoc syntax for PMA and Nginx config in install_lemp_wp (v2.14.2)
# --- Vorige wijzigingen ---
# - ADDED: Multisite Aan/Uit schakelaar menu optie
# - FIX: PHP Extension Management - sed command for enabling extensions
# - FIX: Menu readability and alignment with color codes
# - ADDED: WordPress Cookie Fix/Revert menu opties
# - ADDED: Service Herstart menu optie
# - ADDED: Versie informatie menu optie
# - ADDED: Interactieve PHP Extensie beheer menu optie
# - ADDED: Interactieve PHP instellingen aanpassen menu optie
# - ADDED: Uitgebreide Gezondheidscontrole menu optie
# - ADDED: Welkomstscherm met verbeterde styling
# - REMOVED: Redis/Valkey
# - ADDED: Focus op APCu Caching
# - OPT/FIX: Diverse optimalisaties en bugfixes
# --- Basis Features ---
# - Keuze voor Standaard (onveilig 'root') of Aangepast DB Root Wachtwoord
# - Nieuwste PHP via DNF Module (probeert 8.3) + Remi Repo fallback
# - Sterk Geoptimaliseerde Nginx (Headers, Gzip, Cache, Security)
# - Automatische installatie (Vraagt WP Admin WW & optioneel DB Root WW)
#
# 🚨🚨🚨 WAARSCHUWING: Standaard DB Root WW optie is ONVEILIG! Kies Aangepast! 🚨🚨🚨
# 🚨🚨🚨 KIES EEN STERK WP ADMIN WACHTWOORD WANNEER GEVRAAGD!            🚨🚨🚨
# 🚨🚨🚨 UITSLUITEND VOOR LOKALE, NIET-PUBLIEKE TESTOMGEVINGEN!       🚨🚨🚨
#
# BELANGRIJK: 100% PageSpeed score vereist frontend optimalisatie en page caching NA deze installatie!
#
# WAARSCHUWING: Opties 2 en 3 zijn DESTRUCTIEF en verwijderen data!

set -uo pipefail

# --- Kleurcodes ---
C_BLUE='\e[1;34m'; C_GREEN='\e[1;32m'; C_YELLOW='\e[1;33m'; C_RED='\e[1;31m'
C_CYAN='\e[1;36m'; C_MAGENTA='\e[1;35m'; C_WHITE='\e[1;37m'; C_GREY='\e[0;37m'; C_RESET='\e[0m'

# --- Menu Styling ---
BORDER_DOUBLE="======================================================================================"
BORDER_SINGLE="--------------------------------------------------------------------------------------"
TITLE_COLOR=$C_WHITE; HEADER_COLOR=$C_BLUE; ACTION_INSTALL_COLOR=$C_GREEN; ACTION_CONFIG_COLOR=$C_MAGENTA
ACTION_INFO_COLOR=$C_CYAN; ACTION_WARN_COLOR=$C_YELLOW; ACTION_DANGER_COLOR=$C_RED; PROMPT_COLOR=$C_WHITE

# --- Variabelen ---
CALLING_USER=${SUDO_USER:-$(logname)}
MARIADB_ROOT_PASSWORD_DEFAULT='root'; CUSTOM_DB_ROOT_PASSWORD=''; ACTIVE_DB_ROOT_PASSWORD=''; USE_CUSTOM_DB_ROOT_PASSWORD=false
WORDPRESS_DB_NAME="wordpress_ms_opt_db"; WORDPRESS_DB_USER="wordpress_ms_opt_usr"; WORDPRESS_DB_PASSWORD=''
CUSTOM_WP_ADMIN_USER=''; CUSTOM_WP_ADMIN_PASSWORD=''; WP_ADMIN_EMAIL='admin@example.com'; WP_SITE_TITLE='Top Geoptimaliseerde WP Multisite'; WP_SITE_URL='http://localhost'
PHP_MEMORY_LIMIT="256M"; PHP_UPLOAD_MAX_FILESIZE="64M"; PHP_POST_MAX_SIZE="64M"; PHP_MAX_EXECUTION_TIME="180"; PHP_SETTINGS_TO_ADJUST=( "memory_limit" "post_max_size" "max_execution_time" "upload_max_filesize" "max_input_time" "max_input_vars" )
PHP_EXTENSIONS_DIR="/etc/php.d"
WORDPRESS_ROOT="/var/www/wordpress"; WP_CONFIG_PATH="${WORDPRESS_ROOT}/wp-config.php"; WP_CONTENT_DIR="${WORDPRESS_ROOT}/wp-content"; NGINX_CONF_DIR="/etc/nginx/conf.d"; PHP_INI_PATH="/etc/php.ini"; PHP_OPCACHE_CONF_PATH="${PHP_EXTENSIONS_DIR}/99-wp-optimized-opcache.ini"; PHP_APCU_CONF_PATH="${PHP_EXTENSIONS_DIR}/40-apcu.ini"; PHP_FPM_WWW_CONF="/etc/php-fpm.d/www.conf"; PHPMYADMIN_CONFIG="/etc/phpMyAdmin/config.inc.php"; PHPMYADMIN_TMP_DIR="/var/lib/phpmyadmin/tmp"; MARIADB_DATA_DIR="/var/lib/mysql"; MARIADB_OPT_CONF="/etc/my.cnf.d/99-wordpress-optimizations.cnf"; LOG_FILE="/var/log/lemp_wp_ms_optimized_apcu_install.log"; WP_CLI_PATH="/usr/local/bin/wp"
COOKIE_FIX_CONFIG_LINE="define('COOKIE_DOMAIN', \$_SERVER['HTTP_HOST'] );"
COOKIE_FIX_FUNCTIONS_CODE=$(cat <<'EOT'
// START COOKIE FIX SCRIPT - Added by LEMP Script
if ( defined('SITECOOKIEPATH') && defined('COOKIEPATH') && SITECOOKIEPATH != COOKIEPATH && function_exists('setcookie') ) {
    // Gebruik null coalescing operator voor COOKIE_DOMAIN voor PHP 7+ compatibiliteit
    setcookie(defined('TEST_COOKIE') ? TEST_COOKIE : 'wordpress_test_cookie', 'WP Cookie check', 0, SITECOOKIEPATH, COOKIE_DOMAIN ?? '');
}
// END COOKIE FIX SCRIPT
EOT
); COOKIE_FIX_START_MARKER="// START COOKIE FIX SCRIPT"; COOKIE_FIX_END_MARKER="// END COOKIE FIX SCRIPT"

# --- Logging Functie ---
log_message() { local type="$1" message="$2"; echo "[$(date '+%Y-%m-%d %H:%M:%S')] [${type}] ${message}" | tee -a "$LOG_FILE"; }

# --- Package Lijsten ---
PHP_PACKAGES=( php php-common php-fpm php-mysqlnd php-gd php-json php-mbstring php-xml php-curl php-zip php-intl php-imagick php-opcache php-soap php-bcmath php-sodium php-exif php-fileinfo php-pecl-apcu php-pecl-apcu-devel )
OTHER_PACKAGES=( nginx mariadb-server phpmyadmin curl wget ImageMagick )
CORE_UTILS=( policycoreutils policycoreutils-python-utils util-linux-user openssl dnf-utils )
CERTBOT_PACKAGES=( certbot python3-certbot-nginx )

# --- Hulpfunctie voor commando uitvoering met check ---
run_command() {
    local description="$1"; shift; local suppress_output=false
    if [[ "$1" == "--suppress" ]]; then suppress_output=true; shift; fi
    log_message "INFO" "Start: ${description}"; if output=$("$@" 2>&1); then
        log_message "INFO" "Succes: ${description}"; [[ -n "$output" ]] && echo -e "$output" >> "$LOG_FILE";
        if [[ "$suppress_output" == false ]]; then echo "$output"; fi; return 0;
    else local exit_code=$?; log_message "ERROR" "Mislukt (Exit Code: $exit_code): ${description}."; log_message "ERROR" "Output:\n$output";
        if [[ "$suppress_output" == false ]]; then echo -e "${C_RED}---- FOUT Output ----${C_RESET}" >&2; echo -e "$output" >&2; echo -e "${C_RED}---------------------${C_RESET}" >&2; fi
        log_message "ERROR" "Zie logbestand: ${LOG_FILE}"; return $exit_code; fi
}
# --- Hulpfunctie voor SQL commando's ---
run_mysql_command() { local description="$1"; local sql_command="$2"; run_command "${description}" mysql -u root -p"${ACTIVE_DB_ROOT_PASSWORD}" -e "${sql_command}"; }
# --- Functie om AANGEPAST WP admin gegevens te vragen ---
get_custom_wp_credentials() {
    log_message "INFO" "Instellen WP admin..."; while [[ -z "$CUSTOM_WP_ADMIN_USER" ]]; do read -p "Voer WP ADMIN GEBRUIKERSNAAM in: " CUSTOM_WP_ADMIN_USER; if [[ -z "$CUSTOM_WP_ADMIN_USER" ]]; then echo -e "${C_RED}FOUT: Leeg.${C_RESET}"; fi; done; local p1=""; local p2=""; while true; do read -s -p "Voer WW voor '${CUSTOM_WP_ADMIN_USER}' in: " p1; echo ""; read -s -p "Bevestig WW: " p2; echo ""; if [[ "$p1" == "$p2" ]]; then if [[ -z "$p1" ]]; then echo -e "${C_RED}FOUT: Leeg.${C_RESET}"; else CUSTOM_WP_ADMIN_PASSWORD="$p1"; log_message "INFO" "WP WW OK."; break; fi; else echo -e "${C_RED}FOUT: Komt niet overeen.${C_RESET}"; fi; done
}
# --- Functie om AANGEPAST DB root wachtwoord te vragen ---
get_custom_db_root_password() {
    log_message "INFO" "Instellen DB root ww..."; local p1=""; local p2=""; while true; do read -s -p "Voer GEWENST DB 'root' WW in: " p1; echo ""; read -s -p "Bevestig WW: " p2; echo ""; if [[ "$p1" == "$p2" ]]; then if [[ -z "$p1" ]]; then echo -e "${C_RED}FOUT: Leeg.${C_RESET}"; else CUSTOM_DB_ROOT_PASSWORD="$p1"; USE_CUSTOM_DB_ROOT_PASSWORD=true; log_message "INFO" "Custom DB WW OK."; break; fi; else echo -e "${C_RED}FOUT: Komt niet overeen.${C_RESET}"; fi; done
}

# --- Functies ---
check_root() {
    > "$LOG_FILE"; chown "${CALLING_USER:-root}":"${CALLING_USER:-root}" "$LOG_FILE" || true; log_message "INFO" "Script gestart door $(whoami), aangeroepen door ${CALLING_USER}"; if [[ $EUID -ne 0 ]]; then log_message "ERROR" "Root rechten vereist."; echo -e "${C_RED}FOUT: Script vereist root rechten (sudo).${C_RESET}"; exit 1; fi
}

# --- Welkomstscherm Functie ---
display_welcome_screen() {
    clear; echo -e "${HEADER_COLOR}${BORDER_DOUBLE}${C_RESET}"; printf "${HEADER_COLOR}== %-82s ==${C_RESET}\n" ""; printf "${HEADER_COLOR}== %-82s ==${C_RESET}\n" "    ${TITLE_COLOR}Fedora LEMP + WordPress Multisite Optimalisatie Script${C_RESET}"; printf "${HEADER_COLOR}== %-82s ==${C_RESET}\n" "                  ${C_YELLOW}(Met APCu Object Caching)${C_RESET}"; printf "${HEADER_COLOR}== %-82s ==${C_RESET}\n" ""; printf "${HEADER_COLOR}== %-82s ==${C_RESET}\n" "                    ${C_GREY}Auteur: H Dabo - 2025${C_RESET}"; echo -e "${HEADER_COLOR}${BORDER_DOUBLE}${C_RESET}"; echo ""; log_message "WARN" "🚨🚨🚨 Standaard DB Root WW is ONVEILIG! Kies Aangepast! 🚨🚨🚨"; echo ""
}

# --- Hulpfunctie: Vind actieve theme functions.php ---
get_active_theme_functions_path() {
    local functions_path=""
    if [[ ! -f "$WP_CLI_PATH" ]]; then log_message "ERROR" "WP-CLI niet gevonden op ${WP_CLI_PATH}."; echo -e "${C_RED}FOUT: WP-CLI niet gevonden!${C_RESET}"; return 1; fi
    if [[ ! -d "$WORDPRESS_ROOT" ]]; then log_message "ERROR" "WP map ${WORDPRESS_ROOT} niet gevonden."; echo -e "${C_RED}FOUT: WP map niet gevonden!${C_RESET}"; return 1; fi
    log_message "INFO" "Actieve theme opvragen..."; local active_theme_slug
    if ! active_theme_slug=$(sudo -u nginx "$WP_CLI_PATH" theme list --status=active --field=name --path="$WORDPRESS_ROOT" --allow-root 2>>"$LOG_FILE"); then
        log_message "ERROR" "WP-CLI 'theme list' mislukt (Exit: $?)."; echo -e "${C_RED}FOUT: Kon actieve theme niet ophalen via WP-CLI.${C_RESET}"; return 1; fi
    if [[ -z "$active_theme_slug" ]]; then log_message "ERROR" "WP-CLI gaf geen actieve theme slug."; echo -e "${C_RED}FOUT: Geen actieve theme gevonden.${C_RESET}"; return 1; fi
    functions_path="${WP_CONTENT_DIR}/themes/${active_theme_slug}/functions.php"; log_message "INFO" "Theme: ${active_theme_slug}. Path: ${functions_path}"
    if [[ ! -f "$functions_path" ]]; then log_message "ERROR" "functions.php niet gevonden: ${functions_path}."; echo -e "${C_RED}FOUT: functions.php voor theme '${active_theme_slug}' niet gevonden!${C_RESET}"; return 1; fi
    echo "$functions_path"; return 0
}

# --- Cookie Fix Functie ---
apply_cookie_fixes() {
    log_message "INFO" "Start toepassen cookie fixes..."
    echo -e "\n${C_MAGENTA}--- WordPress Cookie Fix Toepassen ---${C_RESET}"; local changes_made_count=0
    if [[ ! -f "$WP_CONFIG_PATH" ]]; then log_message "ERROR" "wp-config.php niet gevonden."; echo -e "${C_RED}FOUT: ${WP_CONFIG_PATH} niet gevonden!${C_RESET}";
    else if grep -q "define('COOKIE_DOMAIN'" "$WP_CONFIG_PATH"; then log_message "INFO" "COOKIE_DOMAIN bestaat al."; echo -e "${C_YELLOW}INFO:${C_RESET} COOKIE_DOMAIN al in ${WP_CONFIG_PATH}.";
        else local backup_file_config="${WP_CONFIG_PATH}.bak_cookie_fix.$(date +%s)"; log_message "INFO" "Backup ${WP_CONFIG_PATH} -> ${backup_file_config}."; cp "$WP_CONFIG_PATH" "$backup_file_config" || { log_message "ERROR" "Backup mislukt."; echo -e "${C_RED}FOUT: Backup mislukt.${C_RESET}"; return 1; }; echo -e "Backup: ${C_GREY}${backup_file_config}${C_RESET}";
             log_message "INFO" "Toevoegen COOKIE_DOMAIN aan ${WP_CONFIG_PATH}..."; if sed -i "/\/\* That's all, stop editing!/i ${COOKIE_FIX_CONFIG_LINE}" "$WP_CONFIG_PATH"; then log_message "INFO" "COOKIE_DOMAIN toegevoegd."; echo -e "${C_GREEN}SUCCES:${C_RESET} COOKIE_DOMAIN toegevoegd."; ((changes_made_count++)); else log_message "ERROR" "COOKIE_DOMAIN toevoegen mislukt."; echo -e "${C_RED}FOUT: Kon COOKIE_DOMAIN niet toevoegen.${C_RESET}"; cp "$backup_file_config" "$WP_CONFIG_PATH"; fi; fi; fi; echo ""
    local functions_path; if ! functions_path=$(get_active_theme_functions_path); then return 1; fi
    if grep -Fq "$COOKIE_FIX_START_MARKER" "$functions_path"; then log_message "INFO" "Cookie fix marker al in ${functions_path}."; echo -e "${C_YELLOW}INFO:${C_RESET} Cookie fix code al in ${functions_path}.";
    else local backup_file_func="${functions_path}.bak_cookie_fix.$(date +%s)"; log_message "INFO" "Backup ${functions_path} -> ${backup_file_func}."; cp "$functions_path" "$backup_file_func" || { log_message "ERROR" "Backup functions.php mislukt."; echo -e "${C_RED}FOUT: Backup functions.php mislukt.${C_RESET}"; return 1; }; echo -e "Backup: ${C_GREY}${backup_file_func}${C_RESET}";
         log_message "INFO" "Toevoegen cookie fix code aan ${functions_path}..."; if echo -e "\n${COOKIE_FIX_FUNCTIONS_CODE}\n" >> "$functions_path"; then log_message "INFO" "Cookie fix code toegevoegd."; echo -e "${C_GREEN}SUCCES:${C_RESET} Cookie fix code toegevoegd."; ((changes_made_count++)); else log_message "ERROR" "Cookie fix code toevoegen mislukt."; echo -e "${C_RED}FOUT: Kon cookie fix code niet toevoegen.${C_RESET}"; cp "$backup_file_func" "$functions_path"; fi; fi; echo ""
    if [[ $changes_made_count -eq 0 ]]; then echo -e "${C_YELLOW}Geen wijzigingen (fixes waren mogelijk al aanwezig).${C_RESET}"; else echo -e "${C_GREEN}Cookie fixes toegepast. Probeer opnieuw in te loggen.${C_RESET}"; fi
    read -p "Druk op Enter om terug te keren..."; log_message "INFO" "Cookie fix toepassen voltooid."
}

# --- Cookie Fix Ongedaan Maken Functie ---
revert_cookie_fixes() {
    log_message "INFO" "Start ongedaan maken cookie fixes..."; echo -e "\n${C_MAGENTA}--- WordPress Cookie Fix Ongedaan Maken ---${C_RESET}"; local changes_made_count=0
    if [[ ! -f "$WP_CONFIG_PATH" ]]; then log_message "ERROR" "wp-config.php niet gevonden."; echo -e "${C_RED}FOUT: ${WP_CONFIG_PATH} niet gevonden!${C_RESET}";
    else if grep -q "define('COOKIE_DOMAIN'" "$WP_CONFIG_PATH"; then local backup_file_config="${WP_CONFIG_PATH}.bak_cookie_revert.$(date +%s)"; log_message "INFO" "Backup ${WP_CONFIG_PATH} -> ${backup_file_config}."; cp "$WP_CONFIG_PATH" "$backup_file_config" || { log_message "ERROR" "Backup mislukt."; echo -e "${C_RED}FOUT: Backup mislukt.${C_RESET}"; return 1; }; echo -e "Backup: ${C_GREY}${backup_file_config}${C_RESET}";
             log_message "INFO" "Verwijderen COOKIE_DOMAIN uit ${WP_CONFIG_PATH}..."; if sed -i "\|define('COOKIE_DOMAIN', \$_SERVER\['HTTP_HOST'\] );|d" "$WP_CONFIG_PATH"; then log_message "INFO" "COOKIE_DOMAIN verwijderd."; echo -e "${C_GREEN}SUCCES:${C_RESET} COOKIE_DOMAIN verwijderd."; ((changes_made_count++)); else log_message "ERROR" "COOKIE_DOMAIN verwijderen mislukt."; echo -e "${C_RED}FOUT: Kon COOKIE_DOMAIN niet verwijderen.${C_RESET}"; cp "$backup_file_config" "$WP_CONFIG_PATH"; fi
        else log_message "INFO" "COOKIE_DOMAIN niet gevonden."; echo -e "${C_YELLOW}INFO:${C_RESET} COOKIE_DOMAIN niet in ${WP_CONFIG_PATH}."; fi; fi; echo ""
    local functions_path; if ! functions_path=$(get_active_theme_functions_path); then return 1; fi
    if grep -Fq "$COOKIE_FIX_START_MARKER" "$functions_path"; then local backup_file_func="${functions_path}.bak_cookie_revert.$(date +%s)"; log_message "INFO" "Backup ${functions_path} -> ${backup_file_func}."; cp "$functions_path" "$backup_file_func" || { log_message "ERROR" "Backup mislukt."; echo -e "${C_RED}FOUT: Backup mislukt.${C_RESET}"; return 1; }; echo -e "Backup: ${C_GREY}${backup_file_func}${C_RESET}";
         log_message "INFO" "Verwijderen cookie fix blok uit ${functions_path}..."; if sed -i "\#${COOKIE_FIX_START_MARKER}#,\#${COOKIE_FIX_END_MARKER}#d" "$functions_path"; then log_message "INFO" "Cookie fix blok verwijderd."; echo -e "${C_GREEN}SUCCES:${C_RESET} Cookie fix code blok verwijderd."; ((changes_made_count++)); else log_message "ERROR" "Cookie fix blok verwijderen mislukt."; echo -e "${C_RED}FOUT: Kon cookie fix blok niet verwijderen.${C_RESET}"; cp "$backup_file_func" "$functions_path"; fi
    else log_message "INFO" "Cookie fix marker niet gevonden."; echo -e "${C_YELLOW}INFO:${C_RESET} Cookie fix code niet in ${functions_path}."; fi; echo ""
    if [[ $changes_made_count -eq 0 ]]; then echo -e "${C_YELLOW}Geen wijzigingen teruggedraaid.${C_RESET}"; else echo -e "${C_GREEN}Cookie fixes ongedaan gemaakt.${C_RESET}"; fi
    read -p "Druk op Enter om terug te keren..."; log_message "INFO" "Cookie fix ongedaan maken voltooid."
}

# --- Multisite Schakelaar Functie ---
toggle_multisite() {
    log_message "INFO" "Start Multisite schakelaar..."
    echo -e "\n${C_MAGENTA}--- WordPress Multisite Aan/Uit Schakelen ---${C_RESET}"

    if [[ ! -f "$WP_CONFIG_PATH" ]]; then
        log_message "ERROR" "wp-config.php niet gevonden op ${WP_CONFIG_PATH}."
        echo -e "${C_RED}FOUT: Kan wp-config.php niet vinden!${C_RESET}";
        read -p "Druk op Enter om terug te keren..."; return 1;
    fi

    local current_status="unknown"; local multisite_line; multisite_line=$(grep -E "^[[:space:]]*define\( *'MULTISITE' *,.* \);" "$WP_CONFIG_PATH")

    if [[ -z "$multisite_line" ]]; then current_status="disabled"; echo -e "${C_YELLOW}INFO:${C_RESET} Geen 'MULTISITE' definitie gevonden -> Uitgeschakeld."; log_message "INFO" "MULTISITE niet gevonden, beschouwd als disabled."
    elif echo "$multisite_line" | grep -q "true"; then current_status="enabled"; echo -e "${C_YELLOW}INFO:${C_RESET} Multisite = ${C_GREEN}INGESCHAKELD${C_RESET}."; log_message "INFO" "MULTISITE = true."
    else current_status="disabled"; echo -e "${C_YELLOW}INFO:${C_RESET} Multisite = ${C_RED}UITGESCHAKELD${C_RESET}."; log_message "INFO" "MULTISITE = false/onbekend."; fi

    local action; local new_ms_value; local new_subdomain_value
    if [[ "$current_status" == "enabled" ]]; then action="UITschakelen"; new_ms_value="false"; new_subdomain_value="false"; else action="INschakelen"; new_ms_value="true"; new_subdomain_value="true"; fi

    read -p "Wilt u Multisite nu ${action}? [y/N]: " confirm
    if [[ ! "$confirm" =~ ^[Yy]$ ]]; then echo "Actie geannuleerd."; log_message "INFO" "Multisite toggle geannuleerd."; read -p "..."; return 0; fi

    local backup_file_config="${WP_CONFIG_PATH}.bak_ms_toggle.$(date +%s)"; log_message "INFO" "Backup ${WP_CONFIG_PATH} -> ${backup_file_config}."; cp "$WP_CONFIG_PATH" "$backup_file_config" || { log_message "ERROR" "Backup mislukt."; echo -e "${C_RED}FOUT: Backup mislukt!${C_RESET}"; read -p "..."; return 1; }; echo -e "Backup: ${C_GREY}${backup_file_config}${C_RESET}"

    local sed_success=true
    log_message "INFO" "Instellen MULTISITE -> ${new_ms_value}..."; echo -e "Aanpassen ${C_CYAN}MULTISITE${C_RESET} -> ${new_ms_value}..."
    if grep -q "define( *'MULTISITE' *," "$WP_CONFIG_PATH"; then
         if ! sed -i "s|^[[:space:];]*define( *'MULTISITE' *,.*);|define( 'MULTISITE', ${new_ms_value} );|" "$WP_CONFIG_PATH"; then log_message "ERROR" "Sed MULTISITE aanpassen mislukt."; echo -e "${C_RED}FOUT.${C_RESET}"; sed_success=false; fi
    elif [[ "$new_ms_value" == "true" ]]; then log_message "INFO" "MULTISITE toevoegen..."; local stop_editing_line="/* That's all, stop editing!"; if ! sed -i "/$(echo "$stop_editing_line" | sed 's:[/*]:\\&:g')/i define( 'MULTISITE', true );" "$WP_CONFIG_PATH"; then log_message "ERROR" "Sed MULTISITE toevoegen mislukt."; echo -e "${C_RED}FOUT.${C_RESET}"; sed_success=false; fi; fi

    if $sed_success; then
        log_message "INFO" "Instellen SUBDOMAIN_INSTALL -> ${new_subdomain_value}..."; echo -e "Aanpassen ${C_CYAN}SUBDOMAIN_INSTALL${C_RESET} -> ${new_subdomain_value}..."
         if grep -q "define( *'SUBDOMAIN_INSTALL' *," "$WP_CONFIG_PATH"; then
             if ! sed -i "s|^[[:space:];]*define( *'SUBDOMAIN_INSTALL' *,.*);|define( 'SUBDOMAIN_INSTALL', ${new_subdomain_value} );|" "$WP_CONFIG_PATH"; then log_message "ERROR" "Sed SUBDOMAIN_INSTALL aanpassen mislukt."; echo -e "${C_RED}FOUT.${C_RESET}"; sed_success=false; fi
         elif [[ "$new_subdomain_value" == "true" ]]; then log_message "INFO" "SUBDOMAIN_INSTALL toevoegen..."; local stop_editing_line="/* That's all, stop editing!"; if ! sed -i "/$(echo "$stop_editing_line" | sed 's:[/*]:\\&:g')/i define( 'SUBDOMAIN_INSTALL', true );" "$WP_CONFIG_PATH"; then log_message "ERROR" "Sed SUBDOMAIN_INSTALL toevoegen mislukt."; echo -e "${C_RED}FOUT.${C_RESET}"; sed_success=false; fi; fi
    fi

    if $sed_success; then log_message "INFO" "Multisite status gewijzigd naar ${new_ms_value}."; echo -e "${C_GREEN}SUCCES:${C_RESET} Multisite is nu ${action}d."; echo -e "${C_YELLOW}Let op:${C_RESET} Meer stappen (bv. Nginx/htaccess) kunnen nodig zijn.";
    else log_message "ERROR" "Multisite wijzigen mislukt. Backup terug."; echo -e "${C_RED}FOUT: Kon niet aanpassen. Backup teruggezet.${C_RESET}"; cp "$backup_file_config" "$WP_CONFIG_PATH"; fi

    read -p "Druk op Enter om terug te keren..."; log_message "INFO" "Multisite schakelaar voltooid."
}


# --- Service Herstart Functie ---
restart_services() {
    log_message "INFO" "Start herstarten van services..."
    echo -e "\n${C_YELLOW}--- Herstart Services ---${C_RESET}"; local all_restarted=true
    echo -e "Herstarten ${C_CYAN}Nginx${C_RESET}..."; if ! run_command "Herstart Nginx" systemctl restart nginx.service; then echo -e "${C_RED} FOUT.${C_RESET}"; echo -e "${C_YELLOW} Diagnose: status/journalctl${C_RESET}"; all_restarted=false; fi; sleep 0.5
    echo -e "Herstarten ${C_CYAN}MariaDB${C_RESET}..."; if ! run_command "Herstart MariaDB" systemctl restart mariadb.service; then echo -e "${C_RED} FOUT.${C_RESET}"; echo -e "${C_YELLOW} Diagnose: status/journalctl${C_RESET}"; all_restarted=false; fi; sleep 0.5
    echo -e "Herstarten ${C_CYAN}PHP-FPM${C_RESET} (${C_GREY}cache flush${C_RESET})..."; if ! run_command "Herstart PHP-FPM" systemctl restart php-fpm.service; then echo -e "${C_RED} FOUT.${C_RESET}"; echo -e "${C_YELLOW} Diagnose: status/journalctl${C_RESET}"; all_restarted=false; else log_message "INFO" "PHP-FPM OK; Cache geleegd."; fi; sleep 0.5
    echo ""; if [[ "$all_restarted" == true ]]; then echo -e "${C_GREEN}Alle services herstart.${C_RESET}"; log_message "INFO" "Services herstart OK."; else echo -e "${C_YELLOW}Niet alle services herstart.${C_RESET}"; log_message "WARN" "Niet alle services herstart."; fi
    echo ""; read -p "Druk op Enter..."; log_message "INFO" "Service herstart voltooid."
}


# --- Versie Informatie Functie ---
display_versions() {
    log_message "INFO" "Start versie info..."; echo -e "\n${C_CYAN}--- Geïnstalleerde Versies ---${C_RESET}"
    echo -en "${C_WHITE}Nginx:${C_RESET}   "; if nginx_version=$(nginx -v 2>&1); then echo -e "${C_GREEN}${nginx_version}${C_RESET}"; log_message "INFO" "Nginx: ${nginx_version}"; else echo -e "${C_RED}Error.${C_RESET}"; log_message "ERROR" "Nginx versie FAILED."; fi
    echo -en "${C_WHITE}MariaDB:${C_RESET} "; if mariadb_version=$(mysql --version); then echo -e "${C_GREEN}${mariadb_version}${C_RESET}"; log_message "INFO" "MariaDB: ${mariadb_version}"; else echo -e "${C_RED}Error.${C_RESET}"; log_message "ERROR" "MariaDB versie FAILED."; fi
    echo -en "${C_WHITE}PHP:${C_RESET}     "; if php_version=$(php -v 2>/dev/null | head -n 1); then echo -e "${C_GREEN}${php_version}${C_RESET}"; log_message "INFO" "PHP: ${php_version}"; else echo -e "${C_RED}Error.${C_RESET}"; log_message "ERROR" "PHP versie FAILED."; fi
    echo ""; read -p "Druk op Enter..."; log_message "INFO" "Versie info voltooid."
}

# --- PHP Instellingen Aanpassen Functie ---
adjust_php_settings() {
    log_message "INFO" "Start PHP instellingen aanpassen..."; echo -e "\n${C_MAGENTA}--- PHP Instellingen Aanpassen (${PHP_INI_PATH}) ---${C_RESET}"
    if [[ ! -f "$PHP_INI_PATH" ]]; then log_message "ERROR" "${PHP_INI_PATH} niet gevonden."; echo -e "${C_RED}FOUT: ${PHP_INI_PATH} niet gevonden!${C_RESET}"; read -p "..."; return 1; fi
    local backup_file="${PHP_INI_PATH}.bak.$(date +%s)"; log_message "INFO" "Backup -> ${backup_file}"; cp "$PHP_INI_PATH" "$backup_file" || { log_message "ERROR" "Backup mislukt."; echo -e "${C_RED}FOUT: Backup mislukt!${C_RESET}"; read -p "..."; return 1; }
    local setting_changed=false; echo -e "Backup: ${C_GREY}${backup_file}${C_RESET}"; echo -e "Pas aan (Enter = behouden):"; echo ""
    for setting_name in "${PHP_SETTINGS_TO_ADJUST[@]}"; do current_value=$(grep -Ei "^[; ]*${setting_name}[ ]*=" "$PHP_INI_PATH" | tail -n 1 | sed -E 's/^[; ]*[^=]+=[ ]*//; s/[; ].*$//'); [[ -z "$current_value" ]] && current_value="<leeg>"; echo -e "${C_WHITE}${setting_name}:${C_RESET} (Huidig: ${C_YELLOW}${current_value}${C_RESET})"; read -p "  Nieuwe waarde: " new_value
        if [[ -n "$new_value" ]]; then sed -i -E "/^[; ]*${setting_name}[ ]*=/Id" "$PHP_INI_PATH"; if grep -q '^\s*\[PHP\]' "$PHP_INI_PATH"; then sed -i "/^\s*\[PHP\]/a ${setting_name} = ${new_value}" "$PHP_INI_PATH"; else echo "${setting_name} = ${new_value}" >> "$PHP_INI_PATH"; fi; log_message "INFO" "'${setting_name}' -> '${new_value}'."; echo -e "  -> ${C_GREEN}OK: ${new_value}${C_RESET}"; setting_changed=true; else echo -e "  -> Behoud." ; fi; echo "" ; done
    if [[ "$setting_changed" == true ]]; then echo -e "${C_YELLOW}Wijzigingen opgeslagen.${C_RESET}"; echo -e "${C_YELLOW}PHP-FPM herstarten...${C_RESET}"; if run_command "PHP-FPM herstarten" systemctl restart php-fpm; then echo -e "${C_GREEN}OK.${C_RESET}"; else echo -e "${C_RED}FOUT!${C_RESET}"; echo -e "${C_YELLOW}Check status/logs.${C_RESET}"; fi; else echo -e "Geen wijzigingen."; log_message "INFO" "Geen PHP instellingen aangepast."; fi
    echo ""; read -p "Druk op Enter..."; log_message "INFO" "PHP instellingen aanpassen voltooid."
}


# --- PHP Extensie Beheer Functie ---
manage_php_extensions() {
    log_message "INFO" "Start PHP extensie beheer..."; echo -e "\n${C_MAGENTA}--- PHP Extensie Beheer (${PHP_EXTENSIONS_DIR}) ---${C_RESET}"
    if [[ ! -d "$PHP_EXTENSIONS_DIR" ]]; then log_message "ERROR" "${PHP_EXTENSIONS_DIR} niet gevonden."; echo -e "${C_RED}FOUT: Map ${PHP_EXTENSIONS_DIR} niet gevonden!${C_RESET}"; read -p "..."; return 1; fi
    local changes_made=false; local loaded_modules; loaded_modules=$(php -m 2>/dev/null | grep -v '\[PHP Modules\]' | grep -v '\[Zend Modules\]' | tr '[:upper:]' '[:lower:]' | sort | uniq)
    if [[ -z "$loaded_modules" ]]; then log_message "ERROR" "'php -m' mislukt."; echo -e "${C_RED}FOUT: Kon 'php -m' niet uitvoeren.${C_RESET}"; read -p "..."; return 1; fi; log_message "INFO" "Geladen modules:\n${loaded_modules}"
    while true; do clear; echo -e "\n${C_MAGENTA}--- PHP Extensie Beheer (${PHP_EXTENSIONS_DIR}) ---${C_RESET}"; declare -a ini_files; declare -a statuses; declare -a display_names; declare -a toggleable_flags; local counter=1
        echo -e "\n${C_WHITE}Gevonden .ini bestanden & Status:${C_RESET}"; echo -e "${C_GREY}${BORDER_SINGLE}${C_RESET}"
        while IFS= read -r file; do local filename=$(basename "$file"); local clean_display_name=$(echo "$filename" | sed -E 's/^[0-9]+-//; s/\.ini$//'); local module_name_lc=$(echo "$clean_display_name" | tr '[:upper:]' '[:lower:]'); local current_status="Unknown"; local status_color=$C_YELLOW; local status_symbol="[?]"; local toggleable="no"; local has_active_ext_line=false; local has_inactive_ext_line=false
            if grep -Eq '^[[:space:]]*extension=[^;]*\.so' "$file"; then has_active_ext_line=true; fi; if grep -Eq '^[[:space:]]*;+[[:space:]]*extension=[^;]*\.so' "$file"; then has_inactive_ext_line=true; fi
            if echo "${loaded_modules}" | grep -qw "$module_name_lc"; then current_status="Enabled"; status_color=$C_GREEN; status_symbol="[${C_GREEN}✓${C_RESET}]"; if $has_active_ext_line; then toggleable="yes"; fi; if ! $has_active_ext_line && ! $has_inactive_ext_line; then current_status="Enabled ${C_GREY}(Auto)${status_color}"; fi
            else if $has_inactive_ext_line; then current_status="Disabled"; status_color=$C_RED; status_symbol="[ ]"; toggleable="yes"; else current_status="Unknown"; status_color=$C_YELLOW; status_symbol="[${C_YELLOW}?${C_RESET}]"; toggleable="no"; fi; fi
            if grep -Eq '^[[:space:]]*;*[[:space:]]*zend_extension=' "$file"; then if echo "$filename" | grep -q 'opcache'; then current_status="Enabled ${C_GREY}(Zend)${C_GREEN}"; status_color=$C_GREEN; status_symbol="[${C_GREEN}Z${C_RESET}]"; else current_status="Unknown ${C_GREY}(Zend)${C_YELLOW}"; status_color=$C_YELLOW; status_symbol="[${C_YELLOW}Z${C_RESET}]"; fi; toggleable="no"; fi
            local toggle_indicator=" "; if [[ "$toggleable" == "yes" ]]; then toggle_indicator="${C_YELLOW}*${C_RESET}"; fi
            printf " %-4s %-3s %-20s %-20s %-1s %s\n" "$counter." "$status_symbol" "$clean_display_name" "(${status_color}${current_status}${C_RESET})" "$toggle_indicator" "${C_GREY}${filename}${C_RESET}"
            ini_files+=("$file"); statuses+=("$current_status"); display_names+=("$clean_display_name"); toggleable_flags+=("$toggleable"); ((counter++)); done < <(find "$PHP_EXTENSIONS_DIR" -maxdepth 1 -type f -name '*.ini' | sort); echo -e "${C_GREY}${BORDER_SINGLE}${C_RESET}"
        local num_extensions=${#ini_files[@]}; if [[ $num_extensions -eq 0 ]]; then echo -e "\n${C_YELLOW}Geen .ini bestanden gevonden.${C_RESET}"; break; fi
        echo -e "\nNummer kiezen om status te ${C_YELLOW}wisselen${C_RESET} (alleen met ${C_YELLOW}*${C_RESET})."; echo -e "'${C_GREEN}0${C_RESET}' = Opslaan & Afsluiten."; echo -e "'${C_RED}q${C_RESET}' = Afsluiten zonder opslaan."
        read -p "$(echo -e ${PROMPT_COLOR}"Uw keuze [1-${num_extensions}, 0, q]: "${C_RESET})" choice
        case $choice in q|Q) echo "Afsluiten."; log_message "INFO" "PHP ext beheer afgebroken."; break ;; 0) echo "Opslaan & afsluiten."; if [[ "$changes_made" == true ]]; then echo -e "${C_YELLOW}PHP-FPM herstarten...${C_RESET}"; if run_command "PHP-FPM herstarten" systemctl restart php-fpm; then echo -e "${C_GREEN}OK.${C_RESET}"; else echo -e "${C_RED}FOUT!${C_RESET}"; echo -e "${C_YELLOW}Check status/logs.${C_RESET}"; fi; else echo "Geen wijzigingen."; fi; log_message "INFO" "PHP ext beheer voltooid."; break ;; *)
            if [[ "$choice" =~ ^[0-9]+$ ]] && [[ "$choice" -ge 1 ]] && [[ "$choice" -le $num_extensions ]]; then local index=$((choice - 1)); local target_file="${ini_files[$index]}"; local current_status_raw="${statuses[$index]}"; local display_name="${display_names[$index]}"; local toggleable="${toggleable_flags[$index]}"; local base_status; if [[ $current_status_raw == *"Enabled"* ]]; then base_status="Enabled"; elif [[ $current_status_raw == *"Disabled"* ]]; then base_status="Disabled"; else base_status="Unknown"; fi
                if [[ "$toggleable" != "yes" ]]; then echo -e "\n${C_YELLOW}Kan '${display_name}' niet wisselen.${C_RESET}"; echo -e "${C_GREY}(Niet wisselbaar via menu).${C_RESET}"; sleep 3; continue; fi
                local backup_file_ext="${target_file}.bak_ext.$(date +%s)"; log_message "INFO" "Backup ${target_file} -> ${backup_file_ext}"; cp "$target_file" "$backup_file_ext" || { log_message "ERROR" "Backup FAILED."; echo -e "\n${C_RED}FOUT: Backup mislukt!${C_RESET}"; sleep 3; continue; }
                echo -e "Backup: ${C_GREY}${backup_file_ext}${C_RESET}"; echo -e "Wisselen status ${C_BLUE}${display_name}${C_RESET}..."
                if [[ "$base_status" == "Enabled" ]]; then log_message "INFO" "Uitschakelen in ${target_file}"; if sed -i -E '0,/^[[:space:]]*extension=.*\.so/{s|^([[:space:]]*)(extension=.*\.so.*)|;\1\2|}' "$target_file"; then echo -e " -> Nu ${C_RED}uitgeschakeld${C_RESET}."; changes_made=true; else echo -e " ${C_RED}FOUT uitschakelen.${C_RESET}"; log_message "ERROR" "sed uitschakelen FAILED."; fi
                else log_message "INFO" "Inschakelen in ${target_file}"; if sed -i -E '0,/^[[:space:]]*;+[[:space:]]*extension=.*\.so/{ s/^[[:space:]]*;+[[:space:]]*// }' "$target_file"; then if grep -Eq '^[[:space:]]*extension=.*\.so' "$target_file"; then echo -e " -> Nu ${C_GREEN}ingeschakeld${C_RESET}."; changes_made=true; else echo -e " ${C_RED}FOUT: Kon niet uncommenten.${C_RESET}"; log_message "ERROR" "sed uncomment FAILED."; cp "$backup_file_ext" "$target_file"; echo -e " -> Backup terug."; fi; else echo -e " ${C_RED}FOUT inschakelen (sed error).${C_RESET}"; log_message "ERROR" "sed inschakelen FAILED."; cp "$backup_file_ext" "$target_file"; echo -e " -> Backup terug."; fi; fi; sleep 1.5
            else echo -e "\n${C_RED}Ongeldige keuze '${choice}'.${C_RESET}"; sleep 2; fi;;
        esac; done; echo ""
}


# --- Gezondheidscontrole Functie ---
health_check() {
    log_message "INFO" "Start Gezondheidscontrole..."
    echo -e "\n${C_BLUE}--- Start Gezondheidscontrole ---${C_RESET}"; local all_ok=true; local issues_found=0; local services=("nginx" "mariadb" "php-fpm")
    echo -n "[Check] Nginx log map: "; if [ ! -d "/var/log/nginx" ]; then echo -e "${C_YELLOW}MIS.${C_RESET}"; log_message "WARN" "Nginx log map MIS."; echo -e "${C_YELLOW} -> Maak aan...${C_RESET}"; if run_command "Maak /var/log/nginx" mkdir -p /var/log/nginx; then echo -e "${C_GREEN}OK.${C_RESET}"; log_message "INFO" "Map OK."; else echo -e "${C_RED}FAIL.${C_RESET}"; log_message "ERROR" "Map FAIL."; all_ok=false; issues_found=$((issues_found + 1)); fi; else echo -e "${C_GREEN}OK${C_RESET}"; log_message "INFO" "Nginx log map OK."; fi
    echo -n "[Check] PHP-FPM log map: "; if [ ! -d "/var/log/php-fpm" ]; then echo -e "${C_YELLOW}MIS.${C_RESET}"; log_message "WARN" "PHP-FPM log map MIS."; echo -e "${C_YELLOW} -> Maak aan...${C_RESET}"; if run_command "Maak /var/log/php-fpm" mkdir -p /var/log/php-fpm; then echo -e "${C_GREEN}OK.${C_RESET}"; log_message "INFO" "Map OK."; local fpm_user="nginx"; run_command "Perms /var/log/php-fpm" chown "${fpm_user}:${fpm_user}" /var/log/php-fpm || log_message "WARN" "Perms FAIL."; else echo -e "${C_RED}FAIL.${C_RESET}"; log_message "ERROR" "Map FAIL."; all_ok=false; issues_found=$((issues_found + 1)); fi; else echo -e "${C_GREEN}OK${C_RESET}"; log_message "INFO" "PHP-FPM log map OK."; fi
    # Controleer services met verbeterde structuur
    for service in "${services[@]}"; do
        local service_name="${service}.service"
        echo -n "[Service] ${service_name}: Enabled? "
        if systemctl is-enabled --quiet "${service_name}"; then echo -e "${C_GREEN}Ja${C_RESET}"; log_message "INFO" "${service_name} enabled."
        else echo -e "${C_YELLOW}Nee${C_RESET}"; log_message "WARN" "${service_name} NIET enabled."; fi
        echo -n "[Service] ${service_name}: Actief? "
        if systemctl is-active --quiet "${service_name}"; then echo -e "${C_GREEN}Ja${C_RESET}"; log_message "INFO" "${service_name} actief."
        else echo -e "${C_RED}Nee${C_RESET}"; log_message "WARN" "${service_name} NIET actief."
            local can_attempt_restart=true
            if [[ "$service" == "nginx" && ! -d "/var/log/nginx" ]]; then can_attempt_restart=false; log_message "WARN" "Herstart ${service_name} skip: log map mist."
            elif [[ "$service" == "php-fpm" && ! -d "/var/log/php-fpm" ]]; then can_attempt_restart=false; log_message "WARN" "Herstart ${service_name} skip: log map mist."; fi
            if [[ "$can_attempt_restart" == true ]]; then echo -e "${C_YELLOW} -> Herstart...${C_RESET}"; if run_command "Herstart ${service_name}" --suppress systemctl restart "${service_name}"; then echo -e "${C_GREEN}OK.${C_RESET}"; log_message "INFO" "${service_name} herstart OK."
                else echo -e "${C_RED}FAIL.${C_RESET}"; log_message "ERROR" "${service_name} herstart FAILED."; all_ok=false; issues_found=$((issues_found + 1)); echo -e "${C_YELLOW}  Diagnose: ${C_CYAN}systemctl status ${service_name} && journalctl -xeu ${service_name}${C_RESET}"; fi
            else all_ok=false; if [[ $can_attempt_restart == false ]]; then : else issues_found=$((issues_found + 1)); fi; echo -e "${C_YELLOW} -> Herstart overgeslagen.${C_RESET}"; fi
        fi
    done
    echo -n "[Config] Nginx syntax: "; if run_command "Nginx test" --suppress nginx -t; then echo -e "${C_GREEN}OK${C_RESET}"; log_message "INFO" "Nginx config OK."; else echo -e "${C_RED}FAIL${C_RESET}"; log_message "ERROR" "Nginx config FAILED."; echo -e "${C_RED} -> Fout! Check: ${C_CYAN}sudo nginx -t${C_RESET}"; all_ok=false; issues_found=$((issues_found + 1)); fi
    echo -n "[Runtime] PHP CLI: "; if run_command "PHP check" --suppress php -v; then php_version_output=$(php -v 2>/dev/null | head -n 1); echo -e "${C_GREEN}OK (${php_version_output})${C_RESET}"; log_message "INFO" "PHP CLI OK (${php_version_output})."; else echo -e "${C_RED}FAIL${C_RESET}"; log_message "ERROR" "PHP CLI FAIL."; echo -e "${C_RED} -> Fout!${C_RESET}"; all_ok=false; issues_found=$((issues_found + 1)); fi
    echo -n "[WordPress] Map (${WORDPRESS_ROOT}): "; if [[ -d "$WORDPRESS_ROOT" ]] && [[ -n "$(ls -A $WORDPRESS_ROOT)" ]]; then echo -e "${C_GREEN}OK${C_RESET}"; log_message "INFO" "WP map OK."; echo -n "[WordPress] WP-CLI Check: "; if [[ -f "$WP_CLI_PATH" ]]; then local wp_cli_user="nginx"; if ! id "$wp_cli_user" &>/dev/null; then wp_cli_user="root"; fi; if run_command "WP-CLI core check" --suppress sudo -u "$wp_cli_user" "$WP_CLI_PATH" core is-installed --path="$WORDPRESS_ROOT" --allow-root; then echo -e "${C_GREEN}OK${C_RESET}"; log_message "INFO" "WP-CLI check OK."; if [[ -n "${WP_SITE_URL:-}" ]]; then echo -e "[WordPress] ${C_BLUE}Admin URL:${C_RESET} ${C_CYAN}${WP_SITE_URL}/wp-admin/${C_RESET}"; else echo -e "[WordPress] ${C_YELLOW}Admin URL: N/A${C_RESET}"; log_message "WARN" "WP_SITE_URL leeg."; fi; else echo -e "${C_RED}FAIL${C_RESET}"; log_message "ERROR" "WP-CLI check FAILED."; echo -e "${C_RED} -> Fout! Check: ${C_CYAN}sudo -u ${wp_cli_user} ${WP_CLI_PATH} core is-installed --path=${WORDPRESS_ROOT} --allow-root --debug${C_RESET}"; all_ok=false; issues_found=$((issues_found + 1)); fi; else echo -e "${C_YELLOW}MISSING${C_RESET}"; log_message "WARN" "WP-CLI niet gevonden."; fi; else echo -e "${C_RED}FAIL${C_RESET}"; log_message "ERROR" "WP map niet gevonden/leeg."; echo -e "${C_RED} -> Fout!${C_RESET}"; all_ok=false; issues_found=$((issues_found + 1)); fi
    echo -e "\n${C_BLUE}--- Gezondheidscontrole Voltooid ---${C_RESET}"; if [[ "$all_ok" == true ]]; then echo -e "${C_GREEN}Alles lijkt OK.${C_RESET}"; log_message "INFO" "Health Check: OK."; else if [[ $issues_found -eq 0 && "$all_ok" == false ]]; then issues_found=1; log_message "WARN" "Health: issues=0, all_ok=false"; fi; if [[ $issues_found -gt 0 ]]; then echo -e "${C_YELLOW}${issues_found} probleem(en) gevonden.${C_RESET}"; log_message "WARN" "Health Check: ${issues_found} probleem."; else echo -e "${C_YELLOW}Problemen gevonden & mogelijk opgelost.${C_RESET}"; log_message "WARN" "Health Check: Problemen mogelijk opgelost."; fi; fi
    echo ""; read -p "Druk op Enter om terug te keren..."
}

# --- Subfunctie voor MariaDB Optimalisatie ---
optimize_mariadb_config() {
    log_message "INFO" "Optimaliseren MariaDB config (${MARIADB_OPT_CONF})..."; local INNODB_BUFFER_POOL="512M"; local INNODB_LOG_FILE_SIZE="256M"; cat <<EOF > "$MARIADB_OPT_CONF"; # WordPress Optimized MariaDB settings by script\n[mysqld]\nquery_cache_type = 0; query_cache_size = 0\ninnodb_buffer_pool_size = ${INNODB_BUFFER_POOL}\ninnodb_log_file_size = ${INNODB_LOG_FILE_SIZE}\ninnodb_flush_method = O_DIRECT\nEOF
    run_command "Permissies MariaDB opt config" chown root:root "$MARIADB_OPT_CONF" && chmod 644 "$MARIADB_OPT_CONF" || return 1; log_message "INFO" "MariaDB opt config OK."; run_command "MariaDB herstarten" systemctl restart mariadb || { log_message "ERROR" "MariaDB herstart FAILED."; return 1; }; log_message "INFO" "MariaDB herstart OK."; return 0
}

# --- Subfunctie voor Database Setup ---
setup_database() {
    log_message "INFO" "Start DB setup..."; sleep 2; local target_password; local password_source_msg; if [[ "$USE_CUSTOM_DB_ROOT_PASSWORD" == true ]]; then target_password="$CUSTOM_DB_ROOT_PASSWORD"; password_source_msg="AANGEPAST ww"; else target_password="$MARIADB_ROOT_PASSWORD_DEFAULT"; password_source_msg="'root' (ONVEILIG!)"; fi; ACTIVE_DB_ROOT_PASSWORD="$target_password"; log_message "INFO" "DB root ww instellen: ${password_source_msg}"; if ! mysqladmin -u root password "${target_password}" >> "$LOG_FILE" 2>&1 ; then log_message "WARN" "Init ww set mislukt, probeert ALTER..."; if ! mysql -u root -e "ALTER USER 'root'@'localhost' IDENTIFIED BY '${target_password}'; FLUSH PRIVILEGES;" >> "$LOG_FILE" 2>&1 && ! mysql -u root -p"${MARIADB_ROOT_PASSWORD_DEFAULT}" -e "ALTER USER 'root'@'localhost' IDENTIFIED BY '${target_password}'; FLUSH PRIVILEGES;" >> "$LOG_FILE" 2>&1; then if ! run_command "DB root ww (poging 3)" mysql -u root -p"${target_password}" -e "ALTER USER 'root'@'localhost' IDENTIFIED BY '${target_password}'; FLUSH PRIVILEGES;"; then log_message "ERROR" "DB root ww FAILED."; return 1; fi; fi; fi; log_message "INFO" "DB root ww OK."; run_mysql_command "WP DB aanmaken" "CREATE DATABASE IF NOT EXISTS \`${WORDPRESS_DB_NAME}\` DEFAULT CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;" || return 1; log_message "INFO" "WP DB user '${WORDPRESS_DB_USER}'..."; run_mysql_command "WP DB user aanmaken" "CREATE USER IF NOT EXISTS '${WORDPRESS_DB_USER}'@'localhost' IDENTIFIED BY '${WORDPRESS_DB_PASSWORD}';" || return 1; run_mysql_command "WP DB rechten" "GRANT ALL PRIVILEGES ON \`${WORDPRESS_DB_NAME}\`.* TO '${WORDPRESS_DB_USER}'@'localhost';" || return 1; run_mysql_command "Flush privileges" "FLUSH PRIVILEGES;" || return 1; log_message "INFO" "DB config OK."
}
# --- Subfunctie voor WP-CLI installatie ---
install_wp_cli() {
    log_message "INFO" "Install/Update WP-CLI..."; if [ -f "$WP_CLI_PATH" ]; then log_message "INFO" "WP-CLI > Update..."; chown root:root "$WP_CLI_PATH" || true; run_command "WP-CLI bijwerken" "$WP_CLI_PATH" cli update --yes --allow-root || log_message "WARN" "WP-CLI update FAILED."; else run_command "WP-CLI download" curl -fLo /tmp/wp-cli.phar https://raw.githubusercontent.com/wp-cli/builds/gh-pages/phar/wp-cli.phar || return 1; run_command "WP-CLI chmod" chmod +x /tmp/wp-cli.phar || return 1; run_command "WP-CLI move" mv /tmp/wp-cli.phar "$WP_CLI_PATH" || return 1; fi; run_command "WP-CLI check" "$WP_CLI_PATH" --info --allow-root || return 1; log_message "INFO" "WP-CLI OK."
}
# --- Subfunctie voor PHP & OPcache Optimalisatie ---
optimize_php_config() {
    log_message "INFO" "PHP config optimaliseren (${PHP_INI_PATH})..."; if [[ ! -f "$PHP_INI_PATH" ]]; then log_message "ERROR" "${PHP_INI_PATH} niet gevonden!"; return 1; fi; cp "$PHP_INI_PATH" "${PHP_INI_PATH}.bak.$(date +%s)"; run_command "PHP: memory_limit" sed -i "s/^\s*memory_limit\s*=.*/memory_limit = ${PHP_MEMORY_LIMIT}/" "$PHP_INI_PATH" || log_message "WARN" "...FAILED."; run_command "PHP: upload_max_filesize" sed -i "s/^\s*upload_max_filesize\s*=.*/upload_max_filesize = ${PHP_UPLOAD_MAX_FILESIZE}/" "$PHP_INI_PATH" || log_message "WARN" "...FAILED."; run_command "PHP: post_max_size" sed -i "s/^\s*post_max_size\s*=.*/post_max_size = ${PHP_POST_MAX_SIZE}/" "$PHP_INI_PATH" || log_message "WARN" "...FAILED."; run_command "PHP: max_execution_time" sed -i "s/^\s*max_execution_time\s*=.*/max_execution_time = ${PHP_MAX_EXECUTION_TIME}/" "$PHP_INI_PATH" || log_message "WARN" "...FAILED."
    log_message "INFO" "OPcache config (${PHP_OPCACHE_CONF_PATH})..."; cat <<EOF > "$PHP_OPCACHE_CONF_PATH"; ; Optimized OPcache by script\nopcache.enable=1; opcache.enable_cli=1; opcache.memory_consumption=192\nopcache.interned_strings_buffer=16; opcache.max_accelerated_files=12000\nopcache.revalidate_freq=2; opcache.validate_timestamps=1; opcache.save_comments=1\nEOF; run_command "Perms OPcache" chown root:root "$PHP_OPCACHE_CONF_PATH" && chmod 644 "$PHP_OPCACHE_CONF_PATH" || log_message "WARN" "...FAILED.";
    log_message "INFO" "APCu config (${PHP_APCU_CONF_PATH})..."; if [[ ! -f "$PHP_APCU_CONF_PATH" ]] || ! grep -q "apc.enabled" "$PHP_APCU_CONF_PATH"; then if [[ ! -f "$PHP_APCU_CONF_PATH" ]]; then cat <<EOF > "$PHP_APCU_CONF_PATH"; ; Basic APCu by script\nextension=apcu.so\napc.enabled=1; apc.shm_size=128M; apc.enable_cli=1\nEOF; run_command "Perms APCu" chown root:root "$PHP_APCU_CONF_PATH" && chmod 644 "$PHP_APCU_CONF_PATH" || log_message "WARN" "...FAILED."; log_message "INFO" "APCu config OK."; else echo -e "\n; Added by script\napc.enabled=1\napc.shm_size=128M\napc.enable_cli=1" >> "$PHP_APCU_CONF_PATH"; log_message "INFO" "APCu settings OK."; fi; else log_message "INFO" "APCu lijkt OK."; sed -i -E 's/^[; ]*(apc.enabled[ ]*=).*/\11/' "$PHP_APCU_CONF_PATH"; fi; log_message "INFO" "PHP configs OK."
}
# --- Subfunctie voor automatische WordPress Multisite installatie ---
install_wordpress_multisite_auto() {
    log_message "INFO" "Start WP Multisite install..."; if ! command -v "$WP_CLI_PATH" &> /dev/null; then log_message "ERROR" "WP-CLI niet gevonden."; return 1; fi
    log_message "INFO" "wp-config genereren..."; run_command "wp config create" sudo -u nginx "$WP_CLI_PATH" config create --path="${WORDPRESS_ROOT}" --dbname="$WORDPRESS_DB_NAME" --dbuser="$WORDPRESS_DB_USER" --dbpass="$WORDPRESS_DB_PASSWORD" --dbhost="localhost" --allow-root --skip-check --force || return 1
    log_message "INFO" "WP_ALLOW_MULTISITE..."; run_command "wp config set WP_ALLOW_MULTISITE" sudo -u nginx "$WP_CLI_PATH" config set WP_ALLOW_MULTISITE true --raw --path="${WORDPRESS_ROOT}" --anchor="/* That's all, stop editing!" || return 1
    log_message "INFO" "WP core multisite-install..."; if ! run_command "wp core multisite-install" sudo -u nginx "$WP_CLI_PATH" core multisite-install --path="${WORDPRESS_ROOT}" --url="${WP_SITE_URL}" --title="${WP_SITE_TITLE}" --admin_user="${CUSTOM_WP_ADMIN_USER}" --admin_password="${CUSTOM_WP_ADMIN_PASSWORD}" --admin_email="${WP_ADMIN_EMAIL}" --subdomains=0 --allow-root --skip-email --skip-config; then log_message "ERROR" "WP core multisite install FAILED."; return 1; fi
    log_message "INFO" "WP_CACHE constant (APCu)..."; run_command "wp config set WP_CACHE" sudo -u nginx "$WP_CLI_PATH" config set WP_CACHE true --raw --path="${WORDPRESS_ROOT}" --anchor="/* That's all, stop editing!" || return 1
    log_message "INFO" "WP_CACHE OK. Activeer APCu plugin!"; log_message "INFO" "WP Multisite install OK."
}

# --- Hoofdfunctie Installatie ---
install_lemp_wp() {
    local db_setup_choice; while true; do echo ""; echo -e "${C_YELLOW}--- Keuze DB Root WW ---${C_RESET}"; echo " A. Standaard ('root' - ONVEILIG!)"; echo " B. Aangepast (Aanbevolen)"; echo ""; read -p " Keuze [A/B]: " db_setup_choice; case $db_setup_choice in a|A) USE_CUSTOM_DB_ROOT_PASSWORD=false; ACTIVE_DB_ROOT_PASSWORD="$MARIADB_ROOT_PASSWORD_DEFAULT"; log_message "WARN" "Keuze: Standaard DB ww."; break ;; b|B) get_custom_db_root_password; ACTIVE_DB_ROOT_PASSWORD="$CUSTOM_DB_ROOT_PASSWORD"; log_message "INFO" "Keuze: Aangepast DB ww."; break ;; *) echo -e "${C_RED}Ongeldig.${C_RESET}"; ;; esac; done
    log_message "INFO" "================ Start Installatie (MS + APCu) ================"; get_custom_wp_credentials
    run_command "Update systeem" dnf update -y || exit 1; log_message "INFO" "Installatie packages..."; run_command "DNF install packages" dnf install -y "${CORE_UTILS[@]}" "${OTHER_PACKAGES[@]}" || exit 1
    log_message "INFO" "Remi repo..."; if ! run_command "Remi release" dnf install -y --nogpgcheck https://rpms.remirepo.net/fedora/remi-release-$(rpm -E %fedora).rpm; then log_message "WARN" "Remi FAILED."; else log_message "INFO" "Remi OK."; fi
    log_message "INFO" "WP DB ww gen..."; WORDPRESS_DB_PASSWORD=$(openssl rand -base64 12); if [[ -z "$WORDPRESS_DB_PASSWORD" ]]; then log_message "ERROR" "WW gen FAILED."; exit 1; fi
    log_message "INFO" "PHP module stream..."; if ! run_command "Enable PHP ${PHP_MODULE_STREAM}" dnf module enable "${PHP_MODULE_STREAM}" -y; then log_message "WARN" "Enable PHP FAILED."; fi
    run_command "Nginx install" dnf install -y nginx || exit 1; run_command "Nginx enable" systemctl enable nginx || exit 1
    run_command "Firewalld start" systemctl start firewalld || log_message "WARN" "FW start FAILED."; run_command "Firewalld enable" systemctl enable firewalld || exit 1; run_command "FW HTTP" firewall-cmd --permanent --add-service=http || exit 1; run_command "FW HTTPS" firewall-cmd --permanent --add-service=https || exit 1; run_command "FW reload" firewall-cmd --reload || exit 1
    run_command "MariaDB install" dnf install -y mariadb-server || exit 1; run_command "MariaDB enable" systemctl enable mariadb || exit 1; run_command "MariaDB start" systemctl start mariadb || { log_message "ERROR" "MariaDB start FAILED."; exit 1; }
    optimize_mariadb_config || exit 1; setup_database || exit 1
    log_message "INFO" "PHP packages install..."; run_command "DNF install PHP" dnf install -y "${PHP_PACKAGES[@]}" || { log_message "ERROR" "PHP packages FAILED."; exit 1; }
    optimize_php_config || exit 1; log_message "INFO" "PHP-FPM user/group..."; if [[ -f "$PHP_FPM_WWW_CONF" ]]; then cp "$PHP_FPM_WWW_CONF" "${PHP_FPM_WWW_CONF}.bak.$(date +%s)"; sed -i 's/^user = apache/user = nginx/' "$PHP_FPM_WWW_CONF"; sed -i 's/^group = apache/group = nginx/' "$PHP_FPM_WWW_CONF"; else log_message "WARN" "$PHP_FPM_WWW_CONF niet gevonden."; fi
    run_command "PHP-FPM enable" systemctl enable php-fpm || exit 1; run_command "PHP-FPM log map" mkdir -p /var/log/php-fpm || exit 1; run_command "PHP-FPM log perms" chown nginx:nginx /var/log/php-fpm || log_message "WARN" "Perms FAILED."; run_command "PHP-FPM restart" systemctl restart php-fpm || { log_message "ERROR" "PHP-FPM restart FAILED."; exit 1; }
    run_command "PMA install" dnf install -y phpmyadmin || exit 1; log_message "INFO" "PMA config..."; BLOWFISH_SECRET=$(openssl rand -base64 32); PMA_PASSWORD=$(openssl rand -base64 16); mkdir -p "$(dirname "$PHPMYADMIN_CONFIG")"

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

    run_command "PMA temp dir" mkdir -p "$PHPMYADMIN_TMP_DIR" || exit 1; run_command "PMA lib perms" chown -R nginx:nginx "$(dirname "$PHPMYADMIN_TMP_DIR")" || exit 1; run_command "PMA temp chmod" chmod 770 "$PHPMYADMIN_TMP_DIR" || exit 1; log_message "INFO" "PMA DB setup..."; run_mysql_command "PMA DB" "CREATE DATABASE IF NOT EXISTS phpmyadmin DEFAULT CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;" || log_message "WARN" "...FAILED."; run_mysql_command "PMA User" "CREATE USER IF NOT EXISTS 'pma'@'localhost' IDENTIFIED BY '${PMA_PASSWORD}';" || log_message "WARN" "...FAILED."; run_mysql_command "PMA Grant" "GRANT ALL PRIVILEGES ON phpmyadmin.* TO 'pma'@'localhost';" || log_message "WARN" "...FAILED."; run_mysql_command "PMA Flush" "FLUSH PRIVILEGES;" || log_message "WARN" "...FAILED."; SQL_SCHEMA_GZ="/usr/share/phpmyadmin/sql/create_tables.sql.gz"; SQL_SCHEMA="/tmp/create_tables.sql"; if [[ -f "$SQL_SCHEMA_GZ" ]]; then gunzip < "$SQL_SCHEMA_GZ" > "$SQL_SCHEMA"; if run_mysql_command "PMA import" "USE phpmyadmin; SOURCE ${SQL_SCHEMA}"; then log_message "INFO" "PMA schema OK."; rm "$SQL_SCHEMA"; else log_message "WARN" "PMA import FAILED."; fi; else log_message "WARN" "PMA SQL schema niet gevonden."; fi
    install_wp_cli || exit 1; run_command "WP map" mkdir -p "$WORDPRESS_ROOT" || exit 1; cd /tmp || exit 1; run_command "WP download" curl -fLO https://wordpress.org/latest.tar.gz || exit 1; run_command "WP uitpakken" tar -xzf latest.tar.gz -C "$(dirname "$WORDPRESS_ROOT")" || exit 1; if [[ ! -d "$WORDPRESS_ROOT" ]] && [[ -d "$(dirname "$WORDPRESS_ROOT")/wordpress" ]]; then run_command "WP rename" mv "$(dirname "$WORDPRESS_ROOT")/wordpress" "$WORDPRESS_ROOT" || exit 1; fi; run_command "WP perms" chown -R nginx:nginx "$WORDPRESS_ROOT" || exit 1; find "$WORDPRESS_ROOT" -type d -exec chmod 755 {} \; && find "$WORDPRESS_ROOT" -type f -exec chmod 644 {} \; ; rm -f /tmp/latest.tar.gz; log_message "INFO" "WP files OK."
    log_message "INFO" "SELinux..."; if ! run_command "SELinux fcontext" semanage fcontext -a -t httpd_sys_rw_content_t "${WP_CONTENT_DIR}(/.*)?"; then log_message "WARN" "fcontext FAILED."; fi; run_command "SELinux restorecon" restorecon -Rv "${WORDPRESS_ROOT}" || log_message "WARN" "restorecon FAILED."; run_command "SELinux httpd_can_network_connect" setsebool -P httpd_can_network_connect 1 || exit 1; run_command "SELinux httpd_can_network_relay" setsebool -P httpd_can_network_relay 1 || exit 1; log_message "INFO" "SELinux OK."
    install_wordpress_multisite_auto || exit 1
    log_message "INFO" "Nginx config...";

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

    log_message "INFO" "Nginx config OK."; run_command "Nginx log map" mkdir -p /var/log/nginx || exit 1; log_message "INFO" "Nginx config test..."; if ! nginx -t >> "$LOG_FILE" 2>&1; then log_message "ERROR" "Nginx config test FAILED!"; exit 1; fi; log_message "INFO" "Nginx test OK."; run_command "Nginx restart" systemctl restart nginx || { log_message "ERROR" "Nginx restart FAILED."; exit 1; }
    log_message "INFO" "================ Installatie Succesvol ================"; echo ""; echo -e "${C_GREEN}${BORDER_DOUBLE}${C_RESET}"; echo -e " ✅ ${C_GREEN}Installatie Voltooid: LEMP + PMA + WP Multisite + APCu${C_RESET}"; echo -e "${C_GREEN}${BORDER_DOUBLE}${C_RESET}"; echo " ${C_YELLOW}BELANGRIJKE GEGEVENS:${C_RESET}"; echo -e "${C_GREY}${BORDER_SINGLE}${C_RESET}"; echo "   ${C_BLUE}WP Netwerk Admin:${C_RESET} ${C_CYAN}${WP_SITE_URL}/wp-admin/network/${C_RESET} (User: ${CUSTOM_WP_ADMIN_USER}, WW: ${C_YELLOW}${CUSTOM_WP_ADMIN_PASSWORD}${C_RESET})"; echo "   ${C_BLUE}WP Hoofd Admin:${C_RESET}   ${C_CYAN}${WP_SITE_URL}/wp-admin/${C_RESET} (User: ${CUSTOM_WP_ADMIN_USER}, WW: ${CUSTOM_WP_ADMIN_PASSWORD})"; echo "   ${C_BLUE}phpMyAdmin:${C_RESET}       ${C_CYAN}${WP_SITE_URL}/phpmyadmin/${C_RESET} (User: root, WW: ${C_YELLOW}${ACTIVE_DB_ROOT_PASSWORD}${C_RESET}) ${([[ "$USE_CUSTOM_DB_ROOT_PASSWORD" == false ]] && echo -e "${C_RED}(ONVEILIG!)${C_RESET}")}"; echo "   ${C_BLUE}DB Details:${C_RESET}       (Naam: ${WORDPRESS_DB_NAME}, User: ${WORDPRESS_DB_USER}, WW: ${WORDPRESS_DB_PASSWORD})"; echo "   ${C_BLUE}Logbestand:${C_RESET}      ${LOG_FILE}"; echo -e "${C_GREY}${BORDER_SINGLE}${C_RESET}"; echo " ${C_YELLOW}VOLGENDE STAPPEN:${C_RESET}"; echo -e " 🔥 ${C_GREEN}APCu Object Cache:${C_RESET} ${C_YELLOW}ACTIVEER 'APCu Object Cache Backend' plugin in WP Admin!${C_RESET}"; echo -e " 🚀 ${C_GREEN}Prestaties:${C_RESET}       Tune MariaDB (${MARIADB_OPT_CONF}), PHP-FPM (${PHP_FPM_WWW_CONF}), OPcache/APCu. ${C_YELLOW}Installeer Page Cache plugin!${C_RESET}"; echo -e " 👉 ${C_GREEN}HTTPS:${C_RESET}            ${C_CYAN}sudo dnf install -y ${CERTBOT_PACKAGES[*]} && sudo certbot --nginx${C_RESET}"; echo -e "${C_GREEN}${BORDER_DOUBLE}${C_RESET}"
}

# --- Functie voor verwijdering ---
uninstall_lemp_wp() {
    log_message "INFO" "================ Start Verwijdering ================"; echo -e " ${C_RED}WAARSCHUWING: DESTRUCTIEF!${C_RESET}"; read -p "--> Typ 'JA' om door te gaan: " confirm_uninstall; if [[ "${confirm_uninstall}" != "JA" ]]; then log_message "INFO" "Verwijdering geannuleerd."; return 1; fi
    log_message "INFO" "Services stoppen/uitschakelen..."; run_command "Stop Nginx" systemctl stop nginx ||:; run_command "Disable Nginx" systemctl disable nginx ||:; run_command "Stop MariaDB" systemctl stop mariadb ||:; run_command "Disable MariaDB" systemctl disable mariadb ||:; run_command "Stop PHP-FPM" systemctl stop php-fpm ||:; run_command "Disable PHP-FPM" systemctl disable php-fpm ||:
    log_message "INFO" "Firewall regels verwijderen..."; run_command "FW Remove HTTP" firewall-cmd --permanent --remove-service=http ||:; run_command "FW Remove HTTPS" firewall-cmd --permanent --remove-service=https ||:; run_command "FW Reload" firewall-cmd --reload ||:
    echo ""; log_message "WARN" "!! DATABASE VERWIJDERING !! Map: ${MARIADB_DATA_DIR} !!"; echo ""; read -p "--> Typ 'VERWIJDER DB': " confirm_db_delete; if [[ "${confirm_db_delete}" == "VERWIJDER DB" ]]; then run_command "Verwijderen DB data" rm -rf "${MARIADB_DATA_DIR}"; else log_message "INFO" "DB verwijdering overgeslagen."; fi
    log_message "INFO" "Packages verwijderen..."; local ALL_PACKAGES=("${OTHER_PACKAGES[@]}" "${PHP_PACKAGES[@]}" "${CERTBOT_PACKAGES[@]}" "${CORE_UTILS[@]}"); if rpm -q remi-release &>/dev/null; then ALL_PACKAGES+=("remi-release"); fi
    log_message "INFO" "Removing: ${ALL_PACKAGES[*]}"; run_command "Packages verwijderen" dnf remove -y "${ALL_PACKAGES[@]}" || log_message "WARN" "Package remove FAILED."; run_command "Autoremove" dnf autoremove -y || log_message "WARN" "Autoremove FAILED."
    log_message "INFO" "Configuraties, logs & WP-CLI verwijderen..."; run_command "Remove Nginx conf" rm -f "${NGINX_CONF_DIR}/wordpress.conf"; run_command "Remove MariaDB conf" rm -f "${MARIADB_OPT_CONF}"; run_command "Remove PMA conf" rm -rf /etc/phpMyAdmin; run_command "Remove PMA lib" rm -rf /var/lib/phpmyadmin; run_command "Remove OPcache conf" rm -f "$PHP_OPCACHE_CONF_PATH"; run_command "Remove APCu conf" rm -f "$PHP_APCU_CONF_PATH"; run_command "Remove php.ini backups" rm -f "${PHP_INI_PATH}.bak.*"; run_command "Remove ext .ini backups" find "$PHP_EXTENSIONS_DIR" -name '*.ini.bak*' -delete; run_command "Remove WP-CLI" rm -f "$WP_CLI_PATH"; run_command "Remove logs" rm -f /var/log/nginx/wordpress.*.log "$LOG_FILE"; run_command "Remove log dirs" rmdir /var/log/nginx /var/log/php-fpm 2>/dev/null || true
    echo ""; log_message "WARN" "!! WORDPRESS VERWIJDERING !! Map: ${WORDPRESS_ROOT} !!"; echo ""; read -p "--> Typ 'VERWIJDER WP': " confirm_wp_delete; if [[ "${confirm_wp_delete}" == "VERWIJDER WP" ]]; then run_command "Verwijderen WP map" rm -rf "${WORDPRESS_ROOT}"; else log_message "INFO" "WP verwijdering overgeslagen."; fi
    log_message "INFO" "SELinux fcontext verwijderen..."; run_command "SELinux fcontext delete" semanage fcontext -d "${WP_CONTENT_DIR}(/.*)?" || log_message "WARN" "SELinux fcontext delete FAILED."
    log_message "INFO" "================ Verwijdering Voltooid ================"; return 0
}

# --- Hoofdmenu Functie (v2.14.1) ---
main_menu() {
     while true; do
        display_welcome_screen

        echo -e "${HEADER_COLOR}${BORDER_DOUBLE}${C_RESET}"
        printf "${HEADER_COLOR}== %-82s ==${C_RESET}\n" " ${TITLE_COLOR}Hoofdmenu${C_RESET} ${C_GREY}(LEMP + WP Multisite + APCu)${C_RESET}"
        echo -e "${HEADER_COLOR}${BORDER_SINGLE}${C_RESET}"

        # Installatie / De-installatie sectie
        printf "   %-4b %-20s %s\n" "${ACTION_INSTALL_COLOR}[1]${C_RESET}" "Installeren" "Installeer alles (Optimal, Auto)"
        printf "   %-4b %-20s %s\n" "${ACTION_WARN_COLOR}[2]${C_RESET}" "Herinstalleren" "Verwijder alles & installeer opnieuw"
        printf "   %-4b %-20s %s\n" "${ACTION_DANGER_COLOR}[3]${C_RESET}" "Verwijderen" "Verwijder alles ${C_RED}(INCL. DATA!)${C_RESET}"
        echo -e "${HEADER_COLOR}${BORDER_SINGLE}${C_RESET}"

        # Configuratie sectie
        printf "   %-4b %-20s %s\n" "${ACTION_CONFIG_COLOR}[P]${C_RESET}" "PHP Instellingen" "Pas php.ini waarden aan"
        printf "   %-4b %-20s %s\n" "${ACTION_CONFIG_COLOR}[E]${C_RESET}" "PHP Extensies" "Beheer PHP extensies (aan/uit)"
        printf "   %-4b %-20s %s\n" "${ACTION_CONFIG_COLOR}[M]${C_RESET}" "Multisite Toggle" "Schakel Multisite aan/uit in wp-config"
        printf "   %-4b %-20s %s\n" "${ACTION_CONFIG_COLOR}[C]${C_RESET}" "Cookie Fix" "Pas WordPress cookie fixes toe"
        printf "   %-4b %-20s %s\n" "${ACTION_CONFIG_COLOR}[U]${C_RESET}" "Undo Cookie Fix" "Maak cookie fixes ongedaan"
        echo -e "${HEADER_COLOR}${BORDER_SINGLE}${C_RESET}"

        # Informatie & Tools sectie
        printf "   %-4b %-20s %s\n" "${ACTION_INFO_COLOR}[V]${C_RESET}" "Versies" "Toon Nginx, MariaDB, PHP versies"
        printf "   %-4b %-20s %s\n" "${ACTION_INFO_COLOR}[H]${C_RESET}" "Gezondheid" "Controleer services & configuratie"
        printf "   %-4b %-20s %s\n" "${ACTION_INFO_COLOR}[R]${C_RESET}" "Herstart Services" "Herstart Nginx, MariaDB, PHP-FPM"
        printf "   %-4b %-20s %s\n" "${ACTION_INFO_COLOR}[L]${C_RESET}" "Logbestand" "Bekijk (${C_GREY}${LOG_FILE}${C_RESET})"
        echo -e "${HEADER_COLOR}${BORDER_SINGLE}${C_RESET}"

        # Afsluiten
        printf "   %-4b %-20s %s\n" "${C_GREY}[0]${C_RESET}" "Afsluiten" "Script beëindigen"
        echo -e "${HEADER_COLOR}${BORDER_DOUBLE}${C_RESET}"

        # Prompt
        read -p "$(echo -e ${PROMPT_COLOR}"   Uw keuze [1,2,3,P,E,M,C,U,V,H,R,L,0]: "${C_RESET})" choice

        # Verwerk keuze
        case $choice in
            1) install_lemp_wp; log_message "INFO" "Installatie voltooid."; break ;;
            2) if uninstall_lemp_wp; then log_message "INFO" "Verwijdering ok. Start herinstallatie..."; install_lemp_wp; log_message "INFO" "Herinstallatie voltooid."; else log_message "ERROR" "Verwijdering mislukt/geannuleerd."; fi; break ;;
            3) uninstall_lemp_wp; log_message "INFO" "Verwijdering voltooid."; break ;;
            P|p) adjust_php_settings ;;
            E|e) manage_php_extensions ;;
            M|m) toggle_multisite ;;
            C|c) apply_cookie_fixes ;;
            U|u) revert_cookie_fixes ;;
            V|v) display_versions ;;
            H|h) health_check ;;
            R|r) restart_services ;;
            L|l) log_message "INFO" "Logbestand openen..."; less "$LOG_FILE";;
            0) log_message "INFO" "Script afgesloten."; echo -e "\n${C_BLUE}Script afgesloten.${C_RESET}"; exit 0;;
            *) log_message "WARN" "Ongeldige keuze: ${choice}"; echo -e "\n${C_RED}FOUT: Ongeldige keuze '${choice}'. Probeer opnieuw.${C_RESET}"; sleep 2;;
        esac
    done
}

# --- Script Uitvoering ---
check_root
main_menu

exit 0