import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

/// El «atrás» del sistema (el botón o el gesto del móvil) con un `PopScope`
/// dentro de una ruta de go_router, tal como está montada la pantalla de
/// resultado de una ruta: `context.push` y `PopScope(canPop: _saved)`.
void main() {
  Widget app({required bool Function() saved, required void Function() onBlocked}) {
    final router = GoRouter(
      initialLocation: '/',
      routes: [
        GoRoute(
          path: '/',
          builder: (context, state) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () => context.push('/result'),
                child: const Text('abrir'),
              ),
            ),
          ),
        ),
        GoRoute(
          path: '/result',
          builder: (context, state) => PopScope(
            canPop: saved(),
            onPopInvokedWithResult: (didPop, _) {
              if (!didPop) onBlocked();
            },
            child: const Scaffold(body: Center(child: Text('resultado'))),
          ),
        ),
      ],
    );
    return MaterialApp.router(routerConfig: router);
  }

  testWidgets('con la ruta sin guardar, el atras del sistema se intercepta', (tester) async {
    var avisos = 0;
    await tester.pumpWidget(app(saved: () => false, onBlocked: () => avisos++));

    await tester.tap(find.text('abrir'));
    await tester.pumpAndSettle();
    expect(find.text('resultado'), findsOneWidget);

    // El botón/gesto de atrás de Android.
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();

    expect(avisos, 1, reason: 'PopScope debe enterarse del atrás del sistema');
    expect(find.text('resultado'), findsOneWidget, reason: 'y la pantalla no debe cerrarse');
  });

  testWidgets('con la ruta guardada, el atras del sistema sale sin avisar', (tester) async {
    var avisos = 0;
    await tester.pumpWidget(app(saved: () => true, onBlocked: () => avisos++));

    await tester.tap(find.text('abrir'));
    await tester.pumpAndSettle();

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();

    expect(avisos, 0);
    expect(find.text('resultado'), findsNothing);
    expect(find.text('abrir'), findsOneWidget);
  });
}
