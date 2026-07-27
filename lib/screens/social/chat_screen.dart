import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import '../../services/api_service.dart';
import '../../services/push_notification_service.dart';
import 'icebreaker_modal.dart';
import '../../services/block_service.dart';

class ChatScreen extends StatefulWidget {
  final Map<String, dynamic> user;

  const ChatScreen({super.key, required this.user});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> with WidgetsBindingObserver {
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final FocusNode _focusNode = FocusNode();

  List<Map<String, dynamic>> _messages = [];
  bool _isLoading = true;
  bool _isSending = false;
  bool _isLoadingMore = false;
  bool _isBlocked = false;

  String? _conversationId;
  String? _currentUserId;
  Timer? _statusTimer;

  // Live online status (fetched from API, overrides widget.user['online'])
  bool? _isOnline;
  String? _lastActive;

  bool _isRecipientTyping = false;
  Timer? _typingDebounceTimer;

  // ── Chat Session / Subscription state ───────────────────────────────────────
  bool _chatSessionLoaded = false;
  bool _canChat = true; // optimistic default until API responds
  int _daysLeft = 0;
  // ignore: unused_field
  bool _isFreeChat = false;
  int? _extensionDays; // null until admin config loaded
  double? _extensionPrice; // null until admin config loaded
  // ignore: unused_field
  DateTime? _chatExpiresAt;
  bool _adminSettingsAvailable = false; // true only when admin responded

  String _safeString(dynamic val, [String fallback = '']) {
    if (val == null) return fallback;
    return val.toString();
  }

  int _safeInt(dynamic val, [int fallback = 0]) {
    if (val == null) return fallback;
    if (val is int) return val;
    if (val is double) return val.toInt();
    return int.tryParse(val.toString()) ?? fallback;
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _checkBlockStatus();
    _currentUserId = ApiService.currentUserId;
    // Seed status from widget data while API loads
    _isOnline = widget.user['online'] == true;
    _initChat();
    _initSocketListeners();
    _scrollController.addListener(_onScroll);
    _fetchUserStatus();
    _startStatusPolling();
  }

  @override
  void didUpdateWidget(covariant ChatScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    final oldUserId = oldWidget.user['id']?.toString();
    final newUserId = widget.user['id']?.toString();
    final oldConvId = oldWidget.user['conversationId']?.toString();
    final newConvId = widget.user['conversationId']?.toString();

    if (oldUserId != newUserId || oldConvId != newConvId) {
      _removeSocketListeners();
      setState(() {
        _currentUserId = ApiService.currentUserId;
        _isOnline = widget.user['online'] == true;
        _conversationId = newConvId?.isNotEmpty == true ? newConvId : null;
        _messages = [];
        _isLoading = true;
      });
      _checkBlockStatus();
      _initChat();
      _initSocketListeners();
      _fetchUserStatus();
    }
  }

  void _initSocketListeners() {
    ApiService.addSocketListener('new_message', _onNewMessageSocket);
    ApiService.addSocketListener('messages_read', _onMessagesReadSocket);
    ApiService.addSocketListener('user_status_changed', _onUserStatusSocket);
    ApiService.addSocketListener('messages_delivered', _onMessagesDeliveredSocket);
    ApiService.addSocketListener('typing_started', _onTypingStartedSocket);
    ApiService.addSocketListener('typing_stopped', _onTypingStoppedSocket);
  }

  void _removeSocketListeners() {
    ApiService.removeSocketListener('new_message', _onNewMessageSocket);
    ApiService.removeSocketListener('messages_read', _onMessagesReadSocket);
    ApiService.removeSocketListener('user_status_changed', _onUserStatusSocket);
    ApiService.removeSocketListener('messages_delivered', _onMessagesDeliveredSocket);
    ApiService.removeSocketListener('typing_started', _onTypingStartedSocket);
    ApiService.removeSocketListener('typing_stopped', _onTypingStoppedSocket);
  }

  void _onNewMessageSocket(dynamic rawData) {
    if (!mounted || rawData == null) return;
    final data = rawData is Map ? Map<String, dynamic>.from(rawData) : <String, dynamic>{};
    final msgConvId = _safeString(data['conversationId']);

    if (msgConvId.isNotEmpty && _conversationId != null && msgConvId.toLowerCase() == _conversationId!.toLowerCase()) {
      final incoming = _mapApiMessage(data);
      final clientMsgId = _safeString(incoming['clientMessageId']);
      final msgId = _safeString(incoming['id']);

      setState(() {
        final existingIdx = _messages.indexWhere((m) =>
            (msgId.isNotEmpty && _safeString(m['id']) == msgId) ||
            (clientMsgId.isNotEmpty && _safeString(m['clientMessageId']) == clientMsgId) ||
            (clientMsgId.isNotEmpty && _safeString(m['id']) == clientMsgId));

        if (existingIdx != -1) {
          _messages[existingIdx] = incoming;
        } else {
          _messages.insert(0, incoming);
        }
        _sortMessages();
      });
      _markAsRead();
    }
  }

  void _onMessagesReadSocket(dynamic rawData) {
    if (!mounted || rawData == null) return;
    final data = rawData is Map ? Map<String, dynamic>.from(rawData) : <String, dynamic>{};
    final msgConvId = _safeString(data['conversationId']);
    if (_conversationId != null && msgConvId.toLowerCase() == _conversationId!.toLowerCase()) {
      setState(() {
        for (var i = 0; i < _messages.length; i++) {
          if (_messages[i]['isSent'] == true) {
            _messages[i]['status'] = 'read';
          }
        }
      });
    }
  }

  void _onUserStatusSocket(dynamic rawData) {
    if (!mounted || rawData == null) return;
    final data = rawData is Map ? Map<String, dynamic>.from(rawData) : <String, dynamic>{};
    final targetUserId = _safeString(widget.user['id']);
    if (_safeString(data['userId']).toLowerCase() == targetUserId.toLowerCase()) {
      setState(() {
        _isOnline = data['isOnline'] == true;
        _lastActive = _safeString(data['lastActiveAt']);
      });
    }
  }

  void _onMessagesDeliveredSocket(dynamic rawData) {
    if (!mounted || rawData == null) return;
    final data = rawData is Map ? Map<String, dynamic>.from(rawData) : <String, dynamic>{};
    final msgConvId = _safeString(data['conversationId']);
    if (_conversationId != null && msgConvId.toLowerCase() == _conversationId!.toLowerCase()) {
      setState(() {
        for (var i = 0; i < _messages.length; i++) {
          if (_messages[i]['isSent'] == true &&
              _safeString(_messages[i]['status']) == 'sent') {
            _messages[i]['status'] = 'delivered';
          }
        }
      });
    }
  }

  void _onTypingStartedSocket(dynamic rawData) {
    if (!mounted || rawData == null) return;
    final data = rawData is Map ? Map<String, dynamic>.from(rawData) : <String, dynamic>{};
    final msgConvId = _safeString(data['conversationId']);
    if (_conversationId != null && msgConvId.toLowerCase() == _conversationId!.toLowerCase()) {
      setState(() => _isRecipientTyping = true);
    }
  }

  void _onTypingStoppedSocket(dynamic rawData) {
    if (!mounted || rawData == null) return;
    final data = rawData is Map ? Map<String, dynamic>.from(rawData) : <String, dynamic>{};
    final msgConvId = _safeString(data['conversationId']);
    if (_conversationId != null && msgConvId.toLowerCase() == _conversationId!.toLowerCase()) {
      setState(() => _isRecipientTyping = false);
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _markAsRead();
      _fetchUserStatus();
    }
  }

  @override
  void dispose() {
    if (PushNotificationService.activeConversationId == _conversationId) {
      PushNotificationService.activeConversationId = null;
    }
    WidgetsBinding.instance.removeObserver(this);
    _removeSocketListeners();
    _statusTimer?.cancel();
    _typingDebounceTimer?.cancel();
    _messageController.dispose();
    _scrollController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  Future<void> _checkBlockStatus() async {
    final otherUserId = widget.user['id']?.toString();
    if (otherUserId != null) {
      final isBlocked = await BlockService.isUserBlocked(otherUserId);
      if (mounted) {
        setState(() {
          _isBlocked = isBlocked;
        });
      }
    }
  }

  void _toggleBlock() async {
    final otherUserId = widget.user['id']?.toString();
    if (otherUserId == null) return;
    if (_isBlocked) {
      await BlockService.unblockUser(otherUserId);
    } else {
      await BlockService.blockUser(otherUserId);
    }
    _checkBlockStatus();
  }

  void _reportUser() async {
    final otherUserId = widget.user['id']?.toString();
    if (otherUserId == null) return;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Report User'),
        content: const Text(
          'Are you sure you want to report and block this user?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(ctx);
              await BlockService.reportUser(
                otherUserId,
                'Inappropriate behavior',
              );
              _checkBlockStatus();
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('User reported and blocked')),
                );
              }
            },
            child: const Text('Report', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  /// Marks the current conversation as read if we have all the necessary IDs.
  void _markAsRead() {
    final convId = _conversationId;
    final userId = _currentUserId;
    if (!mounted || convId == null || userId == null) return;
    ApiService.markConversationRead(convId, userId);
  }

  /// Fetches and updates the other user's online/offline status.
  Future<void> _fetchUserStatus() async {
    final otherUserId = widget.user['id']?.toString();
    if (otherUserId == null || otherUserId.isEmpty) return;
    final result = await ApiService.getUserOnlineStatus(otherUserId);
    if (!mounted || result == null) return;
    setState(() {
      _isOnline = result['isOnline'] == true;
      _lastActive =
          result['lastActive']?.toString() ?? result['lastSeen']?.toString();
    });
  }

  /// Polls online status every 30 seconds while screen is open.
  void _startStatusPolling() {
    _statusTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      _fetchUserStatus();
    });
  }

  String _formatLastSeen(String? isoString) {
    if (isoString == null) return 'offline';
    final dt = DateTime.tryParse(isoString)?.toLocal();
    if (dt == null) return 'offline';
    final now = DateTime.now();
    final diff = now.difference(dt);
    if (diff.inSeconds < 60) return 'last seen just now';
    if (diff.inMinutes < 60) return 'last seen ${diff.inMinutes}m ago';
    if (diff.inHours < 24) return 'last seen ${diff.inHours}h ago';
    if (diff.inDays == 1) return 'last seen yesterday';
    if (diff.inDays < 7) return 'last seen ${diff.inDays}d ago';
    final hour = dt.hour > 12 ? dt.hour - 12 : (dt.hour == 0 ? 12 : dt.hour);
    final min = dt.minute.toString().padLeft(2, '0');
    final ampm = dt.hour >= 12 ? 'PM' : 'AM';
    return 'last seen ${dt.day}/${dt.month} at $hour:$min $ampm';
  }

  void _sortMessages() {
    _messages.sort((a, b) {
      final aStr = a['createdAt']?.toString();
      final bStr = b['createdAt']?.toString();
      if (aStr == null && bStr == null) return 0;
      if (aStr == null) return 1;
      if (bStr == null) return -1;
      final aTime =
          DateTime.tryParse(aStr) ?? DateTime.fromMillisecondsSinceEpoch(0);
      final bTime =
          DateTime.tryParse(bStr) ?? DateTime.fromMillisecondsSinceEpoch(0);
      return bTime.compareTo(aTime); // descending (newest first)
    });
  }

  // ── Init ────────────────────────────────────────────────────────────────────

  Future<void> _initChat() async {
    final userId = _currentUserId;
    final otherUserId = widget.user['id']?.toString();

    debugPrint('[ChatScreen] _initChat: userId=$userId, otherUserId=$otherUserId');
    debugPrint('[ChatScreen] _initChat: widget.user=${widget.user}');

    if (userId == null || otherUserId == null || otherUserId.isEmpty) {
      debugPrint('[ChatScreen] _initChat: Missing userId or otherUserId, aborting');
      if (mounted) setState(() => _isLoading = false);
      return;
    }

    // Step 3 — create or get conversation
    final existingConvId = widget.user['conversationId']?.toString();
    String? convId = existingConvId?.isNotEmpty == true ? existingConvId : null;
    debugPrint('[ChatScreen] existingConvId=$existingConvId, using convId=$convId');

    convId ??= await ApiService.createOrGetConversation(
      userId: userId,
      otherUserId: otherUserId,
      contextType: widget.user['contextType'] as String?,
      contextId: widget.user['planId'] as String?,
    );

    if (!mounted) return;
    _conversationId = convId;
    debugPrint('[ChatScreen] Final conversationId=$convId');
    PushNotificationService.activeConversationId = convId;

    if (convId == null) {
      debugPrint('[ChatScreen] convId is null, cannot load messages');
      setState(() => _isLoading = false);
      return;
    }

    // Step 4 — fetch messages
    await _fetchMessages();

    // Step 7 — mark as read
    _markAsRead();

    // Step 8 — check chat session status
    if (_conversationId != null) {
      _checkChatSession();
    }
  }


  Future<void> _checkChatSession() async {
    final convId = _conversationId;
    if (convId == null || convId.isEmpty) return;
    final result = await ApiService.getChatSessionStatus(convId);
    if (!mounted) return;

    // Settings come from admin panel — only apply if API responded successfully
    final settings = result?['settings'] as Map<String, dynamic>?;
    final extDays = (settings?['extensionDays'] as num?)?.toInt();
    final extPrice = (settings?['extensionPrice'] as num?)?.toDouble();

    setState(() {
      _chatSessionLoaded = true;
      _adminSettingsAvailable = result != null && settings != null;
      // Chat is free — if API fails or returns null, always allow chat
      _canChat = result == null ? true : (result['canChat'] == true);
      _daysLeft = (result?['daysLeft'] as num?)?.toInt() ?? 3650;
      _isFreeChat = result == null ? true : (result['isFree'] == true);
      // Only update if admin returned a value — never use a local default
      if (extDays != null) _extensionDays = extDays;
      if (extPrice != null) _extensionPrice = extPrice;
      final expiresStr = result?['expiresAt']?.toString();
      _chatExpiresAt = expiresStr != null
          ? DateTime.tryParse(expiresStr)
          : null;
    });
  }

  Future<void> _fetchMessages({
    bool loadMore = false,
    bool markRead = false,
  }) async {
    final convId = _conversationId;
    final userId = _currentUserId;
    if (convId == null || userId == null) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _isLoadingMore = false;
        });
      }
      return;
    }

    if (loadMore) {
      if (_isLoadingMore || _messages.isEmpty) return;
      setState(() => _isLoadingMore = true);
    }

    try {
      String? before;
      if (loadMore && _messages.isNotEmpty) {
        // Oldest message is at the END of the list (reversed display)
        before = _messages.last['createdAt']?.toString();
      }

      final raw = await ApiService.fetchMessages(
        convId,
        userId,
        before: before,
      );
      final mapped = raw.map(_mapApiMessage).toList();

      if (mounted) {
        setState(() {
          if (loadMore) {
            _messages.addAll(mapped);
          } else {
            // Keep temporary messages that are still sending
            final tempMessages = _messages
                .where((m) => m['id']?.toString().startsWith('temp_') == true)
                .toList();
            _messages = mapped;
            for (final temp in tempMessages) {
              if (!_messages.any((m) => m['id'] == temp['id'])) {
                _messages.add(temp);
              }
            }
          }
          _sortMessages();
          _isLoading = false;
          _isLoadingMore = false;
        });

        // Mark conversation as read whenever new messages are fetched
        if (markRead) _markAsRead();
      }
    } catch (e) {
      debugPrint('_fetchMessages error: $e');
      if (mounted) {
        setState(() {
          _isLoading = false;
          _isLoadingMore = false;
        });
      }
    }
  }

  /// Normalise a raw API message into our local map format.
  Map<String, dynamic> _mapApiMessage(Map<String, dynamic> m) {
    String senderId = '';
    if (m['senderId'] != null) {
      senderId = m['senderId'].toString();
    } else if (m['sender'] != null) {
      if (m['sender'] is Map) {
        senderId = (m['sender']['id'] ?? m['sender']['_id'] ?? '').toString();
      } else {
        senderId = m['sender'].toString();
      }
    }

    final type = _safeString(m['type'], 'text');
    final invStatus = _safeString(m['invitationStatus'], 'pending');

    return {
      'id': _safeString(m['id'] ?? m['_id']),
      'clientMessageId': m['clientMessageId']?.toString(),
      'type': type,
      'text': _safeString(m['content'] ?? m['text']),
      'mediaUrl': m['mediaUrl']?.toString(),
      'mediaMimeType': m['mediaMimeType']?.toString(),
      'duration': type == 'voice' || type == 'audio'
          ? _safeInt(m['duration'] ?? m['content'], 5)
          : null,
      'fileSize': m['fileSize'],
      'waveformData': m['waveformData']?.toString(),
      'replyToMessageId': m['replyToMessageId']?.toString(),
      'isSent': senderId.isNotEmpty && senderId.toLowerCase() == _currentUserId?.toLowerCase(),
      'createdAt': m['createdAt']?.toString(),
      'isDeleted': m['isDeleted'] == true || m['deletedAt'] != null,
      'status': _safeString(m['status'], 'sent'),
      // Invitation fields
      if (type == 'invitation') ...{
        'isInvitation': true,
        'invitationStatus': invStatus,
        'invitationRef': m['invitationRef']?.toString(),
        'invitationTime': m['invitationTime']?.toString() ?? '',
        'venue': m['invitationRef']?.toString() ?? 'Venue Invite',
        'date': m['invitationTime']?.toString() ?? '',
      },
    };
  }

  // ── Scroll ──────────────────────────────────────────────────────────────────

  void _onScroll() {
    // ListView is reversed, so "end" = older messages
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 200) {
      _fetchMessages(loadMore: true);
    }
  }

  // ── Send ────────────────────────────────────────────────────────────────────

  Future<void> _sendMessage({String type = 'text', String? content}) async {
    final text = content ?? _messageController.text.trim();
    if (text.isEmpty) return;

    final convId = _conversationId;
    final userId = _currentUserId;
    if (convId == null || userId == null) return;

    final tempId = 'temp_${DateTime.now().millisecondsSinceEpoch}';

    // Optimistic insert
    final optimistic = {
      'id': tempId,
      'clientMessageId': tempId,
      'type': type,
      'text': text,
      'isSent': true,
      'createdAt': DateTime.now().toIso8601String(),
      'isDeleted': false,
      'status': 'sent',
      if (type == 'icebreaker') ...{'isIcebreaker': true},
    };

    setState(() {
      _messages.insert(0, optimistic);
      _sortMessages();
      _isSending = true;
    });
    _messageController.clear();

    try {
      final result = await ApiService.sendMessage(
        convId,
        senderId: userId,
        type: type,
        content: text,
        clientMessageId: tempId,
      );

      if (result != null && mounted) {
        // Replace temp with real message
        final idx = _messages.indexWhere((m) =>
            m['id'] == tempId || m['clientMessageId'] == tempId);
        if (idx != -1) {
          setState(() {
            _messages[idx] = _mapApiMessage(result);
            _sortMessages();
          });
        }
      } else if (mounted) {
        // Remove temp message if send failed
        setState(() => _messages.removeWhere((m) =>
            m['id'] == tempId || m['clientMessageId'] == tempId));
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to send message. Please try again.')),
        );
      }
    } catch (e) {
      debugPrint('_sendMessage error: $e');
      // Roll back optimistic
      if (mounted) {
        setState(() => _messages.removeWhere((m) =>
            m['id'] == tempId || m['clientMessageId'] == tempId));
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Error sending message.')),
        );
      }
    } finally {
      if (mounted) setState(() => _isSending = false);
    }
  }

  Future<void> _openIcebreakers() async {
    final selected = await IcebreakerModal.show(context);
    if (selected != null && selected.isNotEmpty) {
      await _sendMessage(type: 'icebreaker', content: selected);
    }
  }

  // ── Invitation Response ──────────────────────────────────────────────────────

  Future<void> _respondInvitation(String messageId, String action) async {
    // Chat is free — no session expiry check needed
    final convId = _conversationId;
    final userId = _currentUserId;
    if (convId == null || userId == null) return;

    final ok = await ApiService.respondToInvitation(
      convId,
      messageId,
      userId: userId,
      action: action,
    );

    if (ok && mounted) {
      setState(() {
        final idx = _messages.indexWhere((m) => m['id'] == messageId);
        if (idx != -1) {
          _messages[idx] = {
            ..._messages[idx],
            'invitationStatus': action == 'accept' ? 'accepted' : 'declined',
          };
        }
      });
    }
  }

  // ── Delete ───────────────────────────────────────────────────────────────────

  Future<void> _confirmDelete(String messageId) async {
    final convId = _conversationId;
    final userId = _currentUserId;
    if (convId == null || userId == null) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text(
          'Delete message?',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
        content: const Text('This message will be removed for everyone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    final ok = await ApiService.deleteMessage(convId, messageId, userId);
    if (ok && mounted) {
      setState(() {
        final idx = _messages.indexWhere((m) => m['id'] == messageId);
        if (idx != -1) {
          _messages[idx] = {
            ..._messages[idx],
            'isDeleted': true,
            'text': '[Message deleted]',
          };
        }
      });
    }
  }

  // ── Build ────────────────────────────────────────────────────────────────────

  /// Builds a CircleAvatar that gracefully falls back to a gradient + initial
  /// when the network image is missing or returns a 4xx/5xx error.
  Widget _buildAvatarWithFallback({double radius = 20}) {
    String? imageUrl = (widget.user['image'] ?? widget.user['profileImage'] ?? widget.user['profilePicture']) as String?;
    final isAsset = widget.user['isAsset'] == true;

    Widget fallback = Container(
      width: radius * 2,
      height: radius * 2,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: Color(0xFF008069),
      ),
      alignment: Alignment.center,
      child: Icon(Icons.person, color: Colors.white, size: radius * 1.2),
    );

    if (imageUrl == null || imageUrl.isEmpty) return fallback;

    if (isAsset) {
      return CircleAvatar(
        radius: radius,
        backgroundImage: AssetImage(imageUrl),
        backgroundColor: Colors.grey[200],
      );
    }

    if (!imageUrl.startsWith('http') && !imageUrl.startsWith('assets/')) {
      final cleanPath = imageUrl.startsWith('/') ? imageUrl : '/$imageUrl';
      imageUrl = '${ApiService.baseUrl}$cleanPath';
    }

    return ClipOval(
      child: Image.network(
        imageUrl,
        width: radius * 2,
        height: radius * 2,
        fit: BoxFit.cover,
        errorBuilder: (context, error, stackTrace) => fallback,
        loadingBuilder: (_, child, progress) {
          if (progress == null) return child;
          return Container(
            width: radius * 2,
            height: radius * 2,
            color: Colors.grey[200],
            child: Center(
              child: CircularProgressIndicator(
                strokeWidth: 1.5,
                value: progress.expectedTotalBytes != null
                    ? progress.cumulativeBytesLoaded /
                          progress.expectedTotalBytes!
                    : null,
                color: const Color(0xFF7F00FF),
              ),
            ),
          );
        },
      ),
    );
  }

  String _formatMessageTime(String? isoString) {
    if (isoString == null) return '';
    final dt = DateTime.tryParse(isoString)?.toLocal();
    if (dt == null) return '';
    final hour = dt.hour > 12 ? dt.hour - 12 : (dt.hour == 0 ? 12 : dt.hour);
    final minute = dt.minute.toString().padLeft(2, '0');
    final ampm = dt.hour >= 12 ? 'PM' : 'AM';
    return '$hour:$minute $ampm';
  }

  @override
  Widget build(BuildContext context) {
    final bool chatExpired = _chatSessionLoaded && !_canChat;
    final bool expiringSoon = _chatSessionLoaded && _canChat && _daysLeft <= 2;

    return Scaffold(
      backgroundColor: const Color(0xFFFAFAFC),
      appBar: _buildAppBar(context),
      body: Stack(
        children: [
          // Background subtle pattern
          Positioned.fill(
            child: Container(
              color: const Color(0xFFFAFAFC),
              child: Stack(
                children: [
                  Positioned(
                    top: 40, right: 30,
                    child: Icon(Icons.star_rounded, color: const Color(0xFF7C3AED).withValues(alpha: 0.04), size: 24),
                  ),
                  Positioned(
                    top: 180, left: 20,
                    child: Icon(Icons.star_rounded, color: const Color(0xFFE100FF).withValues(alpha: 0.04), size: 18),
                  ),
                  Positioned(
                    bottom: 120, right: 40,
                    child: Icon(Icons.circle_outlined, color: const Color(0xFF7C3AED).withValues(alpha: 0.03), size: 60),
                  ),
                ],
              ),
            ),
          ),
          SafeArea(
            child: Column(
              children: [
                // Event context card if linked
                _buildEventContextCard(),

                // Expiry warning banner
                if (expiringSoon) _buildExpiryBanner(),
                Expanded(
                  child: _isLoading
                      ? const Center(
                          child: CircularProgressIndicator(color: Color(0xFF7C3AED)),
                        )
                      : chatExpired
                      ? _buildChatExpiredState()
                      : _canChat || !_chatSessionLoaded
                      ? _buildMessageList()
                      : _buildNoAccessState(),
                ),
                if (_isBlocked)
                  Container(
                    width: double.infinity,
                    color: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
                    child: const Center(
                      child: Text(
                        'You blocked this user. Unblock to send messages.',
                        style: TextStyle(
                          color: Colors.red,
                          fontWeight: FontWeight.bold,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  )
                else if (chatExpired)
                  _buildExpiredInputBar()
                else if (_canChat || !_chatSessionLoaded)
                  _buildInputArea(context),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEventContextCard() {
    final contextType = widget.user['contextType']?.toString();
    final eventTitle = widget.user['eventTitle']?.toString() ?? widget.user['subject']?.toString() ?? widget.user['planName']?.toString();
    final venueName = widget.user['venueName']?.toString() ?? widget.user['venue']?['name']?.toString() ?? widget.user['location']?.toString() ?? 'Favela';
    final eventTime = widget.user['eventTime']?.toString() ?? 'Today, 8:00 PM';

    if (contextType == null && widget.user['planId'] == null && eventTitle == null) {
      return const SizedBox.shrink();
    }

    final title = eventTitle ?? 'College Party';

    return GestureDetector(
      onTap: () {
        // Tapping event card opens event detail screen if applicable
      },
      child: Container(
        margin: const EdgeInsets.fromLTRB(16, 8, 16, 4),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: const Color(0xFFFAF5FF),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFFF3E8FF)),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: const Color(0xFFF3E8FF),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Text('🎉', style: TextStyle(fontSize: 18)),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                      color: Color(0xFF6B21A8),
                    ),
                  ),
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      const Icon(Icons.location_on_outlined, size: 12, color: Color(0xFF7C3AED)),
                      const SizedBox(width: 2),
                      Text(venueName, style: const TextStyle(fontSize: 11, color: Color(0xFF64748B))),
                      const SizedBox(width: 6),
                      const Icon(Icons.access_time_rounded, size: 12, color: Color(0xFF7C3AED)),
                      const SizedBox(width: 2),
                      Text(eventTime, style: const TextStyle(fontSize: 11, color: Color(0xFF64748B))),
                    ],
                  ),
                ],
              ),
            ),
            const Row(
              children: [
                Text(
                  'View details',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF7C3AED),
                  ),
                ),
                Icon(Icons.chevron_right_rounded, size: 16, color: Color(0xFF7C3AED)),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // ── Chat Session UI Helpers ──────────────────────────────────────────────────

  Widget _buildExpiryBanner() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      color: Colors.orange.shade700,
      child: Row(
        children: [
          const Icon(Icons.timer_rounded, color: Colors.white, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              _daysLeft == 0
                  ? 'Chat expires today!'
                  : 'Chat expires in $_daysLeft day${_daysLeft == 1 ? '' : 's'}.',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          // Only show EXTEND chip when admin has configured the price
          if (_adminSettingsAvailable && _extensionPrice != null)
            GestureDetector(
              onTap: _showExtendOptions,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Text(
                  'EXTEND',
                  style: TextStyle(
                    color: Colors.orange,
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildChatExpiredState() {
    final price = _extensionPrice;
    final days = _extensionDays;
    final adminReady = _adminSettingsAvailable && price != null && days != null;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: Colors.grey.shade100,
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.lock_clock_rounded,
                size: 56,
                color: Color(0xFF7F00FF),
              ),
            ),
            const SizedBox(height: 24),
            const Text(
              'Chat Period Ended',
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w900,
                color: Colors.black87,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              adminReady
                  ? 'Your free chat window has expired. Pay ₹${price.toStringAsFixed(0)} to continue chatting for $days more days.'
                  : 'Your chat window has expired. Pricing is managed by the admin — please wait for configuration.',
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.black54,
                fontSize: 14,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 32),
            if (adminReady) ...[
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _showExtendOptions,
                  icon: const Icon(Icons.bolt_rounded),
                  label: Text('EXTEND FOR ₹${price.toStringAsFixed(0)}'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF7F00FF),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: _requestOtherToPay,
                  icon: const Icon(Icons.person_add_alt_1_rounded),
                  label: const Text('ASK THEM TO PAY'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFF7F00FF),
                    side: const BorderSide(color: Color(0xFF7F00FF)),
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                ),
              ),
            ] else
              _buildAdminPendingBadge(),
          ],
        ),
      ),
    );
  }

  Widget _buildNoAccessState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: Colors.grey.shade100,
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.chat_bubble_outline_rounded,
                size: 56,
                color: Colors.grey,
              ),
            ),
            const SizedBox(height: 24),
            const Text(
              'No one available yet',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w800,
                color: Colors.black87,
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              'When both of you match and connect, your chat will open automatically.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.black54,
                fontSize: 14,
                height: 1.5,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildExpiredInputBar() {
    final price = _extensionPrice;
    final adminReady = _adminSettingsAvailable && price != null;

    return Container(
      padding: const EdgeInsets.all(16),
      color: Colors.white,
      child: adminReady
          ? Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _showExtendOptions,
                    icon: const Icon(Icons.bolt_rounded, size: 18),
                    label: Text('Extend Chat – ₹${price.toStringAsFixed(0)}'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF7F00FF),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                OutlinedButton(
                  onPressed: _requestOtherToPay,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFF7F00FF),
                    side: const BorderSide(color: Color(0xFF7F00FF)),
                    padding: const EdgeInsets.symmetric(
                      vertical: 12,
                      horizontal: 12,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: const Icon(Icons.person_add_alt_1_rounded, size: 20),
                ),
              ],
            )
          : _buildAdminPendingBadge(),
    );
  }

  /// Shown when admin has not yet configured chat pricing
  Widget _buildAdminPendingBadge() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.amber.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.amber.shade300),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.admin_panel_settings_rounded,
            size: 18,
            color: Colors.amber.shade700,
          ),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              'Chat extension is managed by the admin. Please check back later.',
              style: TextStyle(
                color: Colors.amber.shade800,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
              textAlign: TextAlign.center,
            ),
          ),
        ],
      ),
    );
  }

  void _showExtendOptions() {
    final price = _extensionPrice;
    final days = _extensionDays;

    // Block if admin hasn't configured pricing
    if (!_adminSettingsAvailable || price == null || days == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(
                Icons.admin_panel_settings_rounded,
                color: Colors.white,
                size: 18,
              ),
              const SizedBox(width: 8),
              const Expanded(
                child: Text('Chat extension charges are managed by the admin.'),
              ),
            ],
          ),
          backgroundColor: Colors.amber.shade700,
          duration: const Duration(seconds: 3),
        ),
      );
      return;
    }

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(
                  Icons.admin_panel_settings_rounded,
                  color: Color(0xFF7F00FF),
                  size: 20,
                ),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    'Extend Your Chat',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              'Admin-configured pricing: ₹${price.toStringAsFixed(0)} for $days days.',
              style: const TextStyle(color: Colors.black54, fontSize: 13),
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () async {
                  Navigator.pop(ctx);
                  await _payToExtend();
                },
                icon: const Icon(Icons.payment_rounded),
                label: Text('PAY ₹${price.toStringAsFixed(0)} NOW'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF7F00FF),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () async {
                  Navigator.pop(ctx);
                  await _requestOtherToPay();
                },
                icon: const Icon(Icons.person_add_alt_1_rounded),
                label: const Text('ASK THEM TO PAY'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFF7F00FF),
                  side: const BorderSide(color: Color(0xFF7F00FF)),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _payToExtend() async {
    final convId = _conversationId;
    final days = _extensionDays;
    if (convId == null || !_adminSettingsAvailable) return;
    // In a real flow, open Razorpay here and pass the paymentId
    final ok = await ApiService.extendChat(convId);
    if (ok && mounted) {
      await _checkChatSession();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('✅ Chat extended for ${days ?? '?'} days!'),
          backgroundColor: const Color(0xFF7F00FF),
        ),
      );
    }
  }

  Future<void> _requestOtherToPay() async {
    final convId = _conversationId;
    final targetId = widget.user['id']?.toString();
    if (convId == null || targetId == null) return;
    if (!_adminSettingsAvailable) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text(
            'Cannot send request — admin pricing not configured.',
          ),
          backgroundColor: Colors.amber.shade700,
        ),
      );
      return;
    }
    final ok = await ApiService.requestChatExtension(convId, targetId);
    if (ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('✅ Extension request sent!'),
          backgroundColor: Colors.green,
        ),
      );
    }
  }

  PreferredSizeWidget _buildAppBar(BuildContext context) {
    return AppBar(
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.transparent,
      elevation: 0.5,
      shadowColor: const Color(0x0A000000),
      centerTitle: false,
      leadingWidth: 76,
      leading: InkWell(
        onTap: () => Navigator.pop(context),
        borderRadius: BorderRadius.circular(30),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(width: 8),
            const Icon(Icons.arrow_back_rounded, color: Color(0xFF7C3AED), size: 24),
            const SizedBox(width: 4),
            _buildAvatarWithFallback(radius: 20),
          ],
        ),
      ),
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            widget.user['name']?.toString() ??
             (widget.user['firstName'] != null
                 ? '${widget.user['firstName']} ${widget.user['lastName'] ?? ''}'.trim()
                 : 'User'),
            style: const TextStyle(
              color: Color(0xFF0F172A),
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (_isRecipientTyping) ...[
                const Text(
                  'typing...',
                  style: TextStyle(
                    color: Color(0xFF7C3AED),
                    fontSize: 11,
                    fontStyle: FontStyle.italic,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ] else if (_isOnline == true) ...[
                Container(
                  width: 7,
                  height: 7,
                  margin: const EdgeInsets.only(right: 5),
                  decoration: const BoxDecoration(
                    color: Color(0xFF25D366),
                    shape: BoxShape.circle,
                  ),
                ),
                const Text(
                  'Online',
                  style: TextStyle(
                    color: Color(0xFF25D366),
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ] else ...[
                Text(
                  _formatLastSeen(_lastActive),
                  style: const TextStyle(
                    color: Color(0xFF64748B),
                    fontSize: 11,
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
      actions: [
        IconButton(
          icon: const Icon(Icons.auto_awesome_rounded, color: Color(0xFF7C3AED), size: 20),
          onPressed: _openIcebreakers,
        ),
        PopupMenuButton<String>(
          icon: const Icon(Icons.more_vert_rounded, color: Color(0xFF7C3AED)),
          onSelected: (value) {
            if (value == 'block') {
              _toggleBlock();
            } else if (value == 'report') {
              _reportUser();
            }
          },
          itemBuilder: (BuildContext context) => <PopupMenuEntry<String>>[
            PopupMenuItem<String>(
              value: 'block',
              child: Text(_isBlocked ? 'Unblock User' : 'Block User'),
            ),
            const PopupMenuItem<String>(
              value: 'report',
              child: Text('Report User', style: TextStyle(color: Colors.red)),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildMessageList() {
    if (_messages.isEmpty) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.chat_bubble_outline_rounded,
              size: 48,
              color: Color(0xFF008069),
            ),
            SizedBox(height: 12),
            Text(
              'No messages yet.',
              style: TextStyle(
                color: Color(0xFF008069),
                fontWeight: FontWeight.w600,
              ),
            ),
            SizedBox(height: 4),
            Text(
              'Say hello! ⚡',
              style: TextStyle(color: Color(0xFF008069), fontSize: 13),
            ),
          ],
        ),
      );
    }

    return Stack(
      children: [
        ListView.builder(
          controller: _scrollController,
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          reverse: true,
          itemCount: _messages.length + (_isLoadingMore ? 1 : 0),
          itemBuilder: (context, index) {
            if (index == _messages.length) {
              return const Padding(
                padding: EdgeInsets.all(16),
                child: Center(
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Color(0xFF7F00FF),
                  ),
                ),
              );
            }
            final msg = _messages[index];
            final type = _safeString(msg['type'], 'text');

            try {
              if (type == 'invitation') {
                return _buildInvitationCard(msg);
              }
              if (type == 'pay_request') {
                return _buildPayRequestCard(msg);
              }
              if (type == 'system') {
                return _buildSystemMessage(msg);
              }
              return _buildMessageBubble(msg);
            } catch (e) {
              debugPrint('Error rendering chat message at index $index: $e');
              return _buildMessageBubble({
                'isSent': msg['isSent'] == true,
                'text': _safeString(msg['text'] ?? msg['content'], 'Message'),
                'type': 'text',
                'createdAt': msg['createdAt'],
                'status': 'sent',
              });
            }
          },
        ),
        if (_isSending)
          Positioned(
            bottom: 8,
            left: 0,
            right: 0,
            child: Center(
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.6),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Text(
                  'Sending...',
                  style: TextStyle(color: Colors.white, fontSize: 12),
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildMessageStatusIcon(String status, {bool isSent = false}) {
    final color = isSent ? Colors.white.withValues(alpha: 0.8) : const Color(0xFF94A3B8);
    if (status == 'pending') {
      return Icon(Icons.schedule, size: 13, color: color);
    } else if (status == 'read') {
      return Icon(
        Icons.done_all_rounded,
        size: 15,
        color: isSent ? Colors.white : const Color(0xFF34B7F1),
      );
    } else if (status == 'delivered') {
      return Icon(Icons.done_all_rounded, size: 15, color: color);
    } else {
      return Icon(Icons.done_rounded, size: 15, color: color);
    }
  }

  Widget _buildSystemMessage(Map<String, dynamic> msg) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 32),
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
          decoration: BoxDecoration(
            color: Colors.black12,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(
            msg['text']?.toString() ?? '',
            style: const TextStyle(
              fontSize: 12,
              color: Colors.black54,
              fontStyle: FontStyle.italic,
            ),
            textAlign: TextAlign.center,
          ),
        ),
      ),
    );
  }

  Widget _buildPayRequestCard(Map<String, dynamic> msg) {
    final isSent = msg['isSent'] == true;
    Map<String, dynamic> payload = {};
    try {
      final raw = _safeString(msg['text']);
      if (raw.startsWith('{')) {
        payload = Map<String, dynamic>.from(
          (jsonDecode(raw) as Map<dynamic, dynamic>).cast<String, dynamic>(),
        );
      }
    } catch (_) {}

    final requesterName = _safeString(payload['requesterName'], 'Your match');
    final extensionDays = _safeInt(payload['extensionDays'], _extensionDays ?? 7);
    final extensionPrice = (payload['extensionPrice'] as num?)?.toDouble() ?? _extensionPrice ?? 100.0;
    final requesterId = payload['requesterId']?.toString();

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
      child: Center(
        child: Container(
          constraints: const BoxConstraints(maxWidth: 300),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: const Color(0xFF7F00FF).withValues(alpha: 0.3),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.06),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.bolt_rounded,
                color: Color(0xFF7F00FF),
                size: 32,
              ),
              const SizedBox(height: 8),
              Text(
                isSent
                    ? 'You asked them to pay for $extensionDays more days.'
                    : '$requesterName is asking you to pay ₹${extensionPrice.toStringAsFixed(0)} for $extensionDays more days of chat.',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: Colors.black87,
                ),
              ),
              if (!isSent) ...[
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () async {
                      final convId = _conversationId;
                      if (convId == null) return;
                      final ok = await ApiService.acceptChatExtensionRequest(
                        convId,
                        requestedById: requesterId,
                      );
                      if (ok && mounted) {
                        await _checkChatSession();
                        if (!mounted) return;
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              '✅ Chat extended for $extensionDays days!',
                            ),
                            backgroundColor: const Color(0xFF7F00FF),
                          ),
                        );
                      }
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF7F00FF),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    child: Text(
                      'PAY ₹${extensionPrice.toStringAsFixed(0)} & EXTEND',
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMessageBubble(Map<String, dynamic> msg) {
    final isSent = msg['isSent'] == true;
    final isDeleted = msg['isDeleted'] == true;
    final type = _safeString(msg['type'], 'text');
    final isIcebreaker = type == 'icebreaker';
    final text = _safeString(msg['text']);
    final msgId = _safeString(msg['id']);
    final status = _safeString(msg['status'], 'sent');
    final timeStr = _formatMessageTime(msg['createdAt']?.toString());

    return GestureDetector(
      onLongPress:
          (isSent &&
              !isDeleted &&
              msgId.isNotEmpty &&
              !msgId.startsWith('temp_'))
          ? () => _confirmDelete(msgId)
          : null,
      child: Align(
        alignment: isSent ? Alignment.centerRight : Alignment.centerLeft,
        child: Container(
          margin: const EdgeInsets.only(bottom: 6),
          constraints: BoxConstraints(
            maxWidth: MediaQuery.of(context).size.width * 0.76,
          ),
          decoration: BoxDecoration(
            color: isDeleted
                ? const Color(0xFFF1F5F9)
                : (isSent ? const Color(0xFF7C3AED) : Colors.white),
            borderRadius: isSent
                ? const BorderRadius.only(
                    topLeft: Radius.circular(18),
                    topRight: Radius.circular(18),
                    bottomLeft: Radius.circular(18),
                    bottomRight: Radius.circular(4),
                  )
                : const BorderRadius.only(
                    topLeft: Radius.circular(18),
                    topRight: Radius.circular(18),
                    bottomLeft: Radius.circular(4),
                    bottomRight: Radius.circular(18),
                  ),
            border: isSent
                ? null
                : Border.all(color: const Color(0xFFE2E8F0), width: 1),
            boxShadow: const [
              BoxShadow(
                color: Color(0x06000000),
                blurRadius: 8,
                offset: Offset(0, 2),
              ),
            ],
          ),
          child: isDeleted
              ? Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 10,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.block_rounded,
                        size: 14,
                        color: Colors.grey[500],
                      ),
                      const SizedBox(width: 6),
                      Text(
                        '[Message deleted]',
                        style: TextStyle(
                          color: Colors.grey[500],
                          fontStyle: FontStyle.italic,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                )
              : _buildTextBubbleContent(
                  text,
                  timeStr,
                  isSent,
                  isIcebreaker,
                  status,
                ),
        ),
      ),
    );
  }

  Widget _buildTextBubbleContent(
    String text,
    String timeStr,
    bool isSent,
    bool isIcebreaker,
    String status,
  ) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 10, 12, 8),
      child: Column(
        crossAxisAlignment: isSent ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (isIcebreaker) ...[
                const Text('⚡ ', style: TextStyle(fontSize: 14)),
              ],
              Flexible(
                child: Text(
                  text,
                  style: TextStyle(
                    color: isSent ? Colors.white : const Color(0xFF0F172A),
                    fontSize: 14.5,
                    height: 1.3,
                    fontWeight: isIcebreaker ? FontWeight.bold : FontWeight.w400,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                timeStr,
                style: TextStyle(
                  color: isSent ? Colors.white.withValues(alpha: 0.7) : const Color(0xFF94A3B8),
                  fontSize: 10,
                ),
              ),
              if (isSent) ...[
                const SizedBox(width: 4),
                _buildMessageStatusIcon(status, isSent: isSent),
              ],
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildInvitationCard(Map<String, dynamic> msg) {
    final isSent = msg['isSent'] == true;
    final venue = _safeString(msg['venue'], 'Venue Invite');
    final date = _safeString(msg['date'].toString().isNotEmpty ? msg['date'] : msg['invitationTime']);
    final status = _safeString(msg['invitationStatus'], 'pending');
    final msgId = _safeString(msg['id']);
    final msgStatus = _safeString(msg['status'], 'sent');
    final timeStr = _formatMessageTime(msg['createdAt']?.toString());

    return Align(
      alignment: isSent ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        width: 260,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFFDCF8C6), width: 1),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.06),
              blurRadius: 4,
              offset: const Offset(0, 1),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: const BoxDecoration(
                color: Color(0xFF7F00FF),
                borderRadius: BorderRadius.vertical(top: Radius.circular(11)),
              ),
              child: const Row(
                children: [
                  Text('🎉', style: TextStyle(fontSize: 14)),
                  SizedBox(width: 6),
                  Text(
                    'INVITATION',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1.5,
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    venue,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                      color: Colors.black,
                    ),
                  ),
                  const SizedBox(height: 4),
                  if (date.isNotEmpty)
                    Text(
                      date,
                      style: TextStyle(color: Colors.grey[600], fontSize: 13),
                    ),
                  const SizedBox(height: 12),
                  if (status == 'pending' && !isSent) ...[
                    Row(
                      children: [
                        Expanded(
                          child: _inviteButton(
                            'ACCEPT',
                            true,
                            () => _respondInvitation(msgId, 'accept'),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: _inviteButton(
                            'DECLINE',
                            false,
                            () => _respondInvitation(msgId, 'decline'),
                          ),
                        ),
                      ],
                    ),
                  ] else ...[
                    Container(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      decoration: BoxDecoration(
                        color: status == 'accepted'
                            ? const Color(0xFFE8F5E9)
                            : const Color(0xFFFFEBEE),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        status == 'accepted' ? '✅ Accepted' : '❌ Declined',
                        style: TextStyle(
                          color: status == 'accepted'
                              ? const Color(0xFF2E7D32)
                              : const Color(0xFFC62828),
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(height: 6),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      Text(
                        timeStr,
                        style: TextStyle(color: Colors.grey[500], fontSize: 10),
                      ),
                      if (isSent) ...[
                        const SizedBox(width: 4),
                        _buildMessageStatusIcon(msgStatus),
                      ],
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _inviteButton(String label, bool isPrimary, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(
          color: isPrimary ? const Color(0xFF00A884) : Colors.grey[200],
          borderRadius: BorderRadius.circular(8),
        ),
        alignment: Alignment.center,
        child: Text(
          label,
          style: TextStyle(
            color: isPrimary ? Colors.white : Colors.grey[700],
            fontWeight: FontWeight.bold,
            fontSize: 12,
          ),
        ),
      ),
    );
  }

  Widget _buildInputArea(BuildContext context) {
    final hasText = _messageController.text.trim().isNotEmpty;

    return Container(
      margin: const EdgeInsets.fromLTRB(14, 4, 14, 12),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(30),
        boxShadow: const [
          BoxShadow(
            color: Color(0x12000000),
            blurRadius: 18,
            offset: Offset(0, 6),
          ),
        ],
      ),
      child: Row(
        children: [
          const SizedBox(width: 12),
          Expanded(
            child: TextField(
              controller: _messageController,
              focusNode: _focusNode,
              style: const TextStyle(color: Color(0xFF0F172A), fontSize: 15),
              maxLines: 4,
              minLines: 1,
              decoration: const InputDecoration(
                hintText: 'Type a message...',
                hintStyle: TextStyle(
                  color: Color(0xFF94A3B8),
                  fontSize: 15,
                ),
                border: InputBorder.none,
                isDense: true,
                contentPadding: EdgeInsets.symmetric(vertical: 10),
              ),
              onChanged: (text) {
                setState(() {});
              },
            ),
          ),
          const SizedBox(width: 4),
          GestureDetector(
            onTap: hasText ? _sendMessage : null,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: hasText ? const Color(0xFF7C3AED) : const Color(0xFFF3E8FF),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.send_rounded,
                color: hasText ? Colors.white : const Color(0xFFC4B5FD),
                size: 20,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
