#!/bin/bash

# WordPress Multisite Activation Script
# Version: 1.0
# Author: Cursor AI

# Configuration
set -euo pipefail
IFS=$'\n\t'

# Constants
WP_PATH="/var/www/html"
WP_CONFIG="$WP_PATH/wp-config.php"
MODE="subdirectory"  # Changed from "subdomain" to "subdirectory"
NGINX_CONF="/etc/nginx/nginx.conf"
DOMAIN="localhost"
LOG_FILE="/var/log/multipress.log"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Summary function
show_summary() {
    echo -e "\n${BLUE}=== Operation Summary ===${NC}"
    echo -e "${GREEN}Operation completed at: $(date)${NC}"
    echo -e "${YELLOW}WordPress Path: $WP_PATH${NC}"
    echo -e "${YELLOW}Multisite Mode: $MODE${NC}"
    echo -e "${YELLOW}Domain: $DOMAIN${NC}"
    echo -e "${YELLOW}Log File: $LOG_FILE${NC}"
    echo -e "${BLUE}========================${NC}\n"
    read -p "Press Enter to return to the main menu..."
    clear
}

# Logging function
log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" | sudo tee -a "$LOG_FILE" >/dev/null
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

# Install WP-CLI if not present
install_wp_cli() {
    if ! command -v wp &> /dev/null; then
        log "Installing WP-CLI..."
        curl -O https://raw.githubusercontent.com/wp-cli/builds/gh-pages/phar/wp-cli.phar || error_exit "Failed to download WP-CLI"
        chmod +x wp-cli.phar || error_exit "Failed to make WP-CLI executable"
        sudo mv wp-cli.phar /usr/local/bin/wp || error_exit "Failed to move WP-CLI to PATH"
        log "WP-CLI installed successfully"
    fi
}

# Show menu
show_menu() {
    while true; do
        clear
        echo -e "${BLUE}WordPress Multisite Manager${NC}"
        echo "1. Activate Multisite"
        echo "2. Deactivate Multisite"
        echo "3. Health Check"
        echo "4. Cookie Fix"
        echo "5. Exit"
        read -p "Enter your choice (1-5): " choice
        
        case $choice in
            1) activate_multisite ;;
            2) deactivate_multisite ;;
            3) health_check ;;
            4) cookie_fix ;;
            5) echo -e "${GREEN}Exiting...${NC}"; exit 0 ;;
            *) echo -e "${RED}Invalid choice. Please try again.${NC}"; sleep 2 ;;
        esac
    done
}

# Configure NGINX
configure_nginx() {
    log "Configuring NGINX"
    
    # Check if configuration already exists
    if [ -f "/etc/nginx/conf.d/localhost.conf" ]; then
        log "NGINX configuration already exists, skipping creation"
        return
    fi
    
    # Create properly formatted nginx configuration
    cat > /etc/nginx/conf.d/localhost.conf << 'EOF'
server {
    listen 80;
    server_name localhost;
    root /var/www/html;
    index index.php index.html index.htm;

    location / {
        try_files $uri $uri/ /index.php?$args;
    }

    location ~ \.php$ {
        fastcgi_pass unix:/var/run/php-fpm/www.sock;
        fastcgi_param SCRIPT_FILENAME $document_root$fastcgi_script_name;
        include fastcgi_params;
    }
}
EOF
    
    # Set correct permissions
    chown root:root /etc/nginx/conf.d/localhost.conf
    chmod 644 /etc/nginx/conf.d/localhost.conf
    
    # Test and reload nginx
    nginx -t || error_exit "NGINX configuration test failed"
    systemctl restart nginx || error_exit "Failed to restart NGINX"
    
    log "NGINX configuration completed"
}

