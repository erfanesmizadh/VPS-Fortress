#!/bin/bash
# =============================================
# VPS Security Enterprise - Safe SSH Upgrade
# ARM64 / Ubuntu Jammy version
# Author: @AVASH_NET
# =============================================

BRAND="AVASH_NET"

# --- Colors for menu & output ---
RED="\e[31m"
GREEN="\e[32m"
YELLOW="\e[33m"
BLUE="\e[34m"
CYAN="\e[36m"
RESET="\e[0m"

# --- Check root ---
if [[ $EUID -ne 0 ]]; then
    echo -e "${RED}This script must be run as root.${RESET}"
    exit 1
fi

# --- Default Ports ---
DEFAULT_USER_PORTS="2100,2200,8080,8880"
DEFAULT_TRAFFIC_PORTS="80,443,8080"
DEFAULT_SSH_PORT="2222"

# --- Banner ---
echo -e "${CYAN}"
echo "+--------------------------------------+"
echo "|         VPS SECURITY ENTERPRISE      |"
echo "|               $BRAND                 |"
echo "+--------------------------------------+"
echo -e "${RESET}"

# --- Update sources.list ---
echo "Fixing sources.list for ARM64 Ubuntu Jammy..."
cat > /etc/apt/sources.list <<EOL
deb http://ports.ubuntu.com/ubuntu-ports jammy main restricted universe multiverse
deb http://ports.ubuntu.com/ubuntu-ports jammy-updates main restricted universe multiverse
deb http://ports.ubuntu.com/ubuntu-ports jammy-security main restricted universe multiverse
EOL

apt clean
apt update -y && apt upgrade -y

# --- Install required packages ---
echo "Installing required packages..."
apt install -y ufw fail2ban ipset iptables-persistent curl netcat-openbsd

# --- User Inputs ---
read -p "User ports (Default $DEFAULT_USER_PORTS): " USER_PORTS
USER_PORTS=${USER_PORTS:-$DEFAULT_USER_PORTS}

read -p "Traffic ports (Default $DEFAULT_TRAFFIC_PORTS): " TRAFFIC_PORTS
TRAFFIC_PORTS=${TRAFFIC_PORTS:-$DEFAULT_TRAFFIC_PORTS}

read -p "New SSH port (Default $DEFAULT_SSH_PORT): " NEW_SSH_PORT
NEW_SSH_PORT=${NEW_SSH_PORT:-$DEFAULT_SSH_PORT}

# --- Backup SSH ---
echo "Backing up SSH config..."
cp /etc/ssh/sshd_config /etc/ssh/sshd_config.bak

# --- Configure SSH ---
SSHD_CONF="/etc/ssh/sshd_config"
sed -i '/^Port/d' $SSHD_CONF
sed -i '/^PasswordAuthentication/d' $SSHD_CONF
sed -i '/^PermitRootLogin/d' $SSHD_CONF
echo "Port $NEW_SSH_PORT" >> $SSHD_CONF
echo "PasswordAuthentication yes" >> $SSHD_CONF
echo "PermitRootLogin yes" >> $SSHD_CONF

# --- Test SSH config ---
sshd -t || { echo -e "${RED}SSH config error!${RESET}"; exit 1; }

# --- Open SSH port temporarily ---
ufw allow $NEW_SSH_PORT/tcp

# --- Setup UFW ---
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

# --- Restart SSH ---
systemctl restart sshd || { echo -e "${RED}Failed to restart SSH!${RESET}"; exit 1; }
echo -e "${GREEN}✅ SSH is active on port $NEW_SSH_PORT${RESET}"

# --- Setup fail2ban with iptables action ---
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

# --- Setup ipset + iptables persistently ---
ipset create banned hash:ip hashsize 4096 maxelem 100000 -exist
iptables -C INPUT -m set --match-set banned src -j DROP 2>/dev/null || iptables -I INPUT -m set --match-set banned src -j DROP
netfilter-persistent save

# --- Cloudflare / CDN IPs in allow list ---
ipset create allow_cf hash:ip hashsize 4096 maxelem 100000 -exist
CF_IPS=("173.245.48.0/20" "103.21.244.0/22" "103.22.200.0/22" "103.31.4.0/22" "141.101.64.0/18" "108.162.192.0/18")
for ip in "${CF_IPS[@]}"; do
    ipset add allow_cf $ip -exist
done

# --- Disable root login automatically after first SSH login ---
ROOT_LOCK_FILE="/root/.root_locked"
if [ ! -f "$ROOT_LOCK_FILE" ]; then
    echo "After your first SSH login, root login will be disabled automatically for security."
    cat >> /root/.bashrc <<'EOF'

# --- Auto-disable root login ---
LOCK_FILE="$HOME/.root_locked"
if [ ! -f "$LOCK_FILE" ]; then
    sed -i 's/^PermitRootLogin yes/PermitRootLogin prohibit-password/' /etc/ssh/sshd_config
    systemctl restart sshd
    touch "$LOCK_FILE"
    echo "✅ Root login disabled automatically for security."
fi
EOF
fi

# --- Final Report (Beautiful Table) ---
echo -e "${CYAN}+----------------------+---------------------------+"
echo -e "| ${YELLOW}Feature${CYAN}               | ${YELLOW}Status${CYAN}                    |"
echo -e "+----------------------+---------------------------+"
echo -e "| SSH Port             | ${GREEN}$NEW_SSH_PORT${CYAN}                 |"
echo -e "| Password Auth        | ${GREEN}Enabled temporarily${CYAN} |"
echo -e "| Root Login           | ${GREEN}Enabled temporarily${CYAN} |"
echo -e "| User Ports           | ${GREEN}$USER_PORTS${CYAN}         |"
echo -e "| Traffic Ports        | ${GREEN}$TRAFFIC_PORTS${CYAN}       |"
echo -e "| Fail2ban             | ${GREEN}Active${CYAN}              |"
echo -e "| UFW                  | ${GREEN}Active${CYAN}              |"
echo -e "| Cloudflare Allow IPs | ${GREEN}Added${CYAN}               |"
echo -e "+----------------------+---------------------------+"
echo -e "${RESET}"
echo -e "${GREEN}✅ $BRAND VPS Security Setup Complete!${RESET}"
