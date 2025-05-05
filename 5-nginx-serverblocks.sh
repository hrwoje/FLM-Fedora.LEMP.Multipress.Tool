#!/bin/bash

# Nginx Server Block Manager for Fedora
# Version: 1.0
# Author: Cursor AI

# Configuration
set -euo pipefail
IFS=$'\n\t'

# Constants
NGINX_CONF_DIR="/etc/nginx"
SNIPPETS_DIR="$NGINX_CONF_DIR/snippets"
CONF_BACKUP_DIR="/etc/nginx/backups"
LOG_FILE="/var/log/nginx-manager.log"
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

# Check if Nginx is installed
check_nginx() {
    if ! command -v nginx &> /dev/null; then
        error_exit "Nginx is not installed"
    fi
}

# Backup Nginx configuration
backup_config() {
    local backup_dir="$CONF_BACKUP_DIR/$DATE"
    mkdir -p "$backup_dir"
    
    # Exclude the backups directory from the copy
    find "$NGINX_CONF_DIR" -maxdepth 1 -type f -exec cp {} "$backup_dir/" \;
    find "$NGINX_CONF_DIR" -maxdepth 1 -type d -not -path "$CONF_BACKUP_DIR" -exec cp -r {} "$backup_dir/" \;
    
    log "Configuration backed up to $backup_dir"
}

# Create security headers snippet
create_security_headers() {
    local file="$SNIPPETS_DIR/security-headers.conf"
    mkdir -p "$SNIPPETS_DIR"
    
    # Backup current configuration if it exists
    if [ -f "$file" ]; then
        backup_config
    fi
    
    cat > "$file" << 'EOF'
# Security Headers Configuration
add_header Strict-Transport-Security "max-age=31536000; includeSubDomains; preload" always;
add_header X-Frame-Options "SAMEORIGIN" always;
add_header X-Content-Type-Options "nosniff" always;
add_header Referrer-Policy "no-referrer-when-downgrade" always;
add_header Permissions-Policy "camera=(), microphone=(), geolocation=()" always;
add_header Content-Security-Policy "default-src 'self'; script-src 'self' 'unsafe-inline' 'unsafe-eval' https:; style-src 'self' 'unsafe-inline' https:; img-src 'self' data: https:; font-src 'self' https: data:; connect-src 'self' https:; frame-src 'self' https:; media-src 'self' https:; object-src 'none';" always;

# Remove server tokens
server_tokens off;
more_clear_headers Server;
more_clear_headers X-Powered-By;
EOF

    # Set proper permissions
    chown root:root "$file"
    chmod 644 "$file"
    log "Security headers configuration created"
    
    # Test and reload Nginx configuration
    echo -e "${BLUE}Testing Nginx configuration...${NC}"
    if ! nginx -t; then
        error_exit "Nginx configuration test failed after updating security headers"
    fi
    
    echo -e "${BLUE}Reloading Nginx to apply security headers...${NC}"
    systemctl reload nginx || error_exit "Failed to reload Nginx after updating security headers"
    
    log "Nginx reloaded successfully after security headers update"
    echo -e "${GREEN}Security headers updated and Nginx reloaded successfully!${NC}"
    
    # Show summary
    clear
    echo -e "${GREEN}Operation Summary${NC}"
    echo "========================================="
    echo -e "${BLUE}Action:${NC} Update Security Headers"
    echo -e "${BLUE}Status:${NC} Successfully updated and applied"
    echo -e "${BLUE}Configuration Test:${NC} Passed"
    echo -e "${BLUE}Nginx Status:${NC} Successfully reloaded"
    echo -e "${BLUE}Backup Location:${NC} $CONF_BACKUP_DIR/$DATE"
    echo "========================================="
    echo -e "${YELLOW}Press Enter to continue...${NC}"
    read
}

# Create caching configuration
create_caching_config() {
    local file="$SNIPPETS_DIR/caching.conf"
    
    cat > "$file" << 'EOF'
# Caching Configuration
location ~* \.(jpg|jpeg|png|webp|svg|gif|ico)$ {
    expires 1y;
    add_header Cache-Control "public, no-transform";
}

location ~* \.(css|js)$ {
    expires 1y;
    add_header Cache-Control "public, no-transform";
}

location ~* \.(woff|woff2|eot|ttf)$ {
    expires 1y;
    add_header Cache-Control "public, no-transform";
}

location ~* \.(pdf|docx|zip|json)$ {
    expires 1y;
    add_header Cache-Control "public, no-transform";
}

# Dynamic content
location ~ \.php$ {
    expires off;
    add_header Cache-Control "no-store, no-cache, must-revalidate, max-age=0";
}
EOF

    # Set proper permissions
    chown root:root "$file"
    chmod 644 "$file"
    log "Caching configuration created"
}

