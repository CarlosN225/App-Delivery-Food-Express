from pydantic import BaseModel, EmailStr, Field, field_validator

from app.models.usuario import RolUsuario
from app.services.seguridad import sanitizar_texto


class UsuarioCreate(BaseModel):
    nombre: str = Field(min_length=2, max_length=120)
    correo: EmailStr
    contrasena: str = Field(min_length=6, max_length=72)
    rol: RolUsuario = RolUsuario.cliente

    @field_validator("nombre")
    @classmethod
    def _limpiar_nombre(cls, valor: str) -> str:
        limpio = sanitizar_texto(valor) or ""
        if len(limpio) < 2:
            raise ValueError("El nombre no es válido.")
        return limpio


class UsuarioLogin(BaseModel):
    correo: EmailStr
    contrasena: str


class UsuarioOut(BaseModel):
    id: int
    nombre: str
    correo: EmailStr
    rol: RolUsuario

    class Config:
        from_attributes = True


class Token(BaseModel):
    access_token: str
    token_type: str = "bearer"
