#!/bin/bash

# NGINX Manager Script for Fedora
# Version: 1.0
# Author: Cursor AI

# Configuration
LOG_FILE="/var/log/nginx-manager.log"
NGINX_CONF="/etc/nginx/nginx.conf"
NGINX_SERVER_CONF="/etc/nginx/conf.d/localhost.conf"
DEFAULT_WEB_ROOT="/var/www/html"
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

# Check if PHP-FPM is running
check_php_fpm() {
    if ! systemctl is-active php-fpm &> /dev/null; then
        error_exit "PHP-FPM is not running. Please start it first."
    fi
    log "PHP-FPM check passed"
}

# Check if MySQL is running
check_mysql() {
    if ! systemctl is-active mariadb &> /dev/null; then
        error_exit "MySQL is not running. Please start it first."
    fi
    log "MySQL check passed"
}

# Create test page
create_test_page() {
    log "Creating test page"
    echo -e "${BLUE}Creating test page...${NC}"
    
    # Create test page
    cat > "$DEFAULT_WEB_ROOT/test.html" << 'EOF'
<!DOCTYPE html>
<html>
<head>
    <title>NGINX Test Page</title>
    <style>
        body {
            font-family: Arial, sans-serif;
            margin: 0;
            padding: 0;
            display: flex;
            justify-content: center;
            align-items: center;
            height: 100vh;
            background-color: #f0f0f0;
        }
        .container {
            text-align: center;
            padding: 2rem;
            background-color: white;
            border-radius: 10px;
            box-shadow: 0 0 10px rgba(0,0,0,0.1);
        }
        h1 {
            color: #333;
        }
        p {
            color: #666;
        }
    </style>
</head>
<body>
    <div class="container">
        <h1>NGINX Test Page</h1>
        <p>If you can see this page, NGINX is working correctly!</p>
    </div>
</body>
</html>
EOF
    
    # Set correct permissions
    chown nginx:nginx "$DEFAULT_WEB_ROOT/test.html"
    chmod 644 "$DEFAULT_WEB_ROOT/test.html"
    
    echo -e "${GREEN}Test page created successfully${NC}"
    log "Test page created"
}

