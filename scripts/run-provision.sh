#!/bin/bash

# Empêche les prompts interactifs de bloquer
export DEBIAN_FRONTEND=noninteractive

echo "==== Lancement du provisionnement ===="

# Donne les droits d’exécution à tous les scripts nécessaires
chmod +x /vagrant/scripts/provision-jumpbox.sh

# Exécute le script principal de provision de la jumpbox
/vagrant/scripts/provision-jumpbox.sh

echo "==== Provisionnement terminé ===="
