import time

from fastapi import FastAPI, Request
from prometheus_client import Counter, Histogram, make_asgi_app

REQUEST_COUNT = Counter(
    "http_requests_total",
    "Nombre total de requêtes HTTP",
    ["method", "path", "status"],
)

REQUEST_LATENCY = Histogram(
    "http_request_duration_seconds",
    "Durée des requêtes HTTP en secondes",
    ["method", "path"],
)


def setup_metrics(app: FastAPI) -> None:
    """Monte /metrics et instrumente chaque requête via un middleware."""
    app.mount("/metrics", make_asgi_app())

    @app.middleware("http")
    async def track_requests(request: Request, call_next):
        start = time.perf_counter()
        response = await call_next(request)
        duration = time.perf_counter() - start

        # On utilise le template de route ("/users/{user_id}") et non l'URL réelle
        # ("/users/42") pour éviter l'explosion de cardinalité vue au chapitre 9.
        # Si aucune route ne correspond (404), on regroupe tout sous "unmatched"
        # plutôt que d'utiliser le chemin brut — sinon chaque tentative de bot
        # créerait sa propre série temporelle.
        route = request.scope.get("route")
        path = route.path if route else "unmatched"

        REQUEST_COUNT.labels(request.method, path, response.status_code).inc()
        REQUEST_LATENCY.labels(request.method, path).observe(duration)

        return response
