"""
Migraciones mínimas para bases de datos creadas en Sprints anteriores.

`Base.metadata.create_all` crea tablas nuevas, pero no agrega columnas a una
tabla que ya existe. Esta función agrega las columnas que el Sprint 3 necesita
en `pedidos`, así no hace falta borrar la base de datos de desarrollo.
(Para producción se recomienda Alembic.)
"""

from sqlalchemy import inspect, text

COLUMNAS_PEDIDOS = {
    "subtotal": "NUMERIC(10, 2) DEFAULT 0",
    "costo_envio": "NUMERIC(10, 2) DEFAULT 0",
    "direccion_entrega": "VARCHAR(255)",
    "latitud_entrega": "FLOAT",
    "longitud_entrega": "FLOAT",
    "metodo_pago": "VARCHAR(20)",
    "estado_pago": "VARCHAR(20)",
    "mp_preference_id": "VARCHAR(120)",
    "mp_payment_id": "VARCHAR(60)",
    "fecha_actualizacion": "DATETIME",
}

ESTADOS_PEDIDO = "'pendiente','aceptado','recogido','en_camino','entregado','cancelado'"


def aplicar_migraciones(engine) -> None:
    inspector = inspect(engine)
    if "pedidos" not in inspector.get_table_names():
        return

    existentes = {c["name"] for c in inspector.get_columns("pedidos")}
    faltantes = {n: t for n, t in COLUMNAS_PEDIDOS.items() if n not in existentes}

    with engine.begin() as conexion:
        for nombre, tipo in faltantes.items():
            conexion.execute(text(f"ALTER TABLE pedidos ADD COLUMN {nombre} {tipo}"))

        if faltantes:
            # Los pedidos anteriores al Sprint 3 se tratan como efectivo contra entrega.
            conexion.execute(
                text(
                    "UPDATE pedidos SET metodo_pago = 'efectivo', "
                    "estado_pago = 'contra_entrega' WHERE estado_pago IS NULL"
                )
            )
            conexion.execute(
                text(
                    "UPDATE pedidos SET subtotal = total "
                    "WHERE subtotal IS NULL OR subtotal = 0"
                )
            )
            conexion.execute(
                text("UPDATE pedidos SET costo_envio = 0 WHERE costo_envio IS NULL")
            )

        # En MySQL `estado` es un ENUM nativo: hay que ampliar sus valores.
        if engine.dialect.name == "mysql":
            conexion.execute(
                text(
                    f"ALTER TABLE pedidos MODIFY estado "
                    f"ENUM({ESTADOS_PEDIDO}) NOT NULL DEFAULT 'pendiente'"
                )
            )
