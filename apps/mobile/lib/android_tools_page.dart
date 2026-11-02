import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:local_auth/local_auth.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class AndroidToolsPage extends StatefulWidget {
  const AndroidToolsPage({super.key, required this.organizationId, required this.membershipId, required this.role});
  final String organizationId;
  final String membershipId;
  final String role;

  @override
  State<AndroidToolsPage> createState() => _AndroidToolsPageState();
}

class _AndroidToolsPageState extends State<AndroidToolsPage> {
  bool _loading = true;
  bool _busy = false;
  String? _error;
  List<Map<String, dynamic>> _loans = [];
  List<Map<String, dynamic>> _repayments = [];
  List<Map<String, dynamic>> _members = [];
  bool _biometricEnabled = false;
  final _auth = LocalAuthentication();

  num _number(Object? value) => value is num ? value : num.tryParse('$value') ?? 0;
  bool get _canViewAll => const {'committee_admin', 'manager', 'treasurer', 'auditor'}.contains(widget.role);

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final client = Supabase.instance.client;
      var loanQuery = client.from('cooperative_loans')
          .select('id, membership_id, principal_amount, interest_rate, term_months, status, created_at, purpose')
          .eq('organization_id', widget.organizationId);
      if (!_canViewAll) loanQuery = loanQuery.eq('membership_id', widget.membershipId);
      final loans = await loanQuery.order('created_at', ascending: false).limit(500);
      final repayments = await client.from('cooperative_loan_repayments')
          .select('loan_id, amount, payment_date')
          .eq('organization_id', widget.organizationId).limit(2000);
      List<Map<String, dynamic>> members = [];
      if (_canViewAll) {
        final rows = await client.from('memberships').select('id, status')
            .eq('organization_id', widget.organizationId).limit(2000);
        members = List<Map<String, dynamic>>.from(rows);
      }
      final prefs = await SharedPreferences.getInstance();
      if (!mounted) return;
      setState(() {
        _loans = List<Map<String, dynamic>>.from(loans);
        _repayments = List<Map<String, dynamic>>.from(repayments);
        _members = members;
        _biometricEnabled = prefs.getBool('somityhub_biometric_lock') ?? false;
        _loading = false;
      });
    } catch (e) {
      if (mounted) setState(() { _error = 'Dashboard load করা যায়নি: $e'; _loading = false; });
    }
  }

  num _paidFor(String loanId) => _repayments.where((r) => r['loan_id'] == loanId)
      .fold<num>(0, (sum, row) => sum + _number(row['amount']));

  num _totalDue(Map<String, dynamic> loan) =>
      _number(loan['principal_amount']) * (1 + _number(loan['interest_rate']) / 100);

  num _outstanding(Map<String, dynamic> loan) =>
      (_totalDue(loan) - _paidFor(loan['id'].toString())).clamp(0, double.infinity);

  List<Map<String, dynamic>> get _activeLoans =>
      _loans.where((l) => const {'disbursed', 'approved'}.contains(l['status'])).toList();

  List<Map<String, dynamic>> get _dueLoans =>
      _activeLoans.where((l) => _outstanding(l) > 0).toList();

  Future<void> _exportBackup() async {
    setState(() => _busy = true);
    try {
      final client = Supabase.instance.client;
      final data = <String, dynamic>{
        'format': 'somityhub-android-backup-v1',
        'exported_at': DateTime.now().toUtc().toIso8601String(),
        'organization_id': widget.organizationId,
        'exported_by': client.auth.currentUser?.id,
        'loans': _loans,
        'loan_repayments': _repayments,
        'members': _members,
      };
      final bytes = utf8.encode(const JsonEncoder.withIndent('  ').convert(data));
      final path = await FilePicker.platform.saveFile(
        dialogTitle: 'SomityHub backup সংরক্ষণ করুন',
        fileName: 'somityhub-backup-${DateTime.now().toIso8601String().substring(0, 10)}.json',
        type: FileType.custom,
        allowedExtensions: ['json'],
        bytes: bytes,
      );
      if (mounted && path != null) _message('Backup file সংরক্ষিত হয়েছে। নিরাপদ জায়গায় রাখুন।');
    } catch (e) {
      if (mounted) _message('Backup export ব্যর্থ: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _setBiometric() async {
    setState(() => _busy = true);
    try {
      final available = await _auth.canCheckBiometrics && await _auth.isDeviceSupported();
      if (!available) throw Exception('এই ডিভাইসে biometric authentication available নয়।');
      final ok = await _auth.authenticate(
        localizedReason: 'SomityHub biometric security যাচাই করুন',
        options: const AuthenticationOptions(biometricOnly: true, stickyAuth: true),
      );
      if (!ok) return;
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('somityhub_biometric_lock', !_biometricEnabled);
      if (mounted) setState(() => _biometricEnabled = !_biometricEnabled);
      if (mounted) _message(_biometricEnabled ? 'Biometric verification preference enabled হয়েছে।' : 'Biometric preference বন্ধ হয়েছে।');
    } catch (e) {
      if (mounted) _message('Biometric setup করা যায়নি: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _pdfReport() async {
    final doc = pw.Document();
    doc.addPage(pw.MultiPage(build: (_) => [
      pw.Text('SomityHub - Loan & Due Report', style: pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold)),
      pw.SizedBox(height: 8),
      pw.Text('Generated: ${DateTime.now().toIso8601String()}'),
      pw.SizedBox(height: 12),
      pw.TableHelper.fromTextArray(
        headers: ['Loan ID', 'Status', 'Principal', 'Outstanding'],
        data: _loans.map((l) => [
          l['id'].toString().substring(0, 8),
          l['status'].toString(),
          _number(l['principal_amount']).toStringAsFixed(2),
          _outstanding(l).toStringAsFixed(2),
        ]).toList(),
      ),
      pw.SizedBox(height: 12),
      pw.Text('Outstanding total: ${_dueLoans.fold<num>(0, (sum, l) => sum + _outstanding(l)).toStringAsFixed(2)}'),
    ]));
    await Printing.layoutPdf(onLayout: (_) async => doc.save());
  }

  void _message(String value) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(value)));

  @override
  Widget build(BuildContext context) {
    final outstanding = _dueLoans.fold<num>(0, (sum, loan) => sum + _outstanding(loan));
    return Scaffold(
      appBar: AppBar(title: const Text('Dashboard ও Android Tools'), actions: [
        IconButton(onPressed: _loading ? null : _load, icon: const Icon(Icons.refresh)),
      ]),
      body: _loading ? const Center(child: CircularProgressIndicator())
        : _error != null ? Center(child: Padding(padding: const EdgeInsets.all(20), child: Text(_error!)))
        : RefreshIndicator(onRefresh: _load, child: ListView(padding: const EdgeInsets.all(16), children: [
          Wrap(spacing: 10, runSpacing: 10, children: [
            _metric('সক্রিয় ঋণ', _activeLoans.length.toString(), Icons.account_balance),
            _metric('বকেয়া ঋণ', _dueLoans.length.toString(), Icons.pending_actions),
            _metric('মোট বকেয়া', outstanding.toStringAsFixed(2), Icons.payments),
            if (_canViewAll) _metric('সদস্য', _members.length.toString(), Icons.groups),
          ]),
          const SizedBox(height: 18),
          Text('Due Management', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          if (_dueLoans.isEmpty) const Card(child: ListTile(title: Text('বর্তমানে outstanding loan পাওয়া যায়নি।')))
          else ..._dueLoans.map((loan) => Card(child: ListTile(
            leading: const Icon(Icons.event_busy_outlined),
            title: Text('Loan ${loan['id'].toString().substring(0, 8)} · ${loan['status']}'),
            subtitle: Text('Outstanding: ${_outstanding(loan).toStringAsFixed(2)} · Term: ${loan['term_months']} months'),
          ))),
          const Divider(height: 28),
          Text('Reports & Security', style: Theme.of(context).textTheme.titleLarge),
          ListTile(leading: const Icon(Icons.picture_as_pdf), title: const Text('PDF Loan & Due Report'), subtitle: const Text('বর্তমান loan ও repayment data থেকে PDF তৈরি করুন'), onTap: _busy ? null : _pdfReport),
          ListTile(leading: const Icon(Icons.backup_outlined), title: const Text('Export Backup (JSON)'), subtitle: const Text('RLS-অনুমোদিত loan, repayment ও member data export'), onTap: _busy ? null : _exportBackup),
          SwitchListTile(
            secondary: const Icon(Icons.fingerprint),
            title: const Text('Biometric verification preference'),
            subtitle: const Text('এখন enable/disable করার সময় biometric যাচাই করে। App-resume lock integration পরবর্তী ধাপ।'),
            value: _biometricEnabled,
            onChanged: _busy ? null : (_) => _setBiometric(),
          ),
          if (_busy) const Center(child: Padding(padding: EdgeInsets.all(16), child: CircularProgressIndicator())),
        ])),
    );
  }

  Widget _metric(String label, String value, IconData icon) => SizedBox(
    width: 155, child: Card(child: Padding(padding: const EdgeInsets.all(14), child: Column(
      crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(icon), const SizedBox(height: 8), Text(label),
        const SizedBox(height: 4), Text(value, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
      ],
    ))),
  );
}
