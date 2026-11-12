# Question I — Application web à deux niveaux sur Kubernetes (Minikube)

Architecture déployée :

```
                 Navigateur / curl
                        │  http://<IP du nœud>:30080
                        ▼
┌────────────── Nœud Minikube ──────────────────────────────────────┐
│  Service "frontend" (NodePort 30080 → port 80 → targetPort 80)     │
│          │ répartition de charge                                   │
│     ┌────┴─────┐                                                   │
│  Pod frontend  Pod frontend   (Deployment, 2 réplicas, Flask)       │
│     └────┬─────┘                                                   │
│          │ mysql:3306  (DNS interne)                               │
│  Service "mysql" (ClusterIP, interne seulement)                    │
│          ▼                                                         │
│  Pod MySQL 5.7 (Deployment, 1 réplica)                             │
│          │ /var/lib/mysql                                          │
│  PVC mysql-pvc (1Gi, ReadWriteOnce) ──► PV créé automatiquement    │
└────────────────────────────────────────────────────────────────────┘
```

## Contenu du dossier

| Fichier | Rôle |
| --- | --- |
| `frontend/` | Application Flask CRUD (Create, Read, Update, Delete) + `Dockerfile` — c'est l'image `[VOTRE_IMAGE_FRONTEND]` |
| `k8s/mysql-pvc.yaml` | PersistentVolumeClaim de 1 Gi (Étape 4.1) |
| `k8s/mysql-deployment.yaml` | Déploiement MySQL, **volume persistant déjà intégré** (Étapes 2 + 4.2) |
| `k8s/mysql-service.yaml` | Service MySQL (ClusterIP) |
| `k8s/frontend-deployment.yaml` | Déploiement frontend, 2 réplicas (Étape 3.1) |
| `k8s/frontend-service.yaml` | Service frontend de type **NodePort** (Étape 3.2) |
| `nodeport-demo/nodeport-demo.yaml` | Exemple exécutable dédié à l'explication du NodePort |
| `scripts/01…05-*.sh` | Les étapes de l'énoncé, prêtes à exécuter |

---

## Étape 1 — Prérequis (Ubuntu)

```bash
./scripts/01-prerequis.sh
newgrp docker                      # ou fermer / rouvrir le terminal
docker ps                          # doit fonctionner sans sudo
minikube start --driver=docker
kubectl get nodes                  # doit afficher : minikube   Ready   control-plane
```

**Corrections apportées aux commandes de l'énoncé :**

1. **kubectl** — le dépôt `apt.kubernetes.io` (`kubernetes-xenial`) a été gelé puis fermé par le projet Kubernetes ; `apt-get install kubectl` échoue avec ces commandes. On installe donc le binaire officiel depuis `dl.k8s.io` (ou bien le nouveau dépôt `pkgs.k8s.io`). La ligne de l'énoncé est aussi tronquée (`/etc/apt/sourc`).
2. **Minikube** — le fichier à télécharger s'appelle `minikube-linux-amd64` (pas `minikube-linux`), et il faut le rendre exécutable (`sudo install …` le fait, sinon `chmod +x`).
3. **Docker** — ajout de l'utilisateur au groupe `docker` ; sans ça, `minikube start --driver=docker` refuse de démarrer.

> **Sous Windows** (Docker Desktop) : `winget install Kubernetes.kubectl` puis `winget install Kubernetes.minikube`, puis `minikube start --driver=docker`. Les commandes `kubectl` et `minikube` qui suivent sont les mêmes (dans PowerShell, exécutez-les une par une au lieu des scripts `.sh`, ou utilisez Git Bash / WSL).

## Étapes 2 à 5 — Déploiement

```bash
./scripts/02-deploy.sh
```

Ce que fait le script, dans l'ordre :

```bash
minikube image build -t tp-frontend:1.0 ./frontend   # construit l'image frontend DANS Minikube
kubectl apply -f k8s/mysql-pvc.yaml                  # Étape 4.1 (avant MySQL, qui en a besoin)
kubectl apply -f k8s/mysql-deployment.yaml           # Étape 2.1 (+ 4.2)
kubectl apply -f k8s/mysql-service.yaml              # Étape 2.2
kubectl apply -f k8s/frontend-deployment.yaml        # Étape 3.1
kubectl apply -f k8s/frontend-service.yaml           # Étape 3.2
```

