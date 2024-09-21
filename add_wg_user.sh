#!/bin/bash

# Script to add a new WireGuard user to an existing configuration

# Check if the script is run as root
if [ "$EUID" -ne 0 ]; then
  echo "Please run the script as root."
  exit 1
fi

WG_CONFIG="/etc/wireguard/wg0.conf"
CLIENTS_DIR="/etc/wireguard/clients"

# Check if the server configuration file exists
if [ ! -f "$WG_CONFIG" ]; then
  echo "Configuration file $WG_CONFIG not found."
  exit 1
fi

# Create the directory for client configurations if it doesn't exist
if [ ! -d "$CLIENTS_DIR" ]; then
  mkdir -p "$CLIENTS_DIR"
  chmod 700 "$CLIENTS_DIR"
fi

# Prompt for the new user's name
read -p "Enter the name of the new user: " CLIENT_NAME

# Check if a user with the same name already exists
if [ -f "$CLIENTS_DIR/$CLIENT_NAME.conf" ]; then
  echo "A user with the name $CLIENT_NAME already exists."
  exit 1
fi

# Generate keys for the client
umask 077
CLIENT_PRIVATE_KEY=$(wg genkey)
CLIENT_PUBLIC_KEY=$(echo "$CLIENT_PRIVATE_KEY" | wg pubkey)
PRESHARED_KEY=$(wg genpsk)

# Get the server's public key from the configuration file
SERVER_PRIVATE_KEY=$(grep 'PrivateKey' $WG_CONFIG | head -n1 | awk '{print $NF}')
SERVER_PUBLIC_KEY=$(echo "$SERVER_PRIVATE_KEY" | wg pubkey)

# Get the server's external IP address and port
SERVER_ENDPOINT=$(grep 'Endpoint' $WG_CONFIG | head -n1 | awk '{print $NF}')
if [ -z "$SERVER_ENDPOINT" ]; then
  # If Endpoint is not set, use the server's external IP address
  SERVER_IP=$(curl -s https://api.ipify.org)
  SERVER_PORT=$(grep 'ListenPort' $WG_CONFIG | awk '{print $NF}')
  SERVER_ENDPOINT="$SERVER_IP:$SERVER_PORT"
fi

# Find an available IP address for the client
SERVER_SUBNET=$(grep 'Address' $WG_CONFIG | head -n1 | awk '{print $NF}' | cut -d',' -f1)
if [ -z "$SERVER_SUBNET" ]; then
  echo "Unable to determine the server's subnet from the configuration."
  exit 1
fi

IFS='/' read -r SUBNET_IP SUBNET_CIDR <<< "$SERVER_SUBNET"
IFS='.' read -r IP1 IP2 IP3 IP4 <<< "$SUBNET_IP"
CLIENT_IP_PREFIX="$IP1.$IP2.$IP3"
USED_IPS=$(grep 'AllowedIPs' $WG_CONFIG | awk '{print $NF}' | cut -d'/' -f1 | cut -d'.' -f4)
LAST_IP=$(echo "$USED_IPS" | sort -n | tail -n1)

if [ -z "$LAST_IP" ]; then
  CLIENT_IP_SUFFIX=2
else
  CLIENT_IP_SUFFIX=$((LAST_IP + 1))
fi

if [ "$CLIENT_IP_SUFFIX" -ge 254 ]; then
  echo "Maximum number of clients in the subnet reached."
  exit 1
fi

CLIENT_IP="$CLIENT_IP_PREFIX.$CLIENT_IP_SUFFIX"

# Add the client to the server configuration
echo -e "\n[Peer]
# $CLIENT_NAME
PublicKey = $CLIENT_PUBLIC_KEY
PresharedKey = $PRESHARED_KEY
AllowedIPs = $CLIENT_IP/32" >> $WG_CONFIG

# Create the client's configuration file
cat > "$CLIENTS_DIR/$CLIENT_NAME.conf" << EOF
[Interface]
PrivateKey = $CLIENT_PRIVATE_KEY
Address = $CLIENT_IP/24
DNS = 94.140.14.14, 94.140.15.15

[Peer]
PublicKey = $SERVER_PUBLIC_KEY
PresharedKey = $PRESHARED_KEY
Endpoint = $SERVER_ENDPOINT
AllowedIPs = 0.0.0.0/0, ::/0
EOF

# Restart WireGuard to apply changes
wg syncconf wg0 <(wg-quick strip wg0)

# Display the configuration as a QR code (if qrencode is installed)
if command -v qrencode &> /dev/null; then
  echo -e "\nClient configuration as a QR code:"
  qrencode -t ansiutf8 < "$CLIENTS_DIR/$CLIENT_NAME.conf"
fi

echo -e "\nUser $CLIENT_NAME added successfully."
echo "Client configuration file: $CLIENTS_DIR/$CLIENT_NAME.conf"
