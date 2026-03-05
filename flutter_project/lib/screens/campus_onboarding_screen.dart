import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'home_shell.dart';

/// Campus selection screen.
///
/// Supports:
/// - Selecting multiple campuses (user_campuses join table)
/// - Skipping campus entirely (Public-only feed)
/// - Manage mode after login (update selection any time)
///
/// Recommended schema:
/// - campuses(id uuid/text, name text)
/// - users(auth_id text, onboarding_done boolean)
/// - user_campuses(auth_id text, campus_id uuid/text)
class CampusOnboardingScreen extends StatefulWidget {
  final bool manageMode;

  const CampusOnboardingScreen({super.key, this.manageMode = false});

  @override
  State<CampusOnboardingScreen> createState() => _CampusOnboardingScreenState();
}

class _CampusOnboardingScreenState extends State<CampusOnboardingScreen> {
  final _client = Supabase.instance.client;
  final _search = TextEditingController();

  bool _loading = false;
  String? _error;
  List<Map<String, dynamic>> _campuses = [];
  final Set<String> _selectedCampusIds = {};

  @override
  void initState() {
    super.initState();
    _loadCampuses();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _loadCampuses() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final res = await _client.from('campuses').select('id, name').order('name');
      _campuses = (res as List).cast<Map<String, dynamic>>();

      // Preselect existing campuses (manage mode) or if user already picked before.
      await _loadMySelections();
    } on PostgrestException catch (e) {
      _error = e.message;
      _campuses = [];
    } catch (_) {
      _error = 'Could not load campuses.';
      _campuses = [];
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _loadMySelections() async {
    final me = _client.auth.currentUser?.id;
    if (me == null) return;

    try {
      final rows = await _client.from('user_campuses').select('campus_id').eq('auth_id', me);
      final ids = <String>{};
      for (final r in (rows as List)) {
        final m = r as Map;
        final cid = (m['campus_id'] ?? '').toString().trim();
        if (cid.isNotEmpty) ids.add(cid);
      }
      if (!mounted) return;
      setState(() {
        _selectedCampusIds
          ..clear()
          ..addAll(ids);
      });
    } catch (_) {
      // If join table doesn't exist yet, ignore.
    }
  }

  void _toggleCampus(String id) {
    setState(() {
      if (_selectedCampusIds.contains(id)) {
        _selectedCampusIds.remove(id);
      } else {
        _selectedCampusIds.add(id);
      }
    });
  }

  Future<void> _saveSelection({required bool publicOnly}) async {
    final user = _client.auth.currentUser;
    if (user == null) return;

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      // Mark onboarding done (even if user skips campus).
      // In manageMode, keep it true if it already is.
      try {
        await _client.from('users').update({'onboarding_done': true}).eq('auth_id', user.id);
      } catch (_) {
        // ignore if schema doesn't have users/onboarding_done
      }

      // Update multi-campus selection (best-effort).
      try {
        await _client.from('user_campuses').delete().eq('auth_id', user.id);

        if (!publicOnly && _selectedCampusIds.isNotEmpty) {
          final rows = _selectedCampusIds.map((cid) => {'auth_id': user.id, 'campus_id': cid}).toList();
          await _client.from('user_campuses').insert(rows);
        }
      } catch (_) {
        // ignore if join table isn't there
      }

      if (!mounted) return;

      if (widget.manageMode) {
        Navigator.of(context).pop(true);
      } else {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => const HomeShell(categoryId: 0)),
        );
      }
    } on PostgrestException catch (e) {
      if (!mounted) return;
      setState(() => _error = e.message);
    } catch (_) {
      if (!mounted) return;
      setState(() => _error = 'Failed to save selection.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final q = _search.text.trim().toLowerCase();
    final filtered = _campuses.where((c) {
      final name = (c['name'] ?? '').toString().toLowerCase();
      return q.isEmpty || name.contains(q);
    }).toList();

    final title = widget.manageMode ? 'Select campuses' : 'Choose your campus';

    return Scaffold(
      backgroundColor: const Color(0xFFF3F4F6),
      appBar: AppBar(
        title: Text(title),
        leading: widget.manageMode ? const BackButton() : null,
        actions: [
          TextButton(
            onPressed: _loading ? null : () => _saveSelection(publicOnly: true),
            child: const Text('Public only'),
          ),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 680),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  widget.manageMode
                      ? 'Pick campuses you want in your feed.\nYour feed will show posts from selected campuses + public posts.'
                      : 'Pick one or more campuses (you can also use Public-only).\nYour feed will show posts from selected campuses + public posts.',
                  style: const TextStyle(color: Colors.black54, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _search,
                  onChanged: (_) => setState(() {}),
                  decoration: InputDecoration(
                    hintText: 'Search campus…',
                    prefixIcon: const Icon(Icons.search),
                    filled: true,
                    fillColor: Colors.white,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                if (_loading) const LinearProgressIndicator(minHeight: 2),
                if (_error != null) ...[
                  const SizedBox(height: 10),
                  Text(
                    _error!,
                    style: TextStyle(color: Theme.of(context).colorScheme.error),
                  ),
                ],
                const SizedBox(height: 12),
                Expanded(
                  child: _campuses.isEmpty && !_loading
                      ? const Center(
                          child: Text(
                            'No campus list found yet.\nYou can continue with Public-only.',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: Colors.black54),
                          ),
                        )
                      : ListView.separated(
                          itemCount: filtered.length,
                          separatorBuilder: (_, __) => const SizedBox(height: 10),
                          itemBuilder: (context, i) {
                            final c = filtered[i];
                            final id = (c['id'] ?? '').toString();
                            final name = (c['name'] ?? '').toString();
                            final selected = _selectedCampusIds.contains(id);

                            return Material(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(16),
                              child: InkWell(
                                borderRadius: BorderRadius.circular(16),
                                onTap: _loading || id.isEmpty ? null : () => _toggleCampus(id),
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                                  child: Row(
                                    children: [
                                      Icon(
                                        selected ? Icons.check_circle : Icons.school_outlined,
                                        color: selected ? Colors.green : Colors.black87,
                                      ),
                                      const SizedBox(width: 10),
                                      Expanded(
                                        child: Text(
                                          name,
                                          style: const TextStyle(fontWeight: FontWeight.w800),
                                        ),
                                      ),
                                      if (selected) const Icon(Icons.check, color: Colors.green),
                                    ],
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  height: 48,
                  child: FilledButton(
                    onPressed: _loading ? null : () => _saveSelection(publicOnly: _selectedCampusIds.isEmpty),
                    child: Text(
                      widget.manageMode
                          ? (_selectedCampusIds.isEmpty ? 'Save (Public only)' : 'Save (${_selectedCampusIds.length} selected)')
                          : (_selectedCampusIds.isEmpty ? 'Continue (Public only)' : 'Continue (${_selectedCampusIds.length} selected)'),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
