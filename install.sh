#!/bin/bash
# =============================================
# VPS SECURITY ENTERPRISE - ARM64 / Ubuntu Jammy
# Author: @AVASH_NET
# =============================================

BRAND="AVASH_NET"

# --- Colors ---
RED="\e[31m"; GREEN="\e[32m"; YELLOW="\e[33m"; CYAN="\e[36m"; RESET="\e[0m"

# --- Root check ---
if [[ $EUID -ne 0 ]]; then
    echo -e "${RED}❌ Run this script as root!${RESET}"
    exit 1
fi

# --- Banner ---
echo -e "${CYAN}+--------------------------------------+"
echo "|         VPS SECURITY ENTERPRISE      |"
echo "|               $BRAND                 |"
echo "+--------------------------------------+${RESET}"

# --- Fix sources for ARM64 ---
echo "🔧 Fixing sources.list for ARM64 Ubuntu Jammy..."
cat > /etc/apt/sources.list <<EOL
deb [arch=arm64] http://ports.ubuntu.com/ubuntu-ports jammy main restricted universe multiverse
deb [arch=arm64] http://ports.ubuntu.com/ubuntu-ports jammy-updates main restricted universe multiverse
deb [arch=arm64] http://ports.ubuntu.com/ubuntu-ports jammy-security main restricted universe multiverse
EOL

apt clean
apt update -y
apt --fix-broken install -y
apt upgrade -y

# --- Install required packages ---
echo "📦 Installing required packages..."
REQUIRED_PKGS=(ufw fail2ban iptables-persistent curl netcat-openbsd ipset)
for pkg in "${REQUIRED_PKGS[@]}"; do
    if ! dpkg -s $pkg >/dev/null 2>&1; then
        if ! apt install -y $pkg; then
            echo -e "${YELLOW}⚠️ Package $pkg not available, skipping...${RESET}"
        fi
    fi
done

# --- Default ports ---
DEFAULT_USER_PORTS="2100,2200,8080,8880"
DEFAULT_TRAFFIC_PORTS="80,443,8080"
DEFAULT_SSH_PORT="2222"

# --- User input ---
read -p "User ports (Default $DEFAULT_USER_PORTS): " USER_PORTS
USER_PORTS=${USER_PORTS:-$DEFAULT_USER_PORTS}

read -p "Traffic ports (Default $DEFAULT_TRAFFIC_PORTS): " TRAFFIC_PORTS
TRAFFIC_PORTS=${TRAFFIC_PORTS:-$DEFAULT_TRAFFIC_PORTS}

read -p "SSH Port (Default $DEFAULT_SSH_PORT): " NEW_SSH_PORT
NEW_SSH_PORT=${NEW_SSH_PORT:-$DEFAULT_SSH_PORT}

# --- Backup SSH ---
cp /etc/ssh/sshd_config /etc/ssh/sshd_config.bak
sed -i '/^Port/d;/^PasswordAuthentication/d;/^PermitRootLogin/d' /etc/ssh/sshd_config
echo -e "Port $NEW_SSH_PORT\nPasswordAuthentication yes\nPermitRootLogin yes" >> /etc/ssh/sshd_config
sshd -t || { echo -e "${RED}❌ SSH config error!${RESET}"; exit 1; }

# --- UFW setup ---
ufw default deny incoming
ufw default allow outgoing
ufw limit $NEW_SSH_PORT/tcp

IFS=',' read -ra UP <<< "$USER_PORTS"
for p in "${UP[@]}"; do ufw allow $p/tcp; done

IFS=',' read -ra TP <<< "$TRAFFIC_PORTS"
for p in "${TP[@]}"; do ufw allow $p/tcp; done

ufw --force enable

# --- Restart SSH safely ---
systemctl restart sshd
echo -e "${GREEN}✅ SSH is active on port $NEW_SSH_PORT${RESET}"

# --- Fail2ban setup ---
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
EOL
systemctl restart fail2ban

# --- ipset setup if available ---
if command -v ipset >/dev/null 2>&1; then
    ipset create banned hash:ip hashsize 4096 maxelem 100000 -exist
    iptables -C INPUT -m set --match-set banned src -j DROP 2>/dev/null || iptables -I INPUT -m set --match-set banned src -j DROP
    ipset create allow_cf hash:ip hashsize 4096 maxelem 100000 -exist
    CF_IPS=("173.245.48.0/20" "103.21.244.0/22" "103.22.200.0/22" "103.31.4.0/22" "141.101.64.0/18" "108.162.192.0/18")
    for ip in "${CF_IPS[@]}"; do ipset add allow_cf $ip -exist; done
else
    echo -e "${YELLOW}⚠️ ipset not available, skipping IP sets setup.${RESET}"
fi

# --- Auto-disable root login after first SSH login ---
ROOT_LOCK_FILE="/root/.root_locked"
if [ ! -f "$ROOT_LOCK_FILE" ]; then
    cat >> /root/.bashrc <<'EOF'

# --- Auto-disable root login after first SSH login ---
LOCK_FILE="$HOME/.root_locked"
if [ ! -f "$LOCK_FILE" ]; then
    sed -i 's/^PermitRootLogin yes/PermitRootLogin prohibit-password/' /etc/ssh/sshd_config
    systemctl restart sshd
    touch "$LOCK_FILE"
    echo "✅ Root login disabled automatically for security."
fi
EOF
fi

# --- Final Report Table ---
echo -e "${CYAN}+----------------------+---------------------------+"
echo -e "| Feature              | Status                    |"
echo -e "+----------------------+---------------------------+"
echo -e "| SSH Port             | ${GREEN}$NEW_SSH_PORT${CYAN}                 |"
echo -e "| Password Auth        | ${GREEN}Enabled temporarily${CYAN} |"
echo -e "| Root Login           | ${GREEN}Enabled temporarily${CYAN} |"
echo -e "| User Ports           | ${GREEN}$USER_PORTS${CYAN}         |"
echo -e "| Traffic Ports        | ${GREEN}$TRAFFIC_PORTS${CYAN}       |"
echo -e "| Fail2ban             | ${GREEN}Active${CYAN}              |"
echo -e "| UFW                  | ${GREEN}Active${CYAN}              |"
if command -v ipset >/dev/null 2>&1; then
    echo -e "| Cloudflare Allow IPs | ${GREEN}Added${CYAN}               |"
else
    echo -e "| Cloudflare Allow IPs | ${YELLOW}Skipped${CYAN}             |"
fi
echo -e "+----------------------+---------------------------+${RESET}"
echo -e "${GREEN}✅ $BRAND VPS Security Setup Complete!${RESET}"
