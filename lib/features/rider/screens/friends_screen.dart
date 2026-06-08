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
        title: const Text('Eliminar amigo', style: TextStyle(color: AppColors.white)),
        content: Text('¿Dejar de ser amigo de $name?', style: const TextStyle(color: AppColors.grey)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar', style: TextStyle(color: AppColors.grey))),
          TextButton(onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Eliminar', style: TextStyle(color: AppColors.error))),
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
        title: const Text('Amigos', style: TextStyle(color: AppColors.white, fontWeight: FontWeight.w700)),
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: AppColors.orange,
          labelColor: AppColors.orange,
          unselectedLabelColor: AppColors.grey,
          tabs: [
            Tab(text: 'Amigos (${_friends.length})'),
            Tab(
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                const Text('Recibidas'),
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
            Tab(text: 'Enviadas (${_sent.length})'),
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
              child: const Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                Icon(Icons.person_search_outlined, color: AppColors.orange, size: 22),
                SizedBox(width: 10),
                Text('Buscar moteros', style: TextStyle(color: AppColors.orange, fontSize: 15, fontWeight: FontWeight.w700)),
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
        const Text('Aún no tienes amigos.\nUsa el botón de arriba para buscar moteros.',
            textAlign: TextAlign.center,
            style: TextStyle(color: AppColors.grey, fontSize: 14, height: 1.5)),
      ]),
    );
  }

  Widget _buildReceivedList() {
    if (_received.isEmpty) {
      return _buildEmpty('No tienes solicitudes pendientes.', Icons.mail_outline);
    }
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _received.length,
      itemBuilder: (context, index) {
        final r = _received[index];
        return _FriendCard(
          friend: r,
          trailing: Row(mainAxisSize: MainAxisSize.min, children: [
            GestureDetector(
              onTap: () => _accept(r['friendship_id']),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.green.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.green.withOpacity(0.4)),
                ),
                child: const Text('Aceptar', style: TextStyle(color: Colors.green, fontSize: 12, fontWeight: FontWeight.w600)),
              ),
            ),
            const SizedBox(width: 8),
            GestureDetector(
              onTap: () => _reject(r['friendship_id']),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: AppColors.error.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppColors.error.withOpacity(0.3)),
                ),
                child: const Text('Rechazar', style: TextStyle(color: AppColors.error, fontSize: 12, fontWeight: FontWeight.w600)),
              ),
            ),
          ]),
        );
      },
    );
  }

  Widget _buildSentList() {
    if (_sent.isEmpty) {
      return _buildEmpty('No tienes solicitudes enviadas.', Icons.send_outlined);
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
            child: const Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.check_circle, color: Colors.green, size: 14),
              SizedBox(width: 4),
              Text('¡Aceptada!', style: TextStyle(color: Colors.green, fontSize: 11, fontWeight: FontWeight.w700)),
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
            child: const Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.cancel_outlined, color: AppColors.error, size: 14),
              SizedBox(width: 4),
              Text('Rechazada', style: TextStyle(color: AppColors.error, fontSize: 11, fontWeight: FontWeight.w700)),
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
            child: const Text('Pendiente', style: TextStyle(color: AppColors.gold, fontSize: 11)),
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
          label: const Text('Buscar moteros'),
        ),
      ]),
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
