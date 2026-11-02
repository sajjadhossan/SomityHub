import 'dart:convert';
import 'dart:math' as math;

import 'package:device_info_plus/device_info_plus.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show defaultTargetPlatform, kIsWeb, TargetPlatform;
import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import 'cooperative_documents_page.dart';
import 'cooperative_operations_page.dart';
import 'multi_branch_assignment_page.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const supabaseUrl = String.fromEnvironment('SUPABASE_URL');
const supabasePublishableKey = String.fromEnvironment('SUPABASE_PUBLISHABLE_KEY');

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (supabaseUrl.isNotEmpty && supabasePublishableKey.isNotEmpty) {
    await Supabase.initialize(url: supabaseUrl, anonKey: supabasePublishableKey);
  }
  runApp(const SomityHubApp());
}

class SomityHubApp extends StatelessWidget {
  const SomityHubApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'SomityHub',
    debugShowCheckedModeBanner: false,
    theme: ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF126B55)),
      scaffoldBackgroundColor: const Color(0xFFF5F7F6),
      inputDecorationTheme: const InputDecorationTheme(border: OutlineInputBorder()),
    ),
    home: supabaseUrl.isEmpty || supabasePublishableKey.isEmpty
      ? const ConfigurationPage() : const AuthGate(),
  );
}

class ConfigurationPage extends StatelessWidget {
  const ConfigurationPage({super.key});
  @override
  Widget build(BuildContext context) => const Scaffold(
    body: SafeArea(child: Center(child: Padding(
      padding: EdgeInsets.all(24),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Icon(Icons.groups_rounded, size: 64, color: Color(0xFF126B55)),
        SizedBox(height: 16),
        Text('SomityHub', style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold)),
        SizedBox(height: 12),
        Text('Supabase configuration is missing. Build with SUPABASE_URL and SUPABASE_PUBLISHABLE_KEY dart-defines. Never use a service-role key in this app.', textAlign: TextAlign.center),
      ]),
    ))),
  );
}

class AuthGate extends StatelessWidget {
  const AuthGate({super.key});
  @override
  Widget build(BuildContext context) {
    final client = Supabase.instance.client;
    return StreamBuilder<AuthState>(
      stream: client.auth.onAuthStateChange,
      builder: (context, snapshot) => client.auth.currentSession != null
        ? const CommitteePage() : const LoginPage(),
    );
  }
}

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});
  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _register = false;
  bool _busy = false;
  bool _obscure = true;
  String? _message;
  String? _error;

  @override
  void dispose() {
    _name.dispose(); _email.dispose(); _password.dispose(); super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() { _busy = true; _message = null; _error = null; });
    try {
      final auth = Supabase.instance.client.auth;
      if (_register) {
        final result = await auth.signUp(
          email: _email.text.trim(), password: _password.text,
          data: {'display_name': _name.text.trim(), 'preferred_language': 'bn'},
        );
        if (result.session == null && mounted) {
          setState(() => _message = 'Registration request হয়েছে। Email confirmation link খুলে তারপর Login করুন।');
        }
      } else {
        await auth.signInWithPassword(email: _email.text.trim(), password: _password.text);
      }
    } on AuthException catch (e) {
      if (mounted) { setState(() => _error = e.toString()); }
    } catch (e) {
      if (mounted) { setState(() => _error = 'Request failed: $e'); }
    } finally {
      if (mounted) { setState(() => _busy = false); }
    }
  }

  Future<void> _resetPassword() async {
    if (_email.text.trim().isEmpty) { setState(() => _error = 'আগে Email address লিখুন।'); return; }
    setState(() { _busy = true; _error = null; _message = null; });
    try {
      await Supabase.instance.client.auth.resetPasswordForEmail(_email.text.trim());
      if (mounted) { setState(() => _message = 'Email address registered থাকলে password reset link পাঠানো হয়েছে।'); }
    } on AuthException catch (e) {
      if (mounted) { setState(() => _error = e.toString()); }
    } finally {
      if (mounted) { setState(() => _busy = false); }
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(child: Center(child: SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 440), child: Card(
        child: Padding(padding: const EdgeInsets.all(24), child: Form(
          key: _formKey,
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            const Icon(Icons.groups_rounded, size: 56, color: Color(0xFF126B55)),
            const SizedBox(height: 12),
            const Text('SomityHub', textAlign: TextAlign.center, style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Text(_register ? 'নতুন Account তৈরি করুন' : 'আপনার Account-এ প্রবেশ করুন', textAlign: TextAlign.center),
            const SizedBox(height: 24),
            SegmentedButton<bool>(
              segments: const [ButtonSegment(value: false, label: Text('Login')), ButtonSegment(value: true, label: Text('Registration'))],
              selected: {_register},
              onSelectionChanged: _busy ? null : (v) => setState(() { _register = v.first; _message = null; _error = null; }),
            ),
            const SizedBox(height: 20),
            if (_register) ...[
              TextFormField(controller: _name, decoration: const InputDecoration(labelText: 'পূর্ণ নাম'),
                validator: (v) => v == null || v.trim().length < 2 ? 'কমপক্ষে ২ অক্ষরের নাম দিন।' : null),
              const SizedBox(height: 14),
            ],
            TextFormField(controller: _email, keyboardType: TextInputType.emailAddress,
              decoration: const InputDecoration(labelText: 'Email Address'),
              validator: (v) => v == null || !v.contains('@') ? 'সঠিক Email দিন।' : null),
            const SizedBox(height: 14),
            TextFormField(controller: _password, obscureText: _obscure,
              decoration: InputDecoration(labelText: 'Password', suffixIcon: IconButton(
                onPressed: () => setState(() => _obscure = !_obscure),
                icon: Icon(_obscure ? Icons.visibility : Icons.visibility_off))),
              validator: (v) => v == null || v.length < 8 ? 'Password কমপক্ষে ৮ অক্ষরের হতে হবে।' : null),
            if (!_register) Align(alignment: Alignment.centerRight,
              child: TextButton(onPressed: _busy ? null : _resetPassword, child: const Text('Password ভুলে গেছেন?'))),
            const SizedBox(height: 12),
            FilledButton(onPressed: _busy ? null : _submit,
              child: _busy ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2))
                : Text(_register ? 'Account তৈরি করুন' : 'Login করুন')),
            if (_message != null) ...[const SizedBox(height: 16), Text(_message!, style: const TextStyle(color: Colors.green))],
            if (_error != null) ...[const SizedBox(height: 16), Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error))],
          ]),
        )),
      )),
    ))),
  );
}

class CommitteePage extends StatefulWidget {
  const CommitteePage({super.key});
  @override
  State<CommitteePage> createState() => _CommitteePageState();
}

class _CommitteePageState extends State<CommitteePage> {
  late Future<List<Map<String, dynamic>>> _committees;
  @override
  void initState() { super.initState(); _committees = _loadCommittees(); }

  Future<List<Map<String, dynamic>>> _loadCommittees() async {
    final rows = await Supabase.instance.client.from('organizations')
      .select('id, name, slug, currency_code, created_at, logo_path, version, updated_at').order('created_at', ascending: false);
    return List<Map<String, dynamic>>.from(rows);
  }

  void _refresh() => setState(() => _committees = _loadCommittees());

