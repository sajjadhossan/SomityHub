import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class MultiBranchMemberAssignmentPage extends StatefulWidget {
  const MultiBranchMemberAssignmentPage({super.key, required this.organizationId});
  final String organizationId;

  @override
  State<MultiBranchMemberAssignmentPage> createState() => _MultiBranchMemberAssignmentPageState();
}

class _MultiBranchMemberAssignmentPageState extends State<MultiBranchMemberAssignmentPage> {
  List<Map<String, dynamic>> _branches = [];
  List<Map<String, dynamic>> _members = [];
  List<Map<String, dynamic>> _assignments = [];
  String? _memberId;
  final Set<String> _selected = {};
  String? _primary;
  bool _loading = true;
  bool _saving = false;
  String? _error;

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final db = Supabase.instance.client;
      final rows = await Future.wait([
        db.from('organization_branches').select('id,name,branch_code,is_default,is_active')
          .eq('organization_id', widget.organizationId).eq('is_active', true).order('name'),
        db.from('committee_memberships').select('id,member_code,user_id,role')
          .eq('organization_id', widget.organizationId).eq('is_active', true).order('member_code'),
        db.from('membership_branch_assignments').select('membership_id,branch_id,is_primary')
          .eq('organization_id', widget.organizationId),
      ]);
      if (!mounted) return;
      setState(() {
        _branches = List<Map<String, dynamic>>.from(rows[0] as List);
        _members = List<Map<String, dynamic>>.from(rows[1] as List);
        _assignments = List<Map<String, dynamic>>.from(rows[2] as List);
        _memberId = _members.any((m) => m['id'].toString() == _memberId)
          ? _memberId : (_members.isEmpty ? null : _members.first['id'].toString());
        _syncSelection();
      });
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _syncSelection() {
    final rows = _assignments.where((a) => a['membership_id'].toString() == _memberId).toList();
    _selected
      ..clear()
      ..addAll(rows.map((a) => a['branch_id'].toString()));
    _primary = rows.where((a) => a['is_primary'] == true).map((a) => a['branch_id'].toString()).firstOrNull;
    if (_primary == null && _selected.isNotEmpty) _primary = _selected.first;
  }

  Future<void> _save() async {
    if (_memberId == null || _selected.isEmpty || _primary == null || !_selected.contains(_primary)) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('কমপক্ষে একটি শাখা নির্বাচন করে Primary branch নির্ধারণ করুন।')));
      return;
    }
    setState(() => _saving = true);
    try {
      await Supabase.instance.client.rpc('set_member_branch_assignments', params: {
        'p_organization_id': widget.organizationId,
        'p_membership_id': _memberId,
        'p_branch_ids': _selected.toList(),
        'p_primary_branch_id': _primary,
      });
      await _load();
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('সদস্যের multi-branch assignment সংরক্ষিত হয়েছে।')));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Assignment সংরক্ষণ হয়নি: $e')));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('সদস্যের একাধিক শাখা')),
    body: _loading ? const Center(child: CircularProgressIndicator())
      : _error != null ? Center(child: Padding(padding: const EdgeInsets.all(20), child: Text('তথ্য লোড হয়নি: $_error')))
      : ListView(padding: const EdgeInsets.all(16), children: [
        const Text('একজন সদস্যকে একাধিক active branch-এ যুক্ত করুন এবং একটি Primary branch নির্ধারণ করুন।'),
        const SizedBox(height: 16),
        if (_members.isEmpty || _branches.isEmpty)
          const Text('Active member বা branch পাওয়া যায়নি।')
        else ...[
          DropdownButtonFormField<String>(
            value: _memberId,
            decoration: const InputDecoration(labelText: 'সদস্য'),
            items: [for (final m in _members) DropdownMenuItem(
              value: m['id'].toString(), child: Text('${m['member_code']} · ${m['role']}'),
            )],
            onChanged: _saving ? null : (v) => setState(() { _memberId = v; _syncSelection(); }),
          ),
          const SizedBox(height: 12),
          const Text('শাখা নির্বাচন করুন', style: TextStyle(fontWeight: FontWeight.bold)),
          for (final b in _branches)
            CheckboxListTile(
              value: _selected.contains(b['id'].toString()),
              title: Text(b['name'].toString()),
              subtitle: Text('${b['branch_code']} · ${b['is_default'] == true ? 'Default' : 'Additional'}'),
              onChanged: _saving ? null : (checked) => setState(() {
                final id = b['id'].toString();
                if (checked == true) {
                  _selected.add(id);
                  _primary ??= id;
                } else {
                  _selected.remove(id);
                  if (_primary == id) _primary = _selected.isEmpty ? null : _selected.first;
                }
              }),
            ),
          const Divider(),
          const Text('Primary branch', style: TextStyle(fontWeight: FontWeight.bold)),
          for (final b in _branches.where((b) => _selected.contains(b['id'].toString())))
            RadioListTile<String>(
              value: b['id'].toString(), groupValue: _primary,
              title: Text(b['name'].toString()),
              onChanged: _saving ? null : (v) => setState(() => _primary = v),
            ),
          const SizedBox(height: 12),
          FilledButton.icon(onPressed: _saving ? null : _save,
            icon: _saving ? const SizedBox(width: 18,height: 18,child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.save),
            label: const Text('Assignment সংরক্ষণ করুন')),
        ],
      ]),
  );
}
