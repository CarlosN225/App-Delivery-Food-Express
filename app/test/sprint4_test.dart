import 'package:flutter_test/flutter_test.dart';

import 'package:food_express/features/admin/admin_service.dart';
import 'package:food_express/features/delivery/pedido_model.dart';
import 'package:food_express/features/notificaciones/notificacion_service.dart';

void main() {
  group('Rastreo del pedido (#14)', () {
    test('Seguimiento.fromJson lee posiciones, distancia y minutos', () {
      final s = Seguimiento.fromJson({
        'pedido_id': 7,
        'estado': 'en_camino',
        'restaurante': 'Pizza Palace',
        'repartidor_nombre': 'Beto',
        'restaurante_latitud': 19.601,
        'restaurante_longitud': -99.3085,
        'cliente_latitud': 19.61,
        'cliente_longitud': -99.3,
        'repartidor_latitud': 19.605,
        'repartidor_longitud': -99.305,
        'segundos_desde_ubicacion': 8,
        'distancia_restante_km': 0.84,
        'minutos_restantes': 3,
      });
      expect(s.pedidoId, 7);
      expect(s.estado, 'en_camino');
      expect(s.repartidorNombre, 'Beto');
      expect(s.repartidorLatitud, 19.605);
      expect(s.distanciaRestanteKm, 0.84);
      expect(s.minutosRestantes, 3);
    });

    test('sin repartidor asignado las posiciones quedan en null', () {
      final s = Seguimiento.fromJson({
        'pedido_id': 8,
        'estado': 'pendiente',
        'restaurante': 'Taco Manía',
        'cliente_latitud': 19.61,
        'cliente_longitud': -99.3,
      });
      expect(s.repartidorNombre, isNull);
      expect(s.repartidorLatitud, isNull);
      expect(s.segundosDesdeUbicacion, isNull);
      expect(s.minutosRestantes, isNull);
    });
  });

  group('Notificaciones (#15)', () {
    test('tiempoRelativo muestra momentos, minutos, horas y días', () {
      expect(tiempoRelativo(10), 'Hace un momento');
      expect(tiempoRelativo(5 * 60), 'Hace 5 min');
      expect(tiempoRelativo(2 * 3600), 'Hace 2 h');
      expect(tiempoRelativo(3 * 86400), 'Hace 3 d');
    });

    test('Notificacion.fromJson y copiaLeida', () {
      final n = Notificacion.fromJson({
        'id': 3,
        'pedido_id': 7,
        'titulo': 'Pedido aceptado',
        'mensaje': 'Beto aceptó tu pedido #7',
        'leida': false,
        'hace_segundos': 12,
      });
      expect(n.leida, isFalse);
      expect(n.pedidoId, 7);
      final leida = n.copiaLeida();
      expect(leida.leida, isTrue);
      expect(leida.id, n.id);
      expect(leida.titulo, n.titulo);
    });
  });

  group('Panel administrativo (#16 y #17)', () {
    test('RestauranteAdmin.fromJson acepta enteros y valores nulos', () {
      final r = RestauranteAdmin.fromJson({
        'id': 1,
        'nombre': 'Pizza Palace',
        'direccion': null,
        'categoria': 'Pizzas',
        'latitud': 19,
        'longitud': null,
        'total_productos': 4,
      });
      expect(r.latitud, 19.0);
      expect(r.longitud, isNull);
      expect(r.direccion, isNull);
      expect(r.totalProductos, 4);
    });

    test('UsuarioAdmin.fromJson y nombreRol', () {
      final u = UsuarioAdmin.fromJson({
        'id': 2,
        'nombre': 'Ana',
        'correo': 'ana@correo.com',
        'rol': 'repartidor',
        'activo': false,
      });
      expect(u.activo, isFalse);
      expect(nombreRol(u.rol), 'Repartidor');
      expect(nombreRol('administrador'), 'Administrador');
      expect(nombreRol('cliente'), 'Cliente');
    });
  });
}