import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../core/theme/app_theme.dart';
import '../../../widgets/rider_avatar.dart';
import '../providers/friendship_service.dart';

class FriendsScreen extends StatefulWidget {
  const FriendsScreen({super.key});

  @override
  State<FriendsScreen> createState() => _FriendsScreenState();
}

class _FriendsScreenState extends State<FriendsScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;

  List<Map<String, dynamic>> _friends   = [];
  List<Map<String, dynamic>> _received  = [];
  List<Map<String, dynamic>> _sent      = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _loadAll();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadAll() async {
    setState(() => _loading = true);
    final results = await Future.wait([
      FriendshipService.getFriends(),
      FriendshipService.getPendingReceived(),
      FriendshipService.getPendingSent(),
    ]);
    if (!mounted) return;
    setState(() {
      _friends  = List<Map<String, dynamic>>.from(results[0]['friends'] ?? []);
      _received = List<Map<String, dynamic>>.from(results[1]['requests'] ?? []);
      _sent     = List<Map<String, dynamic>>.from(results[2]['requests'] ?? []);
      _loading  = false;
    });
    await _markNotificationsAsSeen();
  }

  Future<void> _markNotificationsAsSeen() async {
    final notified = _sent.where((s) =>
        s['status'] == 'accepted' || s['status'] == 'rejected').toList();
    if (notified.isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    final seenIds = prefs.getStringList('seen_accepted_requests') ?? [];
    for (final a in notified) {
      final id = '${a['friendship_id']}';
      if (!seenIds.contains(id)) seenIds.add(id);
    }
    await prefs.setStringList('seen_accepted_requests', seenIds);
  }

  Future<void> _accept(int friendshipId) async {
    await FriendshipService.accept(friendshipId);
    _loadAll();
  }

  Future<void> _reject(int friendshipId) async {
    await FriendshipService.reject(friendshipId);
    _loadAll();
  }

  Future<void> _unfriend(int friendUserId, String name) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: Text('friends_screen.remove_title'.tr(), style: const TextStyle(color: AppColors.white)),
        content: Text('friends_screen.remove_confirm'.tr(namedArgs: {'name': name}), style: const TextStyle(color: AppColors.grey)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false),
              child: Text('common.cancel'.tr(), style: const TextStyle(color: AppColors.grey))),
          TextButton(onPressed: () => Navigator.pop(ctx, true),
              child: Text('common.delete'.tr(), style: const TextStyle(color: AppColors.error))),
        ],
      ),
    );
    if (confirm == true) {
      await FriendshipService.unfriend(friendUserId);
      _loadAll();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios, color: AppColors.white),
          onPressed: () => context.pop(),
        ),
        title: Text('friends_screen.title'.tr(), style: const TextStyle(color: AppColors.white, fontWeight: FontWeight.w700)),
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: AppColors.orange,
          labelColor: AppColors.orange,
          unselectedLabelColor: AppColors.grey,
          tabs: [
            Tab(text: 'friends_screen.tab_friends'.tr(args: ['${_friends.length}'])),
            Tab(
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Text('friends_screen.tab_received'.tr()),
                if (_received.isNotEmpty) ...[
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(color: AppColors.error, borderRadius: BorderRadius.circular(10)),
                    child: Text('${_received.length}', style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w700)),
                  ),
                ],
              ]),
            ),
            Tab(text: 'friends_screen.tab_sent'.tr(args: ['${_sent.length}'])),
          ],
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: AppColors.orange))
          : TabBarView(
              controller: _tabController,
              children: [
                _buildFriendsList(),
                _buildReceivedList(),
                _buildSentList(),
              ],
            ),
    );
  }

  Widget _buildFriendsList() {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
          child: GestureDetector(
            onTap: () async {
              await context.push('/rider/friends/search');
              _loadAll();
            },
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 14),
              decoration: BoxDecoration(
                gradient: LinearGradient(colors: [
                  AppColors.orange.withOpacity(0.2),
                  AppColors.cyan.withOpacity(0.1),
                ]),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: AppColors.orange.withOpacity(0.5)),
              ),
              child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                const Icon(Icons.person_search_outlined, color: AppColors.orange, size: 22),
                const SizedBox(width: 10),
                Text('friends_screen.search_riders'.tr(), style: const TextStyle(color: AppColors.orange, fontSize: 15, fontWeight: FontWeight.w700)),
              ]),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Expanded(
          child: _friends.isEmpty
              ? _buildEmptyFriends()
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: _friends.length,
                  itemBuilder: (context, index) {
                    final f = _friends[index];
                    return _FriendCard(
                      friend: f,
                      trailing: IconButton(
                        icon: const Icon(Icons.person_remove_outlined, color: AppColors.error, size: 20),
                        onPressed: () => _unfriend(f['user_id'], '${f['first_name']} ${f['last_name']}'),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildEmptyFriends() {
    return Center(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        const Icon(Icons.people_outline, color: AppColors.greyDark, size: 64),
        const SizedBox(height: 16),
        Text('friends_screen.empty'.tr(),
            textAlign: TextAlign.center,
            style: const TextStyle(color: AppColors.grey, fontSize: 14, height: 1.5)),
      ]),
    );
  }

  Widget _buildReceivedList() {
    if (_received.isEmpty) {
      return _buildEmpty('friends_screen.no_pending'.tr(), Icons.mail_outline);
    }
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _received.length,
      itemBuilder: (context, index) {
        final r = _received[index];
        return _FriendCardWithActions(
          friend: r,
          onAccept: () => _accept(r['friendship_id']),
          onReject: () => _reject(r['friendship_id']),
        );
      },
    );
  }

  Widget _buildSentList() {
    if (_sent.isEmpty) {
      return _buildEmpty('friends_screen.no_sent'.tr(), Icons.send_outlined);
    }
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _sent.length,
      itemBuilder: (context, index) {
        final s      = _sent[index];
        final status = s['status'] ?? 'pending';

        Widget badge;
        if (status == 'accepted') {
          badge = Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: Colors.green.withOpacity(0.15),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.green.withOpacity(0.4)),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              const Icon(Icons.check_circle, color: Colors.green, size: 14),
              const SizedBox(width: 4),
              Text('friends_screen.accepted'.tr(), style: const TextStyle(color: Colors.green, fontSize: 11, fontWeight: FontWeight.w700)),
            ]),
          );
        } else if (status == 'rejected') {
          badge = Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: AppColors.error.withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppColors.error.withOpacity(0.4)),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              const Icon(Icons.cancel_outlined, color: AppColors.error, size: 14),
              const SizedBox(width: 4),
              Text('friends_screen.rejected'.tr(), style: const TextStyle(color: AppColors.error, fontSize: 11, fontWeight: FontWeight.w700)),
            ]),
          );
        } else {
          badge = Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: AppColors.gold.withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppColors.gold.withOpacity(0.3)),
            ),
            child: Text('friends_screen.pending_status'.tr(), style: const TextStyle(color: AppColors.gold, fontSize: 11)),
          );
        }

        return _FriendCard(friend: s, trailing: badge);
      },
    );
  }

  Widget _buildEmpty(String text, IconData icon) {
    return Center(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, color: AppColors.greyDark, size: 64),
        const SizedBox(height: 16),
        Text(text, textAlign: TextAlign.center, style: const TextStyle(color: AppColors.grey, fontSize: 14, height: 1.5)),
        const SizedBox(height: 24),
        ElevatedButton.icon(
          onPressed: () async { await context.push('/rider/friends/search'); _loadAll(); },
          icon: const Icon(Icons.person_search_outlined, size: 18),
          label: Text('friends_screen.search_riders'.tr()),
        ),
      ]),
    );
  }
}