  Future<void> _checkForUpdates() async {
    if (!mounted) return;
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
      final opened = await launchUrl(
        Uri.parse('https://github.com/sajjadhossan/SomityHub/releases/tag/desktop-latest'),
        mode: LaunchMode.externalApplication,
      );
      if (!opened && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Desktop download page খোলা যায়নি।')),
        );
      }
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('নতুন version খোঁজা হচ্ছে...')),
    );
    try {
      final response = await http.get(
        Uri.parse('https://api.github.com/repos/sajjadhossan/SomityHub/releases/tags/latest'),
        headers: const {'Accept': 'application/vnd.github+json'},
      ).timeout(const Duration(seconds: 20));
      if (response.statusCode != 200) {
        throw Exception('Update server response: ${response.statusCode}');
      }
      final release = jsonDecode(response.body) as Map<String, dynamic>;
      final releaseName = (release['name'] ?? '').toString();
      final versionMatch = RegExp(r'(\d+\.\d+\.\d+)').firstMatch(releaseName);
      if (versionMatch == null) {
        throw Exception('Latest release version পাওয়া যায়নি।');
      }
      final latestVersion = versionMatch.group(1)!;
      final current = await PackageInfo.fromPlatform();
      int compareVersions(String a, String b) {
        final left = a.split('.').map(int.parse).toList();
        final right = b.split('.').map(int.parse).toList();
        for (var i = 0; i < 3; i++) {
          final x = i < left.length ? left[i] : 0;
          final y = i < right.length ? right[i] : 0;
          if (x != y) return x.compareTo(y);
        }
        return 0;
      }
      if (!mounted) return;
      if (compareVersions(latestVersion, current.version) <= 0) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('আপনার অ্যাপ সর্বশেষ version ${current.version}-এ আছে।')),
        );
        return;
      }
      final assets = List<Map<String, dynamic>>.from(release['assets'] as List? ?? const []);
      final abiInfo = await DeviceInfoPlugin().androidInfo;
      if (!mounted) return;
      final supportedAbis = abiInfo.supportedAbis.toSet();
      const abiAssetNames = <String, String>{
        'arm64-v8a': 'SomityHub-arm64-v8a.apk',
        'armeabi-v7a': 'SomityHub-armeabi-v7a.apk',
        'x86_64': 'SomityHub-x86_64.apk',
      };
      final compatible = assets.where((asset) {
        final name = asset['name']?.toString();
        return abiAssetNames.entries.any((entry) =>
          supportedAbis.contains(entry.key) && entry.value == name);
      }).toList()
        ..sort((a, b) => (a['size'] as num? ?? 0).compareTo(b['size'] as num? ?? 0));
      final universal = assets.where((asset) => asset['name'] == 'SomityHub-latest.apk').toList();
      final choices = compatible.isNotEmpty ? compatible : universal;
      if (choices.isEmpty) throw Exception('এই ফোনের জন্য APK পাওয়া যায়নি।');
      Map<String, dynamic> selectedChoice = choices.first;
      final selectedAsset = await showDialog<Map<String, dynamic>>(
        context: context,
        builder: (dialogContext) => StatefulBuilder(builder: (context, setDialogState) {
          return AlertDialog(
            title: const Text('ফোনের উপযোগী APK বাছুন'),
            content: RadioGroup<Map<String, dynamic>>(
              groupValue: selectedChoice,
              onChanged: (asset) { if (asset != null) setDialogState(() => selectedChoice = asset); },
              child: Column(mainAxisSize: MainAxisSize.min, children: [
              for (var index = 0; index < choices.length; index++) ...[
                _ApkChoiceTile(
                  asset: choices[index],
                  recommended: index == 0,
                ),
              ],
              if (compatible.isEmpty)
                const Text('ABI মিলিয়ে APK পাওয়া যায়নি; Universal APK দেখানো হচ্ছে।'),
            ])),
            actions: [
              TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('পরে')),
              FilledButton(onPressed: () => Navigator.pop(dialogContext, selectedChoice), child: const Text('Download Update')),
            ],
          );
        }),
      );
      if (selectedAsset == null) return;
      final downloadUri = Uri.parse(selectedAsset['browser_download_url'].toString());
      final opened = await launchUrl(downloadUri, mode: LaunchMode.externalApplication);
      if (!opened && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Download link খোলা যায়নি।')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Update check করা যায়নি: $e')),
        );
      }
    }
  }

  Future<void> _createCommittee() async {
    final controller = TextEditingController();
    final formKey = GlobalKey<FormState>();
    final name = await showDialog<String>(context: context, builder: (ctx) => AlertDialog(
      title: const Text('নতুন সমিতি তৈরি করুন'),
      content: Form(key: formKey, child: TextFormField(controller: controller, autofocus: true,
        decoration: const InputDecoration(labelText: 'সমিতির নাম'),
        validator: (v) => v == null || v.trim().length < 2 ? 'কমপক্ষে ২ অক্ষরের নাম দিন।' : null)),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('বাতিল')),
        FilledButton(onPressed: () { if (formKey.currentState!.validate()) Navigator.pop(ctx, controller.text.trim()); }, child: const Text('তৈরি করুন')),
      ],
    ));
    controller.dispose();
    if (name == null || !mounted) return;
    // Keep the committee name exactly as entered (Bangla included).
    final asciiSlug = name.toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
        .replaceAll(RegExp(r'^-+|-+$'), '');
    final slug = asciiSlug.length >= 3
        ? asciiSlug
        : 'committee-${DateTime.now().microsecondsSinceEpoch}';
    try {
      final result = await Supabase.instance.client.rpc('create_committee',
        params: {'p_name': name, 'p_slug': slug});
      _refresh();
      if (!mounted) return;
      final row = result is List && result.isNotEmpty ? result.first : result;
      final code = row is Map ? row['owner_member_code'] : null;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(
        code == null ? 'সমিতি তৈরি হয়েছে।' : 'সমিতি তৈরি হয়েছে। আপনার Admin Member Code: $code')));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('সমিতি তৈরি করা যায়নি: $e')));
    }
  }

  Future<void> _signOut() async => Supabase.instance.client.auth.signOut();

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('SomityHub'), actions: [
      IconButton(onPressed: _refresh, icon: const Icon(Icons.refresh), tooltip: 'Refresh'),
      if (!kIsWeb) IconButton(onPressed: _checkForUpdates, icon: const Icon(Icons.system_update_alt), tooltip: 'Update check'),
      IconButton(onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(
        builder: (_) => const ProfilePage())), icon: const Icon(Icons.person_outline), tooltip: 'আমার Profile'),
      IconButton(onPressed: _signOut, icon: const Icon(Icons.logout), tooltip: 'Logout'),
    ]),
    floatingActionButton: FloatingActionButton.extended(onPressed: _createCommittee,
      icon: const Icon(Icons.add), label: const Text('নতুন সমিতি')),
    body: RefreshIndicator(onRefresh: () async => _refresh(),
      child: FutureBuilder<List<Map<String, dynamic>>>(future: _committees, builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
        if (snapshot.hasError) {
          return ListView(padding: const EdgeInsets.all(24),
            children: [Text('সমিতির তালিকা লোড করা যায়নি: ${snapshot.error}')]);
        }
        final items = snapshot.data ?? [];
        if (items.isEmpty) {
          return ListView(padding: const EdgeInsets.all(24), children: const [
            SizedBox(height: 90), Icon(Icons.groups_outlined, size: 64, color: Colors.grey),
            SizedBox(height: 16), Text('এখনো কোনো সমিতি নেই', textAlign: TextAlign.center, style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            SizedBox(height: 8), Text('নতুন সমিতি তৈরি করতে নিচের + বাটন ব্যবহার করুন।', textAlign: TextAlign.center),
          ]);
        }
        return ListView.separated(padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
          itemCount: items.length, separatorBuilder: (_, __) => const SizedBox(height: 10),
          itemBuilder: (context, index) {
            final item = items[index];
            final logoPath = item['logo_path']?.toString();
            final logoUrl = logoPath == null ? null : Supabase.instance.client.storage
                .from('committee-logos').getPublicUrl(logoPath);
            final version = item['version'] as num? ?? 1;
            return Card(child: ListTile(leading: CircleAvatar(
                backgroundImage: logoUrl == null ? null : NetworkImage('$logoUrl?v=$version'),
                child: logoUrl == null ? const Icon(Icons.groups) : null),
              title: Text(item['name']?.toString() ?? 'Unnamed committee'),
              subtitle: Text('${item['slug'] ?? ''} · ${item['currency_code'] ?? 'BDT'} · সংস্করণ $version'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () async {
                await Navigator.of(context).push(MaterialPageRoute<void>(
                builder: (_) => CommitteeWorkspacePage(
                  organizationId: item['id'].toString(),
                  committeeName: item['name']?.toString() ?? 'সমিতি',
                  logoPath: logoPath,
                  version: version.toInt(),
                ),
              ));
                _refresh();
              },
            ));
          });
      }),
    ),
  );
}

class _ApkChoiceTile extends StatelessWidget {
  const _ApkChoiceTile({required this.asset, required this.recommended});

  final Map<String, dynamic> asset;
  final bool recommended;

  @override
  Widget build(BuildContext context) {
    final bytes = (asset['size'] as num?)?.toInt() ?? 0;
    final megabytes = (bytes / (1024 * 1024)).toStringAsFixed(1);
    final name = asset['name']?.toString() ?? 'APK';
    final label = name.replaceAll('SomityHub-', '').replaceAll('.apk', '');
    return RadioListTile<Map<String, dynamic>>(
      value: asset,
      title: Text('$label · $megabytes MB${recommended ? ' · ছোটতম' : ''}'),
    );
  }
}


class CommitteeWorkspacePage extends StatefulWidget {
  const CommitteeWorkspacePage({
    super.key,
    required this.organizationId,
    required this.committeeName,
    required this.logoPath,
    required this.version,
  });

  final String organizationId;
  final String committeeName;
  final String? logoPath;
  final int version;

  @override
  State<CommitteeWorkspacePage> createState() => _CommitteeWorkspacePageState();
}

class _CommitteeWorkspacePageState extends State<CommitteeWorkspacePage> {
  late Future<List<Map<String, dynamic>>> _members;
  final _searchController = TextEditingController();
  String _statusFilter = 'all';
  String _currentUserId = '';
  String _currentRole = 'member';
  String _currentMembershipId = '';
  bool _canManageMembers = false;
  bool _isCommitteeAdmin = false;
  bool _savingMember = false;
  late String _committeeName;
  String? _committeeLogoPath;
  int _committeeVersion = 1;
  bool _savingCommittee = false;

  static const _committeeRoles = <(String, String)>[
    ('committee_admin', 'অ্যাডমিন'),
    ('manager', 'ম্যানেজার'),
    ('president', 'সভাপতি'),
    ('general_secretary', 'সাধারণ সম্পাদক'),
    ('assistant_secretary', 'সহকারী সম্পাদক'),
    ('accountant', 'হিসাবরক্ষক'),
    ('treasurer', 'কোষাধ্যক্ষ'),
    ('secretary', 'সেক্রেটারি'),
    ('auditor', 'অডিটর'),
    ('member', 'সাধারণ সদস্য'),
  ];

  String _roleLabel(Object? role) {
    for (final entry in _committeeRoles) {
      if (entry.$1 == role?.toString()) return entry.$2;
    }
    return 'সাধারণ সদস্য';
  }

  static const _membershipStatuses = <(String, String)>[
    ('active', 'সক্রিয়'),
    ('pending', 'অনুমোদনের অপেক্ষায়'),
    ('suspended', 'স্থগিত'),
    ('expired', 'মেয়াদোত্তীর্ণ'),
  ];

