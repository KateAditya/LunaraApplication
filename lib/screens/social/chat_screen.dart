import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../../services/api_service.dart';
import 'icebreaker_modal.dart';
import 'venue_invite_picker_screen.dart';
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
  bool _showEmoji = false;
  bool _isBlocked = false;

  String? _conversationId;
  String? _currentUserId;
  Timer? _statusTimer;

  // Live online status (fetched from API, overrides widget.user['online'])
  bool? _isOnline;
  String? _lastActive;

  bool _isRecording = false;
  int _recordingDuration = 0;
  Timer? _recordingTimer;

  // ── Chat Session / Subscription state ───────────────────────────────────────
  // NOTE: These are ALWAYS loaded from admin-panel settings via the API.
  // No hardcoded defaults — if admin hasn't configured yet, UI shows disabled state.
  bool _chatSessionLoaded = false;
  bool _canChat = true;         // optimistic default until API responds
  int _daysLeft = 0;
  // ignore: unused_field
  bool _isFreeChat = false;
  int? _extensionDays;           // null until admin config loaded
  double? _extensionPrice;       // null until admin config loaded
  // ignore: unused_field
  DateTime? _chatExpiresAt;
  bool _adminSettingsAvailable = false; // true only when admin responded

  String? _playingMessageId;
  double _playbackProgress = 0.0;
  int _playbackSeconds = 0;
  Timer? _playbackTimer;

  final List<String> _emojis = [
    '😀', '😃', '😄', '😁', '😆', '😅', '😂', '🤣', '😊', '😇',
    '🙂', '🙃', '😉', '😌', '😍', '🥰', '😘', '😗', '😙', '😚',
    '😋', '😛', '😝', '😜', '🤪', '🤨', '🧐', '🤓', '😎', '🥸',
    '🤩', '🥳', '😏', '😒', '😞', '😔', '😟', '😕', '🙁', '☹️',
    '😣', '😖', '😫', '😩', '🥺', '😢', '😭', '😤', '😠', '😡',
    '🤬', '🤯', '😳', '🥵', '🥶', '😱', '😨', '😰', '😥', '😓',
    '🤗', '🤔', '🫣', '🤭', '🤫', '🤥', '😶', '😶‍🌫️', '😐', '😑',
    '😬', '🫨', '🫠', '😴', '😷', '🤒', '🤕', '🤢',
    '🤮', '🤧', '🥴', '😵', '😵‍💫', '🤠', '👿', '💀', '☠️', '💩',
    '🤡', '👹', '👺', '👻', '👽', '👾', '🤖', '👋', '🤚', '🖐️',
    '👌', '🤌', '🤏', '✌️', '🤞', '🫰', '🤟', '🤘', '🤙', '👈',
    '👉', '👆', '🖕', '👇', '☝️', '👍', '👎', '✊', '👊', '🤛',
    '🤜', '👏', '🙌', '👐', '🤲', '🤝', '🙏', '✍️', '💅', '🤳',
    '💪', '🦾', '🦿', '🦵', '🦶', '👂', '🦻', '👃', '🧠', '🫀',
    '🫁', '🦷', '🦴', '👀', '👁️', '👅', '👄', '💋', '🩸', '❤️',
    '🧡', '💛', '💚', '💙', '💜', '🖤', '🤍', '🤎', '💔', '❤️‍🔥',
    '❤️‍🩹', '❣️', '💕', '💞', '💓', '💗', '💖', '💘', '💝', '💟'
  ];

  void _onEmojiSelected(String emoji) {
    final text = _messageController.text;
    final selection = _messageController.selection;
    final newText = text.replaceRange(
      selection.start == -1 ? text.length : selection.start,
      selection.end == -1 ? text.length : selection.end,
      emoji,
    );
    _messageController.text = newText;
    _messageController.selection = TextSelection.fromPosition(
      TextPosition(offset: (selection.start == -1 ? text.length : selection.start) + emoji.length),
    );
    setState(() {});
  }

  void _onBackspacePressed() {
    final text = _messageController.text;
    final selection = _messageController.selection;
    if (text.isEmpty) return;
    int start = selection.start;
    int end = selection.end;
    if (start == -1) {
      start = text.length;
      end = text.length;
    }
    
    if (start == end) {
      if (start == 0) return;
      final beforeCursor = text.substring(0, start);
      final afterCursor = text.substring(end);
      final beforeChars = beforeCursor.characters;
      if (beforeChars.isEmpty) return;
      final newBefore = beforeChars.skipLast(1).toString();
      _messageController.text = newBefore + afterCursor;
      _messageController.selection = TextSelection.fromPosition(
        TextPosition(offset: newBefore.length),
      );
    } else {
      _messageController.text = text.replaceRange(start, end, '');
      _messageController.selection = TextSelection.fromPosition(
        TextPosition(offset: start),
      );
    }
    setState(() {});
  }

  Widget _buildEmojiPicker() {
    if (!_showEmoji) return const SizedBox.shrink();
    
    return Container(
      height: 250,
      color: const Color(0xFFF4F4F4),
      child: Column(
        children: [
          Expanded(
            child: GridView.builder(
              padding: const EdgeInsets.all(8),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 8,
                mainAxisSpacing: 8,
                crossAxisSpacing: 8,
              ),
              itemCount: _emojis.length,
              itemBuilder: (context, index) {
                final emoji = _emojis[index];
                return InkWell(
                  onTap: () => _onEmojiSelected(emoji),
                  borderRadius: BorderRadius.circular(8),
                  child: Center(
                    child: Text(
                      emoji,
                      style: const TextStyle(fontSize: 24),
                    ),
                  ),
                );
              },
            ),
          ),
          Container(
            color: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                IconButton(
                  icon: const Icon(Icons.backspace_outlined, color: Color(0xFF008069)),
                  onPressed: _onBackspacePressed,
                ),
              ],
            ),
          ),
        ],
      ),
    );
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

  void _initSocketListeners() {
    ApiService.socket?.on('new_message', (data) {
      if (!mounted) return;
      if (data['conversationId'] == _conversationId) {
        setState(() {
          _messages.insert(0, _mapApiMessage(Map<String, dynamic>.from(data)));
          _sortMessages();
        });
        _markAsRead();
      }
    });

    ApiService.socket?.on('messages_read', (data) {
      if (!mounted) return;
      if (data['conversationId'] == _conversationId) {
        setState(() {
          for (var i = 0; i < _messages.length; i++) {
            if (_messages[i]['isSent'] == true) {
              _messages[i]['status'] = 'read';
            }
          }
        });
      }
    });

    ApiService.socket?.on('user_status_changed', (data) {
      if (!mounted) return;
      if (data['userId'] == widget.user['id']) {
        setState(() {
          _isOnline = data['isOnline'] == true;
          _lastActive = data['lastActiveAt']?.toString();
        });
      }
    });

    ApiService.socket?.on('messages_delivered', (data) {
      if (!mounted) return;
      if (data['conversationId'] == _conversationId) {
        setState(() {
          for (var i = 0; i < _messages.length; i++) {
            if (_messages[i]['isSent'] == true && _messages[i]['status'] == 'sent') {
              _messages[i]['status'] = 'delivered';
            }
          }
        });
      }
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _markAsRead();
      _fetchUserStatus(); // Refresh status when app comes to foreground
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    ApiService.socket?.off('new_message');
    ApiService.socket?.off('messages_read');
    ApiService.socket?.off('user_status_changed');
    ApiService.socket?.off('messages_delivered');
    _statusTimer?.cancel();
    _recordingTimer?.cancel();
    _playbackTimer?.cancel();
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
    showDialog(context: context, builder: (ctx) => AlertDialog(
      title: const Text('Report User'),
      content: const Text('Are you sure you want to report and block this user?'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
        TextButton(
          onPressed: () async {
            Navigator.pop(ctx);
            await BlockService.reportUser(otherUserId, 'Inappropriate behavior');
            _checkBlockStatus();
            if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('User reported and blocked')));
          },
          child: const Text('Report', style: TextStyle(color: Colors.red)),
        ),
      ],
    ));
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
      _lastActive = result['lastActive']?.toString() ?? result['lastSeen']?.toString();
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
      final aTime = DateTime.tryParse(aStr) ?? DateTime.fromMillisecondsSinceEpoch(0);
      final bTime = DateTime.tryParse(bStr) ?? DateTime.fromMillisecondsSinceEpoch(0);
      return bTime.compareTo(aTime); // descending (newest first)
    });
  }

  // ── Init ────────────────────────────────────────────────────────────────────

  Future<void> _initChat() async {
    final userId = _currentUserId;
    final otherUserId = widget.user['id']?.toString();

    if (userId == null || otherUserId == null || otherUserId.isEmpty) {
      if (mounted) setState(() => _isLoading = false);
      return;
    }

    // Step 3 — create or get conversation
    final existingConvId = widget.user['conversationId']?.toString();
    String? convId = existingConvId?.isNotEmpty == true ? existingConvId : null;

    convId ??= await ApiService.createOrGetConversation(
        userId: userId,
        otherUserId: otherUserId,
        contextType: widget.user['contextType'] as String?,
        contextId: widget.user['planId'] as String?,
      );

    if (!mounted) return;
    _conversationId = convId;

    if (convId == null) {
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
      _canChat = result?['canChat'] == true;
      _daysLeft = (result?['daysLeft'] as num?)?.toInt() ?? 0;
      _isFreeChat = result?['isFree'] == true;
      // Only update if admin returned a value — never use a local default
      if (extDays != null) _extensionDays = extDays;
      if (extPrice != null) _extensionPrice = extPrice;
      final expiresStr = result?['expiresAt']?.toString();
      _chatExpiresAt = expiresStr != null ? DateTime.tryParse(expiresStr) : null;
    });
  }

  Future<void> _fetchMessages({bool loadMore = false, bool markRead = false}) async {
    final convId = _conversationId;
    final userId = _currentUserId;
    if (convId == null || userId == null) return;

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

      final raw = await ApiService.fetchMessages(convId, userId, before: before);
      final mapped = raw.map(_mapApiMessage).toList();

      if (mounted) {
        setState(() {
          if (loadMore) {
            _messages.addAll(mapped);
          } else {
            // Keep temporary messages that are still sending
            final tempMessages = _messages.where((m) => m['id']?.toString().startsWith('temp_') == true).toList();
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
      if (mounted) setState(() { _isLoading = false; _isLoadingMore = false; });
    }
  }

  /// Normalise a raw API message into our local map format.
  Map<String, dynamic> _mapApiMessage(Map<String, dynamic> m) {
    final senderId = m['senderId']?.toString() ?? m['sender']?.toString() ?? '';
    final type = (m['type'] ?? 'text').toString();
    final invStatus = m['invitationStatus']?.toString() ?? 'pending';

    return {
      'id': m['id']?.toString() ?? m['_id']?.toString() ?? '',
      'type': type,
      'text': m['content']?.toString() ?? m['text']?.toString() ?? '',
      'mediaUrl': m['mediaUrl']?.toString(),
      'isSent': senderId == _currentUserId,
      'createdAt': m['createdAt']?.toString(),
      'isDeleted': m['isDeleted'] == true || m['deletedAt'] != null,
      'status': m['status']?.toString() ?? 'sent',
      'duration': type == 'audio' ? (int.tryParse(m['content']?.toString() ?? '5') ?? 5) : null,
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
      'type': type,
      'text': text,
      'isSent': true,
      'createdAt': DateTime.now().toIso8601String(),
      'isDeleted': false,
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
      );

      if (result != null && mounted) {
        // Replace temp with real message
        final idx = _messages.indexWhere((m) => m['id'] == tempId);
        if (idx != -1) {
          setState(() {
            _messages[idx] = _mapApiMessage(result);
            _sortMessages();
          });
        }
      }
    } catch (e) {
      debugPrint('_sendMessage error: $e');
      // Roll back optimistic
      if (mounted) setState(() => _messages.removeWhere((m) => m['id'] == tempId));
    } finally {
      if (mounted) setState(() => _isSending = false);
    }
  }

  Future<void> _sendImageMessage(String imagePath) async {
    final convId = _conversationId;
    final userId = _currentUserId;
    if (convId == null || userId == null) return;

    final tempId = 'temp_${DateTime.now().millisecondsSinceEpoch}';

    // Optimistic insert
    final optimistic = {
      'id': tempId,
      'type': 'image',
      'mediaUrl': imagePath,
      'isSent': true,
      'createdAt': DateTime.now().toIso8601String(),
      'isDeleted': false,
    };

    setState(() {
      _messages.insert(0, optimistic);
      _sortMessages();
      _isSending = true;
    });

    try {
      final result = await ApiService.sendMessage(
        convId,
        senderId: userId,
        type: 'image',
        mediaUrl: imagePath,
      );

      if (result != null && mounted) {
        final idx = _messages.indexWhere((m) => m['id'] == tempId);
        if (idx != -1) {
          setState(() {
            _messages[idx] = _mapApiMessage(result);
            _sortMessages();
          });
        }
      }
    } catch (e) {
      debugPrint('_sendImageMessage error: $e');
      if (mounted) setState(() => _messages.removeWhere((m) => m['id'] == tempId));
    } finally {
      if (mounted) setState(() => _isSending = false);
    }
  }

  Future<void> _showCameraOptions() async {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (BuildContext context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.camera_alt_rounded, color: Color(0xFF008069)),
                title: const Text('Take a Photo', style: TextStyle(fontWeight: FontWeight.bold)),
                onTap: () {
                  Navigator.pop(context);
                  _pickAndSendImage(ImageSource.camera);
                },
              ),
              ListTile(
                leading: const Icon(Icons.photo_library_rounded, color: Color(0xFF008069)),
                title: const Text('Choose from Gallery', style: TextStyle(fontWeight: FontWeight.bold)),
                onTap: () {
                  Navigator.pop(context);
                  _pickAndSendImage(ImageSource.gallery);
                },
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _pickAndSendImage(ImageSource source) async {
    try {
      final picker = ImagePicker();
      final image = await picker.pickImage(
        source: source,
        maxWidth: 1080,
        maxHeight: 1080,
        imageQuality: 85,
      );
      if (image == null) return;

      await _sendImageMessage(image.path);
    } catch (e) {
      debugPrint('Error picking image: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error picking image: $e'),
            backgroundColor: const Color(0xFF7F00FF),
          ),
        );
      }
    }
  }

  void _startRecording() {
    FocusScope.of(context).unfocus();
    setState(() {
      _showEmoji = false;
      _isRecording = true;
      _recordingDuration = 0;
    });
    _recordingTimer?.cancel();
    _recordingTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      setState(() {
        _recordingDuration++;
      });
    });
  }

  void _cancelRecording() {
    _recordingTimer?.cancel();
    setState(() {
      _isRecording = false;
      _recordingDuration = 0;
    });
  }

  Future<void> _stopAndSendRecording() async {
    _recordingTimer?.cancel();
    final duration = _recordingDuration > 0 ? _recordingDuration : 5;
    setState(() {
      _isRecording = false;
      _recordingDuration = 0;
    });

    final convId = _conversationId;
    final userId = _currentUserId;
    if (convId == null || userId == null) return;

    final tempId = 'temp_${DateTime.now().millisecondsSinceEpoch}';

    // Optimistic insert
    final optimistic = {
      'id': tempId,
      'type': 'audio',
      'text': duration.toString(),
      'mediaUrl': 'mock_voice_note.mp3',
      'isSent': true,
      'createdAt': DateTime.now().toIso8601String(),
      'isDeleted': false,
      'duration': duration,
    };

    setState(() {
      _messages.insert(0, optimistic);
      _sortMessages();
      _isSending = true;
    });

    try {
      final result = await ApiService.sendMessage(
        convId,
        senderId: userId,
        type: 'audio',
        content: duration.toString(),
        mediaUrl: 'mock_voice_note.mp3',
      );

      if (result != null && mounted) {
        final idx = _messages.indexWhere((m) => m['id'] == tempId);
        if (idx != -1) {
          setState(() {
            _messages[idx] = _mapApiMessage(result);
            _sortMessages();
          });
        }
      }
    } catch (e) {
      debugPrint('_stopAndSendRecording error: $e');
      if (mounted) setState(() => _messages.removeWhere((m) => m['id'] == tempId));
    } finally {
      if (mounted) setState(() => _isSending = false);
    }
  }

  void _togglePlayback(String messageId, int durationSeconds) {
    if (_playingMessageId == messageId) {
      _playbackTimer?.cancel();
      setState(() {
        _playingMessageId = null;
      });
    } else {
      _playbackTimer?.cancel();
      setState(() {
        _playingMessageId = messageId;
        _playbackProgress = 0.0;
        _playbackSeconds = 0;
      });
      final totalTicks = durationSeconds * 10;
      int tick = 0;
      _playbackTimer = Timer.periodic(const Duration(milliseconds: 100), (timer) {
        tick++;
        if (tick > totalTicks) {
          timer.cancel();
          setState(() {
            _playingMessageId = null;
            _playbackProgress = 0.0;
            _playbackSeconds = 0;
          });
        } else {
          setState(() {
            _playbackProgress = tick / totalTicks;
            _playbackSeconds = (tick / 10).floor();
          });
        }
      });
    }
  }

  // ── Icebreaker ───────────────────────────────────────────────────────────────

  Future<void> _openIcebreakers() async {
    final selected = await IcebreakerModal.show(context);
    if (selected != null && selected.isNotEmpty) {
      await _sendMessage(type: 'icebreaker', content: selected);
    }
  }

  // ── Invitation Response ──────────────────────────────────────────────────────

  Future<void> _respondInvitation(String messageId, String action) async {
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
        if (idx != -1) _messages[idx] = {..._messages[idx], 'invitationStatus': action == 'accept' ? 'accepted' : 'declined'};
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
        title: const Text('Delete message?', style: TextStyle(fontWeight: FontWeight.w800)),
        content: const Text('This message will be removed for everyone.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
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
        if (idx != -1) _messages[idx] = {..._messages[idx], 'isDeleted': true, 'text': '[Message deleted]'};
      });
    }
  }

  // ── Build ────────────────────────────────────────────────────────────────────

  /// Builds a CircleAvatar that gracefully falls back to a gradient + initial
  /// when the network image is missing or returns a 4xx/5xx error.
  Widget _buildAvatarWithFallback({double radius = 20}) {
    String? imageUrl = widget.user['image'] as String?;
    final isAsset = widget.user['isAsset'] == true;

    Widget fallback = Container(
      width: radius * 2,
      height: radius * 2,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: Color(0xFF008069),
      ),
      alignment: Alignment.center,
      child: Icon(
        Icons.person,
        color: Colors.white,
        size: radius * 1.2,
      ),
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
      backgroundColor: const Color(0xFFECE5DD),
      appBar: _buildAppBar(context),
      body: Column(
        children: [
          // Expiry warning banner
          if (expiringSoon)
            _buildExpiryBanner(),
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator(color: Color(0xFF7F00FF)))
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
                  style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold),
                  textAlign: TextAlign.center,
                ),
              ),
            )
          else if (chatExpired)
            _buildExpiredInputBar()
          else if (_canChat || !_chatSessionLoaded)
            _buildInputArea(context),
          if (!_isBlocked && (_canChat || !_chatSessionLoaded)) _buildEmojiPicker(),
        ],
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
              style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600),
            ),
          ),
          // Only show EXTEND chip when admin has configured the price
          if (_adminSettingsAvailable && _extensionPrice != null)
            GestureDetector(
              onTap: _showExtendOptions,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Text('EXTEND', style: TextStyle(color: Colors.orange, fontSize: 11, fontWeight: FontWeight.bold)),
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
              child: const Icon(Icons.lock_clock_rounded, size: 56, color: Color(0xFF7F00FF)),
            ),
            const SizedBox(height: 24),
            const Text(
              'Chat Period Ended',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: Colors.black87),
            ),
            const SizedBox(height: 12),
            Text(
              adminReady
                  ? 'Your free chat window has expired. Pay ₹${price.toStringAsFixed(0)} to continue chatting for $days more days.'
                  : 'Your chat window has expired. Pricing is managed by the admin — please wait for configuration.',
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.black54, fontSize: 14, height: 1.5),
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
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
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
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
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
              child: const Icon(Icons.chat_bubble_outline_rounded, size: 56, color: Colors.grey),
            ),
            const SizedBox(height: 24),
            const Text(
              'No one available yet',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: Colors.black87),
            ),
            const SizedBox(height: 12),
            const Text(
              'When both of you match and connect, your chat will open automatically.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.black54, fontSize: 14, height: 1.5),
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
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                OutlinedButton(
                  onPressed: _requestOtherToPay,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFF7F00FF),
                    side: const BorderSide(color: Color(0xFF7F00FF)),
                    padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
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
          Icon(Icons.admin_panel_settings_rounded, size: 18, color: Colors.amber.shade700),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              'Chat extension is managed by the admin. Please check back later.',
              style: TextStyle(color: Colors.amber.shade800, fontSize: 12, fontWeight: FontWeight.w600),
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
              const Icon(Icons.admin_panel_settings_rounded, color: Colors.white, size: 18),
              const SizedBox(width: 8),
              const Expanded(child: Text('Chat extension charges are managed by the admin.')),
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
                const Icon(Icons.admin_panel_settings_rounded, color: Color(0xFF7F00FF), size: 20),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text('Extend Your Chat', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900)),
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
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
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
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
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
          content: const Text('Cannot send request — admin pricing not configured.'),
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
      backgroundColor: const Color(0xFF7F00FF),
      surfaceTintColor: const Color(0xFF008069),
      elevation: 2,
      shadowColor: Colors.black26,
      centerTitle: false,
      leadingWidth: 76,
      leading: InkWell(
        onTap: () => Navigator.pop(context),
        borderRadius: BorderRadius.circular(30),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(width: 4),
            const Icon(Icons.arrow_back, color: Colors.white, size: 24),
            const SizedBox(width: 4),
            _buildAvatarWithFallback(radius: 18),
          ],
        ),
      ),
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            widget.user['name'] as String,
            style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
          ),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Animated green dot when online
              if (_isOnline == true) ...[
                Container(
                  width: 7,
                  height: 7,
                  margin: const EdgeInsets.only(right: 5),
                  decoration: const BoxDecoration(
                    color: Color(0xFF25D366),
                    shape: BoxShape.circle,
                  ),
                ),
              ],
              Text(
                _isOnline == true
                    ? 'online'
                    : (_isOnline == false
                        ? _formatLastSeen(_lastActive)
                        : (widget.user['online'] == true ? 'online' : 'offline')),
                style: TextStyle(
                  fontSize: 11,
                  color: _isOnline == true ? const Color(0xFF25D366) : Colors.white70,
                  fontWeight: FontWeight.normal,
                ),
              ),
            ],
          ),
        ],
      ),
      actions: [
        // IconButton(
        //   icon: const Icon(Icons.videocam_rounded, color: Colors.white, size: 24),
        //   onPressed: () {},
        // ),
        // IconButton(
        //   icon: const Icon(Icons.call_rounded, color: Colors.white, size: 22),
        //   onPressed: () {},
        // ),
        IconButton(
          icon: const Icon(Icons.auto_awesome, color: Colors.white, size: 20),
          onPressed: _openIcebreakers,
        ),
        PopupMenuButton<String>(
          icon: const Icon(Icons.more_vert, color: Colors.white),
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
            Icon(Icons.chat_bubble_outline_rounded, size: 48, color: Color(0xFF008069)),
            SizedBox(height: 12),
            Text('No messages yet.', style: TextStyle(color: Color(0xFF008069), fontWeight: FontWeight.w600)),
            SizedBox(height: 4),
            Text('Say hello! ⚡', style: TextStyle(color: Color(0xFF008069), fontSize: 13)),
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
                child: Center(child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF7F00FF))),
              );
            }
            final msg = _messages[index];
            final type = msg['type'] ?? 'text';

            if (type == 'invitation') {
              return _buildInvitationCard(msg);
            }
            if (type == 'audio') {
              return _buildAudioBubble(msg);
            }
            if (type == 'pay_request') {
              return _buildPayRequestCard(msg);
            }
            if (type == 'system') {
              return _buildSystemMessage(msg);
            }
            return _buildMessageBubble(msg);
          },
        ),
        if (_isSending)
          Positioned(
            bottom: 8,
            left: 0,
            right: 0,
            child: Center(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.6),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Text('Sending...', style: TextStyle(color: Colors.white, fontSize: 12)),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildMessageStatusIcon(String status) {
    if (status == 'pending') {
      return const Icon(Icons.schedule, size: 13, color: Colors.grey);
    } else if (status == 'read') {
      return const Icon(Icons.done_all_rounded, size: 15, color: Color(0xFF34B7F1));
    } else if (status == 'delivered') {
      return const Icon(Icons.done_all_rounded, size: 15, color: Colors.grey);
    } else {
      return const Icon(Icons.done_rounded, size: 15, color: Colors.grey);
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
            style: const TextStyle(fontSize: 12, color: Colors.black54, fontStyle: FontStyle.italic),
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
      final raw = msg['text'] as String? ?? '';
      if (raw.startsWith('{')) {
        payload = Map<String, dynamic>.from(
          (jsonDecode(raw) as Map<dynamic, dynamic>).cast<String, dynamic>(),
        );
      }
    } catch (_) {}

    final requesterName = payload['requesterName'] ?? 'Your match';
    final extensionDays = (payload['extensionDays'] as num?)?.toInt() ?? _extensionDays ?? 7;
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
            border: Border.all(color: const Color(0xFF7F00FF).withValues(alpha: 0.3)),
            boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.06), blurRadius: 8, offset: const Offset(0, 2))],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.bolt_rounded, color: Color(0xFF7F00FF), size: 32),
              const SizedBox(height: 8),
              Text(
                isSent
                    ? 'You asked them to pay for $extensionDays more days.'
                    : '$requesterName is asking you to pay ₹${extensionPrice.toStringAsFixed(0)} for $extensionDays more days of chat.',
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.black87),
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
                          SnackBar(content: Text('✅ Chat extended for $extensionDays days!'), backgroundColor: const Color(0xFF7F00FF)),
                        );
                      }
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF7F00FF),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    child: Text('PAY ₹${extensionPrice.toStringAsFixed(0)} & EXTEND', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
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
    final type = msg['type'] ?? 'text';
    final isIcebreaker = type == 'icebreaker';
    final mediaUrl = msg['mediaUrl'] as String?;
    final text = msg['text'] as String? ?? '';
    final msgId = msg['id'] as String? ?? '';
    final status = msg['status']?.toString() ?? 'sent';
    final timeStr = _formatMessageTime(msg['createdAt']?.toString());

    return GestureDetector(
      onLongPress: (isSent && !isDeleted && msgId.isNotEmpty && !msgId.startsWith('temp_'))
          ? () => _confirmDelete(msgId)
          : null,
      child: Align(
        alignment: isSent ? Alignment.centerRight : Alignment.centerLeft,
        child: Container(
          margin: const EdgeInsets.only(bottom: 8),
          constraints: const BoxConstraints(maxWidth: 280),
          decoration: BoxDecoration(
            color: isDeleted
                ? Colors.grey[200]
                : (isSent ? const Color(0xFFDCF8C6) : Colors.white),
            borderRadius: isSent
                ? const BorderRadius.only(
                    topLeft: Radius.circular(12),
                    topRight: Radius.circular(12),
                    bottomLeft: Radius.circular(12),
                    bottomRight: Radius.circular(0),
                  )
                : const BorderRadius.only(
                    topLeft: Radius.circular(12),
                    topRight: Radius.circular(12),
                    bottomLeft: Radius.circular(0),
                    bottomRight: Radius.circular(12),
                  ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.06),
                blurRadius: 3,
                offset: const Offset(0, 1),
              ),
            ],
          ),
          child: isDeleted
              ? Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.block_rounded, size: 14, color: Colors.grey[500]),
                      const SizedBox(width: 6),
                      Text(
                        '[Message deleted]',
                        style: TextStyle(color: Colors.grey[500], fontStyle: FontStyle.italic, fontSize: 13),
                      ),
                    ],
                  ),
                )
              : (mediaUrl != null || type == 'image' || type == 'sticker')
                  ? _buildMediaBubbleContent(type, mediaUrl, timeStr, isSent, status)
                  : _buildTextBubbleContent(text, timeStr, isSent, isIcebreaker, status),
        ),
      ),
    );
  }

  Widget _buildTextBubbleContent(String text, String timeStr, bool isSent, bool isIcebreaker, String status) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 5),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.only(right: 4),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (isIcebreaker) ...[
                  const Text('⚡ ', style: TextStyle(fontSize: 14)),
                ],
                Flexible(
                  child: Text(
                    text,
                    style: TextStyle(
                      color: Colors.black87,
                      fontSize: 15,
                      height: 1.3,
                      fontWeight: isIcebreaker ? FontWeight.bold : FontWeight.normal,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 2),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                timeStr,
                style: TextStyle(color: Colors.grey[600], fontSize: 10),
              ),
              if (isSent) ...[
                const SizedBox(width: 4),
                _buildMessageStatusIcon(status),
              ],
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildMediaBubbleContent(String type, String? mediaUrl, String timeStr, bool isSent, String status) {
    if (mediaUrl == null) return const SizedBox.shrink();

    final isNetworkUrl = mediaUrl.startsWith('http://') || mediaUrl.startsWith('https://');

    Widget imageWidget;
    if (isNetworkUrl) {
      imageWidget = Image.network(
        mediaUrl,
        fit: type == 'sticker' ? BoxFit.contain : BoxFit.cover,
        width: type == 'sticker' ? 120 : 260,
        height: type == 'sticker' ? null : 180,
        loadingBuilder: (context, child, progress) {
          if (progress == null) return child;
          return Container(
            height: 180,
            width: 260,
            color: Colors.grey[100],
            child: const Center(child: CircularProgressIndicator(strokeWidth: 2)),
          );
        },
        errorBuilder: (context, error, stack) => Container(
          height: 120,
          width: 200,
          color: Colors.grey[100],
          child: const Icon(Icons.broken_image_outlined, color: Color(0xFF800080)),
        ),
      );
    } else {
      imageWidget = kIsWeb
          ? Image.network(
              mediaUrl,
              fit: type == 'sticker' ? BoxFit.contain : BoxFit.cover,
              width: type == 'sticker' ? 120 : 260,
              height: type == 'sticker' ? null : 180,
            )
          : Image.file(
              File(mediaUrl),
              fit: type == 'sticker' ? BoxFit.contain : BoxFit.cover,
              width: type == 'sticker' ? 120 : 260,
              height: type == 'sticker' ? null : 180,
              errorBuilder: (context, error, stack) => Container(
                height: 120,
                width: 200,
                color: Colors.grey[100],
                child: const Icon(Icons.broken_image_outlined, color: Color(0xFF800080)),
              ),
            );
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: Stack(
        alignment: Alignment.bottomRight,
        children: [
          imageWidget,
          Container(
            margin: const EdgeInsets.all(6),
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: Colors.black45,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  timeStr,
                  style: const TextStyle(color: Colors.white, fontSize: 10),
                ),
                if (isSent) ...[
                  const SizedBox(width: 4),
                  _buildMessageStatusIcon(status),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAudioBubble(Map<String, dynamic> msg) {
    final isSent = msg['isSent'] == true;
    final isDeleted = msg['isDeleted'] == true;
    final msgId = msg['id'] as String? ?? '';
    final msgStatus = msg['status']?.toString() ?? 'sent';
    final timeStr = _formatMessageTime(msg['createdAt']?.toString());
    final duration = msg['duration'] as int? ?? int.tryParse(msg['text']?.toString() ?? '5') ?? 5;

    final isPlaying = _playingMessageId == msgId;
    final progress = isPlaying ? _playbackProgress : 0.0;
    
    final currentSeconds = isPlaying ? _playbackSeconds : duration;
    final min = (currentSeconds / 60).floor();
    final sec = (currentSeconds % 60).toString().padLeft(2, '0');
    final durationStr = '$min:$sec';

    return Align(
      alignment: isSent ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        constraints: const BoxConstraints(maxWidth: 280),
        decoration: BoxDecoration(
          color: isDeleted
              ? Colors.grey[200]
              : (isSent ? const Color(0xFFDCF8C6) : Colors.white),
          borderRadius: isSent
              ? const BorderRadius.only(
                  topLeft: Radius.circular(12),
                  topRight: Radius.circular(12),
                  bottomLeft: Radius.circular(12),
                  bottomRight: Radius.circular(0),
                )
              : const BorderRadius.only(
                  topLeft: Radius.circular(12),
                  topRight: Radius.circular(12),
                  bottomLeft: Radius.circular(0),
                  bottomRight: Radius.circular(12),
                ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.06),
              blurRadius: 3,
              offset: const Offset(0, 1),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            IconButton(
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
              icon: Icon(
                isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                color: const Color(0xFF800080),
                size: 28,
              ),
              onPressed: () => _togglePlayback(msgId, duration),
            ),
            const SizedBox(width: 8),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: List.generate(15, (index) {
                    final barHeight = 8.0 + (index % 3 == 0 ? 12.0 : (index % 2 == 0 ? 6.0 : 16.0));
                    final isPlayed = index / 15.0 < progress;
                    return Container(
                      margin: const EdgeInsets.symmetric(horizontal: 1.5),
                      width: 3,
                      height: barHeight,
                      decoration: BoxDecoration(
                        color: isPlayed ? const Color(0xFF7F00FF) : Colors.grey[300],
                        borderRadius: BorderRadius.circular(2),
                      ),
                    );
                  }),
                ),
                const SizedBox(height: 4),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      durationStr,
                      style: TextStyle(color: Colors.grey[600], fontSize: 10),
                    ),
                    const SizedBox(width: 40),
                    Text(
                      timeStr,
                      style: TextStyle(color: Colors.grey[600], fontSize: 10),
                    ),
                    if (isSent) ...[
                      const SizedBox(width: 4),
                      _buildMessageStatusIcon(msgStatus),
                    ],
                  ],
                ),
              ],
            ),
            const SizedBox(width: 4),
            Icon(Icons.mic, color: Color(0xFF800080), size: 20),
          ],
        ),
      ),
    );
  }

  Widget _buildInvitationCard(Map<String, dynamic> msg) {
    final isSent = msg['isSent'] == true;
    final venue = msg['venue'] as String? ?? 'Venue Invite';
    final date = msg['date'] as String? ?? msg['invitationTime'] as String? ?? '';
    final status = msg['invitationStatus'] as String? ?? 'pending';
    final msgId = msg['id'] as String? ?? '';
    final msgStatus = msg['status']?.toString() ?? 'sent';
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
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.black),
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
                        Expanded(child: _inviteButton('ACCEPT', true, () => _respondInvitation(msgId, 'accept'))),
                        const SizedBox(width: 8),
                        Expanded(child: _inviteButton('DECLINE', false, () => _respondInvitation(msgId, 'decline'))),
                      ],
                    ),
                  ] else ...[
                    Container(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      decoration: BoxDecoration(
                        color: status == 'accepted' ? const Color(0xFFE8F5E9) : const Color(0xFFFFEBEE),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        status == 'accepted' ? '✅ Accepted' : '❌ Declined',
                        style: TextStyle(
                          color: status == 'accepted' ? const Color(0xFF2E7D32) : const Color(0xFFC62828),
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
    if (_isRecording) {
      return Container(
        color: const Color(0xFFECE5DD),
        padding: const EdgeInsets.fromLTRB(8, 4, 8, 12),
        child: Row(
          children: [
            Expanded(
              child: Container(
                height: 48,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(25),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.06),
                      blurRadius: 4,
                      offset: const Offset(0, 1),
                    ),
                  ],
                ),
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  children: [
                    const Icon(Icons.fiber_manual_record, color: Color(0xFF800080), size: 16),
                    const SizedBox(width: 8),
                    const Text(
                      'Recording Voice Note',
                      style: TextStyle(color: Colors.black54, fontWeight: FontWeight.bold, fontSize: 14),
                    ),
                    const Spacer(),
                    Text(
                      '0:${_recordingDuration.toString().padLeft(2, '0')}',
                      style: const TextStyle(color: Colors.black87, fontWeight: FontWeight.bold, fontSize: 15),
                    ),
                    const SizedBox(width: 16),
                    TextButton(
                      onPressed: _cancelRecording,
                      child: const Text('Cancel', style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 8),
            GestureDetector(
              onTap: _stopAndSendRecording,
              child: Container(
                width: 48,
                height: 48,
                decoration: const BoxDecoration(
                  color: Color(0xFF800080),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.send,
                  color: Colors.white,
                  size: 22,
                ),
              ),
            ),
          ],
        ),
      );
    }

    return Container(
      color: const Color(0xFFECE5DD),
      padding: const EdgeInsets.fromLTRB(8, 4, 8, 12),
      child: Row(
        children: [
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(25),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.06),
                    blurRadius: 4,
                    offset: const Offset(0, 1),
                  ),
                ],
              ),
              child: Row(
                children: [
                  IconButton(
                    icon: Icon(
                      _showEmoji ? Icons.keyboard : Icons.insert_emoticon_rounded,
                      color: Color(0xFF800080),
                      size: 24,
                    ),
                    onPressed: () {
                      if (_showEmoji) {
                        FocusScope.of(context).requestFocus(_focusNode);
                        setState(() {
                          _showEmoji = false;
                        });
                      } else {
                        FocusScope.of(context).unfocus();
                        Future.delayed(const Duration(milliseconds: 100), () {
                          setState(() {
                            _showEmoji = true;
                          });
                        });
                      }
                    },
                  ),
                  Expanded(
                    child: TextField(
                      controller: _messageController,
                      focusNode: _focusNode,
                      style: const TextStyle(color: Colors.black, fontSize: 16),
                      maxLines: null,
                      onTap: () {
                        setState(() {
                          _showEmoji = false;
                        });
                      },
                      decoration: InputDecoration(
                        hintText: 'Message',
                        hintStyle: TextStyle(color: Colors.grey[400], fontSize: 16),
                        border: InputBorder.none,
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(vertical: 8),
                      ),
                      onChanged: (text) {
                        setState(() {});
                      },
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.attach_file_rounded, color: Color(0xFF800080), size: 22),
                    onPressed: () async {
                      await Navigator.push(
                        context,
                        MaterialPageRoute(builder: (context) => const VenueInvitePickerScreen()),
                      );
                    },
                  ),
                  IconButton(
                    icon: const Icon(Icons.camera_alt_rounded, color: Color(0xFF800080), size: 22),
                    onPressed: _showCameraOptions,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: () {
              if (_messageController.text.trim().isEmpty) {
                _startRecording();
              } else {
                _sendMessage();
              }
            },
            child: Container(
              width: 48,
              height: 48,
              decoration: const BoxDecoration(
                color: Color(0xFF800080),
                shape: BoxShape.circle,
              ),
              child: Icon(
                _messageController.text.trim().isEmpty ? Icons.mic : Icons.send,
                color: Colors.white,
                size: 22,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
