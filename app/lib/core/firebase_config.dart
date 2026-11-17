/// Configuración de Firebase Authentication (servicio en la nube).
///
/// La clave web NO va en el código ni en GitHub. Se pasa al compilar:
///   flutter run -d chrome --web-port 5050 --dart-define-from-file=firebase.json
/// donde `app/firebase.json` (ignorado por git) contiene:
///   {"FIREBASE_API_KEY": "tu-clave-web"}
/// Sin la clave, la app funciona igual y solo se desactiva la recuperación
/// de contraseña por correo.
class FirebaseConfig {
  FirebaseConfig._();

  static const String apiKey = String.fromEnvironment('FIREBASE_API_KEY');

  static bool get disponible => apiKey.isNotEmpty;
}
