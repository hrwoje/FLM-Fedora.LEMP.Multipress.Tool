#!/bin/bash

# WordPress Manager Script for Fedora
# Version: 1.0
# Author: Cursor AI

# Configuration
set -euo pipefail
IFS=$'\n\t'

# Constants
LOG_FILE="/var/log/wp-installer.log"
WP_CLI_URL="https://raw.githubusercontent.com/wp-cli/builds/gh-pages/phar/wp-cli.phar"
WP_CLI_PATH="/usr/local/bin/wp"
WP_DEFAULT_DIR="/var/www/html"
TEMP_DIR=$(mktemp -d)

# Colors and symbols
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'
CHECK='✅'
CROSS='❌'
WARNING='⚠️'

# Cleanup function
cleanup() {
    rm -rf "$TEMP_DIR"
    exit
}
trap cleanup EXIT

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

# Check if required services are running
check_services() {
    if ! systemctl is-active nginx &> /dev/null; then
        error_exit "NGINX is not running. Please start it first."
    fi
    
    if ! systemctl is-active php-fpm &> /dev/null; then
        error_exit "PHP-FPM is not running. Please start it first."
    fi
    
    if ! systemctl is-active mariadb &> /dev/null; then
        error_exit "MySQL is not running. Please start it first."
    fi
    
    log "All required services are running"
}

# Generate random password
generate_password() {
    tr -dc 'A-Za-z0-9!@#$%^&*()_+{}|:<>?=' < /dev/urandom | head -c 16
}

# Get user input with default value
get_input() {
    local prompt="$1"
    local default="$2"
    local input
    
    read -p "$prompt [$default]: " input
    echo "${input:-$default}"
}

# Get yes/no input
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

# Show summary function
show_summary() {
    local action="$1"
    local details="$2"
    
    clear
    echo -e "${GREEN}Operation Summary${NC}"
    echo "========================================="
    echo -e "${BLUE}Action:${NC} $action"
    echo -e "${BLUE}Status:${NC} Completed Successfully"
    echo -e "${BLUE}Date:${NC} $(date '+%Y-%m-%d %H:%M:%S')"
    echo
    echo -e "${BLUE}Details:${NC}"
    echo "$details"
    echo "========================================="
    echo -e "${YELLOW}Press Enter to return to the main menu...${NC}"
    read
}

