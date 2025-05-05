#!/bin/bash

# Nginx Configuration Manager
# Version: 1.0
# Author: Cursor AI

# Configuration
set -euo pipefail
IFS=$'\n\t'

# Constants
NGINX_CONF="/etc/nginx/conf.d/multipress.conf"
NGINX_BACKUP_DIR="/etc/nginx/conf.d/backups"
LOG_DIR="/var/log/nginx-manager"
LOG_FILE="$LOG_DIR/nginx-manager.log"
MODSEC_CONF="/etc/modsecurity/modsecurity.conf"

# Colors and symbols
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'
CHECK='✅'
CROSS='❌'
WARNING='⚠️'

# Logging function
log() {
    mkdir -p "$LOG_DIR"
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a "$LOG_FILE" >/dev/null
    echo -e "${BLUE}[LOG]${NC} $1"
}

# Error handling
error_exit() {
    echo -e "${RED}Error: $1${NC}" >&2
    log "ERROR: $1"
    exit 1
}

# Check if running as root
check_root() {
    if [ "$EUID" -ne 0 ]; then
        error_exit "Please run as root"
    fi
}

# Create backup of Nginx configuration
create_backup() {
    local timestamp=$(date +%Y%m%d_%H%M%S)
    mkdir -p "$NGINX_BACKUP_DIR"
    cp "$NGINX_CONF" "$NGINX_BACKUP_DIR/multipress.conf.bak.$timestamp"
    log "Created backup: multipress.conf.bak.$timestamp"
}

# Install required packages
install_packages() {
    log "Installing required packages..."
    
    # Install ModSecurity
    dnf install -y mod_security mod_security_crs || error_exit "Failed to install ModSecurity"
    
    # Configure systemd for Nginx
    systemctl edit nginx << EOF
[Service]
Restart=on-failure
EOF
    
    log "Packages installed successfully"
}

# Initialize configuration files
initialize_config() {
    log "Initializing configuration files..."
    
    # Create log directory
    mkdir -p "$LOG_DIR"
    
    # Create backup directory
    mkdir -p "$NGINX_BACKUP_DIR"
    
    log "Configuration initialized"
}

# Configure ModSecurity
configure_modsecurity() {
    log "Configuring ModSecurity..."
    
    # Create ModSecurity configuration
    mkdir -p /etc/modsecurity
    cat > "$MODSEC_CONF" << 'EOF'
SecRuleEngine On
SecRequestBodyAccess On
SecResponseBodyAccess On
SecResponseBodyMimeType text/plain text/html text/xml application/json
SecRule REQUEST_HEADERS:Content-Type "text/xml" \
     "id:'200000',phase:1,t:none,t:lowercase,pass,nolog,ctl:requestBodyProcessor=XML"
SecRule REQUEST_HEADERS:Content-Type "application/json" \
     "id:'200001',phase:1,t:none,t:lowercase,pass,nolog,ctl:requestBodyProcessor=JSON"
EOF
    
    log "ModSecurity configured"
}

# Manage allowed countries
manage_countries() {
    while true; do
        clear
        echo -e "${BLUE}GeoIP Country Management${NC}"
        echo "1. View allowed countries"
        echo "2. Add country"
        echo "3. Remove country"
        echo "4. Return to main menu"
        read -p "Enter your choice (1-4): " choice
        
        case $choice in
            1)
                echo -e "\n${BLUE}Currently allowed countries:${NC}"
                grep -oP '(?<=yes; )[A-Z]{2}' "$ALLOWED_COUNTRIES_FILE" || echo "No countries configured"
                ;;
            2)
                read -p "Enter country code (e.g., NL): " country
                if [[ $country =~ ^[A-Z]{2}$ ]]; then
                    sed -i "/default no;/a \        $country yes;" "$ALLOWED_COUNTRIES_FILE"
                    log "Added country: $country"
                else
                    echo -e "${RED}Invalid country code${NC}"
                fi
                ;;
            3)
                read -p "Enter country code to remove (e.g., NL): " country
                if [[ $country =~ ^[A-Z]{2}$ ]]; then
                    sed -i "/$country yes;/d" "$ALLOWED_COUNTRIES_FILE"
                    log "Removed country: $country"
                else
                    echo -e "${RED}Invalid country code${NC}"
                fi
                ;;
            4)
                return
                ;;
            *)
                echo -e "${RED}Invalid choice${NC}"
                ;;
        esac
        
        # Reload Nginx after changes
        systemctl reload nginx
        read -p "Press Enter to continue..."
    done
}

