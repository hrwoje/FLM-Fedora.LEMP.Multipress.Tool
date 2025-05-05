#!/bin/bash

# MySQL Manager Script for Fedora
# Version: 1.0
# Author: Cursor AI

# Configuration
LOG_FILE="/tmp/mysql_install_report.log"
MYSQL_SERVICE="mariadb"
MYSQL_PORT=3306

# Colors and symbols
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'
CHECK='✅'
CROSS='❌'
RED_CIRCLE='🔴'
GREEN_CIRCLE='🟢'

# Logging function
log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a "$LOG_FILE" >/dev/null
}

# Error handling
error_exit() {
    echo -e "${RED}Error: $1${NC}" >&2
    log "ERROR: $1"
    exit 1
}

# Check if PHP is installed
check_php() {
    if ! command -v php &> /dev/null; then
        error_exit "PHP is not installed. Please install PHP first."
    fi
    log "PHP check passed"
}

# Check if running with sudo
check_sudo() {
    if [ "$EUID" -ne 0 ]; then
        echo -e "${YELLOW}This operation requires root privileges.${NC}"
        if ! sudo -n true 2>/dev/null; then
            sudo "$0" "$@"
            exit $?
        fi
    fi
}

# Install MySQL
install_mysql() {
    check_sudo
    log "Starting MySQL installation"
    
    if rpm -q mariadb-server &> /dev/null; then
        echo -e "${YELLOW}MySQL is already installed${NC}"
        return
    fi
    
    echo -e "${BLUE}Installing MySQL...${NC}"
    sudo dnf install -y mariadb-server || error_exit "Failed to install MySQL"
    
    echo -e "${BLUE}Starting MySQL service...${NC}"
    sudo systemctl enable --now $MYSQL_SERVICE || error_exit "Failed to start MySQL service"
    
    echo -e "${GREEN}MySQL installation completed successfully${NC}"
    log "MySQL installation completed"
}

# Remove MySQL completely
remove_mysql() {
    check_sudo
    log "Starting MySQL removal"
    
    if ! rpm -q mariadb-server &> /dev/null; then
        echo -e "${YELLOW}MySQL is not installed${NC}"
        return
    fi
    
    echo -e "${BLUE}Stopping MySQL service...${NC}"
    sudo systemctl stop $MYSQL_SERVICE
    
    echo -e "${BLUE}Removing MySQL packages...${NC}"
    sudo dnf remove -y mariadb-server mariadb || error_exit "Failed to remove MySQL packages"
    
    echo -e "${BLUE}Removing MySQL data and configuration...${NC}"
    sudo rm -rf /var/lib/mysql
    sudo rm -rf /etc/my.cnf*
    
    echo -e "${GREEN}MySQL removal completed successfully${NC}"
    log "MySQL removal completed"
}

# Health check
health_check() {
    log "Starting health check"
    echo -e "${BLUE}Performing MySQL health check...${NC}"
    
    # Check if MySQL is installed
    if ! rpm -q mariadb-server &> /dev/null; then
        echo -e "${RED_CIRCLE} MySQL is not installed${NC}"
        return
    fi
    
    # Check service status
    if systemctl is-active $MYSQL_SERVICE &> /dev/null; then
        echo -e "${GREEN_CIRCLE} MySQL service is running${NC}"
    else
        echo -e "${RED_CIRCLE} MySQL service is not running${NC}"
    fi
    
    # Check port
    if netstat -tuln | grep -q ":$MYSQL_PORT "; then
        echo -e "${GREEN_CIRCLE} Port $MYSQL_PORT is open${NC}"
    else
        echo -e "${RED_CIRCLE} Port $MYSQL_PORT is not open${NC}"
    fi
    
    # Check socket
    if [ -S /var/lib/mysql/mysql.sock ]; then
        echo -e "${GREEN_CIRCLE} MySQL socket is available${NC}"
    else
        echo -e "${RED_CIRCLE} MySQL socket is not available${NC}"
    fi
    
    log "Health check completed"
}

# View installation report
view_report() {
    if [ -f "$LOG_FILE" ]; then
        echo -e "${BLUE}Installation Report:${NC}"
        cat "$LOG_FILE"
    else
        echo -e "${YELLOW}No installation report found${NC}"
    fi
}

# Create WordPress database
create_wordpress_db() {
    check_sudo
    log "Starting WordPress database creation"
    
    if ! systemctl is-active $MYSQL_SERVICE &> /dev/null; then
        error_exit "MySQL service is not running"
    fi
    
    read -p "Enter database name: " db_name
    read -p "Enter database user: " db_user
    read -s -p "Enter database password: " db_password
    echo
    
    # Create database and user
    sudo mysql -e "CREATE DATABASE IF NOT EXISTS $db_name;"
    sudo mysql -e "CREATE USER IF NOT EXISTS '$db_user'@'localhost' IDENTIFIED BY '$db_password';"
    sudo mysql -e "GRANT ALL PRIVILEGES ON $db_name.* TO '$db_user'@'localhost';"
    sudo mysql -e "FLUSH PRIVILEGES;"
    
    echo -e "${GREEN}WordPress database created successfully${NC}"
    log "WordPress database created: $db_name"
}

# Main menu
show_menu() {
    while true; do
        clear
        echo -e "${GREEN}MySQL Manager for Fedora${NC}"
        echo "1. Install MySQL"
        echo "2. Remove MySQL completely"
        echo "3. Health Check"
        echo "4. View Installation Report"
        echo "5. Create WordPress Database"
        echo "6. Exit"
        
        read -p "Enter your choice (1-6): " choice
        
        case $choice in
            1)
                install_mysql
                ;;
            2)
                remove_mysql
                ;;
            3)
                health_check
                ;;
            4)
                view_report
                ;;
            5)
                create_wordpress_db
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
check_php
show_menu
