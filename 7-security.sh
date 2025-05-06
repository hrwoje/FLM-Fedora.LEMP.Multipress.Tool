#!/bin/bash

# Fedora Security Suite (Optimized Edition)
# Version: 1.2
# Author: Cursor AI (Improved)

# Prevent background execution
if [[ $(ps -o stat= -p $$) =~ Z|T ]]; then
    echo "This script cannot be run in the background"
    exit 1
fi

# Color definitions
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'  # No Color

# Configuration
set -euo pipefail
IFS=$'\n\t'
trap 'error_exit "Unexpected error on line $LINENO"' ERR

# Prevent concurrent execution
LOCKFILE="/var/run/fedora-secure.lock"
exec 200>"$LOCKFILE"
flock -n 200 || {
  echo "${RED}Another instance of the script is already running.${NC}" >&2
  exit 1
}

# --- [NEW: Reusable Constants] ---
LOG_DIR="/var/log/fedora-secure"
CONF_DIR="/etc/fedora-secure"
DATE=$(date +%Y%m%d_%H%M%S)
LMD_URL="https://github.com/rfxn/linux-malware-detect/archive/refs/heads/master.tar.gz"
LMD_DIR="/usr/local/maldetect"
LMD_BIN="/usr/local/sbin/maldet"
LMD_CONF="$LMD_DIR/conf.maldet"
CHROME_CLEANUP_SCRIPT="/usr/local/bin/chrome-cleanup.sh"
SPAMASSASSIN_DIR="/etc/mail/spamassassin"
ADBLOCK_DIR="/etc/adblock"
CHROME_DIR="/etc/opt/chrome/policies"
GEARY_DIR="/var/lib/geary"

# --- [NEW: Colors and Symbols] ---
CHECK='✅'
CROSS='❌'
WARNING='⚠️'

# --- [NEW: Helper Functions] ---

validate_aide_installation() {
    echo -e "${BLUE}Validating AIDE installation...${NC}"
    local status=true

    if systemctl is-enabled --quiet aide-check.timer && systemctl is-active --quiet aide-check.timer; then
        echo -e "${CHECK} AIDE timer is active and enabled"
    else
        echo -e "${CROSS} AIDE timer is not running or not enabled"
        status=false
    fi

    if [[ -f /var/lib/aide/aide.db.gz ]]; then
        echo -e "${CHECK} AIDE database found"
    else
        echo -e "${CROSS} AIDE database missing"
        status=false
    fi

    if [[ "$status" == true ]]; then
        echo -e "${GREEN}AIDE installation validated successfully${NC}"
    else
        echo -e "${RED}AIDE validation failed. Check configuration.${NC}"
    fi
}

log() {
    mkdir -p "$LOG_DIR"
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" | sudo tee -a "$LOG_DIR/security.log" >/dev/null
}

error_exit() {
    log "ERROR: $1"
    echo -e "${RED}Error: $1${NC}" >&2
    exit 1
}

check_root() {
    echo "DEBUG: Checking root privileges..."
    [[ "$EUID" -ne 0 ]] && error_exit "This script must be run as root"
    echo "DEBUG: Root check passed"
}

start_and_enable() {
    local service=$1
    echo -e "${BLUE}Starting and enabling $service...${NC}"
    systemctl enable "$service" || echo -e "${RED}Failed to enable $service${NC}"
    systemctl start "$service" || echo -e "${RED}Failed to start $service${NC}"
}

is_installed() {
    command -v "$1" &>/dev/null
}

safe_remove() {
    [[ -e "$1" ]] && rm -rf "$1"
}

# --- [Cleanup: Old Installations for All Services] ---
cleanup_old_maldet_installation() {
    echo -e "${YELLOW}Cleaning up previous Maldet installation (if any)...${NC}"
    systemctl stop maldet-update.timer 2>/dev/null || true
    systemctl disable maldet-update.timer 2>/dev/null || true
    rm -f /etc/systemd/system/maldet-update.service
    rm -f /etc/systemd/system/maldet-update.timer
    rm -f "$LMD_BIN"
    rm -rf "$LMD_DIR"
    systemctl daemon-reload
}

cleanup_old_weekly_scan() {
    echo -e "${YELLOW}Cleaning up previous Weekly Scan configuration...${NC}"
    systemctl stop weekly-scan.timer 2>/dev/null || true
    systemctl disable weekly-scan.timer 2>/dev/null || true
    rm -f /etc/systemd/system/weekly-scan.service
    rm -f /etc/systemd/system/weekly-scan.timer
    rm -f /usr/local/bin/weekly-scan.sh
    systemctl daemon-reload
}

