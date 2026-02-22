#!/bin/bash
# =============================================
# VPS Security Enterprise - Safe SSH Upgrade with Auto-Revert
# Author: @AVASH_NET
# =============================================

# --- Check root ---
if [[ $EUID -ne 0 ]]; then
    echo "This script must be run as root."
    exit 1
fi

# --- Default Ports ---
DEFAULT_USER_PORTS="2100,2200,8080,8880"
DEFAULT_TRAFFIC_PORTS="80,443,8080"
DEFAULT_SSH_PORT="2222"

# --- User Inputs with Defaults ---
read -p "User ports (Default $DEFAULT_USER_PORTS): " USER_PORTS
USER_PORTS=${USER_PORTS:-$DEFAULT_USER_PORTS}

read -p "Traffic ports (Default $DEFAULT_TRAFFIC_PORTS): " TRAFFIC_PORTS
TRAFFIC_PORTS=${TRAFFIC_PORTS:-$DEFAULT_TRAFFIC_PORTS}

read -p "New SSH port (Default $DEFAULT_SSH_PORT): " NEW_SSH_PORT
NEW_SSH_PORT=${NEW_SSH_PORT:-$DEFAULT_SSH_PORT}

# --- Update system ---
echo "Updating system..."
apt update -y && apt upgrade -y

# --- Install required packages ---
echo "Installing ufw, fail2ban, ipset, iptables-persistent, curl..."
apt install ufw fail2ban ipset iptables-persistent curl -y

# --- Backup SSH ---
echo "Backing up SSH config..."
SSHD_CONF="/etc/ssh/sshd_config"
cp $SSHD_CONF $SSHD_CONF.bak

# --- Configure SSH safely ---
echo "Configuring SSH securely..."

# Remove any existing Port NEW_SSH_PORT lines
sed -i "/Port $NEW_SSH_PORT/d" $SSHD_CONF
echo "Port $NEW_SSH_PORT" >> $SSHD_CONF

# Disable root login
sed -i "s/^PermitRootLogin .*/PermitRootLogin no/" $SSHD_CONF

# --- Test SSH config ---
sshd -t
if [[ $? -ne 0 ]]; then
    echo "SSH config test failed! Reverting..."
    cp $SSHD_CONF.bak $SSHD_CONF
    exit 1
fi

# --- Open new SSH port in ufw temporarily ---
ufw allow $NEW_SSH_PORT/tcp

# --- Restart SSH safely with rollback ---
systemctl restart sshd
sleep 2

# Test SSH port is listening
nc -z -w5 127.0.0.1 $NEW_SSH_PORT
if [[ $? -ne 0 ]]; then
    echo "SSH on new port failed! Rolling back to previous config..."
    cp $SSHD_CONF.bak $SSHD_CONF
    systemctl restart sshd
    exit 1
fi

echo "✅ SSH is active on port $NEW_SSH_PORT"

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

# --- Setup fail2ban ---
systemctl enable fail2ban
systemctl start fail2ban

cat > /etc/fail2ban/jail.d/custom.conf <<EOL
[sshd]
enabled = true
port = $NEW_SSH_PORT
filter = sshd
logpath = /var/log/auth.log
maxretry = 5
bantime = 3600

[ufw]
enabled = true
filter = ufw
logpath = /var/log/ufw.log
maxretry = 5
bantime = 3600
EOL

systemctl restart fail2ban

# --- Setup ipset + iptables ---
ipset create banned hash:ip hashsize 4096 maxelem 100000 -exist
iptables -I INPUT -m set --match-set banned src -j DROP

mkdir -p /etc/fail2ban/action.d
cat > /etc/fail2ban/action.d/ipset.conf <<EOL
[Definition]
actionstart =
actionstop =
actioncheck =
actionban = ipset add banned <ip>
actionunban = ipset del banned <ip>
EOL

# --- Add Cloudflare / CDN IPs ---
CF_IPS=("173.245.48.0/20" "103.21.244.0/22" "103.22.200.0/22" "103.31.4.0/22" "141.101.64.0/18" "108.162.192.0/18")
for ip in "${CF_IPS[@]}"; do
    ipset add banned $ip -exist
done

# --- Final Report ---
echo "======================================="
echo "✅ VPS Security Enterprise is active!"
echo "SSH is on port: $NEW_SSH_PORT and root login is disabled."
echo "User ports opened: $USER_PORTS"
echo "Traffic ports opened: $TRAFFIC_PORTS"
echo "Fail2ban is active and suspicious IPs are blocked."
echo "UFW is active and default block rules applied."
echo "Cloudflare/CDN IPs added to block list."
echo "SSH backup: /etc/ssh/sshd_config.bak"
echo "Check UFW status: sudo ufw status verbose"
echo "Check Fail2ban status: sudo fail2ban-client status"
echo "Blocked IPs: sudo ipset list banned"
echo "======================================="
