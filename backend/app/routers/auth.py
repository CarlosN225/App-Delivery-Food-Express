from fastapi import APIRouter, Depends, HTTPException, status
from fastapi.security import OAuth2PasswordBearer, OAuth2PasswordRequestForm
from sqlalchemy.orm import Session

from app.database import get_db
from app.models.usuario import Usuario
from app.schemas.usuario import UsuarioCreate, UsuarioOut, Token
from app.services.security import (
    hash_contrasena,
    verificar_contrasena,
    crear_access_token,
    decodificar_access_token,
)

router = APIRouter(prefix="/auth", tags=["Autenticación"])

# Define el esquema de seguridad para que /docs muestre el botón "Authorize"
oauth2_scheme = OAuth2PasswordBearer(tokenUrl="auth/login")


@router.post("/registro", response_model=UsuarioOut, status_code=status.HTTP_201_CREATED)
def registrar_usuario(datos: UsuarioCreate, db: Session = Depends(get_db)):
    """
    Historia #2 — Registro de clientes y repartidores.
    El rol (cliente/repartidor/administrador) se define en el body de la petición.
    """
    existente = db.query(Usuario).filter(Usuario.correo == datos.correo).first()
    if existente:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Ya existe un usuario registrado con ese correo.",
        )

    nuevo_usuario = Usuario(
        nombre=datos.nombre,
        correo=datos.correo,
        contrasena_hash=hash_contrasena(datos.contrasena),
        rol=datos.rol,
    )
    db.add(nuevo_usuario)
    db.commit()
    db.refresh(nuevo_usuario)
    return nuevo_usuario


@router.post("/login", response_model=Token)
def iniciar_sesion(
    form_data: OAuth2PasswordRequestForm = Depends(), db: Session = Depends(get_db)
):
    """
    Historia #2 — Autenticación.
    Usa el formulario estándar de OAuth2 (username = correo, password = contraseña)
    para que funcione directo con el botón "Authorize" de /docs.
    """
    usuario = db.query(Usuario).filter(Usuario.correo == form_data.username).first()

    if not usuario or not verificar_contrasena(form_data.password, usuario.contrasena_hash):
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Correo o contraseña incorrectos.",
            headers={"WWW-Authenticate": "Bearer"},
        )

    token = crear_access_token(datos={"sub": usuario.correo, "rol": usuario.rol.value})
    return {"access_token": token, "token_type": "bearer"}


def obtener_usuario_actual(
    token: str = Depends(oauth2_scheme), db: Session = Depends(get_db)
) -> Usuario:
    credenciales_invalidas = HTTPException(
        status_code=status.HTTP_401_UNAUTHORIZED,
        detail="No se pudo validar la sesión.",
        headers={"WWW-Authenticate": "Bearer"},
    )
    payload = decodificar_access_token(token)
    if payload is None:
        raise credenciales_invalidas

    correo = payload.get("sub")
    usuario = db.query(Usuario).filter(Usuario.correo == correo).first()
    if usuario is None:
        raise credenciales_invalidas
    return usuario


@router.get("/me", response_model=UsuarioOut)
def leer_usuario_actual(usuario_actual: Usuario = Depends(obtener_usuario_actual)):
    """
    Ruta protegida de prueba: si esto responde con los datos del usuario,
    significa que el registro, el login y el token JWT funcionan de punta a punta.
    """
    return usuario_actual
