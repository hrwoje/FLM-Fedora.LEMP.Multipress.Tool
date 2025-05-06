#!/bin/bash

# HTTP Protocol Manager for Nginx
# Version: 1.2

# --- [Configuration] ---
set -euo pipefail
IFS=$'\n\t'

# --- [Constants] ---
NGINX_CONF="/etc/nginx/conf.d/multipress.conf"
BACKUP_DIR="/etc/nginx/conf.d/backups"

# --- [Color Definitions] ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# --- [Symbols] ---
CHECK='✅'
CROSS='❌'
WARNING='⚠️'
INFO='ℹ️'

# --- [Audit Log] ---
AUDIT_LOG="/var/log/nginx-http-audit.log"
AUDIT_DIR="/var/log/nginx-http-audit"

# --- [Helper Functions] ---
audit_log() {
    local message="$1"
    local level="${2:-INFO}"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    mkdir -p "$AUDIT_DIR"
    echo "$timestamp - [$level] - $message" | tee -a "$AUDIT_LOG"
}

create_summary() {
    local protocol="$1"
    local status="$2"
    local details="$3"
    local summary_file="$AUDIT_DIR/${protocol}_summary_$(date +%Y%m%d_%H%M%S).txt"
    
    echo "=== $protocol Configuration Summary ===" > "$summary_file"
    echo "Timestamp: $(date '+%Y-%m-%d %H:%M:%S')" >> "$summary_file"
    echo "Status: $status" >> "$summary_file"
    echo "Details:" >> "$summary_file"
    echo "$details" >> "$summary_file"
    echo "=====================================" >> "$summary_file"
    
    echo -e "${GREEN}Summary saved to: $summary_file${NC}"
}

check_root() {
    if [[ "$EUID" -ne 0 ]]; then
        echo -e "${RED}This script must be run as root${NC}"
        exit 1
    fi
}

check_nginx() {
    if ! command -v nginx &>/dev/null; then
        echo -e "${RED}Nginx is not installed${NC}"
        audit_log "Nginx check failed: Not installed" "ERROR"
        return 1
    fi
    return 0
}

backup_config() {
    local date_stamp=$(date +%Y%m%d_%H%M%S)
    mkdir -p "$BACKUP_DIR"
    
    if [[ -f "$NGINX_CONF" ]]; then
        cp "$NGINX_CONF" "${BACKUP_DIR}/multipress.conf.bak.${date_stamp}"
        audit_log "Configuration backup created: $date_stamp" "INFO"
        echo -e "Backup created: ${BACKUP_DIR}/multipress.conf.bak.${date_stamp}"
    else
        echo -e "${RED}Configuration file not found: $NGINX_CONF${NC}"
        audit_log "Backup failed: Configuration file not found" "ERROR"
        return 1
    fi
    echo "$date_stamp"
}

restore_config() {
    local date_stamp="$1"
    local backup_file="${BACKUP_DIR}/multipress.conf.bak.${date_stamp}"
    
    if [[ -f "$backup_file" ]]; then
        cp "$backup_file" "$NGINX_CONF"
        audit_log "Configuration restored from backup: $date_stamp" "INFO"
        echo -e "Configuration restored from: $backup_file"
    else
        echo -e "${RED}Backup file not found: $backup_file${NC}"
        audit_log "Restore failed: Backup file not found" "ERROR"
        return 1
    fi
}

