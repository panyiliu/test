#!/bin/bash
set -euo pipefail
set -x  # 开启调试模式，显示执行过程

LOG_FILE="/var/log/setup_naive.log"
exec > >(tee -a $LOG_FILE) 2>&1  # 将日志写入文件
FLAG_DIR="/var/lib/setup_naive_flags"
mkdir -p $FLAG_DIR

echo "Starting naive setup script at $(date)"

### 函数定义区 ###

install_go() {
    if ! command -v go &>/dev/null; then
        echo "Installing Go..."
        wget https://go.dev/dl/go1.22.1.linux-amd64.tar.gz
        tar -zxvf go1.22.1.linux-amd64.tar.gz -C /usr/local/
        echo "export PATH=\$PATH:/usr/local/go/bin" >> /etc/profile
        source /etc/profile
        go version
        touch $FLAG_DIR/go_installed
    else
        echo "Go is already installed."
    fi
}

install_caddy() {
    if ! command -v caddy &>/dev/null; then
        echo "Installing Caddy with forwardproxy module..."
        go install github.com/caddyserver/xcaddy/cmd/xcaddy@latest
        ~/go/bin/xcaddy build --with github.com/caddyserver/forwardproxy@caddy2=github.com/klzgrad/forwardproxy@naive
        cp caddy /usr/bin/
        setcap cap_net_bind_service=+ep /usr/bin/caddy
        caddy version
        touch $FLAG_DIR/caddy_installed
    else
        echo "Caddy is already installed."
    fi
}

setup_systemd_service() {
    if [ ! -f /etc/systemd/system/naive.service ]; then
        echo "Creating systemd service for Caddy..."
        cat <<EOF > /etc/systemd/system/naive.service
[Unit]
Description=Caddy
Documentation=https://caddyserver.com/docs/
After=network.target network-online.target
Requires=network-online.target

[Service]
Type=notify
User=root
Group=root
ExecStart=/usr/bin/caddy run --environ --config /etc/caddy/Caddyfile
ExecReload=/usr/bin/caddy reload --config /etc/caddy/Caddyfile
TimeoutStopSec=5s
LimitNOFILE=1048576
LimitNPROC=512
PrivateTmp=true
ProtectSystem=full
AmbientCapabilities=CAP_NET_BIND_SERVICE

[Install]
WantedBy=multi-user.target
EOF
        systemctl daemon-reload
        systemctl enable naive.service
        touch $FLAG_DIR/service_configured
    else
        echo "Systemd service is already configured."
    fi
}

create_caddyfile() {
    if [ ! -f /etc/caddy/Caddyfile ]; then
        echo "Creating default Caddyfile..."
        mkdir -p /etc/caddy
        cat <<EOF > /etc/caddy/Caddyfile
:443 {
    tls internal
    forwardproxy {
        basicauth user password
    }
    file_server {
        root /var/www
    }
}
EOF
        mkdir -p /var/www
        echo "Hello there" > /var/www/index.html
        touch $FLAG_DIR/caddyfile_created
    else
        echo "Caddyfile already exists."
    fi
}

start_caddy_service() {
    echo "Starting Caddy service..."
    systemctl start naive.service
    systemctl status naive.service
}

cleanup() {
    echo "Cleaning up previous installations..."
    rm -rf /usr/local/go /usr/bin/caddy /etc/caddy /etc/systemd/system/naive.service
    rm -rf $FLAG_DIR
    systemctl daemon-reload
    echo "Cleanup completed."
}

### 主逻辑 ###

case "${1:-}" in
    install)
        install_go
        install_caddy
        create_caddyfile
        setup_systemd_service
        start_caddy_service
        ;;
    clean)
        cleanup
        ;;
    *)
        echo "Usage: $0 {install|clean}"
        exit 1
        ;;
esac

echo "Setup script completed successfully at $(date)"
