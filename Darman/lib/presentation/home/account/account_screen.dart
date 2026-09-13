import 'package:darmaan/core/models/user_model.dart';
import 'package:darmaan/core/theme/app_colors.dart';
import 'package:darmaan/core/utils/account_deletion_request.dart';
import 'package:flutter/material.dart';
import 'package:darmaan/widgets/app_icon.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';

class AccountScreen extends StatelessWidget {
  const AccountScreen({
    super.key,
    required this.user,
    required this.onLogout,
    this.isLoggingOut = false,
  });

  final UserModel user;
  final Future<void> Function() onLogout;
  final bool isLoggingOut;

  Future<void> _openWhatsAppSupport(BuildContext context) async {
    const phoneNumber = '923335540708'; // 03335540708 in international format
    final messenger = ScaffoldMessenger.of(context);
    final uri = Uri.parse('https://wa.me/$phoneNumber');
    try {
      final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (opened) return;
    } catch (_) {
      // The message below handles devices without WhatsApp installed as well.
    }
    if (context.mounted) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Unable to open WhatsApp.')),
      );
    }
  }

  Future<void> _openLegalPage(BuildContext context, String url) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final opened = await launchUrl(
        Uri.parse(url),
        mode: LaunchMode.externalApplication,
      );
      if (opened) return;
    } catch (_) {
      // The message below handles devices without a browser as well.
    }
    if (context.mounted) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Unable to open this page.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final accountType = user.role == UserRole.doctor ? 'Doctor' : 'Patient';

    return Scaffold(
      backgroundColor: const Color(0xFFF6F7F9),
      appBar: AppBar(
        backgroundColor: const Color(0xFFF6F7F9),
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        title: Text(
          'Account',
          style: GoogleFonts.outfit(
            fontSize: 20,
            fontWeight: FontWeight.w500,
            letterSpacing: -0.4,
            color: AppColors.textPrimary,
          ),
        ),
      ),
      body: SafeArea(
        top: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
          children: [
            Text(
              'ACCOUNT MANAGEMENT',
              style: GoogleFonts.outfit(
                fontSize: 11.5,
                fontWeight: FontWeight.w500,
                letterSpacing: 0.4,
                color: AppColors.textSecondary.withValues(alpha: 0.75),
              ),
            ),
            const SizedBox(height: 10),
            _LegalLinkButton(
              icon: Icons.support_agent_rounded,
              title: 'Support',
              subtitle: 'Chat with us on WhatsApp',
              onTap: () => _openWhatsAppSupport(context),
            ),
            const SizedBox(height: 10),
            _LegalLinkButton(
              icon: Icons.privacy_tip_outlined,
              title: 'Privacy Policy',
              subtitle: 'Read how Darman handles your data',
              onTap: () => _openLegalPage(
                context,
                'https://darman-web.vercel.app/privacy-policy',
              ),
            ),
            const SizedBox(height: 10),
            _LegalLinkButton(
              icon: Icons.description_outlined,
              title: 'Terms and Conditions',
              subtitle: 'Read the terms for using Darman',
              onTap: () => _openLegalPage(
                context,
                'https://darman-web.vercel.app/terms-and-conditions',
              ),
            ),
            const SizedBox(height: 10),
            Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(18),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.025),
                    blurRadius: 12,
                    offset: const Offset(0, 3),
                  ),
                ],
              ),
              clipBehavior: Clip.antiAlias,
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: isLoggingOut ? null : onLogout,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 15,
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 38,
                          height: 38,
                          decoration: BoxDecoration(
                            color: const Color(0xFFF1F3F5),
                            borderRadius: BorderRadius.circular(11),
                          ),
                          child: const AppIcon(
                            Icons.logout_rounded,
                            color: Color(0xFF344054),
                            size: 19,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                isLoggingOut ? 'Signing out…' : 'Sign out',
                                style: GoogleFonts.outfit(
                                  fontSize: 13.5,
                                  fontWeight: FontWeight.w500,
                                  color: AppColors.textPrimary,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                'Sign out securely from this device',
                                style: GoogleFonts.outfit(
                                  fontSize: 10.5,
                                  color: AppColors.textSecondary,
                                ),
                              ),
                            ],
                          ),
                        ),
                        if (isLoggingOut)
                          const SizedBox.square(
                            dimension: 17,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Color(0xFF344054),
                            ),
                          )
                        else
                          AppIcon(
                            Icons.chevron_right_rounded,
                            size: 20,
                            color: AppColors.textSecondary.withValues(
                              alpha: 0.55,
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 10),
            Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(18),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.025),
                    blurRadius: 12,
                    offset: const Offset(0, 3),
                  ),
                ],
              ),
              clipBehavior: Clip.antiAlias,
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: () => requestAccountDeletion(
                    context,
                    accountType: accountType,
                    fullName: user.name,
                    phoneNumber: user.phone,
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 15,
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 38,
                          height: 38,
                          decoration: BoxDecoration(
                            color: const Color(0xFFFFF0EE),
                            borderRadius: BorderRadius.circular(11),
                          ),
                          child: const AppIcon(
                            Icons.delete_outline_rounded,
                            color: Color(0xFFB42318),
                            size: 19,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Delete account',
                                style: GoogleFonts.outfit(
                                  fontSize: 13.5,
                                  fontWeight: FontWeight.w500,
                                  color: const Color(0xFFB42318),
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                'Request permanent account deletion',
                                style: GoogleFonts.outfit(
                                  fontSize: 10.5,
                                  color: AppColors.textSecondary,
                                ),
                              ),
                            ],
                          ),
                        ),
                        AppIcon(
                          Icons.chevron_right_rounded,
                          size: 20,
                          color: AppColors.textSecondary.withValues(alpha: 0.55),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 14),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6),
              child: Text(
                'Darman verifies account ownership before processing a deletion request. Deletion is permanent once completed.',
                style: GoogleFonts.outfit(
                  fontSize: 11.5,
                  height: 1.5,
                  color: AppColors.textSecondary,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LegalLinkButton extends StatelessWidget {
  const _LegalLinkButton({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.025),
            blurRadius: 12,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
            child: Row(
              children: [
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: const Color(0xFFF1F3F5),
                    borderRadius: BorderRadius.circular(11),
                  ),
                  child: AppIcon(icon, color: const Color(0xFF344054), size: 19),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: GoogleFonts.outfit(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w500,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        style: GoogleFonts.outfit(
                          fontSize: 10.5,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
                AppIcon(
                  Icons.open_in_new_rounded,
                  size: 18,
                  color: AppColors.textSecondary.withValues(alpha: 0.55),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}