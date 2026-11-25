import 'api/api_client.dart';

/// Igual que [homeForRole], pero si la cuenta aún no ha aceptado la versión vigente de los términos y la política
/// (cuentas anteriores al registro de consentimientos, o textos nuevos) pasa antes por `/consent`.
Future<String?> entryRoute(String? role) async {
  final home = homeForRole(role);
  if (home == null) return null;
  try {
    final r = await ApiClient.dio.get('/auth/me');
    if (r.data is Map && r.data['consent_required'] == true) {
      return '/consent?next=${Uri.encodeComponent(home)}';
    }
  } catch (_) {
    // Sin conexión o error: se entra igual; el servidor volverá a avisar la próxima vez.
  }
  return home;
}

/// A dónde lleva cada perfil al entrar, o null si ese perfil aún no tiene
/// pantallas en la app (hoy, el de partner).
///
/// Un solo sitio para decidirlo: lo usan la pantalla de arranque, el login, la
/// elección de perfil y el selector de perfil de dentro de la app. Antes cada
/// uno miraba solo `rider`, y quien entraba con otro perfil se quedaba parado.
String? homeForRole(String? role) {
  switch (role) {
    case 'rider':
      return '/rider/home';
    case 'admin':
    case 'moderator':
      return '/admin/moderation';
    default:
      return null;
  }
}
