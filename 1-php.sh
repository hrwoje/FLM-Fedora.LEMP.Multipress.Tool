#!/bin/bash

# PHP Manager Script for Fedora
# Version: 1.0
# Author: Cursor AI

# Configuration
LOG_FILE="/var/log/php-manager.log"
PHP_DEFAULT_VALUES=(
    "memory_limit = 256M"
    "post_max_size = 64M"
    "max_execution_time = 120"
    "upload_max_filesize = 64M"
    "max_input_time = 120"
    "max_input_vars = 1000"
)

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

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

# Install Remi repository
install_remi_repo() {
    log "Installing Remi repository"
    if ! dnf list installed remi-release >/dev/null 2>&1; then
        dnf install -y https://rpms.remirepo.net/fedora/remi-release-$(rpm -E %fedora).rpm || error_exit "Failed to install Remi repository"
    else
        log "Remi repository is already installed"
    fi
}

# Install PHP with WordPress extensions
install_php_wordpress() {
    log "Installing PHP with WordPress extensions"
    local packages=(
        php php-fpm php-mysqlnd php-gd php-xml php-mbstring php-curl
        php-opcache php-intl php-bcmath php-json php-zip php-soap php-cli php-common
    )
    
    # Check which packages need to be installed
    local to_install=()
    for pkg in "${packages[@]}"; do
        if ! rpm -q "$pkg" >/dev/null 2>&1; then
            to_install+=("$pkg")
        fi
    done
    
    if [ ${#to_install[@]} -gt 0 ]; then
        dnf install -y "${to_install[@]}" || error_exit "Failed to install PHP packages"
    else
        log "All required PHP packages are already installed"
    fi
    
    # Configure PHP
    configure_php
    enable_php_fpm
}

# Uninstall PHP completely
uninstall_php() {
    log "Uninstalling PHP and all extensions"
    if rpm -qa | grep -q '^php'; then
        dnf remove -y php* || error_exit "Failed to uninstall PHP packages"
        systemctl stop php-fpm 2>/dev/null
        systemctl disable php-fpm 2>/dev/null
    else
        log "No PHP packages found to uninstall"
    fi
}

# Install specific PHP version
install_specific_php_version() {
    echo "Available PHP versions:"
    dnf module list php | grep -E '^php:remi'
    read -p "Enter PHP version (e.g., 8.2): " php_version
    
    log "Installing PHP version $php_version"
    dnf module enable -y php:remi-$php_version || error_exit "Failed to enable PHP module"
    dnf install -y php php-fpm || error_exit "Failed to install PHP $php_version"
    
    configure_php
    enable_php_fpm
}

# Switch PHP version
switch_php_version() {
    echo "Available PHP versions:"
    dnf module list php | grep -E '^php:remi'
    read -p "Enter PHP version to switch to: " php_version
    
    log "Switching to PHP version $php_version"
    dnf module enable -y php:remi-$php_version || error_exit "Failed to switch PHP version"
    dnf install -y php php-fpm || error_exit "Failed to install PHP $php_version"
    
    configure_php
    restart_services
}

# Configure PHP settings
configure_php() {
    log "Configuring PHP settings"
    local php_ini=$(php --ini | grep "Loaded Configuration File" | awk '{print $4}')
    
    if [ ! -f "$php_ini" ]; then
        error_exit "PHP configuration file not found: $php_ini"
    fi
    
    for setting in "${PHP_DEFAULT_VALUES[@]}"; do
        key=$(echo "$setting" | awk '{print $1}')
        value=$(echo "$setting" | awk '{print $3}')
        
        if grep -q "^$key" "$php_ini"; then
            sed -i "s/^$key.*/$key = $value/" "$php_ini"
        else
            echo "$key = $value" >> "$php_ini"
        fi
    done
    
    # Apply SELinux context only if the directory exists
    if [ -d "/etc/php" ]; then
        restorecon -Rv /etc/php* || log "Warning: Failed to restore SELinux context"
    fi
}

# Enable and start PHP-FPM
enable_php_fpm() {
    log "Enabling and starting PHP-FPM"
    if systemctl is-enabled php-fpm >/dev/null 2>&1; then
        log "PHP-FPM is already enabled"
    else
        systemctl enable php-fpm || error_exit "Failed to enable PHP-FPM"
    fi
    
    if systemctl is-active php-fpm >/dev/null 2>&1; then
        log "PHP-FPM is already running"
    else
        systemctl start php-fpm || error_exit "Failed to start PHP-FPM"
    fi
}

# Restart services
restart_services() {
    log "Restarting services"
    if systemctl is-active php-fpm >/dev/null 2>&1; then
        systemctl restart php-fpm || error_exit "Failed to restart PHP-FPM"
    fi
    
    # Detect and restart web server
    if systemctl is-active --quiet nginx; then
        systemctl restart nginx || error_exit "Failed to restart Nginx"
    elif systemctl is-active --quiet httpd; then
        systemctl restart httpd || error_exit "Failed to restart Apache"
    fi
}

# Main menu
show_menu() {
    while true; do
        clear
        echo -e "${GREEN}PHP Manager for Fedora${NC}"
        echo "1. Install PHP with WordPress extensions"
        echo "2. Uninstall PHP completely"
        echo "3. Install specific PHP version"
        echo "4. Switch PHP version"
        echo "5. Configure PHP settings"
        echo "6. Exit"
        
        read -p "Enter your choice (1-6): " choice
        
        case $choice in
            1)
                install_php_wordpress
                ;;
            2)
                uninstall_php
                ;;
            3)
                install_specific_php_version
                ;;
            4)
                switch_php_version
                ;;
            5)
                configure_php
                restart_services
                ;;
            6)
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

# Main execution
check_root
install_remi_repo
show_menu
