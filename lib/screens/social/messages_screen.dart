import 'package:flutter/material.dart';
import '../../services/api_service.dart';
import 'chat_screen.dart';

class MessagesScreen extends StatefulWidget {
  const MessagesScreen({super.key});

  @override
  State<MessagesScreen> createState() => _MessagesScreenState();
}

class _MessagesScreenState extends State<MessagesScreen> {
  bool _isLoading = true;
  List<Map<String, dynamic>> _conversations = [];

  @override
  void initState() {
    super.initState();
    _loadConversations();
    _initSocketListeners();
  }

  void _initSocketListeners() {
    ApiService.socket?.on('user_status_changed', (data) {
      if (!mounted) return;
      final userId = data['userId']?.toString();
      final isOnline = data['isOnline'] == true;
      if (userId == null) return;

      bool changed = false;
      for (var c in _conversations) {
        if (_otherUserId(c) == userId) {
          final ou = c['otherUser'] ?? c['otherUserDetails'] ?? c['participant'] ?? c['user'] ?? c['receiver'];
          if (ou is Map) {
            ou['isOnline'] = isOnline;
            ou['online'] = isOnline;
            changed = true;
          }
        }
      }
      if (changed) {
        setState(() {});
      }
    });
  }

  @override
  void dispose() {
    ApiService.socket?.off('user_status_changed');
    super.dispose();
  }

