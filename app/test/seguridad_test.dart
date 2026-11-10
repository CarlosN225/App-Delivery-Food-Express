import 'package:flutter_test/flutter_test.dart';
import 'package:food_express/core/seguridad/enmascarar.dart';
import 'package:food_express/core/seguridad/entorno.dart';
import 'package:food_express/core/seguridad/sanitizador.dart';

void main() {
  group('Sanitizador (Actividad 2)', () {
    test('no cambia una búsqueda normal', () {
      expect(Sanitizador.busqueda('Tacos Don Juan'), 'Tacos Don Juan');
      expect(Sanitizador.busqueda('Cafetería Ñandú'), 'Cafetería Ñandú');
    });

    test('quita XSS e inyección SQL', () {
      final xss = Sanitizador.busqueda("<script>alert('x')</script>pizza");
      expect(xss.contains('<'), isFalse);
      expect(xss.contains("'"), isFalse);
      expect(xss.contains('pizza'), isTrue);

      final sql = Sanitizador.busqueda("' OR 1=1; DROP TABLE usuarios; --");
      for (final peligroso in ["'", ';', '--', '=']) {
        expect(sql.contains(peligroso), isFalse);
      }
    });

    test('limita la longitud', () {
      expect(Sanitizador.busqueda('a' * 500).length, 60);
    });
  });

  group('Enmascarar (Actividad 2)', () {
    test('teléfono y dirección', () {
      expect(Enmascarar.telefono('5512345678'), '******5678');
      expect(Enmascarar.direccion('Calle Hidalgo 100, Col. Centro'), 'Calle Hid***');
    });

    test('teléfonos y correos dentro de un mensaje', () {
      final msg = Enmascarar.texto('Pedido de ana@correo.com, tel 55 1234 5678');
      expect(msg.contains('1234'), isFalse);
      expect(msg.contains('5678'), isTrue);
      expect(msg.contains('ana@correo.com'), isFalse);
    });
  });

  group('Entorno (Actividad 3)', () {
    test('el canal se decide con un switch', () {
      expect(Entorno.canalDesdeTexto('interno'), CanalDistribucion.interno);
      expect(Entorno.canalDesdeTexto('privado'), CanalDistribucion.privadoEnterprise);
      expect(Entorno.canalDesdeTexto('publico'), CanalDistribucion.publico);
      expect(Entorno.canalDesdeTexto('cualquier cosa'), CanalDistribucion.interno);
    });

    test('solo el canal público oculta las herramientas de demo', () {
      expect(Entorno.permiteHerramientasDemo(CanalDistribucion.interno), isTrue);
      expect(Entorno.permiteHerramientasDemo(CanalDistribucion.publico), isFalse);
    });
  });
}
