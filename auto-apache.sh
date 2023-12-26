#!/bin/bash

# Function to check if the script is run as root
checkRootPrivileges() {
  if [[ $EUID -ne 0 ]]; then
    echo "This script must be run as root."
    exit 1
  fi
}

# Function to configure Apache for logging
configureLogging() {
  # Apache log directory
  APACHE_LOG_DIR="/var/log/httpd"

  # Create log directory if not exists
  mkdir -p "$APACHE_LOG_DIR"

  # Configure log formats and files
  echo 'LogFormat "%h %l %u %t \"%r\" %>s %b \"%{Referer}i\" \"%{User-Agent}i\"" combined' >> /etc/httpd/conf/httpd.conf
  echo 'LogFormat "%h %l %u %t \"%r\" %>s %b" common' >> /etc/httpd/conf/httpd.conf
  echo "CustomLog $APACHE_LOG_DIR/access_log combined" >> /etc/httpd/conf/httpd.conf
  echo "ErrorLog $APACHE_LOG_DIR/error_log" >> /etc/httpd/conf/httpd.conf
}

# Function to set up server status output
setupServerStatus() {
  echo "ExtendedStatus On" >> /etc/httpd/conf/httpd.conf
  echo "<Location /server-status>" >> /etc/httpd/conf/httpd.conf
  echo "  SetHandler server-status" >> /etc/httpd/conf/httpd.conf
  echo "  Require local" >> /etc/httpd/conf/httpd.conf
  echo "</Location>" >> /etc/httpd/conf/httpd.conf
}

# Function to configure advanced options
configureAdvancedOptions() {

# Backup existing httpd.conf
mv /etc/httpd/conf/httpd.conf /etc/httpd/conf/httpd.conf.bak

# Create a new httpd.conf
cat <<EOL > /etc/httpd/conf/httpd.conf
ServerRoot "/etc/httpd"
ServerName localhost
Listen 80

LoadModule mpm_prefork_module modules/mod_mpm_prefork.so
LoadModule authn_file_module modules/mod_authn_file.so
LoadModule authn_core_module modules/mod_authn_core.so
LoadModule authz_host_module modules/mod_authz_host.so
LoadModule authz_user_module modules/mod_authz_user.so
LoadModule authz_core_module modules/mod_authz_core.so
LoadModule access_compat_module modules/mod_access_compat.so
LoadModule auth_basic_module modules/mod_auth_basic.so
LoadModule reqtimeout_module modules/mod_reqtimeout.so
LoadModule include_module modules/mod_include.so
LoadModule filter_module modules/mod_filter.so
LoadModule mime_module modules/mod_mime.so
LoadModule log_config_module modules/mod_log_config.so
LoadModule env_module modules/mod_env.so
LoadModule setenvif_module modules/mod_setenvif.so
LoadModule version_module modules/mod_version.so
LoadModule unixd_module modules/mod_unixd.so
LoadModule status_module modules/mod_status.so
LoadModule dir_module modules/mod_dir.so
LoadModule php_module modules/libphp.so
AddHandler php-script .php
User http
Group http

DocumentRoot "/srv/http/example.com"
<Directory "/srv/http/example.com">
    Options Indexes FollowSymLinks MultiViews
    AllowOverride all
    Order Deny,Allow
    Allow from all
</Directory>

DirectoryIndex index.php

<Files ".ht*">
    Require all denied
</Files>

ErrorLog "/var/log/httpd/error_log"
LogLevel warn

LogFormat "%h %l %u %t \"%r\" %>s %b" common
CustomLog "/var/log/httpd/access_log" common
EOL

echo "New httpd.conf created, and the previous httpd.conf has been backed up to httpd.conf.bak."

}

# Function to create demo HTML in root directory
createDemoHTML() {
  echo "<h1>You've set up your Apache successfully</h1>" > /srv/http/index.html
}

# Function to configure dynamic virtual host
configureDynamicVirtualHost() {
  read -p "Enter the main domain (e.g., yourdomain.com): " mainDomain

  # Apache sites-available and sites-enabled directories
  SITES_AVAILABLE="/etc/httpd/conf/extra"
  SITES_ENABLED="/etc/httpd/conf/sites-enabled"

  # Create directories if not exists
  mkdir -p "$SITES_AVAILABLE" "$SITES_ENABLED"

  # Create a template for dynamic virtual host
  cat <<EOL > "$SITES_AVAILABLE/dynamic-vhost-template.conf"
<VirtualHost *:8080>
    ServerAdmin webmaster@${mainDomain}
    DocumentRoot "/srv/http/${mainDomain}"
    ServerName ${mainDomain}
    ServerAlias *${mainDomain}
    VirtualDocumentRoot "/srv/http/%1"
    <Directory "/srv/http/${mainDomain}">
        Options Indexes FollowSymLinks
        AllowOverride All
        Require all granted
        DirectoryIndex index.php index.html index.htm
    </Directory>
</VirtualHost>
EOL

  echo "Dynamic virtual host template created."

  # Create a symbolic link to enable the site
  ln -s "$SITES_AVAILABLE/dynamic-vhost-template.conf" "$SITES_ENABLED/"

  echo "Dynamic virtual host enabled."
}

# Function to configure virtual host
configureVirtualHost() {
  read -e -p "Enter domain (e.g., example.com): " -i "example.com" domain
  read -e -p "Enter PHP version (e.g., 7.4): " -i "7.4" phpVersion

  # Check if PHP is installed
  if ! command -v "php$phpVersion" &> /dev/null; then
    echo "PHP version $phpVersion is not installed. Please install it and run the script again."
    exit 1
  fi

  # Create virtual host configuration
  cat <<EOL >> "/etc/httpd/conf/extra/$domain.conf"
<VirtualHost *:8080>
    ServerAdmin webmaster@$domain
    DocumentRoot "/srv/http/$domain"
    ServerName $domain
    ServerAlias www.$domain
    ErrorLog "/var/log/httpd/$domain-error_log"
    CustomLog "/var/log/httpd/$domain-access_log" common

    <Directory "/srv/http/$domain">
        Options Indexes FollowSymLinks
        AllowOverride All
        Require all granted
        DirectoryIndex index.php index.html index.htm
    </Directory>

    <FilesMatch \.php$>
        SetHandler "proxy:unix:/run/php-fpm/php-fpm.sock|fcgi://localhost/"
    </FilesMatch>
</VirtualHost>
EOL

  # Create document root directory
  mkdir -p "/srv/http/$domain"
  echo "<?php phpinfo(); ?>" > "/srv/http/$domain/index.php"
}

# Main function to install Apache with advanced configurations
main() {
  checkRootPrivileges

  if [ "$1" == "-install" ]; then
    # Install Apache
    pacman -S --noconfirm apache

    # Enable modules
    echo "Enabling modules..."
    echo "LoadModule status_module modules/mod_status.so" >> /etc/httpd/conf/httpd.conf

    # Configure Apache
    configureLogging
    setupServerStatus
    configureAdvancedOptions
    createDemoHTML

    # Restart Apache
    systemctl restart httpd

    # Configure dynamic virtual host
    configureDynamicVirtualHost

    # Configure virtual host
    configureVirtualHost

    echo "Apache installed and configured successfully."
  elif [ "$1" == "-remove" ]; then
    # Remove Apache
    pacman -Rns --noconfirm apache

    # Remove demo HTML file
    rm -f /srv/http/index.html

    echo "Apache removed completely."
  else
    echo "Invalid argument. Usage: $0 [-install | -remove]"
    exit 1
  fi
}

# Invoke main function with provided argument
main "$@"