cleanup_old_services() {
    echo -e "${YELLOW}Checking and cleaning old system service state...${NC}"

    # Auditd reset (does not remove)
    echo -e "${YELLOW}Ensuring auditd is in clean state...${NC}"
    systemctl stop auditd 2>/dev/null || true
    systemctl disable auditd 2>/dev/null || true
    systemctl reset-failed auditd 2>/dev/null || true

    # Reconfigure auditd rules
    echo -e "${YELLOW}Reapplying auditd rule configuration...${NC}"
    mkdir -p /etc/audit/rules.d
    cat > /etc/audit/rules.d/fedora-secure.rules << 'EOF'
-w /etc/passwd -p wa -k passwd_changes
-w /etc/shadow -p wa -k shadow_changes
-w /etc/group -p wa -k group_changes
-w /etc/gshadow -p wa -k gshadow_changes
-w /etc/sudoers -p wa -k sudoers_changes
-w /var/log/ -p wa -k log_changes
EOF
    augenrules --load || echo -e "${YELLOW}Failed to reload audit rules${NC}"
    echo -e "${YELLOW}Checking and cleaning old system service state...${NC}"

    # Auditd reset (does not remove)
    echo -e "${YELLOW}Ensuring auditd is in clean state...${NC}"
    systemctl stop auditd 2>/dev/null || true
    systemctl disable auditd 2>/dev/null || true
    systemctl reset-failed auditd 2>/dev/null || true
    cleanup_old_maldet_installation
    cleanup_old_weekly_scan
    echo -e "${YELLOW}Disabling any lingering Fail2Ban and Firewalld state...${NC}"
    for svc in fail2ban firewalld; do
        systemctl stop "$svc" 2>/dev/null || true
        systemctl disable "$svc" 2>/dev/null || true
    done
}

# --- [Improved: Idempotent LMD Install] ---
install_or_update_maldet() {
    cleanup_old_maldet_installation
    log "Installing or Updating Maldet"
    [[ -f "$LMD_BIN" ]] && echo -e "${YELLOW}Maldet already installed, updating...${NC}" || echo -e "${BLUE}Installing Maldet...${NC}"

    # Create necessary directories
    mkdir -p /usr/local/sbin
    mkdir -p /usr/local/maldetect

    temp_dir=$(mktemp -d)
    curl -L "$LMD_URL" -o "$temp_dir/maldet.tar.gz"
    tar -xzf "$temp_dir/maldet.tar.gz" -C "$temp_dir"
    pushd "$temp_dir"/linux-malware-detect-* > /dev/null
    
    # Install with explicit paths
    ./install.sh --install /usr/local/maldetect || {
        echo -e "${RED}Failed to install Maldet, trying alternative method...${NC}"
        cp -f maldet /usr/local/sbin/maldet
        cp -f maldet /usr/local/sbin/lmd
        chmod +x /usr/local/sbin/maldet
        chmod +x /usr/local/sbin/lmd
    }
    popd > /dev/null

    # Set conservative permissions
    chmod 0750 "$LMD_DIR"
    chown root:root "$LMD_DIR"
    sed -i 's/^quarantine_hits=.*/quarantine_hits=1/' "$LMD_CONF"
    sed -i 's/^quarantine_clean=.*/quarantine_clean=1/' "$LMD_CONF"
    sed -i 's/^email_alert=.*/email_alert=0/' "$LMD_CONF"

    # Systemd timer (idempotent)
    cat > /etc/systemd/system/maldet-update.service << 'EOF'
[Unit]
Description=Maldet Signature Update
After=network.target

[Service]
Type=oneshot
ExecStart=/usr/local/sbin/maldet --update-sigs
User=root
Group=root
EOF

    cat > /etc/systemd/system/maldet-update.timer << 'EOF'
[Unit]
Description=Run Maldet Updates Daily

[Timer]
OnCalendar=daily
Persistent=true

[Install]
WantedBy=timers.target
EOF

    systemctl daemon-reload
    start_and_enable maldet-update.timer
    rm -rf "$temp_dir"

    # Force update signatures
    /usr/local/sbin/maldet --update-sigs || true

    validate_maldet_installation
}

