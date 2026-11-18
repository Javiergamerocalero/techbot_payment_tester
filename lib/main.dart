import 'package:flutter/material.dart';

import 'izipay/pestana.dart';

/// Banco de pruebas de los medios de pago de TECHBOT.
///
/// Una pestaña por medio de pago. Sirve para contestar, parado al lado
/// del equipo en el local del cliente, en qué punto se rompe la
/// cadena: si no se llega al terminal, si no acepta las credenciales,
/// si responde pero no cobra. Cada pestaña deja su propia bitácora con
/// tiempos, y ese texto es lo que se le manda al proveedor cuando hay
/// que reclamar.
///
/// **Para agregar un medio de pago** (Niubiz, Openpay, …): se crea
/// `lib/<medio>/cliente.dart` con el cliente y `lib/<medio>/pestana.dart`
/// con la pantalla, y se añade una entrada a [_pestanas]. La bitácora
/// y su vista ya son compartidas, así que no hay que reimplementarlas.
/// Las claves de preferencias llevan el medio por delante
/// (`izipay_ip`, …) para que dos pestañas no se pisen la configuración.
void main() {
  runApp(const PaymentTesterApp());
}

/// Una pestaña del banco de pruebas.
class _Pestana {
  const _Pestana(this.nombre, this.icono, this.vista);
  final String nombre;
  final IconData icono;
  final Widget vista;
}

const _pestanas = <_Pestana>[
  _Pestana('Izipay', Icons.credit_card, PestanaIzipay()),
  // Próximamente: Niubiz, Openpay.
];

class PaymentTesterApp extends StatelessWidget {
  const PaymentTesterApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'TECHBOT Payment Tester',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorSchemeSeed: const Color(0xFF2B5C9B),
      ),
      home: const _Armazon(),
    );
  }
}

class _Armazon extends StatelessWidget {
  const _Armazon();

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: _pestanas.length,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('TECHBOT Payment Tester'),
          // Con un solo medio de pago la barra de pestañas sobra y
          // quita alto de pantalla; aparece sola cuando haya más.
          bottom: _pestanas.length < 2
              ? null
              : TabBar(
                  tabs: [
                    for (final p in _pestanas)
                      Tab(icon: Icon(p.icono), text: p.nombre),
                  ],
                ),
        ),
        body: SafeArea(
          child: TabBarView(
            // Las pruebas son largas y con el terminal esperando: al
            // cambiar de pestaña no se puede descartar lo que ya se
            // escribió ni la bitácora de la prueba en curso.
            physics: const NeverScrollableScrollPhysics(),
            children: [for (final p in _pestanas) p.vista],
          ),
        ),
      ),
    );
  }
}
