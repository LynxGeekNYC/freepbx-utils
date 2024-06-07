#!/bin/bash

# FreePBX installation script for Ubuntu with Fail2Ban

# Update and upgrade the system
sudo apt update && sudo apt -y upgrade

# Install necessary dependencies
sudo apt install -y wget build-essential apache2 mariadb-server mariadb-client \
    bison flex php php-cli php-curl php-gd php-mbstring php-mysql php-xml php-pear php-bcmath \
    libapache2-mod-php libncurses5-dev libssl-dev libmariadb-dev libmariadb-dev-compat \
    curl sox libtiff5-dev libjpeg62-turbo-dev libncursesw5-dev libxml2-dev libsqlite3-dev \
    libnewt-dev libjansson-dev libedit-dev uuid-dev libxslt1-dev pkg-config \
    subversion git unixodbc-dev uuid uuid-runtime fail2ban

# Enable and start MariaDB
sudo systemctl enable mariadb
sudo systemctl start mariadb

# Secure MariaDB installation
sudo mysql_secure_installation

# Install Node.js and NPM (required for FreePBX 15+)
curl -sL https://deb.nodesource.com/setup_14.x | sudo bash -
sudo apt install -y nodejs

# Download and install Asterisk
cd /usr/src
sudo wget http://downloads.asterisk.org/pub/telephony/asterisk/asterisk-18-current.tar.gz
sudo tar zxvf asterisk-18-current.tar.gz
cd asterisk-18.*/
sudo contrib/scripts/install_prereq install
sudo ./configure
sudo make menuselect
sudo make
sudo make install
sudo make samples
sudo make config
sudo ldconfig

# Create Asterisk user and set permissions
sudo groupadd asterisk
sudo useradd -r -d /var/lib/asterisk -g asterisk asterisk
sudo usermod -aG audio,dialout asterisk
sudo chown -R asterisk:asterisk /etc/asterisk
sudo chown -R asterisk:asterisk /var/{lib,log,spool}/asterisk
sudo chown -R asterisk:asterisk /usr/lib/asterisk
sudo chown -R asterisk:asterisk /var/www/

# Install FreePBX
cd /usr/src
sudo git clone https://github.com/FreePBX/freepbx.git
cd freepbx
sudo ./start_asterisk start
sudo ./install -n

# Configure Apache for FreePBX
sudo a2enmod rewrite
sudo a2enmod headers
sudo service apache2 restart

# Set permissions for FreePBX
sudo chown -R asterisk:asterisk /var/lib/asterisk
sudo chown -R asterisk:asterisk /var/spool/asterisk
sudo chown -R asterisk:asterisk /var/log/asterisk
sudo chown -R asterisk:asterisk /var/run/asterisk
sudo chown -R asterisk:asterisk /var/www/html

# Enable Apache and Asterisk to start on boot
sudo systemctl enable apache2
sudo systemctl enable asterisk

# Restart Apache and Asterisk
sudo systemctl restart apache2
sudo systemctl restart asterisk

# Configure Fail2Ban for FreePBX
sudo cp /etc/fail2ban/jail.conf /etc/fail2ban/jail.local

# Add FreePBX specific jails
sudo tee -a /etc/fail2ban/jail.local <<EOF

[asterisk-iptables]
enabled  = true
filter   = asterisk
action   = iptables-allports[name=ASTERISK, protocol=all]
logpath  = /var/log/asterisk/messages
maxretry = 3
bantime = 86400 ; 1 day

[apache-auth]
enabled  = true
filter   = apache-auth
action   = iptables-multiport[name=apache-auth, port="http,https"]
logpath  = /var/log/apache2/*error.log
maxretry = 3
bantime = 86400 ; 1 day
EOF

# Create Asterisk filter
sudo tee /etc/fail2ban/filter.d/asterisk.conf <<EOF
[Definition]
failregex = NOTICE.* .*: Registration from '.*' failed for '<HOST>' - Wrong password
            NOTICE.* .*: Registration from '.*' failed for '<HOST>' - No matching peer found
            NOTICE.* .*: Registration from '.*' failed for '<HOST>' - Username/auth name mismatch
            NOTICE.* .*: Registration from '.*' failed for '<HOST>' - Device does not match ACL
            NOTICE.* .*: Registration from '.*' failed for '<HOST>' - Not a local domain
            NOTICE.* .*: Registration from '.*' failed for '<HOST>' - No matching endpoint found
            SECURITY.* SecurityEvent=".*" <HOST>
            NOTICE.* <HOST> failed to authenticate
EOF

# Restart Fail2Ban to apply changes
sudo systemctl restart fail2ban

echo "FreePBX installation with Fail2Ban is complete. Please navigate to your server's IP address to complete the FreePBX setup through the web interface."
