# Question IV — Étude de l'architecture de Kubernetes

Plan : [a) Architecture](#a-architecture-de-kubernetes) · [b) Étude de cas](#b-étude-de-cas--un-exemple-complet-et-exécutable) · [c) Avantages et inconvénients](#c-avantages-et-inconvénients-de-kubernetes) · [d) Comparaison](#d-comparaison--kubernetes-conteneurs-docker-et-machines-virtuelles)

---

## a) Architecture de Kubernetes

### a.1 Idée générale : un système déclaratif

Kubernetes (K8s) est un **orchestrateur de conteneurs** : il répartit des conteneurs sur une grappe (*cluster*) de machines et les maintient en fonctionnement. Son principe central est le **modèle déclaratif** :

1. l'utilisateur décrit l'**état désiré** dans des manifestes YAML (« je veux 3 réplicas de cette image ») ;
2. Kubernetes enregistre cet état et observe en permanence l'**état réel** ;
3. des **contrôleurs** corrigent tout écart entre les deux (*boucle de réconciliation*).

On ne dit donc pas à Kubernetes *quoi faire* (démarrer tel conteneur sur telle machine), mais *quoi obtenir*. C'est ce qui rend possibles l'auto-réparation, la mise à l'échelle et les mises à jour automatiques.

### a.2 Vue d'ensemble

Un cluster comprend deux types de machines : le **plan de contrôle** (*control plane*), qui décide, et les **nœuds de travail** (*worker nodes*), qui exécutent.

```
   kubectl / CI-CD / tableau de bord
              │  HTTPS (API REST)
              ▼
┌──────────────────────── PLAN DE CONTRÔLE ────────────────────────┐
│                                                                  │
│   ┌────────────────┐       ┌──────────┐                          │
│   │ kube-apiserver │◄─────►│   etcd   │  base clé-valeur :       │
│   └───────▲────────┘       └──────────┘  tout l'état du cluster  │
│           │ (tous les composants passent par l'API)              │
│   ┌───────┴────────┬──────────────────────┬───────────────────┐  │
│   │ kube-scheduler │ kube-controller-     │ cloud-controller- │  │
│   │ (choix du nœud)│ manager (contrôleurs)│ manager (cloud)   │  │
│   └────────────────┴──────────────────────┴───────────────────┘  │
└───────────────────────────────┬──────────────────────────────────┘
                                │ surveillance (watch) de l'API
        ┌───────────────────────┴───────────────────────┐
        ▼                                               ▼
┌──────────── NŒUD 1 ─────────────┐     ┌──────────── NŒUD 2 ─────────────┐
│ kubelet          kube-proxy     │     │ kubelet          kube-proxy     │
│ runtime de conteneurs           │     │ runtime de conteneurs           │
│ (containerd + runc, via CRI)    │     │ (containerd + runc, via CRI)    │
│ ┌───── Pod ─────┐ ┌─── Pod ───┐ │     │ ┌───── Pod ─────┐ ┌─── Pod ───┐ │
│ │ conteneur(s)  │ │ conteneur │ │     │ │ conteneur(s)  │ │ conteneur │ │
│ └───────────────┘ └───────────┘ │     │ └───────────────┘ └───────────┘ │
│   réseau de pods (plugin CNI)   │◄───►│   réseau de pods (plugin CNI)   │
└─────────────────────────────────┘     └─────────────────────────────────┘
```

### a.3 Composantes du plan de contrôle

| Composante | Rôle |
| --- | --- |
| **kube-apiserver** | Porte d'entrée unique du cluster (API REST). Authentifie, autorise (RBAC), valide les requêtes et est le **seul** composant qui lit et écrit dans etcd. Tous les autres composants communiquent à travers lui. |
| **etcd** | Base de données clé-valeur distribuée et cohérente (algorithme de consensus Raft). Elle contient tout l'état du cluster : objets désirés et état observé. En production, on la réplique sur 3 ou 5 machines. |
| **kube-scheduler** | Attribue un nœud à chaque pod nouvellement créé. Il filtre les nœuds possibles (ressources libres, contraintes, *taints*) puis les classe (répartition, affinités). |
| **kube-controller-manager** | Exécute les contrôleurs : Deployment, ReplicaSet, StatefulSet, Node, Job, EndpointSlice, etc. Chacun applique la boucle « observer → comparer → agir ». |
| **cloud-controller-manager** | Fait le lien avec le fournisseur infonuagique : création d'équilibreurs de charge, de volumes, de routes, détection des nœuds supprimés. Absent sur un cluster local. |

### a.4 Composantes d'un nœud

| Composante | Rôle |
| --- | --- |
| **kubelet** | Agent présent sur chaque nœud. Il reçoit de l'API la liste des pods affectés à son nœud, demande au runtime de lancer les conteneurs, monte les volumes, exécute les **sondes** (liveness, readiness, startup) et rapporte l'état. |
| **Runtime de conteneurs** | Logiciel qui exécute réellement les conteneurs. Le kubelet lui parle par l'interface standard **CRI**. Le plus courant est **containerd** (ou CRI-O), qui s'appuie sur **runc** pour créer le conteneur. Depuis la version 1.24, Kubernetes n'utilise plus Docker Engine directement, mais les images construites avec Docker restent compatibles (format OCI). |
| **kube-proxy** | Programme les règles réseau du nœud (iptables, IPVS ou nftables) pour que l'adresse virtuelle d'un Service redirige vers l'un des pods correspondants : c'est l'équilibrage de charge interne. |

**Modules complémentaires** presque toujours présents : **CoreDNS** (DNS interne, base de la découverte de services), un **plugin CNI** (Calico, Cilium, Flannel… : réseau entre pods), **metrics-server** (mesures CPU/mémoire pour l'autoscaling) et un **contrôleur Ingress** (routage HTTP entrant).

### a.5 Les objets manipulés

| Besoin | Objet Kubernetes |
| --- | --- |
| Unité d'exécution | **Pod** : un ou plusieurs conteneurs qui partagent la même adresse IP et les mêmes volumes |
| Application sans état répliquée | **Deployment** → **ReplicaSet** → Pods |
| Application avec état (base de données) | **StatefulSet** (identité et volume stables par pod) |
| Un pod par nœud (agent de journalisation, de surveillance) | **DaemonSet** |
| Traitement ponctuel ou planifié | **Job**, **CronJob** |
| Adresse stable + équilibrage | **Service** (ClusterIP, NodePort, LoadBalancer) |
| Routage HTTP(S) externe | **Ingress** / Gateway API |
| Configuration, données sensibles | **ConfigMap**, **Secret** |
| Stockage | **PersistentVolume**, **PersistentVolumeClaim**, **StorageClass** |
| Mise à l'échelle automatique | **HorizontalPodAutoscaler** |
| Cloisonnement logique, droits | **Namespace**, **RBAC**, **NetworkPolicy** |

### a.6 Virtualisation : où se situe Kubernetes ?

Kubernetes repose sur la **virtualisation au niveau du système d'exploitation** (conteneurs), qui se superpose souvent à la **virtualisation matérielle** (machines virtuelles) :

```
┌──────────────────────────────────────────────────────────────┐
│ Applications dans des conteneurs (regroupés en Pods)         │  ◄─ orchestrés par Kubernetes
├──────────────────────────────────────────────────────────────┤
│ Runtime de conteneurs (containerd / runc)                    │  virtualisation au niveau OS
├──────────────────────────────────────────────────────────────┤
│ Noyau Linux du nœud : namespaces + cgroups                   │  (noyau partagé par les conteneurs)
├──────────────────────────────────────────────────────────────┤
│ Nœud = machine virtuelle (EC2, Compute Engine, Azure VM…)    │  virtualisation matérielle
├──────────────────────────────────────────────────────────────┤
│ Hyperviseur (KVM, Hyper-V, ESXi)                             │
├──────────────────────────────────────────────────────────────┤
│ Serveur physique                                             │
└──────────────────────────────────────────────────────────────┘
```

- **Machine virtuelle** : l'hyperviseur virtualise le *matériel*. Chaque MV embarque son propre système d'exploitation complet (noyau compris). Isolation forte, mais lourde (Go de disque, démarrage en dizaines de secondes ou minutes).
- **Conteneur** : on virtualise le *système d'exploitation*. Tous les conteneurs d'un nœud partagent le même noyau Linux, isolés par trois mécanismes :
  - les **namespaces** isolent ce que le processus *voit* (PID, réseau, système de fichiers, utilisateurs, nom d'hôte) ;
  - les **cgroups** limitent ce qu'il peut *consommer* (CPU, mémoire, E/S) — ce sont eux qui appliquent les `requests` et `limits` des manifestes ;
  - un **système de fichiers en couches** (OverlayFS) permet de partager les couches communes des images.
- **Pod** : groupe de conteneurs partageant le même *namespace réseau* (même IP, communication par `localhost`).
- **Dans le nuage**, les nœuds Kubernetes sont en général des MV : on combine l'isolation des MV (entre locataires) et la légèreté des conteneurs (entre applications). Kubernetes ajoute lui-même une couche d'**abstraction de l'infrastructure** : l'application demande « 1 Gi de stockage » ou « un équilibreur de charge » sans connaître le fournisseur.
- **Variantes** : des runtimes « bac à sable » (Kata Containers, gVisor) placent chaque pod dans une micro-MV pour renforcer l'isolation ; à l'inverse, KubeVirt permet de gérer des MV comme des objets Kubernetes.

Dans notre étude de cas, Minikube illustre cet empilement : chacun des 3 « nœuds » est lui-même un conteneur Docker (ou une MV), à l'intérieur duquel containerd exécute les pods.

### a.7 Réseau

Le modèle réseau de Kubernetes fixe trois règles : chaque pod a **sa propre adresse IP** ; tous les pods peuvent se joindre **sans NAT**, quel que soit leur nœud (assuré par le plugin CNI) ; les pods étant éphémères, on ne les joint pas directement mais par un **Service**, dont l'IP virtuelle et le nom DNS sont stables.

### a.8 Exemple de déroulement : `kubectl apply -f deployment.yaml` (3 réplicas)

1. `kubectl` envoie le manifeste à l'**API server**, qui l'authentifie, le valide et l'enregistre dans **etcd**.
2. Le **contrôleur de Deployment** voit le nouvel objet et crée un ReplicaSet ; le **contrôleur de ReplicaSet** constate 0 pod sur 3 et crée 3 objets Pod (sans nœud).
3. Le **scheduler** voit ces pods non affectés et choisit un nœud pour chacun.
4. Le **kubelet** de chaque nœud concerné voit « ses » pods, demande à **containerd** de télécharger l'image et de démarrer les conteneurs, puis lance les sondes.
5. Quand un pod est prêt, son IP est ajoutée aux points de terminaison du Service ; **kube-proxy** met à jour les règles réseau et **CoreDNS** répond au nom du Service.
6. Si un pod ou un nœud tombe, l'état réel (2) diffère de l'état désiré (3) : la boucle recommence à l'étape 2.

Aucun composant ne donne d'ordre à un autre : chacun **réagit aux changements** qu'il observe dans l'API. C'est une architecture pilotée par les événements (voir d).

### a.9 Correspondance avec les services cités dans l'énoncé

| Service rendu | Mécanisme Kubernetes |
| --- | --- |
| Déploiements et emplacements | Deployment, StatefulSet, DaemonSet ; scheduler (affinités, *taints*, contraintes de zone) |
| Équilibrage des charges | Service + kube-proxy (interne) ; LoadBalancer / Ingress (externe) |
| Communication entre conteneurs | Réseau de pods (CNI), une IP par pod, `localhost` à l'intérieur d'un pod |
| Découverte de services | CoreDNS : `service.namespace.svc.cluster.local` |
| Mises à jour | Stratégie RollingUpdate, `kubectl rollout undo` |
| Montée en échelle | `kubectl scale`, HorizontalPodAutoscaler, Cluster Autoscaler (ajout de nœuds) |
| Stockage persistant | PersistentVolume / PersistentVolumeClaim / StorageClass (pilotes CSI) |
| Configuration et secrets | ConfigMap, Secret |
| Dysfonctionnements | Sondes liveness/readiness, recréation des pods par les contrôleurs, évacuation des nœuds en panne |

---

## b) Étude de cas : un exemple complet et exécutable

### b.1 Application

Une **API de file de tâches** déployée sur un **cluster de 3 nœuds**. Le code est dans ce dossier.

```
        client (curl / navigateur)
                 │  HTTP
                 ▼
   Service "api" (NodePort 30081) ── équilibrage de charge
        │           │           │
   ┌────┴───┐  ┌────┴───┐  ┌────┴───┐     Deployment "api" : 3 à 8 réplicas (HPA sur le CPU)
   │ api    │  │ api    │  │ api    │     un pod par nœud (topologySpreadConstraints)
   │ nœud 1 │  │ nœud 2 │  │ nœud 3 │     sondes liveness + readiness, PodDisruptionBudget
   └────┬───┘  └────┬───┘  └────┬───┘     config : ConfigMap ; mot de passe : Secret
        └───────────┼───────────┘
                    │ redis:6379 (nom DNS du Service)
                    ▼
            ┌───────────────┐              StatefulSet "redis" (1 réplica, nœud principal)
            │ redis-0       │──► PVC "donnees-redis-0" ──► volume persistant
            │ compteur+file │
            └───▲───────▲───┘
   BLPOP        │       │  longueur de la file (toutes les 5 s)
 (événements)   │       │
        ┌───────┴─────┐ └──── KEDA ──► ajuste le nombre de workers
        │ worker 0..6 │ ◄───────────── de 0 (file vide) à 6
        └─────────────┘                Deployment "worker" : consommateurs de la file
```

- `POST /taches` : l'API dépose un événement dans une file Redis et répond tout de suite (`202`). Un **worker** le consomme et écrit le résultat : interaction **événementielle**, asynchrone.
- **KEDA** (*Kubernetes Event-driven Autoscaling*) surveille la file : aucun worker ne tourne quand elle est vide, et leur nombre augmente avec le nombre d'événements en attente.
- `GET /` : incrémente un compteur de visites stocké dans Redis et renvoie le nom du pod, la version et le message de configuration.

| Fichier | Contenu | Service de l'énoncé illustré |
| --- | --- | --- |
| `app/app.py`, `app/worker.py`, `app/Dockerfile` | Code de l'API et du worker, image de conteneur | — |
| `k8s/00-namespace.yaml` | Namespace `etude-cas` | Isolation |
| `k8s/01-configmap.yaml`, `k8s/02-secret.yaml` | Paramètres et mot de passe | Configuration et secrets |
| `k8s/03-redis.yaml` | StatefulSet + `volumeClaimTemplates` + Service ; `nodeSelector` | Stockage persistant, emplacements |
| `k8s/04-api.yaml` | Deployment (3 réplicas, répartition par nœud, RollingUpdate, sondes), PodDisruptionBudget, Service NodePort | Déploiement, emplacements, équilibrage, découverte, mises à jour, dysfonctionnements |
| `k8s/05-worker.yaml` | Deployment des consommateurs | Communication, événementiel |
| `k8s/06-hpa.yaml` | HorizontalPodAutoscaler de l'API (3 à 8 pods, cible 50 % CPU) | Montée en échelle (selon la charge) |
| `k8s/07-keda-scaledobject.yaml` | ScaledObject KEDA des workers (0 à 6, selon la longueur de la file) | Montée en échelle (selon les événements) |
| `scripts/01-deploy.sh`, `02-demo.sh`, `03-cleanup.sh` | Création du cluster, déploiement, démonstration en 10 étapes, nettoyage | — |

### b.2 Exécution

Prérequis : Docker, `kubectl` et Minikube, environ 6 Go de mémoire libre et un accès Internet (images et KEDA). Les scripts ont été exécutés sous Ubuntu (WSL 2).

```bash
cd question-IV
./scripts/01-deploy.sh        # crée le cluster à 3 nœuds, installe metrics-server et KEDA, construit et déploie
./scripts/02-demo.sh          # les 10 étapes (~10 min) ; ou par exemple : ./scripts/02-demo.sh 5 7
./scripts/03-cleanup.sh       # supprime le namespace et arrête le cluster (--garder : le laisse démarré)
```

Le cluster est créé dans un **profil Minikube séparé** nommé `etude-cas` : le cluster `minikube` de la Question I n'est pas modifié. Après le déploiement, `kubectl` pointe par défaut sur le nouveau cluster ; `minikube start` redémarre celui de la Question I et y replace `kubectl`, et `minikube -p etude-cas delete` supprime le cluster à 3 nœuds.

Pour utiliser l'API depuis le poste : `kubectl --context etude-cas -n etude-cas port-forward service/api 8080:80`, puis `http://localhost:8080/`.

### b.3 Résultats obtenus

Extraits de la sortie de `./scripts/02-demo.sh` (Minikube v1.39, Kubernetes v1.37, runtime containerd, KEDA 2.21, sous Ubuntu/WSL 2). Les noms de pods changent à chaque exécution.

**Étape 1 — Déploiement et emplacements.** Le scheduler place un pod API sur chacun des 3 nœuds (contrainte de répartition) et Redis sur le nœud principal (`nodeSelector`), là où se trouve son volume.

```
NAME            STATUS   ROLES           VERSION
etude-cas       Ready    control-plane   v1.37.0
etude-cas-m02   Ready    <none>          v1.37.0
etude-cas-m03   Ready    <none>          v1.37.0

POD                    NOEUD           ETAT
api-569889b58f-klpfx   etude-cas-m02   Running
api-569889b58f-sp4ps   etude-cas-m03   Running
api-569889b58f-w49s9   etude-cas       Running

POD       NOEUD       ETAT
redis-0   etude-cas   Running
```

**Étape 2 — Découverte de services et équilibrage de charge.** Le nom `api` est résolu par le DNS du cluster vers l'IP virtuelle du Service, qui répartit 12 requêtes entre les 3 pods, situés sur 3 nœuds différents (sous-réseaux `10.244.0`, `.1` et `.2`).

```
Name:    api.etude-cas.svc.cluster.local
Address: 10.109.232.245

NAME        ADDRESSTYPE   PORTS   ENDPOINTS
api-6wdk2   IPv4          8080    10.244.1.6,10.244.2.2,10.244.0.3

      2 api-569889b58f-klpfx
      4 api-569889b58f-sp4ps
      6 api-569889b58f-w49s9
```

La répartition n'est pas parfaitement égale : kube-proxy choisit un pod **au hasard** pour chaque connexion ; elle s'équilibre sur un grand nombre de requêtes.

**Étape 3 — Configuration et secrets.** Le message vient du ConfigMap ; le Deployment ne contient qu'une *référence* au Secret. Après modification du ConfigMap et redémarrage progressif, la même image affiche le nouveau message.

```
{"message":"Bonjour depuis Kubernetes","pod":"api-74cf86c55f-ffzl9","version":"1.0","visites":65}
[{"name":"REDIS_PASSWORD","valueFrom":{"secretKeyRef":{"key":"REDIS_PASSWORD","name":"redis-secret"}}}]
configmap/app-config patched
deployment.apps/api restarted
{"message":"Configuration modifiee sans reconstruire l image","pod":"api-7ff78869c6-25n6p","version":"1.0","visites":66}
```

**Étape 4 — Communication et interaction événementielle.** Au repos, aucun worker ne tourne. L'API répond `en_attente` immédiatement ; l'arrivée des événements fait démarrer un worker, qui les traite.

```
--- Au repos, aucun worker ne tourne : 0 réplica(s)
{"etat":"en_attente","id":"52d9942c","recue_par":"api-7ff78869c6-h2k6x"}
{"etat":"en_attente","id":"c87d1cd0","recue_par":"api-7ff78869c6-4zhjp"}
{"etat":"en_attente","id":"e7e556cd","recue_par":"api-7ff78869c6-4sw5r"}

{"en_file":0,"terminees":[{"etat":"terminee","id":"e7e556cd","resultat":"COMMANDE NUMERO 3",
  "recue_par":"api-7ff78869c6-4sw5r","traitee_par":"worker-6b97659c6d-22s5l", ...}, ...]}

[worker worker-6b97659c6d-22s5l] en attente d'événements sur 'file:taches'
[worker worker-6b97659c6d-22s5l] tâche 52d9942c traitée
```

**Étape 5 — Montée en échelle pilotée par les événements (KEDA).** Une rafale de 150 événements arrive. KEDA lit la longueur de la file et fait passer les workers de 1 à 6 ; la file se vide de plus en plus vite, puis les workers reviennent à 0.

```
    en file : 148   workers : 1
    en file : 142   workers : 1
    en file : 137   workers : 1
    en file : 119   workers : 5
    en file : 89    workers : 5
    en file : 64    workers : 6
    en file : 29    workers : 6
    en file : 0     workers : 6

    worker-6b97659c6d-2sh5p : 24 tâches
    worker-6b97659c6d-cxhht : 10 tâches
    worker-6b97659c6d-fp7sf : 25 tâches
    worker-6b97659c6d-h4ptz : 25 tâches
    worker-6b97659c6d-n89cp : 44 tâches
    worker-6b97659c6d-wspl4 : 25 tâches

NAME     READY   UP-TO-DATE   AVAILABLE
worker   0/0     0            0
```

Avec un seul worker, la file baisse d'environ 1 événement par seconde ; avec 6, d'environ 6 par seconde. Le critère de mise à l'échelle n'est pas le processeur mais **le nombre d'événements en attente** : c'est le propre d'une architecture événementielle. Le retour à zéro signifie qu'au repos le traitement ne consomme aucune ressource, comme dans une offre *serverless*.

**Étape 6 — Dysfonctionnements des pods.** (a) Un pod supprimé est remplacé en quelques secondes (`AGE 7s`). (b) Un pod dont la sonde liveness échoue est redémarré par le kubelet (`RESTARTS 1`) ; il est `0/1` (non prêt) le temps de redémarrer, donc exclu du Service, pendant que les deux autres répondent.

```
pod "api-85f64bb588-h44fr" deleted
api-85f64bb588-jsv4k   1/1     Running   0          105s
api-85f64bb588-rmhxc   1/1     Running   0          7s        <- nouveau pod
api-85f64bb588-vsh25   1/1     Running   0          112s

    Pod cassé : api-85f64bb588-vsh25
api-85f64bb588-jsv4k   1/1     Running   0            2m6s
api-85f64bb588-rmhxc   1/1     Running   0            28s
api-85f64bb588-vsh25   0/1     Running   1 (2s ago)   2m13s   <- conteneur redémarré
```

**Étape 7 — Perte d'un nœud.** Le nœud `etude-cas-m03` est évacué (`kubectl drain`), comme lors d'une maintenance ou du retrait d'une machine. Ses deux pods API sont recréés sur les nœuds restants, et les 40 requêtes envoyées pendant l'opération réussissent toutes.

```
POD                    NOEUD           ETAT            (avant)
api-7675ccfd9b-64sdt   etude-cas-m02   Running
api-7675ccfd9b-v2tk6   etude-cas-m03   Running
api-7675ccfd9b-vjtpw   etude-cas-m03   Running

node/etude-cas-m03 cordoned
pod/api-7675ccfd9b-v2tk6 evicted
pod/api-7675ccfd9b-vjtpw evicted
node/etude-cas-m03 drained

etude-cas-m03   Ready,SchedulingDisabled

POD                    NOEUD           ETAT            (après)
api-7675ccfd9b-64sdt   etude-cas-m02   Running
api-7675ccfd9b-6srgp   etude-cas-m02   Running
api-7675ccfd9b-7nr9w   etude-cas       Running

     40 HTTP=200
```

Deux observations. D'abord, deux des trois pods se trouvaient sur le nœud évacué : le **PodDisruptionBudget** (`minAvailable: 2`) a obligé Kubernetes à les déplacer l'un après l'autre plutôt que de les arrêter ensemble, d'où l'absence d'erreur. Ensuite, la répartition de départ n'était pas d'un pod par nœud comme à l'étape 1 : la contrainte de répartition est déclarée souple (`ScheduleAnyway`) et les pods avaient été recréés juste avant ; c'est une préférence, pas une garantie. Une évacuation est une panne *annoncée* ; lors d'une panne brutale, Kubernetes attend par défaut environ 5 minutes avant de recréer ailleurs les pods du nœud perdu.

**Étape 8 — Stockage persistant.** Le pod Redis est détruit ; le compteur reprend à 23 et non à 1, car les données sont dans le volume et non dans le conteneur.

```
donnees-redis-0   Bound   pvc-03ce1303-...   256Mi   RWO   standard
--- Compteur avant : {... "visites":22}
pod "redis-0" deleted
--- Compteur après : {... "visites":23}
```

**Étape 9 — Mise à jour progressive et retour arrière.** 40 requêtes envoyées pendant le passage à la version 2.0 : les deux versions cohabitent et **aucune requête n'échoue**. `kubectl rollout undo` ramène ensuite la version 1.0.

```
deployment.apps/api image updated
     33 "version":"1.0"
      7 "version":"2.0"
     40 HTTP=200
deployment.apps/api rolled back
{... "version":"1.0","visites":64}
```

Lors d'un premier essai, 1 requête sur 40 échouait : un pod en cours d'arrêt recevait encore du trafic pendant un court instant. L'ajout d'un `preStop` de 5 secondes dans `k8s/04-api.yaml` (arrêt en douceur) a corrigé le problème.

**Étape 10 — Montée en échelle automatique selon la charge (HPA).** Sous charge, l'utilisation CPU passe de 1 % à 178 % de la `request` ; le HPA fait passer le Deployment de 3 à 8 pods (le maximum fixé) en moins d'une minute, et les nouveaux pods sont répartis sur les 3 nœuds.

```
NAME   REFERENCE        TARGETS         MINPODS   MAXPODS   REPLICAS
api    Deployment/api   cpu: 1%/50%     3         8         3
api    Deployment/api   cpu: 178%/50%   3         8         3
api    Deployment/api   cpu: 178%/50%   3         8         7
api    Deployment/api   cpu: 178%/50%   3         8         8
api    Deployment/api   cpu: 173%/50%   3         8         8

POD                    NOEUD
api-85f64bb588-296sk   etude-cas-m03
api-85f64bb588-b9xnb   etude-cas-m03
api-85f64bb588-d6wmd   etude-cas
api-85f64bb588-hnj2w   etude-cas-m02
api-85f64bb588-xgg9t   etude-cas
api-85f64bb588-xn2rn   etude-cas-m03
api-85f64bb588-xnwmv   etude-cas-m02
api-85f64bb588-xskmc   etude-cas-m02
```

L'utilisation reste au-dessus de la cible parce que le plafond de 8 pods est atteint : c'est le rôle de `maxReplicas` de borner le coût. Une fois la charge arrêtée, le HPA redescend à 3 pods.

### b.4 Bilan de l'étude de cas

Avec 8 fichiers de manifestes et sans aucun script d'exploitation, on obtient une application répartie sur 3 nœuds, équilibrée, configurable, persistante, qui se répare, survit au retrait d'un nœud, se met à jour sans coupure et s'adapte à la charge comme au nombre d'événements. Chacun des neuf services de l'énoncé a été observé.

Limites de l'exemple :

- les 3 « nœuds » sont des conteneurs sur une seule machine physique : la panne de cette machine emporte tout, et la répartition géographique (plusieurs zones ou régions) n'est pas représentée ;
- Redis n'est pas répliqué et son volume est local à un nœud : c'est un point de défaillance unique, et la perte du nœud principal entraînerait celle des données ;
- le Secret est en clair dans un fichier et l'accès externe passe par un NodePort au lieu d'un Ingress.

Ces choix sont acceptables pour une démonstration, pas pour la production.

---

## c) Avantages et inconvénients de Kubernetes

### Avantages

| Avantage | Explication |
| --- | --- |
| **Auto-réparation** | Un conteneur planté est redémarré, un pod disparu est recréé, les pods d'un nœud en panne sont replanifiés ailleurs, sans intervention humaine (étapes 6 et 7 de l'étude de cas). |
| **Mise à l'échelle** | Horizontale et automatique selon la charge (HPA), et jusqu'à l'ajout de nœuds (Cluster Autoscaler). Les ressources suivent la demande : on ne paie pas pour le pic en permanence. |
| **Déploiements sans interruption** | Mises à jour progressives et retour arrière en une commande ; base pour les stratégies *blue-green* et *canary*. |
| **Modèle déclaratif** | L'infrastructure est décrite dans des fichiers versionnés (Git) : déploiements reproductibles, revue de code, GitOps. |
| **Portabilité** | Même API chez tous les fournisseurs (EKS, AKS, GKE) et sur site : réduit la dépendance à un fournisseur et permet le nuage hybride ou multi-nuage. |
| **Utilisation efficace des ressources** | Le scheduler « tasse » les conteneurs sur les nœuds selon leurs `requests` ; densité bien supérieure à une application par MV. |
| **Services intégrés** | Découverte de services, équilibrage de charge, configuration, secrets et stockage sont fournis par la plateforme, de façon uniforme pour toutes les applications. |
| **Extensibilité et écosystème** | Ressources personnalisées (CRD) et opérateurs ; vaste écosystème libre (Helm, Prometheus, Istio, Argo CD, KEDA) ; standard de fait soutenu par la CNCF. |
| **Adapté aux microservices** | Chaque service est déployé, mis à l'échelle et mis à jour indépendamment. |

### Inconvénients

| Inconvénient | Explication |
| --- | --- |
| **Complexité et courbe d'apprentissage** | Beaucoup de concepts (pods, services, ingress, RBAC, CNI, CSI…) et beaucoup de YAML. Notre petit exemple demande déjà 8 fichiers de manifestes. |
| **Coût d'exploitation** | Installer, sécuriser, surveiller et mettre à niveau un cluster demande une équipe compétente. Les services gérés (EKS, AKS, GKE) réduisent cette charge mais ne la suppriment pas. |
| **Surdimensionné pour les petits projets** | Pour une application simple sur un serveur, Docker Compose ou une offre PaaS/serverless est plus rapide et moins coûteux. |
| **Surcoût en ressources** | Le plan de contrôle et les agents (kubelet, proxy, DNS, CNI, supervision) consomment CPU et mémoire avant même la première application. |
| **Sécurité à configurer** | Les réglages par défaut sont permissifs : Secrets seulement encodés en base64, réseau ouvert entre tous les pods, noyau partagé entre conteneurs. Il faut ajouter RBAC, NetworkPolicy, chiffrement d'etcd, politiques de sécurité des pods. |
| **Applications avec état plus délicates** | Kubernetes a été conçu d'abord pour le sans-état. Bases de données et files exigent StatefulSets, opérateurs et stratégie de sauvegarde ; beaucoup d'équipes préfèrent une base gérée hors cluster. |
| **Évolution rapide** | Environ trois versions par an, chacune maintenue à peu près un an, avec des API parfois retirées : les mises à niveau sont une tâche récurrente. |
| **Débogage plus difficile** | Un problème peut venir de l'application, du pod, du Service, du DNS, du CNI ou du nœud ; la supervision (journaux, métriques, traces) doit être ajoutée. |
| **Coûts infonuagiques difficiles à maîtriser** | Autoscaling mal réglé, `requests` surévaluées, équilibreurs et volumes oubliés font vite grimper la facture. |

**En résumé :** Kubernetes est rentable lorsque l'on exploite de nombreux services qui doivent rester disponibles et évoluer souvent ; il est disproportionné pour une application unique à charge stable.

---

## d) Comparaison : Kubernetes, conteneurs Docker et machines virtuelles

**Précision.** Les trois ne sont pas au même niveau. Une **MV** virtualise le matériel ; un **conteneur Docker** virtualise le système d'exploitation sur *une* machine ; **Kubernetes** ne remplace ni l'un ni l'autre : il **orchestre des conteneurs** sur un ensemble de machines, qui sont souvent des MV. On compare donc ici trois façons d'exploiter une application : MV seules, conteneurs Docker seuls (Docker Engine / Docker Compose sur un hôte), et conteneurs orchestrés par Kubernetes.

### d.1 Tableau de synthèse

| Critère | Machines virtuelles | Conteneurs Docker (sans orchestrateur) | Kubernetes |
| --- | --- | --- | --- |
| **Unité gérée** | Une machine complète avec son OS | Un conteneur sur un hôte | Un état désiré pour tout un cluster |
| **Maintenance — système** | Un OS complet *par MV* à corriger, durcir et surveiller ; les MV « dérivent » avec le temps | Un seul OS hôte ; l'application et ses dépendances sont figées dans l'image | Idem pour les nœuds, **plus** le cluster lui-même à maintenir (plan de contrôle, etcd, certificats, versions) |
| **Maintenance — mise à jour de l'application** | Modification en place ou reconstruction d'une image de MV (lourd, lent) ; outils externes (Ansible, Packer) | Reconstruire l'image et recréer le conteneur ; courte interruption ; manuel ou scripté | Automatique et progressive (`RollingUpdate`), sans interruption, retour arrière intégré |
| **Maintenance — pannes** | Haute disponibilité de l'hyperviseur : redémarre la MV, mais ne voit pas l'application | `--restart=always` redémarre le conteneur ; rien si l'hôte tombe | Auto-réparation à tous les niveaux : conteneur, pod, nœud ; sondes applicatives |
| **Scalabilité — type** | Surtout verticale (plus de CPU/RAM) ; horizontale par groupes d'autoscaling du fournisseur | Horizontale à la main (`docker compose up --scale`), limitée à **un seul hôte** | Horizontale automatique des pods (HPA) **et** des nœuds (Cluster Autoscaler) ; verticale possible (VPA) |
| **Scalabilité — rapidité** | Lente : démarrer un OS (dizaines de secondes à minutes) | Rapide : démarrer un processus (secondes ou moins) | Rapide pour les pods (secondes) ; l'ajout d'un nœud prend le temps de démarrage d'une MV |
| **Scalabilité — granularité et limites** | Grossière : toute la machine, images de plusieurs Go | Fine, mais plafonnée par la machine ; pas d'équilibrage intégré entre hôtes | Fine (par microservice) ; conçu pour de très grands clusters (jusqu'à 5 000 nœuds selon la documentation officielle) |
| **Interaction événementielle — plateforme** | Peu réactive : scripts, tâches planifiées, alarmes du fournisseur ; gestion surtout impérative | Flux d'événements (`docker events`), *healthchecks*, politiques de redémarrage ; réactions limitées à l'hôte | **Événementielle par conception** : les contrôleurs observent l'API (*watch*) et réagissent à chaque changement (boucle de réconciliation) |
| **Interaction événementielle — applications** | Possible (file de messages entre MV), mais réagir à un événement en créant une MV est lent et coûteux ; peu adapté aux charges brèves | Bien adapté pour exécuter producteurs et consommateurs, mais il faut ajuster soi-même leur nombre | Très adapté : Jobs et CronJobs, autoscaling piloté par les événements avec **KEDA** (longueur d'une file Kafka, RabbitMQ, Redis…), mise à zéro avec **Knative** |
| **Isolation / sécurité** | Forte (noyau séparé) | Plus faible (noyau partagé) | Celle des conteneurs, renforcée par Namespaces, RBAC, NetworkPolicy |
| **Complexité de départ** | Faible, technologie bien connue | Très faible | Élevée |

### d.2 Maintenance

- **MV :** la charge est dominée par le système d'exploitation. Chaque MV est un serveur à part entière à administrer (correctifs, antivirus, sauvegardes), et la configuration diverge au fil des interventions manuelles.
- **Docker :** l'image rend l'application **immuable et reproductible** : on ne corrige pas un conteneur, on le remplace. Mais sur un seul hôte, tout ce qui relève de l'exploitation (répartition, redémarrage après panne de la machine, mise à jour sans coupure) reste à la charge de l'administrateur.
- **Kubernetes :** automatise précisément ces tâches d'exploitation (étapes 6, 7 et 9 de l'étude de cas). En contrepartie, le cluster devient un système à maintenir. Le bilan est favorable quand le nombre de services est grand, défavorable pour une petite application.

### d.3 Scalabilité

- **MV :** l'unité de mise à l'échelle est lourde et lente à démarrer ; on dimensionne donc souvent pour le pic, avec du gaspillage hors pointe.
- **Docker :** un conteneur démarre vite et consomme peu, mais Docker seul ne sait ni répartir sur plusieurs machines ni décider *quand* ajouter des instances.
- **Kubernetes :** apporte la décision automatique (HPA, étape 10 ; KEDA, étape 5), la répartition entre nœuds (scheduler) et l'équilibrage de charge (Service). Deux niveaux s'emboîtent : on ajoute des **pods** en quelques secondes, et des **nœuds** (MV) quand le cluster est plein.

### d.4 Types d'interaction (event-driven)

Deux sens à distinguer :

1. **La plateforme elle-même.** Kubernetes est un système piloté par les événements : chaque création, modification ou panne produit un événement dans l'API, auquel réagissent scheduler, contrôleurs et kubelets. On *déclare* un état et le système converge. Avec des MV ou Docker seul, l'interaction est surtout **impérative** : un opérateur ou un script exécute des commandes, et rien ne corrige une dérive ultérieure.
2. **Les applications hébergées.** Une architecture événementielle (producteurs → file ou bus de messages → consommateurs) a besoin de consommateurs qui apparaissent quand des événements arrivent et disparaissent ensuite. Les conteneurs s'y prêtent par leur démarrage rapide ; Kubernetes ajoute la mise à l'échelle des consommateurs selon le nombre d'événements en attente (KEDA), jusqu'à zéro instance au repos (Knative), ce qui se rapproche du *serverless*. Les MV conviennent mal : trop lentes à démarrer et facturées même inactives.

L'étude de cas illustre les deux sens : l'API publie des tâches que les workers consomment de façon asynchrone, KEDA créant les workers à l'arrivée des événements et les supprimant ensuite (étapes 4 et 5) ; et la plateforme réagit seule aux pannes, au retrait d'un nœud et à la charge (étapes 6, 7 et 10).

### d.5 Conclusion

Les trois technologies sont **complémentaires** plutôt que concurrentes : la MV fournit l'isolation et l'infrastructure, le conteneur fournit l'empaquetage léger et portable de l'application, et Kubernetes fournit l'exploitation automatisée à grande échelle. L'architecture infonuagique la plus répandue les empile : des conteneurs, orchestrés par Kubernetes, sur des nœuds qui sont des MV.

---

## Références

- Documentation officielle de Kubernetes — *Concepts* (composants du cluster, charges de travail, services et réseau, stockage) : <https://kubernetes.io/fr/docs/concepts/>
- Kubernetes — *Considerations for large clusters* : <https://kubernetes.io/docs/setup/best-practices/cluster-large/>
- Documentation Docker — *Docker overview* : <https://docs.docker.com/get-started/docker-overview/>
- B. Burns, B. Grant, D. Oppenheimer, E. Brewer, J. Wilkes, « Borg, Omega, and Kubernetes », *ACM Queue*, 2016.
- KEDA — *Kubernetes Event-driven Autoscaling* : <https://keda.sh/>
