import 'package:darmaan/core/models/wallet_summary_model.dart';
import 'package:darmaan/core/models/wallet_transaction_model.dart';
import 'package:darmaan/core/theme/app_colors.dart';
import 'package:darmaan/core/utils/app_error_message.dart';
import 'package:darmaan/presentation/home/wallet/screens/jazzcash_payment_screen.dart';
import 'package:darmaan/widgets/app_shimmer.dart';
import 'package:darmaan/presentation/home/wallet/repository/wallet_repository.dart';
import 'package:darmaan/presentation/home/wallet/screens/add_money_screen.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

enum _TransactionFilter {
  moneyIn,
  moneyOut,
}

enum _EarningsPeriod {
  day,
  week,
  month,
}

class WalletTransactionsScreen extends StatefulWidget {
  const WalletTransactionsScreen({
    super.key,
    this.isDoctor = false,
    this.refreshToken = 0,
    this.embedded = false,
  });

  final bool isDoctor;
  final int refreshToken;
  final bool embedded;

  @override
  State<WalletTransactionsScreen> createState() =>
      _WalletTransactionsScreenState();
}

class _WalletTransactionsScreenState
    extends State<WalletTransactionsScreen> {
  final WalletRepository _repository = WalletRepository();

  late Future<
      ({
        WalletSummaryModel summary,
        List<WalletTransactionModel> items,
      })> _wallet;

  late _TransactionFilter _filter;

  _EarningsPeriod _earningsPeriod = _EarningsPeriod.month;

  DateTime _earningsDate = DateTime.now();

  @override
  void initState() {
    super.initState();

    _filter = _TransactionFilter.moneyIn;

    _wallet = _load();
  }

  @override
  void didUpdateWidget(
    covariant WalletTransactionsScreen oldWidget,
  ) {
    super.didUpdateWidget(oldWidget);

    if (oldWidget.refreshToken != widget.refreshToken) {
      _wallet = _load();
    }

    if (oldWidget.isDoctor != widget.isDoctor) {
      _filter = _TransactionFilter.moneyIn;
    }
  }

  // ===========================================================================
  // LOAD
  // ===========================================================================

  Future<
      ({
        WalletSummaryModel summary,
        List<WalletTransactionModel> items,
      })> _load() async {
    final results = await Future.wait<Object>([
      _repository.getSummary(),
      _repository.getTransactions(),
    ]);

    final items =
        results[1] as List<WalletTransactionModel>;

    items.sort(
      (a, b) => b.createdAt.compareTo(
        a.createdAt,
      ),
    );

    return (
      summary: results[0] as WalletSummaryModel,
      items: items,
    );
  }

  Future<void> _refresh() async {
    setState(() {
      _wallet = _load();
    });

    await _wallet;
  }

  Future<void> _openAddMoney(WalletSummaryModel summary) async {
    final added = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (_) => JazzCashPaymentScreen(
         
        ),
      ),
    );
    if (added == true && mounted) await _refresh();
  }

  // ===========================================================================
  // BUILD
  // ===========================================================================
  
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor:  Colors.white,

      appBar: AppBar(
        automaticallyImplyLeading: !widget.embedded,
        elevation: 0,
        scrolledUnderElevation: 0,
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        toolbarHeight: 64,
        centerTitle: false,
        titleSpacing: widget.embedded ? 20 : 2,
        leadingWidth: widget.embedded ? 0 : 48,

        leading: widget.embedded
            ? null
            : IconButton(
                onPressed: () {
                  Navigator.pop(context);
                },
                splashRadius: 20,
                icon: const Icon(
                  Icons.arrow_back_rounded,
                  size: 23,
                ),
                color: AppColors.textPrimary,
              ),

        title: Text(
          'Wallet activity',
          style: GoogleFonts.outfit(
            fontSize: 18,
            fontWeight: FontWeight.w500,
            letterSpacing: -0.25,
            color: AppColors.textPrimary,
          ),
        ),
      ),

      body: FutureBuilder<
          ({
            WalletSummaryModel summary,
            List<WalletTransactionModel> items,
          })>(
        future: _wallet,
        builder: (
          context,
          snapshot,
        ) {
          if (snapshot.connectionState !=
              ConnectionState.done) {
            return const _WalletLoading();
          }

          if (snapshot.hasError) {
            return _WalletError(
              message: _readableError(
                snapshot.error!,
              ),
              retry: _refresh,
            );
          }

          final data = snapshot.data!;

          final visibleItems = _filteredItems(
            data.items,
          );

       final doctorEarnings = widget.isDoctor
    ? data.items
        .where(
          (item) =>
              _isInsideSelectedPeriod(item) &&
              item.type ==
                  WalletTransactionType.doctorEarning &&
              item.isCredit,
        )
        .fold<double>(
          0,
          (total, item) =>
              total + item.absoluteAmount,
        )
    : 0.0;

          return RefreshIndicator(
            color: AppColors.brand,
            backgroundColor: Colors.white,
            onRefresh: _refresh,
            child: CustomScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              slivers: [
                SliverToBoxAdapter(
                  child: _BalanceSection(
                    summary: data.summary,
                    showAddMoney: !widget.isDoctor,
                    onAddMoney: () => _openAddMoney(data.summary),
                  ),
                ),
               if (widget.isDoctor)
  SliverToBoxAdapter(
    child: _WalletPeriodFilter(
      isDoctor: true,
      selected: _earningsPeriod,
      selectedDate: _earningsDate,
      amount: doctorEarnings,
      onChanged: (value) {
        setState(() {
          _earningsPeriod = value;
          _earningsDate = DateTime.now();
        });
      },
      onDateTap: _pickEarningsDate,
    ),
  ),
              
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 2, 16, 10),
                    child: _TransactionFilters(
                      selected: _filter,
                      onChanged: (value) {
                        setState(() => _filter = value);
                      },
                    ),
                  ),
                ),
                if (visibleItems.isEmpty)
                  SliverFillRemaining(
                    hasScrollBody: false,
                    child: _WalletEmpty(filter: _filter),
                  )
                else
                  ..._buildTransactionGroups(visibleItems),
                const SliverToBoxAdapter(child: SizedBox(height: 30)),
              ],
            ),
          );
        },
      ),
    );
  }

  // ===========================================================================
  // FILTER
  // ===========================================================================
