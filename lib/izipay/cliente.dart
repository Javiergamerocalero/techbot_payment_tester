import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

/// Cliente del pinpad Izipay P400 (PMP-API REST v2.3).
///
/// Es el mismo contrato que usa el quiosco de San Fernando en
/// producción; acá va recortado a lo que necesita un diagnóstico y sin
/// nada de estado de venta. Lo que NO se cambió a propósito:
///
///  - **Las cabeceras son las mínimas**: solo `Content-Type` y, cuando
///    corresponde, el `Authorization`. Agregar `Accept` o un
///    `User-Agent` propio fue justamente lo que hacía que el pinpad
///    respondiera distinto que Postman.
///  - **El login responde `mensaje`, no `message`**, y el resultado
///    bueno es `"00"`. Leer la clave equivocada hace que un rechazo se
///    vea como un error vacío.
///  - **El monto va en céntimos**, con un mínimo de tres caracteres.
class Izipay {
  Izipay({
    required this.ip,
    required this.puerto,
    required this.usuario,
    required this.password,
    this.alRegistrar,
  });

  final String ip;
  final String puerto;
  final String usuario;
  final String password;

  /// Para que la pantalla vaya mostrando lo que pasa sin esperar al
  /// final: en una prueba en sitio, saber en qué paso se quedó vale
  /// más que el resultado.
  final void Function(String linea)? alRegistrar;

  static const appId = 'POS';
  static const monedaSoles = '604';

  // Códigos de `ecr_transaccion` (manual, pág. 7).
  static const txCompra = '01';
  static const txQrDirecto = '67';

  /// Pide el BIN sin cobrar; `9` libera el pinpad después.
  static const binPedir = '1';
  static const binLiberar = '9';

  static const esperaNormal = Duration(seconds: 30);

  /// Una compra espera a una persona: insertar la tarjeta y marcar la
  /// clave, o sacar el celular y escanear. Por eso es tan larga.
  static const esperaCompra = Duration(seconds: 120);

  String? _token;

  Uri _url(String ruta) => Uri.parse('http://$ip:$puerto/API_PPAD/$ruta');

  Map<String, String> _cabeceras({String? bearer}) => {
    'Content-Type': 'application/json',
    if (bearer != null) 'Authorization': 'Bearer $bearer',
  };

  void _log(String s) => alRegistrar?.call(s);

  /// `12.34` → `"1234"`. Mínimo tres caracteres: los dos últimos son
  /// los decimales, así que `0.10` viaja como `"010"`.
  static String montoEcr(double monto) {
    final centimos = (monto * 100).round();
    if (centimos < 0) throw ArgumentError('El monto no puede ser negativo');
    return centimos.toString().padLeft(3, '0');
  }

  // ── Pruebas ───────────────────────────────────────────────────────

  /// Abre un socket al puerto del pinpad. Separa "no llego al equipo"
  /// de "el equipo me rechaza": si esto falla, no tiene sentido mirar
  /// usuario y contraseña.
  Future<bool> pingTcp() async {
    final reloj = Stopwatch()..start();
    try {
      final s = await Socket.connect(
        ip,
        int.tryParse(puerto) ?? 9090,
        timeout: const Duration(seconds: 8),
      );
      s.destroy();
      _log(
        '✓ Ping TCP a $ip:$puerto — abierto (${reloj.elapsedMilliseconds} ms)',
      );
      return true;
    } catch (e) {
      _log(
        '✕ Ping TCP a $ip:$puerto — sin conexión (${reloj.elapsedMilliseconds} ms)',
      );
      _log('   $e');
      return false;
    }
  }

  Future<String> login({bool forzar = false}) async {
    if (!forzar && _token != null) return _token!;
    final cuerpo = jsonEncode({
      'ecr_usuario': usuario,
      'ecr_password': password,
    });
    final reloj = Stopwatch()..start();
    final http.Response r;
    try {
      r = await http
          .post(_url('login'), headers: _cabeceras(), body: cuerpo)
          .timeout(esperaNormal);
    } catch (e) {
      _log('✕ Login — no se pudo conectar (${reloj.elapsedMilliseconds} ms)');
      _log('   $e');
      throw IzipayError('No se pudo conectar al pinpad: $e');
    }

    if (r.statusCode != 200) {
      _log('✕ Login — HTTP ${r.statusCode} (${reloj.elapsedMilliseconds} ms)');
      _log('   ${r.body}');
      throw IzipayError('Login rechazado (HTTP ${r.statusCode}).');
    }

    final d = jsonDecode(r.body) as Map<String, dynamic>;
    if (d['resultado'] != '00' || d['token'] is! String) {
      // El pinpad escribe `mensaje`, no `message`.
      final motivo = d['mensaje'] ?? d['message'] ?? d['resultado'];
      _log('✕ Login — rechazado: $motivo');
      throw IzipayError('Login rechazado: $motivo');
    }

    _token = d['token'] as String;
    _log('✓ Login correcto (${reloj.elapsedMilliseconds} ms)');
    return _token!;
  }

  /// `/test`: el pinpad contesta que está vivo y listo.
  Future<bool> test() async {
    final d = await _postConToken('test', const {}, operacion: 'Test /test');
    final ok = d['response_code'] == '00';
    _log(
      ok
          ? '✓ Test /test — el pinpad responde listo'
          : '✕ Test /test — response_code=${d['response_code']}',
    );
    return ok;
  }

  // ── Cobro ─────────────────────────────────────────────────────────

