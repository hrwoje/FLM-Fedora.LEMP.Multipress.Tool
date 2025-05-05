#!/bin/bash

# SSL Management Script
# Version: 2.2
# Author: Cursor AI, Refined by ChatGPT

set -euo pipefail
IFS=$'\n\t'

# Constants
CERT_DIR="/etc/pki/tls/certs"
KEY_DIR="/etc/pki/tls/private"
NGINX_CONF_DIR="/etc/nginx/conf.d"
NGINX_MAIN_CONF="/etc/nginx/nginx.conf"
SITE_CONF_FILE="$NGINX_CONF_DIR/multipress.conf"
LOG_DIR="/var/log/ssl-manager"
LOG_FILE="$LOG_DIR/ssl.log"
BACKUP_DIR="$NGINX_CONF_DIR/backups"
DATE=$(date +%Y%m%d_%H%M%S)

# Colors and symbols
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'
CHECK='✅'
CROSS='❌'
WARNING='⚠️'

log() {
    mkdir -p "$LOG_DIR"
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a "$LOG_FILE" >/dev/null
    echo -e "${BLUE}[LOG]${NC} $1"
}

error_exit() {
    echo -e "${RED}Error: $1${NC}" >&2
    log "ERROR: $1"
    if [ -f "$BACKUP_DIR/multipress.conf.bak" ]; then
        log "Restoring from backup..."
        cp "$BACKUP_DIR/multipress.conf.bak" "$SITE_CONF_FILE"
        systemctl restart nginx || true
    fi
    exit 1
}

check_root() {
    [ "$EUID" -ne 0 ] && error_exit "Please run as root"
}

create_backup() {
    local config_file="$1"
    mkdir -p "$BACKUP_DIR"
    if [ -f "$config_file" ]; then
        cp "$config_file" "$BACKUP_DIR/$(basename "$config_file").bak.$DATE" || error_exit "Failed to create timestamped backup"
        cp "$config_file" "$BACKUP_DIR/$(basename "$config_file").bak" || error_exit "Failed to create recovery backup"
        log "Backup created for $config_file"
    fi
}

verify_wordpress() {
    [ -f "/var/www/html/wp-config.php" ] || error_exit "WordPress not found. Please install it first."
    log "WordPress installation verified"
}

configure_ports() {
    log "Configuring firewall and SELinux ports"
    firewall-cmd --list-services | grep -q "https" || {
        firewall-cmd --permanent --add-service=https || error_exit "Failed to open HTTPS in firewall"
        firewall-cmd --reload || error_exit "Failed to reload firewall"
    }
    semanage port -l | grep -q "http_port_t.*443" || {
        semanage port -a -t http_port_t -p tcp 443 || error_exit "Failed to configure SELinux for HTTPS"
    }
}

find_cert_files() {
    local cert=$(find "$CERT_DIR" -name "localhost.pem" 2>/dev/null | head -n1)
    local key=$(find "$KEY_DIR" -name "localhost-key.pem" 2>/dev/null | head -n1)
    [ -n "$cert" ] && [ -n "$key" ] && echo "$cert:$key" || echo ""
}

