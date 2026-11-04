from typing import Optional

from pydantic import BaseModel, ConfigDict, Field, model_validator

from app.models.usuario import RolUsuario


class RestauranteAdminIn(BaseModel):
    """Datos para crear o editar un restaurante desde el panel administrativo."""

    nombre: str = Field(min_length=2, max_length=150)
    direccion: Optional[str] = Field(default=None, max_length=255)
    categoria: Optional[str] = Field(default=None, max_length=80)
    latitud: Optional[float] = Field(default=None, ge=-90, le=90)
    longitud: Optional[float] = Field(default=None, ge=-180, le=180)

    @model_validator(mode="after")
    def coordenadas_completas(self):
        if (self.latitud is None) != (self.longitud is None):
            raise ValueError("Manda latitud y longitud juntas, o ninguna.")
        return self


class RestauranteAdminOut(BaseModel):
    id: int
    nombre: str
    direccion: Optional[str] = None
    categoria: Optional[str] = None
    latitud: Optional[float] = None
    longitud: Optional[float] = None
    total_productos: int = 0


class UsuarioAdminOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: int
    nombre: str
    correo: str
    rol: RolUsuario
    activo: bool


class ActivoIn(BaseModel):
    activo: bool


class RolIn(BaseModel):
    rol: RolUsuario