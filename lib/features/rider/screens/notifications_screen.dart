import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme/app_theme.dart';
import '../providers/app_notification_service.dart';

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
      _notifications = List<Map<String, dynamic>>.from(result['notifications'] ?? []);
      _loading = false;
    });
    await AppNotificationService.markAllRead();
  }

  IconData _iconFor(String type) {
    switch (type) {
      case 'friend_request':  return Icons.person_add_outlined;
      case 'friend_accepted': return Icons.people;
      case 'friend_rejected': return Icons.person_remove_outlined;
      case 'route_shared':    return Icons.route;
      case 'route_join':      return Icons.check_circle_outline;
      case 'route_declined':  return Icons.cancel_outlined;
      default:                return Icons.notifications_outlined;
    }
  }

  Color _colorFor(String type) {
    switch (type) {
      case 'friend_request':  return AppColors.orange;
      case 'friend_accepted': return AppColors.cyan;
      case 'friend_rejected': return AppColors.error;
      case 'route_shared':    return AppColors.cyan;
      case 'route_join':      return AppColors.gold;
      case 'route_declined':  return AppColors.error;
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

  void _onTap(Map<String, dynamic> n) {
    final type = n['type'] as String? ?? '';
    final data = n['data'];
    final Map<String, dynamic> extra = data is Map ? Map<String, dynamic>.from(data) : {};

    if (type == 'friend_request' || type == 'friend_accepted' || type == 'friend_rejected') {
      context.push('/rider/friends');
    } else if ((type == 'route_shared' || type == 'route_join' || type == 'route_declined') &&
        extra['route_id'] != null) {
      context.push('/rider/routes/${extra['route_id']}');
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
                  separatorBuilder: (_, __) =>
                      const Divider(color: AppColors.greyDark, height: 1, indent: 72),
                  itemBuilder: (context, i) {
                    final n    = _notifications[i];
                    final type = n['type'] as String? ?? '';
                    final read = n['read'] == true || n['read'] == 1;

                    return InkWell(
                      onTap: () => _onTap(n),
                      child: Container(
                        color: read ? Colors.transparent : AppColors.orange.withOpacity(0.05),
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              width: 44, height: 44,
                              decoration: BoxDecoration(
                                color: _colorFor(type).withOpacity(0.15),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Icon(_iconFor(type), color: _colorFor(type), size: 22),
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
                    );
                  },
                ),
    );
  }
}
