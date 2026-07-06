import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/foundation.dart';
import 'api_service.dart';

class BlockService {
  static const String _blockedUsersKey = 'blocked_users';

  static Future<List<String>> getBlockedUsers() async {
    final prefs = await SharedPreferences.getInstance();
    List<String> blockedUsers = prefs.getStringList(_blockedUsersKey) ?? [];

    // Sync with backend asynchronously to keep the UI fast
    ApiService.getBlockedUsers().then((backendBlocks) async {
      if (backendBlocks.isNotEmpty || blockedUsers.isNotEmpty) {
        await prefs.setStringList(_blockedUsersKey, backendBlocks);
      }
    }).catchError((e) {
      debugPrint('Error syncing blocked users: $e');
    });

    return blockedUsers;
  }

  static Future<bool> isUserBlocked(String userId) async {
    final blockedUsers = await getBlockedUsers();
    return blockedUsers.contains(userId);
  }

  static Future<void> blockUser(String userId) async {
    final prefs = await SharedPreferences.getInstance();
    final blockedUsers = prefs.getStringList(_blockedUsersKey) ?? [];
    if (!blockedUsers.contains(userId)) {
      blockedUsers.add(userId);
      await prefs.setStringList(_blockedUsersKey, blockedUsers);
    }
    
    // Call backend API
    await ApiService.blockUser(userId);
  }

  static Future<void> unblockUser(String userId) async {
    final prefs = await SharedPreferences.getInstance();
    final blockedUsers = prefs.getStringList(_blockedUsersKey) ?? [];
    if (blockedUsers.contains(userId)) {
      blockedUsers.remove(userId);
      await prefs.setStringList(_blockedUsersKey, blockedUsers);
    }
    
    // Call backend API
    await ApiService.unblockUser(userId);
  }

  static Future<void> reportUser(String userId, String reason) async {
    // Block locally immediately for UI snappiness
    await blockUser(userId);
    
    // Call backend API to report
    await ApiService.reportUser(userId, reason);
  }
}
