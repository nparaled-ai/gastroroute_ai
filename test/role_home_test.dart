import 'package:flutter_test/flutter_test.dart';
import 'package:gastroroute_ai/core/role_home.dart';

void main() {
  test('cada perfil va a su pantalla', () {
    expect(homeForRole('rider'), '/rider/home');
    expect(homeForRole('admin'), '/admin/moderation');
    expect(homeForRole('moderator'), '/admin/moderation');
  });

  test('un perfil sin pantallas (partner) o desconocido no lleva a ninguna', () {
    expect(homeForRole('partner'), isNull);
    expect(homeForRole(null), isNull);
    expect(homeForRole('otro'), isNull);
  });
}
