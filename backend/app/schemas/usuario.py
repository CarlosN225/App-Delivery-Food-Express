from pydantic import BaseModel, EmailStr, Field

from app.models.usuario import RolUsuario


class UsuarioCreate(BaseModel):
    nombre: str = Field(min_length=2, max_length=120)
    correo: EmailStr
    contrasena: str = Field(min_length=6, max_length=72)
    rol: RolUsuario = RolUsuario.cliente


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
