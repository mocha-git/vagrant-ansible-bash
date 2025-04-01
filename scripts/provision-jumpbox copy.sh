#!/bin/bash

# === Journalisation globale ===
exec > >(tee -a /var/log/provision.log) 2>&1

# Stop on error (pour les parties critiques uniquement)
set -e

echo "==== [1/7] Installation d'Ansible & outils utiles ===="
sudo apt update -y
sudo apt install -y ansible sshpass python3-pip python3-venv git curl wget unzip jq software-properties-common apt-transport-https gnupg

echo "==== [2/7] Préparation SSH ===="
SSH_DIR="/home/vagrant/.ssh"
mkdir -p "$SSH_DIR"
chown vagrant:vagrant "$SSH_DIR"
chmod 700 "$SSH_DIR"

mv /home/vagrant/id_rsa "$SSH_DIR/id_rsa"
chmod 600 "$SSH_DIR/id_rsa"
chown vagrant:vagrant "$SSH_DIR/id_rsa"

cat /home/vagrant/id_rsa.pub >> "$SSH_DIR/authorized_keys"
chmod 600 "$SSH_DIR/authorized_keys"
chown vagrant:vagrant "$SSH_DIR/authorized_keys"

rm -f "$SSH_DIR/known_hosts"
for ip in 192.168.56.11 192.168.56.12; do
  ssh-keyscan -H "$ip" >> "$SSH_DIR/known_hosts" 2>/dev/null
done
chown vagrant:vagrant "$SSH_DIR/known_hosts"
chmod 644 "$SSH_DIR/known_hosts"

echo "==== [3/7] Configuration sudo ===="
echo "vagrant ALL=(ALL) NOPASSWD: ALL" | sudo tee /etc/sudoers.d/99_vagrant_nopasswd > /dev/null
sudo chmod 0440 /etc/sudoers.d/99_vagrant_nopasswd

echo "==== [4/7] Installation de Prometheus ===="
set +e

PROM_VERSION="2.52.0"
cd /tmp || { echo "[✗] Impossible de se rendre dans /tmp"; exit 1; }

curl -LO "https://github.com/prometheus/prometheus/releases/download/v${PROM_VERSION}/prometheus-${PROM_VERSION}.linux-amd64.tar.gz"
if [ $? -ne 0 ]; then
  echo "[✗] Échec du téléchargement de Prometheus"
  exit 1
fi

tar -xzf prometheus-${PROM_VERSION}.linux-amd64.tar.gz
if [ $? -ne 0 ]; then
  echo "[✗] Échec de l'extraction de Prometheus"
  exit 1
fi

cd prometheus-${PROM_VERSION}.linux-amd64 || { echo "[✗] Dossier introuvable"; exit 1; }

sudo useradd --no-create-home --shell /bin/false prometheus 2>/dev/null
sudo mkdir -p /etc/prometheus /var/lib/prometheus
sudo cp prometheus promtool /usr/local/bin/
sudo cp -r consoles console_libraries /etc/prometheus

cat <<EOF | sudo tee /etc/prometheus/prometheus.yml
global:
  scrape_interval: 15s

scrape_configs:
  - job_name: "prometheus"
    static_configs:
      - targets: ["localhost:9090"]
  - job_name: "node_exporters"
    static_configs:
      - targets: ["192.168.56.11:9100", "192.168.56.12:9100"]
EOF

cat <<EOF | sudo tee /etc/systemd/system/prometheus.service
[Unit]
Description=Prometheus
Wants=network-online.target
After=network-online.target

[Service]
User=prometheus
ExecStart=/usr/local/bin/prometheus \\
  --config.file=/etc/prometheus/prometheus.yml \\
  --storage.tsdb.path=/var/lib/prometheus \\
  --web.listen-address=0.0.0.0:9090

[Install]
WantedBy=multi-user.target
EOF

sudo chown -R prometheus:prometheus /etc/prometheus /var/lib/prometheus
sudo systemctl daemon-reload
sudo systemctl enable prometheus
sudo systemctl restart prometheus

