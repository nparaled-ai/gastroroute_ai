import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme/app_theme.dart';
import '../../../widgets/rider_avatar.dart';
import '../providers/friendship_service.dart';

class FriendsSearchScreen extends StatefulWidget {
  const FriendsSearchScreen({super.key});

  @override
  State<FriendsSearchScreen> createState() => _FriendsSearchScreenState();
}

class _FriendsSearchScreenState extends State<FriendsSearchScreen> {
  final _searchController = TextEditingController();
  List<Map<String, dynamic>> _results = [];
  bool _loading   = false;
  bool _searched  = false;
  final Map<int, bool> _sending = {};

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _search(String query) async {
    if (query.trim().length < 2) {
      setState(() { _results = []; _searched = false; });
      return;
    }
    setState(() { _loading = true; _searched = true; });
    final result = await FriendshipService.search(query.trim());
    if (!mounted) return;
    setState(() {
      _results = List<Map<String, dynamic>>.from(result['results'] ?? []);
      _loading = false;
    });
  }

  Future<void> _sendRequest(Map<String, dynamic> rider) async {
    final userId = rider['user_id'] as int;
    setState(() => _sending[userId] = true);
    final result = await FriendshipService.sendRequest(userId);
    if (!mounted) return;
    setState(() => _sending[userId] = false);

    if (result['error'] != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(result['error']), backgroundColor: AppColors.error),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(result['message'] ?? 'Solicitud enviada.'), backgroundColor: Colors.green),
      );
      // Actualizar estado local
      setState(() {
        final idx = _results.indexWhere((r) => r['user_id'] == userId);
        if (idx != -1) _results[idx]['friendship_status'] = 'pending';
      });
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
        title: const Text('Buscar moteros',
            style: TextStyle(color: AppColors.white, fontWeight: FontWeight.w700)),
      ),
      body: Column(children: [
        // Buscador
        Container(
          color: AppColors.surface,
          padding: const EdgeInsets.all(16),
          child: TextFormField(
            controller: _searchController,
            autofocus: true,
            style: const TextStyle(color: AppColors.white),
            onChanged: _search,
            decoration: InputDecoration(
              hintText: 'Buscar por nombre o nickname...',
              prefixIcon: const Icon(Icons.search, color: AppColors.grey),
              suffixIcon: _searchController.text.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear, color: AppColors.grey),
                      onPressed: () {
                        _searchController.clear();
                        setState(() { _results = []; _searched = false; });
                      })
                  : null,
            ),
          ),
        ),

        // Resultados
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator(color: AppColors.orange))
              : !_searched
                  ? Center(
                      child: Column(mainAxisSize: MainAxisSize.min, children: [
                        const Icon(Icons.person_search_outlined, color: AppColors.greyDark, size: 64),
                        const SizedBox(height: 16),
                        const Text('Escribe al menos 2 caracteres',
                            style: TextStyle(color: AppColors.grey)),
                      ]),
                    )
                  : _results.isEmpty
                      ? Center(
                          child: Column(mainAxisSize: MainAxisSize.min, children: [
                            const Icon(Icons.search_off, color: AppColors.greyDark, size: 64),
                            const SizedBox(height: 16),
                            const Text('No se encontraron moteros',
                                style: TextStyle(color: AppColors.grey)),
                          ]),
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.all(16),
                          itemCount: _results.length,
                          itemBuilder: (context, index) {
                            final rider = _results[index];
                            return _SearchResultCard(
                              rider: rider,
                              sending: _sending[rider['user_id']] == true,
                              onSendRequest: () => _sendRequest(rider),
                            );
                          },
                        ),
        ),
      ]),
    );
  }
}

class _SearchResultCard extends StatelessWidget {
  final Map<String, dynamic> rider;
  final bool sending;
  final VoidCallback onSendRequest;

  const _SearchResultCard({required this.rider, required this.sending, required this.onSendRequest});

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

  Widget _actionButton() {
    final status      = rider['friendship_status'];
    final isRequester = rider['is_requester'] ?? false;

    if (status == 'accepted') {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: Colors.green.withOpacity(0.1),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.green.withOpacity(0.3)),
        ),
        child: const Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.check, color: Colors.green, size: 14),
          SizedBox(width: 4),
          Text('Amigos', style: TextStyle(color: Colors.green, fontSize: 12)),
        ]),
      );
    }

    if (status == 'pending') {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: AppColors.gold.withOpacity(0.1),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: AppColors.gold.withOpacity(0.3)),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.schedule, color: AppColors.gold, size: 14),
          const SizedBox(width: 4),
          Text(isRequester ? 'Enviada' : 'Recibida',
              style: const TextStyle(color: AppColors.gold, fontSize: 12)),
        ]),
      );
    }

    return GestureDetector(
      onTap: sending ? null : onSendRequest,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          color: AppColors.orange.withOpacity(0.15),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: AppColors.orange.withOpacity(0.5)),
        ),
        child: sending
            ? const SizedBox(width: 16, height: 16,
                child: CircularProgressIndicator(color: AppColors.orange, strokeWidth: 2))
            : const Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.person_add_outlined, color: AppColors.orange, size: 14),
                SizedBox(width: 4),
                Text('Añadir', style: TextStyle(color: AppColors.orange, fontSize: 12, fontWeight: FontWeight.w600)),
              ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final name  = '${rider['first_name'] ?? ''} ${rider['last_name'] ?? ''}'.trim();
    final nick  = rider['nickname'] ?? '';
    final level = rider['experience_level'];
    final lang  = rider['language'];

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
          avatarUrl: rider['avatar_url'],
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
              if (rider['province'] != null) ...[  
                const SizedBox(width: 6),
                Flexible(
                  child: Text(rider['province'],
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: AppColors.grey, fontSize: 11)),
                ),
              ],
            ]),
          ]),
        ),
        const SizedBox(width: 8),
        _actionButton(),
      ]),
    );
  }
}
