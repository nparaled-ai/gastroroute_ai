import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import '../../../core/theme/app_theme.dart';

class RiderAvatar extends StatelessWidget {
  final String? avatarUrl;
  final String level;
  final double size;
  final bool showBorder;

  const RiderAvatar({
    super.key,
    this.avatarUrl,
    required this.level,
    this.size = 90,
    this.showBorder = true,
  });

  Color get _levelColor {
    switch (level) {
      case 'experto':    return AppColors.gold;
      case 'intermedio': return AppColors.cyan;
      default:           return AppColors.grey;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: AppColors.surface,
        border: showBorder ? Border.all(color: _levelColor, width: 2.5) : null,
      ),
      child: ClipOval(
        child: avatarUrl != null && avatarUrl!.isNotEmpty
            ? CachedNetworkImage(
                imageUrl: avatarUrl!,
                fit: BoxFit.cover,
                placeholder: (context, url) => _defaultAvatar(),
                errorWidget: (context, url, error) => _defaultAvatar(),
              )
            : _defaultAvatar(),
      ),
    );
  }

  Widget _defaultAvatar() {
    return Container(
      color: _levelColor.withOpacity(0.1),
      child: Icon(
        Icons.sports_motorsports, // icono de casco
        color: _levelColor,
        size: size * 0.55,
      ),
    );
  }
}
