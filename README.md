# 8CLD876 — Travaux Kubernetes

**Cours :** Conception et architecture des systèmes d'infonuagique (UQAC, DIM)

| Dossier | Contenu | Point d'entrée |
| --- | --- | --- |
| [`question-I/`](question-I/) | Application web à deux niveaux (Flask + MySQL) sur Minikube, avec explication du Service NodePort | [question-I/README.md](question-I/README.md) |
| [`question-IV/`](question-IV/) | Étude de l'architecture de Kubernetes : rapport et étude de cas exécutable (cluster à 3 nœuds, HPA, KEDA) | [question-IV/RAPPORT.md](question-IV/RAPPORT.md) |

## Prérequis

Docker, `kubectl` et Minikube, sous Linux ou WSL 2. L'installation est décrite dans [question-I/README.md](question-I/README.md).

## Exécution rapide

Question I :

```bash
cd question-I
./scripts/02-deploy.sh
```

Question IV :

```bash
cd question-IV
./scripts/01-deploy.sh
./scripts/02-demo.sh
./scripts/03-cleanup.sh
```

Les deux questions utilisent des clusters Minikube distincts (`default` et `etude-cas`). Après la Question IV, `minikube start` redémarre le cluster de la Question I.

## Note

Les mots de passe présents dans les manifestes sont des valeurs de démonstration, utilisées uniquement sur un cluster local.
