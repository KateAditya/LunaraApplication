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
  String _selectedSortFilter = 'All'; // 'All', 'Top Ranked', 'Boosted ⚡', 'VIP Plans 👑', 'Most Liked ❤️'

  final List<String> _genders = ['All', 'Female', 'Male', 'Other'];
  final List<String> _ageRanges = [
    'All Ages',
    '18-24',
    '25-34',
    '35-44',
    '45+',
  ];
  final List<String> _sortFilters = [
    'All',
    'Top Ranked',
    'Boosted ⚡',
    'VIP Plans 👑',
    'Most Liked ❤️',
  ];

  @override
  void initState() {
    super.initState();
    if (widget.users != null && widget.users!.isNotEmpty) {
      _allUsers = List<dynamic>.from(widget.users!);
      _applyFilters();
    }
    _loadAllUsers(forceRefresh: true);
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadAllUsers({bool forceRefresh = true}) async {
    if (!mounted) return;
    if (_allUsers.isEmpty) {
      setState(() => _isLoading = true);
    }
    try {
      final fetched = await ApiService.fetchCustomers(
        limit: 500,
        includeAllCities: true,
        forceRefresh: forceRefresh,
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
      final filtered = _allUsers.where((user) {
        // Exclude self if logged in
        if (currentUserId != null && currentUserId.isNotEmpty) {
          final uId = user['id']?.toString();
          if (uId == currentUserId) return false;
        }

        // Comprehensive search query matching
        final q = _searchQuery.toLowerCase().trim();
        if (q.isNotEmpty) {
          final String firstName = (user['firstName'] ?? '').toString().toLowerCase();
          final String lastName = (user['lastName'] ?? '').toString().toLowerCase();
          final String fullName = (user['fullName'] ?? '$firstName $lastName').toString().toLowerCase();
          final String name = (user['name'] ?? user['displayName'] ?? fullName).toString().toLowerCase();
          final String userName = (user['userName'] ?? user['username'] ?? '').toString().toLowerCase();
          final String email = (user['email'] ?? '').toString().toLowerCase();
          final String phone = (user['phone'] ?? '').toString().toLowerCase();
          final String city = (user['city'] ?? (user['profile'] is Map ? user['profile']['city'] : '') ?? '')
              .toString()
              .toLowerCase();
          final String bio = (user['bio'] ?? (user['profile'] is Map ? user['profile']['bio'] : '') ?? '')
              .toString()
              .toLowerCase();
          final String occupation = (user['occupation'] ?? (user['profile'] is Map ? user['profile']['occupation'] : '') ?? '')
              .toString()
              .toLowerCase();
          final String ig = (user['profile'] is Map ? (user['profile']['instagramHandle'] ?? '') : '')
              .toString()
              .toLowerCase();

          final qWords = q.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();

          final bool matchesSearch = name.contains(q) ||
              fullName.contains(q) ||
              firstName.contains(q) ||
              lastName.contains(q) ||
              userName.contains(q) ||
              email.contains(q) ||
              phone.contains(q) ||
              city.contains(q) ||
              bio.contains(q) ||
              occupation.contains(q) ||
              ig.contains(q) ||
              (qWords.length > 1 && qWords.every((w) =>
                  firstName.contains(w) ||
                  lastName.contains(w) ||
                  fullName.contains(w) ||
                  city.contains(w) ||
                  userName.contains(w) ||
                  occupation.contains(w)
              ));

          if (!matchesSearch) return false;
        }

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

        // Quick sort/filter mode filtering
        if (_selectedSortFilter == 'Boosted ⚡') {
          final isBoosted = user['isBoosted'] == true ||
              (user['boostCount'] != null && (int.tryParse(user['boostCount'].toString()) ?? 0) > 0) ||
              (user['boostsRemaining'] != null && (int.tryParse(user['boostsRemaining'].toString()) ?? 0) > 0);
          if (!isBoosted) return false;
        } else if (_selectedSortFilter == 'VIP Plans 👑') {
          final rawTier = (user['subscriptionTier'] ?? user['tier'] ?? user['packageTier'] ?? 'FREE').toString().toUpperCase();
          final tier = (rawTier == 'NULL' || rawTier == 'UNDEFINED') ? 'FREE' : rawTier;
          final bool hasPlan = tier != 'FREE';
          if (!hasPlan) return false;
        }

        return true;
      }).toList();

      // Advanced Ranking & Sorting Engine
      filtered.sort((a, b) {
        // When searching, sort primarily by match relevance
        final q = _searchQuery.toLowerCase().trim();
        if (q.isNotEmpty) {
          final String firstNameA = (a['firstName'] ?? '').toString().toLowerCase();
          final String lastNameA = (a['lastName'] ?? '').toString().toLowerCase();
          final String fullNameA = (a['fullName'] ?? '$firstNameA $lastNameA').toString().toLowerCase();
          final String nameA = (a['name'] ?? a['displayName'] ?? fullNameA).toString().toLowerCase();
          final String uNameA = (a['userName'] ?? a['username'] ?? '').toString().toLowerCase();
          final String cityA = (a['city'] ?? (a['profile'] is Map ? a['profile']['city'] : '') ?? '').toString().toLowerCase();

          final String firstNameB = (b['firstName'] ?? '').toString().toLowerCase();
          final String lastNameB = (b['lastName'] ?? '').toString().toLowerCase();
          final String fullNameB = (b['fullName'] ?? '$firstNameB $lastNameB').toString().toLowerCase();
          final String nameB = (b['name'] ?? b['displayName'] ?? fullNameB).toString().toLowerCase();
          final String uNameB = (b['userName'] ?? b['username'] ?? '').toString().toLowerCase();
          final String cityB = (b['city'] ?? (b['profile'] is Map ? b['profile']['city'] : '') ?? '').toString().toLowerCase();

          int relevanceScore(String n, String fn, String un, String c) {
            if (n == q || fn == q || un == q) return 100;
            if (fn.startsWith(q) || n.startsWith(q) || un.startsWith(q)) return 80;
            if (fn.contains(q) || n.contains(q) || un.contains(q)) return 60;
            if (c == q || c.startsWith(q)) return 40;
            if (c.contains(q)) return 20;
            return 10;
          }

          final int relA = relevanceScore(nameA, fullNameA, uNameA, cityA);
          final int relB = relevanceScore(nameB, fullNameB, uNameB, cityB);
          if (relA != relB) {
            return relB.compareTo(relA);
          }
        }

        if (_selectedSortFilter == 'Most Liked ❤️') {
          final likesA = (a['likesCount'] is num ? a['likesCount'] : int.tryParse(a['likesCount']?.toString() ?? '0') ?? 0).toInt() +
              ((a['superLikesCount'] is num ? a['superLikesCount'] : int.tryParse(a['superLikesCount']?.toString() ?? '0') ?? 0).toInt() * 2);
          final likesB = (b['likesCount'] is num ? b['likesCount'] : int.tryParse(b['likesCount']?.toString() ?? '0') ?? 0).toInt() +
              ((b['superLikesCount'] is num ? b['superLikesCount'] : int.tryParse(b['superLikesCount']?.toString() ?? '0') ?? 0).toInt() * 2);
          return likesB.compareTo(likesA);
        }

        // Top Ranked / Default / All:
        final scoreA = (a['rankScore'] is num
            ? a['rankScore']
            : double.tryParse(a['rankScore']?.toString() ?? '0') ?? 0);
        final scoreB = (b['rankScore'] is num
            ? b['rankScore']
            : double.tryParse(b['rankScore']?.toString() ?? '0') ?? 0);

        final cmp = scoreB.compareTo(scoreA);
        if (cmp != 0) return cmp;

        // Tie-breaker 1: Boosted status
        final bool isBoostedA = a['isBoosted'] == true;
        final bool isBoostedB = b['isBoosted'] == true;
        if (isBoostedA != isBoostedB) return isBoostedB ? 1 : -1;

        // Tie-breaker 2: VIP Tier rank
        final int tierRankA = (a['tierRank'] is num ? a['tierRank'] : int.tryParse(a['tierRank']?.toString() ?? '0') ?? 0).toInt();
        final int tierRankB = (b['tierRank'] is num ? b['tierRank'] : int.tryParse(b['tierRank']?.toString() ?? '0') ?? 0).toInt();
        if (tierRankA != tierRankB) return tierRankB.compareTo(tierRankA);

        // Tie-breaker 3: Likes and Superlikes
        final totalLikesA = (a['likesCount'] is num ? a['likesCount'] : int.tryParse(a['likesCount']?.toString() ?? '0') ?? 0).toInt() +
            (a['superLikesCount'] is num ? a['superLikesCount'] : int.tryParse(a['superLikesCount']?.toString() ?? '0') ?? 0).toInt();
        final totalLikesB = (b['likesCount'] is num ? b['likesCount'] : int.tryParse(b['likesCount']?.toString() ?? '0') ?? 0).toInt() +
            (b['superLikesCount'] is num ? b['superLikesCount'] : int.tryParse(b['superLikesCount']?.toString() ?? '0') ?? 0).toInt();
        return totalLikesB.compareTo(totalLikesA);
      });

      _filteredUsers = filtered;
    });
  }

  bool get _hasActiveFilters =>
      _searchQuery.isNotEmpty ||
      _selectedGender != 'All' ||
      _selectedAgeRange != 'All Ages' ||
      _selectedSortFilter != 'All';

  void _onSearchChanged(String query) {
    _searchQuery = query;
    _applyFilters();
  }

  @override
  Widget build(BuildContext context) {
    final isTablet = MediaQuery.of(context).size.width > 600;
    final crossAxisCount = isTablet ? 3 : 2;

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        title: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'ALL PROFILES',
              style: TextStyle(
                fontWeight: FontWeight.w900,
                fontSize: 16,
                letterSpacing: 0.8,
                color: Colors.black,
              ),
            ),
            const SizedBox(height: 2),
            if (_allUsers.isNotEmpty)
              Text(
                _hasActiveFilters
                    ? '${_filteredUsers.length} of ${_allUsers.length} ranked profiles'
                    : '${_allUsers.length} ranked profiles',
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
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded, color: LunaraTheme.electricViolet, size: 22),
            tooltip: 'Refresh Profiles',
            onPressed: () => _loadAllUsers(forceRefresh: true),
          ),
        ],
      ),
      body: Column(
        children: [
          // Search Input Bar
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 10, 20, 10),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(30),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.04),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
                border: Border.all(color: Colors.grey[200]!),
              ),
              child: TextField(
                controller: _searchController,
                onChanged: _onSearchChanged,
                style: const TextStyle(
                  color: Colors.black,
                  fontWeight: FontWeight.w600,
                  fontSize: 14,
                ),
                decoration: InputDecoration(
                  hintText: 'Search by name, city, username...',
                  hintStyle: TextStyle(
                    color: Colors.grey[400],
                    fontSize: 13.5,
                    fontWeight: FontWeight.w500,
                  ),
                  border: InputBorder.none,
                  prefixIcon: const Icon(
                    Icons.search_rounded,
                    color: LunaraTheme.electricViolet,
                    size: 22,
                  ),
                  prefixIconConstraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                  suffixIcon: _searchQuery.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear, color: Colors.black54, size: 18),
                          onPressed: () {
                            _searchController.clear();
                            _onSearchChanged('');
                          },
                        )
                      : null,
                ),
              ),
            ),
          ),

          // Sort Filters Row (Purple gradient on selected, clean white on unselected)
          Padding(
            padding: const EdgeInsets.only(left: 20, right: 20, bottom: 6),
            child: SizedBox(
              height: 36,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                physics: const BouncingScrollPhysics(),
                itemCount: _sortFilters.length,
                separatorBuilder: (context, index) => const SizedBox(width: 8),
                itemBuilder: (context, index) {
                  final filter = _sortFilters[index];
                  final isSelected = _selectedSortFilter == filter;
                  return InkWell(
                    borderRadius: BorderRadius.circular(20),
                    onTap: () {
                      setState(() {
                        if (_selectedSortFilter == filter) {
                          _selectedSortFilter = 'All';
                        } else {
                          _selectedSortFilter = filter;
                        }
                        _applyFilters();
                      });
                    },
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                      decoration: BoxDecoration(
                        gradient: isSelected
                            ? const LinearGradient(
                                colors: [Color(0xFF7F00FF), Color(0xFFA855F7)],
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                              )
                            : null,
                        color: isSelected ? null : Colors.white,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: isSelected
                              ? Colors.transparent
                              : Colors.grey[200]!,
                        ),
                        boxShadow: isSelected
                            ? [
                                BoxShadow(
                                  color: LunaraTheme.electricViolet.withValues(alpha: 0.35),
                                  blurRadius: 8,
                                  offset: const Offset(0, 2),
                                ),
                              ]
                            : [],
                      ),
                      child: Center(
                        child: Text(
                          filter,
                          style: TextStyle(
                            color: isSelected ? Colors.white : const Color(0xFF475569),
                            fontWeight: isSelected ? FontWeight.bold : FontWeight.w600,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ),

          // Secondary Filter Chips (Gender & Age - all in consistent purple styling, no blue/cyan)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              physics: const BouncingScrollPhysics(),
              child: Row(
                children: [
                  // Gender Chips
                  ..._genders.map((gender) {
                    final isSelected = _selectedGender == gender;
                    return Padding(
                      padding: const EdgeInsets.only(right: 6.0),
                      child: FilterChip(
                        label: Text(gender),
                        selected: isSelected,
                        onSelected: (selected) {
                          setState(() {
                            _selectedGender = gender;
                            _applyFilters();
                          });
                        },
                        selectedColor: LunaraTheme.electricViolet.withValues(alpha: 0.15),
                        backgroundColor: Colors.white,
                        labelStyle: TextStyle(
                          color: isSelected ? LunaraTheme.electricViolet : const Color(0xFF64748B),
                          fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                          fontSize: 11.5,
                        ),
                        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                        visualDensity: VisualDensity.compact,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                          side: BorderSide(
                            color: isSelected ? LunaraTheme.electricViolet : Colors.grey[200]!,
                          ),
                        ),
                      ),
                    );
                  }),
                  const SizedBox(width: 8),
                  Container(height: 18, width: 1, color: Colors.grey[300]),
                  const SizedBox(width: 8),
                  // Age Chips (All using purple styling)
                  ..._ageRanges.map((ageRange) {
                    final isSelected = _selectedAgeRange == ageRange;
                    return Padding(
                      padding: const EdgeInsets.only(right: 6.0),
                      child: FilterChip(
                        label: Text(ageRange),
                        selected: isSelected,
                        onSelected: (selected) {
                          setState(() {
                            _selectedAgeRange = ageRange;
                            _applyFilters();
                          });
                        },
                        selectedColor: LunaraTheme.electricViolet.withValues(alpha: 0.15),
                        backgroundColor: Colors.white,
                        labelStyle: TextStyle(
                          color: isSelected ? LunaraTheme.electricViolet : const Color(0xFF64748B),
                          fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                          fontSize: 11.5,
                        ),
                        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                        visualDensity: VisualDensity.compact,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                          side: BorderSide(
                            color: isSelected ? LunaraTheme.electricViolet : Colors.grey[200]!,
                          ),
                        ),
                      ),
                    );
                  }),
                ],
              ),
            ),
          ),

          const SizedBox(height: 6),

          // Main User Grid
          Expanded(
            child: _isLoading && _filteredUsers.isEmpty
                ? const Center(
                    child: CircularProgressIndicator(
                      color: LunaraTheme.electricViolet,
                    ),
                  )
                : RefreshIndicator(
                    color: LunaraTheme.electricViolet,
                    onRefresh: () => _loadAllUsers(forceRefresh: true),
                    child: _filteredUsers.isEmpty
                        ? SingleChildScrollView(
                            physics: const AlwaysScrollableScrollPhysics(),
                            child: SizedBox(
                              height: MediaQuery.of(context).size.height * 0.5,
                              child: Center(
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.all(16),
                                      decoration: BoxDecoration(
                                        shape: BoxShape.circle,
                                        color: LunaraTheme.electricViolet.withValues(alpha: 0.1),
                                      ),
                                      child: const Icon(
                                        Icons.person_search_rounded,
                                        size: 40,
                                        color: LunaraTheme.electricViolet,
                                      ),
                                    ),
                                    const SizedBox(height: 16),
                                    const Text(
                                      'No profiles found matching criteria',
                                      style: TextStyle(
                                        fontSize: 15,
                                        fontWeight: FontWeight.bold,
                                        color: Colors.black87,
                                      ),
                                    ),
                                    const SizedBox(height: 6),
                                    Text(
                                      'Try adjusting your search or filters',
                                      style: TextStyle(
                                        fontSize: 13,
                                        color: Colors.grey[600],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          )
                        : GridView.builder(
                            physics: const AlwaysScrollableScrollPhysics(
                              parent: BouncingScrollPhysics(),
                            ),
                            padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
                            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                              crossAxisCount: crossAxisCount,
                              crossAxisSpacing: 14,
                              mainAxisSpacing: 16,
                              childAspectRatio: 0.72,
                            ),
                            itemCount: _filteredUsers.length,
                            itemBuilder: (context, index) {
                              final user = _filteredUsers[index];
                              return _buildUserCard(user);
                            },
                          ),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildUserCard(dynamic user) {
    final String name = (user['firstName'] ?? user['fullName'] ?? user['name'] ?? 'User').toString();
    final String? age = user['age']?.toString();
    final String city = (user['city'] ?? (user['profile'] is Map ? user['profile']['city'] : null) ?? 'Discovery').toString();

    final int likes = (user['likesCount'] is num
            ? user['likesCount']
            : int.tryParse(user['likesCount']?.toString() ?? '0') ?? 0)
        .toInt();
    final int superLikes = (user['superLikesCount'] is num
            ? user['superLikesCount']
            : int.tryParse(user['superLikesCount']?.toString() ?? '0') ?? 0)
        .toInt();

    final dynamic bRaw = user['boostCount'] ?? user['boostsRemaining'];
    final int boosts = (bRaw is num ? bRaw : int.tryParse(bRaw?.toString() ?? '0') ?? 0).toInt();
    final bool isBoosted = user['isBoosted'] == true || boosts > 0;

    final String rawTier = (user['subscriptionTier'] ?? user['tier'] ?? user['packageTier'] ?? 'FREE').toString().toUpperCase();
    final String tier = (rawTier == 'NULL' || rawTier == 'UNDEFINED') ? 'FREE' : rawTier;
    final bool hasPlan = tier != 'FREE';
    final Color? planColor = LunaraTheme.getPlanBadgeColor(user);

    // Glowing border styling based on VIP status and Boost spotlight
    final Color cardBorderColor = isBoosted
        ? Colors.amber.withValues(alpha: 0.8)
        : (hasPlan && planColor != null
            ? planColor.withValues(alpha: 0.6)
            : Colors.grey[200]!);
    final double cardBorderWidth = (isBoosted || hasPlan) ? 1.6 : 1.0;

    return GestureDetector(
      onTap: () {
        try {
          final resolvedUser = User.fromJson(Map<String, dynamic>.from(user));
          final List<User> resolvedAllProfiles = [];
          for (var u in _filteredUsers) {
            try {
              resolvedAllProfiles.add(User.fromJson(Map<String, dynamic>.from(u)));
            } catch (_) {}
          }
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => ProfileScreen(
                user: resolvedUser,
                allProfiles: resolvedAllProfiles,
              ),
            ),
          );
        } catch (e) {
          debugPrint('Error navigating to user profile: $e');
        }
      },
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          gradient: LunaraTheme.cardGradient,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: cardBorderColor,
            width: cardBorderWidth,
          ),
          boxShadow: [
            BoxShadow(
              color: isBoosted
                  ? Colors.amber.withValues(alpha: 0.15)
                  : (hasPlan && planColor != null
                      ? planColor.withValues(alpha: 0.12)
                      : Colors.black.withValues(alpha: 0.04)),
              blurRadius: (isBoosted || hasPlan) ? 12 : 8,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            // Top Badge Row (Boosted / VIP Tier Pill)
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                if (hasPlan)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: tier == 'ELITE'
                            ? [const Color(0xFFFFD700), const Color(0xFFFFB703)]
                            : tier == 'PRO'
                                ? [const Color(0xFFE100FF), const Color(0xFF7F00FF)]
                                : tier == 'PLUS'
                                    ? [const Color(0xFF7F00FF), const Color(0xFFAA44FF)]
                                    : [const Color(0xFF00A9FF), const Color(0xFF0066FF)],
                      ),
                      borderRadius: BorderRadius.circular(10),
                      boxShadow: [
                        BoxShadow(
                          color: (planColor ?? LunaraTheme.electricViolet).withValues(alpha: 0.3),
                          blurRadius: 4,
                          offset: const Offset(0, 1),
                        ),
                      ],
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          tier == 'ELITE' ? Icons.star_rounded : Icons.verified_rounded,
                          color: Colors.white,
                          size: 10,
                        ),
                        const SizedBox(width: 3),
                        Text(
                          tier,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 9.5,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ],
                    ),
                  )
                else
                  const SizedBox(width: 1),

                if (isBoosted)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2.5),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFFFFB703), Color(0xFFFF8800)],
                      ),
                      borderRadius: BorderRadius.circular(10),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.amber.withValues(alpha: 0.4),
                          blurRadius: 4,
                          offset: const Offset(0, 1),
                        ),
                      ],
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.bolt_rounded, color: Colors.white, size: 10),
                        SizedBox(width: 2),
                        Text(
                          'BOOSTED',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 9,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 0.3,
                          ),
                        ),
                      ],
                    ),
                  )
                else
                  const SizedBox(width: 1),
              ],
            ),

            // Profile Avatar with dynamic VIP ring
            LunaraProfileImage(
              userData: user,
              radius: 34,
              isInteractive: false,
              showGradientBorder: true,
              overrideTier: tier,
            ),

            // Name and Verified Checkmark
            Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Flexible(
                      child: Text(
                        age != null && age.isNotEmpty && age != 'null' ? '$name, $age' : name,
                        style: const TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.bold,
                          color: Colors.black,
                          letterSpacing: 0.1,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                      ),
                    ),
                    if (planColor != null) ...[
                      const SizedBox(width: 4),
                      Icon(
                        Icons.verified_rounded,
                        color: planColor,
                        size: 14,
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  city,
                  style: const TextStyle(
                    fontSize: 10.5,
                    color: Color(0xFF64748B),
                    fontWeight: FontWeight.w500,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),

            // Metrics Row: Superlikes & Likes Badges
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Superlikes chip
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                  decoration: BoxDecoration(
                    color: const Color(0xFF9333EA).withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: const Color(0xFF9333EA).withValues(alpha: 0.2),
                      width: 0.8,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.star_rounded,
                        color: Color(0xFF9333EA),
                        size: 12,
                      ),
                      const SizedBox(width: 3),
                      Text(
                        '$superLikes',
                        style: const TextStyle(
                          color: Color(0xFF9333EA),
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 6),
                // Likes chip
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                  decoration: BoxDecoration(
                    color: const Color(0xFFEC4899).withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: const Color(0xFFEC4899).withValues(alpha: 0.2),
                      width: 0.8,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.favorite_rounded,
                        color: Color(0xFFEC4899),
                        size: 12,
                      ),
                      const SizedBox(width: 3),
                      Text(
                        '$likes',
                        style: const TextStyle(
                          color: Color(0xFFEC4899),
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
