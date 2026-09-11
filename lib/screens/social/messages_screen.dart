import 'dart:async';
import 'package:flutter/material.dart';
import '../../services/api_service.dart';
import 'chat_screen.dart';
import 'plan_hub_screen.dart';
import '../../widgets/lunara_cached_image.dart';

class MessagesScreen extends StatefulWidget {
  const MessagesScreen({super.key});

  @override
  State<MessagesScreen> createState() => _MessagesScreenState();
}

class _MessagesScreenState extends State<MessagesScreen> {
  bool _isLoading = true;
  List<Map<String, dynamic>> _conversations = [];
  bool _hasCreatedOrJoinedPlans = false;
  StreamSubscription<Map<String, dynamic>>? _chatUpdateSub;
  Timer? _conversationTimer;

  @override
  void initState() {
    super.initState();
    _loadConversations();
    _initSocketListeners();
    _initLocalStreamListener();
    _startConversationPolling();
  }

  void _startConversationPolling() {
    _conversationTimer?.cancel();
    // Adaptive fallback: Only check every 45s if socket is disconnected to eliminate polling storms
    _conversationTimer = Timer.periodic(const Duration(seconds: 45), (_) {
      if (mounted) {
        final isConnected = ApiService.socket?.connected ?? false;
        if (!isConnected) {
          _loadConversations(isBackgroundRefresh: true);
        }
      }
    });
  }

  void _initLocalStreamListener() {
    _chatUpdateSub = ApiService.chatUpdateStream.listen((data) {
      if (!mounted) return;
      final convId = data['conversationId']?.toString();
      if (convId == null) return;

      setState(() {
        final idx = _conversations.indexWhere(
          (c) => (c['conversationId'] ?? c['id'])?.toString() == convId,
        );
        if (idx != -1) {
          _conversations[idx]['lastMessagePreview'] =
              data['lastMessagePreview'] ?? '';
          _conversations[idx]['lastMessageAt'] = data['lastMessageAt'];
        } else {
          _loadConversations(isBackgroundRefresh: true);
        }
      });
    });
  }

  void _initSocketListeners() {
    ApiService.addSocketListener('new_message', _onNewMessageSocket);
    ApiService.addSocketListener('chat_badge_updated', _onChatBadgeUpdatedSocket);
    ApiService.addSocketListener('messages_read', _onMessagesReadSocket);
    ApiService.addSocketListener('user_status_changed', _onUserStatusSocket);
    ApiService.addSocketListener('conversation_deleted', _onConversationDeletedSocket);
    ApiService.addSocketListener('chat_cleared', _onChatClearedSocket);
    ApiService.addSocketListener('message_deleted', _onMessageDeletedSocket);
  }

  void _onNewMessageSocket(dynamic rawData) {
    if (!mounted || rawData == null) return;
    final data = rawData is Map ? Map<String, dynamic>.from(rawData) : <String, dynamic>{};
    final convId = data['conversationId']?.toString();
    if (convId == null) return;

    final senderId = data['senderId']?.toString();
    final currentUserId = ApiService.currentUserId;
    final type = data['type']?.toString() ?? 'text';
    final content = data['content']?.toString() ?? '';

    String preview = content;
    if (type == 'image') preview = '📷 Photo';
    if (type == 'sticker') preview = '😄 Sticker';
    if (type == 'voice') preview = '🎙 Voice message';
    if (type == 'invitation') preview = '📅 Party invitation';
    if (type == 'icebreaker') preview = '⚡ $content';

    setState(() {
      final idx = _conversations.indexWhere(
        (c) => (c['conversationId'] ?? c['id'])?.toString() == convId,
      );
      if (idx != -1) {
        final target = _conversations.removeAt(idx);
        target['lastMessagePreview'] = preview;
        target['lastMessageAt'] = data['createdAt'] ?? DateTime.now().toIso8601String();
        if (senderId != null && currentUserId != null && senderId.toLowerCase() != currentUserId.toLowerCase()) {
          target['unreadCount'] = (target['unreadCount'] as num? ?? 0).toInt() + 1;
        }
        _conversations.insert(0, target);
      } else {
        _loadConversations(isBackgroundRefresh: true);
      }
    });
  }

