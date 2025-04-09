🛠️ FLM Tool – Fedora LEMP Multipress Installation Tool
FLM Tool (Fedora LEMP Multipress) is a simple, automated BASH script designed specifically for Fedora-based systems. It provides a fast and hassle-free way to set up a full LEMP stack (Linux, Nginx, MariaDB, PHP) with optional WordPress Multisite (Multipress) support, including smart health checks and SELinux compatibility fixes.

🔍 What it does:
Installs and configures a complete LEMP stack on Fedora distributions

Enables or disables WordPress Multisite (Multipress) with a single toggle

Fixes common cookie errors when running multiple sites under WordPress Multisite

Handles SELinux context issues out-of-the-box

Includes a health check module to monitor and manage PHP services and server status

Ensures the server starts automatically on reboot

Designed for local development use cases (perfect for WordPress developers)

✅ Why this tool?
Most WordPress LEMP tools are aimed at Debian/Ubuntu systems, leaving Fedora users without a streamlined option. I created and tested this tool on Fedora 42 Desktop, ensuring it works reliably in a typical developer environment.

🚀 How to use
Just run the script in your terminal. It's easy, guided, and doesn't require deep Linux knowledge. After a reboot, your local server will be running automatically. If needed, re-run the script for quick access to the built-in health checker and management features.


sudo bash -c "bash <(curl -s https://raw.githubusercontent.com/hrwoje/FLM-Fedora.LEMP.Multipress.Tool/refs/heads/main/FLM%20tool%20Englisch.sh)"