class _FriendCardWithActions extends StatelessWidget {
  final Map<String, dynamic> friend;
  final VoidCallback onAccept;
  final VoidCallback onReject;
  const _FriendCardWithActions({required this.friend, required this.onAccept, required this.onReject});

  String _flag(String? lang) {
    switch (lang) {
      case 'en': return '🇬🇧';
      case 'fr': return '🇫🇷';
      case 'de': return '🇩🇪';
      case 'it': return '🇮🇹';
      case 'pt': return '🇵🇹';
      default:   return '🇪🇸';
    }
  }

  Color _levelColor(String? level) {
    switch (level) {
      case 'experto':    return AppColors.gold;
      case 'intermedio': return AppColors.cyan;
      default:           return AppColors.grey;
    }
  }

  String _levelLabel(String? level) {
    switch (level) {
      case 'experto':    return 'EXPERTO';
      case 'intermedio': return 'INTER.';
      default:           return 'NOVATO';
    }
  }

  @override
  Widget build(BuildContext context) {
    final name  = '${friend['first_name'] ?? ''} ${friend['last_name'] ?? ''}'.trim();
    final nick  = friend['nickname'] ?? '';
    final level = friend['experience_level'];
    final lang  = friend['language'];

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.greyDark),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            RiderAvatar(avatarUrl: friend['avatar_url'], level: level ?? 'novato', size: 48),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(name.isNotEmpty ? name : nick,
                    style: const TextStyle(color: AppColors.white, fontWeight: FontWeight.w700, fontSize: 14)),
                if (nick.isNotEmpty)
                  Text('@$nick', style: const TextStyle(color: AppColors.orange, fontSize: 12)),
                const SizedBox(height: 4),
                Row(children: [
                  if (lang != null) ...[
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                      decoration: BoxDecoration(color: AppColors.greyDark.withOpacity(0.5), borderRadius: BorderRadius.circular(6)),
                      child: Text(_flag(lang), style: const TextStyle(fontSize: 12)),
                    ),
                    const SizedBox(width: 6),
                  ],
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: _levelColor(level).withOpacity(0.12),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: _levelColor(level).withOpacity(0.4)),
                    ),
                    child: Text(_levelLabel(level), style: TextStyle(color: _levelColor(level), fontSize: 10, fontWeight: FontWeight.w700)),
                  ),
                ]),
              ]),
            ),
          ]),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(
              child: GestureDetector(
                onTap: onAccept,
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.green.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.green.withOpacity(0.4)),
                  ),
                  child: Center(child: Text('friends_screen.accept'.tr(), style: const TextStyle(color: Colors.green, fontSize: 13, fontWeight: FontWeight.w600))),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: GestureDetector(
                onTap: onReject,
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  decoration: BoxDecoration(
                    color: AppColors.error.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: AppColors.error.withOpacity(0.3)),
                  ),
                  child: Center(child: Text('friends_screen.reject'.tr(), style: const TextStyle(color: AppColors.error, fontSize: 13, fontWeight: FontWeight.w600))),
                ),
              ),
            ),
          ]),
        ],
      ),
    );
  }
}

