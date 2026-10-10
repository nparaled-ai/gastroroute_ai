import 'package:easy_localization/easy_localization.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'core/api/api_client.dart';
import 'core/theme/app_theme.dart';
import 'core/router.dart';
import 'core/services/push_notification_service.dart';
import 'widgets/active_tracking_bar.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await EasyLocalization.ensureInitialized();
  await Firebase.initializeApp();
  await PushNotificationService.init();

  onUnauthorized = () => router.go('/login');

  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
    ),
  );

  runApp(
    EasyLocalization(
      supportedLocales: const [
        Locale('es'),
        Locale('en'),
        Locale('fr'),
        Locale('de'),
        Locale('it'),
        Locale('pt'),
      ],
      path: 'assets/translations',
      fallbackLocale: const Locale('es'),
      child: const GastroRouteApp(),
    ),
  );
}

class GastroRouteApp extends StatelessWidget {
  const GastroRouteApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'GAStroRouteAI',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.dark,
      routerConfig: router,
      localizationsDelegates: context.localizationDelegates,
      supportedLocales: context.supportedLocales,
      locale: context.locale,

      // La barra de "ruta en curso" se monta aquí, una sola vez, por encima
      // del Navigator: así sale en todas las pantallas sin tener que
      // acordarse de añadirla a cada una (son 27 rutas).
      //
      // Va en un Column y no en un Stack a propósito: el Column encoge la app,
      // de modo que los botones flotantes, las pestañas y el final de los
      // scrolls quedan por encima de la barra sin tocar ni una pantalla. Con
      // un Stack habría que ir corrigiendo márgenes uno por uno.
      builder: (context, child) => Column(
        children: [
          Expanded(child: child ?? const SizedBox.shrink()),
          const ActiveTrackingBar(),
        ],
      ),
    );
  }
}
