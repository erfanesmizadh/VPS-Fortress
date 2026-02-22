#!/bin/bash
# =============================================
# VPS SECURITY ENTERPRISE - FULL INSTALL & DASHBOARD
# Author: @AVASH_NET
# ARM64 / Ubuntu Jammy
# =============================================

BRAND="AVASH_NET"

# --- Colors ---
RED="\e[31m"
GREEN="\e[32m"
YELLOW="\e[33m"
BLUE="\e[34m"
CYAN="\e[36m"
RESET="\e[0m"

# --- Default Ports ---
DEFAULT_USER_PORTS="2100,2200,8080,8880"
DEFAULT_TRAFFIC_PORTS="80,443,8080"
DEFAULT_SSH_PORT="2222"

# --- Check root ---
if [[ $EUID -ne 0 ]]; then
    echo -e "${RED}This script must be run as root.${RESET}"
    exit 1
fi

# --- Banner ---
show_banner() {
    clear
    echo -e "${CYAN}+--------------------------------------+"
    echo -e "|         VPS SECURITY ENTERPRISE      |"
    echo -e "|               $BRAND                 |"
    echo -e "+--------------------------------------+${RESET}"
}

# --- Update sources.list safely for ARM64 Jammy ---
update_system() {
    echo "Fixing sources.list for ARM64 Ubuntu Jammy..."
    cat > /etc/apt/sources.list <<EOL
deb [arch=arm64] http://ports.ubuntu.com/ubuntu-ports jammy main restricted universe multiverse
deb [arch=arm64] http://ports.ubuntu.com/ubuntu-ports jammy-updates main restricted universe multiverse
deb [arch=arm64] http://ports.ubuntu.com/ubuntu-ports jammy-security main restricted universe multiverse
EOL
    apt clean
    apt update -y && apt upgrade -y
}

# --- Install required packages ---
install_packages() {
    echo "Installing required packages..."
    apt install -y ufw fail2ban ipset iptables-persistent curl netcat-openbsd
}

# --- Setup SSH ---
setup_ssh() {
    read -p "User ports (Default $DEFAULT_USER_PORTS): " USER_PORTS
    USER_PORTS=${USER_PORTS:-$DEFAULT_USER_PORTS}

    read -p "Traffic ports (Default $DEFAULT_TRAFFIC_PORTS): " TRAFFIC_PORTS
    TRAFFIC_PORTS=${TRAFFIC_PORTS:-$DEFAULT_TRAFFIC_PORTS}

    read -p "New SSH port (Default $DEFAULT_SSH_PORT): " NEW_SSH_PORT
    NEW_SSH_PORT=${NEW_SSH_PORT:-$DEFAULT_SSH_PORT}

    echo "Backing up SSH config..."
    cp /etc/ssh/sshd_config /etc/ssh/sshd_config.bak

    SSHD_CONF="/etc/ssh/sshd_config"
    sed -i '/^Port/d' $SSHD_CONF
    sed -i '/^PasswordAuthentication/d' $SSHD_CONF
    sed -i '/^PermitRootLogin/d' $SSHD_CONF
    echo "Port $NEW_SSH_PORT" >> $SSHD_CONF
    echo "PasswordAuthentication yes" >> $SSHD_CONF
    echo "PermitRootLogin yes" >> $SSHD_CONF

    sshd -t || { echo -e "${RED}SSH config error!${RESET}"; exit 1; }

    ufw allow $NEW_SSH_PORT/tcp
    systemctl restart sshd
    echo -e "${GREEN}✅ SSH is active on port $NEW_SSH_PORT${RESET}"
}

# --- Setup UFW ---
setup_ufw() {
    ufw default deny incoming
    ufw default allow outgoing
    ufw limit $NEW_SSH_PORT/tcp

    IFS=',' read -ra UP <<< "$USER_PORTS"
    for port in "${UP[@]}"; do
        ufw allow "$port"/tcp
    done

    IFS=',' read -ra TP <<< "$TRAFFIC_PORTS"
    for port in "${TP[@]}"; do
        ufw allow "$port"/tcp
    done

    ufw --force enable
}

# --- Setup fail2ban ---
setup_fail2ban() {
    systemctl enable fail2ban
    systemctl start fail2ban

    mkdir -p /etc/fail2ban/jail.d
    cat > /etc/fail2ban/jail.d/custom.conf <<EOL
[sshd]
enabled = true
port = $NEW_SSH_PORT
filter = sshd
logpath = /var/log/auth.log
maxretry = 5
bantime = 3600
action = iptables[name=SSH, port=$NEW_SSH_PORT, protocol=tcp]

[ufw]
enabled = true
filter = ufw
logpath = /var/log/ufw.log
maxretry = 5
bantime = 3600
EOL

    systemctl restart fail2ban
}

