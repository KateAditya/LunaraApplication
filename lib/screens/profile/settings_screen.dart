import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../core/theme.dart';
import '../../services/api_service.dart';
import '../../models/help_article.dart';
import '../../models/community_guideline.dart';
import '../../models/legal_document.dart';



class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _incognitoMode = false;
  bool _pushNotifications = true;
  bool _marketingEmails = false;
  bool _biometricAuth = true;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.all(24.0),
                children: [
                  _buildSectionHeader('ACCOUNT & SECURITY'),
                  const SizedBox(height: 16),
                  _buildSettingsTile(
                    'Personal Information',
                    Icons.person_outline,
                    () => _showPersonalInfoSheet(),
                  ),
                  _buildSettingsTile(
                    'Change Password',
                    Icons.lock_outline,
                    () => _showChangePasswordSheet(),
                  ),
                  _buildSwitchTile(
                    'Biometric Authentication',
                    _biometricAuth,
                    (v) => setState(() => _biometricAuth = v),
                  ),
                  const SizedBox(height: 40),
                  _buildSectionHeader('PRIVACY'),
                  const SizedBox(height: 16),
                  _buildSwitchTile(
                    'Incognito Mode',
                    _incognitoMode,
                    (v) => setState(() => _incognitoMode = v),
                  ),
                  _buildSettingsTile(
                    'Blocked Contacts',
                    Icons.block_flipped,
                    () => _showBlockedContactsSheet(),
                  ),
                  _buildSettingsTile(
                    'Data & Permissions',
                    Icons.data_usage_outlined,
                    () => _showDataPermissionsSheet(),
                  ),
                  const SizedBox(height: 40),
                  _buildSectionHeader('NOTIFICATIONS'),
                  const SizedBox(height: 16),
                  _buildSwitchTile(
                    'Push Notifications',
                    _pushNotifications,
                    (v) => setState(() => _pushNotifications = v),
                  ),
                  _buildSwitchTile(
                    'Marketing Emails',
                    _marketingEmails,
                    (v) => setState(() => _marketingEmails = v),
                  ),
                  const SizedBox(height: 40),
                  _buildSectionHeader('SUPPORT & LEGAL'),
                  const SizedBox(height: 16),
                  _buildSettingsTile(
                    'Help Center',
                    Icons.help_outline,
                    () => _showHelpCenterSheet(),
                  ),
                  _buildSettingsTile(
                    'Community Guidelines',
                    Icons.groups_outlined,
                    () => _showCommunityGuidelinesSheet(),
                  ),
                  _buildSettingsTile(
                    'Legal & Terms',
                    Icons.gavel_outlined,
                    () => _showLegalDocumentsSheet(),
                  ),
                  const SizedBox(height: 40),
                  _buildDangerZone(),
                  const SizedBox(height: 40),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.all(20.0),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back, color: Colors.black),
            onPressed: () => Navigator.pop(context),
          ),
          const SizedBox(width: 8),
          const Text(
            'SETTINGS',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w900,
              letterSpacing: 4,
              color: Colors.black,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Text(
      title,
      style: TextStyle(
        color: Colors.black,
        fontSize: 10,
        fontWeight: FontWeight.w900,
        letterSpacing: 2,
      ),
    );
  }

  Widget _buildSettingsTile(String title, IconData icon, VoidCallback onTap) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            gradient: LunaraTheme.cardGradient,
            borderRadius: BorderRadius.circular(20),
            boxShadow: LunaraTheme.premiumCardShadow,
            border: Border.all(color: LunaraTheme.electricViolet.withValues(alpha: 0.05)),
          ),
          child: Row(
            children: [
              Icon(icon, color: Colors.black, size: 20),
              const SizedBox(width: 16),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    color: Colors.black,
                    fontSize: 14,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              Icon(Icons.chevron_right, color: Colors.grey[300], size: 20),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSwitchTile(
    String title,
    bool value,
    ValueChanged<bool> onChanged,
  ) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          gradient: LunaraTheme.cardGradient,
          borderRadius: BorderRadius.circular(20),
          boxShadow: LunaraTheme.premiumCardShadow,
          border: Border.all(color: LunaraTheme.electricViolet.withValues(alpha: 0.05)),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                title,
                style: const TextStyle(
                  color: Colors.black,
                  fontSize: 14,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
            Switch.adaptive(
              value: value,
              onChanged: onChanged,
              activeTrackColor: LunaraTheme.electricViolet.withValues(alpha: 0.3),
              activeColor: LunaraTheme.electricViolet,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDangerZone() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'DANGER ZONE',
          style: TextStyle(
            color: Colors.redAccent,
            fontSize: 10,
            fontWeight: FontWeight.w900,
            letterSpacing: 2,
          ),
        ),
        const SizedBox(height: 16),
        GestureDetector(
          onTap: () => _showDeleteAccountDialog(),
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.red.withValues(alpha: 0.05),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: Colors.red.withValues(alpha: 0.1)),
            ),
            child: const Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.delete_forever_outlined, color: Colors.redAccent, size: 20),
                SizedBox(width: 12),
                Text(
                  'DELETE ACCOUNT',
                  style: TextStyle(
                    color: Colors.redAccent,
                    fontSize: 12,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  // --- Bottom sheets and dialogs ---

  void _showPersonalInfoSheet() {
    final nameController = TextEditingController(text: 'Julian V.');
    final emailController = TextEditingController(text: 'julian@lunara.app');
    final phoneController = TextEditingController(text: '+91 98765 43210');

    _showFormSheet(
      title: 'PERSONAL INFORMATION',
      children: [
        _formField('Full Name', nameController, Icons.person_outline),
        const SizedBox(height: 16),
        _formField('Email', emailController, Icons.email_outlined),
        const SizedBox(height: 16),
        _formField('Phone', phoneController, Icons.phone_outlined),
        const SizedBox(height: 32),
        _saveButton('SAVE CHANGES'),
      ],
    );
  }

  void _showChangePasswordSheet() {
    final oldController = TextEditingController();
    final newController = TextEditingController();
    final confirmController = TextEditingController();

    bool isUpdating = false;

    _showFormSheet(
      title: 'CHANGE PASSWORD',
      children: [
        _formField(
          'Current Password',
          oldController,
          Icons.lock_outline,
          obscure: true,
        ),
        const SizedBox(height: 16),
        _formField('New Password', newController, Icons.lock_outline, obscure: true),
        const SizedBox(height: 16),
        _formField(
          'Confirm Password',
          confirmController,
          Icons.lock_reset,
          obscure: true,
        ),
        const SizedBox(height: 32),
        StatefulBuilder(
          builder: (context, setState) {
            return _saveButton(
              'UPDATE PASSWORD',
              isLoading: isUpdating,
              onPressed: () async {
                if (newController.text.isEmpty || oldController.text.isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Please fill all fields'), backgroundColor: Colors.red),
                  );
                  return;
                }
                if (newController.text != confirmController.text) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('New passwords do not match'), backgroundColor: Colors.red),
                  );
                  return;
                }
                
                setState(() => isUpdating = true);
                
                final success = await ApiService.changePassword(
                  oldController.text,
                  newController.text,
                  confirmController.text,
                );
                
                if (!mounted) return;
                setState(() => isUpdating = false);
                
                if (success) {
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Password updated successfully!'), backgroundColor: Colors.green),
                  );
                } else {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Failed to update password. Check your current password.'), backgroundColor: Colors.red),
                  );
                }
              },
            );
          }
        ),
      ],
    );
  }

  void _showBlockedContactsSheet() {
    _showFormSheet(
      title: 'BLOCKED CONTACTS',
      children: [
        const SizedBox(height: 40),
        Center(child: Icon(Icons.block_flipped, color: Colors.grey[200], size: 64)),
        const SizedBox(height: 24),
        const Center(
          child: Text(
            'No blocked contacts',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w900,
              color: Colors.black,
            ),
          ),
        ),
        const SizedBox(height: 8),
        Center(
          child: Text(
            'Blocked users will appear here',
            style: TextStyle(color: Colors.black, fontSize: 13),
          ),
        ),
        const SizedBox(height: 40),
      ],
    );
  }

  void _showDataPermissionsSheet() {
    _showFormSheet(
      title: 'DATA & PERMISSIONS',
      children: [
        _infoTile(
          Icons.location_on_outlined,
          'Location',
          'Enabled — used for nearby venues',
        ),
        _infoTile(
          Icons.camera_alt_outlined,
          'Camera',
          'Enabled — used for profile photos',
        ),
        _infoTile(
          Icons.photo_library_outlined,
          'Photo Library',
          'Enabled — used for uploads',
        ),
        _infoTile(Icons.notifications_none, 'Notifications', 'Enabled'),
        const SizedBox(height: 32),
        GestureDetector(
          onTap: () {
            Navigator.pop(context);
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text(
                  'Data export request sent. You\'ll receive an email shortly.',
                ),
                backgroundColor: LunaraTheme.electricViolet,
              ),
            );
          },
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: LunaraTheme.electricViolet.withValues(alpha: 0.05),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: LunaraTheme.electricViolet.withValues(alpha: 0.1)),
            ),
            child: const Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.download_rounded, color: LunaraTheme.electricViolet, size: 20),
                SizedBox(width: 12),
                Text(
                  'REQUEST DATA EXPORT',
                  style: TextStyle(
                    color: LunaraTheme.electricViolet,
                    fontWeight: FontWeight.w900,
                    fontSize: 12,
                    letterSpacing: 1,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }


  void _showHelpCenterSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
      ),
      isScrollControlled: true,
      builder: (ctx) {
        return const HelpCenterSheet();
      },
    );
  }

  void _showCommunityGuidelinesSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
      ),
      isScrollControlled: true,
      builder: (ctx) {
        return const CommunityGuidelinesSheet();
      },
    );
  }

  void _showLegalDocumentsSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
      ),
      isScrollControlled: true,
      builder: (ctx) {
        return const LegalDocumentsSheet();
      },
    );
  }

  void _showDeleteAccountDialog() {
    showDialog(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          backgroundColor: Colors.white,
          surfaceTintColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(32),
          ),
          title: const Text(
            'DELETE ACCOUNT',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w900,
              color: Colors.redAccent,
              letterSpacing: 2,
            ),
            textAlign: TextAlign.center,
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.warning_amber_rounded,
                color: Colors.red[100],
                size: 64,
              ),
              const SizedBox(height: 20),
              Text(
                'Are you sure you want to delete your account? This action cannot be undone. All your data, bookings, and matches will be permanently removed.',
                style: TextStyle(color: Colors.black, fontSize: 14),
                textAlign: TextAlign.center,
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text(
                'CANCEL',
                style: TextStyle(color: Colors.black, fontWeight: FontWeight.w900),
              ),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.redAccent,
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              onPressed: () {
                Navigator.pop(ctx);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text(
                      'Account deletion request submitted. You will be logged out shortly.',
                    ),
                    backgroundColor: Colors.redAccent,
                  ),
                );
              },
              child: const Text(
                'DELETE',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  // --- Helper widgets ---

  void _showFormSheet({required String title, required List<Widget> children}) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
      ),
      isScrollControlled: true,
      builder: (ctx) {
        return Padding(
          padding: EdgeInsets.fromLTRB(
            24,
            24,
            24,
            MediaQuery.of(ctx).viewInsets.bottom + 40,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey[200],
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 32),
              Text(
                title,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 2,
                  color: Colors.black,
                ),
              ),
              const SizedBox(height: 32),
              ...children,
            ],
          ),
        );
      },
    );
  }

  Widget _formField(
    String label,
    TextEditingController controller,
    IconData icon, {
    bool obscure = false,
  }) {
    return TextField(
      controller: controller,
      obscureText: obscure,
      style: const TextStyle(color: Colors.black, fontWeight: FontWeight.bold),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(color: Colors.black, fontWeight: FontWeight.w900),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: Colors.grey[100]!),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: LunaraTheme.electricViolet),
        ),
        prefixIcon: Icon(icon, color: Colors.grey[400]),
        filled: true,
        fillColor: Colors.grey[50],
      ),
    );
  }

  Widget _saveButton(String label, {VoidCallback? onPressed, bool isLoading = false}) {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton(
        style: ElevatedButton.styleFrom(
          backgroundColor: LunaraTheme.electricViolet,
          padding: const EdgeInsets.symmetric(vertical: 20),
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
        ),
        onPressed: isLoading 
            ? null 
            : (onPressed ?? () {
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Changes saved successfully!'),
                    backgroundColor: LunaraTheme.electricViolet,
                  ),
                );
              }),
        child: isLoading
            ? const SizedBox(
                height: 20,
                width: 20,
                child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
              )
            : Text(
                label,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 2,
                ),
              ),
      ),
    );
  }

  Widget _infoTile(IconData icon, String title, String subtitle) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Row(
        children: [
          Icon(icon, color: LunaraTheme.electricViolet, size: 24),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: Colors.black,
                    fontSize: 14,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: const TextStyle(color: Colors.black, fontSize: 12),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class HelpCenterSheet extends StatefulWidget {
  const HelpCenterSheet({super.key});

  @override
  State<HelpCenterSheet> createState() => _HelpCenterSheetState();
}

class _HelpCenterSheetState extends State<HelpCenterSheet> {
  late Future<List<HelpArticle>> _future;

  @override
  void initState() {
    super.initState();
    _future = ApiService.fetchHelpCenterArticles();
  }

  void _retry() {
    setState(() {
      _future = ApiService.fetchHelpCenterArticles();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: MediaQuery.of(context).size.height * 0.8,
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Column(
        children: [
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.grey[200],
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 24),
          const Text(
            'HELP CENTER',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w900,
              letterSpacing: 4,
              color: Colors.black,
            ),
          ),
          const SizedBox(height: 24),
          Expanded(
            child: FutureBuilder<List<HelpArticle>>(
              future: _future,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(
                    child: CircularProgressIndicator(
                      color: LunaraTheme.electricViolet,
                    ),
                  );
                }
                if (snapshot.hasError) {
                  return _buildErrorView();
                }
                final articles = snapshot.data;
                if (articles == null || articles.isEmpty) {
                  return _buildEmptyView();
                }

                return ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  itemCount: articles.length,
                  itemBuilder: (context, index) {
                    final article = articles[index];
                    return _buildArticleCard(article);
                  },
                );
              },
            ),
          ),
          _buildSupportContactBar(),
        ],
      ),
    );
  }

  Widget _buildArticleCard(HelpArticle article) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        gradient: LunaraTheme.cardGradient,
        borderRadius: BorderRadius.circular(20),
        boxShadow: LunaraTheme.premiumCardShadow,
        border: Border.all(color: LunaraTheme.electricViolet.withValues(alpha: 0.05)),
      ),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          title: Text(
            article.title,
            style: const TextStyle(
              color: Colors.black,
              fontSize: 14,
              fontWeight: FontWeight.w900,
            ),
          ),
          subtitle: Text(
            article.category.toUpperCase(),
            style: const TextStyle(
              color: LunaraTheme.electricViolet,
              fontSize: 10,
              fontWeight: FontWeight.w900,
              letterSpacing: 1,
            ),
          ),
          iconColor: LunaraTheme.electricViolet,
          collapsedIconColor: Colors.black54,
          childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          children: [
            Text(
              article.content,
              style: const TextStyle(
                color: Colors.black,
                fontSize: 13,
                height: 1.6,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildErrorView() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error_outline_rounded, color: Colors.red[300], size: 48),
            const SizedBox(height: 16),
            const Text(
              'FAILED TO LOAD HELP CENTER',
              style: TextStyle(
                color: Colors.black,
                fontSize: 14,
                fontWeight: FontWeight.w900,
                letterSpacing: 1,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Please check your internet connection and try again.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.grey,
                fontSize: 12,
              ),
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: _retry,
              style: ElevatedButton.styleFrom(
                backgroundColor: LunaraTheme.electricViolet,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              ),
              child: const Text(
                'RETRY',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyView() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.help_outline_rounded, color: Colors.grey[300], size: 48),
            const SizedBox(height: 16),
            const Text(
              'NO HELP ARTICLES FOUND',
              style: TextStyle(
                color: Colors.black,
                fontSize: 14,
                fontWeight: FontWeight.w900,
                letterSpacing: 1,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Support articles will appear here once published.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.grey,
                fontSize: 12,
              ),
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: _retry,
              style: ElevatedButton.styleFrom(
                backgroundColor: LunaraTheme.electricViolet,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              ),
              child: const Text(
                'REFRESH',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSupportContactBar() {
    return Container(
      padding: const EdgeInsets.all(20),
      margin: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: LunaraTheme.primaryGradient,
        borderRadius: BorderRadius.circular(24),
        boxShadow: LunaraTheme.premiumShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            'STILL NEED HELP?',
            style: TextStyle(
              color: Colors.white,
              fontSize: 11,
              fontWeight: FontWeight.w900,
              letterSpacing: 2,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Get in touch with our 24/7 Support team.',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.8),
              fontSize: 12,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: _buildContactButton(
                  icon: Icons.mail_outline,
                  label: 'EMAIL',
                  onTap: () {
                    Clipboard.setData(const ClipboardData(text: 'support@lunara.buzz'));
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Support email copied to clipboard!'),
                        backgroundColor: LunaraTheme.electricViolet,
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildContactButton(
                  icon: Icons.phone_outlined,
                  label: 'CALL',
                  onTap: () {
                    Clipboard.setData(const ClipboardData(text: '+919876543210'));
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Support phone number copied to clipboard!'),
                        backgroundColor: LunaraTheme.electricViolet,
                      ),
                    );
                  },
                ),
              ),
            ],
          )
        ],
      ),
    );
  }

  Widget _buildContactButton({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: LunaraTheme.electricViolet, size: 16),
            const SizedBox(width: 8),
            Text(
              label,
              style: const TextStyle(
                color: LunaraTheme.electricViolet,
                fontSize: 11,
                fontWeight: FontWeight.w900,
                letterSpacing: 0.5,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class CommunityGuidelinesSheet extends StatefulWidget {
  const CommunityGuidelinesSheet({super.key});

  @override
  State<CommunityGuidelinesSheet> createState() => _CommunityGuidelinesSheetState();
}

class _CommunityGuidelinesSheetState extends State<CommunityGuidelinesSheet> {
  late Future<List<CommunityGuideline>> _future;

  @override
  void initState() {
    super.initState();
    _future = ApiService.fetchCommunityGuidelines();
  }

  void _retry() {
    setState(() {
      _future = ApiService.fetchCommunityGuidelines();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: MediaQuery.of(context).size.height * 0.8,
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Column(
        children: [
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.grey[200],
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 24),
          const Text(
            'COMMUNITY GUIDELINES',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w900,
              letterSpacing: 4,
              color: Colors.black,
            ),
          ),
          const SizedBox(height: 24),
          Expanded(
            child: FutureBuilder<List<CommunityGuideline>>(
              future: _future,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(
                    child: CircularProgressIndicator(
                      color: LunaraTheme.electricViolet,
                    ),
                  );
                }
                if (snapshot.hasError) {
                  return _buildErrorView();
                }
                final guidelines = snapshot.data;
                if (guidelines == null || guidelines.isEmpty) {
                  return _buildEmptyView();
                }

                return ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  itemCount: guidelines.length,
                  itemBuilder: (context, index) {
                    final guideline = guidelines[index];
                    return _buildGuidelineCard(guideline);
                  },
                );
              },
            ),
          ),
          _buildInfoBanner(),
        ],
      ),
    );
  }

  Widget _buildGuidelineCard(CommunityGuideline guideline) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        gradient: LunaraTheme.cardGradient,
        borderRadius: BorderRadius.circular(20),
        boxShadow: LunaraTheme.premiumCardShadow,
        border: Border.all(color: LunaraTheme.electricViolet.withValues(alpha: 0.05)),
      ),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          title: Text(
            guideline.title,
            style: const TextStyle(
              color: Colors.black,
              fontSize: 14,
              fontWeight: FontWeight.w900,
            ),
          ),
          subtitle: Text(
            guideline.category.toUpperCase(),
            style: const TextStyle(
              color: LunaraTheme.electricViolet,
              fontSize: 10,
              fontWeight: FontWeight.w900,
              letterSpacing: 1,
            ),
          ),
          iconColor: LunaraTheme.electricViolet,
          collapsedIconColor: Colors.black54,
          initiallyExpanded: true,
          childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          children: [
            Text(
              guideline.content,
              style: const TextStyle(
                color: Colors.black,
                fontSize: 13,
                height: 1.6,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildErrorView() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error_outline_rounded, color: Colors.red[300], size: 48),
            const SizedBox(height: 16),
            const Text(
              'FAILED TO LOAD GUIDELINES',
              style: TextStyle(
                color: Colors.black,
                fontSize: 14,
                fontWeight: FontWeight.w900,
                letterSpacing: 1,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Please check your internet connection and try again.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.grey,
                fontSize: 12,
              ),
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: _retry,
              style: ElevatedButton.styleFrom(
                backgroundColor: LunaraTheme.electricViolet,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              ),
              child: const Text(
                'RETRY',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyView() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.gavel_rounded, color: Colors.grey[300], size: 48),
            const SizedBox(height: 16),
            const Text(
              'NO GUIDELINES FOUND',
              style: TextStyle(
                color: Colors.black,
                fontSize: 14,
                fontWeight: FontWeight.w900,
                letterSpacing: 1,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Guidelines will appear here once published.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.grey,
                fontSize: 12,
              ),
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: _retry,
              style: ElevatedButton.styleFrom(
                backgroundColor: LunaraTheme.electricViolet,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              ),
              child: const Text(
                'REFRESH',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoBanner() {
    return Container(
      padding: const EdgeInsets.all(20),
      margin: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: LunaraTheme.secondaryGradient,
        borderRadius: BorderRadius.circular(24),
        boxShadow: LunaraTheme.premiumShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          const Row(
            children: [
              Icon(Icons.shield_outlined, color: Colors.white, size: 20),
              SizedBox(width: 8),
              Text(
                'STAY RESPECTFUL',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 11,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 2,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Guidelines are in place to ensure a safe, fun, and inclusive environment for everyone. Violations may result in account suspension.',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.8),
              fontSize: 12,
              height: 1.5,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}

class LegalDocumentsSheet extends StatefulWidget {
  const LegalDocumentsSheet({super.key});

  @override
  State<LegalDocumentsSheet> createState() => _LegalDocumentsSheetState();
}

class _LegalDocumentsSheetState extends State<LegalDocumentsSheet> {
  late Future<List<LegalDocument>> _future;

  @override
  void initState() {
    super.initState();
    _future = ApiService.fetchLegalDocuments();
  }

  void _retry() {
    setState(() {
      _future = ApiService.fetchLegalDocuments();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: MediaQuery.of(context).size.height * 0.8,
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Column(
        children: [
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.grey[200],
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 24),
          const Text(
            'LEGAL & TERMS',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w900,
              letterSpacing: 4,
              color: Colors.black,
            ),
          ),
          const SizedBox(height: 24),
          Expanded(
            child: FutureBuilder<List<LegalDocument>>(
              future: _future,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(
                    child: CircularProgressIndicator(
                      color: LunaraTheme.electricViolet,
                    ),
                  );
                }
                if (snapshot.hasError) {
                  return _buildErrorView();
                }
                final documents = snapshot.data;
                if (documents == null || documents.isEmpty) {
                  return _buildEmptyView();
                }

                return ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  itemCount: documents.length,
                  itemBuilder: (context, index) {
                    final document = documents[index];
                    return _buildDocumentCard(document);
                  },
                );
              },
            ),
          ),
          _buildInfoBanner(),
        ],
      ),
    );
  }

  Widget _buildDocumentCard(LegalDocument document) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        gradient: LunaraTheme.cardGradient,
        borderRadius: BorderRadius.circular(20),
        boxShadow: LunaraTheme.premiumCardShadow,
        border: Border.all(color: LunaraTheme.electricViolet.withValues(alpha: 0.05)),
      ),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          title: Text(
            document.title,
            style: const TextStyle(
              color: Colors.black,
              fontSize: 14,
              fontWeight: FontWeight.w900,
            ),
          ),
          subtitle: Text(
            'VERSION ${document.version} — ACTIVE',
            style: const TextStyle(
              color: LunaraTheme.electricViolet,
              fontSize: 10,
              fontWeight: FontWeight.w900,
              letterSpacing: 1,
            ),
          ),
          iconColor: LunaraTheme.electricViolet,
          collapsedIconColor: Colors.black54,
          initiallyExpanded: true,
          childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          children: [
            Text(
              document.content,
              style: const TextStyle(
                color: Colors.black,
                fontSize: 13,
                height: 1.6,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildErrorView() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error_outline_rounded, color: Colors.red[300], size: 48),
            const SizedBox(height: 16),
            const Text(
              'FAILED TO LOAD LEGAL DOCUMENTS',
              style: TextStyle(
                color: Colors.black,
                fontSize: 14,
                fontWeight: FontWeight.w900,
                letterSpacing: 1,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Please check your internet connection and try again.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.grey,
                fontSize: 12,
              ),
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: _retry,
              style: ElevatedButton.styleFrom(
                backgroundColor: LunaraTheme.electricViolet,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              ),
              child: const Text(
                'RETRY',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyView() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.gavel_rounded, color: Colors.grey[300], size: 48),
            const SizedBox(height: 16),
            const Text(
              'NO LEGAL DOCUMENTS FOUND',
              style: TextStyle(
                color: Colors.black,
                fontSize: 14,
                fontWeight: FontWeight.w900,
                letterSpacing: 1,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Legal terms will appear here once published.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.grey,
                fontSize: 12,
              ),
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: _retry,
              style: ElevatedButton.styleFrom(
                backgroundColor: LunaraTheme.electricViolet,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              ),
              child: const Text(
                'REFRESH',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoBanner() {
    return Container(
      padding: const EdgeInsets.all(20),
      margin: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: LunaraTheme.amberGlow,
        borderRadius: BorderRadius.circular(24),
        boxShadow: LunaraTheme.premiumShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          const Row(
            children: [
              Icon(Icons.gavel_outlined, color: Colors.white, size: 20),
              SizedBox(width: 8),
              Text(
                'LEGAL AGREEMENT',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 11,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 2,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Your privacy, trust, and security are our highest priority. All documents here represent a binding legal agreement.',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.9),
              fontSize: 12,
              height: 1.5,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}