  void _onChatBadgeUpdatedSocket(dynamic rawData) {
    if (!mounted || rawData == null) return;
    final data = rawData is Map ? Map<String, dynamic>.from(rawData) : <String, dynamic>{};
    final convId = data['conversationId']?.toString();
    final unreadCount = data['unreadCount'] != null ? int.tryParse(data['unreadCount'].toString()) : null;
    final chatCount = data['chatCount'] != null ? int.tryParse(data['chatCount'].toString()) : null;

    if (chatCount != null) {
      ApiService.updateChatBadgeCount(chatCount);
    }

    if (convId != null && unreadCount != null) {
      setState(() {
        final idx = _conversations.indexWhere(
          (c) => (c['conversationId'] ?? c['id'])?.toString() == convId,
        );
        if (idx != -1) {
          _conversations[idx]['unreadCount'] = unreadCount;
        }
      });
    }
  }

  void _onMessagesReadSocket(dynamic rawData) {
    // Read receipts update for sent messages (handled in chat screen).
  }

  void _onUserStatusSocket(dynamic rawData) {
    if (!mounted || rawData == null) return;
    final data = rawData is Map ? Map<String, dynamic>.from(rawData) : <String, dynamic>{};
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
  }

  void _onConversationDeletedSocket(dynamic rawData) {
    if (!mounted || rawData == null) return;
    final data = rawData is Map ? Map<String, dynamic>.from(rawData) : <String, dynamic>{};
    final convId = data['conversationId']?.toString();
    if (convId == null) return;

    setState(() {
      _conversations.removeWhere(
        (c) => (c['conversationId'] ?? c['id'])?.toString() == convId,
      );
    });
  }

  void _onChatClearedSocket(dynamic rawData) {
    if (!mounted || rawData == null) return;
    final data = rawData is Map ? Map<String, dynamic>.from(rawData) : <String, dynamic>{};
    final convId = data['conversationId']?.toString();
    if (convId == null) return;

    setState(() {
      final idx = _conversations.indexWhere(
        (c) => (c['conversationId'] ?? c['id'])?.toString() == convId,
      );
      if (idx != -1) {
        _conversations[idx]['lastMessagePreview'] = 'Tap to chat';
        _conversations[idx]['lastMessageAt'] = null;
        _conversations[idx]['unreadCount'] = 0;
      }
    });
  }

  void _onMessageDeletedSocket(dynamic rawData) {
    if (!mounted || rawData == null) return;
    final data = rawData is Map ? Map<String, dynamic>.from(rawData) : <String, dynamic>{};
    final convId = data['conversationId']?.toString();
    if (convId == null) return;

    final deleteForEveryone = data['deleteForEveryone'] != false;
    final targetUserId = (data['targetUserId'] ?? '').toString();
    final myUserId = (ApiService.currentUserId ?? '').toString();

    if (!deleteForEveryone &&
        targetUserId.isNotEmpty &&
        myUserId.isNotEmpty &&
        targetUserId.toLowerCase() != myUserId.toLowerCase()) {
      return; // Not deleted for this user
    }

    setState(() {
      final idx = _conversations.indexWhere(
        (c) => (c['conversationId'] ?? c['id'])?.toString() == convId,
      );
      if (idx != -1) {
        if (data.containsKey('lastMessagePreview')) {
          _conversations[idx]['lastMessagePreview'] =
              data['lastMessagePreview'] ?? '';
          _conversations[idx]['lastMessageAt'] = data['lastMessageAt'];
        } else {
          _loadConversations();
        }
      } else {
        _loadConversations();
      }
    });
  }

  @override
  void dispose() {
    _conversationTimer?.cancel();
    _chatUpdateSub?.cancel();
    ApiService.removeSocketListener('new_message', _onNewMessageSocket);
    ApiService.removeSocketListener('chat_badge_updated', _onChatBadgeUpdatedSocket);
    ApiService.removeSocketListener('messages_read', _onMessagesReadSocket);
    ApiService.removeSocketListener('user_status_changed', _onUserStatusSocket);
    ApiService.removeSocketListener('conversation_deleted', _onConversationDeletedSocket);
    ApiService.removeSocketListener('chat_cleared', _onChatClearedSocket);
    ApiService.removeSocketListener('message_deleted', _onMessageDeletedSocket);
    super.dispose();
  }