  /// Cuerpo de la compra según el modo.
  ///
  /// Los dos modos con QR llevan `ecr_data_adicional` en `"0"`, que es
  /// lo que le dice al pinpad que no pida BIN. El manual (8.1 y 8.2)
  /// es explícito en que esas transacciones no deben ir precedidas de
  /// una consulta de BIN.
  static Map<String, dynamic> cuerpoCompra(double monto, ModoCobro modo) {
    final b = <String, dynamic>{
      'ecr_aplicacion': appId,
      'ecr_transaccion': modo == ModoCobro.qrDirecto ? txQrDirecto : txCompra,
      'ecr_amount': montoEcr(monto),
      'ecr_currency_code': monedaSoles,
    };
    if (modo != ModoCobro.tarjeta) {
      b['ecr_data_adicional'] = '0';
    }
    return b;
  }

  /// Cobra. Con [conBin] hace primero la consulta de BIN y espera la
  /// confirmación de [alRecibirBin]; solo aplica al modo tarjeta.
  Future<Map<String, dynamic>> cobrar(
    double monto, {
    ModoCobro modo = ModoCobro.tarjeta,
    bool conBin = false,
    Future<bool> Function(String bin)? alRecibirBin,
  }) async {
    final base = cuerpoCompra(monto, modo);
    _log(
      '→ ${modo.etiqueta}: transacción ${base['ecr_transaccion']}, '
      'monto ${base['ecr_amount']}'
      '${base.containsKey('ecr_data_adicional') ? ', ecr_data_adicional=0' : ''}',
    );

    if (conBin && modo == ModoCobro.tarjeta) {
      _log('→ Paso 1: consulta de BIN');
      final resp = await _postConToken(
        'procesarTransaccion',
        {...base, 'ecr_data_adicional3': binPedir},
        operacion: 'BIN',
        espera: esperaCompra,
      );
      if (resp['response_code'] != '00') {
        throw IzipayError(
          'Rechazo al solicitar BIN: ${resp['message'] ?? resp['response_code']}',
        );
      }
      final bin = (resp['card'] ?? '').toString();
      _log('   BIN recibido: $bin');

      final seguir = alRecibirBin == null ? true : await alRecibirBin(bin);
      if (!seguir) {
        // Liberar el pinpad: si se deja colgado tras pedir BIN, la
        // siguiente operación falla sin explicación aparente.
        _log('→ Cancelado tras el BIN: liberando el pinpad');
        await _postConToken('procesarTransaccion', {
          ...base,
          'ecr_data_adicional3': binLiberar,
        }, operacion: 'BIN liberar').catchError((_) => <String, dynamic>{});
        throw IzipayError('Compra cancelada tras la consulta de BIN');
      }
      _log('→ Paso 2: compra');
    }

    final r = await _postConToken(
      'procesarTransaccion',
      base,
      operacion: modo.etiqueta,
      espera: esperaCompra,
    );

    final rc = r['response_code']?.toString() ?? '';
    if (rc != '00') {
      final msg = r['message']?.toString().trim();
      _log('✕ ${modo.etiqueta} — rechazada (response_code=$rc)');
      throw IzipayError(
        msg != null && msg.isNotEmpty
            ? msg
            : 'Compra rechazada (response_code=$rc)',
      );
    }
    _log('✓ ${modo.etiqueta} — APROBADA');
    final ref = r['reference_number'] ?? r['approval_code'];
    if (ref != null) _log('   Referencia: $ref');
    return r;
  }

  // ── Transporte ────────────────────────────────────────────────────

  /// Hace la llamada con el token y, si el pinpad contesta 401,
  /// rehace el login una vez y reintenta: el token caduca solo y en
  /// medio de una prueba eso parecería un fallo de credenciales.
  Future<Map<String, dynamic>> _postConToken(
    String ruta,
    Map<String, dynamic> cuerpo, {
    required String operacion,
    Duration? espera,
  }) async {
    Future<http.Response> enviar(String token) => http
        .post(
          _url(ruta),
          headers: _cabeceras(bearer: token),
          body: jsonEncode(cuerpo),
        )
        .timeout(espera ?? esperaNormal);

    final reloj = Stopwatch()..start();
    var token = await login();
    http.Response r;
    try {
      r = await enviar(token);
      if (r.statusCode == 401) {
        _log('   token vencido, repitiendo login');
        token = await login(forzar: true);
        r = await enviar(token);
      }
    } catch (e) {
      _log('✕ $operacion — sin respuesta (${reloj.elapsedMilliseconds} ms)');
      _log('   $e');
      throw IzipayError('$operacion: el pinpad no respondió ($e)');
    }

    _log(
      '   $operacion → HTTP ${r.statusCode} (${reloj.elapsedMilliseconds} ms)',
    );
    if (r.statusCode != 200) {
      _log('   ${r.body}');
      throw IzipayError('$operacion: HTTP ${r.statusCode}');
    }
    try {
      return jsonDecode(r.body) as Map<String, dynamic>;
    } catch (_) {
      _log('   respuesta no entendida: ${r.body}');
      throw IzipayError('$operacion: el pinpad respondió algo inesperado');
    }
  }
}

/// Cómo se le cobra al cliente en el pinpad.
enum ModoCobro {
  /// Transacción `01`. Lee la tarjeta; admite consulta de BIN.
  tarjeta('Tarjeta'),

  /// Transacción `01` con `ecr_data_adicional="0"` (manual 8.1). El
  /// pinpad ofrece elegir entre tarjeta y QR, y se salta el BIN.
  conOpcionQr('Con opción de QR'),

  /// Transacción `67` (manual 8.2). Va directo al QR.
  qrDirecto('QR directo');

  const ModoCobro(this.etiqueta);
  final String etiqueta;

  /// El BIN solo existe leyendo una tarjeta.
  bool get admiteBin => this == ModoCobro.tarjeta;
}

class IzipayError implements Exception {
  IzipayError(this.mensaje);
  final String mensaje;
  @override
  String toString() => mensaje;
}
