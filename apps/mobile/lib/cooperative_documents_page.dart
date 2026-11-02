import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

class CooperativeDocumentsPage extends StatefulWidget {
  const CooperativeDocumentsPage({
    super.key,
    required this.organizationId,
    required this.role,
  });

  final String organizationId;
  final String role;

  @override
  State<CooperativeDocumentsPage> createState() => _CooperativeDocumentsPageState();
}

class _CooperativeDocumentsPageState extends State<CooperativeDocumentsPage> {
  late Future<List<Map<String, dynamic>>> _documents;
  bool _uploading = false;

  bool get _canUpload => widget.role == 'committee_admin' || widget.role == 'manager';

  static const _mimeTypes = <String, String>{
    'pdf': 'application/pdf',
    'jpg': 'image/jpeg',
    'jpeg': 'image/jpeg',
    'png': 'image/png',
    'webp': 'image/webp',
    'doc': 'application/msword',
    'docx': 'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
    'xls': 'application/vnd.ms-excel',
    'xlsx': 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
  };

  @override
  void initState() {
    super.initState();
    _documents = _loadDocuments();
  }

  Future<List<Map<String, dynamic>>> _loadDocuments() async {
    final rows = await Supabase.instance.client
        .from('cooperative_documents')
        .select('id,title,document_type,storage_path,mime_type,file_size_bytes,visibility,created_at')
        .eq('organization_id', widget.organizationId)
        .order('created_at', ascending: false);
    return List<Map<String, dynamic>>.from(rows);
  }

  void _refresh() => setState(() => _documents = _loadDocuments());

  Future<void> _uploadDocument() async {
    final picked = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: _mimeTypes.keys.toList(),
      allowMultiple: false,
      withData: true,
    );
    if (picked == null || picked.files.isEmpty || !mounted) return;