# --- [NEW: Validation Function] ---
validate_maldet_installation() {
    echo -e "${BLUE}Validating Maldet installation...${NC}"

    local valid=true

    if [[ -x "$LMD_BIN" ]]; then
        echo -e "${CHECK} Maldet binary found at $LMD_BIN"
    else
        echo -e "${CROSS} Maldet binary missing"
        valid=false
    fi

    if systemctl is-enabled --quiet maldet-update.timer && systemctl is-active --quiet maldet-update.timer; then
        echo -e "${CHECK} Maldet update timer is active and enabled"
    else
        echo -e "${CROSS} Maldet update timer is not properly set"
        valid=false
    fi

    local sig_file="$LMD_DIR/sigs/rfxn.ndb"
    if [[ -f "$sig_file" ]]; then
        sig_date=$(stat -c '%y' "$sig_file")
        echo -e "${CHECK} Signature file exists: $(basename "$sig_file")"
        echo -e "${CHECK} Signature last updated: $sig_date"
    else
        echo -e "${CROSS} Signature file missing"
        valid=false
    fi

    if [[ "$valid" == true ]]; then
        echo -e "${GREEN}Maldet installation validated successfully${NC}"
    else
        echo -e "${RED}Maldet installation has issues. Please check manually.${NC}"
    fi
}

# --- [Improved: SpamAssassin Permissions] ---
configure_spamassassin() {
    log "Configuring SpamAssassin"
    mkdir -p /etc/mail/spamassassin
    
    # Kill any existing spamd processes and clean up
    pkill -9 -f spamd || true
    rm -f /var/run/spamd.pid
    sleep 2
    
    # Install SpamAssassin if not present
    if ! command -v spamassassin &>/dev/null; then
        dnf install -y spamassassin
    fi
    
    # Create basic configuration
    cat > /etc/mail/spamassassin/local.cf << 'EOF'
# Basic SpamAssassin configuration
required_score 5.0
report_safe 1
use_bayes 1
bayes_auto_learn 1
EOF
    
    chmod 0640 /etc/mail/spamassassin/local.cf
    
    # Create systemd service for SpamAssassin with increased timeout
    cat > /etc/systemd/system/spamassassin.service << 'EOF'
[Unit]
Description=SpamAssassin Daemon
After=network.target

[Service]
Type=forking
ExecStart=/usr/bin/spamd --create-prefs --max-children 5 --helper-home-dir
ExecStop=/usr/bin/spamassassin --stop
Restart=on-failure
TimeoutStartSec=300
TimeoutStopSec=300

[Install]
WantedBy=multi-user.target
EOF

    # Update rules with retry
    for i in {1..3}; do
        if sa-update; then
            echo -e "${GREEN}SpamAssassin rules updated successfully${NC}"
            break
        fi
        echo -e "${YELLOW}Retry $i/3: Updating SpamAssassin rules...${NC}"
        sleep 2
    done
    
    # Enable and start service with timeout
    systemctl daemon-reload
    systemctl enable spamassassin
    
    # Try to start the service with a timeout
    if ! timeout 30s systemctl start spamassassin; then
        echo -e "${YELLOW}Service start timed out, trying alternative method...${NC}"
        # Start spamd directly
        /usr/bin/spamd --create-prefs --max-children 5 --helper-home-dir &
        sleep 5
    fi
    
    # Verify if spamd is running
    if pgrep -f spamd > /dev/null; then
        echo -e "${GREEN}SpamAssassin is running${NC}"
        return 0
    else
        echo -e "${YELLOW}Warning: SpamAssassin failed to start properly${NC}"
        echo -e "${YELLOW}Continuing with other security tools...${NC}"
        return 1
    fi
}

configure_fail2ban() {
    log "Configuring Fail2Ban"
    
    # Install fail2ban if not present
    if ! command -v fail2ban-server &>/dev/null; then
        dnf install -y fail2ban
    fi
    
    # Create basic configuration
    cat > /etc/fail2ban/jail.local << 'EOF'
[DEFAULT]
bantime = 3600
findtime = 600
maxretry = 3
destemail = root@localhost
sender = fail2ban@localhost
action = %(action_mwl)s

[sshd]
enabled = true
port = ssh
filter = sshd
logpath = /var/log/secure
maxretry = 3
EOF

    # Create systemd service
    cat > /etc/systemd/system/fail2ban.service << 'EOF'
[Unit]
Description=Fail2Ban Service
After=network.target

[Service]
Type=simple
ExecStart=/usr/bin/fail2ban-server -xf start
ExecStop=/usr/bin/fail2ban-client stop
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF

    # Enable and start service
    systemctl daemon-reload
    systemctl enable fail2ban
    systemctl start fail2ban
}