# Install WordPress
install_wordpress() {
    log "Starting WordPress installation"
    
    # Get installation directory
    local wp_dir
    if get_yes_no "Use default WordPress directory ($WP_DEFAULT_DIR)?" "y"; then
        wp_dir="$WP_DEFAULT_DIR"
    else
        wp_dir=$(get_input "Enter WordPress installation directory" "$WP_DEFAULT_DIR")
    fi
    
    # Create directory if it doesn't exist
    mkdir -p "$wp_dir"
    
    # Download WordPress
    echo -e "${BLUE}Downloading WordPress...${NC}"
    curl -L https://wordpress.org/latest.tar.gz -o "$TEMP_DIR/wordpress.tar.gz"
    tar -xzf "$TEMP_DIR/wordpress.tar.gz" -C "$TEMP_DIR"
    
    # Remove existing files if any
    rm -rf "$wp_dir"/*
    
    # Move WordPress files
    mv "$TEMP_DIR/wordpress"/* "$wp_dir/"
    
    # Remove .htaccess
    rm -f "$wp_dir/.htaccess"
    
    # Create uploads directory if it doesn't exist
    mkdir -p "$wp_dir/wp-content/uploads"
    
    # Set permissions
    chown -R nginx:nginx "$wp_dir"
    find "$wp_dir" -type d -exec chmod 755 {} \;
    find "$wp_dir" -type f -exec chmod 644 {} \;
    chmod 775 "$wp_dir/wp-content/uploads"
    
    # Configure SELinux
    if [ "$(getenforce)" != "Disabled" ]; then
        echo -e "${BLUE}Configuring SELinux...${NC}"
        semanage fcontext -a -t httpd_sys_content_t "$wp_dir(/.*)?" || error_exit "Failed to set SELinux context"
        restorecon -Rv "$wp_dir" || error_exit "Failed to restore SELinux context"
        chcon -R -t httpd_sys_rw_content_t "$wp_dir/wp-content/uploads" || error_exit "Failed to set SELinux context for uploads"
    fi
    
    # Create database and user
    local db_name="wp_$(date +%s)"
    local db_user="wp_$(date +%s)"
    local db_pass=$(generate_password)
    
    echo -e "${BLUE}Creating database and user...${NC}"
    mysql -e "CREATE DATABASE $db_name;"
    mysql -e "CREATE USER '$db_user'@'localhost' IDENTIFIED BY '$db_pass';"
    mysql -e "GRANT ALL PRIVILEGES ON $db_name.* TO '$db_user'@'localhost';"
    mysql -e "FLUSH PRIVILEGES;"
    
    # Get WordPress admin credentials
    local wp_admin=$(get_input "Enter WordPress admin username" "admin")
    local wp_email=$(get_input "Enter WordPress admin email" "admin@localhost")
    
    # Ask for custom password or generate one
    local wp_pass
    if get_yes_no "Do you want to set a custom password for the admin user?" "n"; then
        while true; do
            read -s -p "Enter WordPress admin password: " wp_pass
            echo
            read -s -p "Confirm WordPress admin password: " wp_pass_confirm
            echo
            if [ "$wp_pass" = "$wp_pass_confirm" ]; then
                break
            else
                echo -e "${RED}Passwords do not match. Please try again.${NC}"
            fi
        done
    else
        wp_pass=$(generate_password)
    fi
    
    # Create wp-config.php
    echo -e "${BLUE}Creating wp-config.php...${NC}"
    cp "$wp_dir/wp-config-sample.php" "$wp_dir/wp-config.php"
    sed -i "s/database_name_here/$db_name/g" "$wp_dir/wp-config.php"
    sed -i "s/username_here/$db_user/g" "$wp_dir/wp-config.php"
    sed -i "s/password_here/$db_pass/g" "$wp_dir/wp-config.php"
    
    # Generate unique keys and salts
    local unique_keys=$(curl -s https://api.wordpress.org/secret-key/1.1/salt/)
    sed -i "/^define('AUTH_KEY'/d" "$wp_dir/wp-config.php"
    sed -i "/^define('SECURE_AUTH_KEY'/d" "$wp_dir/wp-config.php"
    sed -i "/^define('LOGGED_IN_KEY'/d" "$wp_dir/wp-config.php"
    sed -i "/^define('NONCE_KEY'/d" "$wp_dir/wp-config.php"
    sed -i "/^define('AUTH_SALT'/d" "$wp_dir/wp-config.php"
    sed -i "/^define('SECURE_AUTH_SALT'/d" "$wp_dir/wp-config.php"
    sed -i "/^define('LOGGED_IN_SALT'/d" "$wp_dir/wp-config.php"
    sed -i "/^define('NONCE_SALT'/d" "$wp_dir/wp-config.php"
    echo "$unique_keys" >> "$wp_dir/wp-config.php"
    
    # Install WP-CLI if needed
    install_wp_cli
    
    # Install WordPress core
    echo -e "${BLUE}Installing WordPress core...${NC}"
    wp core install --path="$wp_dir" --url="http://localhost" --title="My WordPress Site" --admin_user="$wp_admin" --admin_password="$wp_pass" --admin_email="$wp_email" --skip-email
    
    # Configure firewall
    if systemctl is-active firewalld &> /dev/null; then
        echo -e "${BLUE}Configuring firewall...${NC}"
        firewall-cmd --permanent --add-service=http || error_exit "Failed to add HTTP to firewall"
        firewall-cmd --permanent --add-service=https || error_exit "Failed to add HTTPS to firewall"
        firewall-cmd --reload || error_exit "Failed to reload firewall"
    fi
    
    # Show summary
    local summary_details="
Installation Directory: $wp_dir
Database Name: $db_name
Database User: $db_user
Database Password: $db_pass

WordPress Admin:
Username: $wp_admin
Password: $wp_pass
Email: $wp_email

You can now log in at http://localhost/wp-admin"
    
    show_summary "WordPress Installation" "$summary_details"
}

# Remove WordPress
remove_wordpress() {
    log "Starting WordPress removal"
    
    # Get installation directory
    local wp_dir
    if get_yes_no "Use default WordPress directory ($WP_DEFAULT_DIR)?" "y"; then
        wp_dir="$WP_DEFAULT_DIR"
    else
        wp_dir=$(get_input "Enter WordPress installation directory" "$WP_DEFAULT_DIR")
    fi
    
    if ! get_yes_no "Are you sure you want to remove WordPress from $wp_dir?" "n"; then
        return
    fi
    
    # Try to get database information from wp-config.php
    local db_name=""
    local db_user=""
    
    if [ -f "$wp_dir/wp-config.php" ]; then
        echo -e "${BLUE}Reading database information from wp-config.php...${NC}"
        db_name=$(grep -o "DB_NAME', '[^']*" "$wp_dir/wp-config.php" | cut -d"'" -f3)
        db_user=$(grep -o "DB_USER', '[^']*" "$wp_dir/wp-config.php" | cut -d"'" -f3)
    fi
    
    # If not found in wp-config.php, ask user
    if [ -z "$db_name" ]; then
        db_name=$(get_input "Enter database name to remove" "")
    fi
    
    if [ -z "$db_user" ]; then
        db_user=$(get_input "Enter database user to remove" "")
    fi
    
    # Remove WordPress files
    echo -e "${BLUE}Removing WordPress files...${NC}"
    rm -rf "$wp_dir"
    
    # Remove database and user if they exist
    if [ -n "$db_name" ]; then
        echo -e "${BLUE}Removing database $db_name...${NC}"
        mysql -e "DROP DATABASE IF EXISTS \`$db_name\`;" || echo -e "${YELLOW}Warning: Could not remove database $db_name${NC}"
    fi
    
    if [ -n "$db_user" ]; then
        echo -e "${BLUE}Removing database user $db_user...${NC}"
        mysql -e "DROP USER IF EXISTS '$db_user'@'localhost';" || echo -e "${YELLOW}Warning: Could not remove user $db_user${NC}"
    fi
    
    # Remove SELinux contexts
    if [ "$(getenforce)" != "Disabled" ]; then
        echo -e "${BLUE}Removing SELinux contexts...${NC}"
        semanage fcontext -d "$wp_dir(/.*)?" || echo -e "${YELLOW}Warning: Could not remove SELinux contexts${NC}"
    fi
    
    # Show summary
    local summary_details="
Removed Directory: $wp_dir
Database Removed: $db_name
Database User Removed: $db_user"
    
    show_summary "WordPress Removal" "$summary_details"
}

# Install WP-CLI
install_wp_cli() {
    if [ ! -f "$WP_CLI_PATH" ]; then
        echo -e "${BLUE}Installing WP-CLI...${NC}"
        curl -O "$WP_CLI_URL" || error_exit "Failed to download WP-CLI"
        chmod +x wp-cli.phar
        mv wp-cli.phar "$WP_CLI_PATH"
        log "WP-CLI installed"
    fi
}

# Install plugins
install_plugins() {
    log "Starting plugin installation"
    
    # Get installation directory
    local wp_dir
    if get_yes_no "Use default WordPress directory ($WP_DEFAULT_DIR)?" "y"; then
        wp_dir="$WP_DEFAULT_DIR"
    else
        wp_dir=$(get_input "Enter WordPress installation directory" "$WP_DEFAULT_DIR")
    fi
    
    # Install WP-CLI if needed
    install_wp_cli
    
    # List of plugins to install
    local plugins=(
        "woocommerce"
        "tinypng-image-compression"
        "cloudflare"
        "wp-super-cache"
    )
    
    for plugin in "${plugins[@]}"; do
        if ! wp plugin is-installed "$plugin" --path="$wp_dir"; then
            echo -e "${BLUE}Installing $plugin...${NC}"
            wp plugin install "$plugin" --path="$wp_dir" || error_exit "Failed to install $plugin"
            wp plugin activate "$plugin" --path="$wp_dir" || error_exit "Failed to activate $plugin"
            
            if [ "$plugin" = "tinypng-image-compression" ]; then
                local api_key=$(get_input "Enter TinyPNG API key" "")
                if [ -n "$api_key" ]; then
                    wp option set tinypng_api_key "$api_key" --path="$wp_dir"
                fi
            fi
        else
            echo -e "${GREEN}$plugin is already installed${NC}"
        fi
    done
    
    # Show summary
    local summary_details="
Plugins Installed:
  - woocommerce
  - tinypng-image-compression
  - cloudflare
  - wp-super-cache

Directory: $wp_dir
Status: All plugins installed and activated"
    
    show_summary "Plugin Installation" "$summary_details"
}

# Fix upload permissions
fix_upload_permissions() {
    log "Starting upload permissions fix"
    
    # Get WordPress installation directory
    local wp_dir
    if get_yes_no "Use default WordPress directory ($WP_DEFAULT_DIR)?" "y"; then
        wp_dir="$WP_DEFAULT_DIR"
    else
        wp_dir=$(get_input "Enter WordPress installation directory" "$WP_DEFAULT_DIR")
    fi
    
    # Check if directory exists
    if [ ! -d "$wp_dir" ]; then
        error_exit "WordPress directory not found: $wp_dir"
    fi
    
    echo -e "${BLUE}Fixing upload permissions...${NC}"
    
    # Create and set permissions for wp-content
    echo -e "${BLUE}Setting wp-content permissions...${NC}"
    chown -R nginx:nginx "$wp_dir/wp-content"
    chmod -R 775 "$wp_dir/wp-content"
    
    # Create uploads directory with proper structure
    echo -e "${BLUE}Creating uploads directory structure...${NC}"
    mkdir -p "$wp_dir/wp-content/uploads"
    mkdir -p "$wp_dir/wp-content/uploads/$(date +%Y)"
    mkdir -p "$wp_dir/wp-content/uploads/$(date +%Y)/$(date +%m)"
    
    # Set ownership and permissions for uploads
    echo -e "${BLUE}Setting uploads permissions...${NC}"
    chown -R nginx:nginx "$wp_dir/wp-content/uploads"
    chmod -R 775 "$wp_dir/wp-content/uploads"
    
    # Configure SELinux if enabled
    if [ "$(getenforce)" != "Disabled" ]; then
        echo -e "${BLUE}Configuring SELinux...${NC}"
        # Set context for wp-content
        semanage fcontext -a -t httpd_sys_rw_content_t "$wp_dir/wp-content(/.*)?" || echo -e "${YELLOW}Warning: Could not set SELinux context for wp-content${NC}"
        restorecon -Rv "$wp_dir/wp-content" || echo -e "${YELLOW}Warning: Could not restore SELinux context for wp-content${NC}"
        
        # Set context for uploads
        semanage fcontext -a -t httpd_sys_rw_content_t "$wp_dir/wp-content/uploads(/.*)?" || echo -e "${YELLOW}Warning: Could not set SELinux context for uploads${NC}"
        restorecon -Rv "$wp_dir/wp-content/uploads" || echo -e "${YELLOW}Warning: Could not restore SELinux context for uploads${NC}"
    fi
    
    # Create .htaccess in uploads directory
    echo -e "${BLUE}Creating .htaccess file...${NC}"
    cat > "$wp_dir/wp-content/uploads/.htaccess" << 'EOF'
Options -Indexes
<FilesMatch "\.(php|php3|php4|php5|phtml|pl|py|jsp|asp|htm|html|shtml|sh|cgi)$">
    Order Deny,Allow
    Deny from all
</FilesMatch>
EOF
    chown nginx:nginx "$wp_dir/wp-content/uploads/.htaccess"
    chmod 644 "$wp_dir/wp-content/uploads/.htaccess"
    
    # Set PHP-FPM user and group
    echo -e "${BLUE}Configuring PHP-FPM...${NC}"
    if [ -f "/etc/php-fpm.d/www.conf" ]; then
        sed -i 's/^user = apache/user = nginx/' /etc/php-fpm.d/www.conf
        sed -i 's/^group = apache/group = nginx/' /etc/php-fpm.d/www.conf
        systemctl restart php-fpm
    fi
    
    # Restart Nginx
    echo -e "${BLUE}Restarting Nginx...${NC}"
    systemctl restart nginx
    
    # Show summary
    local summary_details="
Directory: $wp_dir/wp-content/uploads
Owner: nginx:nginx
Permissions: 775
SELinux Context: httpd_sys_rw_content_t
PHP-FPM User: nginx
PHP-FPM Group: nginx
Services Restarted: php-fpm, nginx"
    
    show_summary "Fix Upload Permissions" "$summary_details"
}

# Main menu
while true; do
    clear
    echo -e "${BLUE}WordPress Installation Script${NC}"
    echo "1. Install & Configure WordPress"
    echo "2. Remove WordPress"
    echo "3. Install Recommended Plugins"
    echo "4. Fix Upload Permissions"
    echo "5. Exit"
    read -p "Enter your choice (1-5): " choice

    case $choice in
        1) install_wordpress ;;
        2) remove_wordpress ;;
        3) install_plugins ;;
        4) fix_upload_permissions ;;
        5) echo -e "${GREEN}Exiting...${NC}"; exit 0 ;;
        *) echo -e "${RED}Invalid choice. Please try again.${NC}"; sleep 2 ;;
    esac
done

# Main execution
check_root
check_services
