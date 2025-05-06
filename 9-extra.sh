#!/bin/bash

# Nginx Configuration Manager
# Version: 1.0
# Author: Cursor AI

# Configuration
set -euo pipefail
IFS=$'\n\t'

# Load configuration
CONFIG_FILE="/etc/nginx-manager/config.conf"
if [ -f "$CONFIG_FILE" ]; then
    source "$CONFIG_FILE"
else
    # Default configuration
    NGINX_CONF="/etc/nginx/conf.d/multipress.conf"
    NGINX_BACKUP_DIR="/etc/nginx/conf.d/backups"
    LOG_DIR="/var/log/nginx-manager"
    LOG_FILE="$LOG_DIR/nginx-manager.log"
    MODSEC_CONF="/etc/modsecurity/modsecurity.conf"
    ALLOWED_COUNTRIES_FILE="/etc/nginx/conf.d/allowed_countries.conf"
    WEB_ROOT="/var/www/html"
    SERVER_NAME="localhost"
    SSL_CERT="/etc/pki/tls/certs/localhost.pem"
    SSL_KEY="/etc/pki/tls/private/localhost-key.pem"
    PHP_FPM_SOCKET="/var/run/php-fpm/www.sock"
    CLIENT_MAX_BODY_SIZE="512M"
    WORKER_PROCESSES="auto"
    WORKER_CONNECTIONS="1024"
    KEEPALIVE_TIMEOUT="65"
    GZIP_TYPES="text/plain text/css application/json application/javascript text/xml application/xml application/xml+rss text/javascript"
fi

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
    mkdir -p /etc/systemd/system/nginx.service.d/
    cat > /etc/systemd/system/nginx.service.d/override.conf << EOF
[Service]
Restart=on-failure
EOF
    systemctl daemon-reload
    
    log "Packages installed successfully"
}

