#!/usr/bin/env bash
# Étapes 2 à 5 : démarrage du cluster, construction de l'image frontend, déploiement.
set -euo pipefail
cd "$(dirname "$0")/.."

echo "==> Démarrage de Minikube (si nécessaire)"
minikube status >/dev/null 2>&1 || minikube start --driver=docker
kubectl get nodes

echo "==> Construction de l'image frontend DANS Minikube (remplace [VOTRE_IMAGE_FRONTEND])"
minikube image build -t tp-frontend:1.0 ./frontend

echo "==> Étape 4.1 : PersistentVolumeClaim (créé avant MySQL qui l'utilise)"
kubectl apply -f k8s/mysql-pvc.yaml

echo "==> Étape 2 : base de données MySQL (Deployment + Service)"
kubectl apply -f k8s/mysql-deployment.yaml
kubectl apply -f k8s/mysql-service.yaml
kubectl rollout status deployment/mysql --timeout=300s

echo "==> Étape 3 : frontend (Deployment 2 réplicas + Service NodePort)"
kubectl apply -f k8s/frontend-deployment.yaml
kubectl apply -f k8s/frontend-service.yaml
kubectl rollout status deployment/frontend --timeout=300s

echo "==> État du cluster"
kubectl get pvc,pv
kubectl get deployments,pods -o wide
kubectl get services

echo "==> Étape 5 : URL du frontend"
echo "Linux :   http://$(minikube ip):30080"
echo "Sinon :   minikube service frontend --url   (laisser le terminal ouvert sous Windows/macOS)"
