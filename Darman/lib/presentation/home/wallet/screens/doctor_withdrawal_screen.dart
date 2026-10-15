import 'package:darmaan/core/theme/app_colors.dart';
import 'package:darmaan/core/utils/app_error_message.dart';
import 'package:darmaan/presentation/home/wallet/repository/wallet_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

class DoctorWithdrawalScreen extends StatefulWidget {
  const DoctorWithdrawalScreen({super.key, required this.availableBalance});
  final double availableBalance;

  @override
  State<DoctorWithdrawalScreen> createState() => _DoctorWithdrawalScreenState();
}

class _DoctorWithdrawalScreenState extends State<DoctorWithdrawalScreen> {
  static const _banks = <String>[
    'Allied Bank',
    'Askari Bank',
    'Bank Alfalah',
    'Bank Al Habib',
    'Bank Islami',
    'Bank Makramah',
    'Bank of Khyber',
    'Bank of Punjab',
    'Dubai Islamic Bank Pakistan',
    'Faysal Bank',
    'HabibMetro Bank',
    'HBL',
    'JS Bank',
    'MCB Bank',
    'MCB Islamic Bank',
    'Meezan Bank',
    'National Bank of Pakistan',
    'Soneri Bank',
    'Standard Chartered Pakistan',
    'Sindh Bank',
    'UBL',
    'Zarai Taraqiati Bank',
    'Easypaisa',
    'JazzCash',
    'NayaPay',
    'SadaPay',
    'UPaisa',
    'Zindigi',
  ];

  static const _border = Color(0xFFE2E5EA);

  final _repository = WalletRepository();
  final _formKey = GlobalKey<FormState>();
  final _amount = TextEditingController();
  final _account = TextEditingController();
  final _accountName = TextEditingController();
  final _money = NumberFormat('#,##0.00');
  String? _bank;
  bool _submitting = false;

  @override
  void dispose() {
    _amount.dispose();
    _account.dispose();
    _accountName.dispose();
    super.dispose();
  }

  double get _amountValue => double.tryParse(_amount.text.trim()) ?? 0;
  bool get _exceeds => _amountValue > widget.availableBalance;

