# 🚀 FNMPW Toolkit

<div align="center">

![Fedora](https://img.shields.io/badge/Fedora-294172?style=for-the-badge&logo=fedora&logoColor=white)
![Nginx](https://img.shields.io/badge/Nginx-009639?style=for-the-badge&logo=nginx&logoColor=white)
![MariaDB](https://img.shields.io/badge/MariaDB-003545?style=for-the-badge&logo=mariadb&logoColor=white)
![PHP](https://img.shields.io/badge/PHP-777BB4?style=for-the-badge&logo=php&logoColor=white)
![WordPress](https://img.shields.io/badge/WordPress-21759B?style=for-the-badge&logo=wordpress&logoColor=white)

</div>

## 📋 Overview

FNMPW Toolkit is a comprehensive automation suite for setting up and managing a complete web server stack on Fedora Linux. It provides an intuitive menu-driven interface to install, configure, and maintain all components of a modern web hosting environment.

1-PHP-FPM installer directly from the terminal
<pre><code id="command">
sudo bash -c "bash <(curl -s https://raw.githubusercontent.com/hrwoje/FNPW-Toolkit-Fedora-server-installation/refs/heads/main/1-php.sh)"
</code></pre>

2- Mysql installer directly from the terminal
<pre><code id="command">
sudo bash -c "bash <(curl -s https://raw.githubusercontent.com/hrwoje/FNPW-Toolkit-Fedora-server-installation/refs/heads/main/2-mysql.sh)"
</code></pre>

3- Nginx installer directly from the terminal
<pre><code id="command">
sudo bash -c "bash <(curl -s https://raw.githubusercontent.com/hrwoje/FNPW-Toolkit-Fedora-server-installation/refs/heads/main/3-nginx.sh)"
</code></pre>

4- Wordpress installer directly from the terminal
<pre><code id="command">
sudo bash -c "bash <(curl -s https://raw.githubusercontent.com/hrwoje/FNPW-Toolkit-Fedora-server-installation/refs/heads/main/4-wordpress.sh)"
</code></pre>

5- Nginx serverblocks installer directly from the terminal
<pre><code id="command">
sudo bash -c "bash <(curl -s https://raw.githubusercontent.com/hrwoje/FNPW-Toolkit-Fedora-server-installation/refs/heads/main/5-nginx-serverblocks.sh)"
</code></pre>

6- Multipress installer directly from the terminal
<pre><code id="command">
sudo bash -c "bash <(curl -s https://raw.githubusercontent.com/hrwoje/FNPW-Toolkit-Fedora-server-installation/refs/heads/main/6-multipress.sh)"
</code></pre>

7- Security installer directly from the terminal
<pre><code id="command">
sudo bash -c "bash <(curl -s https://raw.githubusercontent.com/hrwoje/FNPW-Toolkit-Fedora-server-installation/refs/heads/main/7-security.sh)"
</code></pre>

8- SSL installer directly from the terminal
<pre><code id="command">
sudo bash -c "bash <(curl -s https://raw.githubusercontent.com/hrwoje/FNPW-Toolkit-Fedora-server-installation/refs/heads/main/8-ssl.sh)"
</code></pre>

9- Extra installer directly from the terminal
<pre><code id="command">
sudo bash -c "bash <(curl -s https://raw.githubusercontent.com/hrwoje/FNPW-Toolkit-Fedora-server-installation/refs/heads/main/9-extra.sh)"
</code></pre>

Fix services installer directly from the terminal
<pre><code id="command">
sudo bash -c "bash <(curl -s https://raw.githubusercontent.com/hrwoje/FNPW-Toolkit-Fedora-server-installation/refs/heads/main/fix_services.sh)"
</code></pre>


## 🛠️ Components

The toolkit consists of the following modules:

### 1. 🐘 PHP Manager (`1-php.sh`)
- PHP installation with WordPress-optimized extensions
- Version management and switching
- Configuration optimization
- PHP-FPM service management
- Memory and execution time settings

### 2. 🗄️ MySQL Manager (`2-mysql.sh`)
- MariaDB installation and configuration
- Database health monitoring
- WordPress database creation
- Service management
- Security hardening

### 3. 🌐 Nginx Manager (`3-nginx.sh`)
- Nginx web server installation
- Performance optimization
- Security configurations
- SSL/TLS setup
- Virtual host management

### 4. 📝 WordPress Manager (`4-wordpress.sh`)
- WordPress core installation
- Theme and plugin management
- Security hardening
- Performance optimization
- Backup and restore functionality

### 5. 🔧 Nginx Server Blocks (`5-nginx-serverblocks.sh`)
- Virtual host configuration
- Domain management
- SSL certificate integration
- Security headers
- Performance tuning

### 6. 🌍 WordPress Multisite (`6-multipress.sh`)
- Multisite network setup
- Domain mapping
- Network-wide settings
- User management
- Plugin and theme management

### 7. 🔒 Security Manager (`7-security.sh`)
- Firewall configuration
- ModSecurity setup
- SSL/TLS hardening
- Security headers
- Access control

### 8. 🔐 SSL Manager (`8-ssl.sh`)
- Let's Encrypt integration
- Certificate management
- Auto-renewal setup
- SSL configuration
- Security best practices

### 9. ⚡ Extra Features (`9-extra.sh`)
- Performance optimization
- Caching setup
- Compression configuration
- Monitoring tools
- Maintenance utilities

## 🚀 Getting Started

1. Clone the repository:
```bash
git clone https://github.com/yourusername/fnmpw-toolkit.git
cd fnmpw-toolkit
```

2. Make the installer executable:
```bash
chmod +x installer.sh
```

3. Run the installer:
```bash
sudo ./installer.sh
```

## 📋 Requirements

- Fedora Linux (latest version recommended)
- Root or sudo privileges
- Internet connection
- Minimum 2GB RAM
- 20GB free disk space

## 🔧 Usage

The toolkit provides an interactive menu interface. Simply run `installer.sh` and follow the on-screen prompts to:

1. Install individual components
2. Configure settings
3. Manage services
4. Monitor system health
5. Perform maintenance tasks

## 🛡️ Security Features

- Automatic security hardening
- SSL/TLS configuration
- Firewall management
- ModSecurity integration
- Regular security updates

## 📈 Performance Optimization

- Nginx optimization
- PHP-FPM tuning
- MySQL/MariaDB optimization
- Caching configuration
- Compression settings

## 🤝 Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

## 📝 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## 👥 Authors

- **Hrwoje Dabo** - *Initial work*

## 🙏 Acknowledgments

- Fedora Project
- Nginx Team
- MariaDB Foundation
- PHP Team
- WordPress Community

---

<div align="center">
Made with ❤️ by Hrwoje Dabo
</div> 
