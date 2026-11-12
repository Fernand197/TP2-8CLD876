#!/usr/bin/env bash
# Démonstration : une étape par capacité de Kubernetes citée dans l'énoncé.
# Usage : ./scripts/02-demo.sh            (toutes les étapes)
#         ./scripts/02-demo.sh 5 7        (seulement les étapes 5 et 7)
set -euo pipefail
export MSYS_NO_PATHCONV=1
NS=etude-cas
PROFILE=${PROFILE:-etude-cas}
KC="kubectl --context $PROFILE"
K="$KC -n $NS"

# Exécute une commande shell dans le pod "client", donc DEPUIS l'intérieur du cluster.
C() { $K exec deploy/client -- sh -c "$1"; }
titre() { echo; echo "=================================================================="; echo "  $1"; echo "=================================================================="; }
attendre_api() { $K rollout status deployment/api --timeout=300s >/dev/null; }
en_file() { C "curl -s http://api/taches" | grep -o '"en_file":[0-9]*' | cut -d: -f2; }
nb_workers() { n=$($K get deployment worker -o jsonpath='{.status.replicas}'); echo "${n:-0}"; }
pods_par_noeud() { $K get pods -l "$1" -o custom-columns=POD:.metadata.name,NOEUD:.spec.nodeName,ETAT:.status.phase; }

etape1() {
  titre "1) DÉPLOIEMENT ET EMPLACEMENTS : quels pods, sur quels nœuds ?"
  $KC get nodes
  $K get deployment,statefulset
  echo "--- Les 3 pods API sont répartis sur les 3 nœuds (topologySpreadConstraints) :"
  pods_par_noeud app=api
  echo "--- Redis est épinglé sur le nœud principal, là où se trouve son volume (nodeSelector) :"
  pods_par_noeud app=redis
}

etape2() {
  titre "2) DÉCOUVERTE DE SERVICES + ÉQUILIBRAGE DE CHARGE"
  echo "--- Le DNS du cluster résout le nom du Service 'api' :"
  C "nslookup api.$NS.svc.cluster.local | tail -n 3"
  echo "--- Points de terminaison (pods) derrière le Service :"
  $K get endpointslices -l kubernetes.io/service-name=api
  echo "--- 12 requêtes vers http://api/ : répartition par pod"
  C 'for i in $(seq 12); do curl -s http://api/; echo; done' | grep -o 'api-[a-z0-9]*-[a-z0-9]*' | sort | uniq -c
}

etape3() {
  titre "3) CONFIGURATION ET SECRETS"
  echo "--- MESSAGE vient du ConfigMap 'app-config' :"
  C "curl -s http://api/"; echo
  echo "--- Le mot de passe n'est pas dans le Deployment, seulement une référence au Secret :"
  $K get deployment api -o jsonpath='{.spec.template.spec.containers[0].env}'; echo
  echo "--- Modification du ConfigMap puis redémarrage progressif pour la prendre en compte :"
  $K patch configmap app-config --type merge -p '{"data":{"MESSAGE":"Configuration modifiee sans reconstruire l image"}}'
  $K rollout restart deployment/api
  attendre_api
  sleep 6      # laisse les anciens pods finir leur arrêt en douceur (preStop de 5 s)
  C "curl -s http://api/"; echo
}

etape4() {
  titre "4) COMMUNICATION ENTRE CONTENEURS + INTERACTION ÉVÉNEMENTIELLE (API -> file Redis -> worker)"
  echo "--- Au repos, aucun worker ne tourne : $(nb_workers) réplica(s)"
  echo "--- L'API dépose 3 événements dans la file et répond immédiatement (202) :"
  C 'for i in 1 2 3; do curl -s -X POST -H "Content-Type: application/json" -d "{\"texte\":\"commande numero $i\"}" http://api/taches; echo; done'
  echo "--- L'arrivée des événements réveille un worker (KEDA), qui les traite de façon asynchrone..."
  sleep 3
  until [ "$(en_file)" = "0" ]; do sleep 2; done
  sleep 3
  C "curl -s http://api/taches"; echo
  echo "--- Journal du worker :"
  $K logs deployment/worker --tail=4
}

etape5() {
  titre "5) MONTÉE EN ÉCHELLE PILOTÉE PAR LES ÉVÉNEMENTS (KEDA) : workers selon la longueur de la file"
  $K get scaledobject worker
  echo "--- Rafale de 150 événements (1 s de traitement chacun)"
  C 'for i in $(seq 150); do curl -s -o /dev/null -X POST -H "Content-Type: application/json" -d "{\"texte\":\"lot $i\"}" http://api/taches; done'
  echo "--- Toutes les 5 s : événements en attente / nombre de workers"
  while :; do
    f=$(en_file || true); w=$(nb_workers || true); echo "    en file : ${f:-?}   workers : ${w:-0}"
    [ "$f" = "0" ] && break
    sleep 5
  done
  echo "--- Répartition des 150 tâches entre les workers :"
  $K get pods -l app=worker -o name | while read -r p; do
    echo "    $(basename "$p") : $($K logs "$p" 2>/dev/null | grep -c 'traitée') tâches"
  done
  echo "--- File vide : après la période de calme (cooldown), KEDA ramène les workers à 0"
  until [ "$(nb_workers)" = "0" ]; do echo "    workers : $(nb_workers)"; sleep 10; done
  $K get deployment worker
}