  Future<void> _submit() async {
    if (_submitting || !(_formKey.currentState?.validate() ?? false)) return;
    final amount = double.tryParse(_amount.text.trim()) ?? 0;
    if (amount > widget.availableBalance) return;
    setState(() => _submitting = true);
    try {
      await _repository.createDoctorWithdrawalRequest(
        amount: amount,
        bankName: _bank!,
        accountNumber: _account.text.trim(),
        accountName: _accountName.text.trim(),
      );
      if (!mounted) return;
      await _showSuccessDialog();
    } catch (error) {
      _showError(AppErrorMessage.from(error));
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Future<void> _showSuccessDialog() {
    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        icon: const Icon(Icons.check_circle_rounded,
            color: AppColors.brand, size: 48),
        title: Text('Request submitted',
            textAlign: TextAlign.center,
            style:
                GoogleFonts.outfit(fontSize: 18, fontWeight: FontWeight.w500)),
        content: Text(
          'Your withdrawal is waiting for Darman admin approval.',
          textAlign: TextAlign.center,
          style: GoogleFonts.outfit(
              fontSize: 14, color: AppColors.textSecondary),
        ),
        actionsAlignment: MainAxisAlignment.center,
        actions: [
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.brand,
              foregroundColor: Colors.white,
              minimumSize: const Size(140, 44),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
            ),
            onPressed: () {
              Navigator.pop(dialogContext);
              Navigator.pop(context, true);
            },
            child: Text('Done',
                style: GoogleFonts.outfit(fontWeight: FontWeight.w500)),
          ),
        ],
      ),
    );
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  InputDecoration _decoration(String hint,
      {String? prefixText, bool hasError = false}) {
    OutlineInputBorder border(Color color, [double width = 1]) =>
        OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: color, width: width),
        );

    return InputDecoration(
      hintText: hint,
      hintStyle:
          GoogleFonts.outfit(fontSize: 14, color: const Color(0xFF9AA1AC)),
      prefixText: prefixText,
      prefixStyle:
          GoogleFonts.outfit(fontSize: 15, color: AppColors.textPrimary),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 15),
      border: border(_border),
      enabledBorder: border(hasError ? Colors.red.shade400 : _border),
      focusedBorder:
          border(hasError ? Colors.red.shade400 : AppColors.brand, 1.4),
      errorBorder: border(Colors.red.shade300),
      focusedErrorBorder: border(Colors.red.shade400, 1.4),
    );
  }

  Future<void> _pickBank(FormFieldState<String> state) async {
    FocusScope.of(context).unfocus();
    final picked = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _BankSheet(banks: _banks, selected: _bank),
    );
    if (picked != null) {
      setState(() => _bank = picked);
      state.didChange(picked);
    }
  }

  Widget _bankField() {
    return FormField<String>(
      initialValue: _bank,
      validator: (_) => _bank == null ? 'Choose a bank or wallet' : null,
      builder: (state) {
        final hasValue = _bank != null;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: () => _pickBank(state),
              child: InputDecorator(
                decoration: _decoration('', hasError: state.hasError).copyWith(
                  suffixIcon: const Icon(Icons.keyboard_arrow_down_rounded,
                      color: AppColors.textSecondary),
                ),
                child: Text(
                  hasValue ? _bank! : 'Choose bank or wallet',
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.outfit(
                    fontSize: hasValue ? 15 : 14,
                    color: hasValue
                        ? AppColors.textPrimary
                        : const Color(0xFF9AA1AC),
                  ),
                ),
              ),
            ),
            if (state.hasError)
              Padding(
                padding: const EdgeInsets.only(top: 6, left: 12),
                child: Text(
                  state.errorText ?? '',
                  style: GoogleFonts.outfit(
                      fontSize: 12, color: Colors.red.shade600),
                ),
              ),
          ],
        );
      },
    );
  }

  Widget _label(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(text,
            style: GoogleFonts.outfit(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: AppColors.textPrimary)),
      );

  @override
  Widget build(BuildContext context) {
    final inputStyle =
        GoogleFonts.outfit(fontSize: 15, color: AppColors.textPrimary);

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        foregroundColor: AppColors.textPrimary,
        title: Text('Withdraw funds',
            style:
                GoogleFonts.outfit(fontSize: 18, fontWeight: FontWeight.w500)),
      ),
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: ListView(
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
            children: [
              _label('Amount'),
              TextFormField(
                controller: _amount,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,2}')),
                ],
                style: inputStyle,
                onChanged: (_) => setState(() {}),
                decoration: _decoration('Enter amount',
                    prefixText: 'Rs. ', hasError: _exceeds),
                validator: (value) {
                  final amount = double.tryParse(value?.trim() ?? '');
                  if (amount == null || amount <= 0) {
                    return 'Enter a valid amount';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 8),
              Text(
                _exceeds
                    ? 'Amount exceeds your available balance'
                    : 'Available balance: Rs. ${_money.format(widget.availableBalance)}',
                style: GoogleFonts.outfit(
                  fontSize: 13,
                  fontWeight: _exceeds ? FontWeight.w500 : FontWeight.w400,
                  color: _exceeds ? Colors.red.shade600 : AppColors.textSecondary,
                ),
              ),
              const SizedBox(height: 24),
              _label('Bank or wallet'),
              _bankField(),
              const SizedBox(height: 24),
              _label('Account number'),
              TextFormField(
                controller: _account,
                keyboardType: TextInputType.text,
                style: inputStyle,
                onChanged: (_) => setState(() {}),
                decoration: _decoration('Bank account or wallet number'),
                validator: (value) => (value?.trim().length ?? 0) < 5
                    ? 'Enter a valid account number'
                    : null,
              ),
              const SizedBox(height: 24),
              _label('Account holder name'),
              TextFormField(
                controller: _accountName,
                textCapitalization: TextCapitalization.words,
                style: inputStyle,
                decoration: _decoration('Name registered with this account'),
                validator: (value) => (value?.trim().length ?? 0) < 2
                    ? 'Enter the account holder name'
                    : null,
              ),
              const SizedBox(height: 20),
              Text(
                'Your amount will be reserved while Darman reviews this request.',
                style: GoogleFonts.outfit(
                    fontSize: 12.5,
                    height: 1.4,
                    color: AppColors.textSecondary),
              ),
            ],
          ),
        ),
      ),
      bottomNavigationBar: SafeArea(
        top: false,
        child: Container(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
          decoration: const BoxDecoration(
            color: Colors.white,
            border: Border(top: BorderSide(color: Color(0xFFF0F2F5))),
          ),
          child: SizedBox(
            height: 54,
            width: double.infinity,
            child: FilledButton(
              onPressed: (_submitting || _amountValue <= 0) ? null : _submit,
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.brand,
                foregroundColor: Colors.white,
                disabledBackgroundColor: _submitting
                    ? AppColors.brand.withOpacity(0.6)
                    : const Color(0xFFE9ECF0),
                disabledForegroundColor:
                    _submitting ? Colors.white : const Color(0xFF9AA1AC),
                elevation: 0,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14)),
              ),
              child: _submitting
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                          strokeWidth: 2.4, color: Colors.white))
                  : Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text('Request withdrawal',
                            style: GoogleFonts.outfit(
                                fontSize: 16,
                                fontWeight: FontWeight.w500,
                                letterSpacing: 0.2)),
                        const SizedBox(width: 8),
                        const Icon(Icons.arrow_forward_rounded, size: 20),
                      ],
                    ),
            ),
          ),
        ),
      ),
    );
  }
}