List<WalletTransactionModel> _filteredItems(
  List<WalletTransactionModel> items,
) {
  // Doctors use the selected Day/Week/Month period.
  // Patients see all transactions without a date-period filter.
  final periodItems = widget.isDoctor
      ? items.where(_isInsideSelectedPeriod).toList()
      : items;

  switch (_filter) {
    case _TransactionFilter.moneyIn:
      return periodItems
          .where((item) => item.isCredit)
          .toList();

    case _TransactionFilter.moneyOut:
      return periodItems
          .where((item) => item.isDebit)
          .toList();
  }
}

  // ===========================================================================
  // PERIOD
  // ===========================================================================

  bool _isInsideSelectedPeriod(
    WalletTransactionModel item,
  ) {
    final date = item.createdAt.toLocal();

    final selected = DateTime(
      _earningsDate.year,
      _earningsDate.month,
      _earningsDate.day,
    );

    final start = switch (_earningsPeriod) {
      _EarningsPeriod.day => selected,

      _EarningsPeriod.week => selected.subtract(
          Duration(
            days: selected.weekday - DateTime.monday,
          ),
        ),

      _EarningsPeriod.month => DateTime(
          selected.year,
          selected.month,
        ),
    };

    final end = switch (_earningsPeriod) {
      _EarningsPeriod.day => start.add(
          const Duration(days: 1),
        ),

      _EarningsPeriod.week => start.add(
          const Duration(days: 7),
        ),

      _EarningsPeriod.month => DateTime(
          selected.year,
          selected.month + 1,
        ),
    };

    return !date.isBefore(start) &&
        date.isBefore(end);
  }

  Future<void> _pickEarningsDate() async {
    final picked = await showDatePicker(
      context: context,

      builder: (
        context,
        child,
      ) {
        final theme = Theme.of(context);

        return Theme(
          data: theme.copyWith(
            colorScheme:
                theme.colorScheme.copyWith(
              primary: AppColors.brand,
              onPrimary: Colors.white,
              onSurface: Colors.black,
            ),
          ),
          child: child!,
        );
      },

      initialDate: _earningsDate,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),

      helpText: switch (_earningsPeriod) {
        _EarningsPeriod.day => 'SELECT DAY',

        _EarningsPeriod.week =>
          'SELECT ANY DAY IN THE WEEK',

        _EarningsPeriod.month =>
          'SELECT ANY DAY IN THE MONTH',
      },
    );

    if (picked != null && mounted) {
      setState(() {
        _earningsDate = picked;
      });
    }
  }

  // ===========================================================================
  // TRANSACTION GROUPS
  // ===========================================================================

  List<Widget> _buildTransactionGroups(
    List<WalletTransactionModel> items,
  ) {
    final groups =
        <DateTime, List<WalletTransactionModel>>{};

    for (final item in items) {
      final local = item.createdAt.toLocal();

      final day = DateTime(
        local.year,
        local.month,
        local.day,
      );

      groups.putIfAbsent(
        day,
        () => [],
      );

      groups[day]!.add(item);
    }

    final entries = groups.entries.toList()
      ..sort(
        (a, b) => b.key.compareTo(
          a.key,
        ),
      );

    return entries.map(
      (entry) {
        return SliverToBoxAdapter(
          child: _TransactionGroup(
            date: entry.key,
            items: entry.value,
          ),
        );
      },
    ).toList();
  }

  String _readableError(
    Object error,
  ) {
    return AppErrorMessage.from(error);
  }
}

// =============================================================================
// BALANCE
// =============================================================================
class _BalanceSection extends StatelessWidget {
  const _BalanceSection({
    required this.summary,
    required this.showAddMoney,
    required this.onAddMoney,
  });

  final WalletSummaryModel summary;
  final bool showAddMoney;
  final VoidCallback onAddMoney;

