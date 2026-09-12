enum WalletTransactionType {
  walletTopUp,
  walletTopUpReversal,
  walletRecovery,
  consultationPayment,
  doctorEarning,
  platformCommission;

  static WalletTransactionType fromDatabase(String? value) {
    return switch (value) {
      'wallet_top_up' => WalletTransactionType.walletTopUp,
      'wallet_top_up_reversal' => WalletTransactionType.walletTopUpReversal,
      'wallet_recovery' => WalletTransactionType.walletRecovery,
      'consultation_payment' => WalletTransactionType.consultationPayment,
      'doctor_earning' => WalletTransactionType.doctorEarning,
      'platform_commission' => WalletTransactionType.platformCommission,
      _ => throw FormatException('Unknown wallet transaction type: $value'),
    };
  }

  String get databaseValue => switch (this) {
    WalletTransactionType.walletTopUp => 'wallet_top_up',
    WalletTransactionType.walletTopUpReversal => 'wallet_top_up_reversal',
    WalletTransactionType.walletRecovery => 'wallet_recovery',
    WalletTransactionType.consultationPayment => 'consultation_payment',
    WalletTransactionType.doctorEarning => 'doctor_earning',
    WalletTransactionType.platformCommission => 'platform_commission',
  };
}

class WalletTransactionModel {
  const WalletTransactionModel({
    required this.id,
    required this.userId,
    required this.type,
    required this.amount,
    required this.currency,
    required this.description,
    required this.metadata,
    required this.createdAt,
    this.bookingId,
    this.counterpartName,
    this.balanceAfter,
    this.reservedBalanceAfter,
  });

  final String id;
  final String? userId;
  final String? bookingId;
  final String? counterpartName;
  final WalletTransactionType type;
  final double amount;
  final String currency;
  final double? balanceAfter;
  final double? reservedBalanceAfter;
  final String description;
  final Map<String, dynamic> metadata;
  final DateTime createdAt;

  bool get isCredit => amount > 0;
  bool get isDebit => amount < 0;
  double get absoluteAmount => amount.abs();

  factory WalletTransactionModel.fromMap(Map<String, dynamic> map) {
    return WalletTransactionModel(
      id: map['id']?.toString() ?? '',
      userId: map['user_id']?.toString(),
      bookingId: map['booking_id']?.toString(),
      counterpartName: map['counterpart_name']?.toString().trim(),
      type: WalletTransactionType.fromDatabase(
        map['transaction_type']?.toString(),
      ),
      amount: (map['amount'] as num?)?.toDouble() ?? 0,
      currency: map['currency']?.toString() ?? 'PKR',
      balanceAfter: (map['balance_after'] as num?)?.toDouble(),
      reservedBalanceAfter: (map['reserved_balance_after'] as num?)?.toDouble(),
      description: map['description']?.toString() ?? '',
      metadata: map['metadata'] is Map
          ? Map<String, dynamic>.from(map['metadata'] as Map)
          : const {},
      createdAt:
          DateTime.tryParse(map['created_at']?.toString() ?? '')?.toUtc() ??
          DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
    );
  }
}
