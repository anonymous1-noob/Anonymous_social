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

  String? helperText;

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
                  DropdownMenuItem(value: 'harassment', child: Text('Harassment / Bullying')),
                  DropdownMenuItem(value: 'threats', child: Text('Threats / Violence')),
                  DropdownMenuItem(value: 'hate', child: Text('Hate speech')),
                  DropdownMenuItem(value: 'sexual', child: Text('Sexual content')),
                  DropdownMenuItem(value: 'self_harm', child: Text('Self-harm / Suicide')),
                  DropdownMenuItem(value: 'privacy', child: Text('Privacy / Doxxing')),
                  DropdownMenuItem(value: 'illegal', child: Text('Illegal / Drugs / Weapons')),
                  DropdownMenuItem(value: 'misinformation', child: Text('Misinformation')),
                  DropdownMenuItem(value: 'other', child: Text('Other')),
                ],
                onChanged: (v) {
                  if (v == null) return;
                  setState(() {
                    reason = v;
                    helperText = (reason == 'self_harm')
                        ? 'If someone is in immediate danger, contact local emergency services or a trusted adult/counselor.'
                        : null;
                  });
                },
                decoration: const InputDecoration(labelText: 'Reason'),
              ),
              if (helperText != null) ...[
                const SizedBox(height: 10),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.orange.withOpacity(0.10),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.orange.withOpacity(0.35)),
                  ),
                  child: Text(
                    helperText!,
                    style: const TextStyle(fontSize: 12, height: 1.25),
                  ),
                ),
              ],
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
