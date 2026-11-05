import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:zest/app/data/db.dart';
import 'package:zest/kodo/store.dart';
import 'package:zest/kodo/session.dart';

class KodoAttachmentLinks extends StatelessWidget {
  final Todos todo;
  const KodoAttachmentLinks({super.key, required this.todo});
  @override
  Widget build(BuildContext context) {
    final attached = KodoStore.instance.files[todo.remoteKey] ?? [];
    final urls = RegExp(
      r'https?://[^\s<>]+',
    ).allMatches(todo.description).map((m) => m.group(0)!).toSet();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final link in urls)
          TextButton.icon(
            onPressed: () => launchUrl(
              Uri.parse(link),
              mode: LaunchMode.externalApplication,
            ),
            icon: const Icon(Icons.open_in_new, size: 18),
            label: Text(link, maxLines: 2, overflow: TextOverflow.ellipsis),
          ),
        for (final file in attached)
          TextButton.icon(
            onPressed: () async {
              try {
                final url = await Supabase.instance.client.storage
                    .from('portal-documents')
                    .createSignedUrl(file['path'] as String, 60);
                await launchUrl(
                  Uri.parse(url),
                  mode: LaunchMode.externalApplication,
                );
              } catch (e) {
                if (context.mounted) {
                  ScaffoldMessenger.of(
                    context,
                  ).showSnackBar(SnackBar(content: Text(readableKodoError(e))));
                }
              }
            },
            icon: const Icon(Icons.attach_file, size: 18),
            label: Text(file['name'] as String),
          ),
      ],
    );
  }
}