class _BankSheet extends StatefulWidget {
  const _BankSheet({required this.banks, required this.selected});
  final List<String> banks;
  final String? selected;

  @override
  State<_BankSheet> createState() => _BankSheetState();
}

class _BankSheetState extends State<_BankSheet> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final q = _query.trim().toLowerCase();
    final banks = widget.banks
        .where((b) => q.isEmpty || b.toLowerCase().contains(q))
        .toList();

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.7,
        child: Column(
          children: [
            const SizedBox(height: 10),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: const Color(0xFFD9DDE3),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 16),
            Text('Select bank or wallet',
                style: GoogleFonts.outfit(
                    fontSize: 17, fontWeight: FontWeight.w500)),
            const SizedBox(height: 14),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: TextField(
                onChanged: (v) => setState(() => _query = v),
                style: GoogleFonts.outfit(fontSize: 15),
                decoration: InputDecoration(
                  hintText: 'Search bank or wallet',
                  hintStyle: GoogleFonts.outfit(
                      fontSize: 14, color: const Color(0xFF9AA1AC)),
                  prefixIcon: const Icon(Icons.search_rounded,
                      color: AppColors.textSecondary),
                  contentPadding: const EdgeInsets.symmetric(vertical: 12),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: Color(0xFFE2E5EA)),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: Color(0xFFE2E5EA)),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide:
                        const BorderSide(color: AppColors.brand, width: 1.4),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: banks.isEmpty
                  ? Center(
                      child: Text('No bank found',
                          style: GoogleFonts.outfit(
                              fontSize: 14, color: AppColors.textSecondary)),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      itemCount: banks.length,
                      itemBuilder: (context, i) {
                        final bank = banks[i];
                        final isSelected = bank == widget.selected;
                        return ListTile(
                          title: Text(bank,
                              style: GoogleFonts.outfit(
                                fontSize: 15,
                                fontWeight: isSelected
                                    ? FontWeight.w500
                                    : FontWeight.w400,
                                color: isSelected
                                    ? AppColors.brand
                                    : AppColors.textPrimary,
                              )),
                          trailing: isSelected
                              ? const Icon(Icons.check_rounded,
                                  color: AppColors.brand)
                              : null,
                          onTap: () => Navigator.pop(context, bank),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
