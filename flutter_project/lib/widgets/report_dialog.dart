import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

Future<void> showReportDialog({
  required BuildContext context,
  required String targetType, // 'post' or 'comment'
  required String targetId,
}) async {
  final supabase = Supabase.instance.client;

  String reason = 'spam';
  final TextEditingController descriptionCtrl = TextEditingController();
  bool submitting = false;

  await showDialog(
    context: context,
    builder: (_) => StatefulBuilder(
      builder: (context, setState) {
        return AlertDialog(
          title: const Text('Report'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<String>(
                value: reason,
                items: const [
                  DropdownMenuItem(value: 'spam', child: Text('Spam')),
                  DropdownMenuItem(value: 'abuse', child: Text('Abuse')),
                  DropdownMenuItem(value: 'hate', child: Text('Hate speech')),
                  DropdownMenuItem(value: 'misinformation', child: Text('Misinformation')),
                  DropdownMenuItem(value: 'other', child: Text('Other')),
                ],
                onChanged: (v) => setState(() => reason = v!),
                decoration: const InputDecoration(labelText: 'Reason'),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: descriptionCtrl,
                maxLines: 3,
                decoration: const InputDecoration(
                  hintText: 'Optional description',
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: submitting ? null : () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: submitting
                  ? null
                  : () async {
                      setState(() => submitting = true);
                      try {
                        await supabase.rpc(
                          'submit_report',
                          params: {
                            'target_type_input': targetType,
                            'target_id_input': targetId,
                            'reason_input': reason,
                            'description_input': descriptionCtrl.text.trim().isEmpty
                                ? null
                                : descriptionCtrl.text.trim(),
                          },
                        );

                        Navigator.pop(context);
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Report submitted')),
                        );
                      } catch (e) {
                        setState(() => submitting = false);
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text(e.toString())),
                        );
                      }
                    },
              child: submitting
                  ? const SizedBox(
                      height: 16,
                      width: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Submit'),
            ),
          ],
        );
      },
    ),
  );
}