echo "==== [5/7] Installation manuelle de Grafana 11.6.0 ===="

GRAFANA_VERSION="11.6.0"
GRAFANA_DIR="grafana-${GRAFANA_VERSION}"
GRAFANA_TAR="${GRAFANA_DIR}.linux-amd64.tar.gz"
GRAFANA_URL="https://dl.grafana.com/oss/release/${GRAFANA_TAR}"

cd /tmp
curl -LO "${GRAFANA_URL}"

if file "$GRAFANA_TAR" | grep -q "gzip compressed data"; then
  echo "[✓] Archive Grafana valide, extraction..."
  tar -xzf "$GRAFANA_TAR"
else
  echo "[✗] Archive Grafana non valide"
  exit 1
fi

# 🔁 Correction du bug : nom du dossier incorrect
mv grafana-v${GRAFANA_VERSION} "grafana-${GRAFANA_VERSION}.linux-amd64"

sudo mv "grafana-${GRAFANA_VERSION}.linux-amd64" /opt/grafana-${GRAFANA_VERSION}
sudo ln -s /opt/grafana-${GRAFANA_VERSION}/bin/grafana-server /usr/local/bin/grafana-server
sudo ln -s /opt/grafana-${GRAFANA_VERSION}/bin/grafana-cli /usr/local/bin/grafana-cli

cat <<EOF | sudo tee /etc/systemd/system/grafana-server.service
[Unit]
Description=Grafana
After=network.target

[Service]
Type=simple
ExecStart=/usr/local/bin/grafana-server \\
  --homepath=/opt/grafana-${GRAFANA_VERSION} \\
  --config=/opt/grafana-${GRAFANA_VERSION}/conf/defaults.ini
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable grafana-server
sudo systemctl start grafana-server

sleep 5
if ss -tuln | grep -q ':3000'; then
  echo "[✓] Grafana est opérationnel sur le port 3000"
else
  echo "[✗] Grafana ne semble pas avoir démarré correctement"
  exit 1
fi

echo "==== [6/7] Configuration Grafana via API ===="

# Attendre que Grafana soit prêt
until curl -s http://localhost:3000/api/health >/dev/null; do
  echo "En attente de Grafana..."
  sleep 2
done

# Création de la datasource Prometheus
echo "[+] Création de la datasource Prometheus"
curl -s -X POST http://localhost:3000/api/datasources \
  -H "Content-Type: application/json" \
  -u admin:admin \
  -d '{
    "name": "Prometheus",
    "type": "prometheus",
    "url": "http://localhost:9090",
    "access": "proxy",
    "basicAuth": false,
    "isDefault": true
  }'

# Import du dashboard officiel Node Exporter Full (ID 1860)
echo "==== [6.1/7] Import du dashboard officiel Node Exporter (ID 1860) ===="

# Télécharger le dashboard
curl -s https://grafana.com/api/dashboards/1860/revisions/36/download -o /tmp/dashboard1860.json

# Vérifier que le téléchargement a réussi
if [ ! -s /tmp/dashboard1860.json ]; then
  echo "[✗] Échec du téléchargement du dashboard 1860"
  exit 1
fi

# Créer le payload JSON à partir du dashboard
cat <<EOF > /tmp/import_dashboard.json
{
  "dashboard": $(cat /tmp/dashboard1860.json),
  "overwrite": true,
  "inputs": [
    {
      "name": "DS_PROMETHEUS",
      "type": "datasource",
      "pluginId": "prometheus",
      "value": "Prometheus"
    }
  ]
}
EOF

# Envoi via API Grafana
curl -s -X POST http://localhost:3000/api/dashboards/import \
  -H "Content-Type: application/json" \
  -u admin:admin \
  -d @/tmp/import_dashboard.json

echo "[✓] Dashboard Node Exporter Full importé avec succès !"

echo "==== [7/7] Provision terminé ===="

cd /vagrant/ansible
ansible-playbook -i inventory.ini playbook.yml