# --- [Improved: Abstracted Tool Installer] ---
check_dnf() {
    echo "DEBUG: Checking DNF..."
    if ! command -v dnf &>/dev/null; then
        error_exit "DNF package manager is not installed"
    fi
    echo "DEBUG: DNF check passed"
}

check_internet() {
    echo "DEBUG: Checking internet connection..."
    if ! ping -c 1 fedoraproject.org &>/dev/null; then
        error_exit "No internet connection. Please check your network."
    fi
    echo "DEBUG: Internet check passed"
}

update_system() {
    echo "DEBUG: Starting system update..."
    echo -e "${BLUE}Updating system repositories...${NC}"
    if ! dnf update -y; then
        echo -e "${RED}Failed to update repositories${NC}"
        return 1
    fi
    echo "DEBUG: System update completed"
    return 0
}

install_tool_if_missing() {
    local pkg=$1
    echo "DEBUG: Checking package: $pkg"
    echo -e "${BLUE}Checking $pkg...${NC}"
    
    # Check if package is installed
    if ! dnf list installed "$pkg" &>/dev/null; then
        echo "DEBUG: Package $pkg not found, installing..."
        echo -e "${YELLOW}Installing $pkg...${NC}"
        if ! dnf install -y "$pkg" --setopt=install_weak_deps=False; then
            echo "DEBUG: Failed to install $pkg"
            echo -e "${RED}Failed to install $pkg${NC}"
            return 1
        fi
        echo "DEBUG: Successfully installed $pkg"
        echo -e "${GREEN}Successfully installed $pkg${NC}"
    else
        echo "DEBUG: Package $pkg already installed"
        echo -e "${GREEN}$pkg is already installed${NC}"
    fi
    return 0
}

# --- [AIDE & chkservices Integration] ---
install_aide() {
    log "Installing and configuring AIDE"
    
    # Kill any existing aide processes
    pkill -f aide || true
    sleep 2
    
    # Remove any existing lock files
    rm -f /var/log/aide/aide.log.lock
    rm -f /var/lib/aide/aide.db.lock
    
    # Install AIDE if not present
    if ! command -v aide &>/dev/null; then
        dnf install -y aide
    fi
    
    # Create AIDE configuration
    cat > /etc/aide.conf << 'EOF'
# AIDE configuration
@@define DBDIR /var/lib/aide
@@define LOGDIR /var/log/aide

# The location of the database to be read.
database=file:@@{DBDIR}/aide.db.gz

# The location of the database to be written.
database_out=file:@@{DBDIR}/aide.db.new.gz

# Whether to gzip the output to database.
gzip_dbout=yes

# Default rule
ALL = p+i+u+g+sha512

# Directories to check
/etc ALL
/bin ALL
/sbin ALL
/usr/bin ALL
/usr/sbin ALL
/usr/local/bin ALL
/usr/local/sbin ALL
/var/log ALL
/var/lib ALL
/var/spool ALL
/var/cache ALL
/var/run ALL
/var/lock ALL
/var/log/aide ALL
EOF

    # Create directories if they don't exist
    mkdir -p /var/lib/aide
    mkdir -p /var/log/aide
    
    # Set proper permissions
    chmod 0600 /etc/aide.conf
    chown root:root /etc/aide.conf
    
    # Initialize AIDE database with retry
    for i in {1..3}; do
        if aide --init; then
            echo -e "${GREEN}AIDE database initialized successfully${NC}"
            mv /var/lib/aide/aide.db.new.gz /var/lib/aide/aide.db.gz
            break
        fi
        echo -e "${YELLOW}Retry $i/3: Initializing AIDE database...${NC}"
        sleep 5
    done
    
    # Create daily check timer
    cat > /etc/systemd/system/aide-check.timer << 'EOF'
[Unit]
Description=Run AIDE check daily
After=network.target

[Timer]
OnCalendar=daily
AccuracySec=1h
Persistent=true

[Install]
WantedBy=timers.target
EOF

    # Create check service
    cat > /etc/systemd/system/aide-check.service << 'EOF'
[Unit]
Description=AIDE check
After=network.target

[Service]
Type=oneshot
ExecStart=/usr/sbin/aide --check
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF

    # Enable and start timer
    systemctl daemon-reload
    systemctl enable aide-check.timer
    systemctl start aide-check.timer
    
    echo -e "${GREEN}AIDE installation and configuration completed${NC}"
}

