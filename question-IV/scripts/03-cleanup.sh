#!/usr/bin/env bash
# Supprime toute l'étude de cas (le Namespace emporte pods, services, secrets, PVC...),
# puis arrête le cluster à 3 nœuds.
# Usage : ./scripts/03-cleanup.sh            (supprime le namespace et arrête le cluster)
#         ./scripts/03-cleanup.sh --garder   (supprime le namespace, laisse le cluster démarré)
set -euo pipefail
PROFILE=${PROFILE:-etude-cas}

if minikube -p "$PROFILE" status >/dev/null 2>&1; then
  kubectl --context "$PROFILE" delete namespace etude-cas --ignore-not-found
  echo "Namespace supprimé."
  if [ "${1:-}" != "--garder" ]; then
    minikube -p "$PROFILE" stop
  fi
else
  echo "Le cluster '$PROFILE' est déjà arrêté."
fi

echo "Supprimer définitivement le cluster (3 nœuds) :  minikube -p $PROFILE delete"
echo "Revenir à la Question I :                        minikube start"
