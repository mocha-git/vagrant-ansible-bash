#!/bin/bash

# Mise à jour
apt-get update && apt-get upgrade -y

# Installations de base
apt-get install -y curl git software-properties-common openssh-server python3 python3-pip

# Installation Apache (sera configuré via Ansible ensuite)
apt-get install -y apache2

# Nettoyage
apt-get autoremove -y

echo "[+] Installing Node Exporter..."

NODE_EXPORTER_VERSION="1.8.1"
cd /tmp
wget https://github.com/prometheus/node_exporter/releases/download/v$NODE_EXPORTER_VERSION/node_exporter-$NODE_EXPORTER_VERSION.linux-amd64.tar.gz
tar xvf node_exporter-$NODE_EXPORTER_VERSION.linux-amd64.tar.gz
sudo mv node_exporter-$NODE_EXPORTER_VERSION.linux-amd64/node_exporter /usr/local/bin/

# Service systemd
sudo tee /etc/systemd/system/node_exporter.service > /dev/null <<EOF
[Unit]
Description=Node Exporter
After=network.target

[Service]
User=nobody
ExecStart=/usr/local/bin/node_exporter

[Install]
WantedBy=default.target
EOF

sudo systemctl daemon-reexec
sudo systemctl daemon-reload
sudo systemctl enable --now node_exporter