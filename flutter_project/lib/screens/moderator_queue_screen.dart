import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class ModeratorQueueScreen extends StatefulWidget {
  const ModeratorQueueScreen({super.key});

  @override
  State<ModeratorQueueScreen> createState() => _ModeratorQueueScreenState();
}

class _ModeratorQueueScreenState extends State<ModeratorQueueScreen> {
  final _client = Supabase.instance.client;

  bool _loading = false;
  String? _error;
  List<Map<String, dynamic>> _reports = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      // Recommended schema: reports(id, target_type, target_id, reason, details, status, created_at)
      final res = await _client
          .from('reports')
          .select('*')
          .neq('status', 'resolved')
          .order('created_at', ascending: false)
          .limit(200);

      _reports = (res as List).cast<Map<String, dynamic>>();
    } on PostgrestException catch (e) {
      _error = e.message;
      _reports = [];
    } catch (_) {
      _error = 'Failed to load reports.';
      _reports = [];
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _resolve(String reportId) async {
    setState(() => _loading = true);
    try {
      await _client.from('reports').update({'status': 'resolved'}).eq('id', reportId);
      await _load();
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Resolve failed: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF3F4F6),
      appBar: AppBar(
        title: const Text('Moderator queue'),
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : (_error != null)
                ? ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.all(16),
                    children: [
                      Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
                      const SizedBox(height: 8),
                      const Text(
                        'Tip: ensure you have a "reports" table with a "status" column.',
                        style: TextStyle(color: Colors.black54, fontWeight: FontWeight.w600),
                      ),
                    ],
                  )
                : (_reports.isEmpty)
                    ? ListView(
                        physics: const AlwaysScrollableScrollPhysics(),
                        padding: const EdgeInsets.symmetric(vertical: 60),
                        children: const [
                          Icon(Icons.verified_outlined, size: 46, color: Colors.black38),
                          SizedBox(height: 12),
                          Center(
                            child: Text(
                              'All clear 🎉',
                              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: Colors.black54),
                            ),
                          ),
                        ],
                      )
                    : ListView.separated(
                        physics: const AlwaysScrollableScrollPhysics(),
                        padding: const EdgeInsets.fromLTRB(12, 12, 12, 18),
                        itemCount: _reports.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 10),
                        itemBuilder: (context, i) {
                          final r = _reports[i];
                          final id = (r['id'] ?? '').toString();
                          final type = (r['target_type'] ?? '').toString();
                          final targetId = (r['target_id'] ?? '').toString();
                          final reason = (r['reason'] ?? '').toString();
                          final details = (r['details'] ?? '').toString();

                          return Material(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(18),
                            child: Padding(
                              padding: const EdgeInsets.all(14),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      const Icon(Icons.flag_outlined),
                                      const SizedBox(width: 8),
                                      Text(
                                        reason.isEmpty ? 'Report' : reason,
                                        style: const TextStyle(fontWeight: FontWeight.w900),
                                      ),
                                      const Spacer(),
                                      Text(type, style: const TextStyle(color: Colors.black54, fontWeight: FontWeight.w700)),
                                    ],
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    'Target: $targetId',
                                    style: const TextStyle(color: Colors.black54, fontWeight: FontWeight.w700),
                                  ),
                                  if (details.isNotEmpty) ...[
                                    const SizedBox(height: 8),
                                    Text(details, style: const TextStyle(fontWeight: FontWeight.w600)),
                                  ],
                                  const SizedBox(height: 12),
                                  Row(
                                    children: [
                                      const Spacer(),
                                      TextButton.icon(
                                        onPressed: id.isEmpty ? null : () => _resolve(id),
                                        icon: const Icon(Icons.check_circle_outline),
                                        label: const Text('Resolve'),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
      ),
    );
  }
}