  Future<void> _loadConversations() async {
    setState(() => _isLoading = true);
    try {
      final userId = ApiService.currentUserId;
      if (userId == null) {
        if (mounted) setState(() => _isLoading = false);
        return;
      }

      final conversations = await ApiService.fetchConversations(userId);

      // Debug: print raw API shape so we can map fields correctly
      if (conversations.isNotEmpty) {        
        debugPrint('[MessagesScreen] First conversation raw: ${conversations.first}');
      } else {
        debugPrint('[MessagesScreen] No conversations returned');
      }

      if (mounted) {
        setState(() {
          _conversations = conversations;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Error loading conversations: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // ── Helpers ─────────────────────────────────────────────────────────────────

  String _formatAvatarUrl(String? path) {
    if (path == null || path.isEmpty) return '';
    if (path.startsWith('http://') || path.startsWith('https://')) return path;
    if (path.startsWith('assets/')) return path;
    final cleanPath = path.startsWith('/') ? path : '/$path';
    return '${ApiService.baseUrl}$cleanPath';
  }

  String _otherUserName(Map<String, dynamic> c) {
    // Try multiple possible field names for the other user object
    final ou = c['otherUser'] ?? c['otherUserDetails'] ?? c['participant'] ?? c['user'] ?? c['receiver'] ?? c['sender'];
    if (ou is Map) {
      final name = ou['name'] ?? ou['username'];
      if (name != null && name.toString().trim().isNotEmpty) {
        return name.toString().trim().toUpperCase();
      }
      final first = ou['firstName'] ?? ou['first_name'] ?? '';
      final last = ou['lastName'] ?? ou['last_name'] ?? '';
      final full = '$first $last'.trim();
      if (full.isNotEmpty) return full.toUpperCase();
    }
    // Try direct top-level fields
    final directName = c['otherUserName'] ?? c['name'] ?? c['username'];
    if (directName != null && directName.toString().isNotEmpty) {
      return directName.toString().toUpperCase();
    }
    // Try participants array
    final participants = c['participants'];
    if (participants is List && participants.isNotEmpty) {
      final myId = ApiService.currentUserId;
      for (final p in participants) {
        if (p is Map) {
          final pid = p['id']?.toString() ?? p['_id']?.toString();
          if (pid != myId) {
            final name = p['name'] ?? p['username'];
            if (name != null && name.toString().trim().isNotEmpty) {
              return name.toString().trim().toUpperCase();
            }
            final first = p['firstName'] ?? p['first_name'] ?? '';
            final last = p['lastName'] ?? p['last_name'] ?? '';
            final full = '$first $last'.trim();
            if (full.isNotEmpty) return full.toUpperCase();
          }
        }
      }
    }
    debugPrint('[MessagesScreen] Could not find name in conversation: $c');
    return 'USER';
  }

  String _otherUserId(Map<String, dynamic> c) {
    final ou = c['otherUser'] ?? c['otherUserDetails'] ?? c['participant'] ?? c['user'] ?? c['receiver'];
    if (ou is Map) return ou['id']?.toString() ?? ou['_id']?.toString() ?? '';
    // Try direct fields
    final directId = c['otherUserId'] ?? c['receiverId'] ?? c['participantId'];
    if (directId != null) return directId.toString();
    // Try participants array
    final participants = c['participants'];
    if (participants is List && participants.isNotEmpty) {
      final myId = ApiService.currentUserId;
      for (final p in participants) {
        if (p is Map) {
          final pid = p['id']?.toString() ?? p['_id']?.toString();
          if (pid != null && pid != myId) return pid;
        }
      }
    }
    return '';
  }

  String _otherUserAvatar(Map<String, dynamic> c) {
    // Attempt to extract avatar from various possible fields
    String? avatar;
    final ou = c['otherUser'] ?? c['otherUserDetails'] ?? c['participant'] ?? c['user'] ?? c['receiver'];
    if (ou is Map) {
      avatar = ou['profilePhoto']?.toString() ??
          ou['profilePhotoUrl']?.toString() ??
          ou['avatar']?.toString() ??
          ou['photo']?.toString() ??
          ou['image']?.toString();
    }
    // Fallback to participants array if needed
    final participantsList = c['participants'];
    if ((avatar == null || avatar.isEmpty) && participantsList is List && participantsList.isNotEmpty) {
      final myId = ApiService.currentUserId;
      for (final p in participantsList) {
        if (p is Map) {
          final pid = p['id']?.toString() ?? p['_id']?.toString();
          if (pid != myId) {
            avatar = p['profilePhoto']?.toString() ??
                p['profilePhotoUrl']?.toString() ??
                p['avatar']?.toString() ??
                p['photo']?.toString() ??
                p['image']?.toString();
            break;
          }
        }
      }
    }
    return _formatAvatarUrl(avatar);
  }

  String _lastMessage(Map<String, dynamic> c) {
    final preview = c['lastMessagePreview'];
    if (preview != null && preview.toString().isNotEmpty) return preview.toString();

    // Check for a nested lastMessage object
    final lm = c['lastMessage'] ?? c['lastMessageText'];
    if (lm is Map) {
      return lm['content']?.toString() ??
          lm['text']?.toString() ??
          lm['body']?.toString() ??
          lm['message']?.toString() ??
          'Tap to chat';
    }

    // Try direct message fields as fallback
    final direct = c['message'] ?? c['lastMessageText'] ?? c['preview'] ?? c['lastMessage'];
    if (direct != null && direct.toString().isNotEmpty) return direct.toString();

    return 'Tap to chat';
  }

  String _formattedTime(Map<String, dynamic> c) {
    final raw = c['lastMessageAt'] ?? c['updatedAt'] ?? c['createdAt'] ?? c['timestamp'];
    if (raw == null) return '';
    DateTime? dt;
    // Handle numeric timestamps (milliseconds)
    if (raw is int) {
      dt = DateTime.fromMillisecondsSinceEpoch(raw);
    } else {
      dt = DateTime.tryParse(raw.toString());
    }
    if (dt == null) return '';
    // Ensure we compare in local time
    dt = dt.toLocal();
    final now = DateTime.now();
    final diff = now.difference(dt);
    if (diff.isNegative || diff.inMinutes < 1) return 'Now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m';
    if (diff.inHours < 24) return '${diff.inHours}h';
    if (diff.inDays < 7) return '${diff.inDays}d';
    return '${dt.day}/${dt.month}';
  }

  int _unreadCount(Map<String, dynamic> c) {
    final uc = c['unreadCount'];
    if (uc is int) return uc;
    return int.tryParse(uc?.toString() ?? '0') ?? 0;
  }

  bool _isOnline(Map<String, dynamic> c) {
    final ou = c['otherUser'];
    if (ou is Map) return ou['isOnline'] == true || ou['online'] == true;
    return false;
  }

  void _openChat(Map<String, dynamic> conversation) {
    final conversationId = conversation['id']?.toString() ??
        conversation['conversationId']?.toString() ??
        conversation['_id']?.toString();

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ChatScreen(
          user: {
            'id': _otherUserId(conversation),
            'name': _otherUserName(conversation),
            'image': _otherUserAvatar(conversation),
            'isAsset': false,
            'online': _isOnline(conversation),
            'conversationId': conversationId,
          },
        ),
      ),
    ).then((_) => _loadConversations());
  }

  /// Open a fresh chat by tapping a profile in the People strip.
  void _openChatWithCustomer(Map<String, dynamic> customer) {     
    final id = customer['id']?.toString() ?? customer['_id']?.toString() ?? '';
    final firstName = customer['firstName']?.toString() ?? customer['name']?.toString() ?? '';
    final lastName = customer['lastName']?.toString() ?? '';
    final name = '$firstName $lastName'.trim();
    final avatar = _formatAvatarUrl(customer['profilePhotoUrl']?.toString() ??
        customer['profileImage']?.toString() ??
        customer['avatar']?.toString() ??
        customer['image']?.toString());

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ChatScreen(
          user: {
            'id': id,
            'name': name,
            'image': avatar,
            'isAsset': false,
            'online': customer['isOnline'] == true || customer['online'] == true,
          },
        ),
      ),
    ).then((_) => _loadConversations());
  }

  // ── Build ────────────────────────────────────────────────────────────────────

  void _showContactsPicker() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return Container(
          padding: const EdgeInsets.symmetric(vertical: 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Text(
                  'Select Contact',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 18,
                    color: Color(0xFF008069),
                  ),
                ),
              ),
              const Divider(),
              Expanded(
                child: FutureBuilder<List<Map<String, dynamic>>>(
                  future: ApiService.fetchCustomers(),
                  builder: (context, snapshot) {
                    final users = snapshot.data ?? [];
                    if (snapshot.connectionState == ConnectionState.waiting && users.isEmpty) {
                      return const Center(child: CircularProgressIndicator(color: Color(0xFF008069)));
                    }
                    if (users.isEmpty) {
                      return const Center(child: Text('No contacts found'));
                    }
                    return ListView.builder(
                      itemCount: users.length,
                      itemBuilder: (context, index) {
                        final u = users[index];
                        final firstName = u['firstName']?.toString() ?? u['name']?.toString() ?? '';
                        final lastName = u['lastName']?.toString() ?? '';
                        final displayName = '$firstName $lastName'.trim();
                        final avatar = _formatAvatarUrl(u['profilePhotoUrl']?.toString() ??
                            u['profileImage']?.toString() ??
                            u['avatar']?.toString() ??
                            u['image']?.toString());
                        final initial = displayName.isNotEmpty ? displayName[0].toUpperCase() : '?';

                        return ListTile(
                          leading: _buildUserAvatar(avatar: avatar, initial: initial, radius: 20),
                          title: Text(displayName, style: const TextStyle(fontWeight: FontWeight.bold)),
                          subtitle: Text(u['isOnline'] == true ? 'Online' : 'Offline'),
                          onTap: () {
                            Navigator.pop(context);
                            _openChatWithCustomer(u);
                          },
                        );
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  // ── Build ────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: const Color(0xFF7F00FF),
        surfaceTintColor: const Color(0xFF7F00FF),
        elevation: 1,
        shadowColor: Colors.black26,
        title: const Text(
          'Chat',
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            fontSize: 22,
          ),
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: Color(0xFF7F00FF)))
          : RefreshIndicator(
              color: const Color(0xFF7F00FF),
              onRefresh: _loadConversations,
              child: _conversations.isEmpty ? _buildEmpty() : _buildList(),
            ),
      floatingActionButton: FloatingActionButton(
        onPressed: _showContactsPicker,
        backgroundColor: const Color(0xFF7F00FF),
        elevation: 4,
        shape: const CircleBorder(),
        child: const Icon(Icons.chat_rounded, color: Colors.white, size: 24),
      ),
    );
  }

  Widget _buildEmpty() {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      children: [
        SizedBox(height: MediaQuery.of(context).size.height * 0.15),
        Icon(Icons.chat_bubble_outline_rounded, size: 64, color: const Color(0xFF7F00FF).withValues(alpha: 0.25)),
        const SizedBox(height: 16),
        const Text(
          'No conversations yet',
          textAlign: TextAlign.center,
          style: TextStyle(color: Colors.black87, fontSize: 17, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 8),
        Text(
          'Tap the chat icon below to start chatting',
          textAlign: TextAlign.center,
          style: TextStyle(color: Colors.grey[500], fontSize: 14),
        ),
      ],
    );
  }

  Widget _buildList() {
    return ListView.builder(
      physics: const AlwaysScrollableScrollPhysics(),
      itemCount: _conversations.length,
      itemBuilder: (context, index) {
        return _buildConversationTile(_conversations[index], index);
      },
    );
  }

  Widget _buildConversationTile(Map<String, dynamic> c, int index) {
    final unread = _unreadCount(c);
    final name = _otherUserName(c);
    final avatar = _otherUserAvatar(c);
    final lastMsg = _lastMessage(c);
    final time = _formattedTime(c);
    final online = _isOnline(c);
    final initial = name.isNotEmpty ? name[0].toUpperCase() : '?';

    return Column(
      children: [
        InkWell(
          onTap: () => _openChat(c),
          splashColor: const Color(0xFF7F00FF).withValues(alpha: 0.05),
          highlightColor: const Color(0xFF7F00FF).withValues(alpha: 0.03),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Row(
              children: [
                Stack(
                  children: [
                    _buildUserAvatar(avatar: avatar, initial: initial, radius: 26),
                    if (online)
                      Positioned(
                        right: 1,
                        bottom: 1,
                        child: Container(
                          width: 14,
                          height: 14,
                          decoration: BoxDecoration(
                            color: const Color(0xFF4CAF50),
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.white, width: 2.5),
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontWeight: unread > 0 ? FontWeight.bold : FontWeight.w600,
                                fontSize: 16,
                                color: Colors.black,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            time,
                            style: TextStyle(
                              fontSize: 12,
                              color: unread > 0 ? const Color(0xFF7F00FF) : Colors.grey[500],
                              fontWeight: unread > 0 ? FontWeight.bold : FontWeight.normal,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              lastMsg,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 14,
                                color: unread > 0 ? Colors.black87 : Colors.grey[500],
                                fontWeight: unread > 0 ? FontWeight.w500 : FontWeight.normal,
                              ),
                            ),
                          ),
                          if (unread > 0) ...[
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                              decoration: const BoxDecoration(
                                color: Color(0xFF7F00FF),
                                shape: BoxShape.circle,
                              ),
                              child: Text(
                                unread > 99 ? '99+' : '$unread',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        if (index < _conversations.length - 1)
          Padding(
            padding: const EdgeInsets.only(left: 82),
            child: Divider(height: 1, color: Colors.grey[200]),
          ),
      ],
    );
  }

  Widget _buildUserAvatar({
    required String avatar,
    required String initial,
    double radius = 26,
  }) {
    Widget fallback = Container(
      width: radius * 2,
      height: radius * 2,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: Colors.grey[300],
      ),
      alignment: Alignment.center,
      child: Icon(
        Icons.person,
        color: Colors.grey[600],
        size: radius * 1.2,
      ),
    );

    if (avatar.isEmpty) return fallback;

    return ClipOval(
      child: Image.network(
        avatar,
        width: radius * 2,
        height: radius * 2,
        fit: BoxFit.cover,
        errorBuilder: (context, error, stackTrace) => fallback,
        loadingBuilder: (_, child, progress) {
          if (progress == null) return child;
          return Container(
            width: radius * 2,
            height: radius * 2,
            color: Colors.grey[100],
            child: Center(
              child: CircularProgressIndicator(
                strokeWidth: 1.5,
                value: progress.expectedTotalBytes != null
                    ? progress.cumulativeBytesLoaded / progress.expectedTotalBytes!
                    : null,
                color: const Color(0xFF7F00FF),
              ),
            ),
          );
        },
      ),
    );
  }
}
