#!/usr/bin/env bash
# Démo exécutable du type NodePort.
set -euo pipefail
cd "$(dirname "$0")/.."

echo "==> Démarrage de Minikube (si nécessaire)"
minikube status >/dev/null 2>&1 || minikube start --driver=docker

kubectl apply -f nodeport-demo/nodeport-demo.yaml
kubectl rollout status deployment/hello --timeout=180s

echo "==> Le Service : TYPE=NodePort, PORT(S)=8080:30007/TCP  (port du Service : port du nœud)"
kubectl get service hello-nodeport -o wide
echo "==> Les pods derrière le Service (Endpoints)"
kubectl get endpoints hello-nodeport

NODE_IP=$(minikube ip)
echo
echo "==> (A) Accès EXTERNE : <IP du nœud>:<nodePort> = $NODE_IP:30007"
for i in $(seq 1 6); do curl -s --max-time 3 "http://$NODE_IP:30007" || echo "non joignable (voir B')"; done

echo
echo "==> (B') Alternative Windows/macOS : tunnel Minikube"
echo "    minikube service hello-nodeport --url"

echo
echo "==> (C) Accès INTERNE : le même Service garde un ClusterIP sur le port 8080"
# Le nom "hello-nodeport" est résolu par le DNS du cluster (CoreDNS) : juste après un
# démarrage de Minikube il peut ne pas être prêt, d'où l'attente et les nouvelles tentatives.
kubectl wait -n kube-system --for=condition=Ready pod -l k8s-app=kube-dns --timeout=120s
kubectl delete pod client --ignore-not-found >/dev/null 2>&1
kubectl run client --rm -i --restart=Never --image=busybox:1.36 -- \
  sh -c 'for i in 1 2 3; do
           n=0
           until wget -qO- http://hello-nodeport:8080 2>/dev/null; do
             n=$((n+1)); [ "$n" -ge 10 ] && { echo "DNS du cluster indisponible"; exit 1; }
             sleep 3
           done
         done'

echo
echo "Nettoyage de la démo : kubectl delete -f nodeport-demo/nodeport-demo.yaml"
