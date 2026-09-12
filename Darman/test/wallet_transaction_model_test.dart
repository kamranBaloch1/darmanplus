import 'package:darmaan/core/models/wallet_transaction_model.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('parses a booking-independent wallet top-up', () {
    final transaction = WalletTransactionModel.fromMap({
      'id': 'transaction-1',
      'user_id': 'patient-1',
      'booking_id': null,
      'transaction_type': 'wallet_top_up',
      'amount': 2500,
      'currency': 'PKR',
      'balance_after': 4000,
      'description': 'Wallet top-up',
      'metadata': {'provider': 'verified-payment-provider'},
      'created_at': '2026-08-17T12:00:00Z',
    });

    expect(transaction.type, WalletTransactionType.walletTopUp);
    expect(transaction.bookingId, isNull);
    expect(transaction.isCredit, isTrue);
    expect(transaction.absoluteAmount, 2500);
    expect(transaction.currency, 'PKR');
  });

  test('parses a consultation debit with its booking id', () {
    final transaction = WalletTransactionModel.fromMap({
      'id': 'transaction-2',
      'user_id': 'patient-1',
      'booking_id': 'booking-1',
      'transaction_type': 'consultation_payment',
      'amount': -1000,
      'currency': 'PKR',
      'description': 'Consultation payment completed',
      'created_at': '2026-08-17T12:30:00Z',
    });

    expect(transaction.type, WalletTransactionType.consultationPayment);
    expect(transaction.bookingId, 'booking-1');
    expect(transaction.isDebit, isTrue);
    expect(transaction.absoluteAmount, 1000);
  });
}
