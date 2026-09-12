enum WalletTopUpStatus {
  pending,
  succeeded,
  failed,
  expired,
  reversed;

  static WalletTopUpStatus fromDatabase(String? value) {
    return switch (value) {
      'succeeded' => WalletTopUpStatus.succeeded,
      'failed' => WalletTopUpStatus.failed,
      'expired' => WalletTopUpStatus.expired,
      'reversed' => WalletTopUpStatus.reversed,
      _ => WalletTopUpStatus.pending,
    };
  }
}

class WalletTopUpSession {
  const WalletTopUpSession({
    required this.requestId,
    required this.checkoutUrl,
    required this.amount,
    required this.currency,
    required this.expiresAt,
  });

  final String requestId;
  final Uri checkoutUrl;
  final double amount;
  final String currency;
  final DateTime expiresAt;

  factory WalletTopUpSession.fromMap(Map<String, dynamic> map) {
    final requestId = map['request_id']?.toString() ?? '';
    final checkoutUrl = Uri.tryParse(map['checkout_url']?.toString() ?? '');
    final expiresAt = DateTime.tryParse(map['expires_at']?.toString() ?? '');
    if (requestId.isEmpty || checkoutUrl == null || expiresAt == null) {
      throw const FormatException('Invalid JazzCash checkout response');
    }
    return WalletTopUpSession(
      requestId: requestId,
      checkoutUrl: checkoutUrl,
      amount: (map['amount'] as num?)?.toDouble() ?? 0,
      currency: map['currency']?.toString() ?? 'PKR',
      expiresAt: expiresAt.toUtc(),
    );
  }
}

class WalletTopUpResult {
  const WalletTopUpResult({
    required this.requestId,
    required this.status,
    required this.amount,
    required this.currency,
    this.responseMessage,
    this.providerReference,
    this.walletTransactionId,
  });

  final String requestId;
  final WalletTopUpStatus status;
  final double amount;
  final String currency;
  final String? responseMessage;
  final String? providerReference;
  final String? walletTransactionId;

  factory WalletTopUpResult.fromMap(Map<String, dynamic> map) {
    return WalletTopUpResult(
      requestId: map['request_id']?.toString() ?? '',
      status: WalletTopUpStatus.fromDatabase(map['status']?.toString()),
      amount: (map['amount'] as num?)?.toDouble() ?? 0,
      currency: map['currency']?.toString() ?? 'PKR',
      responseMessage: map['response_message']?.toString(),
      providerReference: map['provider_reference']?.toString(),
      walletTransactionId: map['wallet_transaction_id']?.toString(),
    );
  }
}
