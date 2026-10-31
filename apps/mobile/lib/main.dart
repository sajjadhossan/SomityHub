import 'dart:convert';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';
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
      .select('id, name, slug, currency_code, created_at').order('created_at', ascending: false);
    return List<Map<String, dynamic>>.from(rows);
  }

  void _refresh() => setState(() => _committees = _loadCommittees());

  Future<void> _checkForUpdates() async {
    if (!mounted) return;
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
      final downloadUri = Uri.parse(
        'https://github.com/sajjadhossan/SomityHub/releases/latest/download/SomityHub-latest.apk',
      );
      final install = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('নতুন Update পাওয়া গেছে'),
          content: Text('বর্তমান version: ${current.version}\nনতুন version: $latestVersion\n\nAPK download করে Android-এর installer থেকে update করুন। আপনার app data সাধারণত অক্ষত থাকবে।'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('পরে')),
            FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('Download Update')),
          ],
        ),
      );
      if (install == true) {
        final opened = await launchUrl(downloadUri, mode: LaunchMode.externalApplication);
        if (!opened && mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Download link খোলা যায়নি।')),
          );
        }
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
            return Card(child: ListTile(leading: const CircleAvatar(child: Icon(Icons.groups)),
              title: Text(item['name']?.toString() ?? 'Unnamed committee'),
              subtitle: Text('${item['slug'] ?? ''} · ${item['currency_code'] ?? 'BDT'}'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(
                builder: (_) => CommitteeWorkspacePage(
                  organizationId: item['id'].toString(),
                  committeeName: item['name']?.toString() ?? 'সমিতি',
                ),
              )),
            ));
          });
      }),
    ),
  );
}


class CommitteeWorkspacePage extends StatefulWidget {
  const CommitteeWorkspacePage({
    super.key,
    required this.organizationId,
    required this.committeeName,
  });

  final String organizationId;
  final String committeeName;

  @override
  State<CommitteeWorkspacePage> createState() => _CommitteeWorkspacePageState();
}

class _CommitteeWorkspacePageState extends State<CommitteeWorkspacePage> {
  late Future<List<Map<String, dynamic>>> _members;

  @override
  void initState() {
    super.initState();
    _members = _loadMembers();
  }

  Future<List<Map<String, dynamic>>> _loadMembers() async {
    final client = Supabase.instance.client;
    final rows = await client.from('committee_memberships')
        .select('id, user_id, member_code, role, is_active, joined_at')
        .eq('organization_id', widget.organizationId)
        .order('joined_at', ascending: false);
    final members = List<Map<String, dynamic>>.from(rows);
    final details = await client.from('member_details')
        .select('membership_id, phone, address')
        .eq('organization_id', widget.organizationId);
    final detailByMembership = <String, Map<String, dynamic>>{
      for (final row in details)
        row['membership_id'].toString(): Map<String, dynamic>.from(row),
    };
    for (final member in members) {
      member['details'] = detailByMembership[member['id'].toString()];
    }
    return members;
  }

  void _refresh() => setState(() => _members = _loadMembers());

  Future<void> _addMember() async {
    final formKey = GlobalKey<FormState>();
    final userId = TextEditingController();
    final phone = TextEditingController();
    final address = TextEditingController();
    final accepted = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('নতুন সদস্য যোগ করুন'),
        content: Form(
          key: formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('সদস্যের আগে থেকে SomityHub account থাকতে হবে। তার Account UUID প্রয়োজন।'),
                const SizedBox(height: 12),
                TextFormField(
                  controller: userId,
                  decoration: const InputDecoration(labelText: 'User UUID'),
                  validator: (value) {
                    final v = value?.trim() ?? '';
                    final uuid = RegExp(r'^[0-9a-fA-F-]{36}$');
                    return uuid.hasMatch(v) ? null : 'সঠিক User UUID দিন।';
                  },
                ),
                const SizedBox(height: 12),
                TextFormField(controller: phone, decoration: const InputDecoration(labelText: 'মোবাইল (ঐচ্ছিক)')),
                const SizedBox(height: 12),
                TextFormField(controller: address, decoration: const InputDecoration(labelText: 'ঠিকানা (ঐচ্ছিক)')),
              ],
            ),
          ),
        ),
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
      userId.dispose();
      phone.dispose();
      address.dispose();
      return;
    }

    try {
      final result = await Supabase.instance.client.rpc('add_committee_member', params: {
        'p_organization_id': widget.organizationId,
        'p_user_id': userId.text.trim(),
        'p_phone': phone.text.trim().isEmpty ? null : phone.text.trim(),
        'p_address': address.text.trim().isEmpty ? null : address.text.trim(),
      });
      final row = result is List && result.isNotEmpty ? result.first : result;
      final code = row is Map ? row['member_code'] : null;
      _refresh();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(code == null ? 'সদস্য যোগ হয়েছে।' : 'সদস্য যোগ হয়েছে। Member Code: $code'),
        ));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('সদস্য যোগ করা যায়নি: $e'),
        ));
      }
    } finally {
      userId.dispose();
      phone.dispose();
      address.dispose();
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(widget.committeeName),
      actions: [
        IconButton(onPressed: _refresh, icon: const Icon(Icons.refresh), tooltip: 'Refresh'),
      ],
    ),
    floatingActionButton: FloatingActionButton.extended(
      onPressed: _addMember,
      icon: const Icon(Icons.person_add_alt_1),
      label: const Text('সদস্য যোগ করুন'),
    ),
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

        final members = snapshot.data ?? [];
        final activeCount = members.where((member) => member['is_active'] == true).length;

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
                            Text(members.length.toString(), style: const TextStyle(fontSize: 26, fontWeight: FontWeight.bold)),
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
              const Text('সদস্য তালিকা', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              if (members.isEmpty)
                const Card(child: Padding(
                  padding: EdgeInsets.all(20),
                  child: Text('এখনো কোনো সদস্য যোগ করা হয়নি।'),
                )),
              for (final member in members)
                Card(child: ListTile(
                  leading: CircleAvatar(
                    child: Text((member['member_code']?.toString().startsWith('ADM-') ?? false) ? 'A' : 'M'),
                  ),
                  title: Text(member['member_code']?.toString() ?? 'Member'),
                  subtitle: Text([
                    member['role']?.toString() ?? 'member',
                    member['is_active'] == true ? 'সক্রিয়' : 'নিষ্ক্রিয়',
                    if ((member['details']?['phone'] ?? '').toString().isNotEmpty)
                      member['details']['phone'].toString(),
                    if ((member['details']?['address'] ?? '').toString().isNotEmpty)
                      member['details']['address'].toString(),
                  ].join(' · ')),
                  trailing: const Icon(Icons.badge_outlined),
                )),
            ],
          ),
        );
      },
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