etape6() {
  titre "6) GESTION DES DYSFONCTIONNEMENTS (auto-réparation des pods)"
  VICTIME=$($K get pod -l app=api -o jsonpath='{.items[0].metadata.name}')
  echo "--- (a) Suppression brutale du pod $VICTIME : le Deployment en recrée un"
  $K delete pod "$VICTIME" --wait=false
  attendre_api
  $K get pods -l app=api --field-selector=status.phase=Running

  echo "--- (b) Blocage applicatif simulé : la sonde liveness échoue, le kubelet redémarre le conteneur"
  CASSE=$(C "curl -s -X POST http://api/casser" | grep -o 'api-[a-z0-9]*-[a-z0-9]*')
  echo "    Pod cassé : $CASSE"
  until [ "$($K get pod "$CASSE" -o jsonpath='{.status.containerStatuses[0].restartCount}')" != "0" ]; do
    echo "    ... en attente de la détection par la sonde"; sleep 5
  done
  $K get pods -l app=api
  echo "    (colonne RESTARTS = 1 pour $CASSE ; pendant ce temps les autres pods servaient le trafic)"
  attendre_api
}

etape7() {
  titre "7) PERTE D'UN NŒUD : évacuation (drain) et replanification des pods ailleurs"
  # On évacue un nœud de travail qui n'héberge pas le pod "client" (il envoie les requêtes de contrôle).
  NOEUD_CLIENT=$($K get pod -l app=client -o jsonpath='{.items[0].spec.nodeName}')
  NOEUD=$($KC get nodes -l '!node-role.kubernetes.io/control-plane' -o name | cut -d/ -f2 | grep -vx "$NOEUD_CLIENT" | tail -n 1)
  echo "--- Avant : emplacement des pods API"
  pods_par_noeud app=api
  echo "--- Évacuation du nœud $NOEUD (comme pour une maintenance ou un retrait de machine)"
  echo "    Des requêtes sont envoyées pendant l'opération pour vérifier la continuité du service."
  C 'for i in $(seq 40); do curl -s -m 3 -o /dev/null -w "HTTP=%{http_code}\n" http://api/; sleep 0.3; done' > /tmp/drain-requetes.txt 2>/dev/null &
  REQ=$!
  $KC drain "$NOEUD" --ignore-daemonsets --delete-emptydir-data --timeout=180s 2>&1 | grep -E 'cordoned|evicted|drained' || true
  wait $REQ || true
  $KC get nodes
  attendre_api
  $K rollout status deployment/client --timeout=120s >/dev/null
  echo "--- Après : les pods du nœud évacué ont été recréés sur les nœuds restants"
  pods_par_noeud app=api
  echo "--- 40 requêtes envoyées pendant l'évacuation :"
  sort /tmp/drain-requetes.txt | uniq -c
  echo "--- Remise en service du nœud (les pods existants ne sont pas déplacés automatiquement)"
  $KC uncordon "$NOEUD"
}

etape8() {
  titre "8) STOCKAGE PERSISTANT : les données survivent à la destruction du pod Redis"
  $K get pvc
  echo "--- Compteur avant : $(C 'curl -s http://api/')"
  $K delete pod redis-0
  echo "--- Le StatefulSet recrée redis-0 et lui rattache le MÊME volume :"
  $K rollout status statefulset/redis --timeout=300s
  $K wait --for=condition=Ready pod -l app=api --timeout=120s >/dev/null
  echo "--- Compteur après (il continue, il ne repart pas de 1) : $(C 'curl -s http://api/')"
}

etape9() {
  titre "9) MISE À JOUR PROGRESSIVE v1.0 -> v2.0 sans interruption, puis retour arrière"
  $K set image deployment/api api=etude-cas:2.0
  echo "--- 40 requêtes pendant le déploiement (version servie et code HTTP) :"
  C 'for i in $(seq 40); do curl -s -m 3 -w " HTTP=%{http_code}\n" http://api/; sleep 0.3; done' \
    | grep -o '"version":"[^"]*"\|HTTP=[0-9]*' | sort | uniq -c
  attendre_api
  $K rollout history deployment/api
  echo "--- Retour arrière (rollback) vers la révision précédente :"
  $K rollout undo deployment/api 2>/dev/null
  attendre_api
  C "curl -s http://api/"; echo
}

etape10() {
  titre "10) MONTÉE EN ÉCHELLE AUTOMATIQUE (HPA) sous charge processeur (~4 min)"
  echo "--- Attente des premières mesures CPU des pods (metrics-server, ~1 min après leur création)"
  for i in $(seq 36); do
    [ -n "$($K get hpa api -o jsonpath='{.status.currentMetrics[0].resource.current.averageUtilization}' 2>/dev/null)" ] && break
    sleep 5
  done
  $K get hpa api
  echo "--- Génération de charge : 6 clients en boucle sur /cpu pendant 120 s"
  C 'for j in 1 2 3 4 5 6; do (fin=$(( $(date +%s) + 120 )); while [ $(date +%s) -lt $fin ]; do curl -s -o /dev/null "http://api/cpu?ms=300"; done) & done; wait' &
  for i in $(seq 10); do sleep 15; $K get hpa api --no-headers; done
  wait
  echo "--- Les nouveaux pods sont répartis sur les nœuds :"
  pods_par_noeud app=api
  echo "    (après ~1 à 2 min sans charge, le HPA redescend à 3 réplicas : $K get hpa api -w)"
}

if [ $# -eq 0 ]; then set -- 1 2 3 4 5 6 7 8 9 10; fi
for n in "$@"; do "etape$n"; done
