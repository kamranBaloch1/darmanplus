import 'package:flutter/material.dart';
import 'package:darmaan/widgets/app_icon.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

const String accountDeletionSupportEmail = 'contact@findus.com.pk';

Future<void> requestAccountDeletion(
  BuildContext context, {
  required String accountType,
  required String fullName,
  String? phoneNumber,
}) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      icon: const AppIcon(
        Icons.delete_outline_rounded,
        color: Color(0xFFB42318),
      ),
      title: const Text('Request account deletion?'),
      content: const Text(
        'Account deletion is permanent. Darman will verify that you own the '
        'account before deleting eligible account data.',
        textAlign: TextAlign.center,
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext, false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(dialogContext, true),
          style: FilledButton.styleFrom(
            backgroundColor: const Color(0xFFB42318),
          ),
          child: const Text('Continue'),
        ),
      ],
    ),
  );

  if (confirmed != true || !context.mounted) return;

  final phone = phoneNumber?.trim();
  final body = <String>[
    'Hello Darman Support,',
    '',
    'I want to permanently delete my Darman account.',
    '',
    'Full name: ${fullName.trim()}',
    'Registered phone number: ${phone?.isNotEmpty == true ? phone : 'Not available'}',
    'Account type: $accountType',
    '',
    'I understand that account deletion is permanent.',
  ].join('\n');
  const subject = 'Darman account deletion request';
  final uri = Uri.parse(
    'mailto:$accountDeletionSupportEmail'
    '?subject=${Uri.encodeComponent(subject)}'
    '&body=${Uri.encodeComponent(body)}',
  );

  try {
    final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (opened || !context.mounted) return;
  } catch (_) {
    // The fallback below gives the user a usable contact when no mail app exists.
  }

  await Clipboard.setData(
    const ClipboardData(text: accountDeletionSupportEmail),
  );
  if (!context.mounted) return;
  ScaffoldMessenger.of(context).showSnackBar(
    const SnackBar(
      content: Text(
        'No email app was found. The Darman support email was copied.',
      ),
      behavior: SnackBarBehavior.floating,
    ),
  );
}