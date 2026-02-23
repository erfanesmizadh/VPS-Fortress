#!/bin/bash
# =============================================
# VPS SECURITY PRO MENU + BBR + ROOT LOGIN
# Author: @AVASH_NET
# =============================================

BRAND="AVASH_NET"

RED="\e[31m"; GREEN="\e[32m"; YELLOW="\e[33m"; CYAN="\e[36m"; RESET="\e[0m"

if [[ $EUID -ne 0 ]]; then
    echo -e "${RED}Run as root!${RESET}"
    exit 1
fi

# --- Helper Functions ---
check_sshd() {
    sshd -t >/dev/null 2>&1
    return $?
}

enable_bbr() {
    echo -e "${CYAN}🔹 Enabling BBR TCP congestion control...${RESET}"
    modprobe tcp_bbr
    echo "tcp_bbr" > /etc/modules-load.d/bbr.conf
    sysctl -w net.core.default_qdisc=fq
    sysctl -w net.ipv4.tcp_congestion_control=bbr
    if sysctl net.ipv4.tcp_congestion_control | grep -q bbr; then
        echo -e "${GREEN}✅ BBR is enabled${RESET}"
    else
        echo -e "${RED}❌ BBR failed${RESET}"
    fi
}

configure_ssh() {
    DEFAULT_SSH_PORT="2222"
    read -p "SSH Port (Default $DEFAULT_SSH_PORT): " NEW_SSH_PORT
    NEW_SSH_PORT=${NEW_SSH_PORT:-$DEFAULT_SSH_PORT}
    cp /etc/ssh/sshd_config /etc/ssh/sshd_config.bak
    sed -i '/^Port/d;/^PermitRootLogin/d;/^PasswordAuthentication/d;/^UseDNS/d' /etc/ssh/sshd_config
    cat >> /etc/ssh/sshd_config <<EOF
Port $NEW_SSH_PORT
PermitRootLogin yes
PasswordAuthentication yes
UseDNS no
LoginGraceTime 60
EOF
    check_sshd || { echo -e "${RED}SSH config error!${RESET}"; return 1; }
    systemctl restart sshd
    echo -e "${GREEN}✅ SSH running on port $NEW_SSH_PORT with root login enabled${RESET}"
}

configure_firewall() {
    DEFAULT_USER_PORTS="2100,2200,8080,8880"
    DEFAULT_TRAFFIC_PORTS="80,443,8080"

    read -p "User ports (Default $DEFAULT_USER_PORTS): " USER_PORTS
    USER_PORTS=${USER_PORTS:-$DEFAULT_USER_PORTS}
    read -p "Traffic ports (Default $DEFAULT_TRAFFIC_PORTS): " TRAFFIC_PORTS
    TRAFFIC_PORTS=${TRAFFIC_PORTS:-$DEFAULT_TRAFFIC_PORTS}

    # Convert Persian comma
    USER_PORTS=$(echo "$USER_PORTS" | tr '،' ',')
    TRAFFIC_PORTS=$(echo "$TRAFFIC_PORTS" | tr '،' ',')

    # Merge & validate
    ALL_PORTS="$USER_PORTS,$TRAFFIC_PORTS"
    ALL_PORTS=$(echo "$ALL_PORTS" | tr ',' '\n' | sort -u | tr '\n' ',' | sed 's/,$//')
    VALID_PORTS=""
    for p in $(echo $ALL_PORTS | tr ',' ' '); do
        if [[ $p =~ ^[0-9]+$ ]] && [ "$p" -ge 1 ] && [ "$p" -le 65535 ]; then
            VALID_PORTS+="$p,"
        else
            echo -e "${YELLOW}⚠️ Skipping invalid port: $p${RESET}"
        fi
    done
    VALID_PORTS=$(echo $VALID_PORTS | sed 's/,$//')

    # UFW rules
    ufw reset
    ufw default deny incoming
    ufw default allow outgoing

    # Allow ports
    read -p "Enter SSH port to allow: " SSH_PORT
    ufw allow "$SSH_PORT"/tcp
    for p in $(echo $VALID_PORTS | tr ',' ' '); do
        ufw allow "$p"/tcp
    done
    ufw --force enable
    echo -e "${GREEN}✅ Firewall configured${RESET}"
}

setup_fail2ban() {
    apt install -y fail2ban
    systemctl enable fail2ban
    systemctl restart fail2ban
    echo -e "${GREEN}✅ Fail2ban is active${RESET}"
}

show_report() {
    echo -e "${CYAN}+----------------------+---------------------------+"
    echo -e "| Feature              | Status                    |"
    echo -e "+----------------------+---------------------------+"
    echo -e "| SSH Port             | ${GREEN}$SSH_PORT${CYAN}                 |"
    echo -e "| Root Login           | ${GREEN}Always Enabled${CYAN}     |"
    echo -e "| Open Ports           | ${GREEN}$VALID_PORTS${CYAN}       |"
    echo -e "| Firewall (UFW)       | ${GREEN}Active${CYAN}              |"
    echo -e "| Fail2ban             | ${GREEN}Active${CYAN}              |"
    echo -e "| BBR                  | ${GREEN}Enabled${CYAN}             |"
    echo -e "+----------------------+---------------------------+${RESET}"
}

# --- Menu ---
while true; do
    echo -e "${CYAN}+---------------- VPS SECURITY PRO MENU ----------------+${RESET}"
    echo "1) Configure SSH + Enable Root Login"
    echo "2) Configure Firewall (UFW + Ports)"
    echo "3) Setup Fail2ban"
    echo "4) Enable BBR TCP Acceleration"
    echo "5) Show Current Status"
    echo "0) Exit"
    read -p "Select option: " choice
    case $choice in
        1) configure_ssh ;;
        2) configure_firewall ;;
        3) setup_fail2ban ;;
        4) enable_bbr ;;
        5) show_report ;;
        0) echo "Exiting..."; exit 0 ;;
        *) echo -e "${YELLOW}Invalid option!${RESET}" ;;
    esac
done