# Create compression configuration
create_compression_config() {
    local file="$SNIPPETS_DIR/compression.conf"
    
    cat > "$file" << 'EOF'
# Compression Configuration
gzip on;
gzip_vary on;
gzip_proxied any;
gzip_comp_level 6;
gzip_types text/plain text/css text/xml application/json application/javascript application/xml+rss application/atom+xml image/svg+xml;

# Brotli compression (if available)
brotli on;
brotli_comp_level 6;
brotli_types text/plain text/css text/xml application/json application/javascript application/xml+rss application/atom+xml image/svg+xml;
EOF

    # Set proper permissions
    chown root:root "$file"
    chmod 644 "$file"
    log "Compression configuration created"
}

# Create upload configuration
create_upload_config() {
    local file="$SNIPPETS_DIR/upload.conf"
    
    cat > "$file" << 'EOF'
# Upload Configuration
client_max_body_size 256M;
client_body_timeout 300s;
client_header_timeout 300s;
keepalive_timeout 300s;

# Allow specific file types
location ~* \.(jpg|jpeg|png|webp|svg|gif|mp4|pdf|zip|docx|json|woff2)$ {
    client_max_body_size 256M;
}
EOF

    # Set proper permissions
    chown root:root "$file"
    chmod 644 "$file"
    log "Upload configuration created"
}

# Create performance configuration
create_performance_config() {
    local file="$SNIPPETS_DIR/performance.conf"
    
    cat > "$file" << 'EOF'
# Performance Configuration
sendfile on;
tcp_nopush on;
tcp_nodelay on;
keepalive_timeout 65;
types_hash_max_size 2048;

# Buffer size for POST submissions
client_body_buffer_size 128k;

# Buffer size for Headers
client_header_buffer_size 1k;

# Max time to receive client headers/body
client_body_timeout 12;
client_header_timeout 12;

# Max time to keep a connection open for
keepalive_timeout 15;

# Max time for the client accept/receive a response
send_timeout 10;

# Skip buffering for static files
sendfile_max_chunk 1m;

# Optimize log format
log_format main '$remote_addr - $remote_user [$time_local] "$request" '
                '$status $body_bytes_sent "$http_referer" '
                '"$http_user_agent" "$http_x_forwarded_for"';

# Disable etag
etag off;
EOF

    # Set proper permissions
    chown root:root "$file"
    chmod 644 "$file"
    log "Performance configuration created"
}

# Add summary function
show_summary() {
    local action="$1"
    local domain="$2"
    local wp_path="$3"
    local is_multisite="$4"
    local multisite_type="$5"
    
    clear
    echo -e "${GREEN}Operation Summary${NC}"
    echo "========================================="
    echo -e "${BLUE}Action:${NC} $action"
    echo -e "${BLUE}Domain:${NC} $domain"
    echo -e "${BLUE}WordPress Path:${NC} $wp_path"
    
    if [ "$is_multisite" = true ]; then
        echo -e "${BLUE}Multisite Type:${NC} $([ "$multisite_type" = "1" ] && echo "Subdirectory" || echo "Subdomain")"
    fi
    
    echo -e "${BLUE}Configuration Files Created:${NC}"
    echo "  - $SNIPPETS_DIR/security-headers.conf"
    echo "  - $SNIPPETS_DIR/caching.conf"
    echo "  - $SNIPPETS_DIR/compression.conf"
    echo "  - $SNIPPETS_DIR/upload.conf"
    echo "  - $SNIPPETS_DIR/performance.conf"
    
    echo -e "${BLUE}Backup Location:${NC} $CONF_BACKUP_DIR/$DATE"
    echo "========================================="
    echo -e "${YELLOW}Press Enter to return to the main menu...${NC}"
    read
}

