from fastapi import APIRouter

router = APIRouter()


@router.get("/health", tags=["health"])
def health_check():
    """Utilisé par les probes Kubernetes (liveness/readiness) et les load balancers."""
    """Un petit test pour voir si le GitOps marche"""
    return {"status": "ok"}