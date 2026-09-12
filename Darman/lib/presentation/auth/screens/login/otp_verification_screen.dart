import 'dart:async';
import 'dart:ui' as ui;

import 'package:darmaan/core/utils/auth_navigator.dart';
import 'package:darmaan/core/utils/phone_number_formatter.dart';
import 'package:darmaan/presentation/auth/repository/login/phone_auth_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

class OtpVerificationScreen extends StatefulWidget {
  final String phoneNumber;

  const OtpVerificationScreen({super.key, required this.phoneNumber});

  @override
  State<OtpVerificationScreen> createState() => _OtpVerificationScreenState();
}

class _OtpVerificationScreenState extends State<OtpVerificationScreen> {
  final PhoneAuthRepository _repo = PhoneAuthRepository();

  static const int _otpLength = 6;

  final List<TextEditingController> _controllers =
      List.generate(_otpLength, (_) => TextEditingController());
  final List<FocusNode> _focusNodes =
      List.generate(_otpLength, (_) => FocusNode());

  bool _verifying = false;
  bool _resending = false;
  int _resendCooldown = 60;
  String? _inlineError;
  bool _shaking = false;

  // ---- Palette (kept consistent with the rest of the app) --------------
  static const Color _primary = Color(0xFF2D6CDF);
  static const Color _primaryDark = Color(0xFF1E52B8);
  static const Color _textColorDark = Color(0xFF13161A);

  /// Snapshot of whatever was in the clipboard when this screen opened.
  /// We ignore this value and only autofill when something NEW appears.
  String _clipboardSnapshotOnEntry = '';

  _AppLifecycleObserver? _lifecycleObserver;

  @override
  void initState() {
    super.initState();
    _tickCooldown();
    _initClipboardListener();
    WidgetsBinding.instance
        .addPostFrameCallback((_) => _focusNodes.first.requestFocus());
  }

  // ── Clipboard handling ────────────────────────────────────────────────

  /// On init: record whatever is already in the clipboard so we can ignore it.
  /// Then start watching for new content when the app comes back to foreground.
  Future<void> _initClipboardListener() async {
    try {
      final data = await Clipboard.getData(Clipboard.kTextPlain);
      _clipboardSnapshotOnEntry = data?.text?.trim() ?? '';
    } catch (_) {
      _clipboardSnapshotOnEntry = '';
    }

    _lifecycleObserver = _AppLifecycleObserver(_checkClipboardForNew);
    WidgetsBinding.instance.addObserver(_lifecycleObserver!);
  }

  /// Called every time the app resumes from background.
  /// Only autofills if the clipboard contains something DIFFERENT from
  /// what was there when the screen first opened.
  Future<void> _checkClipboardForNew() async {
    if (!mounted) return;
    try {
      final data = await Clipboard.getData(Clipboard.kTextPlain);
      final current = data?.text?.trim() ?? '';

      if (current == _clipboardSnapshotOnEntry) return;

      final match = RegExp(r'\b(\d{6})\b').firstMatch(current);
      if (match != null) {
        final code = match.group(1)!;
        if (mounted) _autoFill(code);
      }
    } catch (_) {
      // Clipboard access can fail silently — never crash the screen.
    }
  }

  void _autoFill(String code, {bool replaceExisting = false}) {
    if (code.length != _otpLength) return;

    // Only autofill if the boxes are currently empty so we never overwrite
    // something the user has already started typing manually.
    if (!replaceExisting && _currentOtp.isNotEmpty) return;

    for (int i = 0; i < _otpLength; i++) {
      _controllers[i].text = code[i];
    }

    setState(() => _inlineError = null);

    Future.delayed(const Duration(milliseconds: 300), () {
      if (mounted) _verifyOtp();
    });
  }

  @override
  void dispose() {
    if (_lifecycleObserver != null) {
      WidgetsBinding.instance.removeObserver(_lifecycleObserver!);
    }
    for (final c in _controllers) {
      c.dispose();
    }
    for (final f in _focusNodes) {
      f.dispose();
    }
    super.dispose();
  }

  // ── Cooldown timer ────────────────────────────────────────────────────

