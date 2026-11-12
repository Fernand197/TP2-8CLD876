#!/usr/bin/env bash
# Vérifications : CRUD via MySQL, persistance après suppression du pod, répartition entre réplicas.
set -euo pipefail

MYSQL_POD() { kubectl get pod -l app=mysql -o jsonpath='{.items[0].metadata.name}'; }
SQL() { kubectl exec "$(MYSQL_POD)" -- mysql -uroot -ppassword tpdb -e "$1" 2>/dev/null; }

echo "==> 1) Insertion d'une ligne de test directement dans MySQL"
SQL "DELETE FROM etudiants WHERE nom = 'Test-persistance';"   # évite les doublons si le script est relancé
SQL "INSERT INTO etudiants (nom, programme) VALUES ('Test-persistance', '8CLD876');"
SQL "SELECT * FROM etudiants;"

OLD=$(MYSQL_POD)
echo "==> 2) Suppression du pod MySQL ($OLD) — le Deployment en recrée un"
kubectl delete pod "$OLD"
kubectl rollout status deployment/mysql --timeout=300s
sleep 5
until SQL "SELECT 1;" >/dev/null; do echo "   ... MySQL redémarre"; sleep 3; done
echo "   Nouveau pod : $(MYSQL_POD)"

echo "==> 3) Les données sont toujours là (grâce au PVC mysql-pvc) :"
SQL "SELECT * FROM etudiants;"

echo "==> 4) Accès au frontend par le NodePort 30080 — observez le nom du pod qui change"
URL="http://$(minikube ip):30080"
for i in 1 2 3 4 5 6; do
  curl -s --max-time 3 "$URL/health" || echo "(IP du nœud non joignable : utilisez 'minikube service frontend --url')"
  echo
done
