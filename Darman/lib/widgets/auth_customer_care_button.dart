import 'package:darmaan/core/theme/app_colors.dart';
import 'package:darmaan/widgets/app_icon.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

class AuthCustomerCareButton extends StatelessWidget {
  const AuthCustomerCareButton({super.key});

  static const _phoneNumber = '923335540708';

  Future<void> _openWhatsApp(BuildContext context) async {
    final message = Uri.encodeComponent(
      'Hello Darman Support, I need help with my account.',
    );
    try {
      final opened = await launchUrl(
        Uri.parse('https://wa.me/$_phoneNumber?text=$message'),
        mode: LaunchMode.externalApplication,
      );
      if (opened) return;
    } catch (_) {}
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Unable to open WhatsApp.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return FloatingActionButton.small(
      heroTag: null,
      tooltip: 'Customer care on WhatsApp',
      elevation: 0,
      backgroundColor: const Color(0xFFF0F4FA),
      foregroundColor: AppColors.brand,
      onPressed: () => _openWhatsApp(context),
      child: const AppIcon(Icons.support_agent_rounded, size: 22),
    );
  }
}
