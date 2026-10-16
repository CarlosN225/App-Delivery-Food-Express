from app.services import logistica as lg


def test_haversine_cero_y_simetria():
    assert lg.haversine_km(19.6, -99.3, 19.6, -99.3) == 0
    a = lg.haversine_km(19.60, -99.30, 19.61, -99.31)
    b = lg.haversine_km(19.61, -99.31, 19.60, -99.30)
    assert abs(a - b) < 1e-9
    assert 1.4 < a < 1.7  # ~1.5 km


def test_envio_minimo_y_por_distancia():
    assert lg.calcular_envio(None) == lg.ENVIO_MINIMO
    assert lg.calcular_envio(0.5) == lg.ENVIO_MINIMO
    assert lg.calcular_envio(10) == 60.0  # 20 + 4*10


def test_minutos():
    assert lg.minutos_estimados(0) == 0
    assert lg.minutos_estimados(0.01) == 1
    assert lg.minutos_estimados(25) == 60


def _p(id, rest, cli, recogido=False):
    return lg.PedidoRuta(id, f"R{id}", rest, f"C{id}", cli, recogido)


def test_ruta_recoge_antes_de_entregar():
    # El cliente 1 está muy cerca del repartidor, pero primero hay que recoger.
    origen = (19.600, -99.300)
    pedidos = [_p(1, (19.700, -99.300), (19.601, -99.300))]
    orden = lg.ordenar_paradas(origen, pedidos)
    assert [(s.pedido_id, s.tipo) for s in orden] == [(1, "recoger"), (1, "entregar")]


def test_ruta_vecino_mas_cercano_con_varios_pedidos():
    origen = (0.0, 0.0)
    pedidos = [
        _p(1, (0.0, 0.01), (0.0, 0.02)),
        _p(2, (0.0, 0.05), (0.0, 0.06)),
    ]
    orden = lg.ordenar_paradas(origen, pedidos)
    assert [(s.pedido_id, s.tipo) for s in orden] == [
        (1, "recoger"), (1, "entregar"), (2, "recoger"), (2, "entregar"),
    ]


def test_ruta_pedido_ya_recogido_solo_entrega():
    orden = lg.ordenar_paradas((0, 0), [_p(7, (1, 1), (0, 0.01), recogido=True)])
    assert [(s.pedido_id, s.tipo) for s in orden] == [(7, "entregar")]


def test_tramos_suman_totales():
    pedidos = [_p(1, (0.0, 0.01), (0.0, 0.02))]
    paradas = lg.ordenar_paradas((0.0, 0.0), pedidos)
    r = lg.construir_tramos((0.0, 0.0), paradas)
    assert len(r["tramos"]) == 2
    assert abs(r["distancia_total_km"] - sum(t["distancia_km"] for t in r["tramos"])) < 0.02
    assert r["minutos_total"] == sum(t["minutos"] for t in r["tramos"])


def test_ruta_de_pedido_segun_estado():
    p = _p(1, (0.0, 0.01), (0.0, 0.02))
    aceptado = lg.ruta_de_pedido("aceptado", (0.0, 0.0), p)
    assert [t["tipo"] for t in aceptado["tramos"]] == ["recoger", "entregar"]
    en_camino = lg.ruta_de_pedido("en_camino", (0.0, 0.015), p)
    assert [t["tipo"] for t in en_camino["tramos"]] == ["entregar"]
    assert lg.ruta_de_pedido("entregado", None, p)["tramos"] == []
    # Sin posición del repartidor, el trayecto parte del restaurante.
    sin_gps = lg.ruta_de_pedido("aceptado", None, p)
    assert [t["tipo"] for t in sin_gps["tramos"]] == ["entregar"]