**Remarques :**

- **Image frontend** : `imagePullPolicy: Never` indique à Kubernetes d'utiliser l'image construite localement dans Minikube au lieu de la chercher sur Docker Hub.
- **Ordre** : l'énoncé crée le PVC à l'Étape 4 puis réapplique MySQL. Ici, le PVC est créé en premier et `mysql-deployment.yaml` contient déjà `volumeMounts`/`volumes`, ce qui revient au même résultat final.
- **`strategy: Recreate`** sur MySQL : un volume `ReadWriteOnce` ne doit pas être monté par deux pods MySQL en même temps pendant une mise à jour.
- **Connexion frontend → base** : le frontend se connecte à l'hôte `mysql`, qui est **le nom du Service**. Le DNS du cluster (CoreDNS) le résout vers le ClusterIP du Service, qui redirige vers le pod MySQL.

Résultat attendu :

```
$ kubectl get pvc
NAME        STATUS   VOLUME          CAPACITY   ACCESS MODES   STORAGECLASS
mysql-pvc   Bound    pvc-xxxxxxxx    1Gi        RWO            standard

$ kubectl get pods
NAME                        READY   STATUS    RESTARTS
frontend-7c9d8b6f4d-abcde   1/1     Running   0
frontend-7c9d8b6f4d-fghij   1/1     Running   0
mysql-5d8f7c9b8-klmno       1/1     Running   0

$ kubectl get svc
NAME         TYPE        CLUSTER-IP      PORT(S)
frontend     NodePort    10.96.x.x       80:30080/TCP
kubernetes   ClusterIP   10.96.0.1       443/TCP
mysql        ClusterIP   10.96.y.y       3306/TCP
```

### Étape 5 — Accéder à l'application

```bash
minikube service frontend --url
# ex. http://192.168.49.2:30080
```

Ouvrez l'URL : ajoutez, modifiez et supprimez des étudiants (CRUD). Le bandeau bleu affiche le **nom du pod** qui a servi la page ; en rafraîchissant (Ctrl+F5), il alterne entre les 2 réplicas.

> Sous Windows/macOS avec le driver Docker, l'IP du nœud n'est pas joignable directement : `minikube service … --url` ouvre un tunnel ; **gardez ce terminal ouvert** et utilisez l'URL `127.0.0.1:<port>` affichée.

### Vérification de la persistance et du CRUD

```bash
./scripts/03-tests.sh
```

Le script insère une ligne, **supprime le pod MySQL**, attend que le Deployment en recrée un, puis relit la table : la ligne est toujours présente, car les données sont dans le PVC et non dans le conteneur. (Sans le volume, la table serait vide après le redémarrage.)

## Étape 6 — Nettoyage

```bash
./scripts/05-cleanup.sh       # supprime services, déploiements, PVC, puis minikube stop
```

---

## Explication du type NodePort (avec exemple exécutable)

### Les types de Service

Un **Service** donne une adresse stable à un ensemble de pods (choisis par `selector`), car les pods sont éphémères et leur IP change.

| Type | Accessible depuis | Exemple dans ce projet |
| --- | --- | --- |
| `ClusterIP` (défaut) | Intérieur du cluster seulement | `mysql` : la base ne doit pas être exposée à l'extérieur |
| `NodePort` | Extérieur, via `IP_du_nœud:nodePort` | `frontend` : l'utilisateur doit atteindre l'interface |
| `LoadBalancer` | Extérieur, via un équilibreur de charge du fournisseur cloud (AWS ELB…) | — |

### Le principe du NodePort

Un Service `NodePort` **est un ClusterIP auquel on ajoute un port ouvert sur chaque nœud** du cluster, dans la plage **30000–32767**. Le composant `kube-proxy` de chaque nœud intercepte le trafic qui arrive sur ce port et le redirige vers l'un des pods du Service (répartition de charge).

Trois ports à ne pas confondre :

```yaml
ports:
  - port: 8080        # port du Service sur son ClusterIP (accès interne : hello-nodeport:8080)
    targetPort: 5678  # port où écoute réellement le conteneur
    nodePort: 30007   # port ouvert sur chaque nœud (accès externe : <IP_nœud>:30007)
```