# --- [HTTP/2 Functions] ---
check_http2() {
    echo -e "${BLUE}Checking HTTP/2 status...${NC}"
    local check_summary=""
    
    # Check if HTTP/2 module is available
    if ! nginx -V 2>&1 | grep -q "http_v2_module"; then
        echo -e "${CROSS} HTTP/2 module is not available in Nginx"
        check_summary+="Module Status: Not Available\n"
        audit_log "HTTP/2 check failed: Module not available" "ERROR"
        return 1
    fi
    check_summary+="Module Status: Available\n"
    
    # Check if HTTP/2 is enabled in config
    if grep -q "listen.*443.*ssl.*http2" "$NGINX_CONF"; then
        echo -e "${CHECK} HTTP/2 is enabled in $NGINX_CONF"
        check_summary+="Status: Enabled\nConfiguration File: $NGINX_CONF"
        audit_log "HTTP/2 check: Enabled" "INFO"
        create_summary "HTTP2" "Enabled" "$check_summary"
        return 0
    else
        echo -e "${CROSS} HTTP/2 is not enabled in $NGINX_CONF"
        check_summary+="Status: Not Enabled\nConfiguration File: $NGINX_CONF"
        audit_log "HTTP/2 check: Not enabled" "WARNING"
        create_summary "HTTP2" "Not Enabled" "$check_summary"
        return 1
    fi
}

enable_http2() {
    echo -e "${BLUE}Enabling HTTP/2...${NC}"
    local enable_summary=""
    
    # Create backup
    local backup_stamp=$(backup_config)
    enable_summary+="Backup created: $backup_stamp\n"
    
    # Enable HTTP/2 in SSL server block
    if grep -q "listen.*443.*ssl" "$NGINX_CONF"; then
        sed -i 's/listen.*443.*ssl.*;/listen 443 ssl http2;/g' "$NGINX_CONF"
        enable_summary+="Modified configuration in: $NGINX_CONF\n"
        echo -e "${CHECK} Added HTTP/2 to $NGINX_CONF"
    else
        echo -e "${RED}No SSL server block found in $NGINX_CONF${NC}"
        enable_summary+="Error: No SSL server block found"
        audit_log "HTTP/2 enable failed: No SSL server block" "ERROR"
        create_summary "HTTP2" "Failed" "$enable_summary"
        return 1
    fi
    
    # Test configuration
    if ! nginx -t; then
        echo -e "${RED}Configuration test failed, restoring backup...${NC}"
        restore_config "$backup_stamp"
        enable_summary+="\nStatus: Failed - Configuration test failed\nBackup restored"
        audit_log "HTTP/2 enable failed: Configuration test failed" "ERROR"
        create_summary "HTTP2" "Failed" "$enable_summary"
        return 1
    fi
    
    # Reload Nginx
    if systemctl reload nginx; then
        echo -e "${GREEN}HTTP/2 has been successfully enabled${NC}"
        enable_summary+="\nStatus: Successfully enabled"
        audit_log "HTTP/2 enabled successfully" "INFO"
        create_summary "HTTP2" "Enabled" "$enable_summary"
        return 0
    else
        echo -e "${RED}Failed to reload Nginx${NC}"
        enable_summary+="\nStatus: Failed - Nginx reload failed"
        audit_log "HTTP/2 enable failed: Nginx reload failed" "ERROR"
        create_summary "HTTP2" "Failed" "$enable_summary"
        return 1
    fi
}

# --- [HTTP/3 Functions] ---
check_http3() {
    echo -e "${BLUE}Checking HTTP/3 status...${NC}"
    local check_summary=""
    
    # Check if HTTP/3 module is available
    if ! nginx -V 2>&1 | grep -q "http_v3_module"; then
        echo -e "${CROSS} HTTP/3 module is not available in Nginx"
        check_summary+="Module Status: Not Available\n"
        audit_log "HTTP/3 check failed: Module not available" "ERROR"
        return 1
    fi
    check_summary+="Module Status: Available\n"
    
    # Check if HTTP/3 is enabled in config
    if grep -q "http3 on" "$NGINX_CONF"; then
        echo -e "${CHECK} HTTP/3 is enabled in $NGINX_CONF"
        check_summary+="Status: Enabled\nConfiguration File: $NGINX_CONF"
        audit_log "HTTP/3 check: Enabled" "INFO"
        create_summary "HTTP3" "Enabled" "$check_summary"
        return 0
    else
        echo -e "${CROSS} HTTP/3 is not enabled in $NGINX_CONF"
        check_summary+="Status: Not Enabled\nConfiguration File: $NGINX_CONF"
        audit_log "HTTP/3 check: Not enabled" "WARNING"
        create_summary "HTTP3" "Not Enabled" "$check_summary"
        return 1
    fi
}

