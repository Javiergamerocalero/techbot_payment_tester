import 'package:flutter/material.dart';

/// La bitácora de una pestaña.
///
/// Es lo que de verdad entrega esta app: cuando algo falla en el local
/// del cliente, lo que se le manda al proveedor es este texto, con los
/// tiempos de cada paso. Por eso cada medio de pago tiene la suya y no
/// se mezclan.
class Bitacora extends ChangeNotifier {
  final _lineas = <String>[];

  List<String> get lineas => List.unmodifiable(_lineas);

  void escribir(String linea) {
    _lineas.add(linea);
    notifyListeners();
  }

  void titulo(String texto) {
    _lineas.add('');
    _lineas.add('── $texto ──');
    notifyListeners();
  }

  void limpiar() {
    _lineas.clear();
    notifyListeners();
  }

  String get texto => _lineas.join('\n');
}

/// La consola de abajo. Se desplaza sola al final: en una prueba larga
/// lo que importa es la última línea, no la primera.
class VistaBitacora extends StatefulWidget {
  const VistaBitacora({
    super.key,
    required this.bitacora,
    this.ocupado = false,
    this.alto = 320,
  });

  final Bitacora bitacora;
  final bool ocupado;
  final double alto;

  @override
  State<VistaBitacora> createState() => _VistaBitacoraState();
}

class _VistaBitacoraState extends State<VistaBitacora> {
  final _scroll = ScrollController();

  @override
  void initState() {
    super.initState();
    widget.bitacora.addListener(_alFinal);
  }

  @override
  void dispose() {
    widget.bitacora.removeListener(_alFinal);
    _scroll.dispose();
    super.dispose();
  }

  void _alFinal() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.jumpTo(_scroll.position.maxScrollExtent);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.bitacora,
      builder: (context, _) {
        final lineas = widget.bitacora.lineas;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: double.infinity,
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Row(
                children: [
                  const Icon(Icons.terminal, size: 18),
                  const SizedBox(width: 8),
                  const Text(
                    'Log',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                  const Spacer(),
                  if (widget.ocupado)
                    const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                ],
              ),
            ),
            Container(
              width: double.infinity,
              height: widget.alto,
              color: const Color(0xFF10172A),
              padding: const EdgeInsets.all(12),
              child: lineas.isEmpty
                  ? const Text(
                      'Sin actividad. Ingresa los datos y pulsa un botón.',
                      style: TextStyle(
                        color: Color(0xFF9AA4B2),
                        fontFamily: 'monospace',
                        fontSize: 13,
                      ),
                    )
                  : ListView.builder(
                      controller: _scroll,
                      itemCount: lineas.length,
                      itemBuilder: (_, i) => Text(
                        lineas[i],
                        style: TextStyle(
                          color: colorDeLinea(lineas[i]),
                          fontFamily: 'monospace',
                          fontSize: 13,
                        ),
                      ),
                    ),
            ),
          ],
        );
      },
    );
  }

  /// Verde lo que salió, rojo lo que falló, azul los encabezados. En
  /// una pantalla llena de texto es lo que permite ver de un vistazo
  /// dónde se cortó.
  static Color colorDeLinea(String l) {
    if (l.startsWith('✓')) return const Color(0xFF6EE7A8);
    if (l.startsWith('✕')) return const Color(0xFFFF8A8A);
    if (l.startsWith('──')) return const Color(0xFF7DD3FC);
    return const Color(0xFFD7DEE8);
  }
}
