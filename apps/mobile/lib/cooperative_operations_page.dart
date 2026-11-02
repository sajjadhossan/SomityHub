import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class CooperativeOperationsPage extends StatefulWidget {
  const CooperativeOperationsPage({
    super.key,
    required this.organizationId,
    required this.membershipId,
    required this.role,
  });

  final String organizationId;
  final String membershipId;
  final String role;

  @override
  State<CooperativeOperationsPage> createState() => _CooperativeOperationsPageState();
}

class _CooperativeOperationsPageState extends State<CooperativeOperationsPage>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs;
  bool _busy = false;
  List<Map<String, dynamic>> _branches = [];
  List<Map<String, dynamic>> _members = [];
  List<Map<String, dynamic>> _assignments = [];
  List<Map<String, dynamic>> _loans = [];
  List<Map<String, dynamic>> _repayments = [];
  List<Map<String, dynamic>> _vouchers = [];
  List<Map<String, dynamic>> _meetings = [];
  List<Map<String, dynamic>> _transactions = [];
  List<Map<String, dynamic>> _receipts = [];
  String? _error;

  bool get _canManage => const ['committee_admin', 'manager'].contains(widget.role);
  bool get _canReviewFinance => const ['committee_admin', 'manager', 'treasurer'].contains(widget.role);
  bool get _canFinance => const ['committee_admin', 'manager', 'treasurer', 'accountant', 'auditor'].contains(widget.role);
  bool get _canCreateVoucher => const ['committee_admin', 'manager', 'treasurer', 'accountant'].contains(widget.role);
  bool get _canProcessLoanCash => const ['committee_admin', 'manager', 'treasurer', 'accountant'].contains(widget.role);
  bool get _canManageMeetings => const ['committee_admin', 'manager', 'general_secretary', 'secretary'].contains(widget.role);

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 6, vsync: this);
    _load();
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() { _busy = true; _error = null; });
    try {
      final db = Supabase.instance.client;
      final results = await Future.wait<dynamic>([
        db.from('organization_branches').select('id,name,branch_code,is_default,is_active')
          .eq('organization_id', widget.organizationId).eq('is_active', true).order('is_default', ascending: false),
        db.from('committee_memberships').select('id,member_code,user_id,role')
          .eq('organization_id', widget.organizationId).eq('is_active', true).order('member_code'),
        db.from('membership_branch_assignments').select('membership_id,branch_id')
          .eq('organization_id', widget.organizationId),
        db.from('cooperative_loans').select().eq('organization_id', widget.organizationId).order('created_at', ascending: false).limit(100),
        _canFinance
          ? db.from('cooperative_vouchers').select().eq('organization_id', widget.organizationId).order('transaction_date', ascending: false).limit(100)
          : Future.value(<Map<String, dynamic>>[]),
        db.from('cooperative_meetings').select().eq('organization_id', widget.organizationId).order('starts_at', ascending: false).limit(100),
        _canFinance
          ? db.from('financial_transactions').select('id,branch_id,transaction_type,amount,status,created_at')
              .eq('organization_id', widget.organizationId).order('created_at', ascending: false).limit(500)
          : Future.value(<Map<String, dynamic>>[]),
        db.rpc('get_financial_receipts', params: {
          'p_org_id': widget.organizationId,
          'p_membership_id': _canFinance ? null : widget.membershipId,
          'p_limit': 100,
        }),
        db.from('cooperative_loan_repayments').select('loan_id,amount,payment_date,reference_number')
          .eq('organization_id', widget.organizationId),
      ]);
      if (!mounted) return;
      setState(() {
        _branches = List<Map<String, dynamic>>.from(results[0] as List);
        _members = List<Map<String, dynamic>>.from(results[1] as List);
        _assignments = List<Map<String, dynamic>>.from(results[2] as List);
        _loans = List<Map<String, dynamic>>.from(results[3] as List);
        _vouchers = List<Map<String, dynamic>>.from(results[4] as List);
        _meetings = List<Map<String, dynamic>>.from(results[5] as List);
        _transactions = List<Map<String, dynamic>>.from(results[6] as List);
        _receipts = List<Map<String, dynamic>>.from(results[7] as List);
        _repayments = List<Map<String, dynamic>>.from(results[8] as List);
      });
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _money(Object? value) {
    final n = value is num ? value : num.tryParse(value?.toString() ?? '') ?? 0;
    return n.toStringAsFixed(2);
  }

  String _date(Object? value) {
    if (value == null) return '—';
    final d = DateTime.tryParse(value.toString())?.toLocal();
    if (d == null) return value.toString();
    return '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';
  }

  String _branchName(Object? id) => _branches.firstWhere(
    (b) => b['id'].toString() == id?.toString(),
    orElse: () => {'name': 'শাখা অজানা'},
  )['name'].toString();

  String _memberCode(Object? id) => _members.firstWhere(
    (m) => m['id'].toString() == id?.toString(),
    orElse: () => {'member_code': id?.toString() ?? 'সদস্য'},
  )['member_code'].toString();

  Future<void> _messageError(Object e) async {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('কাজটি সম্পন্ন হয়নি: $e')),
      );
    }
  }

  Future<void> _createLoan() async {
    if (_branches.isEmpty) return _messageError('সক্রিয় শাখা পাওয়া যায়নি।');
    final amount = TextEditingController();
    final rate = TextEditingController(text: '0');
    final months = TextEditingController(text: '12');
    final purpose = TextEditingController();
    String branch = _branches.first['id'].toString();
    final form = GlobalKey<FormState>();
    final ok = await showDialog<bool>(context: context, builder: (ctx) => StatefulBuilder(
      builder: (ctx, setDialog) => AlertDialog(
        title: const Text('ঋণের আবেদন'),
        content: Form(key: form, child: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
          TextFormField(controller: amount, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'ঋণের পরিমাণ'),
            validator: (v) => (num.tryParse(v ?? '') ?? 0) <= 0 ? 'সঠিক পরিমাণ দিন।' : null),
          TextFormField(controller: rate, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Flat interest rate (%)'),
            validator: (v) { final n = num.tryParse(v ?? ''); return n == null || n < 0 || n > 100 ? '০–১০০ এর মধ্যে দিন।' : null; }),
          TextFormField(controller: months, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'মেয়াদ (মাস)'),
            validator: (v) { final n = int.tryParse(v ?? ''); return n == null || n < 1 || n > 600 ? '১–৬০০ মাসের মধ্যে দিন।' : null; }),
          DropdownButtonFormField<String>(initialValue: branch, decoration: const InputDecoration(labelText: 'শাখা'),
            items: [for (final b in _branches) DropdownMenuItem(value: b['id'].toString(), child: Text(b['name'].toString()))],
            onChanged: (v) => setDialog(() => branch = v ?? branch)),
          TextFormField(controller: purpose, maxLines: 3, decoration: const InputDecoration(labelText: 'ঋণের উদ্দেশ্য'),
            validator: (v) => (v?.trim().length ?? 0) < 3 ? 'কমপক্ষে ৩ অক্ষর লিখুন।' : null),
        ]))),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('বাতিল')),
          FilledButton(onPressed: () { if (form.currentState!.validate()) Navigator.pop(ctx, true); }, child: const Text('আবেদন জমা')),
        ],
      ),
    ));
    if (ok != true || !mounted) { amount.dispose(); rate.dispose(); months.dispose(); purpose.dispose(); return; }
    try {
      await Supabase.instance.client.from('cooperative_loans').insert({
        'organization_id': widget.organizationId, 'membership_id': widget.membershipId,
        'branch_id': branch, 'principal_amount': num.parse(amount.text),
        'interest_rate': num.parse(rate.text), 'term_months': int.parse(months.text),
        'purpose': purpose.text.trim(), 'requested_by': Supabase.instance.client.auth.currentUser!.id,
        'status': 'pending',
      });
      await _load();
    } catch (e) { await _messageError(e); }
    amount.dispose(); rate.dispose(); months.dispose(); purpose.dispose();
  }

  Future<void> _reviewLoan(Map<String, dynamic> row, String decision) async {
    try {
      await Supabase.instance.client.rpc('review_cooperative_loan', params: {
        'p_loan_id': row['id'], 'p_decision': decision,
      });
      await _load();
    } catch (e) { await _messageError(e); }
  }

  Future<void> _disburseLoan(Map<String, dynamic> row) async {
    final reference = TextEditingController();
    final ok = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(
      title: const Text('ঋণ বিতরণ নিশ্চিত করুন'),
      content: TextField(controller: reference, decoration: const InputDecoration(labelText: 'Bank / transaction reference (ঐচ্ছিক)')),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('বাতিল')),
        FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('বিতরণ রেকর্ড করুন')),
      ],
    ));
    if (ok == true && mounted) {
      try {
        await Supabase.instance.client.rpc('disburse_cooperative_loan', params: {
          'p_loan_id': row['id'],
          'p_reference_number': reference.text.trim().isEmpty ? null : reference.text.trim(),
        });
        await _load();
      } catch (e) { await _messageError(e); }
    }
    reference.dispose();
  }

  Future<void> _repayLoan(Map<String, dynamic> row) async {
    final amount = TextEditingController();
    final ref = TextEditingController();
    final ok = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(
      title: const Text('ঋণের কিস্তি গ্রহণ'),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        TextField(controller: amount, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'পরিশোধের পরিমাণ')),
        TextField(controller: ref, decoration: const InputDecoration(labelText: 'Reference (ঐচ্ছিক)')),
      ]),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('বাতিল')),
        FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('রেকর্ড করুন')),
      ],
    ));
    if (ok == true && mounted) {
      try {
        final n = num.tryParse(amount.text);
        if (n == null || n <= 0) throw Exception('সঠিক পরিমাণ দিন।');
        await Supabase.instance.client.rpc('record_cooperative_loan_repayment', params: {
          'p_loan_id': row['id'], 'p_amount': n,
          'p_payment_date': DateTime.now().toIso8601String().substring(0, 10),
          'p_reference_number': ref.text.trim().isEmpty ? null : ref.text.trim(),
        });
        await _load();
      } catch (e) { await _messageError(e); }
    }
    amount.dispose(); ref.dispose();
  }

  Future<void> _createVoucher() async {
    if (_branches.isEmpty) return _messageError('সক্রিয় শাখা পাওয়া যায়নি।');
    final category = TextEditingController();
    final amount = TextEditingController();
    final description = TextEditingController();
    final number = TextEditingController(text: 'V-${DateTime.now().millisecondsSinceEpoch}');
    String type = 'expense';
    String branch = _branches.first['id'].toString();
    final form = GlobalKey<FormState>();
    final ok = await showDialog<bool>(context: context, builder: (ctx) => StatefulBuilder(
      builder: (ctx, setDialog) => AlertDialog(
        title: const Text('নতুন ভাউচার'),
        content: Form(key: form, child: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
          TextFormField(controller: number, decoration: const InputDecoration(labelText: 'ভাউচার নম্বর'),
            validator: (v) => (v?.trim().isEmpty ?? true) ? 'নম্বর দিন।' : null),
          DropdownButtonFormField<String>(initialValue: type, decoration: const InputDecoration(labelText: 'ধরন'),
            items: const [DropdownMenuItem(value: 'income', child: Text('আয়')), DropdownMenuItem(value: 'expense', child: Text('ব্যয়'))],
            onChanged: (v) => setDialog(() => type = v ?? type)),
          TextFormField(controller: category, decoration: const InputDecoration(labelText: 'খাত'),
            validator: (v) => (v?.trim().length ?? 0) < 2 ? 'খাত লিখুন।' : null),
          TextFormField(controller: amount, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'পরিমাণ'),
            validator: (v) => (num.tryParse(v ?? '') ?? 0) <= 0 ? 'সঠিক পরিমাণ দিন।' : null),
          DropdownButtonFormField<String>(initialValue: branch, decoration: const InputDecoration(labelText: 'শাখা'),
            items: [for (final b in _branches) DropdownMenuItem(value: b['id'].toString(), child: Text(b['name'].toString()))],
            onChanged: (v) => setDialog(() => branch = v ?? branch)),
          TextFormField(controller: description, maxLines: 2, decoration: const InputDecoration(labelText: 'বিবরণ'),
            validator: (v) => (v?.trim().length ?? 0) < 2 ? 'বিবরণ লিখুন।' : null),
        ]))),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('বাতিল')),
          FilledButton(onPressed: () { if (form.currentState!.validate()) Navigator.pop(ctx, true); }, child: const Text('জমা দিন')),
        ],
      ),
    ));
    if (ok == true && mounted) {
      try {
        await Supabase.instance.client.from('cooperative_vouchers').insert({
          'organization_id': widget.organizationId, 'branch_id': branch,
          'voucher_number': number.text.trim(), 'voucher_type': type,
          'category': category.text.trim(), 'amount': num.parse(amount.text),
          'description': description.text.trim(), 'created_by': Supabase.instance.client.auth.currentUser!.id,
          'status': 'pending',
        });
        await _load();
      } catch (e) { await _messageError(e); }
    }
    category.dispose(); amount.dispose(); description.dispose(); number.dispose();
  }

  Future<void> _reviewVoucher(Map<String, dynamic> row, String decision) async {
    try {
      await Supabase.instance.client.rpc('review_cooperative_voucher', params: {
        'p_voucher_id': row['id'], 'p_decision': decision,
      });
      await _load();
    } catch (e) { await _messageError(e); }
  }

  Future<void> _createMeeting() async {
    if (_branches.isEmpty) return _messageError('সক্রিয় শাখা পাওয়া যায়নি।');
    final title = TextEditingController();
    final agenda = TextEditingController();
    final location = TextEditingController();
    String branch = _branches.first['id'].toString();
    DateTime starts = DateTime.now().add(const Duration(days: 1));
    final form = GlobalKey<FormState>();
    final ok = await showDialog<bool>(context: context, builder: (ctx) => StatefulBuilder(
      builder: (ctx, setDialog) => AlertDialog(
        title: const Text('সভা নির্ধারণ'),
        content: Form(key: form, child: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
          TextFormField(controller: title, decoration: const InputDecoration(labelText: 'সভার শিরোনাম'),
            validator: (v) => (v?.trim().length ?? 0) < 2 ? 'শিরোনাম লিখুন।' : null),
          TextFormField(controller: agenda, maxLines: 2, decoration: const InputDecoration(labelText: 'আলোচ্যসূচি')),
          TextFormField(controller: location, decoration: const InputDecoration(labelText: 'স্থান')),
          DropdownButtonFormField<String>(initialValue: branch, decoration: const InputDecoration(labelText: 'শাখা'),
            items: [for (final b in _branches) DropdownMenuItem(value: b['id'].toString(), child: Text(b['name'].toString()))],
            onChanged: (v) => setDialog(() => branch = v ?? branch)),
          ListTile(contentPadding: EdgeInsets.zero, title: const Text('সভার তারিখ ও সময়'),
            subtitle: Text(starts.toLocal().toString().substring(0, 16)),
            trailing: IconButton(icon: const Icon(Icons.calendar_month), onPressed: () async {
              final d = await showDatePicker(context: ctx, initialDate: starts, firstDate: DateTime.now().subtract(const Duration(days: 365)), lastDate: DateTime.now().add(const Duration(days: 3650)));
              if (d == null || !ctx.mounted) return;
              final t = await showTimePicker(context: ctx, initialTime: TimeOfDay.fromDateTime(starts));
              if (t != null) setDialog(() => starts = DateTime(d.year, d.month, d.day, t.hour, t.minute));
            })),
        ]))),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('বাতিল')),
          FilledButton(onPressed: () { if (form.currentState!.validate()) Navigator.pop(ctx, true); }, child: const Text('সংরক্ষণ')),
        ],
      ),
    ));
    if (ok == true && mounted) {
      try {
        await Supabase.instance.client.from('cooperative_meetings').insert({
          'organization_id': widget.organizationId, 'branch_id': branch,
          'title': title.text.trim(), 'agenda': agenda.text.trim().isEmpty ? null : agenda.text.trim(),
          'location': location.text.trim().isEmpty ? null : location.text.trim(),
          'starts_at': starts.toUtc().toIso8601String(),
          'created_by': Supabase.instance.client.auth.currentUser!.id,
        });
        await _load();
      } catch (e) { await _messageError(e); }
    }
    title.dispose(); agenda.dispose(); location.dispose();
  }

  Future<void> _showReceipt(Map<String, dynamic> receipt) async {
    Map<String, dynamic>? verification;
    var verifying = false;
    await showDialog<void>(context: context, builder: (dialogContext) => StatefulBuilder(
      builder: (dialogContext, setDialog) => AlertDialog(
        title: Text('রসিদ · ${receipt['receipt_number']}'),
        content: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
          QrImageView(data: receipt['verification_token'].toString(), size: 176),
          Text(receipt['receipt_number'].toString(), style: const TextStyle(fontWeight: FontWeight.bold)),
          Text('৳${_money(receipt['amount'])} · ${receipt['transaction_type']}'),
          Text('ইস্যু: ${_date(receipt['issued_at'])}'),
          if (verification != null) ...[
            const Divider(),
            Text('Verification: ${verification!['receipt_status']}',
              style: TextStyle(fontWeight: FontWeight.bold,
                color: verification!['receipt_status'] == 'valid' ? Colors.green : Colors.red)),
            Text('${verification!['committee_name'] ?? ''}'),
            Text('${verification!['currency_code'] ?? ''} ${verification!['amount'] ?? ''}'),
          ],
        ])),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('বন্ধ')),
          FilledButton(
            onPressed: verifying ? null : () async {
              setDialog(() => verifying = true);
              try {
                final result = await Supabase.instance.client.rpc('verify_financial_receipt',
                  params: {'p_verification_token': receipt['verification_token']});
                final rows = List<Map<String, dynamic>>.from(result as List);
                if (dialogContext.mounted) {
                  setDialog(() {
                    verification = rows.isEmpty ? {'receipt_status': 'not_found'} : rows.first;
                    verifying = false;
                  });
                }
              } catch (e) {
                if (dialogContext.mounted) {
                  setDialog(() {
                    verification = {'receipt_status': 'error', 'committee_name': e.toString()};
                    verifying = false;
                  });
                }
              }
            },
            child: verifying ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
              : const Text('রসিদ যাচাই করুন'),
          ),
        ],
      ),
    ));
  }

  Future<void> _updateMeetingStatus(Map<String, dynamic> meeting, String status) async {
    try {
      await Supabase.instance.client.from('cooperative_meetings')
        .update({'status': status})
        .eq('organization_id', widget.organizationId)
        .eq('id', meeting['id']);
      await _load();
    } catch (e) { await _messageError(e); }
  }

  Future<void> _attendance(Map<String, dynamic> meeting) async {
    try {
      final rows = await Supabase.instance.client.from('cooperative_attendance')
        .select('membership_id,attendance_status,note').eq('meeting_id', meeting['id']);
      final existing = {for (final r in rows) r['membership_id'].toString(): Map<String, dynamic>.from(r)};
      final members = _members.where((m) => _branchMemberIds(meeting['branch_id']).contains(m['id'].toString())).toList();
      if (!mounted) return;
      await showDialog<void>(context: context, builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialog) => AlertDialog(
          title: Text('উপস্থিতি · ${meeting['title']}'),
          content: SizedBox(width: 420, child: members.isEmpty
            ? const Text('এই শাখায় কোনো সদস্য পাওয়া যায়নি।')
            : ListView(shrinkWrap: true, children: [for (final m in members)
              DropdownButtonFormField<String>(
                initialValue: (existing[m['id'].toString()]?['attendance_status'] ?? 'present').toString(),
                decoration: InputDecoration(labelText: m['member_code'].toString()),
                items: const [
                  DropdownMenuItem(value: 'present', child: Text('উপস্থিত')),
                  DropdownMenuItem(value: 'absent', child: Text('অনুপস্থিত')),
                  DropdownMenuItem(value: 'late', child: Text('দেরি')),
                  DropdownMenuItem(value: 'excused', child: Text('ছুটি')),
                ],
                onChanged: (v) => setDialog(() {
                  existing[m['id'].toString()] = {'attendance_status': v ?? 'present'};
                }),
              ),
            ])),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('বন্ধ')),
            if (_canManageMeetings) FilledButton(onPressed: () async {
              try {
                final payload = members.map((m) => {
                  'organization_id': widget.organizationId, 'meeting_id': meeting['id'],
                  'membership_id': m['id'], 'attendance_status': existing[m['id'].toString()]?['attendance_status'] ?? 'present',
                  'marked_by': Supabase.instance.client.auth.currentUser!.id,
                }).toList();
                if (payload.isNotEmpty) {
                  await Supabase.instance.client.from('cooperative_attendance')
                    .upsert(payload, onConflict: 'meeting_id,membership_id');
                }
                if (ctx.mounted) Navigator.pop(ctx);
                await _load();
              } catch (e) { await _messageError(e); }
            }, child: const Text('উপস্থিতি সংরক্ষণ')),
          ],
        ),
      ));
    } catch (e) { await _messageError(e); }
  }

  List<String> _branchMemberIds(Object? branchId) => _assignments
    .where((a) => a['branch_id'].toString() == branchId?.toString())
    .map((a) => a['membership_id'].toString()).toSet().toList();

  @override
  Widget build(BuildContext context) {
    final approved = _transactions.where((r) => r['status'] == 'approved').toList();
    final deposits = approved.where((r) => r['transaction_type'] == 'deposit').fold<num>(0, (s, r) => s + ((r['amount'] as num?) ?? 0));
    final withdrawals = approved.where((r) => r['transaction_type'] == 'withdrawal').fold<num>(0, (s, r) => s + ((r['amount'] as num?) ?? 0));
    final expenses = approved.where((r) => r['transaction_type'] == 'expense').fold<num>(0, (s, r) => s + ((r['amount'] as num?) ?? 0));
    final otherIncome = approved.where((r) => r['transaction_type'] == 'income').fold<num>(0, (s, r) => s + ((r['amount'] as num?) ?? 0));
    final loanDisbursements = approved.where((r) => r['transaction_type'] == 'loan_disbursement').fold<num>(0, (s, r) => s + ((r['amount'] as num?) ?? 0));
    final loanRepayments = approved.where((r) => r['transaction_type'] == 'loan_repayment').fold<num>(0, (s, r) => s + ((r['amount'] as num?) ?? 0));
    return Scaffold(
      appBar: AppBar(title: const Text('সমিতির কার্যক্রম'), actions: [
        IconButton(onPressed: _busy ? null : _load, icon: const Icon(Icons.refresh)),
      ], bottom: TabBar(controller: _tabs, isScrollable: true, tabs: const [
        Tab(text: 'ঋণ'), Tab(text: 'ভাউচার'), Tab(text: 'সভা ও উপস্থিতি'), Tab(text: 'রসিদ'), Tab(text: 'রিপোর্ট'), Tab(text: 'শাখা'),
      ])),
      body: _busy && _branches.isEmpty
        ? const Center(child: CircularProgressIndicator())
        : _error != null
          ? Center(child: Padding(padding: const EdgeInsets.all(20), child: Text('তথ্য লোড হয়নি: $_error')))
          : TabBarView(controller: _tabs, children: [
            _loansView(),
            _vouchersView(),
            _meetingsView(),
            _receiptsView(),
            _reportsView(deposits, withdrawals, expenses, otherIncome, loanDisbursements, loanRepayments),
            _branchesView(),
          ]),
    );
  }

  Widget _loanCard(Map<String, dynamic> r) {
    final paid = _repayments.where((p) => p['loan_id'].toString() == r['id'].toString())
      .fold<num>(0, (sum, p) => sum + ((p['amount'] as num?) ?? 0));
    final totalDue = ((r['principal_amount'] as num?) ?? 0) *
      (1 + ((r['interest_rate'] as num?) ?? 0) / 100);
    final outstanding = totalDue - paid > 0 ? totalDue - paid : 0;
    return Card(child: ListTile(
      title: Text('${_memberCode(r['membership_id'])} · ৳${_money(r['principal_amount'])}'),
      subtitle: Text('${r['purpose']}\n${_branchName(r['branch_id'])} · ${r['term_months']} মাস · Flat ${r['interest_rate']}% · ${r['status']}\nপরিশোধ: ৳${_money(paid)} · বকেয়া: ৳${_money(outstanding)}'),
      isThreeLine: true,
      trailing: PopupMenuButton<String>(onSelected: (v) {
        if (v == 'approved' || v == 'rejected') _reviewLoan(r, v);
        if (v == 'disburse') _disburseLoan(r);
        if (v == 'repay') _repayLoan(r);
      }, itemBuilder: (_) => [
        if (_canReviewFinance && r['status'] == 'pending') const PopupMenuItem(value: 'approved', child: Text('অনুমোদন')),
        if (_canReviewFinance && r['status'] == 'pending') const PopupMenuItem(value: 'rejected', child: Text('প্রত্যাখ্যান')),
        if (_canProcessLoanCash && r['status'] == 'approved') const PopupMenuItem(value: 'disburse', child: Text('ঋণ বিতরণ')),
        if (_canProcessLoanCash && r['status'] == 'disbursed') const PopupMenuItem(value: 'repay', child: Text('কিস্তি গ্রহণ')),
      ]),
    ));
  }

  Widget _loansView() => ListView(padding: const EdgeInsets.all(16), children: [
    if (!_canManage && !_canFinance) FilledButton.icon(onPressed: _createLoan, icon: const Icon(Icons.add), label: const Text('ঋণের আবেদন করুন')),
    if (_canReviewFinance) FilledButton.icon(onPressed: _createLoan, icon: const Icon(Icons.add), label: const Text('ঋণের আবেদন তৈরি করুন')),
    if (_loans.isEmpty) const ListTile(title: Text('কোনো ঋণের আবেদন নেই।')),
    for (final r in _loans) _loanCard(r),
  ]);

  Widget _vouchersView() => ListView(padding: const EdgeInsets.all(16), children: [
    if (_canCreateVoucher) FilledButton.icon(onPressed: _createVoucher, icon: const Icon(Icons.add), label: const Text('নতুন ভাউচার')),
    if (!_canFinance) const ListTile(title: Text('ভাউচার দেখতে Finance role প্রয়োজন।')),
    if (_canFinance && !_canCreateVoucher) const ListTile(title: Text('Auditor role-এ ভাউচার দেখা যাবে; নতুন ভাউচার তৈরি করা যাবে না।')),
    if (_vouchers.isEmpty && _canFinance) const ListTile(title: Text('কোনো ভাউচার নেই।')),
    for (final r in _vouchers) Card(child: ListTile(
      title: Text('${r['voucher_number']} · ৳${_money(r['amount'])}'),
      subtitle: Text('${r['voucher_type'] == 'income' ? 'আয়' : 'ব্যয়'} · ${r['category']}\n${r['description']}\n${_branchName(r['branch_id'])} · ${_date(r['transaction_date'])} · ${r['status']}'),
      isThreeLine: true,
      trailing: _canReviewFinance && r['status'] == 'pending' ? PopupMenuButton<String>(
        onSelected: (v) => _reviewVoucher(r, v),
        itemBuilder: (_) => const [
          PopupMenuItem(value: 'approved', child: Text('অনুমোদন')),
          PopupMenuItem(value: 'rejected', child: Text('প্রত্যাখ্যান')),
        ],
      ) : null,
    )),
    if (_vouchers.isNotEmpty) const Padding(padding: EdgeInsets.all(8), child: Text('নোট: অনুমোদিত voucher এখনো cash ledger-এ post হয় না; রিপোর্টে financial transaction ledger-ই দেখানো হয়।')),
  ]);

  Widget _meetingsView() => ListView(padding: const EdgeInsets.all(16), children: [
    if (_canManageMeetings) FilledButton.icon(onPressed: _createMeeting, icon: const Icon(Icons.add), label: const Text('নতুন সভা নির্ধারণ')),
    if (_meetings.isEmpty) const ListTile(title: Text('কোনো সভা নির্ধারিত নেই।')),
    for (final r in _meetings) Card(child: ListTile(
      title: Text(r['title'].toString()),
      subtitle: Text('${_date(r['starts_at'])} · ${_branchName(r['branch_id'])}\n${r['location'] ?? ''}\n${r['agenda'] ?? ''}'),
      isThreeLine: true,
      trailing: PopupMenuButton<String>(
        onSelected: (value) {
          if (value == 'attendance') {
            _attendance(r);
          }
          if (value == 'completed' || value == 'cancelled') {
            _updateMeetingStatus(r, value);
          }
        },
        itemBuilder: (_) => [
          const PopupMenuItem(value: 'attendance', child: Text('উপস্থিতি নিন')),
          if (_canManageMeetings && r['status'] == 'scheduled')
            const PopupMenuItem(value: 'completed', child: Text('সভা সম্পন্ন')),
          if (_canManageMeetings && r['status'] == 'scheduled')
            const PopupMenuItem(value: 'cancelled', child: Text('সভা বাতিল')),
        ],
      ),
    )),
  ]);

  Widget _receiptsView() => ListView(padding: const EdgeInsets.all(16), children: [
    const Text('অনুমোদিত Deposit / Withdrawal-এর system-issued receipt', style: TextStyle(fontWeight: FontWeight.bold)),
    if (_receipts.isEmpty) const ListTile(title: Text('এখনো কোনো রসিদ ইস্যু হয়নি।')),
    for (final r in _receipts) Card(child: ListTile(
      leading: const Icon(Icons.receipt_long_outlined),
      title: Text(r['receipt_number'].toString()),
      subtitle: Text('${r['transaction_type']} · ৳${_money(r['amount'])} · ${_date(r['issued_at'])}'),
      trailing: const Icon(Icons.qr_code_2),
      onTap: () => _showReceipt(r),
    )),
  ]);

  Widget _reportsView(num deposits, num withdrawals, num expenses, num otherIncome, num loanDisbursements, num loanRepayments) => ListView(padding: const EdgeInsets.all(16), children: [
    const Text('অনুমোদিত Financial Transaction Ledger', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
    const SizedBox(height: 8),
    _metric('সঞ্চয় / Deposit', deposits),
    _metric('উত্তোলন / Withdrawal', withdrawals),
    _metric('অন্যান্য ব্যয়', expenses),
    _metric('নিট প্রবাহ (Deposit − Withdrawal − Expense)', deposits - withdrawals - expenses),
    const SizedBox(height: 12),
    Text('সাম্প্রতিক অনুমোদিত লেনদেন: ${approvedTransactions.length}'),
    for (final r in approvedTransactions.take(100)) ListTile(
      dense: true, title: Text('${r['transaction_type']} · ৳${_money(r['amount'])}'),
      subtitle: Text('${_branchName(r['branch_id'])} · ${_date(r['created_at'])}'),
    ),
    const Text('রিপোর্টটি financial_transactions-এর approved rows থেকে তৈরি। Savings member balance ledger-এর বাইরে voucher ও loan cash movements সমিতির cash flow-তে অন্তর্ভুক্ত।', style: TextStyle(color: Colors.grey)),
  ]);

  List<Map<String, dynamic>> get approvedTransactions =>
    _transactions.where((r) => r['status'] == 'approved').toList();

  Widget _metric(String label, num value) => Card(child: ListTile(
    title: Text(label), trailing: Text('৳${value.toStringAsFixed(2)}', style: const TextStyle(fontWeight: FontWeight.bold)),
  ));

  Widget _branchesView() => ListView(padding: const EdgeInsets.all(16), children: [
    const Text('সক্রিয় শাখা', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
    for (final b in _branches) Card(child: ListTile(
      leading: Icon(b['is_default'] == true ? Icons.home_work : Icons.store),
      title: Text(b['name'].toString()),
      subtitle: Text('${b['branch_code'] ?? ''} · ${b['is_default'] == true ? 'Default branch' : 'Active'}'),
    )),
    const Text('শাখা তৈরি, বন্ধ এবং সদস্যের primary branch নির্ধারণের জন্য মূল workspace-এর Branch Management ব্যবহার করুন।'),
  ]);
}
