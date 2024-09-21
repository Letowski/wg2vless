#!/bin/bash
if [ "$EUID" -ne 0 ]; then
  echo "Пожалуйста, запустите скрипт с правами root."
  exit 1
fi

# Получаем данные exit node
read -p "Введите IP exit node: " IP_EXIT
echo "IP_EXIT=$IP_EXIT" >> info.txt
read -p "Введите логин для exit node: " EXIT_USER
echo "EXIT_USER=$EXIT_USER" >> info.txt
read -s -p "Введите пароль для exit node: " EXIT_PASSWORD
echo "EXIT_PASSWORD=$EXIT_PASSWORD" >> info.txt
echo

# Устанавливаем пакеты на enter node
sudo apt-get update
sleep 1
sudo apt install -y sshpass git curl unzip wireguard wireguard-tools iptables iptables-persistent wget tcpdump qrencode fail2ban

# Устанавливаем XRAY
bash -c "$(curl -L https://github.com/XTLS/Xray-install/raw/main/install-release.sh)" @ install -u root

# Клонируем репозиторий
git clone https://github.com/Letowski/wg2vless.git
sleep 2
cd wg2vless

# Включаем проброс трафика
grep -qxF 'net.ipv4.ip_forward=1' /etc/sysctl.conf || echo 'net.ipv4.ip_forward=1' >> /etc/sysctl.conf
sysctl -p

## Устанавливаем wireguard

