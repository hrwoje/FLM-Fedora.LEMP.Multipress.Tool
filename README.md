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


⚡ One-line Installation (Terminal Execution)
You can easily run the FLM Tool directly from your terminal using one of the following one-liner commands. Choose your preferred language version below:

🇬🇧 English Version:
<pre><code id="command">
sudo bash -c "bash <(curl -s https://raw.githubusercontent.com/hrwoje/FLM-Fedora.LEMP.Multipress.Tool/refs/heads/main/FLM%20tool%20Englisch.sh)"
</code></pre>
🇳🇱 Dutch Version:
<pre><code id="command">
sudo bash -c "bash <(curl -s https://raw.githubusercontent.com/hrwoje/FLM-Fedora.LEMP.Multipress.Tool/refs/heads/main/FLM%20tool%20Nederlands.sh)"
</code></pre>
These commands will automatically download and run the FLM Tool installation script for Fedora systems.
No need to clone or download anything manually — just copy, paste, and you're good to go!
<br>
✔️ Works out-of-the-box on Fedora Desktop<br>
✔️ Includes SELinux fixes, health checks, and Multipress (WordPress Multisite) management<br>
✔️ Perfect for setting up a local LEMP development server in seconds<br>