# Install server block
install_server_block() {
    local domain
    local wp_path
    local is_multisite
    local multisite_type
    
    # Get domain name
    read -p "Enter domain name (e.g., example.com): " domain
    
    # Get WordPress path
    read -p "Enter WordPress installation path (default: /var/www/html): " wp_path
    wp_path=${wp_path:-/var/www/html}
    
    # Check if multisite
    if get_yes_no "Is this a WordPress Multisite installation?" "n"; then
        is_multisite=true
        echo "Choose Multisite type:"
        echo "1) Subdirectory"
        echo "2) Subdomain"
        read -p "Enter your choice (1-2): " multisite_type
    else
        is_multisite=false
        multisite_type=""
    fi
    
    # Create server block
    local server_block="$NGINX_CONF_DIR/conf.d/$domain.conf"
    
    # Backup current configuration
    backup_config
    
    # Create all configuration files
    create_security_headers
    create_caching_config
    create_compression_config
    create_upload_config
    create_performance_config
    
    cat > "$server_block" << EOF
server {
    listen 80;
    server_name $domain www.$domain;
    root $wp_path;
    index index.php index.html index.htm;

    # Include all configurations
    include $SNIPPETS_DIR/security-headers.conf;
    include $SNIPPETS_DIR/caching.conf;
    include $SNIPPETS_DIR/compression.conf;
    include $SNIPPETS_DIR/upload.conf;
    include $SNIPPETS_DIR/performance.conf;

    # WordPress configuration
    location / {
        try_files \$uri \$uri/ /index.php?\$args;
    }

    # PHP configuration
    location ~ \.php$ {
        fastcgi_pass unix:/var/run/php-fpm/php-fpm.sock;
        fastcgi_index index.php;
        fastcgi_param SCRIPT_FILENAME \$document_root\$fastcgi_script_name;
        include fastcgi_params;
    }

    # Multisite configuration
EOF

    if [ "$is_multisite" = true ]; then
        if [ "$multisite_type" = "1" ]; then
            cat >> "$server_block" << 'EOF'
    # Subdirectory multisite
    location ~ ^/[_0-9a-zA-Z-]+/files/(.*)$ {
        try_files /wp-content/blogs.dir/$blogid/files/$2 /wp-includes/ms-files.php?file=$2 ;
        access_log off; log_not_found off; expires max;
    }

    if (!-e $request_filename) {
        rewrite /wp-admin$ $scheme://$host$uri/ permanent;
        rewrite ^/[_0-9a-zA-Z-]+(/wp-.*) $1 last;
        rewrite ^/[_0-9a-zA-Z-]+(/.*\.php)$ $1 last;
    }
EOF
        else
            cat >> "$server_block" << 'EOF'
    # Subdomain multisite
    location ~ ^/files/(.*)$ {
        try_files /wp-content/blogs.dir/$blogid/files/$2 /wp-includes/ms-files.php?file=$2 ;
        access_log off; log_not_found off; expires max;
    }

    if (!-e $request_filename) {
        rewrite /wp-admin$ $scheme://$host$uri/ permanent;
        rewrite ^(/[^/]+)?(/wp-.*) $2 last;
        rewrite ^(/[^/]+)?(/.*\.php)$ $2 last;
    }
EOF
        fi
    fi

    # Close server block
    echo "}" >> "$server_block"
    
    # Set proper permissions
    chown root:root "$server_block"
    chmod 644 "$server_block"
    
    log "Server block created for $domain"
    echo -e "${GREEN}Server block created successfully!${NC}"
    
    # Show summary
    show_summary "Install Server Block" "$domain" "$wp_path" "$is_multisite" "$multisite_type"
}

# Reset server block to default
reset_server_block() {
    local domain
    read -p "Enter domain name to reset (e.g., example.com): " domain
    
    local server_block="$NGINX_CONF_DIR/conf.d/$domain.conf"
    if [ ! -f "$server_block" ]; then
        error_exit "Server block for $domain not found"
    fi
    
    # Backup current configuration
    backup_config
    
    # Create default server block
    cat > "$server_block" << EOF
server {
    listen 80;
    server_name $domain www.$domain;
    root /var/www/html;
    index index.php index.html index.htm;

    location / {
        try_files \$uri \$uri/ /index.php?\$args;
    }

    location ~ \.php$ {
        fastcgi_pass unix:/var/run/php-fpm/php-fpm.sock;
        fastcgi_index index.php;
        fastcgi_param SCRIPT_FILENAME \$document_root\$fastcgi_script_name;
        include fastcgi_params;
    }
}
EOF
    
    log "Server block reset for $domain"
    echo -e "${GREEN}Server block reset successfully!${NC}"
    
    # Show summary
    show_summary "Reset Server Block" "$domain" "/var/www/html" "false" ""
}

# Restart Nginx
restart_nginx() {
    echo -e "${BLUE}Testing Nginx configuration...${NC}"
    if ! nginx -t; then
        error_exit "Nginx configuration test failed"
    fi
    
    echo -e "${BLUE}Reloading Nginx...${NC}"
    systemctl reload nginx || error_exit "Failed to reload Nginx"
    
    log "Nginx reloaded successfully"
    echo -e "${GREEN}Nginx reloaded successfully!${NC}"
    
    # Show summary
    clear
    echo -e "${GREEN}Operation Summary${NC}"
    echo "========================================="
    echo -e "${BLUE}Action:${NC} Restart Nginx"
    echo -e "${BLUE}Status:${NC} Successfully reloaded"
    echo -e "${BLUE}Configuration Test:${NC} Passed"
    echo "========================================="
    echo -e "${YELLOW}Press Enter to return to the main menu...${NC}"
    read
}

# Main menu
show_menu() {
    while true; do
        clear
        echo -e "${GREEN}Nginx Server Block Manager${NC}"
        echo "1. Install Server Block"
        echo "2. Reset Server Block to Default"
        echo "3. Restart Nginx"
        echo "4. Exit"
        
        read -p "Enter your choice (1-4): " choice
        
        case $choice in
            1)
                install_server_block
                ;;
            2)
                reset_server_block
                ;;
            3)
                restart_nginx
                ;;
            4)
                echo "Exiting..."
                exit 0
                ;;
            *)
                echo "Invalid choice. Please try again."
                ;;
        esac
        
        read -p "Press Enter to continue..."
    done
}

# Helper function for yes/no questions
get_yes_no() {
    local prompt="$1"
    local default="$2"
    local input
    
    while true; do
        read -p "$prompt (y/n) [$default]: " input
        input=${input:-$default}
        case $input in
            [Yy]* ) return 0;;
            [Nn]* ) return 1;;
            * ) echo "Please answer yes or no.";;
        esac
    done
}

# Main execution
check_root
check_nginx
show_menu 