  String _membershipStatusLabel(Object? status) {
    for (final entry in _membershipStatuses) {
      if (entry.$1 == status?.toString()) return entry.$2;
    }
    return 'অজানা';
  }



  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _committeeName = widget.committeeName;
    _committeeLogoPath = widget.logoPath;
    _committeeVersion = widget.version;
    _members = _loadMembers();
  }

  Future<void> _openMemberCard(Map<String, dynamic> member) async {
    await Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => MemberIdCardPage(
        member: member,
        organizationId: widget.organizationId,
        committeeName: _committeeName,
        logoPath: _committeeLogoPath,
      ),
    ));
  }

  Future<void> _openMyMemberCard() async {
    try {
      final members = await _members;
      final member = members.firstWhere(
        (item) => item['id'].toString() == _currentMembershipId,
      );
      if (!mounted) return;
      await _openMemberCard(member);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('আপনার Member ID Card খোলা যায়নি: $e')),
        );
      }
    }
  }

  Future<void> _openQrScanner() async {
    if (!kIsWeb && (defaultTargetPlatform == TargetPlatform.windows ||
        defaultTargetPlatform == TargetPlatform.linux)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('QR Scanner এই Desktop platform-এ এখনো supported নয়।')),
      );
      return;
    }
    await Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => MemberQrVerificationPage(
        organizationId: widget.organizationId,
        scannerMembershipId: _currentMembershipId,
      ),
    ));
  }

  Future<void> _editCommittee() async {
    final name = TextEditingController(text: _committeeName);
    final formKey = GlobalKey<FormState>();
    PlatformFile? selectedLogo;
    final saved = await showDialog<bool>(context: context, builder: (dialogContext) => StatefulBuilder(
      builder: (context, setDialogState) => AlertDialog(
        title: const Text('সমিতির তথ্য সম্পাদনা'),
        content: Form(key: formKey, child: Column(mainAxisSize: MainAxisSize.min, children: [
          TextFormField(controller: name, decoration: const InputDecoration(labelText: 'সমিতির নাম'),
            validator: (value) => value == null || value.trim().length < 2 ? 'কমপক্ষে ২ অক্ষরের নাম দিন।' : null),
          const SizedBox(height: 12),
          if (selectedLogo?.bytes != null) CircleAvatar(radius: 32, backgroundImage: MemoryImage(selectedLogo!.bytes!)),
          OutlinedButton.icon(
            onPressed: () async {
              final result = await FilePicker.platform.pickFiles(type: FileType.image, allowMultiple: false, withData: true);
              if (result != null && result.files.isNotEmpty && context.mounted) {
                setDialogState(() => selectedLogo = result.files.first);
              }
            },
            icon: const Icon(Icons.image_outlined),
            label: Text(selectedLogo == null ? 'লোগো বাছুন (JPG/PNG/WebP)' : 'অন্য লোগো বাছুন'),
          ),
          const Text('লোগো সর্বোচ্চ ২ MB; JPG, PNG বা WebP।'),
        ])),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('বাতিল')),
          FilledButton(onPressed: () { if (formKey.currentState!.validate()) Navigator.pop(dialogContext, true); }, child: const Text('সংরক্ষণ')),
        ],
      ),
    ));
    if (saved != true || !mounted) { name.dispose(); return; }
    setState(() => _savingCommittee = true);
    try {
      String? newLogoPath = _committeeLogoPath;
      final bytes = selectedLogo?.bytes;
      if (selectedLogo != null) {
        if (bytes == null || bytes.isEmpty || bytes.length > 2 * 1024 * 1024) {
          throw Exception('লোগোটি পড়া যায়নি অথবা ২ MB-এর বেশি।');
        }
        final extension = (selectedLogo!.extension ?? '').toLowerCase();
        const mimeTypes = {'jpg': 'image/jpeg', 'jpeg': 'image/jpeg', 'png': 'image/png', 'webp': 'image/webp'};
        final mime = mimeTypes[extension];
        if (mime == null) throw Exception('JPG, PNG বা WebP ফাইল ব্যবহার করুন।');
        newLogoPath = '${widget.organizationId}/${DateTime.now().microsecondsSinceEpoch}.$extension';
        await Supabase.instance.client.storage.from('committee-logos').uploadBinary(
          newLogoPath, bytes, fileOptions: FileOptions(contentType: mime, upsert: false));
      }
      final updated = await Supabase.instance.client.from('organizations').update({
        'name': name.text.trim(), 'logo_path': newLogoPath,
      }).eq('id', widget.organizationId).select('version, logo_path').single();
      if (!mounted) return;
      setState(() {
        _committeeName = name.text.trim();
        _committeeLogoPath = updated['logo_path']?.toString();
        _committeeVersion = (updated['version'] as num).toInt();
      });
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('সমিতির তথ্য সংরক্ষিত · সংস্করণ $_committeeVersion')));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('সমিতির তথ্য সংরক্ষণ হয়নি: $e')));
    } finally {
      name.dispose();
      if (mounted) setState(() => _savingCommittee = false);
    }
  }

  Future<void> _showCommitteeHistory() async {
    try {
      final rows = await Supabase.instance.client.from('audit_log')
        .select('actor_id, before_data, after_data, created_at')
        .eq('organization_id', widget.organizationId)
        .eq('action', 'committee_profile_updated')
        .order('created_at', ascending: false)
        .limit(20);
      if (!mounted) return;
      final history = List<Map<String, dynamic>>.from(rows);
      await showDialog<void>(context: context, builder: (dialogContext) => AlertDialog(
        title: const Text('সমিতির পরিবর্তনের ইতিহাস'),
        content: SizedBox(width: 420, child: history.isEmpty
          ? const Text('এখনো কোনো নাম বা লোগো পরিবর্তন হয়নি।')
          : ListView.separated(shrinkWrap: true, itemCount: history.length,
            separatorBuilder: (_, __) => const Divider(),
            itemBuilder: (context, index) {
              final entry = history[index];
              final before = Map<String, dynamic>.from(entry['before_data'] as Map);
              final after = Map<String, dynamic>.from(entry['after_data'] as Map);
              final date = DateTime.parse(entry['created_at'].toString()).toLocal();
              final actor = entry['actor_id']?.toString() ?? '';
              return ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text('${before['name'] ?? ''} → ${after['name'] ?? ''}'),
                subtitle: Text('সংস্করণ ${before['version']} → ${after['version']}\n'
                  '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year} '
                  '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')} · '
                  'অ্যাকাউন্ট ${actor.length > 8 ? actor.substring(0, 8) : actor}'),
              );
            })),
        actions: [TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('বন্ধ'))],
      ));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('ইতিহাস লোড হয়নি: $e')));
    }
  }

  Future<List<Map<String, dynamic>>> _loadMembers() async {
    final client = Supabase.instance.client;
    final user = client.auth.currentUser;
    if (user == null) throw Exception('Login session পাওয়া যায়নি।');
    _currentUserId = user.id;

    final rows = await client.from('committee_memberships')
        .select('id, user_id, member_code, role, is_active, status, joined_at')
        .eq('organization_id', widget.organizationId)
        .order('joined_at', ascending: false);
    final members = List<Map<String, dynamic>>.from(rows);
    final actorRows = members.where((member) =>
        member['user_id'] == user.id && member['is_active'] == true).toList();
    if (actorRows.isEmpty) {
      throw Exception('এই account-টি এই সমিতির সদস্য নয়। Admin-এর কাছে account যোগ করতে বলুন।');
    }
    _currentMembershipId = actorRows.first['id'].toString();
    final role = actorRows.first['role']?.toString() ?? 'member';
    if (mounted) {
      setState(() {
        _isCommitteeAdmin = role == 'committee_admin';
        _currentRole = role;
        _canManageMembers = _isCommitteeAdmin || role == 'manager';
      });
    }

    final profileIds = members.map((member) => member['user_id'].toString()).toSet().toList();
    if (profileIds.isNotEmpty) {
      final profiles = await client.from('profiles').select('id, display_name').inFilter('id', profileIds);
      final names = {for (final row in profiles) row['id'].toString(): row['display_name']?.toString()};
      for (final member in members) {
        member['display_name'] = names[member['user_id'].toString()];
      }
    }

    final details = await client.from('member_details')
        .select('membership_id, phone, address, date_of_birth, emergency_contact, notes, photo_path')
        .eq('organization_id', widget.organizationId);
    final detailByMembership = <String, Map<String, dynamic>>{
      for (final row in details)
        row['membership_id'].toString(): Map<String, dynamic>.from(row),
    };
    for (final member in members) {
      final details = detailByMembership[member['id'].toString()];
      member['details'] = details;
      final photoPath = details?['photo_path']?.toString();
      if (photoPath != null && photoPath.isNotEmpty) {
        try {
          final signed = await client.storage.from('member-photos').createSignedUrl(photoPath, 3600);
          details!['photo_url'] = signed;
        } catch (_) {
          details!['photo_url'] = null;
        }
      }
    }
    return members;
  }

  void _refresh() => setState(() => _members = _loadMembers());

  Future<void> _editMemberDetails(Map<String, dynamic> member) async {
    final details = member['details'] as Map<String, dynamic>?;
    final phone = TextEditingController(text: details?['phone']?.toString() ?? '');
    final address = TextEditingController(text: details?['address']?.toString() ?? '');
    final dateOfBirth = TextEditingController(text: details?['date_of_birth']?.toString() ?? '');
    final emergencyContact = TextEditingController(text: details?['emergency_contact']?.toString() ?? '');
    final notes = TextEditingController(text: details?['notes']?.toString() ?? '');
    PlatformFile? selectedPhoto;
    final formKey = GlobalKey<FormState>();
    final saved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(builder: (dialogContext, setDialogState) => AlertDialog(
        title: Text('সদস্যের তথ্য · ${member['member_code'] ?? ''}'),
        content: Form(
          key: formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (details?['photo_url'] != null || selectedPhoto?.bytes != null)
                  CircleAvatar(
                    radius: 34,
                    backgroundImage: selectedPhoto?.bytes != null
                        ? MemoryImage(selectedPhoto!.bytes!)
                        : NetworkImage(details!['photo_url']!) as ImageProvider,
                  ),
                OutlinedButton.icon(
                  onPressed: () async {
                    final result = await FilePicker.platform.pickFiles(
                      type: FileType.image, allowMultiple: false, withData: true);
                    if (result != null && result.files.isNotEmpty && dialogContext.mounted) {
                      setDialogState(() => selectedPhoto = result.files.first);
                    }
                  },
                  icon: const Icon(Icons.add_a_photo_outlined),
                  label: Text(selectedPhoto == null ? 'সদস্যের ছবি বাছুন' : 'ছবি নির্বাচিত · অন্য ছবি বাছুন'),
                ),
                const Text('ছবি সর্বোচ্চ ২ MB; JPG, PNG বা WebP।'),
                TextFormField(
                  controller: phone,
                  keyboardType: TextInputType.phone,
                  decoration: const InputDecoration(labelText: 'মোবাইল (ঐচ্ছিক)'),
                  maxLength: 40,
                ),
                TextFormField(
                  controller: address,
                  decoration: const InputDecoration(labelText: 'ঠিকানা (ঐচ্ছিক)'),
                  maxLines: 3,
                  maxLength: 300,
                ),
                TextFormField(
                  controller: dateOfBirth,
                  decoration: const InputDecoration(labelText: 'জন্মতারিখ (YYYY-MM-DD, ঐচ্ছিক)'),
                  keyboardType: TextInputType.datetime,
                  validator: (value) {
                    final text = value?.trim() ?? '';
                    if (text.isEmpty) return null;
                    final match = RegExp(r'^([0-9]{4})-([0-9]{2})-([0-9]{2})$').firstMatch(text);
                    if (match == null) return 'YYYY-MM-DD ফরম্যাটে তারিখ দিন।';
                    final year = int.parse(match.group(1)!);
                    final month = int.parse(match.group(2)!);
                    final day = int.parse(match.group(3)!);
                    final parsed = DateTime(year, month, day);
                    return parsed.year == year && parsed.month == month && parsed.day == day
                        ? null : 'সঠিক তারিখ দিন।';
                  },
                  maxLength: 10,
                ),
                TextFormField(
                  controller: emergencyContact,
                  decoration: const InputDecoration(labelText: 'জরুরি যোগাযোগ (ঐচ্ছিক)'),
                  maxLength: 120,
                ),
                TextFormField(
                  controller: notes,
                  decoration: const InputDecoration(labelText: 'নোট (ঐচ্ছিক)'),
                  maxLines: 3,
                  maxLength: 1000,
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('বাতিল')),
          FilledButton(
            onPressed: () {
              if (formKey.currentState!.validate()) Navigator.pop(dialogContext, true);
            },
            child: const Text('সংরক্ষণ করুন'),
          ),
        ],
      )),
    );

    if (saved != true || !mounted) {
      phone.dispose();
      address.dispose();
      dateOfBirth.dispose();
      emergencyContact.dispose();
      notes.dispose();
      return;
    }

    try {
      final client = Supabase.instance.client;
      final values = {
        'phone': phone.text.trim().isEmpty ? null : phone.text.trim(),
        'address': address.text.trim().isEmpty ? null : address.text.trim(),
        'date_of_birth': dateOfBirth.text.trim().isEmpty ? null : dateOfBirth.text.trim(),
        'emergency_contact': emergencyContact.text.trim().isEmpty ? null : emergencyContact.text.trim(),
        'notes': notes.text.trim().isEmpty ? null : notes.text.trim(),
        'photo_path': details?['photo_path'],
      };
      if (selectedPhoto != null) {
        final bytes = selectedPhoto!.bytes;
        if (bytes == null || bytes.isEmpty || bytes.length > 2 * 1024 * 1024) {
          throw Exception('ছবিটি পড়া যায়নি অথবা ২ MB-এর বেশি।');
        }
        final extension = (selectedPhoto!.extension ?? '').toLowerCase();
        const mimeTypes = {'jpg': 'image/jpeg', 'jpeg': 'image/jpeg', 'png': 'image/png', 'webp': 'image/webp'};
        final mime = mimeTypes[extension];
        if (mime == null) throw Exception('JPG, PNG বা WebP ছবি ব্যবহার করুন।');
        final path = '${widget.organizationId}/${member['id']}/${DateTime.now().microsecondsSinceEpoch}.$extension';
        await client.storage.from('member-photos').uploadBinary(
          path, bytes, fileOptions: FileOptions(contentType: mime, upsert: false));
        values['photo_path'] = path;
      }
      final existing = member['details'] as Map<String, dynamic>?;
      if (existing == null) {
        await client.from('member_details').insert({
          'organization_id': widget.organizationId,
          'membership_id': member['id'],
          ...values,
        });
      } else {
        await client.from('member_details')
            .update(values)
            .eq('membership_id', member['id'])
            .eq('organization_id', widget.organizationId);
      }
      _refresh();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('সদস্যের তথ্য আপডেট হয়েছে।')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('সদস্যের তথ্য আপডেট করা যায়নি: $e')),
        );
      }
    } finally {
      phone.dispose();
      address.dispose();
      dateOfBirth.dispose();
      emergencyContact.dispose();
      notes.dispose();
    }
  }

  Future<void> _changeMemberRole(Map<String, dynamic> member) async {
    if (!_isCommitteeAdmin || member['user_id'] == _currentUserId) return;
    final newRole = await showDialog<String>(
      context: context,
      builder: (dialogContext) => SimpleDialog(
        title: Text('${member['display_name'] ?? member['member_code']} · পদ নির্বাচন করুন'),
        children: [
          for (final role in _committeeRoles)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(dialogContext, role.$1),
              child: Text(role.$2),
            ),
        ],
      ),
    );
    if (newRole == null || newRole == member['role'] || !mounted) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Role পরিবর্তন করবেন?'),
        content: Text('${member['display_name'] ?? member['member_code']}-এর পদ ${_roleLabel(member['role'])} থেকে ${_roleLabel(newRole)} করা হবে।'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('বাতিল')),
          FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('পরিবর্তন করুন')),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _savingMember = true);
    try {
      await Supabase.instance.client.rpc('admin_update_committee_member_role', params: {
        'p_organization_id': widget.organizationId,
        'p_membership_id': member['id'],
        'p_new_role': newRole,
      });
      _refresh();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('${member['display_name'] ?? member['member_code']}-এর পদ ${_roleLabel(newRole)} করা হয়েছে।'),
        ));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Role আপডেট করা যায়নি: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _savingMember = false);
    }
  }

  Future<void> _changeMemberStatus(Map<String, dynamic> member) async {
    if (!_canManageMembers || member['user_id'] == _currentUserId) return;
    final currentStatus = member['status']?.toString() ??
        (member['is_active'] == true ? 'active' : 'suspended');
    final selected = await showDialog<String>(
      context: context,
      builder: (dialogContext) => SimpleDialog(
        title: Text('${member['display_name'] ?? member['member_code']} · সদস্যের অবস্থা'),
        children: [
          for (final status in _membershipStatuses)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(dialogContext, status.$1),
              child: Text(status.$2),
            ),
        ],
      ),
    );
    if (selected == null || selected == currentStatus || !mounted) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('সদস্যের অবস্থা পরিবর্তন করবেন?'),
        content: Text('${member['display_name'] ?? member['member_code']}-এর অবস্থা ${_membershipStatusLabel(currentStatus)} থেকে ${_membershipStatusLabel(selected)} করা হবে।'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('বাতিল')),
          FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('পরিবর্তন করুন')),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _savingMember = true);
    try {
      await Supabase.instance.client.rpc('admin_update_committee_member_status', params: {
        'p_organization_id': widget.organizationId,
        'p_membership_id': member['id'],
        'p_new_status': selected,
      });
      _refresh();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('সদস্যের অবস্থা ${_membershipStatusLabel(selected)} করা হয়েছে।'),
        ));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('সদস্যের অবস্থা পরিবর্তন হয়নি: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _savingMember = false);
    }
  }

  Future<void> _openScanHistory() async {
    await Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => QrVerificationHistoryPage(organizationId: widget.organizationId),
    ));
  }

  Future<void> _addMember() async {
    final formKey = GlobalKey<FormState>();
    final email = TextEditingController();
    final phone = TextEditingController();
    final address = TextEditingController();
    var selectedRole = 'member';
    final accepted = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('সমিতিতে account যোগ করুন'),
        content: StatefulBuilder(builder: (context, setDialogState) => Form(
          key: formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('ব্যক্তিকে আগে SomityHub-এ account খুলে একবার login করতে বলুন। Registration-এর email দিন।'),
                const SizedBox(height: 12),
                TextFormField(
                  controller: email,
                  keyboardType: TextInputType.emailAddress,
                  decoration: const InputDecoration(labelText: 'Account-এর Email'),
                  validator: (value) {
                    final v = value?.trim() ?? '';
                    return v.contains('@') ? null : 'Registration-এ ব্যবহার করা email দিন।';
                  },
                ),
                if (_isCommitteeAdmin) ...[
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    initialValue: selectedRole,
                    decoration: const InputDecoration(labelText: 'সমিতির পদ'),
                    items: [for (final role in _committeeRoles) DropdownMenuItem(value: role.$1, child: Text(role.$2))],
                    onChanged: (value) => setDialogState(() => selectedRole = value ?? 'member'),
                  ),
                ],
                const SizedBox(height: 12),
                TextFormField(controller: phone, decoration: const InputDecoration(labelText: 'মোবাইল (ঐচ্ছিক)')),
                const SizedBox(height: 12),
                TextFormField(controller: address, decoration: const InputDecoration(labelText: 'ঠিকানা (ঐচ্ছিক)')),
              ],
            ),
          ),
        )),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('বাতিল')),
          FilledButton(
            onPressed: () {
              if (formKey.currentState!.validate()) {
                Navigator.pop(dialogContext, true);
              }
            },
            child: const Text('সদস্য যোগ করুন'),
          ),
        ],
      ),
    );

    if (accepted != true || !mounted) {
      email.dispose();
      phone.dispose();
      address.dispose();
      return;
    }

    try {
      final result = await Supabase.instance.client.rpc('add_committee_member_by_email', params: {
        'p_organization_id': widget.organizationId,
        'p_email': email.text.trim(),
        'p_role': _isCommitteeAdmin ? selectedRole : 'member',
        'p_phone': phone.text.trim().isEmpty ? null : phone.text.trim(),
        'p_address': address.text.trim().isEmpty ? null : address.text.trim(),
      });
      final row = result is List && result.isNotEmpty ? result.first : result;
      final code = row is Map ? row['member_code'] : null;
      _refresh();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(code == null ? 'সমিতিতে account যোগ হয়েছে।' : 'সমিতিতে account যোগ হয়েছে। Member Code: $code'),
        ));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('সদস্য যোগ করা যায়নি: $e'),
        ));
      }
    } finally {
      email.dispose();
      phone.dispose();
      address.dispose();
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Row(children: [
        if (_committeeLogoPath != null) ...[
          CircleAvatar(radius: 15, backgroundImage: NetworkImage(
            '${Supabase.instance.client.storage.from('committee-logos').getPublicUrl(_committeeLogoPath!)}?v=$_committeeVersion')),
          const SizedBox(width: 8),
        ],
        Flexible(child: Text(_committeeName)),
      ]),
      actions: [
        if (_isCommitteeAdmin) IconButton(onPressed: _showCommitteeHistory,
          icon: const Icon(Icons.history), tooltip: 'সমিতির পরিবর্তনের ইতিহাস'),
        if (_isCommitteeAdmin) IconButton(onPressed: _savingCommittee ? null : _editCommittee,
          icon: const Icon(Icons.edit_outlined), tooltip: 'সমিতির নাম ও লোগো সম্পাদনা'),
        IconButton(onPressed: _refresh, icon: const Icon(Icons.refresh), tooltip: 'Refresh'),
      ],
    ),
    floatingActionButton: null,
    body: FutureBuilder<List<Map<String, dynamic>>>(
      future: _members,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return ListView(
            padding: const EdgeInsets.all(20),
            children: [
              Text('সদস্য তালিকা লোড করা যায়নি: ${snapshot.error}'),
              const SizedBox(height: 8),
              const Text('আপনার committee manager permission এবং Membership SELECT policy যাচাই করুন।'),
            ],
          );
        }

        final allMembers = snapshot.data ?? [];
        final activeCount = allMembers.where((member) => member['status'] == 'active' || (member['status'] == null && member['is_active'] == true)).length;
        final query = _searchController.text.trim().toLowerCase();
        final members = allMembers.where((member) {
          final status = member['status']?.toString() ?? (member['is_active'] == true ? 'active' : 'suspended');
          if (_statusFilter != 'all' && status != _statusFilter) return false;
          if (query.isEmpty) return true;
          final details = member['details'] as Map<String, dynamic>?;
          final searchable = [
            member['display_name'], member['member_code'], _roleLabel(member['role']), details?['phone'], details?['address'],
            details?['date_of_birth'], details?['emergency_contact'], details?['notes'],
          ].map((value) => value?.toString().toLowerCase() ?? '').join(' ');
          return searchable.contains(query);
        }).toList();

        return RefreshIndicator(
          onRefresh: () async => _refresh(),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
            children: [
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(18),
                  child: Row(
                    children: [
                      const Icon(Icons.groups_outlined, size: 36),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('মোট সদস্য'),
                            Text(allMembers.length.toString(), style: const TextStyle(fontSize: 26, fontWeight: FontWeight.bold)),
                          ],
                        ),
                      ),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('সক্রিয় সদস্য'),
                            Text(activeCount.toString(), style: const TextStyle(fontSize: 26, fontWeight: FontWeight.bold)),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Card(child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(_isCommitteeAdmin ? Icons.admin_panel_settings : _canManageMembers ? Icons.manage_accounts : Icons.person_outline),
                    title: Text('এই সমিতিতে আপনার পদ: ${_roleLabel(_currentRole)}'),
                    subtitle: Text(_isCommitteeAdmin
                        ? 'আপনি account যোগ ও অন্য সদস্যের পদ নির্ধারণ করতে পারবেন।'
                        : _canManageMembers
                            ? 'আপনি সদস্য যোগ ও তথ্য পরিচালনা করতে পারবেন; পদ Admin নির্ধারণ করেন।'
                            : 'এই Member account-এ account যোগ বা পদ বদলের অনুমতি নেই। Admin account দিয়ে login করুন।'),
                  ),
                  if (_isCommitteeAdmin) ...[
                    const SizedBox(height: 8),
                    OutlinedButton.icon(
                      onPressed: _savingCommittee ? null : _editCommittee,
                      icon: const Icon(Icons.edit_outlined),
                      label: const Text('সমিতির নাম ও লোগো সম্পাদনা'),
                    ),
                  ],
                  OutlinedButton.icon(
                    onPressed: _openScanHistory,
                    icon: const Icon(Icons.history),
                    label: const Text('QR Scan History'),
                  ),
                  const SizedBox(height: 8),
                  FilledButton.icon(
                    onPressed: _openMyMemberCard,
                    icon: const Icon(Icons.badge_outlined),
                    label: const Text('আমার Member ID Card'),
                  ),
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    onPressed: _openQrScanner,
                    icon: const Icon(Icons.qr_code_scanner),
                    label: const Text('QR Code যাচাই করুন'),
                  ),
                  const SizedBox(height: 10),
                  if (_canManageMembers)
                    FilledButton.icon(
                      onPressed: _savingMember ? null : _addMember,
                      icon: const Icon(Icons.person_add_alt_1),
                      label: Text(_isCommitteeAdmin ? 'নিবন্ধিত account যোগ করুন' : 'সাধারণ সদস্য যোগ করুন'),
                    ),
                  const SizedBox(height: 10),
                  if (_canManageMembers) ...[
                    const SizedBox(height: 8),
                    OutlinedButton.icon(
                      onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(
                        builder: (_) => BranchManagementPage(organizationId: widget.organizationId),
                      )),
                      icon: const Icon(Icons.account_tree_outlined),
                      label: const Text('শাখা ব্যবস্থাপনা'),
                    ),
                    const SizedBox(height: 8),
                    OutlinedButton.icon(
                      onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(
                        builder: (_) => MultiBranchMemberAssignmentPage(organizationId: widget.organizationId),
                      )),
                      icon: const Icon(Icons.people_alt_outlined),
                      label: const Text('সদস্যের একাধিক শাখা নির্ধারণ'),
                    ),
                  ],
                  OutlinedButton.icon(
                    onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(
                      builder: (_) => FinancialWorkspacePage(
                        organizationId: widget.organizationId,
                        committeeName: _committeeName,
                        membershipId: _currentMembershipId,
                        role: _currentRole,
                      ),
                    )),
                    icon: const Icon(Icons.account_balance_wallet_outlined),
                    label: const Text('আর্থিক হিসাব ও লেনদেন'),
                  ),
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(
                      builder: (_) => CooperativeDocumentsPage(
                        organizationId: widget.organizationId,
                        role: _currentRole,
                      ),
                    )),
                    icon: const Icon(Icons.folder_copy_outlined),
                    label: const Text('সমিতির নথিপত্র'),
                  ),
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(
                      builder: (_) => CooperativeOperationsPage(
                        organizationId: widget.organizationId,
                        membershipId: _currentMembershipId,
                        role: _currentRole,
                      ),
                    )),
                    icon: const Icon(Icons.assignment_outlined),
                    label: const Text('ঋণ, ভাউচার, সভা ও রিপোর্ট'),
                  ),
                ]),
              )),
              const SizedBox(height: 12),
              const Text('সদস্যসংখ্যার কোনো সীমা নেই। Member Code সিস্টেম থেকে স্বয়ংক্রিয়ভাবে তৈরি হয়।',
                style: TextStyle(color: Colors.grey)),
              const SizedBox(height: 8),
              const Text('সদস্য তালিকা', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              TextField(
                controller: _searchController,
                decoration: InputDecoration(
                  labelText: 'সদস্য খুঁজুন',
                  hintText: 'নাম, Member Code, পদ, মোবাইল বা ঠিকানা',
                  prefixIcon: const Icon(Icons.search),
                  suffixIcon: _searchController.text.isEmpty ? null : IconButton(
                    tooltip: 'মুছে ফেলুন',
                    onPressed: () {
                      _searchController.clear();
                      setState(() {});
                    },
                    icon: const Icon(Icons.clear),
                  ),
                  border: const OutlineInputBorder(),
                ),
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                initialValue: _statusFilter,
                decoration: const InputDecoration(labelText: 'সদস্যের অবস্থা'),
                items: const [
                  DropdownMenuItem(value: 'all', child: Text('সব সদস্য')),
                  DropdownMenuItem(value: 'active', child: Text('সক্রিয়')),
                  DropdownMenuItem(value: 'pending', child: Text('অনুমোদনের অপেক্ষায়')),
                  DropdownMenuItem(value: 'suspended', child: Text('স্থগিত')),
                  DropdownMenuItem(value: 'expired', child: Text('মেয়াদোত্তীর্ণ')),
                ],
                onChanged: (value) => setState(() => _statusFilter = value ?? 'all'),
              ),
              const SizedBox(height: 8),
              if (allMembers.isEmpty)
                const Card(child: Padding(
                  padding: EdgeInsets.all(20),
                  child: Text('এখনো কোনো সদস্য যোগ করা হয়নি।'),
                ))
              else if (members.isEmpty)
                const Card(child: Padding(
                  padding: EdgeInsets.all(20),
                  child: Text('এই খোঁজ বা ফিল্টারে কোনো সদস্য পাওয়া যায়নি।'),
                )),
              for (final member in members)
                Card(child: ListTile(
                  onTap: () => _openMemberCard(member),
                  leading: CircleAvatar(
                    backgroundImage: (member['details']?['photo_url'] as String?)?.isNotEmpty == true
                        ? NetworkImage(member['details']['photo_url'].toString()) : null,
                    child: (member['details']?['photo_url'] as String?)?.isNotEmpty == true
                        ? null : Icon(member['role'] == 'committee_admin'
                        ? Icons.admin_panel_settings_outlined
                        : member['role'] == 'manager'
                            ? Icons.manage_accounts_outlined
                            : Icons.person_outline),
                  ),
                  title: Text(member['display_name']?.toString().isNotEmpty == true
                      ? member['display_name'].toString()
                      : member['member_code']?.toString() ?? 'সদস্য'),
                  subtitle: Text([
                    '${_roleLabel(member['role'])} · ${member['member_code'] ?? ''}',
                    _membershipStatusLabel(member['status'] ?? (member['is_active'] == true ? 'active' : 'suspended')),
                    if ((member['details']?['phone'] ?? '').toString().isNotEmpty)
                      member['details']['phone'].toString(),
                    if ((member['details']?['address'] ?? '').toString().isNotEmpty)
                      member['details']['address'].toString(),
                  ].join(' · ')),
                  trailing: _canManageMembers ? Row(mainAxisSize: MainAxisSize.min, children: [
                    if (_isCommitteeAdmin && member['user_id'] != _currentUserId)
                      IconButton.filledTonal(
                        tooltip: 'পদ পরিবর্তন',
                        onPressed: _savingMember ? null : () => _changeMemberRole(member),
                        icon: const Icon(Icons.badge_outlined),
                      ),
                    PopupMenuButton<String>(
                      tooltip: 'সদস্য পরিচালনা',
                      onSelected: (action) {
                        if (action == 'edit') _editMemberDetails(member);
                        if (action == 'status') _changeMemberStatus(member);
                      },
                      itemBuilder: (context) => [
                        PopupMenuItem(
                          value: 'edit',
                          enabled: !_savingMember,
                          child: const ListTile(
                            leading: Icon(Icons.edit_outlined),
                            title: Text('সদস্যের তথ্য ও ছবি সম্পাদনা'),
                            contentPadding: EdgeInsets.zero,
                          ),
                        ),
                        PopupMenuItem(
                          value: 'status',
                          enabled: !_savingMember && member['user_id'] != _currentUserId,
                          child: const ListTile(
                            leading: Icon(Icons.toggle_on_outlined),
                            title: Text('Membership Status পরিবর্তন'),
                            contentPadding: EdgeInsets.zero,
                          ),
                        ),
                      ],
                    ),
                  ]) : null,
                )),
            ],
          ),
        );
      },
    ),
  );
}