# Initialize configuration files
initialize_config() {
    log "Initializing configuration files..."
    
    # Create configuration directory
    mkdir -p /etc/nginx-manager
    
    # Create default configuration file if it doesn't exist
    if [ ! -f "$CONFIG_FILE" ]; then
        cat > "$CONFIG_FILE" << EOF
# Nginx Manager Configuration
NGINX_CONF="/etc/nginx/conf.d/multipress.conf"
NGINX_BACKUP_DIR="/etc/nginx/conf.d/backups"
LOG_DIR="/var/log/nginx-manager"
LOG_FILE="$LOG_DIR/nginx-manager.log"
MODSEC_CONF="/etc/modsecurity/modsecurity.conf"
ALLOWED_COUNTRIES_FILE="/etc/nginx/conf.d/allowed_countries.conf"
WEB_ROOT="/var/www/html"
SERVER_NAME="localhost"
SSL_CERT="/etc/pki/tls/certs/localhost.pem"
SSL_KEY="/etc/pki/tls/private/localhost-key.pem"
PHP_FPM_SOCKET="/var/run/php-fpm/www.sock"
CLIENT_MAX_BODY_SIZE="512M"
WORKER_PROCESSES="auto"
WORKER_CONNECTIONS="1024"
KEEPALIVE_TIMEOUT="65"
GZIP_TYPES="text/plain text/css application/json application/javascript text/xml application/xml application/xml+rss text/javascript"
EOF
    fi
    
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
    cat > "$MODSEC_CONF" << EOF
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

# Optimize Nginx configuration
optimize_nginx() {
    log "Optimizing Nginx configuration..."
    create_backup
    
    # Create the optimized configuration
    cat > "$NGINX_CONF" << EOF
# HTTP to HTTPS redirect
server {
    listen 80;
    server_name $SERVER_NAME;
    return 301 https://\$host\$request_uri;
}

# HTTP server block
server {
    listen 80;
    server_name $SERVER_NAME;
    root $WEB_ROOT;
    index index.php index.html index.htm;
    client_max_body_size $CLIENT_MAX_BODY_SIZE;

    # WordPress multisite subdirectory rules
    if (!-e \$request_filename) {
        rewrite /wp-admin\$ \$scheme://\$host\$uri/ permanent;
        rewrite ^/[_0-9a-zA-Z-]+(/wp-.*) \$1 last;
        rewrite ^/[_0-9a-zA-Z-]+(/.*\.php)\$ \$1 last;
    }

    location / {
        try_files \$uri \$uri/ /index.php?\$args;
    }

    location ~ \.php\$ {
        try_files \$uri =404;
        fastcgi_split_path_info ^(.+\.php)(/.+)\$;
        fastcgi_pass unix:$PHP_FPM_SOCKET;
        fastcgi_index index.php;
        include fastcgi_params;
        fastcgi_param SCRIPT_FILENAME \$document_root\$fastcgi_script_name;
        fastcgi_param PATH_INFO \$fastcgi_path_info;
    }
}

# HTTPS server block
server {
    listen 443 ssl http2;
    server_name $SERVER_NAME;
    root $WEB_ROOT;
    index index.php index.html index.htm;
    client_max_body_size $CLIENT_MAX_BODY_SIZE;

    ssl_certificate $SSL_CERT;
    ssl_certificate_key $SSL_KEY;
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384:ECDHE-ECDSA-CHACHA20-POLY1305:ECDHE-RSA-CHACHA20-POLY1305:DHE-RSA-AES128-GCM-SHA256:DHE-RSA-AES256-GCM-SHA384;
    ssl_prefer_server_ciphers off;
    ssl_session_timeout 1d;
    ssl_session_cache shared:SSL:50m;
    ssl_session_tickets off;
    ssl_stapling on;
    ssl_stapling_verify on;
    resolver 8.8.8.8 8.8.4.4 valid=300s;
    resolver_timeout 5s;
    add_header Strict-Transport-Security "max-age=63072000" always;

    # WordPress multisite subdirectory rules
    if (!-e \$request_filename) {
        rewrite /wp-admin\$ \$scheme://\$host\$uri/ permanent;
        rewrite ^/[_0-9a-zA-Z-]+(/wp-.*) \$1 last;
        rewrite ^/[_0-9a-zA-Z-]+(/.*\.php)\$ \$1 last;
    }

    location / {
        try_files \$uri \$uri/ /index.php?\$args;
    }

    location ~ \.php\$ {
        try_files \$uri =404;
        fastcgi_split_path_info ^(.+\.php)(/.+)\$;
        fastcgi_pass unix:$PHP_FPM_SOCKET;
        fastcgi_index index.php;
        include fastcgi_params;
        fastcgi_param SCRIPT_FILENAME \$document_root\$fastcgi_script_name;
        fastcgi_param PATH_INFO \$fastcgi_path_info;
    }
}
EOF

    # Create main Nginx configuration
    cat > /etc/nginx/nginx.conf << EOF
user nginx;
worker_processes $WORKER_PROCESSES;
error_log /var/log/nginx/error.log warn;
pid /var/run/nginx.pid;

events {
    worker_connections $WORKER_CONNECTIONS;
}

http {
    include /etc/nginx/mime.types;
    default_type application/octet-stream;
    log_format main '\$remote_addr - \$remote_user [\$time_local] "\$request" '
                    '\$status \$body_bytes_sent "\$http_referer" '
                    '"\$http_user_agent" "\$http_x_forwarded_for"';
    access_log /var/log/nginx/access.log main;
    sendfile on;
    tcp_nopush on;
    tcp_nodelay on;
    keepalive_timeout $KEEPALIVE_TIMEOUT;
    types_hash_max_size 2048;
    server_tokens off;
    gzip on;
    gzip_disable "msie6";
    gzip_vary on;
    gzip_proxied any;
    gzip_comp_level 6;
    gzip_types $GZIP_TYPES;
    include /etc/nginx/conf.d/*.conf;
}
EOF

    log "Nginx configuration optimized"
}

# Main menu
main_menu() {
    while true; do
        clear
        echo -e "${BLUE}Nginx Configuration Manager${NC}"
        echo "1. Initialize Configuration"
        echo "2. Install Required Packages"
        echo "3. Configure ModSecurity"
        echo "4. Optimize Nginx Configuration"
        echo "5. Exit"
        read -p "Enter your choice (1-5): " choice
        
        case $choice in
            1) initialize_config ;;
            2) install_packages ;;
            3) configure_modsecurity ;;
            4) optimize_nginx ;;
            5) echo -e "${GREEN}Exiting...${NC}"; exit 0 ;;
            *) echo -e "${RED}Invalid choice${NC}" ;;
        esac
        
        read -p "Press Enter to continue..."
    done
}

# Start the script
check_root
main_menu 