# Activate Multisite
activate_multisite() {
    log "Starting Multisite activation"
    
    # Check if multisite is already active
    if grep -q "define('MULTISITE', true);" "$WP_CONFIG"; then
        echo -e "${YELLOW}Multisite is already active. Skipping activation.${NC}"
        show_summary
        return
    fi
    
    # Install WP-CLI if needed
    install_wp_cli
    
    # Check if WordPress is installed
    if [ ! -f "$WP_CONFIG" ]; then
        error_exit "WordPress not found at $WP_PATH"
    fi
    
    # Backup wp-config.php if it doesn't exist
    if [ ! -f "${WP_CONFIG}.bak" ]; then
        cp "$WP_CONFIG" "${WP_CONFIG}.bak"
        log "Created backup of wp-config.php"
    fi
    
    # Check if wp-config.php needs to be updated
    if ! grep -q "WP_ALLOW_MULTISITE" "$WP_CONFIG"; then
        # Extract database settings from existing wp-config.php
        DB_NAME=$(grep -oP "define\('DB_NAME',\s*'[^']*'" "$WP_CONFIG" | cut -d"'" -f4)
        DB_USER=$(grep -oP "define\('DB_USER',\s*'[^']*'" "$WP_CONFIG" | cut -d"'" -f4)
        DB_PASSWORD=$(grep -oP "define\('DB_PASSWORD',\s*'[^']*'" "$WP_CONFIG" | cut -d"'" -f4)
        DB_HOST=$(grep -oP "define\('DB_HOST',\s*'[^']*'" "$WP_CONFIG" | cut -d"'" -f4)
        DB_CHARSET=$(grep -oP "define\('DB_CHARSET',\s*'[^']*'" "$WP_CONFIG" | cut -d"'" -f4)
        DB_COLLATE=$(grep -oP "define\('DB_COLLATE',\s*'[^']*'" "$WP_CONFIG" | cut -d"'" -f4)
        
        # Extract authentication keys from existing wp-config.php
        AUTH_KEY=$(grep -oP "define\('AUTH_KEY',\s*'[^']*'" "$WP_CONFIG" | cut -d"'" -f4)
        SECURE_AUTH_KEY=$(grep -oP "define\('SECURE_AUTH_KEY',\s*'[^']*'" "$WP_CONFIG" | cut -d"'" -f4)
        LOGGED_IN_KEY=$(grep -oP "define\('LOGGED_IN_KEY',\s*'[^']*'" "$WP_CONFIG" | cut -d"'" -f4)
        NONCE_KEY=$(grep -oP "define\('NONCE_KEY',\s*'[^']*'" "$WP_CONFIG" | cut -d"'" -f4)
        AUTH_SALT=$(grep -oP "define\('AUTH_SALT',\s*'[^']*'" "$WP_CONFIG" | cut -d"'" -f4)
        SECURE_AUTH_SALT=$(grep -oP "define\('SECURE_AUTH_SALT',\s*'[^']*'" "$WP_CONFIG" | cut -d"'" -f4)
        LOGGED_IN_SALT=$(grep -oP "define\('LOGGED_IN_SALT',\s*'[^']*'" "$WP_CONFIG" | cut -d"'" -f4)
        NONCE_SALT=$(grep -oP "define\('NONCE_SALT',\s*'[^']*'" "$WP_CONFIG" | cut -d"'" -f4)
        
        # Extract table prefix from existing wp-config.php
        TABLE_PREFIX=$(grep -oP "\$table_prefix\s*=\s*'[^']*'" "$WP_CONFIG" | cut -d"'" -f2)
        
        # Create properly formatted wp-config.php with existing settings
        cat > "$WP_CONFIG" << EOF
<?php
/**
 * The base configuration for WordPress
 */

// ** Database settings - You can get this info from your web host ** //
define('DB_NAME', '$DB_NAME');
define('DB_USER', '$DB_USER');
define('DB_PASSWORD', '$DB_PASSWORD');
define('DB_HOST', '$DB_HOST');
define('DB_CHARSET', '$DB_CHARSET');
define('DB_COLLATE', '$DB_COLLATE');

/**#@+
 * Authentication unique keys and salts.
 */
define('AUTH_KEY',         '$AUTH_KEY');
define('SECURE_AUTH_KEY',  '$SECURE_AUTH_KEY');
define('LOGGED_IN_KEY',    '$LOGGED_IN_KEY');
define('NONCE_KEY',        '$NONCE_KEY');
define('AUTH_SALT',        '$AUTH_SALT');
define('SECURE_AUTH_SALT', '$SECURE_AUTH_SALT');
define('LOGGED_IN_SALT',   '$LOGGED_IN_SALT');
define('NONCE_SALT',       '$NONCE_SALT');

/**#@-*/

/**
 * WordPress database table prefix.
 */
\$table_prefix = '$TABLE_PREFIX';

/**
 * For developers: WordPress debugging mode.
 */
define('WP_DEBUG', false);

/* That's all, stop editing! Happy publishing. */

/** Absolute path to the WordPress directory. */
if (!defined('ABSPATH')) {
    define('ABSPATH', __DIR__ . '/');
}

/** Sets up WordPress vars and included files. */
require_once ABSPATH . 'wp-settings.php';
EOF
        log "Created new wp-config.php with existing database settings"
    fi
    
    # Add WP_ALLOW_MULTISITE if not present
    if ! grep -q "WP_ALLOW_MULTISITE" "$WP_CONFIG"; then
        sed -i "/\/\* That's all, stop editing! Happy publishing. \*\//i define('WP_ALLOW_MULTISITE', true);" "$WP_CONFIG"
        log "Added WP_ALLOW_MULTISITE to wp-config.php"
    fi
    
    # Initialize Multisite using WP-CLI if not already done
    if ! grep -q "define('MULTISITE', true);" "$WP_CONFIG"; then
        if [ "$MODE" = "subdomain" ]; then
            wp core multisite-convert --path="$WP_PATH" --allow-root || error_exit "Failed to convert to subdomain Multisite"
        else
            wp core multisite-convert --path="$WP_PATH" --allow-root || error_exit "Failed to convert to subdirectory Multisite"
        fi
        log "Converted WordPress to multisite mode"
    fi
    
    # Add Multisite constants if not present
    if ! grep -q "define('MULTISITE', true);" "$WP_CONFIG"; then
        sed -i "/\/\* That's all, stop editing! Happy publishing. \*\//i \
define('MULTISITE', true);\n\
define('SUBDOMAIN_INSTALL', $( [ \"$MODE\" = \"subdomain\" ] && echo \"true\" || echo \"false\" ));\n\
define('DOMAIN_CURRENT_SITE', '$DOMAIN');\n\
define('PATH_CURRENT_SITE', '/');\n\
define('SITE_ID_CURRENT_SITE', 1);\n\
define('BLOG_ID_CURRENT_SITE', 1);" "$WP_CONFIG"
        log "Added multisite constants to wp-config.php"
    fi
    
    # Configure NGINX
    configure_nginx
    
    # Configure SELinux
    configure_selinux
    
    # Restart services
    systemctl restart nginx php-fpm mariadb
    
    log "Multisite activation completed"
    echo -e "${GREEN}Multisite activated successfully!${NC}"
    show_summary
}

