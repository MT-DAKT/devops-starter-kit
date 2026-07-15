from contextlib import asynccontextmanager

from fastapi import FastAPI

from app.database import Base, engine
from app.metrics import setup_metrics
from app.routers import health, users


@asynccontextmanager
async def lifespan(app: FastAPI):
    # Création des tables au démarrage
    Base.metadata.create_all(bind=engine)
    yield


app = FastAPI(
    title="Starter Kit API",
    version="0.1.0",
    lifespan=lifespan,
)

setup_metrics(app)

app.include_router(health.router)
app.include_router(users.router, prefix="/users", tags=["users"])