# Detect system configuration
detect_system_config() {
    log "Detecting system configuration..."
    
    # Detect PHP-FPM socket
    if [ -S "/var/run/php-fpm/www.sock" ]; then
        PHP_FPM_SOCKET="/var/run/php-fpm/www.sock"
    elif [ -S "/var/run/php/php-fpm.sock" ]; then
        PHP_FPM_SOCKET="/var/run/php/php-fpm.sock"
    else
        # Try to find PHP-FPM socket
        PHP_FPM_SOCKET=$(find /var/run -name "php*.sock" 2>/dev/null | head -n 1)
        if [ -z "$PHP_FPM_SOCKET" ]; then
            error_exit "PHP-FPM socket not found"
        fi
    fi
    log "Detected PHP-FPM socket: $PHP_FPM_SOCKET"
    
    # Detect SSL certificates
    if [ -f "/etc/pki/tls/certs/localhost.pem" ]; then
        SSL_CERT="/etc/pki/tls/certs/localhost.pem"
        SSL_KEY="/etc/pki/tls/private/localhost-key.pem"
    elif [ -f "/etc/ssl/certs/nginx-selfsigned.crt" ]; then
        SSL_CERT="/etc/ssl/certs/nginx-selfsigned.crt"
        SSL_KEY="/etc/ssl/private/nginx-selfsigned.key"
    else
        # Try to find SSL certificates
        SSL_CERT=$(find /etc -name "*.pem" -o -name "*.crt" 2>/dev/null | grep -i "cert" | head -n 1)
        SSL_KEY=$(find /etc -name "*.pem" -o -name "*.key" 2>/dev/null | grep -i "key" | head -n 1)
        if [ -z "$SSL_CERT" ] || [ -z "$SSL_KEY" ]; then
            error_exit "SSL certificates not found"
        fi
    fi
    log "Detected SSL certificate: $SSL_CERT"
    log "Detected SSL key: $SSL_KEY"
    
    # Detect web root
    if [ -d "/var/www/html" ]; then
        WEB_ROOT="/var/www/html"
    elif [ -d "/var/www" ]; then
        WEB_ROOT="/var/www"
    else
        # Try to find web root
        WEB_ROOT=$(find /var/www -maxdepth 1 -type d 2>/dev/null | head -n 1)
        if [ -z "$WEB_ROOT" ]; then
            error_exit "Web root directory not found"
        fi
    fi
    log "Detected web root: $WEB_ROOT"
    
    # Detect server name
    if [ -f "/etc/hostname" ]; then
        SERVER_NAME=$(cat /etc/hostname)
    else
        SERVER_NAME=$(hostname)
    fi
    log "Detected server name: $SERVER_NAME"
}