# Configure SELinux
configure_selinux() {
    log "Configuring SELinux"
    
    # Set file contexts
    semanage fcontext -a -t httpd_sys_rw_content_t "$WP_PATH(/.*)?" || error_exit "Failed to set SELinux context"
    restorecon -Rv "$WP_PATH" || error_exit "Failed to restore SELinux context"
    
    # Set booleans
    setsebool -P httpd_can_network_connect_db on || error_exit "Failed to set SELinux boolean"
    
    log "SELinux configuration completed"
}

# Health Check
health_check() {
    log "Starting health check"
    local issues=0
    
    # Create necessary directories if they don't exist
    echo -e "${BLUE}Creating necessary directories...${NC}"
    sudo mkdir -p /var/lib/php-fpm
    sudo mkdir -p /var/log/php-fpm
    sudo mkdir -p /var/lib/nginx
    sudo mkdir -p /var/log/nginx
    sudo mkdir -p /var/lib/mysql
    sudo mkdir -p /var/log/mariadb
    
    # Fix directory permissions
    echo -e "${BLUE}Fixing directory permissions...${NC}"
    
    # Nginx permissions
    sudo chown -R nginx:nginx /var/log/nginx
    sudo chmod -R 755 /var/log/nginx
    sudo chown -R nginx:nginx /var/lib/nginx
    sudo chmod -R 755 /var/lib/nginx
    
    # MariaDB permissions
    sudo chown -R mysql:mysql /var/lib/mysql
    sudo chmod -R 755 /var/lib/mysql
    sudo chown -R mysql:mysql /var/log/mariadb
    sudo chmod -R 755 /var/log/mariadb
    
    # PHP-FPM permissions
    sudo chown -R nginx:nginx /var/lib/php-fpm
    sudo chmod -R 755 /var/lib/php-fpm
    sudo chown -R nginx:nginx /var/log/php-fpm
    sudo chmod -R 755 /var/log/php-fpm
    
    # Check wp-config.php
    echo -e "${BLUE}Checking wp-config.php...${NC}"
    if ! grep -q "MULTISITE" "$WP_CONFIG"; then
        echo -e "${RED}MULTISITE not defined in wp-config.php${NC}"
        ((issues++))
    fi
    
    # Check database tables
    echo -e "${BLUE}Checking database tables...${NC}"
    if ! wp db query "SHOW TABLES LIKE 'wp_blogs'" --path="$WP_PATH" | grep -q "wp_blogs"; then
        echo -e "${RED}wp_blogs table not found${NC}"
        ((issues++))
    fi
    
    # Check NGINX configuration
    echo -e "${BLUE}Checking NGINX configuration...${NC}"
    if [ "$MODE" = "subdomain" ] && ! grep -q "server_name localhost \*.localhost" "$NGINX_CONF"; then
        echo -e "${RED}NGINX server_name not configured for subdomains${NC}"
        ((issues++))
    fi
    
    # Check SELinux
    echo -e "${BLUE}Checking SELinux...${NC}"
    if ! ls -Z "$WP_PATH" | grep -q "httpd_sys_rw_content_t"; then
        echo -e "${RED}SELinux context not set correctly${NC}"
        ((issues++))
    fi
    
    # Check and start services
    echo -e "${BLUE}Checking and starting services...${NC}"
    for service in nginx php-fpm mariadb; do
        if ! systemctl is-active "$service" >/dev/null; then
            echo -e "${YELLOW}$service is not running, attempting to start...${NC}"
            sudo systemctl start "$service" || {
                echo -e "${RED}Failed to start $service${NC}"
                ((issues++))
            }
        fi
        # Enable services to start on boot
        sudo systemctl enable "$service" || {
            echo -e "${RED}Failed to enable $service${NC}"
            ((issues++))
        }
    done
    
    if [ $issues -eq 0 ]; then
        echo -e "${GREEN}All checks passed successfully!${NC}"
    else
        echo -e "${YELLOW}Found $issues issues${NC}"
    fi
    
    log "Health check completed with $issues issues"
    show_summary
}