# Install and configure NGINX
install_nginx() {
    log "Starting NGINX installation"
    
    # Install NGINX if not already installed
    if ! rpm -q nginx &> /dev/null; then
        echo -e "${BLUE}Installing NGINX...${NC}"
        dnf install -y nginx || error_exit "Failed to install NGINX"
    fi
    
    # Configure firewall
    if systemctl is-active firewalld &> /dev/null; then
        echo -e "${BLUE}Configuring firewall...${NC}"
        firewall-cmd --permanent --add-service=http || error_exit "Failed to add HTTP to firewall"
        firewall-cmd --permanent --add-service=https || error_exit "Failed to add HTTPS to firewall"
        firewall-cmd --reload || error_exit "Failed to reload firewall"
    fi
    
    # Configure SELinux
    if [ "$(getenforce)" != "Disabled" ]; then
        echo -e "${BLUE}Configuring SELinux...${NC}"
        setsebool -P httpd_can_network_connect 1 || error_exit "Failed to set SELinux boolean"
        semanage port -a -t http_port_t -p tcp 80 || error_exit "Failed to add SELinux port label"
        semanage port -a -t http_port_t -p tcp 443 || error_exit "Failed to add SELinux port label"
    fi
    
    # Create NGINX configuration
    echo -e "${BLUE}Creating NGINX configuration...${NC}"
    cat > "$NGINX_CONF" << 'EOF'
user nginx;
worker_processes auto;
error_log /var/log/nginx/error.log;
pid /run/nginx.pid;

events {
    worker_connections 1024;
}

http {
    include /etc/nginx/mime.types;
    default_type application/octet-stream;
    
    log_format main '$remote_addr - $remote_user [$time_local] "$request" '
                    '$status $body_bytes_sent "$http_referer" '
                    '"$http_user_agent" "$http_x_forwarded_for"';
    
    access_log /var/log/nginx/access.log main;
    
    sendfile on;
    tcp_nopush on;
    tcp_nodelay on;
    keepalive_timeout 65;
    types_hash_max_size 2048;
    
    gzip on;
    gzip_disable "msie6";
    gzip_vary on;
    gzip_proxied any;
    gzip_comp_level 6;
    gzip_types text/plain text/css application/json application/javascript text/xml application/xml application/xml+rss text/javascript;
    
    include /etc/nginx/conf.d/*.conf;
}
EOF
    
    # Create server configuration
    echo -e "${BLUE}Creating server configuration...${NC}"
    cat > "$NGINX_SERVER_CONF" << 'EOF'
server {
    listen 127.0.0.1:80;
    server_name localhost;
    root /var/www/html;
    index index.php index.html index.htm;
    
    add_header X-Frame-Options SAMEORIGIN;
    add_header X-Content-Type-Options nosniff;
    add_header X-XSS-Protection "1; mode=block";
    add_header Referrer-Policy "strict-origin-when-cross-origin";
    
    location / {
        try_files $uri $uri/ /index.php?$args;
    }
    
    location ~ \.php$ {
        fastcgi_pass unix:/run/php-fpm/www.sock;
        fastcgi_index index.php;
        fastcgi_param SCRIPT_FILENAME $document_root$fastcgi_script_name;
        include fastcgi_params;
    }
    
    location ~* \.(js|css|png|jpg|jpeg|gif|ico)$ {
        expires max;
        log_not_found off;
    }
}
EOF
    
    # Create test page
    create_test_page
    
    # Validate configuration
    echo -e "${BLUE}Validating configuration...${NC}"
    nginx -t || error_exit "NGINX configuration test failed"
    
    # Enable and start NGINX
    echo -e "${BLUE}Starting NGINX service...${NC}"
    systemctl enable --now nginx || error_exit "Failed to start NGINX"
    
    echo -e "${GREEN}NGINX installation completed successfully${NC}"
    log "NGINX installation completed"
}

# Remove NGINX
remove_nginx() {
    log "Starting NGINX removal"
    
    if ! rpm -q nginx &> /dev/null; then
        echo -e "${YELLOW}NGINX is not installed${NC}"
        return
    fi
    
    # Backup configuration
    echo -e "${BLUE}Backing up configuration...${NC}"
    tar -czf "$TEMP_DIR/nginx_backup_$(date +%Y%m%d).tar.gz" /etc/nginx || error_exit "Failed to backup NGINX configuration"
    
    # Stop and disable NGINX
    echo -e "${BLUE}Stopping NGINX service...${NC}"
    systemctl stop nginx
    systemctl disable nginx
    
    # Remove firewall rules
    if systemctl is-active firewalld &> /dev/null; then
        echo -e "${BLUE}Removing firewall rules...${NC}"
        firewall-cmd --permanent --remove-service=http
        firewall-cmd --permanent --remove-service=https
        firewall-cmd --reload
    fi
    
    # Remove package and configuration
    echo -e "${BLUE}Removing NGINX packages...${NC}"
    dnf remove -y nginx || error_exit "Failed to remove NGINX"
    rm -rf /etc/nginx
    
    echo -e "${GREEN}NGINX removal completed successfully${NC}"
    log "NGINX removal completed"
}

# Health check
health_check() {
    log "Starting health check"
    echo -e "${BLUE}Performing NGINX health check...${NC}"
    
    # Check if NGINX is installed
    if ! rpm -q nginx &> /dev/null; then
        echo -e "${CROSS} NGINX is not installed${NC}"
        return
    fi
    
    # Check service status
    if systemctl is-active nginx &> /dev/null; then
        echo -e "${CHECK} NGINX service is running${NC}"
    else
        echo -e "${CROSS} NGINX service is not running${NC}"
    fi
    
    # Check if NGINX is enabled
    if systemctl is-enabled nginx &> /dev/null; then
        echo -e "${CHECK} NGINX is enabled to start on boot${NC}"
    else
        echo -e "${CROSS} NGINX is not enabled to start on boot${NC}"
    fi
    
    # Check configuration
    if nginx -t &> /dev/null; then
        echo -e "${CHECK} NGINX configuration is valid${NC}"
    else
        echo -e "${CROSS} NGINX configuration is invalid${NC}"
    fi
    
    # Check if listening on localhost only
    if netstat -tuln | grep -q "127.0.0.1:80"; then
        echo -e "${CHECK} NGINX is listening on localhost only${NC}"
    else
        echo -e "${CROSS} NGINX is not listening on localhost only${NC}"
    fi
    
    # Check PHP-FPM
    if systemctl is-active php-fpm &> /dev/null; then
        echo -e "${CHECK} PHP-FPM is running${NC}"
    else
        echo -e "${CROSS} PHP-FPM is not running${NC}"
    fi
    
    # Check PHP socket
    if [ -S "/run/php-fpm/www.sock" ]; then
        echo -e "${CHECK} PHP-FPM socket is available${NC}"
    else
        echo -e "${CROSS} PHP-FPM socket is not available${NC}"
    fi
    
    # Check firewall ports
    if systemctl is-active firewalld &> /dev/null; then
        if firewall-cmd --list-ports | grep -q "80/tcp"; then
            echo -e "${CHECK} Port 80 is open in firewall${NC}"
        else
            echo -e "${CROSS} Port 80 is not open in firewall${NC}"
        fi
    fi
    
    # Check error log
    if [ -f "/var/log/nginx/error.log" ]; then
        echo -e "${BLUE}Last 10 lines of error log:${NC}"
        tail -n 10 /var/log/nginx/error.log
    fi
    
    # Check SELinux denials
    if [ "$(getenforce)" != "Disabled" ]; then
        echo -e "${BLUE}SELinux denials:${NC}"
        ausearch -m AVC -ts recent | grep nginx || echo "No recent SELinux denials found"
    fi
    
    log "Health check completed"
}

# Show status summary
show_status() {
    log "Showing status summary"
    echo -e "${BLUE}NGINX Status Summary:${NC}"
    
    # Service status
    systemctl status nginx --no-pager
    
    # Configuration test
    echo -e "\n${BLUE}Configuration Test:${NC}"
    nginx -t
    
    # Listening ports
    echo -e "\n${BLUE}Listening Ports:${NC}"
    netstat -tuln | grep nginx
    
    # PHP-FPM status
    echo -e "\n${BLUE}PHP-FPM Status:${NC}"
    systemctl status php-fpm --no-pager
    
    log "Status summary completed"
}

# Main menu
show_menu() {
    while true; do
        clear
        echo -e "${GREEN}NGINX Manager for Fedora${NC}"
        echo "1. Install & Configure NGINX"
        echo "2. Remove NGINX"
        echo "3. Run Health Check"
        echo "4. Show Status Summary"
        echo "5. Exit"
        
        read -p "Enter your choice (1-5): " choice
        
        case $choice in
            1)
                install_nginx
                ;;
            2)
                remove_nginx
                ;;
            3)
                health_check
                ;;
            4)
                show_status
                ;;
            5)
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
check_php_fpm
check_mysql
show_menu
