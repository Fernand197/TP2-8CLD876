FROM python:3.12-slim

# La version est gravée dans l'image : 1.0 et 2.0 sont deux images différentes (mise à jour progressive)
ARG APP_VERSION=1.0
ENV APP_VERSION=${APP_VERSION} \
    PYTHONUNBUFFERED=1

WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt
COPY app.py worker.py ./

# Bonne pratique : ne pas exécuter le conteneur en root
RUN useradd --uid 10001 --no-create-home appuser
USER 10001

EXPOSE 8080
# Par défaut l'image lance l'API ; le Deployment "worker" remplace cette commande par "python worker.py"
CMD ["gunicorn", "--bind", "0.0.0.0:8080", "--workers", "1", "--threads", "8", "app:app"]
