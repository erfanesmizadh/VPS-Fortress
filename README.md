# VPS-Fortress

**VPS-Fortress** یک اسکریپت امنیتی پیشرفته برای سرورهای لینوکس است که امنیت SSH، فایروال و پورت‌های حساس شما را به سطح Enterprise ارتقا می‌دهد.

---

## ویژگی‌ها

- تغییر پورت SSH و غیرفعال کردن ورود root
- فعال‌سازی **ufw** با بلاک پیش‌فرض و باز کردن پورت‌های دلخواه
- **rate-limit** برای SSH و جلوگیری از حملات brute-force
- نصب و فعال‌سازی **fail2ban** برای بلاک کردن آی‌پی‌های مشکوک
- **ipset + iptables** برای بلاک سریع آی‌پی‌ها
- امکان اضافه کردن لیست آی‌پی‌های خطرناک (Cloudflare/CDN)
- مانیتورینگ زنده وضعیت ufw، fail2ban و آی‌پی‌های بلاک شده

---

## نصب و اجرا

برای اجرای اسکریپت کافیست یک دستور در سرور خود وارد کنید:

```bash
curl -O https://raw.githubusercontent.com/erfanesmizadh/VPS-Fortress/main/install.sh
chmod +x install.sh
sudo bash install.sh