class _FriendCard extends StatelessWidget {
  final Map<String, dynamic> friend;
  final Widget trailing;
  const _FriendCard({required this.friend, required this.trailing});

  String _flag(String? lang) {
    switch (lang) {
      case 'en': return '🇬🇧';
      case 'fr': return '🇫🇷';
      case 'de': return '🇩🇪';
      case 'it': return '🇮🇹';
      case 'pt': return '🇵🇹';
      default:   return '🇪🇸';
    }
  }

  Color _levelColor(String? level) {
    switch (level) {
      case 'experto':    return AppColors.gold;
      case 'intermedio': return AppColors.cyan;
      default:           return AppColors.grey;
    }
  }

  String _levelLabel(String? level) {
    switch (level) {
      case 'experto':    return 'EXPERTO';
      case 'intermedio': return 'INTER.';
      default:           return 'NOVATO';
    }
  }

  @override
  Widget build(BuildContext context) {
    final name  = '${friend['first_name'] ?? ''} ${friend['last_name'] ?? ''}'.trim();
    final nick  = friend['nickname'] ?? '';
    final level = friend['experience_level'];
    final lang  = friend['language'];

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.greyDark),
      ),
      child: Row(children: [
        RiderAvatar(
          avatarUrl: friend['avatar_url'],
          level: level ?? 'novato',
          size: 48,
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(name.isNotEmpty ? name : nick,
                style: const TextStyle(color: AppColors.white, fontWeight: FontWeight.w700, fontSize: 14)),
            if (nick.isNotEmpty)
              Text('@$nick', style: const TextStyle(color: AppColors.orange, fontSize: 12)),
            const SizedBox(height: 4),
            Row(children: [
              // Bandera idioma
              if (lang != null)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                  decoration: BoxDecoration(
                    color: AppColors.greyDark.withOpacity(0.5),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(_flag(lang), style: const TextStyle(fontSize: 12)),
                ),
              if (lang != null) const SizedBox(width: 6),
              // Nivel
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: _levelColor(level).withOpacity(0.12),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: _levelColor(level).withOpacity(0.4)),
                ),
                child: Text(
                  _levelLabel(level),
                  style: TextStyle(
                    color: _levelColor(level),
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
              if (friend['province'] != null) ...[  
                const SizedBox(width: 6),
                Flexible(
                  child: Text(friend['province'],
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: AppColors.grey, fontSize: 11)),
                ),
              ],
            ]),
          ]),
        ),
        const SizedBox(width: 8),
        trailing,
      ]),
    );
  }
}
