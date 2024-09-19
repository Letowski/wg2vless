# 2 steps nextgen vpn

## Requirements
2 debian 12 (minimal) instances (1 core, 400+mb ram, 3+gb storage, unlimited traffic)

## Sever one (exit node):
### 1) prepare system:
    apt update
    apt install -y git curl uuid
    git clone https://github.com/Letowski/wg2vless.git
    cd wg2vless
    touch info.txt
### 2) install golang
    wget https://go.dev/dl/go1.22.5.linux-amd64.tar.gz
    tar -xvf go1.22.5.linux-amd64.tar.gz -C /usr/local
    echo "export GOROOT=/usr/local/go" >> ~/.bashrc
    echo "export GOPATH=$HOME/go" >> ~/.bashrc
    echo "export PATH=$GOPATH/bin:$GOROOT/bin:$PATH" >> ~/.bashrc
    source ~/.bashrc
    ln -s /usr/local/go/bin/go /bin/go
    go version
### 3) install RealiTLScanner and set XRAY_SITE
    git clone https://github.com/XTLS/RealiTLScanner.git
    cd RealiTLScanner/
    go build
    export IP_EXIT=$(curl ipinfo.io/ip)
    timeout 30s ./RealiTLScanner -addr $IP_EXIT -port 443 -timeout 5 -out sites.csv
    export XRAY_SITE=$(tail -1 sites.csv | cut -d ',' -f3)
    rm sites.csv
    cd ..
    echo "export IP_EXIT="$IP_EXIT >> info.txt
    echo "export XRAY_SITE="$XRAY_SITE >> info.txt
### 4) generate uuid:
    export XRAY_UUID=$(uuid -v 4)
    echo "export XRAY_UUID="$XRAY_UUID >> info.txt
### 5) install xray
    bash -c "$(curl -L https://github.com/XTLS/Xray-install/raw/main/install-release.sh)" @ install -u root
    timeout 5s systemctl status xray
### 6) generate keys
    export XRAY_KEYS=$(/usr/local/bin/xray x25519)
    export XRAY_PRIVATE=${XRAY_KEYS:13:43}
    export XRAY_PUBLIC=${XRAY_KEYS:69:43}
    export XRAY_SHORT=${XRAY_UUID:0:8}${XRAY_UUID:0:8}
    echo "export XRAY_PRIVATE="$XRAY_PRIVATE >> info.txt
    echo "export XRAY_PUBLIC="$XRAY_PUBLIC >> info.txt
    echo "export XRAY_SHORT="$XRAY_SHORT >> info.txt
### 7) check envs
    echo $IP_EXIT
    echo $XRAY_SITE
    echo $XRAY_UUID
    echo $XRAY_PRIVATE
    echo $XRAY_PUBLIC
    echo $XRAY_SHORT
### 8) configure xray
    rm /usr/local/etc/xray/config.json
    sed -i -e "s/XRAY_UUID/$XRAY_UUID/g" exit_node/config.json
    sed -i -e "s/XRAY_SITE/$XRAY_SITE/g" exit_node/config.json
    sed -i -e "s/XRAY_PRIVATE/$XRAY_PRIVATE/g" exit_node/config.json
    sed -i -e "s/XRAY_SHORT/$XRAY_SHORT/g" exit_node/config.json
    cp exit_node/config.json /usr/local/etc/xray/config.json
    systemctl restart xray
    timeout 5s systemctl status xray
### 9) node is ready
    cat info.txt

## Server two (enter node):
### 1) prepare system:
    apt update
    apt -y install git curl unzip wireguard iptables iptables-persistent
    git clone https://github.com/Letowski/wg2vless.git
    cd wg2vless
    touch info.txt
### 2) set envs
    copy console output of last command (cat info.txt) from exit_node
    and past (and execute) it in the console of ented_node
### 3) install tun2socks:
    wget https://github.com/xjasonlyu/tun2socks/releases/download/v2.5.2/tun2socks-linux-amd64-v3.zip
    unzip tun2socks-linux-amd64-v3.zip
    chmod +x ./tun2socks-linux-amd64-v3
    mv ./tun2socks-linux-amd64-v3 /bin/tun2socks
    tun2socks --v
    rm tun2socks-linux-amd64-v3.zip
    echo "210 v2ray" >> /etc/iproute2/rt_tables
### 4) enable port forwarding:
    echo "net.ipv4.ip_forward=1" >> /etc/sysctl.conf
    sysctl -p
### 5) configure wireguard:
    export IP_ENTER=$(curl ipinfo.io/ip)
    echo "export IP_ENTER="$IP_ENTER >> info.txt
    umask 077
    wg genkey > server_private_key.txt
    wg pubkey < server_private_key.txt > server_public_key.txt
    wg genkey > client_private_key.txt
    wg pubkey < client_private_key.txt > client_public_key.txt
    export WG_SERVER_PRIVATE=$(cat server_private_key.txt)
    export WG_SERVER_PUBLIC=$(cat server_public_key.txt)
    export WG_CLIENT_PUBLIC=$(cat client_public_key.txt)
    export WG_CLIENT_PRIVATE=$(cat client_private_key.txt)
    echo "export WG_SERVER_PRIVATE="$WG_SERVER_PRIVATE >> info.txt
    echo "export WG_SERVER_PUBLIC="$WG_SERVER_PUBLIC >> info.txt
    echo "export WG_CLIENT_PUBLIC="$WG_CLIENT_PUBLIC >> info.txt
    echo "export WG_CLIENT_PRIVATE="$WG_CLIENT_PRIVATE >> info.txt
    sed -i -e "s/WG_SERVER_PRIVATE/$WG_SERVER_PRIVATE/g" enter_node/wg0.conf
    sed -i -e "s/WG_CLIENT_PUBLIC/$WG_CLIENT_PUBLIC/g" enter_node/wg0.conf
    cp enter_node/wg0.conf /etc/wireguard/wg0.conf
    sed -i -e "s/WG_CLIENT_PRIVATE/$WG_CLIENT_PRIVATE/g" enter_node/wg_client.conf
    sed -i -e "s/WG_SERVER_PUBLIC/$WG_SERVER_PUBLIC/g" enter_node/wg_client.conf
    sed -i -e "s/IP_ENTER/$IP_ENTER/g" enter_node/wg_client.conf
    wg-quick up wg0
### 5) install v2rayA:
    wget -qO - https://apt.v2raya.org/key/public-key.asc | tee /etc/apt/keyrings/v2raya.asc
    echo "deb [signed-by=/etc/apt/keyrings/v2raya.asc] https://apt.v2raya.org/ v2raya main" | tee /etc/apt/sources.list.d/v2raya.list
    apt update
    apt install -y v2raya v2ray
### 6) install xray
    bash -c "$(curl -L https://github.com/XTLS/Xray-install/raw/main/install-release.sh)" @ install -u root
    timeout 5s systemctl status xray
### 7) configure xray
    rm /usr/local/etc/xray/config.json
    sed -i -e "s/IP_EXIT/$IP_EXIT/g" enter_node/config.json
    sed -i -e "s/XRAY_UUID/$XRAY_UUID/g" enter_node/config.json
    sed -i -e "s/XRAY_SITE/$XRAY_SITE/g" enter_node/config.json
    sed -i -e "s/XRAY_PUBLIC/$XRAY_PUBLIC/g" enter_node/config.json
    sed -i -e "s/XRAY_SHORT/$XRAY_SHORT/g" enter_node/config.json
    cp enter_node/config.json /usr/local/etc/xray/config.json
    systemctl restart xray
    timeout 5s systemctl status xray
### 99) show client config
    cat enter_node/wg_client.conf


