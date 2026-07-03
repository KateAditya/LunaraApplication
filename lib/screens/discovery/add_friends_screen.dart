import 'package:flutter/material.dart';
import '../../core/theme.dart';
import '../../widgets/action_button.dart';
import 'payment_confirmation_screen.dart';

class AddFriendsScreen extends StatefulWidget {
  final Map<String, dynamic> venue;
  final String date;
  final String package;

  const AddFriendsScreen({
    super.key,
    required this.venue,
    required this.date,
    required this.package,
  });

  @override
  State<AddFriendsScreen> createState() => _AddFriendsScreenState();
}

class _AddFriendsScreenState extends State<AddFriendsScreen> {
  final List<Map<String, dynamic>> _allFriends = [
    {'id': '1', 'name': 'Zane Archer', 'avatar': 'assets/images/profiles/zane.png', 'status': 'Online'},
    {'id': '2', 'name': 'Lyra Vance', 'avatar': 'assets/images/profiles/lyra.png', 'status': 'Active 5m ago'},
    {'id': '3', 'name': 'Elara Sky', 'avatar': 'assets/images/profiles/elara.png', 'status': 'Online'},
    {'id': '4', 'name': 'Kaelen Voss', 'avatar': 'assets/images/profiles/zane.png', 'status': 'Busy'},
    {'id': '5', 'name': 'Nova Ray', 'avatar': 'assets/images/profiles/lyra.png', 'status': 'Online'},
    {'id': '6', 'name': 'Jaxen Cole', 'avatar': 'assets/images/profiles/elara.png', 'status': 'Active 1h ago'},
    {'id': '7', 'name': 'Aria Storm', 'avatar': 'assets/images/profiles/zane.png', 'status': 'Online'},
  ];

  final Set<String> _selectedFriends = {};
  String _searchQuery = '';

  List<Map<String, dynamic>> get _filteredFriends {
    if (_searchQuery.isEmpty) return _allFriends;
    return _allFriends
        .where((f) => f['name'].toLowerCase().contains(_searchQuery.toLowerCase()))
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(),
            _buildSearchBar(),
            _buildSelectedFriendsHorizontal(),
            Expanded(
              child: _buildFriendsList(),
            ),
            _buildFooter(),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.all(24.0),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back, color: Colors.black),
            onPressed: () => Navigator.pop(context),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'ADD FRIENDS',
                  style: LunaraTheme.headingStyle.copyWith(
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 2,
                  ),
                ),
                Text(
                  'To your booking at ${widget.venue['name']}',
                  style: TextStyle(
                    color: Colors.grey[600],
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchBar() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 8),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.grey[100],
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.grey[200]!),
        ),
        child: TextField(
          onChanged: (val) => setState(() => _searchQuery = val),
          decoration: InputDecoration(
            hintText: 'Search friends...',
            hintStyle: TextStyle(color: Colors.grey[400], fontSize: 14),
            prefixIcon: Icon(Icons.search, color: Colors.grey[400]),
            border: InputBorder.none,
            contentPadding: const EdgeInsets.symmetric(vertical: 14),
          ),
        ),
      ),
    );
  }

  Widget _buildSelectedFriendsHorizontal() {
    if (_selectedFriends.isEmpty) return const SizedBox.shrink();

    return Container(
      height: 90,
      margin: const EdgeInsets.only(top: 16),
      child: ListView.builder(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        scrollDirection: Axis.horizontal,
        itemCount: _selectedFriends.length,
        itemBuilder: (context, index) {
          final friendId = _selectedFriends.elementAt(index);
          final friend = _allFriends.firstWhere((f) => f['id'] == friendId);
          return Padding(
            padding: const EdgeInsets.only(right: 16.0),
            child: Column(
              children: [
                Stack(
                  children: [
                    CircleAvatar(
                      radius: 26,
                      backgroundImage: AssetImage(friend['avatar']),
                    ),
                    Positioned(
                      right: 0,
                      top: 0,
                      child: GestureDetector(
                        onTap: () => setState(() => _selectedFriends.remove(friendId)),
                        child: Container(
                          padding: const EdgeInsets.all(2),
                          decoration: const BoxDecoration(
                            color: Colors.black,
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(Icons.close, size: 12, color: Colors.white),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  friend['name'].split(' ')[0],
                  style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w600),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildFriendsList() {
    final friends = _filteredFriends;
    if (friends.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.search_off, size: 48, color: Colors.grey[300]),
            const SizedBox(height: 16),
            Text(
              'No friends found',
              style: TextStyle(color: Colors.grey[500], fontSize: 16),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      itemCount: friends.length,
      itemBuilder: (context, index) {
        final friend = friends[index];
        final isSelected = _selectedFriends.contains(friend['id']);

        return GestureDetector(
          onTap: () {
            setState(() {
              if (isSelected) {
                _selectedFriends.remove(friend['id']);
              } else {
                _selectedFriends.add(friend['id']);
              }
            });
          },
          child: Container(
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: isSelected ? LunaraTheme.electricViolet.withValues(alpha: 0.05) : Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: isSelected ? LunaraTheme.electricViolet : Colors.grey[200]!,
                width: 1,
              ),
            ),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 24,
                  backgroundImage: AssetImage(friend['avatar']),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        friend['name'],
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: isSelected ? FontWeight.w900 : FontWeight.w700,
                          color: Colors.black,
                        ),
                      ),
                      Text(
                        friend['status'],
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey[500],
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  width: 24,
                  height: 24,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: isSelected ? LunaraTheme.electricViolet : Colors.grey[300]!,
                      width: 2,
                    ),
                    color: isSelected ? LunaraTheme.electricViolet : Colors.transparent,
                  ),
                  child: isSelected
                      ? const Icon(Icons.check, size: 16, color: Colors.white)
                      : null,
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildFooter() {
    return Padding(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_selectedFriends.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 16.0),
              child: Text(
                '${_selectedFriends.length} friends selected',
                style: TextStyle(
                  color: LunaraTheme.electricViolet,
                  fontWeight: FontWeight.w900,
                  fontSize: 13,
                  letterSpacing: 1,
                ),
              ),
            ),
          LunaraActionButton(
            text: 'PROCEED TO PAYMENT',
            onPressed: () {
              final chargesVal = widget.venue['tableBookingCharges'];
              String chargesStr = '20';
              if (chargesVal != null) {
                final parsed = double.tryParse(chargesVal.toString());
                if (parsed != null) {
                  chargesStr = parsed.toStringAsFixed(0);
                }
              }

              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => PaymentConfirmationScreen(
                    venue: widget.venue,
                    date: widget.date,
                    package: widget.package,
                    totalPrice: '₹$chargesStr',
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}