  void _tickCooldown() {
    if (!mounted || _resendCooldown <= 0) return;
    Future.delayed(const Duration(seconds: 1), () {
      if (!mounted) return;
      setState(() => _resendCooldown--);
      _tickCooldown();
    });
  }

  // ── Resend OTP ────────────────────────────────────────────────────────

  Future<void> _resendOtp() async {
    if (_resending || _resendCooldown > 0) return;
    setState(() {
      _resending = true;
      _inlineError = null;
    });

    try {
      await _repo.sendOtp(phoneNumber: widget.phoneNumber);
      if (!mounted) return;

      // Keep the current clipboard as the baseline. Otherwise an old copied
      // OTP could be treated as new after resend and consume another attempt.
      try {
        final clipboard = await Clipboard.getData(Clipboard.kTextPlain);
        _clipboardSnapshotOnEntry = clipboard?.text?.trim() ?? '';
      } catch (_) {
        _clipboardSnapshotOnEntry = '';
      }

      setState(() => _resendCooldown = 60);
      _tickCooldown();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('A new code was sent on WhatsApp.'),
          backgroundColor: Colors.green,
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _inlineError = _messageForError(e));
    } finally {
      if (mounted) setState(() => _resending = false);
    }
  }

  // ── Verify OTP ──────────────────────────────────────────────────────────

  String get _currentOtp => _controllers.map((c) => c.text).join();

  Future<void> _verifyOtp() async {
    if (_verifying) return;
    if (_currentOtp.length != _otpLength) return;

    setState(() {
      _verifying = true;
      _inlineError = null;
    });
    FocusScope.of(context).unfocus();

    try {
      await _repo.verifyOtp(
        phoneNumber: widget.phoneNumber,
        otp: _currentOtp,
      );

      if (!mounted) return;
      await AuthNavigator.goToCorrectScreen(context);
    } catch (error) {
      if (!mounted) return;

      String code = error.toString();
      while (code.startsWith('Exception: ')) {
        code = code.substring('Exception: '.length);
      }

      final message = _messageForError(code);
      setState(() => _inlineError = message);
      await _shakeAndClear(code);
    } finally {
      if (mounted) setState(() => _verifying = false);
    }
  }

  String _messageForError(Object error) {
    final code = error.toString().replaceFirst('Exception: ', '');
    switch (code) {
      case 'otp_invalid':
        return 'The code is incorrect. Please try again.';
      case 'otp_expired':
        return 'This code has expired. Request a new code.';
      case 'max_attempts_reached':
        return 'Too many attempts. Please try again later.';
      case 'invalid_session':
        return 'The login session could not be created.';
      default:
        return 'Verification failed. Please try again.';
    }
  }

  Future<void> _shakeAndClear(String code) async {
    setState(() => _shaking = true);
    await Future.delayed(const Duration(milliseconds: 400));
    if (!mounted) return;
    setState(() => _shaking = false);

    const clearOnError = {'otp_invalid', 'otp_expired', 'max_attempts_reached'};
    if (clearOnError.contains(code)) {
      _clearOtp();
    }
  }

  void _clearOtp() {
    for (final c in _controllers) {
      c.clear();
    }
    if (mounted) {
      _focusNodes.first.requestFocus();
      setState(() {});
    }
  }

  // ── Resend button ───────────────────────────────────────────────────────

  Widget _buildResendButton() {
    if (_resending) {
      return const SizedBox(
        width: 20,
        height: 20,
        child: CircularProgressIndicator(strokeWidth: 2, color: _primary),
      );
    }

    if (_resendCooldown > 0) {
      return Container(
        width: 52,
        height: 52,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: Colors.grey.shade100,
        ),
        child: Center(
          child: Text(
            _resendCooldown.toString().padLeft(2, '0'),
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w500,
              color: _textColorDark,
              height: 1,
            ),
          ),
        ),
      );
    }

    return GestureDetector(
      onTap: _resendOtp,
      child: const Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.refresh_rounded, size: 22, color: _textColorDark),
          SizedBox(height: 4),
          Text(
            'Resend code',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w500,
              color: _textColorDark,
            ),
          ),
        ],
      ),
    );
  }

  // ── UI ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(height: 40.h),

            Padding(
              padding: EdgeInsets.symmetric(horizontal: 24.w),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Enter your code',
                    style: TextStyle(
                      fontSize: 22.sp,
                      fontWeight: FontWeight.w500,
                      color: _textColorDark,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'A code was sent to ${formatLocalPhoneNumber(widget.phoneNumber)}',
                    style: TextStyle(
                      fontSize: 14.sp,
                      color: Colors.grey.shade600,
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 28),

            // ── OTP boxes with shake ────────────────────────────────────
            AnimatedContainer(
              duration: const Duration(milliseconds: 80),
              transform: Matrix4.translationValues(
                _shaking ? 8.0 : 0.0,
                0,
                0,
              ),
                child: Padding(
                padding: EdgeInsets.symmetric(horizontal: 24.w),
                child: Directionality(
                  textDirection: ui.TextDirection.ltr,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: List.generate(_otpLength, _buildOtpBox),
                  ),
                ),
              ),
            ),

            const SizedBox(height: 12),

            // ── Inline error ────────────────────────────────────────────
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 200),
              child: _inlineError != null
                  ? Padding(
                      key: ValueKey(_inlineError),
                      padding: const EdgeInsets.symmetric(horizontal: 24),
                      child: Row(
                        children: [
                          Icon(Icons.error_outline,
                              size: 14, color: Colors.red.shade600),
                          const SizedBox(width: 6),
                          Flexible(
                            child: Text(
                              _inlineError!,
                              style: TextStyle(
                                fontSize: 13,
                                color: Colors.red.shade600,
                              ),
                            ),
                          ),
                        ],
                      ),
                    )
                  : const SizedBox(key: ValueKey('no_error'), height: 20),
            ),

            const SizedBox(height: 8),

            if (_verifying)
              const Center(
                child: CircularProgressIndicator(
                  color: _primary,
                  strokeWidth: 2,
                ),
              ),

            const SizedBox(height: 8),

            // ── Resend ────────────────────────────────────────────────
            Center(child: _buildResendButton()),

            const Spacer(),
          ],
        ),
      ),
    );
  }

  Widget _buildOtpBox(int index) {
    final isFilled = _controllers[index].text.isNotEmpty;
    final hasError = _inlineError != null;

    return Container(
      width: 50.w,
      height: 50.w,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: isFilled && !hasError
            ? const LinearGradient(
                colors: [_primary, _primaryDark],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              )
            : null,
        color: hasError
            ? Colors.red.shade50
            : isFilled
                ? null
                : Colors.grey.shade100,
        border: hasError
            ? Border.all(color: Colors.red.shade300, width: 1.5)
            : null,
      ),
      child: Center(
        child: TextField(
          controller: _controllers[index],
          focusNode: _focusNodes[index],
          keyboardType: TextInputType.number,
          autofillHints: const [AutofillHints.oneTimeCode],
          textDirection: ui.TextDirection.ltr,
          maxLength: _otpLength,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 20.sp,
            fontWeight: FontWeight.w500,
            color: hasError ? Colors.red.shade700 : Colors.white,
          ),
          inputFormatters: [
            FilteringTextInputFormatter.digitsOnly,
            LengthLimitingTextInputFormatter(_otpLength),
          ],
          decoration: const InputDecoration(
            counterText: '',
            border: InputBorder.none,
            isDense: true,
            contentPadding: EdgeInsets.zero,
          ),
          onChanged: (value) {
            if (_inlineError != null) setState(() => _inlineError = null);

            // Handle paste: if 6 digits land in one box, distribute them all.
            if (value.length == _otpLength &&
                RegExp(r'^\d{6}$').hasMatch(value)) {
              _autoFill(value, replaceExisting: true);
              return;
            }

            setState(() {});

            if (value.isNotEmpty) {
              if (index < _otpLength - 1) {
                _focusNodes[index + 1].requestFocus();
              }
              if (index == _otpLength - 1 && !_verifying) {
                _verifyOtp();
              }
            } else {
              if (index > 0) {
                _focusNodes[index - 1].requestFocus();
              }
            }
          },
        ),
      ),
    );
  }
}

// ── App lifecycle observer ──────────────────────────────────────────────

class _AppLifecycleObserver extends WidgetsBindingObserver {
  final VoidCallback onResume;
  _AppLifecycleObserver(this.onResume);

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) onResume();
  }
}