    final file = picked.files.single;
    final bytes = file.bytes;
    final extension = (file.extension ?? '').toLowerCase();
    final mime = _mimeTypes[extension];
    if (bytes == null || bytes.isEmpty || bytes.length > 20 * 1024 * 1024 || mime == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Supported file দিন; সর্বোচ্চ size 20 MB।')),
      );
      return;
    }

    final titleController = TextEditingController(
      text: file.name.replaceFirst(RegExp(r'\\.[^.]+$'), ''),
    );
    final typeController = TextEditingController(text: 'সাধারণ নথি');
    var visibility = 'committee';
    final formKey = GlobalKey<FormState>();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('নথির তথ্য'),
          content: Form(
            key: formKey,
            child: SingleChildScrollView(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Text(file.name, maxLines: 2, overflow: TextOverflow.ellipsis),
                TextFormField(
                  controller: titleController,
                  decoration: const InputDecoration(labelText: 'নথির শিরোনাম'),
                  validator: (value) => value == null || value.trim().length < 2
                      ? 'কমপক্ষে ২ অক্ষরের শিরোনাম দিন।' : null,
                ),
                const SizedBox(height: 10),
                TextFormField(
                  controller: typeController,
                  decoration: const InputDecoration(labelText: 'নথির ধরন'),
                  validator: (value) => value == null || value.trim().length < 2
                      ? 'নথির ধরন লিখুন।' : null,
                ),
                const SizedBox(height: 10),
                DropdownButtonFormField<String>(
                  initialValue: visibility,
                  decoration: const InputDecoration(labelText: 'কারা দেখতে পারবেন'),
                  items: const [
                    DropdownMenuItem(value: 'committee', child: Text('সমিতির সক্রিয় সদস্য')),
                    DropdownMenuItem(value: 'managers', child: Text('শুধু ব্যবস্থাপনা ও নিরীক্ষক')),
                  ],
                  onChanged: (value) => setDialogState(() => visibility = value ?? 'committee'),
                ),
              ]),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('বাতিল')),
            FilledButton(
              onPressed: () {
                if (formKey.currentState!.validate()) Navigator.pop(dialogContext, true);
              },
              child: const Text('Upload'),
            ),
          ],
        ),
      ),
    );
    if (confirmed != true || !mounted) {
      titleController.dispose();
      typeController.dispose();
      return;
    }

    setState(() => _uploading = true);
    final client = Supabase.instance.client;
    final userId = client.auth.currentUser?.id;
    final path = '${widget.organizationId}/$userId/${DateTime.now().microsecondsSinceEpoch}.$extension';
    var uploaded = false;
    try {
      if (userId == null) throw Exception('Login session পাওয়া যায়নি।');
      await client.storage.from('cooperative-documents').uploadBinary(
        path,
        bytes,
        fileOptions: FileOptions(contentType: mime, upsert: false),
      );
      uploaded = true;
      await client.from('cooperative_documents').insert({
        'organization_id': widget.organizationId,
        'title': titleController.text.trim(),
        'document_type': typeController.text.trim(),
        'storage_path': path,
        'mime_type': mime,
        'file_size_bytes': bytes.length,
        'visibility': visibility,
        'uploaded_by': userId,
      });
      if (!mounted) return;
      _refresh();
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('নথি নিরাপদভাবে সংরক্ষণ হয়েছে।')));
    } catch (e) {
      if (uploaded) {
        try {
          await client.storage.from('cooperative-documents').remove([path]);
        } catch (_) {}
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('নথি সংরক্ষণ হয়নি: $e')));
      }
    } finally {
      titleController.dispose();
      typeController.dispose();
      if (mounted) setState(() => _uploading = false);
    }
  }

  Future<void> _openDocument(Map<String, dynamic> document) async {
    try {
      final signed = await Supabase.instance.client.storage
          .from('cooperative-documents')
          .createSignedUrl(document['storage_path'].toString(), 300);
      final uri = Uri.parse(signed);
      if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
        throw Exception('এই ডিভাইসে ফাইল খোলার app পাওয়া যায়নি।');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('নথি খোলা যায়নি: $e')));
      }
    }
  }

  String _sizeLabel(Object? value) {
    final bytes = (value as num?)?.toInt() ?? 0;
    if (bytes >= 1024 * 1024) return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    return '${(bytes / 1024).toStringAsFixed(0)} KB';
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('সমিতির নথিপত্র')),
    floatingActionButton: _canUpload
        ? FloatingActionButton.extended(
            onPressed: _uploading ? null : _uploadDocument,
            icon: _uploading
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.upload_file),
            label: Text(_uploading ? 'Upload হচ্ছে' : 'নথি Upload'),
          )
        : null,
    body: RefreshIndicator(
      onRefresh: () async => _refresh(),
      child: FutureBuilder<List<Map<String, dynamic>>>(
        future: _documents,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return ListView(children: [
              const SizedBox(height: 100),
              Center(child: Text('নথি লোড হয়নি: ${snapshot.error}')),
            ]);
          }
          final documents = snapshot.data ?? [];
          if (documents.isEmpty) {
            return ListView(children: const [
              SizedBox(height: 100),
              Icon(Icons.folder_open_outlined, size: 56, color: Colors.grey),
              SizedBox(height: 12),
              Center(child: Text('এখনো কোনো নথি সংরক্ষণ করা হয়নি।')),
            ]);
          }
          return ListView.separated(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 96),
            itemCount: documents.length,
            separatorBuilder: (_, __) => const SizedBox(height: 6),
            itemBuilder: (context, index) {
              final item = documents[index];
              final date = DateTime.tryParse(item['created_at'].toString())?.toLocal();
              final dateLabel = date == null
                  ? '' : '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}';
              return Card(
                child: ListTile(
                  leading: const CircleAvatar(child: Icon(Icons.description_outlined)),
                  title: Text(item['title'].toString()),
                  subtitle: Text('${item['document_type']} · ${_sizeLabel(item['file_size_bytes'])} · $dateLabel\n'
                      '${item['visibility'] == 'managers' ? 'ব্যবস্থাপনা-সীমিত' : 'কমিটি'}'),
                  isThreeLine: true,
                  trailing: const Icon(Icons.open_in_new),
                  onTap: () => _openDocument(item),
                ),
              );
            },
          );
        },
      ),
    ),
  );
}
