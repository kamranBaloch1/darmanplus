import 'package:darmaan/presentation/auth/repository/login/phone_auth_repository.dart';
import 'package:darmaan/presentation/auth/screens/login/otp_verification_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen>
    with SingleTickerProviderStateMixin {
  final PhoneAuthRepository _phoneAuthRepository = PhoneAuthRepository();

  final TextEditingController _phoneController = TextEditingController();
  final FocusNode _phoneFocusNode = FocusNode();

  bool isLoading = false;
  bool _isPhoneValid = false;
  String? _errorText;

  late final AnimationController _entranceController;
  late final Animation<double> _fadeAnimation;
  late final Animation<Offset> _slideAnimation;

  // ---- Palette -------------------------------------------------------
  static const Color _primaryColor = Color(0xFF2D6CDF);
  static const Color _primaryDark = Color(0xFF1E52B8);
  static const Color _backgroundColor = Color(0xFFF7F9FC);
  static const Color _surfaceColor = Colors.white;
  static const Color _textColor = Color(0xFF13161A);
  static const Color _errorColor = Color(0xFFDC3545);

  // Exactly 11 digits, Pakistani mobile format: 03XXXXXXXXX
  static final RegExp _localPhoneRegex = RegExp(r'^03\d{9}$');

  @override
  void initState() {
    super.initState();

    _phoneFocusNode.addListener(() {
      if (mounted) setState(() {});
    });

    _phoneController.addListener(() {
      final digits = _phoneController.text.trim();
      final valid = _localPhoneRegex.hasMatch(digits);
      if (valid != _isPhoneValid || _errorText != null) {
        setState(() {
          _isPhoneValid = valid;
          _errorText = null;
        });
      }
    });

    _entranceController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 550),
    );
    _fadeAnimation = CurvedAnimation(
      parent: _entranceController,
      curve: Curves.easeOut,
    );
    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, 0.04),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _entranceController,
      curve: Curves.easeOutCubic,
    ));

    _entranceController.forward();
  }

  Future<void> _continueWithPhone() async {
    if (isLoading || !_isPhoneValid) return;

    FocusScope.of(context).unfocus();
    HapticFeedback.selectionClick();

    final digits = _phoneController.text.trim();
    // Convert local 03XXXXXXXXX -> +923XXXXXXXXX
    final phone = '+92${digits.substring(1)}';

    setState(() {
      isLoading = true;
      _errorText = null;
    });

    try {
      await _phoneAuthRepository.sendOtp(phoneNumber: phone);

      if (!mounted) return;

      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => OtpVerificationScreen(phoneNumber: phone),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _errorText = _messageForError(e));
    } finally {
      if (mounted) {
        setState(() => isLoading = false);
      }
    }
  }

  String _messageForError(Object error) {
    final code = error.toString().replaceFirst('Exception: ', '');

    switch (code) {
      case 'phone_not_registered_whatsapp':
        return 'This number is not available on WhatsApp.';
      case 'max_attempts_reached':
        return 'Too many attempts. Please try again later.';
      case 'invalid_phone':
        return 'Please enter a valid Pakistani mobile number.';
      default:
        return 'We could not send the code. Please try again.';
    }
  }

  @override
  void dispose() {
    _phoneController.dispose();
    _phoneFocusNode.dispose();
    _entranceController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return GestureDetector(
      onTap: () => FocusScope.of(context).unfocus(),
      child: Scaffold(
        backgroundColor: _backgroundColor,
        body: SafeArea(
          child: Align(
            alignment: Alignment.topCenter,
            child: SingleChildScrollView(
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              padding: EdgeInsets.fromLTRB(
                24.w,
                28.h,
                24.w,
                24.h + bottomInset * 0.1,
              ),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 440),
                child: FadeTransition(
                  opacity: _fadeAnimation,
                  child: SlideTransition(
                    position: _slideAnimation,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const SizedBox(height: 12),

                        // SINGLE HEADLINE
                        Text(
                          'Enter Your Whatsapp Number.',
                          textAlign: TextAlign.start,
                          style: TextStyle(
                            fontSize: 18.4.sp,
                            fontWeight: FontWeight.w500,
                            color: Colors.black87,
                            letterSpacing: -0.2,
                          ),
                        ),

                        const SizedBox(height: 24),

                        // PHONE FIELD — kept at the top of the form
                        _buildPhoneField(),

                        AnimatedSwitcher(
                          duration: const Duration(milliseconds: 180),
                          child: _errorText != null
                              ? Padding(
                                  key: ValueKey(_errorText),
                                  padding: const EdgeInsets.only(top: 10, left: 4),
                                  child: Row(
                                    children: [
                                      const Icon(
                                        Icons.error_outline_rounded,
                                        size: 15,
                                        color: _errorColor,
                                      ),
                                      const SizedBox(width: 6),
                                      Expanded(
                                        child: Text(
                                          _errorText!,
                                          style: const TextStyle(
                                            fontSize: 12.5,
                                            fontWeight: FontWeight.w500,
                                            color: _errorColor,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                )
                              : const SizedBox(
                                  key: ValueKey('empty'),
                                  height: 0,
                                ),
                        ),

                        const SizedBox(height: 24),

                        _buildContinueButton(),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

 
  Widget _buildPhoneField() {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 160),
      curve: Curves.easeOut,
      height: 58.h,
      decoration: BoxDecoration(
        color: _surfaceColor,
        borderRadius: BorderRadius.circular(16.r),
        // No border, no colored focus glow — just a subtle neutral shadow.
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Row(
        children: [
          SizedBox(width: 18.w),
 
          Expanded(
            child: TextField(
              controller: _phoneController,
              focusNode: _phoneFocusNode,
              keyboardType: TextInputType.phone,
              textInputAction: TextInputAction.done,
              autofillHints: const [AutofillHints.telephoneNumber],
              inputFormatters: [
                FilteringTextInputFormatter.digitsOnly,
                LengthLimitingTextInputFormatter(11),
              ],
              cursorColor: _primaryColor,
              style: TextStyle(
                fontSize: 16.sp,
                fontWeight: FontWeight.w500,
                color: _textColor,
                letterSpacing: 0.3,
              ),
              decoration: InputDecoration(
                border: InputBorder.none,
                isCollapsed: true,
                hintText: '03XXXXXXXXX',
                hintStyle: TextStyle(
                  fontSize: 16.sp,
                  fontWeight: FontWeight.w400,
                  color: Colors.grey.shade400,
                ),
              ),
              onSubmitted: (_) => _continueWithPhone(),
            ),
          ),
 
          SizedBox(width: 18.w),
        ],
      ),
    );
  }
 
  Widget _buildContinueButton() {
    final enabled = _isPhoneValid && !isLoading;

    return SizedBox(
        width: double.infinity,
        height: 50.h,
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            gradient: LinearGradient(
              colors: !enabled
                  ? [_primaryColor.withOpacity(0.35), _primaryColor.withOpacity(0.35)]
                  : [_primaryColor, _primaryDark],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            boxShadow: !enabled
                ? []
                : [
                    BoxShadow(
                      color: _primaryColor.withOpacity(0.28),
                      blurRadius: 16,
                      offset: const Offset(0, 8),
                    ),
                  ],
          ),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(16),
              onTap: enabled ? _continueWithPhone : null,
              child: Center(
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 180),
                  child: isLoading
                      ? const SizedBox(
                          key: ValueKey('loading'),
                          width: 21,
                          height: 21,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.2,
                            color: Colors.white,
                          ),
                        )
                      : const Text(
                          'Continue',
                          key: ValueKey('label'),
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w500,
                            color: Colors.white,
                            letterSpacing: 0.2,
                          ),
                        ),
                ),
              ),
            ),
          ),
        ),
      );
  }
}
