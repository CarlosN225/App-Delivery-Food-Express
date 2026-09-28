/// Configuración base para conectarse al backend de Food Express.
///
/// IMPORTANTE — la URL correcta depende de dónde estés corriendo la app:
///  - Flutter Web (chrome), la forma más rápida de probar:  http://127.0.0.1:8000
///  - Emulador de Android:                                  http://10.0.2.2:8000
///  - Simulador de iOS:                                     http://127.0.0.1:8000
///  - Dispositivo físico (celular real):                    http://<IP-de-tu-compu>:8000
///
/// Cambia el valor de abajo según en dónde vayas a probar.
class ApiConfig {
  static const String baseUrl = 'http://127.0.0.1:8000';
}
