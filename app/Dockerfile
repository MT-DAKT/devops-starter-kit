# --- Étape de build : installe les dépendances ---
FROM python:3.12-slim AS builder
WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir --user -r requirements.txt

# --- Étape finale : image d'exécution allégée ---
FROM python:3.12-slim
WORKDIR /app

RUN useradd -m appuser

# On copie les packages installés directement dans le home de appuser,
# avec les bonnes permissions dès la copie (--chown)
COPY --from=builder --chown=appuser:appuser /root/.local /home/appuser/.local
COPY --chown=appuser:appuser ./app ./app

ENV PATH=/home/appuser/.local/bin:$PATH \
    PYTHONUNBUFFERED=1

EXPOSE 8000

USER appuser

CMD ["uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8000"]