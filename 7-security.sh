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

    temp_dir=$(mktemp -d)
    curl -L "$LMD_URL" -o "$temp_dir/maldet.tar.gz"
    tar -xzf "$temp_dir/maldet.tar.gz" -C "$temp_dir"
    pushd "$temp_dir"/linux-malware-detect-* > /dev/null
    ./install.sh || error_exit "Failed to install Maldet"
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
    
    # Create basic configuration
    cat > /etc/mail/spamassassin/local.cf << 'EOF'
# Basic SpamAssassin configuration
required_score 5.0
report_safe 1
use_bayes 1
bayes_auto_learn 1
EOF
    
    chmod 0640 /etc/mail/spamassassin/local.cf
    
    # Update rules with retry
    for i in {1..3}; do
        if sa-update; then
            echo -e "\033[0;32mSpamAssassin rules updated successfully\033[0m"
            return 0
        fi
        echo -e "\033[1;33mRetry $i/3: Updating SpamAssassin rules...\033[0m"
        sleep 2
    done
    
    echo -e "\033[1;33mCould not update rules after 3 attempts\033[0m"
    return 1
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
    echo -e "${BLUE}Installing and configuring AIDE...${NC}"
    
    # Install AIDE if not present
    install_tool_if_missing aide
    
    # Initialize AIDE database
    if ! command -v aide >/dev/null 2>&1; then
        echo -e "${RED}AIDE command not found after installation${NC}"
        return 1
    fi
    
    # Create initial database if it doesn't exist
    if [[ ! -f /var/lib/aide/aide.db.gz ]]; then
        echo -e "${BLUE}Initializing AIDE database (this may take a while)...${NC}"
        if aide --init; then
            echo -e "${GREEN}AIDE database initialized successfully${NC}"
            mv -f /var/lib/aide/aide.db.new.gz /var/lib/aide/aide.db.gz
        else
            echo -e "${RED}AIDE initialization failed${NC}"
            return 1
        fi
    else
        echo -e "${GREEN}AIDE database already exists${NC}"
    fi

    # Set up AIDE check timer
    echo -e "${BLUE}Setting up AIDE check timer...${NC}"
    
    # Create service file with proper permissions
    cat > /etc/systemd/system/aide-check.service << 'EOF'
[Unit]
Description=AIDE Check
Documentation=man:aide(1)

[Service]
Type=oneshot
ExecStart=/usr/sbin/aide --check
EOF
    chmod 644 /etc/systemd/system/aide-check.service

    # Create timer file with proper permissions
    cat > /etc/systemd/system/aide-check.timer << 'EOF'
[Unit]
Description=Daily AIDE check

[Timer]
OnCalendar=daily
RandomizedDelaySec=1hour
Persistent=true

[Install]
WantedBy=timers.target
EOF
    chmod 644 /etc/systemd/system/aide-check.timer

    # Reload systemd and enable timer
    echo -e "${BLUE}Activating AIDE timer...${NC}"
    systemctl daemon-reload
    systemctl enable aide-check.timer
    systemctl start aide-check.timer

    # Verify timer status
    if systemctl is-active --quiet aide-check.timer; then
        echo -e "${GREEN}AIDE timer successfully activated${NC}"
        systemctl status aide-check.timer | grep "Trigger:" || true
    else
        echo -e "${RED}Failed to activate AIDE timer${NC}"
        return 1
    fi

    echo -e "${GREEN}AIDE setup completed successfully${NC}"
    return 0
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
    echo "DEBUG: Starting security tools installation..."
    check_root
    check_dnf
    check_internet
    cleanup_old_services
    log "Installing security tools"

    # Update system first
    if ! update_system; then
        echo -e "${RED}System update failed. Installation may not work correctly.${NC}"
        read -p "Press Enter to continue anyway or Ctrl+C to abort..."
    fi

    echo -e "${BLUE}Installing base tools...${NC}"
    local failed_packages=()
    local packages=(
        "chkrootkit"
        "rkhunter"
        "lynis"
        "fail2ban"
        "audit"
        "firewalld"
        "spamassassin"
        "aide"
        "openscap-scanner"
        "openscap-utils"
        "scap-security-guide"
        "selinux-policy"
        "selinux-policy-targeted"
        "setools-console"
        "policycoreutils"
        "policycoreutils-python-utils"
    )

    echo "DEBUG: Starting package installation loop..."
    for pkg in "${packages[@]}"; do
        echo "DEBUG: Processing package: $pkg"
        if ! install_tool_if_missing "$pkg"; then
            failed_packages+=("$pkg")
        fi
    done
    echo "DEBUG: Package installation loop completed"

    if [ ${#failed_packages[@]} -gt 0 ]; then
        echo -e "${RED}Failed to install the following packages:${NC}"
        printf '%s\n' "${failed_packages[@]}"
        echo -e "${YELLOW}Continuing with installation of other tools...${NC}"
    fi

    echo "DEBUG: Starting Maldet installation..."
    echo -e "${BLUE}Installing Maldet...${NC}"
    install_or_update_maldet

    echo "DEBUG: Starting service configuration..."
    echo -e "${BLUE}Configuring Fail2Ban, Firewalld, Auditd...${NC}"
    for svc in fail2ban firewalld auditd; do
        start_and_enable "$svc"
    done

    echo "DEBUG: Starting SELinux configuration..."
    echo -e "${BLUE}Configuring SELinux...${NC}"
    if ! setenforce 1; then
        echo -e "${YELLOW}Failed to set SELinux to enforcing mode${NC}"
    fi
    if ! sed -i 's/^SELINUX=.*/SELINUX=enforcing/' /etc/selinux/config; then
        echo -e "${YELLOW}Failed to update SELinux config${NC}"
    fi

    echo "DEBUG: Starting SpamAssassin configuration..."
    echo -e "${BLUE}Configuring SpamAssassin...${NC}"
    configure_spamassassin

    echo "DEBUG: Starting AIDE installation..."
    install_aide
    echo "DEBUG: Starting chkservices installation..."
    install_chkservices

    echo -e "${GREEN}Installation completed${NC}"
    echo
    echo "========================================="
    echo -e "${BLUE}Installed Services:${NC}"
    for svc in fail2ban firewalld auditd maldet-update.timer aide-check.timer; do
        echo -n "- $svc: "
        systemctl is-active --quiet "$svc" && echo -e "${GREEN}Active${NC}" || echo -e "${RED}Inactive${NC}"
    done
    echo
    echo -e "${BLUE}SELinux:${NC} $(getenforce)"
    echo -e "${BLUE}Log directory:${NC} $LOG_DIR"
    echo -e "${BLUE}AIDE DB:${NC} /var/lib/aide/aide.db.gz"
    echo "========================================="
    echo -e "${YELLOW}Press Enter to return to the main menu...${NC}"
    read
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