  Future<void> _loadConversations({bool isBackgroundRefresh = false}) async {
    if (!isBackgroundRefresh && _conversations.isEmpty) {
      setState(() => _isLoading = true);
    }
    try {
      final userId = ApiService.currentUserId;
      if (userId == null) {
        if (mounted) setState(() => _isLoading = false);
        return;
      }

      final conversations = await ApiService.fetchConversations(userId);

      int totalUnread = 0;
      for (final c in conversations) {
        totalUnread += _unreadCount(c);
      }
      ApiService.updateChatBadgeCount(totalUnread);

      bool hasPlans = _hasCreatedOrJoinedPlans;
      if (conversations.isEmpty) {
        try {
          final results = await Future.wait([
            ApiService.fetchMyPartyPlans(),
            ApiService.fetchMyPartyPlanRequests(),
            ApiService.fetchMyStrangersMeetRequests(),
          ]);
          final myPartyPlans = results[0];
          final myPartyRequests = results[1];
          final myStrangersMeets = results[2];

          hasPlans = myPartyPlans.isNotEmpty || myPartyRequests.isNotEmpty || myStrangersMeets.isNotEmpty;
        } catch (e) {
          debugPrint('Error fetching plans check: $e');
        }
      }

      if (mounted) {
        // Smart reconciliation: only trigger setState if data actually changed
        bool hasChanges = false;
        if (_conversations.length != conversations.length) {
          hasChanges = true;
        } else {
          for (int i = 0; i < conversations.length; i++) {
            final newC = conversations[i];
            final newId = (newC['conversationId'] ?? newC['id'])?.toString();
            final oldC = _conversations.firstWhere(
              (c) => (c['conversationId'] ?? c['id'])?.toString() == newId,
              orElse: () => {},
            );
            if (oldC.isEmpty) {
              hasChanges = true;
              break;
            }
            final oldPreview = oldC['lastMessagePreview']?.toString() ?? '';
            final newPreview = newC['lastMessagePreview']?.toString() ?? '';
            final oldUnread = _unreadCount(oldC);
            final newUnread = _unreadCount(newC);
            final oldTime = oldC['lastMessageAt']?.toString() ?? '';
            final newTime = newC['lastMessageAt']?.toString() ?? '';
            final oldOnline = _isOnline(oldC);
            final newOnline = _isOnline(newC);

            if (oldPreview != newPreview ||
                oldUnread != newUnread ||
                oldTime != newTime ||
                oldOnline != newOnline) {
              hasChanges = true;
              break;
            }
          }
        }

        if (hasChanges || _isLoading || _hasCreatedOrJoinedPlans != hasPlans) {
          setState(() {
            _conversations = conversations;
            _hasCreatedOrJoinedPlans = hasPlans;
            _isLoading = false;
          });
        }
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
    final preview = c['lastMessagePreview']?.toString().trim();
    if (preview != null && preview.isNotEmpty) return preview;

    // Check for a nested lastMessage object
    final lm = c['lastMessage'] ?? c['lastMessageText'];
    if (lm is Map) {
      final content = lm['content']?.toString().trim() ??
          lm['text']?.toString().trim() ??
          lm['body']?.toString().trim() ??
          lm['message']?.toString().trim();
      if (content != null && content.isNotEmpty) return content;
    }

    // Try direct message fields as fallback
    final direct = c['message'] ?? c['lastMessageText'] ?? c['preview'] ?? c['lastMessage'];
    if (direct != null && direct.toString().trim().isNotEmpty) return direct.toString().trim();

    return 'Tap to chat';
  }

  String _formattedTime(Map<String, dynamic> c) {
    final lastMsg = _lastMessage(c);
    if (lastMsg == 'Tap to chat') return '';
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
    final otherId = _otherUserId(conversation);

    // Optimistically zero unread count immediately in local list and update badge
    final currentUnread = _unreadCount(conversation);
    if (currentUnread > 0) {
      setState(() {
        conversation['unreadCount'] = 0;
      });
      final currentTotal = ApiService.chatBadgeNotifier.value;
      if (currentTotal >= currentUnread) {
        ApiService.updateChatBadgeCount(currentTotal - currentUnread);
      }
    }

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ChatScreen(
          user: {
            'id': otherId,
            'name': _otherUserName(conversation),
            'image': _otherUserAvatar(conversation),
            'isAsset': false,
            'online': _isOnline(conversation),
            'conversationId': conversationId,
          },
        ),
      ),
    ).then((result) {
      if (result is Map && result['deleted'] == true) {
        final deletedConvId = result['conversationId']?.toString();
        final deletedOtherUserId = result['otherUserId']?.toString();
        setState(() {
          _conversations.removeWhere((item) =>
            (deletedConvId != null && (item['conversationId'] ?? item['id'])?.toString() == deletedConvId) ||
            (deletedOtherUserId != null && _otherUserId(item) == deletedOtherUserId) ||
            (otherId.isNotEmpty && _otherUserId(item) == otherId));
        });
      }
      _loadConversations(isBackgroundRefresh: true);
    });
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
    );
  }

  Widget _buildEmpty() {
    if (!_hasCreatedOrJoinedPlans) {
      return _buildNoPlansEmptyState();
    }
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

  Widget _buildNoPlansEmptyState() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      alignment: Alignment.center,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Elegant glow circle behind icon
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: const Color(0xFF7F00FF).withValues(alpha: 0.08),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.forum_outlined,
              size: 72,
              color: Color(0xFF7F00FF),
            ),
          ),
          const SizedBox(height: 28),
          const Text(
            'Connect & Chat',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.black87,
              fontSize: 22,
              fontWeight: FontWeight.bold,
              letterSpacing: -0.5,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'You haven\'t created or joined any plans yet. Start or join a plan to open chat rooms and connect with other users!',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.grey[600],
              fontSize: 15,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 36),
          // Gradient Create Button
          Container(
            width: double.infinity,
            height: 52,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF7F00FF), Color(0xFF9F33FF)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF7F00FF).withValues(alpha: 0.3),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: ElevatedButton.icon(
              onPressed: () {
                Navigator.push(
                  context,
                  PageRouteBuilder(
                    pageBuilder: (_, _, _) => const PlanHubScreen(autoShowCreatePlan: true),
                    transitionsBuilder: (_, anim, _, child) {
                      return SlideTransition(
                        position: Tween<Offset>(
                          begin: const Offset(0, 1),
                          end: Offset.zero,
                        ).animate(
                          CurvedAnimation(parent: anim, curve: Curves.easeOutCubic),
                        ),
                        child: child,
                      );
                    },
                    transitionDuration: const Duration(milliseconds: 350),
                  ),
                ).then((_) => _loadConversations());
              },
              icon: const Icon(Icons.add_circle_outline_rounded, color: Colors.white),
              label: const Text(
                'Create a Party Plan',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.transparent,
                shadowColor: Colors.transparent,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          // Outlined Browse Button
          SizedBox(
            width: double.infinity,
            height: 52,
            child: OutlinedButton.icon(
              onPressed: () {
                Navigator.push(
                  context,
                  PageRouteBuilder(
                    pageBuilder: (_, _, _) => const PlanHubScreen(),
                    transitionsBuilder: (_, anim, _, child) {
                      return SlideTransition(
                        position: Tween<Offset>(
                          begin: const Offset(0, 1),
                          end: Offset.zero,
                        ).animate(
                          CurvedAnimation(parent: anim, curve: Curves.easeOutCubic),
                        ),
                        child: child,
                      );
                    },
                    transitionDuration: const Duration(milliseconds: 350),
                  ),
                ).then((_) => _loadConversations());
              },
              icon: const Icon(Icons.search_rounded, color: Color(0xFF7F00FF)),
              label: const Text(
                'Browse & Join Plans',
                style: TextStyle(
                  color: Color(0xFF7F00FF),
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
              style: OutlinedButton.styleFrom(
                side: const BorderSide(color: Color(0xFF7F00FF), width: 1.5),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
            ),
          ),
        ],
      ),
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
    final convId = (c['conversationId'] ?? c['id'])?.toString() ?? 'conv_$index';

    return Dismissible(
      key: ValueKey('conv_$convId'),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.symmetric(horizontal: 24),
        color: const Color(0xFFEF4444),
        child: const Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            Icon(Icons.delete_outline_rounded, color: Colors.white, size: 24),
            SizedBox(width: 6),
            Text(
              'Delete',
              style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
            ),
          ],
        ),
      ),
      confirmDismiss: (direction) => _showDeleteConfirmation(c),
      child: Column(
        children: [
          InkWell(
            onTap: () => _openChat(c),
            onLongPress: () => _showConversationOptions(c),
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
                                (lastMsg.isEmpty || lastMsg == 'Tap to chat') ? 'Tap to chat' : lastMsg,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 14,
                                  color: unread > 0
                                      ? Colors.black87
                                      : (lastMsg == 'Tap to chat' || lastMsg.isEmpty
                                          ? const Color(0xFF7F00FF)
                                          : Colors.grey[600]),
                                  fontWeight: unread > 0
                                      ? FontWeight.w600
                                      : ((lastMsg == 'Tap to chat' || lastMsg.isEmpty) ? FontWeight.w500 : FontWeight.normal),
                                  fontStyle: (lastMsg == 'Tap to chat' || lastMsg.isEmpty) ? FontStyle.italic : FontStyle.normal,
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
      ),
    );
  }

  void _showConversationOptions(Map<String, dynamic> c) {
    final name = _otherUserName(c);
    final avatar = _otherUserAvatar(c);
    final initial = name.isNotEmpty ? name[0].toUpperCase() : '?';

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetCtx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey[300],
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 16),
              ListTile(
                leading: _buildUserAvatar(avatar: avatar, initial: initial, radius: 22),
                title: Text(
                  name,
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
                subtitle: const Text('Conversation Options', style: TextStyle(fontSize: 12)),
              ),
              const Divider(height: 1),
              ListTile(
                leading: const Icon(Icons.chat_bubble_outline_rounded, color: Color(0xFF7F00FF)),
                title: const Text('Open Chat'),
                onTap: () {
                  Navigator.pop(sheetCtx);
                  _openChat(c);
                },
              ),
              ListTile(
                leading: const Icon(Icons.cleaning_services_outlined, color: Color(0xFFF59E0B)),
                title: const Text('Clear Chat History'),
                subtitle: const Text('Remove messages from this conversation', style: TextStyle(fontSize: 12)),
                onTap: () {
                  Navigator.pop(sheetCtx);
                  _showClearConfirmation(c);
                },
              ),
              ListTile(
                leading: const Icon(Icons.delete_outline_rounded, color: Color(0xFFEF4444)),
                title: const Text(
                  'Delete Chat',
                  style: TextStyle(color: Color(0xFFEF4444), fontWeight: FontWeight.bold),
                ),
                subtitle: const Text('Remove user & messages from your chat list', style: TextStyle(fontSize: 12)),
                onTap: () {
                  Navigator.pop(sheetCtx);
                  _showDeleteConfirmation(c);
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<bool?> _showDeleteConfirmation(Map<String, dynamic> c) async {
    final name = _otherUserName(c);
    final convId = (c['conversationId'] ?? c['id'])?.toString() ?? '';
    final otherId = _otherUserId(c);
    final userId = ApiService.currentUserId ?? '';

    return showDialog<bool>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text('Delete chat with $name?'),
        content: const Text(
          'This will permanently delete this conversation and remove the user from your chats list.',
          style: TextStyle(fontSize: 14, height: 1.35),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx, false),
            child: const Text('Cancel', style: TextStyle(color: Colors.grey, fontWeight: FontWeight.bold)),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(dialogCtx, true);
              final targetId = convId.isNotEmpty ? convId : otherId;
              if (targetId.isNotEmpty && userId.isNotEmpty) {
                setState(() {
                  _conversations.removeWhere((item) =>
                    (convId.isNotEmpty && (item['conversationId'] ?? item['id'])?.toString() == convId) ||
                    (otherId.isNotEmpty && _otherUserId(item) == otherId));
                });

                final success = await ApiService.deleteConversation(targetId, userId);
                if (mounted) {
                  if (success) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('✓ Chat deleted successfully'),
                        backgroundColor: Color(0xFF10B981),
                      ),
                    );
                  }
                  _loadConversations();
                }
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFEF4444),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            child: const Text('Delete Chat', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  Future<void> _showClearConfirmation(Map<String, dynamic> c) async {
    final name = _otherUserName(c);
    final convId = (c['conversationId'] ?? c['id'])?.toString() ?? '';
    final userId = ApiService.currentUserId ?? '';

    final confirm = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text('Clear chat with $name?'),
        content: const Text(
          'All messages in this chat will be cleared for you.',
          style: TextStyle(fontSize: 14, height: 1.35),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx, false),
            child: const Text('Cancel', style: TextStyle(color: Colors.grey, fontWeight: FontWeight.bold)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(dialogCtx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFF59E0B),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            child: const Text('Clear Chat', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );

    if (confirm == true && convId.isNotEmpty && userId.isNotEmpty) {
      final success = await ApiService.clearChat(convId, userId);
      if (success && mounted) {
        setState(() {
          final idx = _conversations.indexWhere((item) => (item['conversationId'] ?? item['id'])?.toString() == convId);
          if (idx != -1) {
            _conversations[idx]['lastMessagePreview'] = '';
            _conversations[idx]['unreadCount'] = 0;
          }
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('✓ Chat cleared'),
            backgroundColor: Color(0xFF10B981),
          ),
        );
      }
    }
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
      child: LunaraCachedImage(
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
