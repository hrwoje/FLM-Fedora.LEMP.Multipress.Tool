#!/bin/bash

# =======================================
# FNMPW Toolkit - install.sh
# Fedora Nginx MariaDB PHP-FPM WordPress
# Author & Copyright: Hrwoje Dabo
# =======================================

# Color Codes
RED='\e[31m'
GREEN='\e[32m'
YELLOW='\e[33m'
BLUE='\e[34m'
MAGENTA='\e[35m'
CYAN='\e[36m'
BOLD='\e[1m'
RESET='\e[0m'

# List of scripts
SCRIPTS=(
  "1-php.sh"
  "2-mysql.sh"
  "3-nginx.sh"
  "4-wordpress.sh"
  "5-nginx-serverblocks.sh"
  "6-multipress.sh"
  "7-security.sh"
  "8-ssl.sh"
  "9-extra.sh"
)

# ASCII Dragon Header
ascii_art() {
cat << "EOF"
                             ______________
                            /             /|
                           /             / |
                          /____________ /  |
                         | ___________ |   |
                         ||           ||   |
                         ||   FNMPW   ||   |
                         ||  TOOLKIT  ||   |
                         ||___________||   |
                         |   _______   |  /
                        /|  (_______)  | /
                       ( |_____________|/
                        \_/___________/

EOF
}

# Display the menu
show_menu() {
  clear
  echo -e "${CYAN}"
  ascii_art
  echo -e "${RESET}${BOLD}${BLUE}FNMPW Toolkit${RESET}"
  echo -e "${YELLOW}Fedora Nginx MariaDB PHP-FPM WordPress${RESET}"
  echo -e "${MAGENTA}Author: Hrwoje Dabo${RESET}"
  echo "====================================================="
  echo ""
  echo -e "${BOLD}Select a script to run:${RESET}"
  for i in "${!SCRIPTS[@]}"; do
    script_name="${SCRIPTS[$i]}"
    script_title=$(echo "$script_name" | cut -d'-' -f2- | sed 's/.sh//;s/-/ /g')
    printf "  ${GREEN}[%d]${RESET} %s\n" $((i + 1)) "$script_title"
  done
  echo -e "  ${BLUE}[b]${RESET} Back to main menu"
  echo -e "  ${RED}[q]${RESET} Quit"
  echo ""
}

# Execute the selected script
run_script() {
  local choice="$1"
  if [[ "$choice" =~ ^[1-9]$ && "$choice" -le ${#SCRIPTS[@]} ]]; then
    script="./${SCRIPTS[$((choice - 1))]}"
    if [[ -f "$script" && -x "$script" ]]; then
      clear
      echo -e "${BOLD}Running script: $script${RESET}"
      echo -e "${CYAN}Press 'b' to return to the main menu...${RESET}"
      while true; do
        "$script"
        echo ""
        read -rp "[b] Back to menu: " back
        [[ "$back" == "b" || "$back" == "B" ]] && break
      done
    else
      echo -e "${RED}Error: Script $script not found or not executable.${RESET}"
      read -rp "Press Enter to return..."
    fi
  else
    echo -e "${RED}Invalid selection.${RESET}"
    sleep 1
  fi
}

# Main control loop
main() {
  while true; do
    show_menu
    read -rp "Your choice: " user_input
    case "$user_input" in
      [1-9]) run_script "$user_input" ;;
      b|B) continue ;;
      q|Q) echo -e "${YELLOW}Goodbye!${RESET}"; exit 0 ;;
      *) echo -e "${RED}Invalid input.${RESET}"; sleep 1 ;;
    esac
  done
}

# Make sure scripts are executable
for file in "${SCRIPTS[@]}"; do
  chmod +x "$file" 2>/dev/null
done

# Start the menu
main

