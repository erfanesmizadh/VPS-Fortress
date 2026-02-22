# VPS-Fortress

✅ **VPS Security Enterprise – محافظ سرور شما با SSH امن، UFW، Fail2ban و IP Blocking**  

VPS-Fortress یک اسکریپت Bash برای افزایش امنیت سرورهای لینوکسی است که شامل ویژگی‌های زیر می‌باشد:

- تغییر پورت SSH با پیش‌فرض امن `(Default 2222)`  
- غیرفعال کردن ورود root به SSH  
- فعال‌سازی **UFW** با قوانین پیش‌فرض  
- فعال‌سازی **Fail2ban** و جلوگیری از حملات Brute-force  
- افزودن IP های **Cloudflare/CDN** به لیست بلاک  
- پشتیبان‌گیری خودکار از فایل SSH قبل از اعمال تغییرات  
- قابلیت rollback خودکار در صورت بروز خطا در SSH  

---

## ⚡ نصب و اجرا

برای اجرای اسکریپت با یک دستور کافیست:

```bash
curl -O https://raw.githubusercontent.com/erfanesmizadh/VPS-Fortress/main/install.sh
chmod +x install.sh
sudo bash install.sh
