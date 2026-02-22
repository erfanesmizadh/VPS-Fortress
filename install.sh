#!/bin/bash
# =============================================
# Enterprise VPS Security Script
# Author: ChatGPT
# =============================================

# --- Check root ---
if [[ $EUID -ne 0 ]]; then
    echo "این اسکریپت باید با دسترسی root اجرا شود."
    exit 1
fi

# --- User Inputs ---
read -p "پورت‌های یوزر (مثلا 2100,2101): " USER_PORTS
read -p "پورت‌های ترافیک (مثلا 80,443,8080): " TRAFFIC_PORTS
read -p "پورت SSH جدید شما (مثلا 2222): " NEW_SSH_PORT

# --- Update system ---
echo "در حال بروزرسانی سیستم..."
apt update -y && apt upgrade -y

# --- Install packages ---
echo "در حال نصب ufw, fail2ban, ipset, iptables-persistent, curl..."
apt install ufw fail2ban ipset iptables-persistent curl -y

# --- Backup SSH ---
cp /etc/ssh/sshd_config /etc/ssh/sshd_config.bak

# --- SSH Security ---
sed -i "s/#Port 22/Port $NEW_SSH_PORT/" /etc/ssh/sshd_config
sed -i "s/Port 22/Port $NEW_SSH_PORT/" /etc/ssh/sshd_config
sed -i "s/PermitRootLogin yes/PermitRootLogin no/" /etc/ssh/sshd_config
systemctl restart sshd

# --- Setup UFW ---
ufw default deny incoming
ufw default allow outgoing
ufw allow $NEW_SSH_PORT/tcp
ufw limit $NEW_SSH_PORT/tcp

# Allow user ports
IFS=',' read -ra UP <<< "$USER_PORTS"
for port in "${UP[@]}"; do
    ufw allow "$port"/tcp
done

# Allow traffic ports
IFS=',' read -ra TP <<< "$TRAFFIC_PORTS"
for port in "${TP[@]}"; do
    ufw allow "$port"/tcp
done

ufw --force enable

# --- Setup fail2ban ---
systemctl enable fail2ban
systemctl start fail2ban

# Custom fail2ban configuration
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

# --- Setup ipset + iptables for auto-block ---
ipset create banned hash:ip hashsize 4096 maxelem 100000 -exist
iptables -I INPUT -m set --match-set banned src -j DROP

# Fail2ban action for ipset
mkdir -p /etc/fail2ban/action.d
cat > /etc/fail2ban/action.d/ipset.conf <<EOL
[Definition]
actionstart =
actionstop =
actioncheck =
actionban = ipset add banned <ip>
actionunban = ipset del banned <ip>
EOL

# --- Add Cloudflare / CDN IP ranges automatically ---
echo "در حال اضافه کردن IP های Cloudflare به لیست بلاک (اختیاری)..."
CF_IPS=("173.245.48.0/20" "103.21.244.0/22" "103.22.200.0/22" "103.31.4.0/22" "141.101.64.0/18" "108.162.192.0/18")
for ip in "${CF_IPS[@]}"; do
    ipset add banned $ip -exist
done

# --- Reporting & Monitoring ---
echo "======================================="
echo "✅ VPS Security Enterprise فعال شد!"
echo "SSH روی پورت: $NEW_SSH_PORT و root login غیرفعال شد."
echo "پورت‌های یوزر باز شدند: $USER_PORTS"
echo "پورت‌های ترافیک باز شدند: $TRAFFIC_PORTS"
echo "Fail2ban فعال و آی‌پی‌های مشکوک بلاک می‌شوند."
echo "ufw فعال و بلاک پیش‌فرض اعمال شد."
echo "Cloudflare/CDN IP ها به لیست بلاک اضافه شدند."
echo "نسخه پشتیبان SSH: /etc/ssh/sshd_config.bak"
echo "برای وضعیت ufw: sudo ufw status verbose"
echo "برای وضعیت fail2ban: sudo fail2ban-client status"
echo "برای آی‌پی‌های بلاک شده: sudo ipset list banned"
echo "======================================="
