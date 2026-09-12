import 'dart:async';

import 'package:darmaan/core/models/wallet_top_up_model.dart';
import 'package:darmaan/core/theme/app_colors.dart';
import 'package:darmaan/presentation/home/wallet/repository/wallet_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

class AddMoneyScreen extends StatefulWidget {
  const AddMoneyScreen({
    super.key,
    required this.currentBalance,
  });

  final double currentBalance;

  @override
  State<AddMoneyScreen> createState() => _AddMoneyScreenState();
}

class _AddMoneyScreenState extends State<AddMoneyScreen>
    with WidgetsBindingObserver {
  static const _quickAmounts = <int>[500, 1000, 2000, 5000];

  final WalletRepository _repository = WalletRepository();
  final TextEditingController _amountController = TextEditingController();
  final FocusNode _amountFocus = FocusNode();
  String? _topUpRequestId;
  bool _submitting = false;
  bool _checkingStatus = false;

  int? get _amount => int.tryParse(_amountController.text.trim());
  bool get _canContinue {
    final amount = _amount ?? 0;
    return amount >= 100 && amount <= 1000000;
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _amountController.addListener(_onAmountChanged);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _amountController
      ..removeListener(_onAmountChanged)
      ..dispose();
    _amountFocus.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _topUpRequestId != null) {
      unawaited(_pollPaymentStatusAfterReturn());
    }
  }

  Future<void> _pollPaymentStatusAfterReturn() async {
    const waits = <Duration>[
      Duration(milliseconds: 450),
      Duration(seconds: 2),
      Duration(seconds: 3),
    ];
    for (final wait in waits) {
      await Future<void>.delayed(wait);
      if (!mounted || _topUpRequestId == null) return;
      await _checkPaymentStatus(silentWhilePending: true);
    }
  }

  void _onAmountChanged() {
    if (mounted) setState(() {});
  }

  void _selectAmount(int value) {
    _amountController
      ..text = value.toString()
      ..selection = TextSelection.collapsed(
        offset: value.toString().length,
      );
    _amountFocus.requestFocus();
  }

  Future<void> _continue() async {
    if (_topUpRequestId != null) {
      await _checkPaymentStatus();
      return;
    }

    FocusScope.of(context).unfocus();
    await _startJazzCashPayment();
  }

  Future<void> _startJazzCashPayment() async {
    final amount = _amount;
    if (amount == null || !_canContinue || _submitting) return;

    setState(() => _submitting = true);
    try {
      final session = await _repository.createJazzCashTopUp(amount: amount);
      if (!mounted) return;
      setState(() => _topUpRequestId = session.requestId);

      final opened = await launchUrl(
        session.checkoutUrl,
        mode: LaunchMode.externalApplication,
      );
      if (!opened) {
        setState(() => _topUpRequestId = null);
        throw const WalletException('JazzCash could not be opened.');
      }
    } catch (error) {
      if (mounted) _showError(_message(error));
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Future<void> _checkPaymentStatus({bool silentWhilePending = false}) async {
    final requestId = _topUpRequestId;
    if (requestId == null || _checkingStatus) return;

    setState(() => _checkingStatus = true);
    try {
      final result = await _repository.getTopUpStatus(requestId);
      if (!mounted) return;
      switch (result.status) {
        case WalletTopUpStatus.succeeded:
          await _showSuccess(result);
          if (mounted) Navigator.pop(context, true);
          return;
        case WalletTopUpStatus.failed:
        case WalletTopUpStatus.expired:
          setState(() => _topUpRequestId = null);
          _showError(
            result.responseMessage?.trim().isNotEmpty == true
                ? result.responseMessage!
                : 'The JazzCash payment was not completed.',
          );
          return;
        case WalletTopUpStatus.reversed:
          setState(() => _topUpRequestId = null);
          _showError(
            'JazzCash reversed this payment. Your wallet has been adjusted.',
          );
          return;
        case WalletTopUpStatus.pending:
          if (!silentWhilePending) {
            _showInfo(
              'Payment is still pending. Complete it in JazzCash, then check again.',
            );
          }
          return;
      }
    } catch (error) {
      if (mounted && !silentWhilePending) _showError(_message(error));
    } finally {
      if (mounted) setState(() => _checkingStatus = false);
    }
  }

  Future<void> _showSuccess(WalletTopUpResult result) {
    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
        contentPadding: const EdgeInsets.fromLTRB(24, 26, 24, 18),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 58,
              height: 58,
              decoration: const BoxDecoration(
                color: Color(0xFFECFDF3),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.check_rounded,
                size: 31,
                color: Color(0xFF16A34A),
              ),
            ),
            const SizedBox(height: 18),
            Text(
              'Money added',
              style: GoogleFonts.outfit(
                fontSize: 21,
                fontWeight: FontWeight.w500,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 7),
            Text(
              'Rs. ${NumberFormat('#,##0').format(result.amount)} was added to your wallet.',
              textAlign: TextAlign.center,
              style: GoogleFonts.outfit(
                fontSize: 13.5,
                height: 1.45,
                color: AppColors.textSecondary,
              ),
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: () => Navigator.pop(dialogContext),
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.brand,
                  padding: const EdgeInsets.symmetric(vertical: 13),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(13),
                  ),
                ),
                child: Text(
                  'Done',
                  style: GoogleFonts.outfit(fontWeight: FontWeight.w500),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          backgroundColor: const Color(0xFFB42318),
          content: Text(message, style: GoogleFonts.outfit()),
        ),
      );
  }

  void _showInfo(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          content: Text(message, style: GoogleFonts.outfit()),
        ),
      );
  }

  String _message(Object error) {
    if (error is WalletException) return error.message;
    return error.toString().replaceFirst(RegExp(r'^Exception:\s*'), '');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor:  Colors.white,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: InkWell(
                onTap: () => Navigator.pop(context),
                borderRadius: BorderRadius.circular(13),
                child: Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(13),
                    boxShadow: const [
                      BoxShadow(
                        color: Color(0x12000000),
                        blurRadius: 10,
                        offset: Offset(0, 2),
                      ),
                    ],
                  ),
                  alignment: Alignment.center,
                  child: const Icon(
                    Icons.arrow_back_rounded,
                    size: 16,
                    color: Color(0xFF111827),
                  ),
                ),
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                keyboardDismissBehavior:
                    ScrollViewKeyboardDismissBehavior.onDrag,
                physics: const BouncingScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(22, 10, 22, 30),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Add Funds',
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 26,
                        fontWeight: FontWeight.w500,
                        letterSpacing: -0.6,
                        color: const Color(0xFF111827),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Enter any amount to load into your wallet',
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 13,
                        color: const Color(0xFF6B7280),
                      ),
                    ),
                    const SizedBox(height: 28),
                    _AmountInput(
                      controller: _amountController,
                      focusNode: _amountFocus,
                      enabled: _topUpRequestId == null && !_submitting,
                    ),
                    const SizedBox(height: 18),
                    Text(
                      'QUICK SELECT',
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                        letterSpacing: 1,
                        color: const Color(0xFF9CA3AF),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        for (var i = 0; i < _quickAmounts.length; i++) ...[
                          if (i != 0) const SizedBox(width: 8),
                          Expanded(
                            child: _QuickAmountChip(
                              amount: _quickAmounts[i],
                              selected: _amount == _quickAmounts[i],
                              onTap: _topUpRequestId == null && !_submitting
                                  ? () => _selectAmount(_quickAmounts[i])
                                  : null,
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 34),
                    Text(
                      'PAYMENT METHOD',
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                        letterSpacing: 1,
                        color: const Color(0xFF9CA3AF),
                      ),
                    ),
                    const SizedBox(height: 10),
                    const _JazzCashMethodCard(),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        const Icon(
                          Icons.info_outline_rounded,
                          size: 13,
                          color: Color(0xFF9CA3AF),
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            'Only JazzCash top-up is supported at this time',
                            style: GoogleFonts.plusJakartaSans(
                              fontSize: 11,
                              fontWeight: FontWeight.w500,
                              color: const Color(0xFF9CA3AF),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 22),
                    if (_topUpRequestId != null) ...[
                      const _PendingPaymentNotice(),
                      const SizedBox(height: 14),
                    ],
                  ],
                ),
              ),
            ),
            Container(
              color: const Color(0xFFF6F7FB),
              padding: const EdgeInsets.fromLTRB(22, 10, 22, 14),
              child: SafeArea(
                top: false,
                child: SizedBox(
                  width: double.infinity,
                  height: 56,
                  child: FilledButton(
                    onPressed: (_canContinue || _topUpRequestId != null) &&
                            !_submitting &&
                            !_checkingStatus
                        ? _continue
                        : null,
                    style: FilledButton.styleFrom(
                      elevation: 0,
                      backgroundColor: AppColors.brand,
                      disabledBackgroundColor:
                          AppColors.brand.withValues(alpha: 0.30),
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                    child: _submitting || _checkingStatus
                        ? const SizedBox(
                            width: 21,
                            height: 21,
                            child: CircularProgressIndicator(
                              strokeWidth: 2.2,
                              color: Colors.white,
                            ),
                          )
                        : Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                _topUpRequestId != null
                                    ? Icons.refresh_rounded
                                    : Icons.account_balance_wallet_rounded,
                                size: 18,
                              ),
                              const SizedBox(width: 10),
                              Text(
                                _topUpRequestId != null
                                    ? 'Check payment status'
                                    : 'Add Funds',
                                style: GoogleFonts.plusJakartaSans(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AmountInput extends StatelessWidget {
  const _AmountInput({
    required this.controller,
    required this.focusNode,
    required this.enabled,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0x12000000)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0D000000),
            blurRadius: 14,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'AMOUNT',
            style: GoogleFonts.plusJakartaSans(
              fontSize: 11,
              fontWeight: FontWeight.w500,
              letterSpacing: 0.8,
              color: const Color(0xFF9CA3AF),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: AppColors.brand.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  'PKR',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    letterSpacing: 0.5,
                    color: AppColors.brand,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextField(
                  controller: controller,
                  focusNode: focusNode,
                  enabled: enabled,
                  autofocus: true,
                  keyboardType: TextInputType.number,
                  textInputAction: TextInputAction.done,
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly,
                    LengthLimitingTextInputFormatter(7),
                  ],
                  decoration: InputDecoration(
                    border: InputBorder.none,
                    hintText: '0',
                    hintStyle: GoogleFonts.plusJakartaSans(
                      fontSize: 32,
                      fontWeight: FontWeight.w500,
                      color: const Color(0xFFD1D5DB),
                    ),
                    isDense: true,
                    contentPadding: EdgeInsets.zero,
                  ),
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 32,
                    height: 1.25,
                    fontWeight: FontWeight.w500,
                    letterSpacing: -1,
                    color: const Color(0xFF111827),
                  ),
                ),
              ),
              if (controller.text.isNotEmpty)
                IconButton(
                  onPressed: enabled ? controller.clear : null,
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(
                    Icons.cancel_rounded,
                    color: Color(0xFFD1D5DB),
                    size: 22,
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _QuickAmountChip extends StatelessWidget {
  const _QuickAmountChip({
    required this.amount,
    required this.selected,
    required this.onTap,
  });

  final int amount;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? AppColors.brand : Colors.white,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: selected
                  ? Colors.transparent
                  : const Color(0xFFE8EDF3),
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  NumberFormat('#,##0').format(amount),
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: selected ? Colors.white : const Color(0xFF111827),
                  ),
                ),
              ),
              const SizedBox(height: 1),
              Text(
                'PKR',
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 9,
                  fontWeight: FontWeight.w500,
                  letterSpacing: 0.4,
                  color: selected
                      ? Colors.white70
                      : const Color(0xFF9CA3AF),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _JazzCashMethodCard extends StatelessWidget {
  const _JazzCashMethodCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
  
        boxShadow: const [
          BoxShadow(
            color: Color(0x0A000000),
            blurRadius: 10,
            offset: Offset(0, 3),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            alignment: Alignment.center,
           
            child: Image.asset(
              'assets/images/branding/jazzcash_icon.png',
              width: 50,
              height: 50,
            )
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'JazzCash',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 15,
                    fontWeight: FontWeight.w500,
                    color: const Color(0xFF111827),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Mobile wallet · Pakistan',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 12,
                    color: const Color(0xFF6B7280),
                  ),
                ),
              ],
            ),
          ),
          Container(
            width: 22,
            height: 22,
            decoration: const BoxDecoration(
              color: AppColors.brand,
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.check_rounded, color: Colors.white, size: 14),
          ),
        ],
      ),
    );
  }
}

class _PendingPaymentNotice extends StatelessWidget {
  const _PendingPaymentNotice();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF7ED),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          const SizedBox(
            width: 24,
            height: 24,
            child: CircularProgressIndicator(
              strokeWidth: 2.3,
              color: Color(0xFFEA580C),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'Waiting for JazzCash confirmation. Return here after completing the payment.',
              style: GoogleFonts.outfit(
                fontSize: 12.5,
                height: 1.4,
                color: const Color(0xFF9A3412),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