install_chkservices() {
    echo -e "${BLUE}Installing chkservices for service overview...${NC}"
    dnf install -y chkservice || echo -e "${YELLOW}chkservice not found in default repos. Skipping.${NC}"
}

# --- [Health Check Enhancements] ---
health_check() {
    check_root
    log "Performing health check"
    echo -e "${BLUE}Performing health check...${NC}"
    echo "========================================="

    # Check system services
    echo -e "\n${BLUE}System Services:${NC}"
    for service in maldet-update.timer fail2ban firewalld auditd aide-check.timer; do
        if systemctl is-active --quiet "$service"; then
            if [[ "$service" == *".timer" ]]; then
                next_run=$(systemctl list-timers --all | grep "$service" | awk '{print $1, $2}')
                echo -e "${CHECK} $service is running (next: $next_run)"
            else
                echo -e "${CHECK} $service is running"
            fi
        else
            echo -e "${CROSS} $service is NOT running"
        fi
    done

    # Check security tools
    echo -e "\n${BLUE}Security Tools:${NC}"
    declare -A tool_paths=(
        ["chkrootkit"]="/usr/sbin/chkrootkit"
        ["rkhunter"]="/usr/bin/rkhunter"
        ["lynis"]="/usr/bin/lynis"
        ["aide"]="/usr/sbin/aide"
        ["maldet"]="/usr/local/sbin/maldet"
    )

    for tool in "${!tool_paths[@]}"; do
        if [[ -x "${tool_paths[$tool]}" ]]; then
            echo -e "${CHECK} $tool is installed"
        else
            echo -e "${CROSS} $tool is NOT installed"
        fi
    done

    # Check SELinux
    echo -e "\n${BLUE}SELinux Status:${NC}"
    selinux_status=$(getenforce)
    if [[ "$selinux_status" == "Enforcing" ]]; then
        echo -e "${CHECK} SELinux is in Enforcing mode"
    else
        echo -e "${CROSS} SELinux is in $selinux_status mode"
    fi

    # Check AIDE database
    echo -e "\n${BLUE}AIDE Database:${NC}"
    if [[ -f /var/lib/aide/aide.db.gz ]]; then
        db_date=$(stat -c '%y' /var/lib/aide/aide.db.gz)
        echo -e "${CHECK} AIDE database exists (last modified: $db_date)"
    else
        echo -e "${CROSS} AIDE database not found"
    fi

    # Check Maldet signatures
    echo -e "\n${BLUE}Maldet Signatures:${NC}"
    if [[ -f /usr/local/maldetect/sigs/rfxn.ndb ]]; then
        sig_date=$(stat -c '%y' /usr/local/maldetect/sigs/rfxn.ndb)
        echo -e "${CHECK} Maldet signatures exist (last updated: $sig_date)"
    else
        echo -e "${CROSS} Maldet signatures not found"
    fi

    echo -e "\n${YELLOW}Press Enter to return to the main menu...${NC}"
    read
}

