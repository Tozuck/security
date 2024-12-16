#!/bin/bash

# Exit on any error
set -e

# Function to log and print messages
echo_info() {
  echo -e "\033[1;32m[INFO]\033[0m $1"
}
echo_error() {
  echo -e "\033[1;31m[ERROR]\033[0m $1"
  exit 1
}

# Check for root privileges
if [ "$EUID" -ne 0 ]; then
  echo_error "This script must be run as root. Use sudo."
fi

# Update system packages
echo_info "Updating package lists..."
apt-get update -y

# Install required packages
echo_info "Installing required packages..."
apt-get install -y curl socat git ufw fail2ban iptables || echo_error "Failed to install packages."

# Enable SYN Cookies to protect against SYN Flood attacks
echo_info "Enabling SYN Cookies..."
echo 1 > /proc/sys/net/ipv4/tcp_syncookies

mkdir /etc/iptables
touch /etc/iptables/rules.v4

# Configure UFW (firewall) to allow necessary ports only
echo_info "Configuring UFW to allow necessary ports..."
ufw default deny incoming
ufw default allow outgoing
ufw allow 22    # SSH
ufw allow 80    # HTTP
ufw allow 443   # HTTPS
ufw allow 62050 # VPN Port 1
ufw allow 62051 # VPN Port 2
ufw --force enable || echo_error "Failed to enable UFW"

# Set up iptables to prevent SYN Flood attacks and limit incoming connections
echo_info "Configuring iptables for SYN Flood protection..."
# Limit the rate of incoming SYN packets
iptables -A INPUT -p tcp --syn -m limit --limit 1/s --limit-burst 4 -j ACCEPT
iptables -A INPUT -p tcp --syn -j DROP

# Protect SSH port from brute-force attacks
echo_info "Protecting SSH from brute-force attacks..."
iptables -A INPUT -p tcp --dport 22 -m recent --set --name sshattack --rsource
iptables -A INPUT -p tcp --dport 22 -m recent --update --seconds 60 --hitcount 5 --name sshattack --rsource -j REJECT

# Limit the number of connections to your VPN ports (62050, 62051) to prevent abuse
echo_info "Limiting connections to VPN ports..."
iptables -A INPUT -p tcp --dport 62050 -m connlimit --connlimit-above 10 -j REJECT
iptables -A INPUT -p tcp --dport 62051 -m connlimit --connlimit-above 10 -j REJECT

# Set up fail2ban to protect against brute-force and DDoS attacks
echo_info "Setting up Fail2Ban..."
systemctl enable fail2ban
systemctl start fail2ban

# Create Fail2Ban configuration for SSH, HTTPS, and VPN ports
echo_info "Creating Fail2Ban filters for SSH, HTTPS, and VPN ports..."
cat <<EOL > /etc/fail2ban/jail.local
[DEFAULT]
bantime = 600
findtime = 600
maxretry = 5

[sshd]
enabled = true
port    = 22
logpath = /var/log/auth.log
maxretry = 5
bantime = 600

[https]
enabled = true
port    = 443
logpath = /var/log/apache2/access.log
maxretry = 5
bantime = 600

[vpn]
enabled = true
port    = 62050,62051
logpath = /var/log/xray/access.log
maxretry = 5
bantime = 600
EOL

# Restart Fail2Ban to apply the changes
systemctl restart fail2ban

# Save iptables rules to make them persistent
mkdir /etc/iptables
touch /etc/iptables/rules.v4
echo_info "Saving iptables rules..."
iptables-save > /etc/iptables/rules.v4

# Final system check
echo_info "System setup complete! Your server is now more secure against DDoS and SYN Flood attacks."

