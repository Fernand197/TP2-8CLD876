#!/usr/bin/env bash
# Étape 1 : prérequis sur Ubuntu (Docker, kubectl, Minikube)
set -euo pipefail

echo "==> 1) Docker"
sudo apt-get update
sudo apt-get install -y docker.io curl
sudo systemctl enable --now docker
sudo usermod -aG docker "$USER"   # permet d'utiliser docker sans sudo (reconnexion ou 'newgrp docker' requis)

echo "==> 2) kubectl (binaire officiel ; l'ancien dépôt apt.kubernetes.io n'existe plus)"
ARCH=$(dpkg --print-architecture)   # amd64 (PC classique) ou arm64
KVER=$(curl -L -s https://dl.k8s.io/release/stable.txt)
curl -LO "https://dl.k8s.io/release/${KVER}/bin/linux/${ARCH}/kubectl"
sudo install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl
rm -f kubectl
kubectl version --client

echo "==> 3) Minikube (le fichier s'appelle minikube-linux-${ARCH} et doit être exécutable)"
curl -LO "https://storage.googleapis.com/minikube/releases/latest/minikube-linux-${ARCH}"
sudo install "minikube-linux-${ARCH}" /usr/local/bin/minikube
rm -f "minikube-linux-${ARCH}"
minikube version

echo
echo "Terminé. Activez maintenant le groupe docker, au choix :"
echo "  - fermez puis rouvrez le terminal (sous WSL : 'wsl --shutdown' dans PowerShell, puis rouvrir Ubuntu)"
echo "  - ou :  newgrp docker   (si 'command not found' : sudo apt install util-linux-extra)"
echo "Vérifiez avec 'docker ps', puis lancez :  minikube start --driver=docker"
