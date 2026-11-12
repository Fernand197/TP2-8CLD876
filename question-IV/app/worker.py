"""
Consommateur d'événements (worker).

Il n'expose aucun port : il attend (BLPOP bloquant) qu'un événement arrive dans la file Redis,
le traite, puis écrit le résultat. L'API et le worker ne s'appellent jamais directement :
ils sont découplés par la file, ce qui permet de les mettre à l'échelle séparément.
"""
import hashlib
import json
import os
import signal
import socket
import time

import redis

POD = socket.gethostname()
FILE_TACHES = "file:taches"
TERMINEES = "taches:terminees"

db = redis.Redis(
    host=os.getenv("REDIS_HOST", "redis"),
    port=int(os.getenv("REDIS_PORT", "6379")),
    password=os.getenv("REDIS_PASSWORD"),
    decode_responses=True,
    socket_connect_timeout=3,
)


def traiter(tache):
    time.sleep(float(os.getenv("DUREE_TRAITEMENT", "0.5")))   # simule un travail long
    texte = tache["texte"]
    return {
        "etat": "terminee",
        "resultat": texte.upper(),
        "mots": len(texte.split()),
        "sha256": hashlib.sha256(texte.encode()).hexdigest()[:16],
        "traitee_par": POD,
    }


arret = {"demande": False}


def demander_arret(*_):
    """SIGTERM (réduction du nombre de workers) : on termine la tâche en cours avant de sortir."""
    arret["demande"] = True


def main():
    signal.signal(signal.SIGTERM, demander_arret)
    print(f"[worker {POD}] en attente d'événements sur '{FILE_TACHES}'", flush=True)
    while not arret["demande"]:
        try:
            element = db.blpop(FILE_TACHES, timeout=5)
            if element is None:
                continue
            tache = json.loads(element[1])
            db.hset(f"tache:{tache['id']}", mapping=traiter(tache))
            db.lpush(TERMINEES, tache["id"])
            db.ltrim(TERMINEES, 0, 99)
            print(f"[worker {POD}] tâche {tache['id']} traitée", flush=True)
        except redis.RedisError as exc:
            print(f"[worker {POD}] Redis injoignable, nouvel essai dans 2 s : {exc}", flush=True)
            time.sleep(2)
    print(f"[worker {POD}] arrêt propre", flush=True)


if __name__ == "__main__":
    main()