# --- Setup ipset ---
setup_ipset() {
    ipset create banned hash:ip hashsize 4096 maxelem 100000 -exist
    iptables -C INPUT -m set --match-set banned src -j DROP 2>/dev/null || iptables -I INPUT -m set --match-set banned src -j DROP
    netfilter-persistent save

    ipset create allow_cf hash:ip hashsize 4096 maxelem 100000 -exist
    CF_IPS=("173.245.48.0/20" "103.21.244.0/22" "103.22.200.0/22" "103.31.4.0/22" "141.101.64.0/18" "108.162.192.0/18")
    for ip in "${CF_IPS[@]}"; do
        ipset add allow_cf $ip -exist
    done
}

# --- Interactive Dashboard Functions ---
show_status() {
    SSH_PORT=$(grep -E "^Port " /etc/ssh/sshd_config | awk '{print $2}')
    PASSWORD_AUTH=$(grep -E "^PasswordAuthentication " /etc/ssh/sshd_config | awk '{print $2}')
    ROOT_LOGIN=$(grep -E "^PermitRootLogin " /etc/ssh/sshd_config | awk '{print $2}')
    UFW_STATUS=$(ufw status | head -1)
    FAIL2BAN_STATUS=$(systemctl is-active fail2ban)
    echo -e "${CYAN}+----------------------+---------------------------+"
    echo -e "| ${YELLOW}Feature${CYAN}               | ${YELLOW}Status${CYAN}                    |"
    echo -e "+----------------------+---------------------------+"
    echo -e "| SSH Port             | ${GREEN}${SSH_PORT}${CYAN}                 |"
    echo -e "| Password Auth        | ${GREEN}${PASSWORD_AUTH}${CYAN}           |"
    echo -e "| Root Login           | ${GREEN}${ROOT_LOGIN}${CYAN}           |"
    echo -e "| UFW                  | ${GREEN}${UFW_STATUS}${CYAN} |"
    echo -e "| Fail2ban             | ${GREEN}${FAIL2BAN_STATUS}${CYAN}              |"
    echo -e "+----------------------+---------------------------+${RESET}"
}

change_ssh_port() {
    read -p "Enter new SSH port: " NEW_PORT
    sed -i "/^Port /c\Port $NEW_PORT" /etc/ssh/sshd_config
    ufw allow $NEW_PORT/tcp
    systemctl restart sshd
    echo -e "${GREEN}✅ SSH port changed to $NEW_PORT${RESET}"
}

toggle_root_login() {
    CURRENT=$(grep "^PermitRootLogin" /etc/ssh/sshd_config | awk '{print $2}')
    if [[ "$CURRENT" == "yes" ]]; then
        sed -i 's/^PermitRootLogin yes/PermitRootLogin prohibit-password/' /etc/ssh/sshd_config
        echo -e "${YELLOW}Root login disabled.${RESET}"
    else
        sed -i 's/^PermitRootLogin prohibit-password/PermitRootLogin yes/' /etc/ssh/sshd_config
        echo -e "${GREEN}Root login enabled.${RESET}"
    fi
    systemctl restart sshd
}

manage_ports() {
    echo "1) Open port"
    echo "2) Close port"
    read -p "Choose option: " PORT_OPTION
    read -p "Enter port number: " PORT_NUM
    if [[ "$PORT_OPTION" == "1" ]]; then
        ufw allow $PORT_NUM/tcp
        echo -e "${GREEN}Port $PORT_NUM opened.${RESET}"
    else
        ufw delete allow $PORT_NUM/tcp
        echo -e "${RED}Port $PORT_NUM closed.${RESET}"
    fi
}

show_ipsets() {
    echo -e "${CYAN}--- Blocked IPs ---${RESET}"
    ipset list banned
    echo -e "${CYAN}--- Allowed Cloudflare IPs ---${RESET}"
    ipset list allow_cf
}

main_menu() {
    while true; do
        show_banner
        show_status
        echo -e "${YELLOW}1) Change SSH Port${RESET}"
        echo -e "${YELLOW}2) Toggle Root Login${RESET}"
        echo -e "${YELLOW}3) Manage Ports (Open/Close)${RESET}"
        echo -e "${YELLOW}4) Show IP Sets${RESET}"
        echo -e "${YELLOW}5) Exit${RESET}"
        read -p "Choose an option: " CHOICE
        case $CHOICE in
            1) change_ssh_port ;;
            2) toggle_root_login ;;
            3) manage_ports ;;
            4) show_ipsets ;;
            5) exit 0 ;;
            *) echo -e "${RED}Invalid option!${RESET}" ;;
        esac
        read -p "Press Enter to continue..."
    done
}

# --- Run Installation ---
show_banner
update_system
install_packages
setup_ssh
setup_ufw
setup_fail2ban
setup_ipset

echo -e "${GREEN}✅ $BRAND VPS Security Installed Successfully!${RESET}"
echo "Launching interactive dashboard..."
main_menu
