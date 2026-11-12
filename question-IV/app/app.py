"""
Étude de cas Kubernetes (8CLD876 - Question IV) : API "file de tâches".

L'API (Flask) :
  - compte les visites dans Redis                      -> stockage persistant
  - publie des tâches dans une file Redis              -> interaction événementielle (event-driven)
  - lit sa configuration dans des variables d'env.     -> ConfigMap + Secret
  - expose /healthz et /ready                          -> sondes liveness / readiness (auto-réparation)
  - expose /cpu pour consommer du processeur           -> démonstration de l'autoscaling (HPA)

Le nom d'hôte "redis" est le nom du Service Kubernetes : il est résolu par le DNS du cluster.
"""
import hashlib
import json
import os
import socket
import time
import uuid

import redis
from flask import Flask, jsonify, request

VERSION = os.getenv("APP_VERSION", "dev")            # fixée dans l'image (Dockerfile)
MESSAGE = os.getenv("MESSAGE", "Bonjour")            # vient du ConfigMap
REDIS_HOST = os.getenv("REDIS_HOST", "redis")        # vient du ConfigMap (nom du Service)
REDIS_PORT = int(os.getenv("REDIS_PORT", "6379"))
REDIS_PASSWORD = os.getenv("REDIS_PASSWORD")         # vient du Secret
POD = socket.gethostname()                           # dans Kubernetes : le nom du pod

FILE_TACHES = "file:taches"
TERMINEES = "taches:terminees"

app = Flask(__name__)
db = redis.Redis(
    host=REDIS_HOST, port=REDIS_PORT, password=REDIS_PASSWORD,
    decode_responses=True, socket_timeout=3, socket_connect_timeout=3,
)
etat = {"casse": False}


@app.get("/")
def accueil():
    visites = db.incr("visites")
    return jsonify(message=MESSAGE, version=VERSION, pod=POD, visites=visites)


@app.post("/taches")
def creer_tache():
    """Producteur : dépose un événement dans la file et répond tout de suite (202)."""
    texte = (request.get_json(silent=True) or {}).get("texte", "tâche sans texte")
    id_tache = uuid.uuid4().hex[:8]
    db.hset(f"tache:{id_tache}", mapping={"etat": "en_attente", "texte": texte, "recue_par": POD})
    db.rpush(FILE_TACHES, json.dumps({"id": id_tache, "texte": texte}))
    return jsonify(id=id_tache, etat="en_attente", recue_par=POD), 202


@app.get("/taches")
def lister_taches():
    ids = db.lrange(TERMINEES, 0, 19)
    return jsonify(
        en_file=db.llen(FILE_TACHES),
        terminees=[{"id": i, **db.hgetall(f"tache:{i}")} for i in ids],
    )


@app.get("/taches/<id_tache>")
def lire_tache(id_tache):
    tache = db.hgetall(f"tache:{id_tache}")
    if not tache:
        return jsonify(erreur="tâche inconnue"), 404
    return jsonify(id=id_tache, **tache)


@app.get("/cpu")
def cpu():
    """Consomme du processeur pendant ?ms= millisecondes (pour déclencher le HPA)."""
    duree = min(int(request.args.get("ms", "200")), 2000) / 1000
    fin, bloc, tours = time.monotonic() + duree, b"x" * 1_000_000, 0
    while time.monotonic() < fin:
        hashlib.sha256(bloc).hexdigest()
        tours += 1
    return jsonify(pod=POD, tours=tours)


@app.get("/healthz")
def healthz():
    """Sonde liveness : si elle échoue, le kubelet redémarre le conteneur."""
    if etat["casse"]:
        return jsonify(status="casse", pod=POD), 500
    return jsonify(status="ok", pod=POD)


@app.get("/ready")
def ready():
    """Sonde readiness : si elle échoue, le pod est retiré du Service (plus de trafic)."""
    try:
        db.ping()
        return jsonify(status="pret", pod=POD)
    except redis.RedisError as exc:
        return jsonify(status="redis injoignable", detail=str(exc), pod=POD), 503


@app.post("/casser")
def casser():
    """Simule un blocage applicatif : /healthz répond 500 jusqu'au redémarrage du conteneur."""
    etat["casse"] = True
    return jsonify(pod=POD, info="ce pod va échouer sa sonde liveness et être redémarré")


@app.errorhandler(redis.RedisError)
def erreur_redis(exc):
    return jsonify(erreur="redis injoignable", detail=str(exc), pod=POD), 503


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=8080)