enable_http3() {
    echo -e "${BLUE}Enabling HTTP/3...${NC}"
    local enable_summary=""
    
    # Create backup
    local backup_stamp=$(backup_config)
    enable_summary+="Backup created: $backup_stamp\n"
    
    # Enable HTTP/3 in SSL server block
    if grep -q "listen.*443.*ssl.*http2" "$NGINX_CONF"; then
        sed -i '/listen.*443.*ssl.*http2;/a \    listen 443 quic reuseport;\n    listen [::]:443 quic reuseport;\n    http3 on;\n    http3_hq on;' "$NGINX_CONF"
        enable_summary+="Modified configuration in: $NGINX_CONF\n"
        echo -e "${CHECK} Added HTTP/3 to $NGINX_CONF"
    else
        echo -e "${RED}No HTTP/2 SSL server block found in $NGINX_CONF${NC}"
        enable_summary+="Error: No HTTP/2 SSL server block found"
        audit_log "HTTP/3 enable failed: No HTTP/2 SSL server block" "ERROR"
        create_summary "HTTP3" "Failed" "$enable_summary"
        return 1
    fi
    
    # Test configuration
    if ! nginx -t; then
        echo -e "${RED}Configuration test failed, restoring backup...${NC}"
        restore_config "$backup_stamp"
        enable_summary+="\nStatus: Failed - Configuration test failed\nBackup restored"
        audit_log "HTTP/3 enable failed: Configuration test failed" "ERROR"
        create_summary "HTTP3" "Failed" "$enable_summary"
        return 1
    fi
    
    # Reload Nginx
    if systemctl reload nginx; then
        echo -e "${GREEN}HTTP/3 has been successfully enabled${NC}"
        echo -e "${YELLOW}Note: Make sure your firewall allows UDP port 443 for QUIC${NC}"
        enable_summary+="\nStatus: Successfully enabled\nNote: UDP port 443 must be open for QUIC"
        audit_log "HTTP/3 enabled successfully" "INFO"
        create_summary "HTTP3" "Enabled" "$enable_summary"
        return 0
    else
        echo -e "${RED}Failed to reload Nginx${NC}"
        enable_summary+="\nStatus: Failed - Nginx reload failed"
        audit_log "HTTP/3 enable failed: Nginx reload failed" "ERROR"
        create_summary "HTTP3" "Failed" "$enable_summary"
        return 1
    fi
}

# --- [Main Menu] ---
main_menu() {
    while true; do
        clear
        echo -e "${BLUE}Nginx HTTP Protocol Manager${NC}"
        echo "1. Check HTTP/2 Status"
        echo "2. Enable HTTP/2"
        echo "3. Check HTTP/3 Status"
        echo "4. Enable HTTP/3"
        echo "5. View Audit Log"
        echo "6. Exit"
        
        read -rp "Enter your choice: " choice
        
        case $choice in
            1)
                if check_nginx; then
                    check_http2
                fi
                read -rp "Press Enter to continue..."
                ;;
            2)
                if check_nginx; then
                    enable_http2
                fi
                read -rp "Press Enter to continue..."
                ;;
            3)
                if check_nginx; then
                    check_http3
                fi
                read -rp "Press Enter to continue..."
                ;;
            4)
                if check_nginx; then
                    enable_http3
                fi
                read -rp "Press Enter to continue..."
                ;;
            5)
                if [[ -f "$AUDIT_LOG" ]]; then
                    echo -e "${BLUE}Audit Log Contents:${NC}"
                    tail -n 50 "$AUDIT_LOG"
                else
                    echo -e "${YELLOW}No audit log found${NC}"
                fi
                read -rp "Press Enter to continue..."
                ;;
            6)
                echo -e "${GREEN}Goodbye!${NC}"
                exit 0
                ;;
            *)
                echo -e "${RED}Invalid choice${NC}"
                sleep 2
                ;;
        esac
    done
}

# --- [Script Execution] ---
check_root
main_menu 