# Получаем внешний IP
export IP_ENTER=$(curl -s https://api.ipify.org)

# Генерация ключей для сервера и клиента
umask 077
wg genkey > server_private_key.txt
wg pubkey < server_private_key.txt > server_public_key.txt
wg genkey > client_private_key.txt
wg pubkey < client_private_key.txt > client_public_key.txt
export WG_SERVER_PRIVATE=$(cat server_private_key.txt)
export WG_SERVER_PUBLIC=$(cat server_public_key.txt)
export WG_CLIENT_PUBLIC=$(cat client_public_key.txt)
export WG_CLIENT_PRIVATE=$(cat client_private_key.txt)
echo "export WG_CLIENT_PRIVATE=$WG_CLIENT_PRIVATE" >> info.txt
sed -i -e "s|WG_SERVER_PRIVATE|$WG_SERVER_PRIVATE|g" enter_node/wg0.conf
sed -i -e "s|WG_CLIENT_PUBLIC|$WG_CLIENT_PUBLIC|g" enter_node/wg0.conf
cp enter_node/wg0.conf /etc/wireguard/wg0.conf
sed -i -e "s|WG_CLIENT_PRIVATE|$WG_CLIENT_PRIVATE|g" enter_node/wg_client.conf
sed -i -e "s|WG_SERVER_PUBLIC|$WG_SERVER_PUBLIC|g" enter_node/wg_client.conf
sed -i -e "s|IP_ENTER|$IP_ENTER|g" enter_node/wg_client.conf

# Запуск WireGuard
wg-quick up wg0
systemctl enable wg-quick@wg0.service

# Устанавливаем tun2socks
wget -O tun2socks-linux-amd64.zip https://github.com/xjasonlyu/tun2socks/releases/download/v2.5.2/tun2socks-linux-amd64.zip
unzip tun2socks-linux-amd64.zip
chmod +x ./tun2socks-linux-amd64
mv ./tun2socks-linux-amd64 /usr/local/bin/tun2socks
rm tun2socks-linux-amd64.zip
cp enter_node/tun2socks.service /etc/systemd/system/tun2socks.service
systemctl start tun2socks
systemctl enable tun2socks

# Настройка маршрутизации
iptables -A FORWARD -i wg0 -j ACCEPT
export INTERFACE=$(ip -o -4 route show to default | awk '{print $5}')
iptables -t nat -A POSTROUTING -o $INTERFACE -j MASQUERADE
iptables -t nat -A POSTROUTING -o tun0 -j MASQUERADE
netfilter-persistent save
chmod +x routes.sh
if [ -f "./routes.sh" ]; then
  chmod +x routes.sh
  ./routes.sh
else
  echo "Файл routes.sh не найден. Пропускаем этот шаг."
fi

# Поиск сайта для маскировки используя RealiTLScanner
wget https://github.com/XTLS/RealiTLScanner/releases/download/v0.2.1/RealiTLScanner-linux-64
chmod +x ./RealiTLScanner-linux-64
timeout 30s ./RealiTLScanner-linux-64 -addr $IP_EXIT -port 443 -timeout 5 -out sites.csv
export XRAY_SITE=$(tail -1 sites.csv | cut -d ',' -f3 | sed 's/^*\.\(.*\)/\1/')
rm sites.csv RealiTLScanner-linux-64
echo "export XRAY_SITE="$XRAY_SITE >> info.txt

# Генерация XRAY UUID и ключей
export XRAY_UUID=$(uuidgen)
echo "export XRAY_UUID=$XRAY_UUID" >> info.txt

# Генерация приватного и публичного ключа с использованием Xray
XRAY_KEYS=$(/usr/local/bin/xray x25519)
export XRAY_PRIVATE=$(echo "$XRAY_KEYS" | grep 'Private' | awk '{print $3}')
export XRAY_PUBLIC=$(echo "$XRAY_KEYS" | grep 'Public' | awk '{print $3}')
export XRAY_SHORT=$(echo $XRAY_UUID | sed 's/-//g' | cut -c1-16)

# Сохранение переменных XRAY в файл
echo "export XRAY_PRIVATE=$XRAY_PRIVATE" >> info.txt
echo "export XRAY_PUBLIC=$XRAY_PUBLIC" >> info.txt
echo "export XRAY_SHORT=$XRAY_SHORT" >> info.txt

# Вывод для проверки переменных окружения
echo "IP_EXIT $IP_EXIT"
echo "IP_ENTER $IP_ENTER"
echo "XRAY_SITE $XRAY_SITE"
echo "XRAY_UUID $XRAY_UUID"
echo "XRAY_PRIVATE $XRAY_PRIVATE"
echo "XRAY_PUBLIC $XRAY_PUBLIC"
echo "XRAY_SHORT $XRAY_SHORT"

# Настройка конфигурации Xray (enter node)
sed -i \
    -e "s/IP_EXIT/$IP_EXIT/g" \
    -e "s/XRAY_UUID/$XRAY_UUID/g" \
    -e "s/XRAY_SITE/$XRAY_SITE/g" \
    -e "s/XRAY_PUBLIC/$XRAY_PUBLIC/g" \
    -e "s/XRAY_SHORT/$XRAY_SHORT/g" \
    enter_node/config.json

# Копирование конфигурационного файла и перезапуск Xray
rm /usr/local/etc/xray/config.json
cp enter_node/config.json /usr/local/etc/xray/config.json
systemctl restart xray fail2ban
sleep 2

# Настройка exit node
sshpass -p "$EXIT_PASSWORD" ssh -o StrictHostKeyChecking=no $EXIT_USER@$IP_EXIT << EOF
sudo apt update
sleep 1
sudo apt install -y git curl uuid iptables wget tcpdump fail2ban
# enable port forwarding
grep -qxF 'net.ipv4.ip_forward=1' /etc/sysctl.conf || echo 'net.ipv4.ip_forward=1' >> /etc/sysctl.conf
sysctl -p
EOF
sshpass -p "$EXIT_PASSWORD" ssh -o StrictHostKeyChecking=no $EXIT_USER@$IP_EXIT 'bash -c "$(curl -L https://github.com/XTLS/Xray-install/raw/main/install-release.sh)" @ install -u root'
sed -i -e "s/XRAY_UUID/$XRAY_UUID/g" exit_node/config.json
sed -i -e "s/XRAY_SITE/$XRAY_SITE/g" exit_node/config.json
sed -i -e "s/XRAY_PRIVATE/$XRAY_PRIVATE/g" exit_node/config.json
sed -i -e "s/XRAY_SHORT/$XRAY_SHORT/g" exit_node/config.json
sshpass -p "$EXIT_PASSWORD" scp -o StrictHostKeyChecking=no "exit_node/config.json" "$EXIT_USER@$IP_EXIT:/usr/local/etc/xray/config.json"
sshpass -p "$EXIT_PASSWORD" ssh -o StrictHostKeyChecking=no $EXIT_USER@$IP_EXIT << EOF
systemctl restart xray fail2ban
sleep 2
systemctl status xray
EOF

rm -rf wg2vless
rm ./info.txt

# show WG client config
echo -e "${GREEN}\nHere is your client config file as a QR Code:\n${NC}"
qrencode -t ansiutf8 -l L <"enter_node/wg_client.conf"
echo ""

echo -e "${GREEN}Your client config file is in enter_node/wg_client.conf"

if [ "$(curl -s -x socks5h://127.0.0.1:20170 eth0.me 2>/dev/null)" = "$IP_EXIT" ]; then
  echo "TEST VPN - ON"
else
  echo "TEST VPN - OFF"
fi


echo "Скрипт завершен."
