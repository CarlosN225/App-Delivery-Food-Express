import 'package:flutter_test/flutter_test.dart';

import 'package:food_express/features/cart/carrito_service.dart';
import 'package:food_express/features/delivery/pedido_model.dart';
import 'package:food_express/features/restaurants/restaurant_model.dart';

Restaurante _restaurante(int id) =>
    Restaurante(id: id, nombre: 'Restaurante $id', distanciaKm: 1.0);

Producto _producto(int id, int restauranteId, double precio) => Producto(
      id: id,
      restauranteId: restauranteId,
      nombre: 'Producto $id',
      precio: precio,
    );

void main() {
  group('CarritoService', () {
    late CarritoService carrito;
    final pizza = _restaurante(1);
    final tacos = _restaurante(2);
    final pepperoni = _producto(10, 1, 120);
    final cola = _producto(11, 1, 30);
    final taco = _producto(20, 2, 25);

    setUp(() => carrito = CarritoService());

    test('empieza vacío', () {
      expect(carrito.vacio, isTrue);
      expect(carrito.subtotal, 0);
      expect(carrito.totalPiezas, 0);
      expect(carrito.restaurante, isNull);
    });

    test('suma piezas y subtotal (el ejemplo del wireframe: \$180)', () {
      carrito.agregar(pizza, pepperoni);
      carrito.agregar(pizza, cola);
      carrito.agregar(pizza, cola);
      expect(carrito.totalPiezas, 3);
      expect(carrito.cantidadDe(cola.id), 2);
      expect(carrito.subtotal, 180);
      expect(carrito.restaurante?.id, 1);
    });

    test('quitarUno y eliminar actualizan el carrito', () {
      carrito.agregar(pizza, cola);
      carrito.agregar(pizza, cola);
      carrito.quitarUno(cola.id);
      expect(carrito.cantidadDe(cola.id), 1);
      carrito.quitarUno(cola.id);
      expect(carrito.vacio, isTrue);
      expect(carrito.restaurante, isNull);

      carrito.agregar(pizza, pepperoni);
      carrito.eliminar(pepperoni.id);
      expect(carrito.vacio, isTrue);
    });

    test('solo admite un restaurante a la vez', () {
      carrito.agregar(pizza, pepperoni);
      expect(carrito.puedeAgregarDe(pizza), isTrue);
      expect(carrito.puedeAgregarDe(tacos), isFalse);

      // Si la pantalla confirma, agregar de otro restaurante vacía el anterior.
      carrito.agregar(tacos, taco);
      expect(carrito.restaurante?.id, 2);
      expect(carrito.cantidadDe(pepperoni.id), 0);
      expect(carrito.totalPiezas, 1);
    });

    test('máximo 50 piezas por producto (igual que el backend)', () {
      for (var i = 0; i < 60; i++) {
        carrito.agregar(pizza, cola);
      }
      expect(carrito.cantidadDe(cola.id), CarritoService.maxPorProducto);
    });

    test('itemsParaApi tiene el formato del backend', () {
      carrito.agregar(pizza, pepperoni);
      carrito.agregar(pizza, cola);
      carrito.agregar(pizza, cola);
      expect(carrito.itemsParaApi, [
        {'producto_id': 10, 'cantidad': 1},
        {'producto_id': 11, 'cantidad': 2},
      ]);
    });

    test('notifica a la interfaz cuando cambia', () {
      var avisos = 0;
      carrito.addListener(() => avisos++);
      carrito.agregar(pizza, pepperoni);
      carrito.quitarUno(pepperoni.id);
      expect(avisos, 2);
    });
  });

  group('Modelos del pedido', () {
    test('Pedido.fromJson lee el JSON del backend', () {
      final pedido = Pedido.fromJson({
        'id': 7,
        'cliente_id': 1,
        'repartidor_id': null,
        'restaurante_id': 3,
        'restaurante': 'Pizza Express',
        'estado': 'pendiente',
        'estado_pago': 'pendiente',
        'metodo_pago': 'mercado_pago',
        'subtotal': 180.0,
        'costo_envio': 30.0,
        'total': 210.0,
        'direccion_entrega': 'Av. Reforma 123',
        'items': [
          {
            'producto_id': 10,
            'nombre': 'Pepperoni',
            'cantidad': 1,
            'precio_unitario': 120.0,
            'importe': 120.0,
          },
        ],
      });
      expect(pedido.total, 210);
      expect(pedido.items.single.nombre, 'Pepperoni');
      expect(pedido.pagoPendiente, isTrue);
      expect(pedido.cobraEnEfectivo, isFalse);
    });

    test('RutaOptima.fromJson y textos de estado', () {
      final ruta = RutaOptima.fromJson({
        'tramos': [
          {
            'pedido_id': 1,
            'tipo': 'recoger',
            'destino': 'Pizza Express',
            'latitud': 19.6,
            'longitud': -99.3,
            'distancia_km': 1.2,
            'minutos': 3,
          },
        ],
        'distancia_total_km': 1.2,
        'minutos_total': 3,
      });
      expect(ruta.tramos.single.tipo, 'recoger');
      expect(ruta.minutosTotal, 3);
      expect(textoEstado('en_camino'), 'En camino');
    });
  });
}
