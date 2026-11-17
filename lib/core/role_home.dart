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