class MemberIdCardPage extends StatelessWidget {
  const MemberIdCardPage({
    super.key,
    required this.member,
    required this.organizationId,
    required this.committeeName,
    required this.logoPath,
  });

  final Map<String, dynamic> member;
  final String organizationId;
  final String committeeName;
  final String? logoPath;

  String get _roleLabel {
    const roles = <String, String>{
      'committee_admin': 'অ্যাডমিন',
      'manager': 'ম্যানেজার',
      'president': 'সভাপতি',
      'general_secretary': 'সাধারণ সম্পাদক',
      'assistant_secretary': 'সহকারী সম্পাদক',
      'accountant': 'হিসাবরক্ষক',
      'treasurer': 'কোষাধ্যক্ষ',
      'secretary': 'সেক্রেটারি',
      'auditor': 'অডিটর',
      'member': 'সাধারণ সদস্য',
    };
    return roles[member['role']?.toString()] ?? 'সাধারণ সদস্য';
  }

  @override
  Widget build(BuildContext context) {
    final memberId = member['id']?.toString() ?? '';
    final memberCode = member['member_code']?.toString() ?? '—';
    final displayName = member['display_name']?.toString().trim();
    final status = member['status']?.toString() ?? (member['is_active'] == true ? 'active' : 'suspended');
    final isActive = status == 'active';
    final details = member['details'] as Map<String, dynamic>?;
    final phone = details?['phone']?.toString() ?? '';
    final photoUrl = details?['photo_url']?.toString();
    final logoUrl = logoPath == null
        ? null
        : Supabase.instance.client.storage.from('committee-logos').getPublicUrl(logoPath!);
    final qrData = jsonEncode({
      'app': 'somityhub',
      'v': 1,
      'organization_id': organizationId,
      'membership_id': memberId,
    });

    return Scaffold(
      appBar: AppBar(title: const Text('Digital Member ID Card')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Card(
            clipBehavior: Clip.antiAlias,
            child: Column(
              children: [
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.fromLTRB(20, 24, 20, 22),
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      colors: [Color(0xFF0D5948), Color(0xFF16866A)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                  ),
                  child: Column(
                    children: [
                      if (logoUrl != null)
                        CircleAvatar(
                          radius: 30,
                          backgroundColor: Colors.white,
                          backgroundImage: NetworkImage(logoUrl),
                        )
                      else
                        const CircleAvatar(
                          radius: 30,
                          backgroundColor: Colors.white,
                          child: Icon(Icons.groups_rounded, size: 34, color: Color(0xFF126B55)),
                        ),
                      const SizedBox(height: 12),
                      const Text('SOMITYHUB MEMBER',
                        style: TextStyle(color: Colors.white70, letterSpacing: 1.5, fontWeight: FontWeight.w600)),
                      const SizedBox(height: 6),
                      Text(committeeName,
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    children: [
                      CircleAvatar(
                        radius: 42,
                        backgroundColor: const Color(0xFFE8F2EF),
                        backgroundImage: photoUrl == null || photoUrl.isEmpty ? null : NetworkImage(photoUrl),
                        child: photoUrl == null || photoUrl.isEmpty
                            ? const Icon(Icons.person, size: 44, color: Color(0xFF126B55)) : null,
                      ),
                      const SizedBox(height: 12),
                      Text(
                        displayName == null || displayName.isEmpty ? 'সদস্য' : displayName,
                        textAlign: TextAlign.center,
                        style: const TextStyle(fontSize: 21, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 4),
                      Text(_roleLabel, style: const TextStyle(color: Colors.black54)),
                      const SizedBox(height: 18),
                      _MemberIdField(label: 'MEMBER ID', value: memberCode),
                      if (phone.isNotEmpty) ...[
                        const SizedBox(height: 10),
                        _MemberIdField(label: 'MOBILE', value: phone),
                      ],
                      const SizedBox(height: 18),
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          border: Border.all(color: const Color(0xFFE1E8E5)),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: QrImageView(
                          data: qrData,
                          version: QrVersions.auto,
                          size: 176,
                          backgroundColor: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 8),
                      const Text('পরিচয় যাচাই করতে SomityHub অ্যাপ দিয়ে QR Code scan করুন।',
                        textAlign: TextAlign.center, style: TextStyle(color: Colors.black54, fontSize: 12)),
                      const SizedBox(height: 16),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        decoration: BoxDecoration(
                          color: isActive ? const Color(0xFFE5F4EC) : const Color(0xFFFCE8E6),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          status.toUpperCase().replaceAll('_', ' '),
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: isActive ? const Color(0xFF176B43) : const Color(0xFFB3261E),
                            fontWeight: FontWeight.bold,
                            letterSpacing: 1,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          const Text(
            'QR Code-এ শুধু committee ও membership reference থাকে। ব্যক্তিগত বা আর্থিক তথ্য QR-এর মধ্যে রাখা হয় না; যাচাইয়ের সময় server থেকে status দেখা হয়।',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.black54, fontSize: 12),
          ),
        ],
      ),
    );
  }
}

class _MemberIdField extends StatelessWidget {
  const _MemberIdField({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
    decoration: BoxDecoration(
      color: const Color(0xFFF5F7F6),
      borderRadius: BorderRadius.circular(8),
    ),
    child: Column(
      children: [
        Text(label, style: const TextStyle(fontSize: 10, color: Colors.black54, letterSpacing: 1)),
        const SizedBox(height: 3),
        Text(value, textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
      ],
    ),
  );
}

class MemberQrVerificationPage extends StatefulWidget {
  const MemberQrVerificationPage({
    super.key,
    required this.organizationId,
    required this.scannerMembershipId,
  });

  final String organizationId;
  final String scannerMembershipId;

  @override
  State<MemberQrVerificationPage> createState() => _MemberQrVerificationPageState();
}

class _MemberQrVerificationPageState extends State<MemberQrVerificationPage> {
  bool _processing = false;
  bool _completed = false;
  Map<String, dynamic>? _verifiedMember;
  String? _error;

  Future<void> _verifyCode(String rawValue) async {
    if (_processing || _completed) {
      return;
    }
    setState(() { _processing = true; _error = null; });
    try {
      Map<String, dynamic> payload;
      final scannedUri = Uri.tryParse(rawValue);
      if (scannedUri != null && scannedUri.scheme == 'somityhub' && scannedUri.host == 'verify') {
        payload = {
          'app': 'somityhub',
          'v': 1,
          'organization_id': scannedUri.queryParameters['organization_id'],
          'membership_id': scannedUri.queryParameters['membership_id'],
        };
      } else {
        final decoded = jsonDecode(rawValue);
        if (decoded is! Map) throw const FormatException('Invalid QR data');
        payload = Map<String, dynamic>.from(decoded);
      }
      if (payload['app'] != 'somityhub' || payload['v'] != 1 ||
          payload['organization_id'] is! String || payload['membership_id'] is! String) {
        throw const FormatException('Unsupported QR code');
      }
      if (payload['organization_id'] != widget.organizationId) {
        throw const FormatException('QR code belongs to another committee');
      }

      final client = Supabase.instance.client;
      final membership = await client.from('committee_memberships')
          .select('id, user_id, member_code, role, is_active, status, joined_at')
          .eq('organization_id', payload['organization_id'] as String)
          .eq('id', payload['membership_id'] as String)
          .maybeSingle();

      if (membership == null) {
        if (mounted) {
          setState(() {
            _completed = true;
            _error = 'এই Member ID পাওয়া যায়নি অথবা যাচাইয়ের অনুমতি নেই।';
          });
        }
        return;
      }

      await client.from('qr_verification_logs').insert({
        'organization_id': widget.organizationId,
        'membership_id': membership['id'],
        'scanned_by_membership_id': widget.scannerMembershipId,
      });
      final results = await Future.wait<dynamic>([
        client.from('profiles').select('display_name')
          .eq('id', membership['user_id'].toString()).maybeSingle(),
        client.from('organizations').select('name')
          .eq('id', payload['organization_id'] as String).maybeSingle(),
        client.from('member_details').select('photo_path')
          .eq('organization_id', widget.organizationId)
          .eq('membership_id', membership['id']).maybeSingle(),
      ]);
      final profile = results[0] as Map<String, dynamic>?;
      final organization = results[1] as Map<String, dynamic>?;
      final details = results[2] as Map<String, dynamic>?;
      String? photoUrl;
      final photoPath = details?['photo_path']?.toString();
      if (photoPath != null && photoPath.isNotEmpty) {
        try {
          photoUrl = await client.storage.from('member-photos').createSignedUrl(photoPath, 3600);
        } catch (_) {
          photoUrl = null;
        }
      }
      if (mounted) {
        setState(() {
          _completed = true;
          _verifiedMember = {
            ...membership,
            'display_name': profile?['display_name']?.toString() ?? 'সদস্য',
            'organization_name': organization?['name']?.toString() ?? 'সমিতি',
            'photo_url': photoUrl,
          };
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _completed = true;
          _error = 'QR Code সঠিক নয় অথবা server থেকে পরিচয় যাচাই করা যায়নি।';
        });
      }
    } finally {
      if (mounted) setState(() => _processing = false);
    }
  }

  void _scanAgain() {
    setState(() {
      _completed = false;
      _verifiedMember = null;
      _error = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final member = _verifiedMember;
    final status = member?['status']?.toString() ?? (member?['is_active'] == true ? 'active' : 'suspended');
    final isActive = status == 'active';
    return Scaffold(
      appBar: AppBar(title: const Text('Member QR Verification')),
      body: Column(
        children: [
          Expanded(
            child: _completed
                ? Center(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.all(24),
                      child: Card(
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                member == null ? Icons.error_outline :
                                  isActive ? Icons.verified_rounded : Icons.gpp_bad_outlined,
                                size: 64,
                                color: member == null ? Colors.red :
                                  isActive ? Colors.green : Colors.red,
                              ),
                              const SizedBox(height: 12),
                              Text(
                                member == null ? 'যাচাই করা যায়নি' :
                                  isActive ? 'পরিচয় যাচাই সফল' : 'সদস্য নিষ্ক্রিয়',
                                style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                              ),
                              if (_error != null) ...[
                                const SizedBox(height: 8),
                                Text(_error!, textAlign: TextAlign.center),
                              ],
                              if (member != null) ...[
                                const SizedBox(height: 16),
                                CircleAvatar(
                                  radius: 34,
                                  backgroundImage: (member['photo_url'] as String?)?.isNotEmpty == true
                                      ? NetworkImage(member['photo_url'].toString()) : null,
                                  child: (member['photo_url'] as String?)?.isNotEmpty == true
                                      ? null : const Icon(Icons.person, size: 36),
                                ),
                                const SizedBox(height: 10),
                                Text(member['display_name'].toString(),
                                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
                                Text('Member ID: ${member['member_code'] ?? '—'}'),
                                Text(member['organization_name'].toString()),
                                Text('Status: ${status.toUpperCase()}'),
                                if (!isActive)
                                  const Text('এই সদস্য বর্তমানে Active নন।', style: TextStyle(color: Colors.red, fontWeight: FontWeight.w600)),
                              ],
                              const SizedBox(height: 20),
                              FilledButton.icon(
                                onPressed: _scanAgain,
                                icon: const Icon(Icons.qr_code_scanner),
                                label: const Text('আরেকটি QR Scan করুন'),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  )
                : Stack(
                    fit: StackFit.expand,
                    children: [
                      MobileScanner(onDetect: (capture) {
                        if (capture.barcodes.isEmpty) return;
                        final value = capture.barcodes.first.rawValue;
                        if (value != null && value.isNotEmpty) _verifyCode(value);
                      }),
                      const Align(
                        alignment: Alignment.center,
                        child: SizedBox(
                          width: 250,
                          height: 250,
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              border: Border.fromBorderSide(BorderSide(color: Colors.white, width: 3)),
                              borderRadius: BorderRadius.all(Radius.circular(18)),
                            ),
                          ),
                        ),
                      ),
                      if (_processing)
                        const Align(
                          alignment: Alignment.bottomCenter,
                          child: Padding(
                            padding: EdgeInsets.all(24),
                            child: Card(child: Padding(
                              padding: EdgeInsets.all(12),
                              child: Row(mainAxisSize: MainAxisSize.min, children: [
                                SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
                                SizedBox(width: 12),
                                Text('পরিচয় যাচাই হচ্ছে...'),
                              ]),
                            )),
                          ),
                        ),
                    ],
                  ),
          ),
          const Padding(
            padding: EdgeInsets.all(16),
            child: Text('সদস্যের ID Card-এর QR Code ক্যামেরার সামনে ধরুন।',
              textAlign: TextAlign.center),
          ),
        ],
      ),
    );
  }
}

class QrVerificationHistoryPage extends StatefulWidget {
  const QrVerificationHistoryPage({super.key, required this.organizationId});

  final String organizationId;

  @override
  State<QrVerificationHistoryPage> createState() => _QrVerificationHistoryPageState();
}

class _QrVerificationHistoryPageState extends State<QrVerificationHistoryPage> {
  late Future<List<Map<String, dynamic>>> _history;

  @override
  void initState() {
    super.initState();
    _history = _loadHistory();
  }

  Future<List<Map<String, dynamic>>> _loadHistory() async {
    final client = Supabase.instance.client;
    final logs = await client.from('qr_verification_logs')
        .select('id, membership_id, scanned_by_membership_id, scanned_at')
        .eq('organization_id', widget.organizationId)
        .order('scanned_at', ascending: false)
        .limit(100);
    final rows = List<Map<String, dynamic>>.from(logs);
    if (rows.isEmpty) return rows;
    final ids = rows.expand((row) => [
      row['membership_id'].toString(),
      row['scanned_by_membership_id'].toString(),
    ]).toSet().toList();
    final memberships = await client.from('committee_memberships')
        .select('id, member_code, user_id')
        .eq('organization_id', widget.organizationId)
        .inFilter('id', ids);
    final membershipById = {
      for (final row in memberships) row['id'].toString(): Map<String, dynamic>.from(row),
    };
    final userIds = memberships.map((row) => row['user_id'].toString()).toSet().toList();
    final profiles = userIds.isEmpty ? <dynamic>[] :
      await client.from('profiles').select('id, display_name').inFilter('id', userIds);
    final names = {for (final row in profiles) row['id'].toString(): row['display_name']?.toString()};
    for (final row in rows) {
      final member = membershipById[row['membership_id'].toString()];
      final scanner = membershipById[row['scanned_by_membership_id'].toString()];
      row['member_code'] = member?['member_code'] ?? '—';
      row['member_name'] = names[member?['user_id']?.toString()] ?? 'সদস্য';
      row['scanner_code'] = scanner?['member_code'] ?? '—';
      row['scanner_name'] = names[scanner?['user_id']?.toString()] ?? 'সদস্য';
    }
    return rows;
  }

  String _date(Object? value) {
    final date = DateTime.parse(value.toString()).toLocal();
    return '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year} '
      '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('QR Verification History')),
    body: FutureBuilder<List<Map<String, dynamic>>>(
      future: _history,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return Center(child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text('Scan history লোড করা যায়নি: ${snapshot.error}'),
          ));
        }
        final rows = snapshot.data ?? [];
        if (rows.isEmpty) return const Center(child: Text('এখনো কোনো QR scan history নেই।'));
        return RefreshIndicator(
          onRefresh: () async => setState(() => _history = _loadHistory()),
          child: ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: rows.length,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (context, index) {
              final row = rows[index];
              return Card(child: ListTile(
                leading: const CircleAvatar(child: Icon(Icons.qr_code_scanner)),
                title: Text('${row['member_name']} · ${row['member_code']}'),
                subtitle: Text('Scan করেছেন: ${row['scanner_name']} · ${row['scanner_code']}\n${_date(row['scanned_at'])}'),
                isThreeLine: true,
              ));
            },
          ),
        );
      },
    ),
  );
}

class FinancialWorkspacePage extends StatefulWidget {
  const FinancialWorkspacePage({
    super.key,
    required this.organizationId,
    required this.committeeName,
    required this.membershipId,
    required this.role,
  });

  final String organizationId;
  final String committeeName;
  final String membershipId;
  final String role;

  @override
  State<FinancialWorkspacePage> createState() => _FinancialWorkspacePageState();
}

class _FinancialWorkspacePageState extends State<FinancialWorkspacePage> {
  bool _loading = true;
  bool _saving = false;
  num _balance = 0;
  List<Map<String, dynamic>> _ledger = [];
  List<Map<String, dynamic>> _pending = [];
  String? _error;

  bool get _canReview => widget.role == 'committee_admin' || widget.role == 'treasurer';
  bool get _canSeeCommitteeQueue =>
      const {'committee_admin', 'manager', 'treasurer', 'auditor'}.contains(widget.role);

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final client = Supabase.instance.client;
      final results = await Future.wait<dynamic>([
        client.rpc('get_member_balance', params: {
          'p_org_id': widget.organizationId,
          'p_membership_id': widget.membershipId,
        }),
        client.rpc('get_member_ledger', params: {
          'p_org_id': widget.organizationId,
          'p_membership_id': widget.membershipId,
          'p_limit': 100,
          'p_before': null,
        }),
      ]);
      final ledgerRows = List<Map<String, dynamic>>.from(results[1] as List);
      var pendingQuery = client.from('financial_transactions')
          .select('id, membership_id, transaction_type, amount, description, reference_number, status, created_at')
          .eq('organization_id', widget.organizationId)
          .eq('status', 'pending');
      if (!_canSeeCommitteeQueue) {
        pendingQuery = pendingQuery.eq('membership_id', widget.membershipId);
      }
      final pendingRows = await pendingQuery.order('created_at', ascending: false).limit(100);
      if (!mounted) return;
      setState(() {
        _balance = results[0] as num? ?? 0;
        _ledger = ledgerRows;
        _pending = List<Map<String, dynamic>>.from(pendingRows);
      });
    } catch (e) {
      if (mounted) setState(() => _error = 'আর্থিক তথ্য লোড করা যায়নি: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _money(Object? value) {
    final amount = num.tryParse(value?.toString() ?? '') ?? 0;
    return '৳ ${amount.toStringAsFixed(2)}';
  }

  String _typeLabel(Object? type) {
    switch (type?.toString()) {
      case 'deposit': return 'জমা';
      case 'withdrawal': return 'উত্তোলন';
      default: return type?.toString() ?? 'লেনদেন';
    }
  }

  String _statusLabel(Object? status) {
    switch (status?.toString()) {
      case 'pending': return 'অনুমোদনের অপেক্ষায়';
      case 'approved': return 'অনুমোদিত';
      case 'rejected': return 'বাতিল';
      default: return status?.toString() ?? '';
    }
  }

  String _newUuid() {
    final random = math.Random.secure();
    final bytes = List<int>.generate(16, (_) => random.nextInt(256));
    bytes[6] = (bytes[6] & 0x0f) | 0x40;
    bytes[8] = (bytes[8] & 0x3f) | 0x80;
    final hex = bytes.map((value) => value.toRadixString(16).padLeft(2, '0')).join();
    return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
  }

  Future<void> _submitRequest(String type) async {
    final formKey = GlobalKey<FormState>();
    final amount = TextEditingController();
    final description = TextEditingController();
    final accepted = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(type == 'deposit' ? 'জমার অনুরোধ' : 'উত্তোলনের অনুরোধ'),
        content: Form(
          key: formKey,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            TextFormField(
              controller: amount,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(labelText: 'পরিমাণ (BDT)'),
              validator: (value) {
                final parsed = num.tryParse((value ?? '').trim());
                return parsed == null || !parsed.isFinite || parsed <= 0
                    ? 'সঠিক পরিমাণ লিখুন।' : null;
              },
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: description,
              maxLength: 300,
              maxLines: 2,
              decoration: const InputDecoration(labelText: 'বিবরণ (ঐচ্ছিক)'),
            ),
            if (type == 'deposit') ...[
              const SizedBox(height: 8),
              const Text('জমা অনুমোদনের আগে ব্যাংক/ক্যাশ জমার প্রমাণ যাচাই প্রয়োজন হতে পারে।',
                style: TextStyle(color: Colors.black54)),
            ],
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('বাতিল')),
          FilledButton(onPressed: () {
            if (formKey.currentState!.validate()) Navigator.pop(dialogContext, true);
          }, child: const Text('অনুরোধ পাঠান')),
        ],
      ),
    );
    if (accepted != true || !mounted) {
      amount.dispose();
      description.dispose();
      return;
    }
    setState(() => _saving = true);
    try {
      await Supabase.instance.client.rpc('submit_financial_request', params: {
        'p_org_id': widget.organizationId,
        'p_membership_id': widget.membershipId,
        'p_transaction_type': type,
        'p_amount': num.parse(amount.text.trim()),
        'p_description': description.text.trim().isEmpty ? null : description.text.trim(),
        'p_reference_number': null,
        'p_idempotency_key': _newUuid(),
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('লেনদেনের অনুরোধ জমা হয়েছে। অনুমোদনের আগে ব্যালেন্সে যোগ হবে না।')),
        );
      }
      await _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('অনুরোধ জমা হয়নি: $e')),
        );
      }
    } finally {
      amount.dispose();
      description.dispose();
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _review(Map<String, dynamic> transaction, String decision) async {
    if (!_canReview) return;
    final note = TextEditingController();
    final accepted = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(decision == 'approved' ? 'লেনদেন অনুমোদন' : 'লেনদেন বাতিল'),
        content: TextField(
          controller: note,
          maxLength: 500,
          maxLines: 3,
          decoration: const InputDecoration(labelText: 'মন্তব্য (ঐচ্ছিক)'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('ফিরে যান')),
          FilledButton(onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(decision == 'approved' ? 'অনুমোদন করুন' : 'বাতিল করুন')),
        ],
      ),
    );
    if (accepted != true || !mounted) { note.dispose(); return; }
    setState(() => _saving = true);
    try {
      await Supabase.instance.client.rpc('review_financial_request', params: {
        'p_transaction_id': transaction['id'],
        'p_decision': decision,
        'p_note': note.text.trim().isEmpty ? null : note.text.trim(),
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(decision == 'approved' ? 'লেনদেন অনুমোদিত হয়েছে।' : 'লেনদেন বাতিল হয়েছে।')),
        );
      }
      await _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Review সম্পন্ন হয়নি: $e')),
        );
      }
    } finally {
      note.dispose();
      if (mounted) setState(() => _saving = false);
    }
  }

  String _date(Object? value) {
    if (value == null) return '';
    final date = DateTime.tryParse(value.toString())?.toLocal();
    if (date == null) return value.toString();
    return '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}';
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('আর্থিক হিসাব'),
      actions: [IconButton(onPressed: _loading ? null : _load,
        icon: const Icon(Icons.refresh), tooltip: 'Refresh')],
    ),
    body: _loading
      ? const Center(child: CircularProgressIndicator())
      : _error != null
        ? ListView(padding: const EdgeInsets.all(20), children: [
            Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
            const SizedBox(height: 12),
            OutlinedButton.icon(onPressed: _load, icon: const Icon(Icons.refresh), label: const Text('আবার চেষ্টা করুন')),
          ])
        : RefreshIndicator(
            onRefresh: _load,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
              children: [
                Card(child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(widget.committeeName, style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 8),
                    const Text('আপনার বর্তমান অনুমোদিত ব্যালেন্স'),
                    Text(_money(_balance), style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                      fontWeight: FontWeight.bold, color: const Color(0xFF126B55))),
                  ]),
                )),
                const SizedBox(height: 12),
                Row(children: [
                  Expanded(child: FilledButton.icon(
                    onPressed: _saving ? null : () => _submitRequest('deposit'),
                    icon: const Icon(Icons.add_circle_outline), label: const Text('জমার অনুরোধ'))),
                  const SizedBox(width: 10),
                  Expanded(child: OutlinedButton.icon(
                    onPressed: _saving ? null : () => _submitRequest('withdrawal'),
                    icon: const Icon(Icons.outbox_outlined), label: const Text('উত্তোলন'))),
                ]),
                if (_saving) const LinearProgressIndicator(),
                const SizedBox(height: 20),
                Text('অনুমোদনের অপেক্ষায়', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 8),
                if (_pending.isEmpty)
                  const Card(child: Padding(padding: EdgeInsets.all(16), child: Text('কোনো pending অনুরোধ নেই।')))
                else
                  for (final item in _pending)
                    Card(child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Row(children: [
                          Expanded(child: Text(_typeLabel(item['transaction_type']),
                            style: const TextStyle(fontWeight: FontWeight.bold))),
                          Text(_money(item['amount']), style: const TextStyle(fontWeight: FontWeight.bold)),
                        ]),
                        if ((item['description'] ?? '').toString().isNotEmpty)
                          Text(item['description'].toString()),
                        Text('${_date(item['created_at'])} · ${_statusLabel(item['status'])}',
                          style: const TextStyle(color: Colors.black54)),
                        if (_canReview) ...[
                          const SizedBox(height: 8),
                          Wrap(spacing: 8, children: [
                            FilledButton.tonal(onPressed: _saving ? null : () => _review(item, 'approved'),
                              child: const Text('অনুমোদন')),
                            OutlinedButton(onPressed: _saving ? null : () => _review(item, 'rejected'),
                              child: const Text('বাতিল')),
                          ]),
                        ],
                      ]),
                    )),
                const SizedBox(height: 20),
                Text('লেনদেনের হিসাব', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 8),
                if (_ledger.isEmpty)
                  const Card(child: Padding(padding: EdgeInsets.all(16), child: Text('এখনো কোনো অনুমোদিত লেনদেন নেই।')))
                else
                  for (final item in _ledger)
                    Card(child: ListTile(
                      leading: Icon(
                        (num.tryParse(item['signed_amount']?.toString() ?? '') ?? 0) >= 0
                          ? Icons.south_west : Icons.north_east,
                        color: (num.tryParse(item['signed_amount']?.toString() ?? '') ?? 0) >= 0
                          ? Colors.green : Colors.red,
                      ),
                      title: Text(_typeLabel(item['transaction_type'])),
                      subtitle: Text(_date(item['transaction_date'])),
                      trailing: Text(_money(item['signed_amount']),
                        style: const TextStyle(fontWeight: FontWeight.bold)),
                    )),
                const SizedBox(height: 8),
                const Text('Pending অনুরোধ অনুমোদিত না হওয়া পর্যন্ত ব্যালেন্স পরিবর্তিত হয় না। জমা অনুমোদনের জন্য যাচাইকৃত evidence প্রয়োজন।',
                  style: TextStyle(color: Colors.black54)),
              ],
            ),
          ),
  );
}


