#!/usr/bin/env bash
# Étape 6 : nettoyage.
set -uo pipefail
cd "$(dirname "$0")/.."

kubectl delete -f nodeport-demo/nodeport-demo.yaml --ignore-not-found
kubectl delete -f k8s/frontend-service.yaml --ignore-not-found
kubectl delete -f k8s/frontend-deployment.yaml --ignore-not-found
kubectl delete -f k8s/mysql-service.yaml --ignore-not-found
kubectl delete -f k8s/mysql-deployment.yaml --ignore-not-found
kubectl delete -f k8s/mysql-pvc.yaml --ignore-not-found   # supprime aussi les données
kubectl get all,pvc
minikube stop
