class WalletSummaryModel {
  const WalletSummaryModel({
    required this.balance,
    required this.reservedBalance,
    required this.recoveryDue,
    this.currency = 'PKR',
  });

  final double balance;
  final double reservedBalance;
  final double recoveryDue;
  final String currency;
  double get totalBalance => balance + reservedBalance;

  factory WalletSummaryModel.fromMap(Map<String, dynamic> map) {
    return WalletSummaryModel(
      balance: (map['wallet_balance'] as num?)?.toDouble() ?? 0,
      reservedBalance:
          (map['wallet_reserved_balance'] as num?)?.toDouble() ?? 0,
      recoveryDue:
          (map['wallet_recovery_due'] as num?)?.toDouble() ?? 0,
    );
  }
}