# Deactivate Multisite
deactivate_multisite() {
    log "Starting Multisite deactivation"
    
    # Remove Multisite definitions from wp-config.php
    sed -i "/define('MULTISITE'/d" "$WP_CONFIG"
    sed -i "/define('SUBDOMAIN_INSTALL'/d" "$WP_CONFIG"
    sed -i "/define('DOMAIN_CURRENT_SITE'/d" "$WP_CONFIG"
    sed -i "/define('PATH_CURRENT_SITE'/d" "$WP_CONFIG"
    sed -i "/define('SITE_ID_CURRENT_SITE'/d" "$WP_CONFIG"
    sed -i "/define('BLOG_ID_CURRENT_SITE'/d" "$WP_CONFIG"
    
    # Restore NGINX configuration
    sed -i "/server_name/s/localhost \*.localhost/localhost/" "$NGINX_CONF"
    
    # Restart services
    systemctl restart nginx php-fpm mariadb
    
    log "Multisite deactivation completed"
    echo -e "${GREEN}Multisite deactivated successfully!${NC}"
    show_summary
}

# Cookie Fix function
cookie_fix() {
    log "Starting Cookie Fix"
    echo -e "${BLUE}Applying Cookie Fix...${NC}"
    
    # Apply the nginx configuration fix
    sudo bash -c 'printf "server {\n    listen 80;\n    server_name localhost;\n    root /var/www/html;\n    index index.php index.html index.htm;\n\n    # WordPress multisite subdirectory rules\n    if (!-e \$request_filename) {\n        rewrite /wp-admin\$ \$scheme://\$host\$uri/ permanent;\n        rewrite ^/[_0-9a-zA-Z-]+(/wp-.*) \$1 last;\n        rewrite ^/[_0-9a-zA-Z-]+(/.*\.php)\$ \$1 last;\n    }\n\n    location / {\n        try_files \$uri \$uri/ /index.php?\$args;\n    }\n\n    location ~ \.php\$ {\n        try_files \$uri =404;\n        fastcgi_split_path_info ^(.+\.php)(/.+)\$;\n        fastcgi_pass unix:/var/run/php-fpm/www.sock;\n        fastcgi_index index.php;\n        fastcgi_param SCRIPT_FILENAME \$document_root\$fastcgi_script_name;\n        include fastcgi_params;\n    }\n\n    # Deny access to .htaccess files\n    location ~ /\.ht {\n        deny all;\n    }\n\n    # Deny access to sensitive files\n    location ~* \.(engine|inc|info|install|make|module|profile|test|po|sh|.*sql|theme|tpl(\.php)?|xtmpl)\$|^(\..*|Entries.*|Repository|Root|Tag|Template)\$|\.php_ {\n        deny all;\n    }\n}" > /etc/nginx/conf.d/localhost.conf'
    
    # Test and restart nginx
    if sudo nginx -t; then
        sudo systemctl restart nginx
        echo -e "${GREEN}Cookie Fix applied successfully!${NC}"
        log "Cookie Fix completed successfully"
    else
        echo -e "${RED}Failed to apply Cookie Fix. Please check nginx configuration.${NC}"
        log "Cookie Fix failed - nginx configuration test failed"
    fi
    
    show_summary
}

# Main execution
check_root
show_menu
