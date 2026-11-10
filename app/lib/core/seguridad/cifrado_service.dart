import 'dart:convert';

import 'package:encrypt/encrypt.dart' as enc;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'registro.dart';

/// Criptografía simétrica local (Actividad 1): cifra datos sensibles, como el
/// token de sesión (JWT) del usuario, con AES-256 en modo GCM.
///
///  - AES-256-GCM: cifra y además detecta si alguien alteró el texto cifrado.
///  - Cada cifrado usa un IV (vector de inicialización) aleatorio de 12 bytes.
///  - La llave de 32 bytes se genera una sola vez por instalación. En Android
///    e iOS se guarda en el almacén seguro del sistema (Keystore / Keychain).
///    En web ese almacén no siempre existe, y entonces se guarda en el
///    almacenamiento local del navegador (protege menos; es una limitación
///    conocida y se documenta).
///
/// Formato guardado:  v1:<IV en base64>:<texto cifrado en base64>
class CifradoService {
  CifradoService._();

  static const _clave = 'food_express_llave_aes';
  static const _prefijo = 'v1:';
  static const _almacen = FlutterSecureStorage();

  static enc.Key? _llaveEnMemoria;

  static bool estaCifrado(String valor) => valor.startsWith(_prefijo);

  static Future<enc.Key> _obtenerLlave() async {
    if (_llaveEnMemoria != null) return _llaveEnMemoria!;

    String? guardada;
    try {
      guardada = await _almacen.read(key: _clave);
    } catch (_) {}
    if (guardada == null) {
      try {
        guardada = (await SharedPreferences.getInstance()).getString(_clave);
      } catch (_) {}
    }

    if (guardada != null) {
      return _llaveEnMemoria = enc.Key.fromBase64(guardada);
    }

    // Primera vez: se genera una llave aleatoria de 256 bits.
    final nueva = enc.Key.fromSecureRandom(32);
    var guardadaSegura = false;
    try {
      await _almacen.write(key: _clave, value: nueva.base64);
      guardadaSegura = true;
    } catch (_) {}
    if (!guardadaSegura) {
      try {
        await (await SharedPreferences.getInstance())
            .setString(_clave, nueva.base64);
      } catch (_) {}
    }
    Registro.info('Llave AES generada (256 bits).');
    return _llaveEnMemoria = nueva;
  }

  static enc.Encrypter _cifrador(enc.Key llave) =>
      enc.Encrypter(enc.AES(llave, mode: enc.AESMode.gcm));

  /// Texto plano -> v1:<iv>:<cifrado>
  static Future<String> cifrar(String textoPlano) async {
    final llave = await _obtenerLlave();
    final iv = enc.IV.fromSecureRandom(12);
    final cifrado = _cifrador(llave).encrypt(textoPlano, iv: iv);
    return '$_prefijo${iv.base64}:${cifrado.base64}';
  }

  /// v1:<iv>:<cifrado> -> texto plano. Devuelve null si el dato fue alterado
  /// o la llave no coincide (por ejemplo, si se borraron los datos del navegador).
  static Future<String?> descifrar(String guardado) async {
    if (!estaCifrado(guardado)) return null;
    try {
      final partes = guardado.substring(_prefijo.length).split(':');
      if (partes.length != 2) return null;
      final iv = enc.IV.fromBase64(partes[0]);
      final cifrado = enc.Encrypted(base64Decode(partes[1]));
      return _cifrador(await _obtenerLlave()).decrypt(cifrado, iv: iv);
    } catch (e) {
      Registro.aviso('No se pudo descifrar el dato guardado: $e');
      return null;
    }
  }
}