install_ssl() {
    DOMAIN_STORE="/etc/ssl-manager/last-domain"
    mkdir -p /etc/ssl-manager
    
    if [ -f "$DOMAIN_STORE" ]; then
        default_domain=$(cat "$DOMAIN_STORE")
        read -rp "Enter your domain (default: $default_domain): " domain
        domain="${domain:-$default_domain}"
    else
        read -rp "Enter your domain (e.g. example.test): " domain
        [ -z "$domain" ] && error_exit "Domain cannot be empty"
    fi
    
    echo "$domain" > "$DOMAIN_STORE"
    wildcard_domain="*.$domain"
    log "Installing SSL"
    verify_wordpress
    configure_ports

    # Install required packages
    dnf install -y nss-tools ca-certificates || error_exit "Failed to install required packages"
    
    # Download and install mkcert
    log "Installing mkcert..."
    curl -JLO "https://github.com/FiloSottile/mkcert/releases/download/v1.4.4/mkcert-v1.4.4-linux-amd64" || error_exit "Failed to download mkcert"
    mv mkcert-v1.4.4-linux-amd64 /usr/local/bin/mkcert || error_exit "Failed to move mkcert"
    chmod +x /usr/local/bin/mkcert || error_exit "Failed to set mkcert permissions"
    
    # Install the local CA
    log "Installing local CA..."
    mkcert -install || error_exit "Failed to install local CA"
    
    # Create certificate directories
    mkdir -p "$CERT_DIR" "$KEY_DIR"
    
    # Generate certificates
    log "Generating certificates..."
    TMP_DIR=$(mktemp -d)
    cd "$TMP_DIR" || error_exit "Failed to enter temp directory"
    
    # Generate certificates for localhost and domain
    mkcert -cert-file "$domain.pem" -key-file "$domain-key.pem" "$domain" "$wildcard_domain" localhost 127.0.0.1 ::1 || error_exit "Certificate generation failed"
    
    # Move certificates to proper locations
    mv "$domain.pem" "$CERT_DIR/" && mv "$domain-key.pem" "$KEY_DIR/" || error_exit "Failed to move certificates"
    
    # Set proper permissions
    chmod 644 "$CERT_DIR/$domain.pem" && chmod 600 "$KEY_DIR/$domain-key.pem"
    chown root:root "$CERT_DIR/$domain.pem" "$KEY_DIR/$domain-key.pem"
    restorecon "$CERT_DIR/$domain.pem" "$KEY_DIR/$domain-key.pem"
    
    # Cleanup
    cd - > /dev/null && rm -rf "$TMP_DIR"

    local cert_file="$CERT_DIR/$domain.pem"
    local key_file="$KEY_DIR/$domain-key.pem"

    create_backup "$SITE_CONF_FILE"

    # Create Nginx configuration
    cat > "$SITE_CONF_FILE" << EOF
# Updated SSL configuration with wildcard cert for multipress
server {
    listen 80;
    server_name localhost;
    return 301 https://\$host\$request_uri;
}

server {
    listen 443 ssl http2;
    server_name localhost $domain *.$domain;
    ssl_certificate $cert_file;
    ssl_certificate_key $key_file;
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers 'ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256';
    ssl_prefer_server_ciphers on;
    ssl_session_cache shared:SSL:10m;
    ssl_session_timeout 10m;
    ssl_session_tickets off;
    ssl_stapling on;
    ssl_stapling_verify on;
    resolver 8.8.8.8 8.8.4.4 valid=300s;
    resolver_timeout 5s;
    
    root /var/www/html;
    index index.php index.html index.htm;

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
        fastcgi_pass unix:/var/run/php-fpm/www.sock;
        fastcgi_index index.php;
        fastcgi_param SCRIPT_FILENAME \$document_root\$fastcgi_script_name;
        include fastcgi_params;
    }

    location ~ /\.ht {
        deny all;
    }

    location ~* \.(engine|inc|info|install|make|module|profile|test|po|sh|.*sql|theme|tpl(\.php)?|xtmpl)\$|^(\..*|Entries.*|Repository|Root|Tag|Template)\$|\.php_ {
        deny all;
    }
}
EOF

    # Test and reload Nginx
    nginx -t || error_exit "Nginx configuration test failed"
    systemctl restart nginx || error_exit "Failed to restart Nginx"

    # Update system trust store
    log "Updating system trust store..."
    update-ca-trust || error_exit "Failed to update system trust store"

    show_summary "SSL Installation" "Certificate installed to: $SITE_CONF_FILE\nCertificate: $cert_file\nKey: $key_file\n\nPlease restart your browser to apply the new certificate trust settings."
}