Chemin d'une requête :

```
Client ──► 192.168.49.2:30007 ──► kube-proxy ──► ClusterIP:8080 ──► un des pods :5678
           (IP nœud : nodePort)                  (port)             (targetPort)
```

Si `nodePort` est omis, Kubernetes en choisit un au hasard dans la plage (c'est le cas du `frontend-service.yaml` de l'énoncé ; nous l'avons fixé à 30080 pour avoir une URL prévisible).

### Exemple exécutable

`nodeport-demo/nodeport-demo.yaml` déploie 3 pods `hello` (image `hashicorp/http-echo`) qui répondent chacun avec **leur propre nom**, et un Service `NodePort` sur le port 30007.

```bash
./scripts/04-nodeport-demo.sh
```

ou manuellement :

```bash
kubectl apply -f nodeport-demo/nodeport-demo.yaml
kubectl get svc hello-nodeport
# NAME             TYPE       CLUSTER-IP     PORT(S)
# hello-nodeport   NodePort   10.104.x.x     8080:30007/TCP

kubectl get endpoints hello-nodeport      # les 3 IP de pods derrière le Service

# (A) Accès externe par le NodePort (Linux)
for i in 1 2 3 4 5 6; do curl -s http://$(minikube ip):30007; done
# Bonjour ! Reponse du pod hello-6b9c7d-x2k4p
# Bonjour ! Reponse du pod hello-6b9c7d-m8q1z
# Bonjour ! Reponse du pod hello-6b9c7d-r5t7w
# ...   -> la charge est répartie entre les 3 pods

# (A') Windows / macOS : tunnel
minikube service hello-nodeport --url

# (B) Le même Service reste accessible en interne sur son port 8080
kubectl run client --rm -i --restart=Never --image=busybox:1.36 -- \
  wget -qO- http://hello-nodeport:8080

# Nettoyage
kubectl delete -f nodeport-demo/nodeport-demo.yaml
```

**Ce que montre l'exemple :** (1) le Service est joignable depuis l'extérieur du cluster par `IP_du_nœud:30007` ; (2) les requêtes sont réparties entre les pods ; (3) un NodePort garde aussi son accès interne (`ClusterIP:8080`).

**Limites du NodePort :** plage de ports imposée (30000–32767), un seul service par port, et le client doit connaître l'IP d'un nœud (qui peut changer). En production, on préfère un `LoadBalancer` ou un `Ingress` ; NodePort convient bien au développement et aux tests, comme ici avec Minikube.

---

## Dépannage rapide

| Symptôme | Cause / solution |
| --- | --- |
| Pod frontend `ErrImageNeverPull` | L'image n'est pas dans Minikube : relancer `minikube image build -t tp-frontend:1.0 ./frontend` |
| Pod MySQL `Pending` | PVC non lié : `kubectl describe pvc mysql-pvc` ; vérifier `minikube addons list` (storage-provisioner activé) |
| `newgrp: command not found` | Sur les Ubuntu récents : `sudo apt install util-linux-extra`, ou fermer puis rouvrir le terminal (sous WSL : `wsl --shutdown` dans PowerShell) |
| MySQL `CrashLoopBackOff` / `ImagePullBackOff` sur machine ARM (Mac M1/M2/M3) | `mysql:5.7` n'existe pas en ARM. Dans `k8s/mysql-deployment.yaml`, mettre `image: mysql:8.0` et ajouter sous le conteneur `args: ["--default-authentication-plugin=mysql_native_password"]` (sans cet argument, le frontend ne peut pas s'authentifier auprès de MySQL 8) |
| Page « Erreur base de données » | MySQL pas encore prêt : attendre, puis `kubectl logs deploy/frontend` |
| `curl $(minikube ip):30080` bloque | Windows/macOS : utiliser `minikube service frontend --url` |
| Sous WSL, l'URL `http://192.168.49.2:30080` ne s'ouvre pas dans le navigateur Windows | Cette IP appartient au réseau Docker interne à WSL. Lancer `kubectl port-forward --address 0.0.0.0 service/frontend 8080:80` (terminal ouvert) et ouvrir `http://localhost:8080` |
