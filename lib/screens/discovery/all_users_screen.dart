import 'package:flutter/material.dart';
import '../../core/theme.dart';
import '../../widgets/lunara_profile_image.dart';
import '../../models/user.dart';
import '../../services/api_service.dart';
import '../profile/profile_screen.dart';

class AllUsersScreen extends StatefulWidget {
  final List<dynamic>? users;

  const AllUsersScreen({super.key, this.users});

  @override
  State<AllUsersScreen> createState() => _AllUsersScreenState();
}

class _AllUsersScreenState extends State<AllUsersScreen> {
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  List<dynamic> _allUsers = [];
  List<dynamic> _filteredUsers = [];
  bool _isLoading = false;

  String _selectedGender = 'All';
  String _selectedAgeRange = 'All Ages';

  final List<String> _genders = ['All', 'Male', 'Female', 'Other'];
  final List<String> _ageRanges = [
    'All Ages',
    '18-24',
    '25-34',
    '35-44',
    '45+',
  ];

  @override
  void initState() {
    super.initState();
    if (widget.users != null && widget.users!.isNotEmpty) {
      _allUsers = List<dynamic>.from(widget.users!);
      _filteredUsers = List<dynamic>.from(widget.users!);
    }
    _loadAllUsers();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadAllUsers() async {
    if (!mounted) return;
    if (_allUsers.isEmpty) {
      setState(() => _isLoading = true);
    }
    try {
      final fetched = await ApiService.fetchCustomers(
        limit: 100,
        includeAllCities: true,
      );
      if (fetched.isNotEmpty && mounted) {
        setState(() {
          _allUsers = fetched;
          _isLoading = false;
          _applyFilters();
        });
      } else if (mounted) {
        setState(() => _isLoading = false);
      }
    } catch (e) {
      debugPrint('Error loading all users in AllUsersScreen: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _applyFilters() {
    final currentUserId = ApiService.currentUserId;
    setState(() {
      _filteredUsers = _allUsers.where((user) {
        // Exclude self if logged in
        if (currentUserId != null && currentUserId.isNotEmpty) {
          final uId = user['id']?.toString();
          if (uId == currentUserId) return false;
        }

        // Search
        final String name =
            (user['firstName'] ?? user['fullName'] ?? user['name'] ?? 'User')
                .toString()
                .toLowerCase();
        final String userName = (user['userName'] ?? '')
            .toString()
            .toLowerCase();
        final String email = (user['email'] ?? '')
            .toString()
            .toLowerCase();
        final q = _searchQuery.toLowerCase().trim();
        final bool matchesSearch =
            q.isEmpty || name.contains(q) || userName.contains(q) || email.contains(q);
        if (!matchesSearch) return false;

        // Gender filter
        if (_selectedGender != 'All') {
          String userGender = '';
          if (user['profile'] != null && user['profile']['gender'] != null) {
            userGender = user['profile']['gender'].toString().toLowerCase().trim();
          } else if (user['gender'] != null) {
            userGender = user['gender'].toString().toLowerCase().trim();
          }

          final targetGender = _selectedGender.toLowerCase();
          if (targetGender == 'male') {
            if (userGender != 'male' && userGender != 'm') return false;
          } else if (targetGender == 'female') {
            if (userGender != 'female' && userGender != 'f') return false;
          } else if (targetGender == 'other') {
            if (userGender == 'male' || userGender == 'm' || userGender == 'female' || userGender == 'f') return false;
          }
        }

        // Age filter
        if (_selectedAgeRange != 'All Ages') {
          int? age;
          if (user['age'] != null) {
            age = int.tryParse(user['age'].toString());
          }
          if (age == null && user['dateOfBirth'] != null) {
            try {
              final dob = DateTime.parse(user['dateOfBirth'].toString());
              age = DateTime.now().year - dob.year;
            } catch (_) {}
          }

          if (age == null) return false;

          if (_selectedAgeRange == '18-24' && (age < 18 || age > 24)) {
            return false;
          }
          if (_selectedAgeRange == '25-34' && (age < 25 || age > 34)) {
            return false;
          }
          if (_selectedAgeRange == '35-44' && (age < 35 || age > 44)) {
            return false;
          }
          if (_selectedAgeRange == '45+' && age < 45) return false;
        }

        return true;
      }).toList();
    });
  }

  bool get _hasActiveFilters =>
      _searchQuery.isNotEmpty ||
      _selectedGender != 'All' ||
      _selectedAgeRange != 'All Ages';

  void _onSearchChanged(String query) {
    _searchQuery = query;
    _applyFilters();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        title: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'ALL PROFILES',
              style: TextStyle(
                fontWeight: FontWeight.w900,
                fontSize: 16,
                letterSpacing: 0.5,
                color: Colors.black,
              ),
            ),
            const SizedBox(height: 2),
            if (_allUsers.isNotEmpty)
              Text(
                _hasActiveFilters
                    ? '${_filteredUsers.length} of ${_allUsers.length} profiles'
                    : '${_allUsers.length} profiles',
                style: const TextStyle(
                  fontSize: 12,
                  color: Color(0xFF64748B),
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.2,
                ),
              ),
          ],
        ),
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, size: 20, color: Colors.black),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 8, 24, 16),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(30),
                boxShadow: LunaraTheme.premiumCardShadow,
                border: Border.all(color: Colors.grey[100]!),
              ),
              child: TextField(
                controller: _searchController,
                onChanged: _onSearchChanged,
                style: const TextStyle(
                  color: Colors.black,
                  fontWeight: FontWeight.bold,
                ),
                decoration: InputDecoration(
                  hintText: 'Search users by name, username...',
                  hintStyle: TextStyle(
                    color: Colors.grey[400],
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                  border: InputBorder.none,
                  suffixIcon: _searchQuery.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear, color: Colors.black54),
                          onPressed: () {
                            _searchController.clear();
                            _onSearchChanged('');
                          },
                        )
                      : const Icon(
                          Icons.search,
                          color: LunaraTheme.electricViolet,
                        ),
                ),
              ),
            ),
          ),

          // Filters UI
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 4),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  physics: const BouncingScrollPhysics(),
                  child: Row(
                    children: _genders.map((gender) {
                      final isSelected = _selectedGender == gender;
                      return Padding(
                        padding: const EdgeInsets.only(right: 8.0),
                        child: ChoiceChip(
                          label: Text(gender),
                          selected: isSelected,
                          onSelected: (selected) {
                            if (selected) {
                              _selectedGender = gender;
                              _applyFilters();
                            }
                          },
                          selectedColor: LunaraTheme.electricViolet.withValues(
                            alpha: 0.2,
                          ),
                          backgroundColor: Colors.grey[100],
                          labelStyle: TextStyle(
                            color: isSelected
                                ? LunaraTheme.electricViolet
                                : Colors.black87,
                            fontWeight: isSelected
                                ? FontWeight.bold
                                : FontWeight.normal,
                            fontSize: 12,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(20),
                            side: BorderSide(
                              color: isSelected
                                  ? LunaraTheme.electricViolet
                                  : Colors.transparent,
                            ),
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ),
                const SizedBox(height: 8),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  physics: const BouncingScrollPhysics(),
                  child: Row(
                    children: _ageRanges.map((ageRange) {
                      final isSelected = _selectedAgeRange == ageRange;
                      return Padding(
                        padding: const EdgeInsets.only(right: 8.0),
                        child: ChoiceChip(
                          label: Text(ageRange),
                          selected: isSelected,
                          onSelected: (selected) {
                            if (selected) {
                              _selectedAgeRange = ageRange;
                              _applyFilters();
                            }
                          },
                          selectedColor: LunaraTheme.electricViolet.withValues(
                            alpha: 0.2,
                          ),
                          backgroundColor: Colors.grey[100],
                          labelStyle: TextStyle(
                            color: isSelected
                                ? LunaraTheme.electricViolet
                                : Colors.black87,
                            fontWeight: isSelected
                                ? FontWeight.bold
                                : FontWeight.normal,
                            fontSize: 12,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(20),
                            side: BorderSide(
                              color: isSelected
                                  ? LunaraTheme.electricViolet
                                  : Colors.transparent,
                            ),
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ),
                const SizedBox(height: 12),
              ],
            ),
          ),

          Expanded(
            child: _isLoading && _filteredUsers.isEmpty
                ? const Center(
                    child: CircularProgressIndicator(
                      color: LunaraTheme.electricViolet,
                    ),
                  )
                : RefreshIndicator(
                    color: LunaraTheme.electricViolet,
                    onRefresh: _loadAllUsers,
                    child: _filteredUsers.isEmpty
                        ? const SingleChildScrollView(
                            physics: AlwaysScrollableScrollPhysics(),
                            child: SizedBox(
                              height: 300,
                              child: Center(
                                child: Text(
                                  'No users found.',
                                  style: TextStyle(
                                    color: Colors.grey,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ),
                          )
                        : GridView.builder(
                            physics: const AlwaysScrollableScrollPhysics(
                              parent: BouncingScrollPhysics(),
                            ),
                            padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
                            gridDelegate:
                                const SliverGridDelegateWithFixedCrossAxisCount(
                                  crossAxisCount: 3,
                                  crossAxisSpacing: 16,
                                  mainAxisSpacing: 24,
                                  childAspectRatio: 0.65,
                                ),
                            itemCount: _filteredUsers.length,
                            itemBuilder: (context, index) {
                              final user = _filteredUsers[index];
                              final String name =
                                  (user['firstName'] ??
                                          user['fullName'] ??
                                          user['name'] ??
                                          'User')
                                      .toString();

                              return GestureDetector(
                                onTap: () {
                                  try {
                                    final resolvedUser = User.fromJson(user);
                                    final List<User> resolvedAllProfiles = [];
                                    for (var u in _filteredUsers) {
                                      try {
                                        resolvedAllProfiles.add(User.fromJson(Map<String, dynamic>.from(u)));
                                      } catch (_) {}
                                    }
                                    Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (context) =>
                                            ProfileScreen(
                                              user: resolvedUser,
                                              allProfiles: resolvedAllProfiles,
                                            ),
                                      ),
                                    );
                                  } catch (e) {
                                    debugPrint('Error navigating to user profile: $e');
                                  }
                                },
                                child: Column(
                                  children: [
                                    LunaraProfileImage(
                                      userData: user,
                                      radius: 40,
                                      isInteractive: false,
                                    ),
                                    const SizedBox(height: 12),
                                    Text(
                                      name,
                                      style: const TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w600,
                                        color: Colors.black,
                                        letterSpacing: 0.2,
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      textAlign: TextAlign.center,
                                    ),
                                  ],
                                ),
                              );
                            },
                          ),
                  ),
          ),
        ],
      ),
    );
  }
}