class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key});
  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  final _name = TextEditingController();
  String _language = 'bn';
  String _email = '';
  bool _loading = true;
  bool _saving = false;
  String? _error;
  String? _message;

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _loadProfile() async {
    try {
      final client = Supabase.instance.client;
      final user = client.auth.currentUser;
      if (user == null) throw Exception('Login session পাওয়া যায়নি।');
      _email = user.email ?? '';
      final row = await client.from('profiles')
        .select('display_name, preferred_language')
        .eq('id', user.id).maybeSingle();
      if (row == null) throw Exception('আপনার Profile record পাওয়া যায়নি।');
      _name.text = (row['display_name'] ?? '').toString();
      _language = row['preferred_language'] == 'en' ? 'en' : 'bn';
    } catch (e) {
      _error = 'Profile load করা যায়নি: $e';
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _saveProfile() async {
    final name = _name.text.trim();
    if (name.length < 2) {
      setState(() => _error = 'নাম কমপক্ষে ২ অক্ষরের হতে হবে।');
      return;
    }
    setState(() { _saving = true; _error = null; _message = null; });
    try {
      final user = Supabase.instance.client.auth.currentUser;
      if (user == null) throw Exception('Login session পাওয়া যায়নি।');
      await Supabase.instance.client.from('profiles').update({
        'display_name': name,
        'preferred_language': _language,
      }).eq('id', user.id);
      if (mounted) setState(() => _message = 'Profile সফলভাবে আপডেট হয়েছে।');
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('আমার Profile')),
    body: SafeArea(child: _loading
      ? const Center(child: CircularProgressIndicator())
      : ListView(padding: const EdgeInsets.all(20), children: [
          Card(child: Padding(padding: const EdgeInsets.all(20), child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              const Icon(Icons.account_circle_outlined, size: 64),
              const SizedBox(height: 16),
              TextFormField(initialValue: _email, readOnly: true,
                decoration: const InputDecoration(labelText: 'Email Address')),
              const SizedBox(height: 16),
              TextField(controller: _name, maxLength: 120,
                decoration: const InputDecoration(labelText: 'পূর্ণ নাম')),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                initialValue: _language,
                decoration: const InputDecoration(labelText: 'Interface Language'),
                items: const [
                  DropdownMenuItem(value: 'bn', child: Text('বাংলা')),
                  DropdownMenuItem(value: 'en', child: Text('English')),
                ],
                onChanged: _saving ? null : (value) {
                  if (value != null) setState(() => _language = value);
                },
              ),
              const SizedBox(height: 16),
              FilledButton(onPressed: _saving ? null : _saveProfile,
                child: _saving ? const CircularProgressIndicator() : const Text('Profile সংরক্ষণ করুন')),
              if (_message != null) ...[
                const SizedBox(height: 12),
                Text(_message!, style: const TextStyle(color: Colors.green)),
              ],
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
              ],
            ],
          ))),
        ])),
  );
}


