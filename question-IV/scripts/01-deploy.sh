#!/usr/bin/env bash
# Crée un cluster Minikube à 3 nœuds (profil séparé), installe metrics-server et KEDA,
# construit les images (v1.0 et v2.0) puis déploie toute l'étude de cas.
set -euo pipefail
export MSYS_NO_PATHCONV=1          # Git Bash (Windows) : ne pas réécrire les chemins passés à kubectl
cd "$(dirname "$0")/.."
NS=etude-cas
PROFILE=${PROFILE:-etude-cas}      # profil Minikube dédié : le cluster "minikube" par défaut n'est pas touché
KEDA_VERSION=${KEDA_VERSION:-2.21.0}
MK="minikube -p $PROFILE"
KC="kubectl --context $PROFILE"

echo "==> Cluster Minikube '$PROFILE' à 3 nœuds (créé ou démarré si nécessaire)"
$MK status >/dev/null 2>&1 || $MK start --nodes 3 --driver=docker
$MK addons enable metrics-server       # mesures CPU pour le HPA
$KC get nodes -o wide

echo "==> Installation de KEDA $KEDA_VERSION (autoscaling piloté par les événements)"
$KC apply --server-side -f "https://github.com/kedacore/keda/releases/download/v$KEDA_VERSION/keda-$KEDA_VERSION.yaml" >/dev/null
$KC -n keda wait --for=condition=Available deployment --all --timeout=300s

echo "==> Construction des images etude-cas:1.0 et etude-cas:2.0, puis chargement sur les 3 nœuds"
for v in 1.0 2.0; do
  docker build -q --build-arg APP_VERSION="$v" -t "etude-cas:$v" ./app
  $MK image load "etude-cas:$v"
done

echo "==> Application des manifestes (dans l'ordre des noms de fichiers)"
$KC apply -f k8s/

echo "==> Attente : Redis, API, client"
$KC -n "$NS" rollout status statefulset/redis --timeout=300s
$KC -n "$NS" rollout status deployment/api --timeout=300s
$KC -n "$NS" rollout status deployment/client --timeout=300s

echo "==> État du déploiement"
$KC -n "$NS" get statefulset,deployment,pods,svc,pvc,hpa,scaledobject -o wide

echo
echo "Prêt. Lancer la démonstration :   ./scripts/02-demo.sh"
echo "Accès depuis le poste (navigateur / curl) :"
echo "  kubectl --context $PROFILE -n $NS port-forward service/api 8080:80     puis   http://localhost:8080/"
echo "Note : kubectl pointe maintenant par défaut sur le cluster '$PROFILE'."
echo "       Pour revenir au cluster de la Question I :   minikube start"
