#!/bin/bash
# =============================================
# VPS Security Enterprise - Safe SSH Upgrade
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

# --- Install required packages ---
echo "در حال نصب ufw, fail2ban, ipset, iptables-persistent, curl..."
apt install ufw fail2ban ipset iptables-persistent curl -y

# --- Backup SSH ---
cp /etc/ssh/sshd_config /etc/ssh/sshd_config.bak

# --- Configure SSH safely ---
echo "در حال پیکربندی SSH به صورت امن..."
SSHD_CONF="/etc/ssh/sshd_config"

# Remove any existing Port NEW_SSH_PORT lines
sed -i "/Port $NEW_SSH_PORT/d" $SSHD_CONF
echo "Port $NEW_SSH_PORT" >> $SSHD_CONF

# Disable root login
sed -i "s/^PermitRootLogin .*/PermitRootLogin no/" $SSHD_CONF

# --- Test new SSH port locally ---
echo "تست اتصال به پورت SSH جدید روی localhost..."
sshd -t
if [[ $? -ne 0 ]]; then
    echo "خطا در پیکربندی SSH! تغییرات اعمال نمی‌شوند."
    exit 1
fi

# Open new SSH port in ufw temporarily
ufw allow $NEW_SSH_PORT/tcp

# Test SSH connection locally using netcat
nc -z -w5 127.0.0.1 $NEW_SSH_PORT
if [[ $? -ne 0 ]]; then
    echo "خطا: پورت SSH جدید باز نیست یا مشکل دارد!"
    echo "دسترسی از راه دور امن نیست، تغییر پورت انجام نشد."
    exit 1
fi

# --- Restart SSH safely ---
systemctl restart sshd
if [[ $? -ne 0 ]]; then
    echo "راه‌اندازی SSH با پورت جدید ناموفق بود. بررسی کنید!"
    exit 1
fi

echo "✅ SSH با پورت $NEW_SSH_PORT فعال شد."

# --- Setup UFW ---
ufw default deny incoming
ufw default allow outgoing
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
echo "✅  VPS Security Enterprise فعال شد!"
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
