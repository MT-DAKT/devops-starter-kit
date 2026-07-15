from sqlalchemy import Column, Integer, String
from pydantic import BaseModel, ConfigDict

from app.database import Base


# --- Modèle ORM (table réelle en base) ---
class UserDB(Base):
    __tablename__ = "users"

    id = Column(Integer, primary_key=True, index=True)
    name = Column(String, nullable=False)
    email = Column(String, unique=True, nullable=False)


# --- Schémas Pydantic (validation des entrées/sorties API) ---
class UserCreate(BaseModel):
    name: str
    email: str


class UserOut(BaseModel):
    id: int
    name: str
    email: str

    model_config = ConfigDict(from_attributes=True)