  @override
  Widget build(BuildContext context) {
    final money = NumberFormat('#,##0.00');

    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(14, 8, 14, 18),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(18, 18, 18, 17),
        decoration: BoxDecoration(
          color: const Color(0xFFF3F4F6),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  alignment: Alignment.center,
                  child: const Icon(
                    Icons.account_balance_wallet_outlined,
                    size: 18,
                    color: Colors.black,
                  ),
                ),

                const SizedBox(width: 10),

                Expanded(
                  child: Text(
                    'Available balance',
                    style: GoogleFonts.outfit(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ),

                // Patient side: reserved-for-consultations badge, top right.
                if (showAddMoney && summary.reservedBalance > 0) ...[
                  const SizedBox(width: 10),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 7,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(11),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.lock_outline_rounded,
                          size: 12,
                          color: AppColors.textSecondary,
                        ),
                        const SizedBox(width: 5),
                        Text(
                          'Reserved: Rs. ${money.format(summary.reservedBalance)}',
                          style: GoogleFonts.outfit(
                            fontSize: 10,
                            fontWeight: FontWeight.w500,
                            color: Colors.black,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],

                // Doctor side keeps the old plain reserved box below (unchanged flow).
              ],
            ),

            const SizedBox(height: 20),

            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  'Rs.',
                  style: GoogleFonts.outfit(
                    fontSize: 16,
                    height: 1.3,
                    fontWeight: FontWeight.w500,
                    color: Colors.black,
                  ),
                ),

                const SizedBox(width: 6),

                Flexible(
                  child: Text(
                    money.format(summary.balance),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.outfit(
                      fontSize: 32,
                      height: 1,
                      fontWeight: FontWeight.w500,
                      letterSpacing: -1,
                      color: Colors.black,
                    ),
                  ),
                ),
              ],
            ),

            // Add money button now sits under the balance amount.
            if (showAddMoney) ...[
              const SizedBox(height: 30),
              SizedBox(
                width: double.infinity,
                height: 46,
                child: FilledButton.icon(
                  onPressed: onAddMoney,
                  style: FilledButton.styleFrom(
                    elevation: 0,
                    backgroundColor: AppColors.brand,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(11),
                    ),
                  ),
                  icon: const Icon(Icons.add_rounded, size: 17),
                  label: Text(
                    'Add money',
                    style: GoogleFonts.outfit(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ),
            ],

            // Doctor side (no Add money): keep the reserved box in its old spot.
            if (!showAddMoney && summary.reservedBalance > 0) ...[
              const SizedBox(height: 17),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  horizontal: 11,
                  vertical: 9,
                ),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(11),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.lock_outline_rounded,
                      size: 14,
                      color: AppColors.textSecondary,
                    ),
                    const SizedBox(width: 7),
                    Expanded(
                      child: Text(
                        'Reserved for consultations',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.outfit(
                          fontSize: 10.8,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'Rs. ${money.format(summary.reservedBalance)}',
                      style: GoogleFonts.outfit(
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                        color: Colors.black,
                      ),
                    ),
                  ],
                ),
              ),
            ],

            if (summary.recoveryDue > 0) ...[
              const SizedBox(height: 10),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  horizontal: 11,
                  vertical: 9,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFF1F0),
                  borderRadius: BorderRadius.circular(11),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.info_outline_rounded,
                      size: 14,
                      color: Color(0xFFB42318),
                    ),
                    const SizedBox(width: 7),
                    Expanded(
                      child: Text(
                        'Amount due from a reversed payment',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.outfit(
                          fontSize: 10.8,
                          color: const Color(0xFFB42318),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'Rs. ${money.format(summary.recoveryDue)}',
                      style: GoogleFonts.outfit(
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                        color: const Color(0xFFB42318),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
// =============================================================================
// DAY / WEEK / MONTH
// =============================================================================

class _WalletPeriodFilter extends StatelessWidget {
  const _WalletPeriodFilter({
    required this.isDoctor,
    required this.selected,
    required this.selectedDate,
    required this.amount,
    required this.onChanged,
    required this.onDateTap,
  });

  final bool isDoctor;

  final _EarningsPeriod selected;

  final DateTime selectedDate;

  final double amount;

  final ValueChanged<_EarningsPeriod>
      onChanged;

  final VoidCallback onDateTap;

  @override
  Widget build(BuildContext context) {
    final money = NumberFormat(
      '#,##0.00',
    );

    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(
        16,
        0,
        16,
        18,
      ),
      child: Container(
        padding: const EdgeInsets.all(
          15,
        ),
        decoration: BoxDecoration(
          color: const Color(0xFFF7F8FA),
          borderRadius: BorderRadius.circular(
            16,
          ),
        ),
        child: Column(
          crossAxisAlignment:
              CrossAxisAlignment.start,
          children: [
            // Doctor keeps selected earnings.
            //
            // Patient does NOT show:
            // "Spent on selected day/week/month"

            if (isDoctor) ...[
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment:
                          CrossAxisAlignment.start,
                      children: [
                        Text(
                          _doctorPeriodLabel,
                          style:
                              GoogleFonts.outfit(
                            fontSize: 11.5,
                            color: AppColors
                                .textSecondary,
                          ),
                        ),

                        const SizedBox(
                          height: 4,
                        ),

                        Text(
                          'Rs. ${money.format(amount)}',
                          style:
                              GoogleFonts.outfit(
                            fontSize: 22,
                            fontWeight:
                                FontWeight.w500,
                            letterSpacing: -0.4,
                            color: AppColors
                                .textPrimary,
                          ),
                        ),
                      ],
                    ),
                  ),

                  Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      color: const Color(
                        0xFFEDF8F1,
                      ),
                      borderRadius:
                          BorderRadius.circular(
                        11,
                      ),
                    ),
                    child: const Icon(
                      Icons.trending_up_rounded,
                      size: 20,
                      color: Color(
                        0xFF16834A,
                      ),
                    ),
                  ),
                ],
              ),

              const SizedBox(
                height: 14,
              ),
            ],

            // -----------------------------------------------------------------
            // DAY / WEEK / MONTH
            // -----------------------------------------------------------------

            Row(
              children:
                  _EarningsPeriod.values.map(
                (period) {
                  final active =
                      period == selected;

                  return Expanded(
                    child: Padding(
                      padding:
                          EdgeInsets.only(
                        right: period ==
                                _EarningsPeriod
                                    .month
                            ? 0
                            : 7,
                      ),
                      child: Material(
                        color: active
                            ? AppColors.brand
                            : Colors.white,
                        borderRadius:
                            BorderRadius.circular(
                          10,
                        ),
                        child: InkWell(
                          onTap: () {
                            onChanged(period);
                          },
                          borderRadius:
                              BorderRadius.circular(
                            10,
                          ),
                          child: Padding(
                            padding:
                                const EdgeInsets
                                    .symmetric(
                              vertical: 9,
                            ),
                            child: Text(
                              switch (period) {
                                _EarningsPeriod.day =>
                                  'Day',
                                _EarningsPeriod.week =>
                                  'Week',
                                _EarningsPeriod.month =>
                                  'Month',
                              },
                              textAlign:
                                  TextAlign.center,
                              style:
                                  GoogleFonts.outfit(
                                fontSize: 11.5,
                                fontWeight:
                                    FontWeight.w500,
                                color: active
                                    ? Colors.white
                                    : AppColors
                                        .textSecondary,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ).toList(),
            ),

            const SizedBox(
              height: 10,
            ),

            // -----------------------------------------------------------------
            // DATE
            // -----------------------------------------------------------------

            Material(
              color: Colors.white,
              borderRadius:
                  BorderRadius.circular(
                10,
              ),
              child: InkWell(
                onTap: onDateTap,
                borderRadius:
                    BorderRadius.circular(
                  10,
                ),
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 11,
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.calendar_month_outlined,
                        size: 17,
                        color: AppColors
                            .textSecondary,
                      ),

                      const SizedBox(
                        width: 8,
                      ),

                      Expanded(
                        child: Text(
                          _dateLabel,
                          style:
                              GoogleFonts.outfit(
                            fontSize: 11.8,
                            fontWeight:
                                FontWeight.w500,
                            color: Colors.black,
                          ),
                        ),
                      ),

                      const Icon(
                        Icons.expand_more_rounded,
                        size: 19,
                        color: Colors.black,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String get _doctorPeriodLabel {
    return switch (selected) {
      _EarningsPeriod.day =>
        'Selected day earnings',

      _EarningsPeriod.week =>
        'Selected week earnings',

      _EarningsPeriod.month =>
        'Selected month earnings',
    };
  }

  String get _dateLabel {
    final date = DateTime(
      selectedDate.year,
      selectedDate.month,
      selectedDate.day,
    );

    return switch (selected) {
      _EarningsPeriod.day =>
        DateFormat(
          'dd MMM yyyy',
        ).format(date),

      _EarningsPeriod.week => () {
          final start = date.subtract(
            Duration(
              days:
                  date.weekday - DateTime.monday,
            ),
          );

          final end = start.add(
            const Duration(
              days: 6,
            ),
          );

          return '${DateFormat('dd MMM').format(start)} - '
              '${DateFormat('dd MMM yyyy').format(end)}';
        }(),

      _EarningsPeriod.month =>
        DateFormat(
          'MMMM yyyy',
        ).format(date),
    };
  }
}

// =============================================================================
// MONEY IN / MONEY OUT FILTER
// =============================================================================

class _TransactionFilters extends StatelessWidget {
  const _TransactionFilters({
    required this.selected,
    required this.onChanged,
  });

  final _TransactionFilter selected;

  final ValueChanged<_TransactionFilter>
      onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 42,
      padding: const EdgeInsets.all(
        4,
      ),
      decoration: BoxDecoration(
        color: const Color(
          0xFFEDEFF2,
        ),
        borderRadius: BorderRadius.circular(
          13,
        ),
      ),
      child: Row(
        children: [
          _FilterItem(
            label: 'Money in',
            selected:
                selected ==
                _TransactionFilter.moneyIn,
            onTap: () {
              onChanged(
                _TransactionFilter.moneyIn,
              );
            },
          ),

          _FilterItem(
            label: 'Money out',
            selected:
                selected ==
                _TransactionFilter.moneyOut,
            onTap: () {
              onChanged(
                _TransactionFilter.moneyOut,
              );
            },
          ),
        ],
      ),
    );
  }
}

class _FilterItem extends StatelessWidget {
  const _FilterItem({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;

  final bool selected;

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Material(
        color: selected
            ? Colors.white
            : Colors.transparent,
        borderRadius: BorderRadius.circular(
          10,
        ),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(
            10,
          ),
          child: Center(
            child: Text(
              label,
              style: GoogleFonts.outfit(
                fontSize: 11.2,
                fontWeight: FontWeight.w500,
                color: selected
                    ? AppColors.textPrimary
                    : AppColors.textSecondary,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// =============================================================================
// TRANSACTION GROUP
// =============================================================================

class _TransactionGroup extends StatelessWidget {
  const _TransactionGroup({
    required this.date,
    required this.items,
  });

  final DateTime date;

  final List<WalletTransactionModel> items;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        14,
        5,
        14,
        13,
      ),
      child: Column(
        crossAxisAlignment:
            CrossAxisAlignment.start,
        children: [
          Padding(
            padding:
                const EdgeInsets.fromLTRB(
              3,
              7,
              3,
              8,
            ),
            child: Text(
              _dateLabel(date),
              style: GoogleFonts.outfit(
                fontSize: 10.7,
                fontWeight: FontWeight.w500,
                color:
                    AppColors.textSecondary,
              ),
            ),
          ),

          Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius:
                  BorderRadius.circular(
                17,
              ),
            ),
            clipBehavior: Clip.antiAlias,
            child: Column(
              children: List.generate(
                items.length,
                (
                  index,
                ) {
                  return Column(
                    children: [
                      _TransactionRow(
                        transaction:
                            items[index],
                      ),

                      if (index !=
                          items.length - 1)
                        const Padding(
                          padding:
                              EdgeInsets.only(
                            left: 68,
                          ),
                          child: Divider(
                            height: 1,
                            thickness: 1,
                            color: Color(
                              0xFFF0F1F3,
                            ),
                          ),
                        ),
                    ],
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _dateLabel(
    DateTime value,
  ) {
    final now = DateTime.now();

    final today = DateTime(
      now.year,
      now.month,
      now.day,
    );

    final yesterday = today.subtract(
      const Duration(
        days: 1,
      ),
    );

    if (value == today) {
      return 'TODAY';
    }

    if (value == yesterday) {
      return 'YESTERDAY';
    }

    return DateFormat(
      'EEE, d MMM',
    ).format(value).toUpperCase();
  }
}

// =============================================================================
// TRANSACTION
// =============================================================================

class _TransactionRow extends StatelessWidget {
  const _TransactionRow({
    required this.transaction,
  });

  final WalletTransactionModel transaction;

  bool get _credit =>
      transaction.isCredit;

  @override
  Widget build(BuildContext context) {
    final money = NumberFormat(
      '#,##0.00',
    );

    final description =
        _activityDescription;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () {
          _showDetails(context);
        },
        child: Padding(
          padding:
              const EdgeInsets.fromLTRB(
            13,
            13,
            10,
            13,
          ),
          child: Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: _iconBackground,
                  borderRadius:
                      BorderRadius.circular(
                    13,
                  ),
                ),
                alignment: Alignment.center,
                child: Icon(
                  _icon,
                  size: 19,
                  color: _iconColor,
                ),
              ),

              const SizedBox(
                width: 11,
              ),

              Expanded(
                child: Column(
                  crossAxisAlignment:
                      CrossAxisAlignment.start,
                  children: [
                    Text(
                      _title(
                        transaction.type,
                      ),
                      maxLines: 1,
                      overflow:
                          TextOverflow.ellipsis,
                      style:
                          GoogleFonts.outfit(
                        fontSize: 12.8,
                        height: 1.2,
                        fontWeight:
                            FontWeight.w500,
                        color: AppColors
                            .textPrimary,
                      ),
                    ),

                    const SizedBox(
                      height: 4,
                    ),

                    Text(
                      description.isNotEmpty
                          ? description
                          : _fallbackDescription,
                      maxLines: 1,
                      overflow:
                          TextOverflow.ellipsis,
                      style:
                          GoogleFonts.outfit(
                        fontSize: 10.8,
                        fontWeight:
                            FontWeight.w400,
                        color: AppColors
                            .textSecondary,
                      ),
                    ),

                    const SizedBox(
                      height: 3,
                    ),

                    Text(
                      DateFormat(
                        'h:mm a',
                      ).format(
                        transaction.createdAt
                            .toLocal(),
                      ),
                      style:
                          GoogleFonts.outfit(
                        fontSize: 9.8,
                        color: AppColors
                            .textSecondary
                            .withValues(
                          alpha: 0.8,
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(
                width: 10,
              ),

              Column(
                crossAxisAlignment:
                    CrossAxisAlignment.end,
                children: [
                  Text(
                    '${_credit ? '+' : '-'} Rs. ${money.format(transaction.absoluteAmount)}',
                    style:
                        GoogleFonts.outfit(
                      fontSize: 12.4,
                      fontWeight:
                          FontWeight.w500,
                      color: _credit
                          ? const Color(
                              0xFF16834A,
                            )
                          : AppColors
                              .textPrimary,
                    ),
                  ),

                  const SizedBox(
                    height: 4,
                  ),

                  Text(
                    _credit
                        ? 'Money in'
                        : 'Money out',
                    style:
                        GoogleFonts.outfit(
                      fontSize: 9.5,
                      fontWeight:
                          FontWeight.w400,
                      color: AppColors
                          .textSecondary,
                    ),
                  ),
                ],
              ),

              const SizedBox(
                width: 3,
              ),

              Icon(
                Icons.chevron_right_rounded,
                size: 18,
                color: AppColors.textSecondary
                    .withValues(
                  alpha: 0.55,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String get _fallbackDescription {
    return switch (transaction.type) {
      WalletTransactionType.walletTopUp =>
        'Funds added to your wallet',

      WalletTransactionType.walletTopUpReversal =>
        'JazzCash payment reversed',

      WalletTransactionType.walletRecovery =>
        'Reversed payment amount recovered',

      WalletTransactionType.consultationPayment =>
        'Paid for a consultation',

      WalletTransactionType.doctorEarning =>
        'Earnings from a consultation',

      WalletTransactionType.platformCommission =>
        'Service fee for consultation',
    };
  }

  String get _activityDescription {
    if (transaction.type ==
        WalletTransactionType.doctorEarning) {
      final commission =
          (transaction.metadata['commission']
                  as num?)
              ?.toDouble();

      final gross =
          (transaction.metadata['gross_fee']
                  as num?)
              ?.toDouble();

      final rate = (transaction.metadata[
                      'commission_rate']
                  as num?)
              ?.toDouble() ??
          (gross != null &&
                  gross > 0 &&
                  commission != null
              ? commission / gross
              : 0.12);

      if (commission != null) {
        return '${(rate * 100).toStringAsFixed(0)}% commission: '
            'Rs. ${NumberFormat('#,##0.00').format(commission)}';
      }
    }

    final saved =
        transaction.description.trim();

    return saved.isNotEmpty
        ? saved
        : _fallbackDescription;
  }

  void _showDetails(
    BuildContext context,
  ) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      useSafeArea: true,
      isScrollControlled: true,
      builder: (_) =>
          _TransactionDetailsSheet(
        transaction: transaction,
      ),
    );
  }

  IconData get _icon {
    switch (transaction.type) {
      case WalletTransactionType.walletTopUp:
        return Icons.add_rounded;

      case WalletTransactionType.walletTopUpReversal:
        return Icons.undo_rounded;

      case WalletTransactionType.walletRecovery:
        return Icons.shield_outlined;

      case WalletTransactionType.consultationPayment:
        return Icons
            .medical_services_outlined;

      case WalletTransactionType.doctorEarning:
        return Icons.payments_outlined;

      case WalletTransactionType.platformCommission:
        return Icons
            .receipt_long_outlined;
    }
  }

  Color get _iconBackground {
    if (_credit) {
      return const Color(
        0xFFEDF8F1,
      );
    }

    return const Color(
      0xFFF1F3F5,
    );
  }

  Color get _iconColor {
    if (_credit) {
      return const Color(
        0xFF16834A,
      );
    }

    return AppColors.textSecondary;
  }

  String _title(
    WalletTransactionType type,
  ) {
    return switch (type) {
      WalletTransactionType.walletTopUp =>
        'Wallet top-up',

      WalletTransactionType.walletTopUpReversal =>
        'Payment reversed',

      WalletTransactionType.walletRecovery =>
        'Balance recovery',

      WalletTransactionType.consultationPayment =>
        'Consultation payment',

      WalletTransactionType.doctorEarning =>
        'Consultation earning',

      WalletTransactionType.platformCommission =>
        'Platform commission',
    };
  }
}

// =============================================================================
// TRANSACTION DETAILS
// =============================================================================

class _TransactionDetailsSheet
    extends StatelessWidget {
  const _TransactionDetailsSheet({
    required this.transaction,
  });

  final WalletTransactionModel transaction;

  @override
  Widget build(BuildContext context) {
    final money = NumberFormat(
      '#,##0.00',
    );

    final credit = transaction.isCredit;

    final color = credit
        ? const Color(0xFF16834A)
        : AppColors.textPrimary;

    final description =
        transaction.description.trim();

    final counterpartName =
        transaction.counterpartName?.trim();

    final counterpartLabel = switch (transaction.type) {
      WalletTransactionType.doctorEarning => 'Patient',
      WalletTransactionType.consultationPayment => 'Doctor',
      _ => null,
    };

    final isDoctorEarning =
        transaction.type ==
            WalletTransactionType.doctorEarning;

    final grossFee =
        (transaction.metadata['gross_fee']
                as num?)
            ?.toDouble();

    final commission =
        (transaction.metadata['commission']
                as num?)
            ?.toDouble();

    final commissionRate =
        (transaction.metadata[
                    'commission_rate']
                as num?)
            ?.toDouble() ??
        (grossFee != null &&
                grossFee > 0 &&
                commission != null
            ? commission / grossFee
            : 0.12);

    return Container(
      padding: const EdgeInsets.fromLTRB(
        20,
        10,
        20,
        24,
      ),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(
            24,
          ),
        ),
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 38,
              height: 4,
              decoration: BoxDecoration(
                color:
                    const Color(0xFFD8DBDF),
                borderRadius:
                    BorderRadius.circular(
                  99,
                ),
              ),
            ),

            const SizedBox(
              height: 22,
            ),

            Container(
              width: 54,
              height: 54,
              decoration: BoxDecoration(
                color: credit
                    ? const Color(
                        0xFFEDF8F1,
                      )
                    : const Color(
                        0xFFF1F3F5,
                      ),
                shape: BoxShape.circle,
              ),
              child: Icon(
                credit
                    ? Icons.south_west_rounded
                    : Icons.north_east_rounded,
                color: color,
                size: 23,
              ),
            ),

            const SizedBox(
              height: 12,
            ),

            Text(
              '${credit ? '+' : '-'} Rs. ${money.format(transaction.absoluteAmount)}',
              style: GoogleFonts.outfit(
                fontSize: 27,
                fontWeight: FontWeight.w500,
                letterSpacing: -0.7,
                color: color,
              ),
            ),

            const SizedBox(
              height: 4,
            ),

            Text(
              credit
                  ? 'Money received'
                  : 'Money paid',
              style: GoogleFonts.outfit(
                fontSize: 12,
                color:
                    AppColors.textSecondary,
              ),
            ),

            const SizedBox(
              height: 22,
            ),

            Container(
              padding: const EdgeInsets.all(
                15,
              ),
              decoration: BoxDecoration(
                color:
                    const Color(0xFFF7F8FA),
                borderRadius:
                    BorderRadius.circular(
                  14,
                ),
              ),
              child: Column(
                children: [
                  _ReceiptRow(
                    label: 'Type',
                    value: _transactionTitle(
                      transaction.type,
                    ),
                  ),

                  if (counterpartLabel != null &&
                      counterpartName != null &&
                      counterpartName.isNotEmpty) ...[
                    const Divider(
                      height: 25,
                      color: Color(0xFFE8EAED),
                    ),
                    _ReceiptRow(
                      label: counterpartLabel,
                      value: counterpartName,
                    ),
                  ],

                  if (description.isNotEmpty) ...[
                    const Divider(
                      height: 25,
                      color:
                          Color(0xFFE8EAED),
                    ),
                    _ReceiptRow(
                      label: 'Details',
                      value: description,
                    ),
                  ],

                  if (isDoctorEarning &&
                      grossFee != null) ...[
                    const Divider(
                      height: 25,
                      color:
                          Color(0xFFE8EAED),
                    ),
                    _ReceiptRow(
                      label:
                          'Consultation fee',
                      value:
                          'Rs. ${money.format(grossFee)}',
                    ),
                  ],

                  if (isDoctorEarning) ...[
                    const Divider(
                      height: 25,
                      color:
                          Color(0xFFE8EAED),
                    ),

                    _ReceiptRow(
                      label:
                          'Platform commission',
                      value:
                          '${(commissionRate * 100).toStringAsFixed(0)}% • '
                          'Rs. ${money.format(commission ?? ((grossFee ?? 0) * commissionRate))}',
                    ),

                    const Divider(
                      height: 25,
                      color:
                          Color(0xFFE8EAED),
                    ),

                    _ReceiptRow(
                      label: 'You earned',
                      value:
                          'Rs. ${money.format(transaction.absoluteAmount)}',
                    ),
                  ],

                  const Divider(
                    height: 25,
                    color: Color(
                      0xFFE8EAED,
                    ),
                  ),

                  _ReceiptRow(
                    label: 'Date',
                    value: DateFormat(
                      'dd MMM yyyy, h:mm a',
                    ).format(
                      transaction.createdAt
                          .toLocal(),
                    ),
                  ),

                  if (transaction
                          .balanceAfter !=
                      null) ...[
                    const Divider(
                      height: 25,
                      color:
                          Color(0xFFE8EAED),
                    ),

                    _ReceiptRow(
                      label: 'Balance after',
                      value:
                          'Rs. ${money.format(transaction.balanceAfter)}',
                    ),
                  ],

                  if (transaction
                          .reservedBalanceAfter !=
                      null) ...[
                    const Divider(
                      height: 25,
                      color:
                          Color(0xFFE8EAED),
                    ),

                    _ReceiptRow(
                      label: 'Reserved after',
                      value:
                          'Rs. ${money.format(transaction.reservedBalanceAfter)}',
                    ),
                  ],

                  if (transaction.bookingId
                          ?.trim()
                          .isNotEmpty ==
                      true) ...[
                    const Divider(
                      height: 25,
                      color:
                          Color(0xFFE8EAED),
                    ),

                    _ReceiptRow(
                      label:
                          'Booking reference',
                      value: _shortReference(
                        transaction.bookingId!,
                      ),
                    ),
                  ],

                  const Divider(
                    height: 25,
                    color: Color(
                      0xFFE8EAED,
                    ),
                  ),

                  _ReceiptRow(
                    label: 'Transaction ID',
                    value: _shortReference(
                      transaction.id,
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(
              height: 16,
            ),

            SizedBox(
              width: double.infinity,
              height: 48,
              child: FilledButton(
                onPressed: () {
                  Navigator.pop(context);
                },
                style:
                    FilledButton.styleFrom(
                  elevation: 0,
                  backgroundColor:
                      AppColors.brand,
                  foregroundColor:
                      Colors.white,
                  shape:
                      RoundedRectangleBorder(
                    borderRadius:
                        BorderRadius.circular(
                      13,
                    ),
                  ),
                ),
                child: Text(
                  'Done',
                  style:
                      GoogleFonts.outfit(
                    fontWeight:
                        FontWeight.w500,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  static String _shortReference(
    String value,
  ) {
    final clean = value.trim();

    if (clean.length <= 14) {
      return clean;
    }

    return '${clean.substring(0, 8)}…${clean.substring(clean.length - 4)}';
  }
}

// =============================================================================
// RECEIPT
// =============================================================================

class _ReceiptRow extends StatelessWidget {
  const _ReceiptRow({
    required this.label,
    required this.value,
  });

  final String label;

  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment:
          CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Text(
            label,
            style: GoogleFonts.outfit(
              fontSize: 11.5,
              color:
                  AppColors.textSecondary,
            ),
          ),
        ),

        const SizedBox(
          width: 20,
        ),

        Flexible(
          child: Text(
            value,
            textAlign: TextAlign.right,
            style: GoogleFonts.outfit(
              fontSize: 11.8,
              fontWeight: FontWeight.w500,
              color:
                  AppColors.textPrimary,
            ),
          ),
        ),
      ],
    );
  }
}

String _transactionTitle(
  WalletTransactionType type,
) {
  return switch (type) {
    WalletTransactionType.walletTopUp =>
      'Wallet top-up',

    WalletTransactionType.walletTopUpReversal =>
      'Payment reversed',

    WalletTransactionType.walletRecovery =>
      'Balance recovery',

    WalletTransactionType.consultationPayment =>
      'Consultation payment',

    WalletTransactionType.doctorEarning =>
      'Consultation earning',

    WalletTransactionType.platformCommission =>
      'Platform commission',
  };
}

// =============================================================================
// EMPTY
// =============================================================================

class _WalletEmpty extends StatelessWidget {
  const _WalletEmpty({
    required this.filter,
  });

  final _TransactionFilter filter;

  @override
  Widget build(BuildContext context) {
    final moneyIn =
        filter == _TransactionFilter.moneyIn;

    return Center(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          40,
          20,
          40,
          80,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: const BoxDecoration(
                color: Color(
                  0xFFEDEFF2,
                ),
                shape: BoxShape.circle,
              ),
              alignment: Alignment.center,
              child: Icon(
                moneyIn
                    ? Icons
                        .south_west_rounded
                    : Icons
                        .north_east_rounded,
                size: 27,
                color:
                    AppColors.textSecondary,
              ),
            ),

            const SizedBox(
              height: 17,
            ),

            Text(
              moneyIn
                  ? 'No money in'
                  : 'No money out',
              textAlign: TextAlign.center,
              style: GoogleFonts.outfit(
                fontSize: 15,
                fontWeight: FontWeight.w500,
                color:
                    AppColors.textPrimary,
              ),
            ),

            const SizedBox(
              height: 6,
            ),

            Text(
              moneyIn
                  ? 'Money added or received during this period will appear here.'
                  : 'Payments made during this period will appear here.',
              textAlign: TextAlign.center,
              style: GoogleFonts.outfit(
                fontSize: 11.7,
                height: 1.5,
                color:
                    AppColors.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// =============================================================================
// LOADING
// =============================================================================

class _WalletLoading extends StatelessWidget {
  const _WalletLoading();

  @override
  Widget build(BuildContext context) {
    return const AppListShimmer(
      itemCount: 6,
      showAvatar: false,
      horizontalPadding: 16,
    );
  }
}

// =============================================================================
// ERROR
// =============================================================================

class _WalletError extends StatelessWidget {
  const _WalletError({
    required this.message,
    required this.retry,
  });

  final String message;

  final Future<void> Function() retry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding:
            const EdgeInsets.symmetric(
          horizontal: 38,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: const BoxDecoration(
                color: Color(
                  0xFFEDEFF2,
                ),
                shape: BoxShape.circle,
              ),
              alignment: Alignment.center,
              child: Icon(
                Icons.error_outline_rounded,
                size: 27,
                color:
                    AppColors.textSecondary,
              ),
            ),

            const SizedBox(
              height: 17,
            ),

            Text(
              'Couldn’t load wallet',
              textAlign: TextAlign.center,
              style: GoogleFonts.outfit(
                fontSize: 15.5,
                fontWeight: FontWeight.w500,
                color:
                    AppColors.textPrimary,
              ),
            ),

            const SizedBox(
              height: 7,
            ),

            Text(
              message,
              textAlign: TextAlign.center,
              maxLines: 3,
              overflow:
                  TextOverflow.ellipsis,
              style: GoogleFonts.outfit(
                fontSize: 11.8,
                height: 1.5,
                color:
                    AppColors.textSecondary,
              ),
            ),

            const SizedBox(
              height: 18,
            ),

            FilledButton(
              onPressed: () {
                retry();
              },
              style:
                  FilledButton.styleFrom(
                elevation: 0,
                backgroundColor:
                    const Color(
                  0xFFEDEFF2,
                ),
                foregroundColor:
                    AppColors.textPrimary,
                padding:
                    const EdgeInsets.symmetric(
                  horizontal: 18,
                  vertical: 11,
                ),
                shape:
                    RoundedRectangleBorder(
                  borderRadius:
                      BorderRadius.circular(
                    11,
                  ),
                ),
              ),
              child: Text(
                'Try again',
                style: GoogleFonts.outfit(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