class BranchManagementPage extends StatefulWidget {
  const BranchManagementPage({super.key, required this.organizationId});
  final String organizationId;

  @override
  State<BranchManagementPage> createState() => _BranchManagementPageState();
}

class _BranchManagementPageState extends State<BranchManagementPage> {
  late Future<List<Map<String, dynamic>>> _branches;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _branches = _loadBranches();
  }

  Future<List<Map<String, dynamic>>> _loadBranches() async {
    final rows = await Supabase.instance.client.from('organization_branches')
      .select('id, branch_code, name, address, phone, is_default, is_active, created_at')
      .eq('organization_id', widget.organizationId)
      .order('is_default', ascending: false)
      .order('name');
    return List<Map<String, dynamic>>.from(rows);
  }

  void _refresh() => setState(() => _branches = _loadBranches());

  Future<void> _createBranch() async {
    final formKey = GlobalKey<FormState>();
    final code = TextEditingController();
    final name = TextEditingController();
    final address = TextEditingController();
    final phone = TextEditingController();
    final accepted = await showDialog<bool>(context: context, builder: (dialogContext) => AlertDialog(
      title: const Text('নতুন শাখা তৈরি করুন'),
      content: Form(key: formKey, child: SingleChildScrollView(child: Column(
        mainAxisSize: MainAxisSize.min, children: [
          TextFormField(controller: code, textCapitalization: TextCapitalization.characters,
            decoration: const InputDecoration(labelText: 'Branch Code'),
            validator: (v) => v == null || v.trim().isEmpty || v.trim().length > 32 ? '১–৩২ অক্ষরের code দিন।' : null),
          const SizedBox(height: 12),
          TextFormField(controller: name, decoration: const InputDecoration(labelText: 'শাখার নাম'),
            validator: (v) => v == null || v.trim().length < 2 || v.trim().length > 120 ? '২–১২০ অক্ষরের নাম দিন।' : null),
          const SizedBox(height: 12),
          TextFormField(controller: address, decoration: const InputDecoration(labelText: 'ঠিকানা (ঐচ্ছিক)')),
          const SizedBox(height: 12),
          TextFormField(controller: phone, keyboardType: TextInputType.phone,
            decoration: const InputDecoration(labelText: 'ফোন (ঐচ্ছিক)')),
        ],
      ))),
      actions: [
        TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('বাতিল')),
        FilledButton(onPressed: () { if (formKey.currentState!.validate()) Navigator.pop(dialogContext, true); },
          child: const Text('তৈরি করুন')),
      ],
    ));
    if (accepted != true || !mounted) {
      code.dispose(); name.dispose(); address.dispose(); phone.dispose();
      return;
    }
    setState(() => _saving = true);
    try {
      final userId = Supabase.instance.client.auth.currentUser?.id;
      if (userId == null) throw Exception('Login session পাওয়া যায়নি।');
      await Supabase.instance.client.from('organization_branches').insert({
        'organization_id': widget.organizationId,
        'branch_code': code.text.trim().toUpperCase(),
        'name': name.text.trim(),
        'address': address.text.trim().isEmpty ? null : address.text.trim(),
        'phone': phone.text.trim().isEmpty ? null : phone.text.trim(),
        'created_by': userId,
      });
      _refresh();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('নতুন শাখা তৈরি হয়েছে।')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('শাখা তৈরি করা যায়নি: $e')),
        );
      }
    } finally {
      code.dispose(); name.dispose(); address.dispose(); phone.dispose();
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _setActive(Map<String, dynamic> branch, bool active) async {
    if (branch['is_default'] == true && !active) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Default branch নিষ্ক্রিয় করা যাবে না।')),
      );
      return;
    }
    setState(() => _saving = true);
    try {
      await Supabase.instance.client.from('organization_branches')
        .update({'is_active': active, 'updated_at': DateTime.now().toUtc().toIso8601String()})
        .eq('organization_id', widget.organizationId).eq('id', branch['id']);
      _refresh();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('শাখার অবস্থা পরিবর্তন হয়নি: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('শাখা ব্যবস্থাপনা'), actions: [
      IconButton(onPressed: _refresh, icon: const Icon(Icons.refresh)),
    ]),
    floatingActionButton: FloatingActionButton.extended(
      onPressed: _saving ? null : _createBranch,
      icon: const Icon(Icons.add), label: const Text('নতুন শাখা'),
    ),
    body: FutureBuilder<List<Map<String, dynamic>>>(
      future: _branches,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return Center(child: Padding(padding: const EdgeInsets.all(20),
            child: Text('শাখার তালিকা লোড হয়নি: ${snapshot.error}')));
        }
        final branches = snapshot.data ?? [];
        return ListView(padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
          children: [
            const Text('সমিতির শাখাগুলো এখানে দেখা ও পরিচালনা করা যাবে। Default branch বিদ্যমান financial records-এর ধারাবাহিকতা রক্ষা করে।'),
            const SizedBox(height: 12),
            if (branches.isEmpty) const Card(child: Padding(
              padding: EdgeInsets.all(16), child: Text('কোনো শাখা পাওয়া যায়নি।'))),
            for (final branch in branches)
              Card(child: ListTile(
                leading: CircleAvatar(child: Icon(branch['is_default'] == true
                  ? Icons.home_work_outlined : Icons.account_tree_outlined)),
                title: Text(branch['name']?.toString() ?? 'শাখা'),
                subtitle: Text('${branch['branch_code']} · ${branch['is_default'] == true ? 'Default' : 'Additional'} · ${branch['is_active'] == true ? 'সক্রিয়' : 'নিষ্ক্রিয়'}${(branch['address'] ?? '').toString().isEmpty ? '' : '\\n${branch['address']}'}'),
                trailing: branch['is_default'] == true ? const Chip(label: Text('Default'))
                  : Switch(value: branch['is_active'] == true, onChanged: _saving ? null
                    : (value) => _setActive(branch, value)),
              )),
          ],
        );
      },
    ),
  );
}


