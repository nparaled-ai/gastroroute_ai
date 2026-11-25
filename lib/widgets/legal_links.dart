import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../core/theme/app_theme.dart';

/// Aviso legal, términos y política de privacidad, siempre a mano y sin necesidad de registrarse: el aviso legal debe
/// ser accesible «de forma permanente, fácil, directa y gratuita» (art. 10 de la Ley 34/2002).
class LegalLinks extends StatelessWidget {
  const LegalLinks({super.key});

  Widget _link(BuildContext context, String key, String doc) => InkWell(
        onTap: () => context.push('/legal/$doc'),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          child: Text(key.tr(),
              style: const TextStyle(color: AppColors.grey, fontSize: 12.5, decoration: TextDecoration.underline)),
        ),
      );

  @override
  Widget build(BuildContext context) {
    return Wrap(
      alignment: WrapAlignment.center,
      children: [
        _link(context, 'legal.notice', 'notice'),
        _link(context, 'legal.terms', 'terms'),
        _link(context, 'legal.privacy', 'privacy'),
      ],
    );
  }
}
