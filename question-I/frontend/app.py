"""
Frontend du projet Kubernetes à deux niveaux (8CLD876 - Question I).
Application Flask qui effectue des opérations CRUD sur MySQL.
Le nom d'hôte MySQL est "mysql" : c'est le nom du Service Kubernetes (DNS interne du cluster).
"""
import os
import socket
import time

import pymysql
from flask import Flask, redirect, render_template_string, request, url_for

DB_HOST = os.getenv("DB_HOST", "mysql")
DB_PORT = int(os.getenv("DB_PORT", "3306"))
DB_USER = os.getenv("DB_USER", "root")
DB_PASSWORD = os.getenv("DB_PASSWORD", "password")
DB_NAME = os.getenv("DB_NAME", "tpdb")

app = Flask(__name__)


def connect(with_db=True):
    return pymysql.connect(
        host=DB_HOST,
        port=DB_PORT,
        user=DB_USER,
        password=DB_PASSWORD,
        database=DB_NAME if with_db else None,
        autocommit=True,
        cursorclass=pymysql.cursors.DictCursor,
        connect_timeout=5,
    )


def init_db(retries=30, delay=3):
    """MySQL peut démarrer après le frontend : on réessaie jusqu'à ce qu'il réponde."""
    for attempt in range(1, retries + 1):
        try:
            conn = connect(with_db=False)
            with conn.cursor() as cur:
                cur.execute(f"CREATE DATABASE IF NOT EXISTS `{DB_NAME}`")
                cur.execute(f"USE `{DB_NAME}`")
                cur.execute(
                    """CREATE TABLE IF NOT EXISTS etudiants (
                        id INT AUTO_INCREMENT PRIMARY KEY,
                        nom VARCHAR(100) NOT NULL,
                        programme VARCHAR(100) NOT NULL,
                        cree_le TIMESTAMP DEFAULT CURRENT_TIMESTAMP
                    )"""
                )
            conn.close()
            print(f"[init_db] Base '{DB_NAME}' prête (tentative {attempt}).", flush=True)
            return
        except pymysql.MySQLError as exc:
            print(f"[init_db] MySQL pas encore prêt ({attempt}/{retries}) : {exc}", flush=True)
            time.sleep(delay)
    raise RuntimeError("Impossible de joindre MySQL")


PAGE = """
<!doctype html>
<html lang="fr">
<head>
<meta charset="utf-8">
<title>Projet Kubernetes à deux niveaux</title>
<style>
 body{font-family:system-ui,Arial,sans-serif;max-width:820px;margin:40px auto;padding:0 16px;color:#222}
 h1{margin-bottom:4px} .info{background:#eef4ff;border-left:4px solid #3366cc;padding:10px 14px;margin:16px 0}
 table{border-collapse:collapse;width:100%} th,td{border:1px solid #ccc;padding:8px;text-align:left}
 th{background:#f3f3f3} form.inline{display:inline} input{padding:6px} button{padding:6px 12px;cursor:pointer}
 .err{background:#fde8e8;border-left:4px solid #c33;padding:10px 14px}
</style>
</head>
<body>
<h1>Gestion des étudiants (CRUD)</h1>
<p>Frontend Flask &rarr; Service <code>mysql</code> &rarr; Pod MySQL avec volume persistant</p>
<div class="info">
 Page servie par le pod : <b>{{ pod }}</b><br>
 Rafraîchissez plusieurs fois : le Service NodePort répartit les requêtes entre les 2 réplicas.
</div>
{% if error %}<div class="err">Erreur base de données : {{ error }}</div>{% endif %}

<h2>Ajouter (Create)</h2>
<form method="post" action="{{ url_for('create') }}">
 <input name="nom" placeholder="Nom" required>
 <input name="programme" placeholder="Programme" required>
 <button type="submit">Ajouter</button>
</form>

<h2>Liste (Read)</h2>
<table>
 <tr><th>ID</th><th>Nom</th><th>Programme</th><th>Créé le</th><th>Actions (Update / Delete)</th></tr>
 {% for e in etudiants %}
 <tr>
  <td>{{ e.id }}</td><td>{{ e.nom }}</td><td>{{ e.programme }}</td><td>{{ e.cree_le }}</td>
  <td>
   <form class="inline" method="post" action="{{ url_for('update', id=e.id) }}">
    <input name="programme" placeholder="Nouveau programme" required>
    <button type="submit">Modifier</button>
   </form>
   <form class="inline" method="post" action="{{ url_for('delete', id=e.id) }}">
    <button type="submit">Supprimer</button>
   </form>
  </td>
 </tr>
 {% else %}
 <tr><td colspan="5">Aucun enregistrement.</td></tr>
 {% endfor %}
</table>
</body>
</html>
"""


@app.route("/")
def index():
    etudiants, error = [], None
    try:
        conn = connect()
        with conn.cursor() as cur:
            cur.execute("SELECT * FROM etudiants ORDER BY id")
            etudiants = cur.fetchall()
        conn.close()
    except pymysql.MySQLError as exc:
        error = str(exc)
    return render_template_string(PAGE, etudiants=etudiants, error=error, pod=socket.gethostname())


@app.route("/create", methods=["POST"])
def create():
    conn = connect()
    with conn.cursor() as cur:
        cur.execute(
            "INSERT INTO etudiants (nom, programme) VALUES (%s, %s)",
            (request.form["nom"], request.form["programme"]),
        )
    conn.close()
    return redirect(url_for("index"))


@app.route("/update/<int:id>", methods=["POST"])
def update(id):
    conn = connect()
    with conn.cursor() as cur:
        cur.execute("UPDATE etudiants SET programme=%s WHERE id=%s", (request.form["programme"], id))
    conn.close()
    return redirect(url_for("index"))


@app.route("/delete/<int:id>", methods=["POST"])
def delete(id):
    conn = connect()
    with conn.cursor() as cur:
        cur.execute("DELETE FROM etudiants WHERE id=%s", (id,))
    conn.close()
    return redirect(url_for("index"))


@app.route("/health")
def health():
    return {"status": "ok", "pod": socket.gethostname()}


init_db()

if __name__ == "__main__":
    app.run(host="0.0.0.0", port=80)
