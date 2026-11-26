import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme/app_theme.dart';
import '../providers/app_notification_service.dart';
import '../providers/route_tracking_service.dart';

class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  List<Map<String, dynamic>> _notifications = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final result = await AppNotificationService.getNotifications();
    if (!mounted) return;
    setState(() {
      _notifications = _agrupar(List<Map<String, dynamic>>.from(result['notifications'] ?? []));
      _loading = false;
    });
    await AppNotificationService.markAllRead();
  }

  /// Los avisos seguidos de la MISMA persona sobre la MISMA ruta («se ha apuntado / no puede ir / se ha
  /// apuntado») van en una sola fila: la más reciente, con «+2» al lado. Antes ocupaban tres.
  static const _deRodada = {'route_join', 'route_declined'};

  List<Map<String, dynamic>> _agrupar(List<Map<String, dynamic>> lista) {
    final out = <Map<String, dynamic>>[];
    for (final n in lista) {
      final d = n['data'];
      final prev = out.isEmpty ? null : out.last;
      final pd = prev?['data'];
      final mismo = prev != null &&
          _deRodada.contains(n['type']) && _deRodada.contains(prev['type']) &&
          d is Map && pd is Map &&
          '${d['route_id']}' == '${pd['route_id']}' && '${d['user_id']}' == '${pd['user_id']}';
      if (mismo) {
        (prev['_ids'] as List).add(n['id']);
        prev['_more'] = (prev['_more'] as int) + 1;
      } else {
        out.add({...n, '_ids': [n['id']], '_more': 0});
      }
    }
    return out;
  }

  Future<void> _deleteOne(int index) async {
    final n  = _notifications[index];
    final ids = List<int>.from((n['_ids'] as List?) ?? [n['id']]);
    setState(() => _notifications.removeAt(index));
    for (final id in ids) {
      await AppNotificationService.deleteNotification(id);
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text('notifications.deleted'.tr()),
      behavior: SnackBarBehavior.floating,
      margin: const EdgeInsets.all(16),
      duration: const Duration(seconds: 2),
    ));
  }

  Future<void> _deleteAll() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: Text('notifications.delete_all'.tr(),
            style: const TextStyle(color: AppColors.white)),
        content: Text('notifications.delete_all_confirm'.tr(),
            style: const TextStyle(color: AppColors.grey)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('common.cancel'.tr(),
                style: const TextStyle(color: AppColors.grey)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text('notifications.delete_all'.tr(),
                style: const TextStyle(color: AppColors.error)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    setState(() => _notifications.clear());
    await AppNotificationService.deleteAllNotifications();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text('notifications.deleted_all'.tr()),
      behavior: SnackBarBehavior.floating,
      margin: const EdgeInsets.all(16),
      duration: const Duration(seconds: 2),
    ));
  }

  IconData _iconFor(String type) {
    switch (type) {
      case 'friend_request':  return Icons.person_add_outlined;
      case 'friend_accepted': return Icons.people;
      case 'friend_rejected': return Icons.person_remove_outlined;
      case 'moderation_public_route': return Icons.public;
      case 'moderation_report': return Icons.flag_outlined;
      case 'report_received':
      case 'report_dismissed':
      case 'report_actioned': return Icons.outlined_flag;
      case 'content_hidden': return Icons.visibility_off_outlined;
      case 'content_restored': return Icons.visibility_outlined;
      case 'moderation_warning': return Icons.report_gmailerrorred;
      case 'route_shared':    return Icons.group_outlined;      // de un AMIGO
      case 'route_shared_public': return Icons.public;          // de alguien de tu ZONA
      case 'route_join':      return Icons.check_circle_outline;
      case 'route_declined':  return Icons.cancel_outlined;
      case 'route_departure': return Icons.alarm;
      case 'tracking_auto_closed': return Icons.flag_outlined;
      default:                return Icons.notifications_outlined;
    }
  }

  Color _colorFor(String type) {
    switch (type) {
      case 'friend_request':  return AppColors.orange;
      case 'friend_accepted': return AppColors.cyan;
      case 'friend_rejected': return AppColors.error;
      case 'moderation_public_route': return AppColors.gold;
      case 'moderation_report': return AppColors.orange;
      case 'content_hidden': return AppColors.error;
      case 'content_restored': return AppColors.cyan;
      case 'moderation_warning': return AppColors.error;
      case 'route_shared':    return AppColors.cyan;
      case 'route_shared_public': return AppColors.gold;
      case 'route_join':      return AppColors.gold;
      case 'route_declined':  return AppColors.error;
      case 'route_departure': return AppColors.orange;
      case 'tracking_auto_closed': return AppColors.gold;
      default:                return AppColors.grey;
    }
  }

  String _timeAgo(String? createdAt) {
    if (createdAt == null) return '';
    final dt = DateTime.tryParse(createdAt);
    if (dt == null) return '';
    final diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 1)  return 'notifications.now'.tr();
    if (diff.inMinutes < 60) return 'notifications.minutes_ago'.tr(namedArgs: {'n': '${diff.inMinutes}'});
    if (diff.inHours < 24)   return 'notifications.hours_ago'.tr(namedArgs: {'n': '${diff.inHours}'});
    if (diff.inDays < 7)     return 'notifications.days_ago'.tr(namedArgs: {'n': '${diff.inDays}'});
    return '${dt.day}/${dt.month}/${dt.year}';
  }

  /// A dónde lleva cada notificación al tocarla.
  ///
  /// Si aquí falta un tipo, la notificación se queda muerta: se ve en la lista
  /// pero no hace nada al pulsarla, sin ningún aviso. Al añadir un tipo nuevo
  /// en el servidor hay que darlo de alta también aquí y en [_iconFor] y
  /// [_colorFor], o sale con la campana gris genérica.
  Future<void> _onTap(Map<String, dynamic> n) async {
    final type = n['type'] as String? ?? '';
    final data = n['data'];
    final Map<String, dynamic> extra = data is Map ? Map<String, dynamic>.from(data) : {};

    if (type == 'friend_request' || type == 'friend_accepted' || type == 'friend_rejected') {
      // Pedida → Recibidas (para aceptarla); aceptada → Amigos; rechazada → Enviadas (ya no está).
      final tab = type == 'friend_request' ? 1 : (type == 'friend_rejected' ? 2 : 0);
      context.push('/rider/friends', extra: {'tab': tab});
      return;
    }

    // Aviso a moderación: hay denuncias por revisar.
    if (type == 'moderation_report') {
      context.push('/admin/moderation/reports');
      return;
    }

    // Aviso a moderación: alguien ha publicado una ruta para todos. Lleva a verla (solo lectura) y a su autor.
    if (type == 'moderation_public_route' && extra['route_id'] != null) {
      context.push('/admin/moderation/public-routes/${extra['route_id']}');
      return;
    }

    // Todo lo que apunta a una ruta abre su detalle, incluido el aviso de
    // salida, que es donde está el botón de iniciar el tracking.
    if (extra['route_id'] != null &&
        (type == 'route_shared' ||
            type == 'route_join' ||
            type == 'route_declined' ||
            type == 'route_departure')) {
      context.push('/rider/routes/${extra['route_id']}');
      return;
    }

    // Ruta cerrada sola a las 24h: lleva a su resumen. El resumen necesita los
    // datos del tracking, así que hay que pedirlos antes de navegar.
    if (type == 'tracking_auto_closed' && extra['tracking_id'] != null) {
      final id = int.tryParse('${extra['tracking_id']}');
      if (id == null) return;

      final summary = await RouteTrackingService.summary(id);
      if (!mounted) return;

      if (summary == null) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('notifications.open_failed'.tr()),
          backgroundColor: AppColors.error,
        ));
        return;
      }

      context.push('/rider/summary', extra: summary);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        elevation: 0,
        title: Text('notifications.title'.tr(),
            style: const TextStyle(color: AppColors.white, fontWeight: FontWeight.w700)),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios, color: AppColors.white),
          onPressed: () => context.pop(),
        ),
        actions: [
          // Con texto: un icono suelto de papelera no decía qué iba a borrar. Pide confirmación (_deleteAll).
          if (_notifications.isNotEmpty)
            TextButton.icon(
              icon: const Icon(Icons.delete_sweep_outlined, color: AppColors.grey, size: 20),
              label: Text('notifications.delete_all'.tr(),
                  style: const TextStyle(color: AppColors.grey, fontSize: 13)),
              onPressed: _deleteAll,
            ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: AppColors.orange))
          : _notifications.isEmpty
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.notifications_none, color: AppColors.greyDark, size: 64),
                      const SizedBox(height: 16),
                      Text('notifications.empty'.tr(),
                          style: const TextStyle(color: AppColors.grey, fontSize: 16)),
                    ],
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  itemCount: _notifications.length,
                  separatorBuilder: (_, _) =>
                      const Divider(color: AppColors.greyDark, height: 1, indent: 72),
                  itemBuilder: (context, i) {
                    final n    = _notifications[i];
                    final type = n['type'] as String? ?? '';
                    final read = n['read'] == true || n['read'] == 1;
                    // Una ruta compartida por un AMIGO y una publicada por alguien de tu ZONA no son lo mismo: icono
                    // y color distintos (el texto también lo dice).
                    final nData = n['data'];
                    final look = (type == 'route_shared' && nData is Map && nData['type'] == 'public')
                        ? 'route_shared_public'
                        : type;

                    return Dismissible(
                      key: ValueKey(n['id']),
                      direction: DismissDirection.endToStart,
                      background: Container(
                        alignment: Alignment.centerRight,
                        padding: const EdgeInsets.only(right: 20),
                        color: AppColors.error,
                        child: const Icon(Icons.delete_outline, color: Colors.white, size: 26),
                      ),
                      onDismissed: (_) => _deleteOne(i),
                      child: InkWell(
                        onTap: () => _onTap(n),
                        child: Container(
                          color: read ? Colors.transparent : AppColors.orange.withValues(alpha: 0.05),
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Container(
                                width: 44, height: 44,
                                decoration: BoxDecoration(
                                  color: _colorFor(look).withValues(alpha: 0.15),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Icon(_iconFor(look), color: _colorFor(look), size: 22),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Expanded(
                                          child: Text(
                                            n['title'] ?? '',
                                            style: TextStyle(
                                              color: AppColors.white,
                                              fontSize: 14,
                                              fontWeight: read ? FontWeight.w500 : FontWeight.w700,
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        if ((n['_more'] as int? ?? 0) > 0)
                                          Padding(
                                            padding: const EdgeInsets.only(right: 6),
                                            child: Text('+${n['_more']}',
                                                style: const TextStyle(color: AppColors.orange, fontSize: 11, fontWeight: FontWeight.w700)),
                                          ),
                                        Text(
                                          _timeAgo(n['created_at'] as String?),
                                          style: const TextStyle(color: AppColors.grey, fontSize: 11),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 3),
                                    Text(
                                      n['body'] ?? '',
                                      style: const TextStyle(color: AppColors.grey, fontSize: 13),
                                    ),
                                  ],
                                ),
                              ),
                              if (!read)
                                const Padding(
                                  padding: EdgeInsets.only(left: 8, top: 4),
                                  child: CircleAvatar(
                                    radius: 4,
                                    backgroundColor: AppColors.orange,
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
    );
  }
}