class BranchMemberAssignmentPage extends StatefulWidget {
  const BranchMemberAssignmentPage({super.key, required this.organizationId});
  final String organizationId;

  @override
  State<BranchMemberAssignmentPage> createState() => _BranchMemberAssignmentPageState();
}

class _BranchMemberAssignmentPageState extends State<BranchMemberAssignmentPage> {
  List<Map<String, dynamic>> _branches = [];
  List<Map<String, dynamic>> _members = [];
  String? _branchId;
  String? _membershipId;
  bool _loading = true;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final client = Supabase.instance.client;
      final branchRows = await client.from('organization_branches')
        .select('id, name, branch_code, is_active')
        .eq('organization_id', widget.organizationId)
        .eq('is_active', true).order('name');
      final memberRows = await client.from('committee_memberships')
        .select('id, user_id, member_code, role')
        .eq('organization_id', widget.organizationId)
        .eq('is_active', true).order('member_code');
      final profiles = memberRows.isEmpty ? [] : await client.from('profiles')
        .select('id, display_name')
        .inFilter('id', memberRows.map((m) => m['user_id'].toString()).toList());
      final names = {for (final p in profiles) p['id'].toString(): p['display_name']?.toString()};
      final branches = List<Map<String, dynamic>>.from(branchRows);
      final members = List<Map<String, dynamic>>.from(memberRows);
      for (final member in members) {
        member['display_name'] = names[member['user_id'].toString()];
      }
      if (!mounted) return;
      setState(() {
        _branches = branches;
        _members = members;
        _branchId = branches.any((b) => b['id'] == _branchId) ? _branchId : (branches.isEmpty ? null : branches.first['id'].toString());
        _membershipId = members.any((m) => m['id'] == _membershipId) ? _membershipId : (members.isEmpty ? null : members.first['id'].toString());
      });
    } catch (e) {
      if (mounted) setState(() => _error = 'তথ্য লোড করা যায়নি: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _assign() async {
    if (_branchId == null || _membershipId == null) return;
    setState(() => _saving = true);
    try {
      await Supabase.instance.client.rpc('set_member_primary_branch', params: {
        'p_organization_id': widget.organizationId,
        'p_membership_id': _membershipId,
        'p_branch_id': _branchId,
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('সদস্যের primary branch আপডেট হয়েছে।')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Branch assignment পরিবর্তন হয়নি: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('সদস্যের শাখা নির্ধারণ'), actions: [
      IconButton(onPressed: _loading ? null : _load, icon: const Icon(Icons.refresh)),
    ]),
    body: _loading ? const Center(child: CircularProgressIndicator())
      : _error != null ? Center(child: Padding(padding: const EdgeInsets.all(20), child: Text(_error!)))
      : ListView(padding: const EdgeInsets.all(20), children: [
          const Text('একজন active সদস্যের primary branch নির্বাচন করুন। পরিবর্তনটি database transaction-এর মাধ্যমে atomic ভাবে সংরক্ষিত হবে।'),
          const SizedBox(height: 16),
          if (_members.isEmpty || _branches.isEmpty)
            const Card(child: Padding(padding: EdgeInsets.all(16), child: Text('সদস্য বা active branch পাওয়া যায়নি।')))
          else ...[
            DropdownButtonFormField<String>(
              initialValue: _membershipId,
              decoration: const InputDecoration(labelText: 'সদস্য'),
              items: [for (final m in _members) DropdownMenuItem(
                value: m['id'].toString(),
                child: Text('${m['display_name'] ?? m['member_code']} · ${m['member_code']}'),
              )],
              onChanged: _saving ? null : (v) => setState(() => _membershipId = v),
            ),
            const SizedBox(height: 14),
            DropdownButtonFormField<String>(
              initialValue: _branchId,
              decoration: const InputDecoration(labelText: 'Primary branch'),
              items: [for (final b in _branches) DropdownMenuItem(
                value: b['id'].toString(),
                child: Text('${b['name']} · ${b['branch_code']}'),
              )],
              onChanged: _saving ? null : (v) => setState(() => _branchId = v),
            ),
            const SizedBox(height: 18),
            FilledButton.icon(
              onPressed: _saving ? null : _assign,
              icon: const Icon(Icons.save_outlined),
              label: Text(_saving ? 'সংরক্ষণ হচ্ছে...' : 'Primary branch সংরক্ষণ'),
            ),
          ],
        ]),
  );
}
