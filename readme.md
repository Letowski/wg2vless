## Envs:
### before installation:
    IP_ENTER=<ip of enter node>
    IP_EXIT=<ip of exit node>
### during installation:
    XRAY_SITE=<pseudo-hostname for xray>
    XRAY_UUID=<unique uuid for xray>
    XRAY_PRIVATE
    XRAY_SHORT

## Sever one (exit node):
### 1) install debian 12:
    apt update
    apt -y install git
    git clone https://github.com/Letowski/wg2vless.git
    cd wg2vless
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
    apt install -y git curl
    git clone https://github.com/XTLS/RealiTLScanner.git
    cd RealiTLScanner/
    go build
    export IP_EXIT=$(curl ipinfo.io/ip)
    ./RealiTLScanner -addr $IP_EXIT -port 443 -timeout 30
    export XRAY_SITE=<site for xray>
### 4) generate uuid:
    apt install uuid -y
    export XRAY_UUID=$(uuid -v 4)
    echo $XRAY_UUID
### 5) install xray
    bash -c "$(curl -L https://github.com/XTLS/Xray-install/raw/main/install-release.sh)" @ install -u root
    systemctl status xray
### 6) configure xray
    rm /usr/local/etc/xray/config.json
    sed -i -e "s/XRAY_UUID/$XRAY_UUID/g" exit_node/config.json
    sed -i -e "s/XRAY_SITE/$XRAY_SITE/g" exit_node/config.json
    sed -i -e "s/XRAY_PRIVATE/$XRAY_PRIVATE/g" exit_node/config.json
    sed -i -e "s/XRAY_SHORT/$XRAY_SHORT/g" exit_node/config.json
    cp exit_node/config.json /usr/local/etc/xray/config.json
    systemctl restart xray
    systemctl status xray

## Server two (enter node):
### 1) install debian 12:
    apt update
    apt -y install git 
### 2) install tun2socks:
    wget https://github.com/xjasonlyu/tun2socks/releases/download/v2.5.2/tun2socks-linux-amd64-v3.zip
    apt -y install unzip
    unzip tun2socks-linux-amd64-v3.zip
    chmod +x ./tun2socks-linux-amd64-v3
    mv ./tun2socks-linux-amd64-v3 /bin/tun2socks
    tun2socks --v
    rm tun2socks-linux-amd64-v3.zip
### 3) enable port forwarding:
    echo "net.ipv4.ip_forward=1" >> /etc/sysctl.conf
    sysctl -p
### 4) install wireguard:
    apt -y install wireguard
### 5) install v2rayA:
    wget -qO - https://apt.v2raya.org/key/public-key.asc | tee /etc/apt/keyrings/v2raya.asc
    echo "deb [signed-by=/etc/apt/keyrings/v2raya.asc] https://apt.v2raya.org/ v2raya main" | tee /etc/apt/sources.list.d/v2raya.list
    apt update
    apt install -y v2raya v2ray
### 6) install iptables:
    apt install -y iptables
    apt install -y iptables-persistent