# Optimize Nginx configuration
optimize_nginx() {
    log "Optimizing Nginx configuration..."
    create_backup
    
    # Create the optimized configuration
    cat > "$NGINX_CONF" << 'EOF'
# HTTP to HTTPS redirect
server {
    listen 80;
    server_name localhost;
    return 301 https://$host$request_uri;
}

# HTTP server block
server {
    listen 80;
    server_name localhost;
    root /var/www/html;
    index index.php index.html index.htm;
    client_max_body_size 512M;

    # WordPress multisite subdirectory rules
    if (!-e $request_filename) {
        rewrite /wp-admin$ $scheme://$host$uri/ permanent;
        rewrite ^/[_0-9a-zA-Z-]+(/wp-.*) $1 last;
        rewrite ^/[_0-9a-zA-Z-]+(/.*\.php)$ $1 last;
    }

    location / {
        try_files $uri $uri/ /index.php?$args;
    }

    location ~ \.php$ {
        try_files $uri =404;
        fastcgi_split_path_info ^(.+\.php)(/.+)$;
        fastcgi_pass unix:/var/run/php-fpm/www.sock;
        fastcgi_index index.php;
        fastcgi_param SCRIPT_FILENAME $document_root$fastcgi_script_name;
        include fastcgi_params;
    }

    location ~ /\.ht {
        deny all;
    }

    location ~* \.(engine|inc|info|install|make|module|profile|test|po|sh|.*sql|theme|tpl(\.php)?|xtmpl)$|^(\..*|Entries.*|Repository|Root|Tag|Template)$|\.php_ {
        deny all;
    }
}

# HTTPS server block
server {
    listen 443 ssl;
    server_name localhost;
    client_max_body_size 512M;
    
    # SSL configuration
    ssl_certificate /etc/pki/tls/certs/localhost.pem;
    ssl_certificate_key /etc/pki/tls/private/localhost-key.pem;
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers 'ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256';
    
    # Basic configuration
    root /var/www/html;
    index index.php index.html index.htm;
    server_tokens off;

    # Compression settings
    gzip on;
    gzip_vary on;
    gzip_proxied any;
    gzip_comp_level 6;
    gzip_types text/plain text/css text/xml application/json application/javascript application/xml+rss image/svg+xml;

    # Security headers
    add_header X-Frame-Options "SAMEORIGIN" always;
    add_header X-Content-Type-Options "nosniff" always;
    add_header X-XSS-Protection "1; mode=block" always;
    add_header Referrer-Policy "no-referrer-when-downgrade" always;
    add_header Strict-Transport-Security "max-age=63072000; includeSubDomains; preload" always;

    # WordPress multisite subdirectory rules
    if (!-e $request_filename) {
        rewrite /wp-admin$ $scheme://$host$uri/ permanent;
        rewrite ^/[_0-9a-zA-Z-]+(/wp-.*) $1 last;
        rewrite ^/[_0-9a-zA-Z-]+(/.*\.php)$ $1 last;
    }

    location / {
        try_files $uri $uri/ /index.php?$args;
    }

    location ~ \.php$ {
        try_files $uri =404;
        fastcgi_split_path_info ^(.+\.php)(/.+)$;
        fastcgi_pass unix:/var/run/php-fpm/www.sock;
        fastcgi_index index.php;
        fastcgi_param SCRIPT_FILENAME $document_root$fastcgi_script_name;
        include fastcgi_params;
    }

    location ~ /\.ht {
        deny all;
    }

    location ~* \.(engine|inc|info|install|make|module|profile|test|po|sh|.*sql|theme|tpl(\.php)?|xtmpl)$|^(\..*|Entries.*|Repository|Root|Tag|Template)$|\.php_ {
        deny all;
    }

    # Cache headers
    location ~* \.(jpg|jpeg|png|gif|ico|css|js|svg|woff2?|ttf|eot)$ {
        expires max;
        log_not_found off;
        access_log off;
    }

    # Block known bots
    if ($http_user_agent ~* (semrush|crawler|MJ12bot|AhrefsBot|DotBot|BLEXBot)) {
        return 403;
    }

    autoindex off;
}
EOF

    # Test and reload Nginx
    nginx -t || error_exit "Nginx configuration test failed"
    systemctl reload nginx || error_exit "Failed to reload Nginx"
    
    log "Nginx configuration optimized"
}

# Show summary
show_summary() {
    local action="$1"
    local details="$2"
    
    clear
    echo -e "${GREEN}Operation Summary${NC}"
    echo "========================================="
    echo -e "${BLUE}Action:${NC} $action"
    echo -e "${BLUE}Time:${NC} $(date)"
    echo -e "${BLUE}Details:${NC}"
    echo "$details"
    echo "========================================="
    echo -e "${YELLOW}Press Enter to return to the main menu...${NC}"
    read
}

# Check required files and directories
check_requirements() {
    log "Checking requirements..."
    
    # Check if Nginx is installed
    if ! command -v nginx &> /dev/null; then
        error_exit "Nginx is not installed"
    fi
    
    # Check if configuration directory exists
    if [ ! -d "$(dirname "$NGINX_CONF")" ]; then
        error_exit "Nginx configuration directory does not exist"
    fi
    
    # Check if ModSecurity directory exists
    if [ ! -d "/etc/modsecurity" ]; then
        mkdir -p /etc/modsecurity
        log "Created ModSecurity directory"
    fi
    
    log "Requirements check completed"
}

# Main menu
main_menu() {
    while true; do
        clear
        echo -e "${BLUE}Nginx Configuration Manager${NC}"
        echo "1. Install Required Packages"
        echo "2. Configure ModSecurity"
        echo "3. Optimize Nginx Configuration"
        echo "4. View Logs"
        echo "5. Exit"
        read -p "Enter your choice (1-5): " choice
        
        case $choice in
            1)
                check_requirements
                install_packages
                show_summary "Package Installation" "All required packages have been installed"
                ;;
            2)
                check_requirements
                configure_modsecurity
                show_summary "ModSecurity Configuration" "ModSecurity has been configured"
                ;;
            3)
                check_requirements
                optimize_nginx
                show_summary "Nginx Optimization" "Nginx configuration has been optimized"
                ;;
            4)
                echo -e "\n${BLUE}Recent Log Entries:${NC}"
                tail -n 20 "$LOG_FILE" || echo "No logs found"
                read -p "Press Enter to continue..."
                ;;
            5)
                echo -e "${GREEN}Exiting...${NC}"
                exit 0
                ;;
            *)
                echo -e "${RED}Invalid choice${NC}"
                sleep 2
                ;;
        esac
    done
}

# Start script
check_root
initialize_config
main_menu 