remove_ssl() {
    log "Removing SSL"
    read -p "Type 'yes' to confirm SSL removal: " confirm
    [ "$confirm" != "yes" ] && echo "Cancelled" && return

    create_backup "$SITE_CONF_FILE"

    if [ -f "$BACKUP_DIR/multipress.conf.bak" ]; then
        cp "$BACKUP_DIR/multipress.conf.bak" "$SITE_CONF_FILE"
    else
        cat > "$SITE_CONF_FILE" << EOF
server {
    listen 80;
    server_name localhost;
    root /var/www/html;
    index index.php index.html index.htm;
    location / {
        try_files \$uri \$uri/ /index.php?\$args;
    }
    location ~ \.php\$ {
        try_files \$uri =404;
        fastcgi_pass unix:/var/run/php-fpm/www.sock;
        fastcgi_param SCRIPT_FILENAME \$document_root\$fastcgi_script_name;
        include fastcgi_params;
    }
    location ~ /\.ht {
        deny all;
    }
}
EOF
    fi

    rm -f "$CERT_DIR"/*.pem "$KEY_DIR"/*-key.pem
    mkcert -uninstall || true
    rm -f /usr/local/bin/mkcert

    nginx -t && systemctl reload nginx || error_exit "Failed to reload Nginx"
    show_summary "SSL Removal" "SSL configuration removed. Nginx reloaded."
}

health_check() {
    log "Running SSL health check"
    local report=()
    [ -f "$CERT_DIR/localhost.pem" ] && report+=("Cert: $CHECK") || report+=("Cert: $CROSS")
    nginx -t &> /dev/null && report+=("Nginx config: $CHECK") || report+=("Nginx config: $CROSS")
    nginx -V 2>&1 | grep -q "http_ssl_module" && report+=("SSL Module: $CHECK") || report+=("SSL Module: $CROSS")
    firewall-cmd --list-services | grep -q "https" && report+=("HTTPS Firewall: $CHECK") || report+=("HTTPS Firewall: $CROSS")
    
    show_summary "SSL Health Check" "$(printf '%s\n' "${report[@]}")"
}

configure_http_redirect() {
    log "Configuring HTTP to HTTPS redirect"
    
    create_backup "$SITE_CONF_FILE"
    
    # Get the domain from the store
    DOMAIN_STORE="/etc/ssl-manager/last-domain"
    if [ ! -f "$DOMAIN_STORE" ]; then
        error_exit "Domain store not found. Please install SSL first (option 1)."
    fi
    domain=$(cat "$DOMAIN_STORE")
    
    # Check if SSL is installed
    cert_file="$CERT_DIR/$domain.pem"
    key_file="$KEY_DIR/$domain-key.pem"
    
    if [ ! -f "$cert_file" ] || [ ! -f "$key_file" ]; then
        error_exit "SSL certificates not found. Please install SSL first (option 1)."
    fi
    
    # Create new configuration with proper redirect
    cat > "$SITE_CONF_FILE" << EOF
# HTTP to HTTPS redirect configuration
server {
    listen 80 default_server;
    listen [::]:80 default_server;
    server_name $domain *.$domain localhost;
    
    # Redirect all HTTP traffic to HTTPS
    location / {
        return 301 https://\$server_name\$request_uri;
    }
}

server {
    listen 443 ssl http2 default_server;
    listen [::]:443 ssl http2 default_server;
    server_name $domain *.$domain localhost;
    
    # SSL configuration
    ssl_certificate $cert_file;
    ssl_certificate_key $key_file;
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers 'ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256';
    ssl_prefer_server_ciphers on;
    ssl_session_cache shared:SSL:10m;
    ssl_session_timeout 10m;
    ssl_session_tickets off;
    ssl_stapling on;
    ssl_stapling_verify on;
    resolver 8.8.8.8 8.8.4.4 valid=300s;
    resolver_timeout 5s;
    
    # HSTS (uncomment if you're sure)
    # add_header Strict-Transport-Security "max-age=63072000" always;
    
    root /var/www/html;
    index index.php index.html index.htm;

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
        fastcgi_pass unix:/var/run/php-fpm/www.sock;
        fastcgi_index index.php;
        fastcgi_param SCRIPT_FILENAME \$document_root\$fastcgi_script_name;
        include fastcgi_params;
    }

    location ~ /\.ht {
        deny all;
    }

    location ~* \.(engine|inc|info|install|make|module|profile|test|po|sh|.*sql|theme|tpl(\.php)?|xtmpl)\$|^(\..*|Entries.*|Repository|Root|Tag|Template)\$|\.php_ {
        deny all;
    }
}
EOF
    
    # Test and reload Nginx
    nginx -t || error_exit "Nginx configuration test failed"
    systemctl restart nginx || error_exit "Failed to restart Nginx"
    
    show_summary "HTTP Redirect" "HTTP to HTTPS redirect has been configured successfully.\nAll HTTP traffic will now be redirected to HTTPS."
}

show_summary() {
    local title="$1"
    local details="$2"
    
    clear
    echo -e "${GREEN}$title${NC}"
    echo "========================================="
    echo -e "$details"
    echo "========================================="
    echo -e "${YELLOW}Press Enter to continue...${NC}"
    read
}

# Main menu
while true; do
    clear
    echo -e "${BLUE}SSL Management Menu${NC}"
    echo "1. Install SSL"
    echo "2. Remove SSL"
    echo "3. Health Check"
    echo "4. Configure HTTP to HTTPS Redirect"
    echo "5. Exit"
    read -p "Enter your choice (1-5): " choice

    case $choice in
        1) install_ssl ;;
        2) remove_ssl ;;
        3) health_check ;;
        4) configure_http_redirect ;;
        5) echo -e "${GREEN}Exiting...${NC}"; exit 0 ;;
        *) echo -e "${RED}Invalid choice. Please try again.${NC}"; sleep 2 ;;
    esac
done