# --- [Main Tool Installation Improved] ---
install_security_tools() {
    echo -e "${BLUE}Installing security tools...${NC}"
    
    # Install chkrootkit
    echo -e "${BLUE}Installing chkrootkit...${NC}"
    if ! dnf install -y chkrootkit; then
        echo -e "${RED}Failed to install chkrootkit${NC}"
        return 1
    fi
    
    # Configure chkrootkit to run with sudo
    cat > /etc/systemd/system/chkrootkit.service << 'EOF'
[Unit]
Description=Chkrootkit Security Scanner
After=network.target

[Service]
Type=oneshot
ExecStart=/usr/sbin/chkrootkit
User=root
Group=root

[Install]
WantedBy=multi-user.target
EOF

    # Create daily timer for chkrootkit
    cat > /etc/systemd/system/chkrootkit.timer << 'EOF'
[Unit]
Description=Run Chkrootkit Daily

[Timer]
OnCalendar=daily
Persistent=true

[Install]
WantedBy=timers.target
EOF

    # Create sudoers entry for chkrootkit
    echo "%wheel ALL=(ALL) NOPASSWD: /usr/sbin/chkrootkit" | sudo tee /etc/sudoers.d/chkrootkit
    chmod 0440 /etc/sudoers.d/chkrootkit
    
    # Enable and start the timer
    systemctl daemon-reload
    systemctl enable chkrootkit.timer
    systemctl start chkrootkit.timer
    
    # Install Lynis
    echo -e "${BLUE}Installing Lynis...${NC}"
    if ! dnf install -y lynis; then
        echo -e "${RED}Failed to install Lynis${NC}"
        return 1
    fi
    
    # Configure Lynis
    mkdir -p /var/log/lynis
    chmod 750 /var/log/lynis
    
    # Create systemd service for Lynis
    cat > /etc/systemd/system/lynis.service << 'EOF'
[Unit]
Description=Lynis Security Scanner
After=network.target

[Service]
Type=oneshot
ExecStart=/usr/sbin/lynis audit system
User=root
Group=root

[Install]
WantedBy=multi-user.target
EOF

    # Create weekly timer for Lynis
    cat > /etc/systemd/system/lynis.timer << 'EOF'
[Unit]
Description=Run Lynis Weekly

[Timer]
OnCalendar=weekly
Persistent=true

[Install]
WantedBy=timers.target
EOF

    systemctl daemon-reload
    systemctl enable lynis.timer
    systemctl start lynis.timer
    
    # Install RKHunter
    echo -e "${BLUE}Installing RKHunter...${NC}"
    if ! dnf install -y rkhunter; then
        echo -e "${RED}Failed to install RKHunter${NC}"
        return 1
    fi
    
    # Update RKHunter database
    rkhunter --update
    rkhunter --propupd
    
    # Configure RKHunter
    sed -i 's/^CRON_DAILY_RUN=.*/CRON_DAILY_RUN="yes"/' /etc/default/rkhunter
    sed -i 's/^APT_AUTOGEN=.*/APT_AUTOGEN="yes"/' /etc/default/rkhunter
    
    # Create systemd service for RKHunter
    cat > /etc/systemd/system/rkhunter.service << 'EOF'
[Unit]
Description=Rootkit Hunter
After=network.target

[Service]
Type=oneshot
ExecStart=/usr/sbin/rkhunter --check --sk
User=root
Group=root

[Install]
WantedBy=multi-user.target
EOF

    # Create systemd timer for RKHunter
    cat > /etc/systemd/system/rkhunter.timer << 'EOF'
[Unit]
Description=Run RKHunter Daily

[Timer]
OnCalendar=daily
Persistent=true

[Install]
WantedBy=timers.target
EOF

    systemctl daemon-reload
    systemctl enable rkhunter.timer
    systemctl start rkhunter.timer
    
    # Validate installations
    echo -e "${BLUE}Validating installations...${NC}"
    
    # Check chkrootkit
    if command -v chkrootkit &>/dev/null; then
        echo -e "${CHECK} chkrootkit installed successfully"
    else
        echo -e "${CROSS} chkrootkit installation failed"
    fi
    
    # Check Lynis
    if command -v lynis &>/dev/null; then
        echo -e "${CHECK} lynis installed successfully"
    else
        echo -e "${CROSS} lynis installation failed"
    fi
    
    # Check RKHunter
    if command -v rkhunter &>/dev/null; then
        echo -e "${CHECK} rkhunter installed successfully"
    else
        echo -e "${CROSS} rkhunter installation failed"
    fi
    
    echo -e "${GREEN}Security tools installation completed${NC}"
}

# --- [Main Menu Stub] ---
while true; do
    clear
    echo -e "${BLUE}Fedora Security Suite (Optimized)${NC}"
    echo "1. Install Security Tools"
    echo "2. Health Check"
    echo "3. Manual Scans"
    echo "4. Exit"
    read -rp "Enter your choice: " choice
    case $choice in
        1) install_security_tools ;;
        2) health_check ;;
        3) check_root
           echo -e "${BLUE}Manual Scan Menu:${NC}"
           echo "1. Maldet Scan"
           echo "2. RKHunter Scan"
           echo "3. Chkrootkit Scan"
           echo "4. AIDE Integrity Check"
           echo "5. Full System Scan"
           echo "0. Back"
           read -rp "Select scan: " scan_choice
           case $scan_choice in
               1) maldet -a / ;;
               2) rkhunter --check --sk ;;
               3) chkrootkit ;;
               4) aide --check ;;
               5)
                   echo "Running full scan..."
                   maldet -a /
                   rkhunter --check --sk
                   chkrootkit
                   aide --check ;;
               0) ;;  # back
               *) echo -e "${RED}Invalid scan option${NC}"; sleep 2 ;;
           esac ;;
        4) echo -e "${GREEN}Exiting...${NC}"; exit 0 ;;
        *) echo -e "${RED}Invalid choice${NC}"; sleep 2 ;;
    esac
done