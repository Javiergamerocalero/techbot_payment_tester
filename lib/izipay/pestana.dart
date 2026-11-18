import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../comun/bitacora.dart';
import 'cliente.dart';

/// Pestaña de Izipay: pinpad P400 por su API REST local.
///
/// Cada prueba es un botón suelto además del diagnóstico completo,
/// porque lo que hay que contestar parado al lado del equipo es en qué
/// punto se rompe la cadena: si no se llega al pinpad, si no acepta
/// las credenciales, si responde pero no cobra, o si el problema es
/// solo con el QR.
class PestanaIzipay extends StatefulWidget {
  const PestanaIzipay({super.key});

  @override
  State<PestanaIzipay> createState() => _PestanaIzipayState();
}

class _PestanaIzipayState extends State<PestanaIzipay>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  static const _kIp = 'izipay_ip';
  static const _kPuerto = 'izipay_puerto';
  static const _kUsuario = 'izipay_usuario';
  static const _kPassword = 'izipay_password';

  final _ip = TextEditingController();
  final _puerto = TextEditingController(text: '9090');
  final _usuario = TextEditingController(text: 'izipay');
  final _password = TextEditingController(text: 'izipay');
  final _monto = TextEditingController(text: '1.00');

  final _bitacora = Bitacora();

  ModoCobro _modo = ModoCobro.tarjeta;
  bool _conBin = false;
  bool _ocupado = false;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  @override
  void dispose() {
    for (final c in [_ip, _puerto, _usuario, _password, _monto]) {
      c.dispose();
    }
    _bitacora.dispose();
    super.dispose();
  }

  Future<void> _cargar() async {
    try {
      final p = await SharedPreferences.getInstance();
      setState(() {
        _ip.text = p.getString(_kIp) ?? '';
        _puerto.text = p.getString(_kPuerto) ?? '9090';
        _usuario.text = p.getString(_kUsuario) ?? 'izipay';
        _password.text = p.getString(_kPassword) ?? 'izipay';
      });
    } catch (_) {
      // Sin preferencias se arranca con los valores por defecto; no es
      // motivo para dejar al técnico sin herramienta.
    }
  }

  Future<void> _guardar() async {
    try {
      final p = await SharedPreferences.getInstance();
      await p.setString(_kIp, _ip.text.trim());
      await p.setString(_kPuerto, _puerto.text.trim());
      await p.setString(_kUsuario, _usuario.text.trim());
      await p.setString(_kPassword, _password.text);
    } catch (_) {}
  }

  void _log(String linea) {
    if (!mounted) return;
    _bitacora.escribir(linea);
  }

  Izipay? _cliente() {
    final ip = _ip.text.trim();
    if (ip.isEmpty) {
      _log('✕ Falta la IP del pinpad.');
      return null;
    }
    return Izipay(
      ip: ip,
      puerto: _puerto.text.trim().isEmpty ? '9090' : _puerto.text.trim(),
      usuario: _usuario.text.trim(),
      password: _password.text,
      alRegistrar: _log,
    );
  }

  /// Envuelve cada prueba: guarda la configuración, bloquea los
  /// botones mientras corre y deja constancia de cómo terminó. Sin el
  /// bloqueo, dos operaciones a la vez dejan el pinpad en un estado
  /// que obliga a reiniciarlo.
  Future<void> _correr(
    String titulo,
    Future<void> Function(Izipay) accion,
  ) async {
    if (_ocupado) return;
    await _guardar();
    final c = _cliente();
    if (c == null) return;
    setState(() => _ocupado = true);
    _bitacora.titulo(titulo);
    try {
      await accion(c);
    } on IzipayError catch (e) {
      _log('✕ $e');
    } catch (e) {
      _log('✕ Error inesperado: $e');
    } finally {
      if (mounted) setState(() => _ocupado = false);
    }
  }

  Future<void> _diagnosticoCompleto() =>
      _correr('Diagnóstico completo', (c) async {
        if (!await c.pingTcp()) {
          _log(
            '→ No se llega al pinpad. Revisa la IP, el puerto y que el '
            'equipo esté en la misma red.',
          );
          return;
        }
        await c.login();
        await c.test();
        _log(
          '→ Listo: el pinpad responde y acepta las credenciales. '
          'Falta probar un cobro.',
        );
      });

  Future<void> _pagar() => _correr('Pago · ${_modo.etiqueta}', (c) async {
    final monto = double.tryParse(_monto.text.trim().replaceAll(',', '.'));
    if (monto == null || monto <= 0) {
      _log('✕ Monto inválido.');
      return;
    }
    await c.cobrar(
      monto,
      modo: _modo,
      conBin: _conBin && _modo.admiteBin,
      alRecibirBin: (bin) async => _confirmarBin(bin),
    );
  });

  Future<bool> _confirmarBin(String bin) async {
    final seguir = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (c) => AlertDialog(
        title: const Text('BIN recibido'),
        content: Text('Tarjeta: $bin\n\n¿Continuar con el cobro?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Continuar'),
          ),
        ],
      ),
    );
    return seguir ?? false;
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        TextField(
          controller: _ip,
          keyboardType: TextInputType.url,
          autocorrect: false,
          decoration: const InputDecoration(
            labelText: 'IP del PinPad',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _puerto,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          decoration: const InputDecoration(
            labelText: 'Puerto',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _usuario,
                autocorrect: false,
                decoration: const InputDecoration(
                  labelText: 'Usuario',
                  border: OutlineInputBorder(),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: TextField(
                controller: _password,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: 'Password',
                  border: OutlineInputBorder(),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            _boton(
              Icons.network_check,
              'Ping TCP',
              () => _correr('Ping TCP', (c) => c.pingTcp()),
            ),
            _boton(
              Icons.key,
              'Login',
              () => _correr('Login', (c) async => c.login(forzar: true)),
            ),
            _boton(
              Icons.power_settings_new,
              'Test /test',
              () => _correr('Test /test', (c) async => c.test()),
            ),
            _boton(
              Icons.fact_check_outlined,
              'Diagnóstico completo',
              _diagnosticoCompleto,
            ),
          ],
        ),
        const SizedBox(height: 20),
        _tarjetaPago(),
        const SizedBox(height: 20),
        Align(
          alignment: Alignment.centerRight,
          child: TextButton.icon(
            onPressed: _bitacora.limpiar,
            icon: const Icon(Icons.delete_outline, size: 18),
            label: const Text('Limpiar'),
          ),
        ),
        VistaBitacora(bitacora: _bitacora, ocupado: _ocupado),
      ],
    );
  }

  Widget _boton(IconData icono, String texto, VoidCallback alPulsar) {
    return FilledButton.icon(
      onPressed: _ocupado ? null : alPulsar,
      icon: Icon(icono, size: 20),
      label: Text(texto),
    );
  }

  Widget _tarjetaPago() {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        side: BorderSide(color: Theme.of(context).dividerColor),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.credit_card, size: 20),
                const SizedBox(width: 8),
                Text(
                  'Pago',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            // Tres modos y no un interruptor de QR: el manual define
            // DOS formas distintas de cobrar con QR y se comportan
            // distinto en el pinpad, así que hay que poder probar cada
            // una por separado.
            SegmentedButton<ModoCobro>(
              segments: const [
                ButtonSegment(
                  value: ModoCobro.tarjeta,
                  label: Text('Tarjeta'),
                  icon: Icon(Icons.credit_card),
                ),
                ButtonSegment(
                  value: ModoCobro.conOpcionQr,
                  label: Text('Con opción QR'),
                  icon: Icon(Icons.splitscreen),
                ),
                ButtonSegment(
                  value: ModoCobro.qrDirecto,
                  label: Text('QR directo'),
                  icon: Icon(Icons.qr_code_2),
                ),
              ],
              selected: {_modo},
              onSelectionChanged: _ocupado
                  ? null
                  : (s) => setState(() => _modo = s.first),
            ),
            const SizedBox(height: 6),
            Text(switch (_modo) {
              ModoCobro.tarjeta =>
                'Transacción 01. Lee la tarjeta; admite consulta de BIN.',
              ModoCobro.conOpcionQr =>
                'Transacción 01 con ecr_data_adicional="0" (manual 8.1). '
                    'El pinpad deja elegir tarjeta o QR.',
              ModoCobro.qrDirecto =>
                'Transacción 67 (manual 8.2). Va directo al QR.',
            }, style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 8),
            // El BIN solo existe leyendo una tarjeta: el manual
            // prohíbe pedirlo antes de las transacciones con QR. Se
            // deshabilita en vez de dejar probar la combinación que el
            // pinpad rechaza, que parecería un fallo del QR.
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: _conBin && _modo.admiteBin,
              onChanged: (_ocupado || !_modo.admiteBin)
                  ? null
                  : (v) => setState(() => _conBin = v),
              title: const Text('Con BIN'),
              subtitle: Text(
                _modo.admiteBin
                    ? 'Pide el BIN de la tarjeta antes de cobrar'
                    : 'No aplica: el QR no admite consulta de BIN',
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _monto,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: const InputDecoration(
                      labelText: 'Monto (S/)',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF1E7E34),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 18,
                    ),
                  ),
                  onPressed: _ocupado ? null : _pagar,
                  icon: const Icon(Icons.attach_money),
                  label: const Text('Pagar'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
