import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class NotificationsScreen extends StatelessWidget {
  final supabase = Supabase.instance.client;

  NotificationsScreen({super.key});

  String _label(Map<String, dynamic> n) {
    switch (n['type']) {
      case 'post_like':
        return 'liked your post';
      case 'post_comment':
        return 'commented on your post';
      case 'comment_reply':
        return 'replied to your comment';
      default:
        return 'activity';
    }
  }

  String _timeAgo(String ts) {
    final d = DateTime.parse(ts).toLocal();
    final diff = DateTime.now().difference(d);

    if (diff.inSeconds < 60) return 'now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m';
    if (diff.inHours < 24) return '${diff.inHours}h';
    return '${diff.inDays}d';
  }

  @override
  Widget build(BuildContext context) {
    final stream = supabase
        .from('notifications')
        .stream(primaryKey: ['id'])
        .order('created_at', ascending: false);

    return Scaffold(
      appBar: AppBar(title: const Text('Notifications')),
      body: StreamBuilder<List<Map<String, dynamic>>>(
        stream: stream,
        builder: (context, snap) {
          if (!snap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final items = snap.data!;
          if (items.isEmpty) {
            return const Center(child: Text('No notifications yet'));
          }

          return ListView.builder(
            itemCount: items.length,
            itemBuilder: (context, i) {
              final n = items[i];
              final unread = n['is_read'] == false;

              return ListTile(
                leading: Icon(
                  Icons.notifications,
                  color: unread ? Colors.blue : Colors.grey,
                ),
                title: Text(
                  _label(n),
                  style: TextStyle(
                    fontWeight: unread ? FontWeight.bold : FontWeight.normal,
                  ),
                ),
                subtitle: Text(_timeAgo(n['created_at'])),
                onTap: () async {
                  await supabase
                      .from('notifications')
                      .update({'is_read': true})
                      .eq('id', n['id']);

                  Navigator.pop(context);
                },
              );
            },
          );
        },
      ),
    );
  }
}
