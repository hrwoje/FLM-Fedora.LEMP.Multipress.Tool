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

sudo bash -c "bash <(curl -s https://raw.githubusercontent.com/hrwoje/FLM-Fedora.LEMP.Multipress.Tool/refs/heads/main/FLM%20tool%20Englisch.sh)"

🇳🇱 Dutch Version:

sudo bash -c "bash <(curl -s https://raw.githubusercontent.com/hrwoje/FLM-Fedora.LEMP.Multipress.Tool/refs/heads/main/FLM%20tool%20Nederlands.sh)"

These commands will automatically download and run the FLM Tool installation script for Fedora systems.
No need to clone or download anything manually — just copy, paste, and you're good to go!

✔️ Works out-of-the-box on Fedora Desktop
✔️ Includes SELinux fixes, health checks, and Multipress (WordPress Multisite) management
✔️ Perfect for setting up a local LEMP development server in seconds


<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <title>FLM Tool Installer</title>
  <style>
    body {
      font-family: sans-serif;
      background: #f8f8f8;
      padding: 2rem;
    }
    .button {
      background-color: #2d89ef;
      color: white;
      border: none;
      padding: 12px 20px;
      font-size: 16px;
      border-radius: 8px;
      cursor: pointer;
      margin-top: 1rem;
    }
    .button:hover {
      background-color: #1b65c2;
    }
    .message {
      margin-top: 1rem;
      color: green;
    }
  </style>
</head>
<body>

<h2>🛠️ Install FLM Tool (English Version)</h2>
<p>Click the button below to copy the installation command. Then paste it into your terminal.</p>

<pre><code id="command">
sudo bash -c "bash &lt;(curl -s https://raw.githubusercontent.com/hrwoje/FLM-Fedora.LEMP.Multipress.Tool/refs/heads/main/FLM%20tool%20Englisch.sh)"
</code></pre>

<button class="button" onclick="copyCommand()">📋 Copy to Clipboard</button>
<p id="message" class="message"></p>

<script>
  function copyCommand() {
    const commandText = document.getElementById("command").innerText;
    navigator.clipboard.writeText(commandText).then(() => {
      document.getElementById("message").textContent = "✅ Command copied! Open your terminal and paste it.";
    });
  }
</script>

</body>
</html>
