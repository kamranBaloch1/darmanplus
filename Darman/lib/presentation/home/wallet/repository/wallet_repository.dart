import 'package:darmaan/core/models/wallet_summary_model.dart';
import 'package:darmaan/core/models/wallet_top_up_model.dart';
import 'package:darmaan/core/models/wallet_transaction_model.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class WalletException implements Exception {
  const WalletException(this.message);

  final String message;

  @override
  String toString() => message;
}

class WalletRepository {
  WalletRepository({
    SupabaseClient? client,
  }) : _client = client ?? Supabase.instance.client;

  final SupabaseClient _client;

  String get _userId {
    final id = _client.auth.currentUser?.id;

    if (id == null) {
      throw const WalletException(
        'Please sign in to use your wallet.',
      );
    }

    return id;
  }

  Future<WalletSummaryModel> getSummary() async {
    try {
      final row = await _client
          .from('users')
          .select(
            'wallet_balance, wallet_reserved_balance, wallet_recovery_due',
          )
          .eq('uid', _userId)
          .single();

      return WalletSummaryModel.fromMap(row);
    } on PostgrestException catch (error) {
      throw WalletException(error.message);
    }
  }

  Future<List<WalletTransactionModel>> getTransactions({
    int limit = 50,
    DateTime? before,
  }) async {
    if (limit < 1 || limit > 100) {
      throw const WalletException(
        'Transaction page size must be between 1 and 100.',
      );
    }

    try {
      final rows = await _client.rpc(
        'get_my_wallet_transactions',
        params: {
          'p_limit': limit,
          'p_before': before?.toUtc().toIso8601String(),
        },
      );

      return (rows as List)
          .map(
            (row) => WalletTransactionModel.fromMap(
              Map<String, dynamic>.from(
                row as Map,
              ),
            ),
          )
          .toList();
    } on PostgrestException catch (error) {
      final missingFunction = error.code == 'PGRST202' ||
          error.message.contains('get_my_wallet_transactions');
      if (missingFunction) {
        return _getTransactionsLegacy(limit: limit, before: before);
      }
      throw WalletException(error.message);
    }
  }

  Future<WalletTopUpSession> createJazzCashTopUp({
    required int amount,
  }) async {
    if (amount < 100 || amount > 1000000) {
      throw const WalletException(
        'Amount must be between Rs. 100 and Rs. 1,000,000.',
      );
    }

    try {
      final response = await _client.functions.invoke(
        'create-jazzcash-top-up',
        body: {'amount': amount},
      );
      final data = response.data;
      if (data is! Map) {
        throw const WalletException('JazzCash checkout could not be created.');
      }
      final map = Map<String, dynamic>.from(data);
      final error = map['error']?.toString().trim();
      if (response.status < 200 || response.status >= 300) {
        throw WalletException(
          error?.isNotEmpty == true
              ? error!
              : 'JazzCash checkout could not be created.',
        );
      }
      return WalletTopUpSession.fromMap(map);
    } on WalletException {
      rethrow;
    } on FunctionException catch (error) {
      final details = error.details;
      if (details is Map && details['error'] != null) {
        throw WalletException(details['error'].toString());
      }
      throw WalletException(error.reasonPhrase ?? 'JazzCash is unavailable.');
    } catch (error) {
      throw WalletException('Could not start JazzCash payment: $error');
    }
  }

  Future<WalletTopUpResult> getTopUpStatus(String requestId) async {
    try {
      final data = await _client.rpc(
        'get_my_wallet_top_up_status',
        params: {'p_request_id': requestId},
      );
      if (data is! Map) {
        throw const WalletException('Payment status could not be checked.');
      }
      return WalletTopUpResult.fromMap(Map<String, dynamic>.from(data));
    } on WalletException {
      rethrow;
    } on PostgrestException catch (error) {
      throw WalletException(error.message);
    }
  }

  Future<void> createDoctorWithdrawalRequest({
    required double amount,
    required String bankName,
    required String accountNumber,
    required String accountName,
  }) async {
    try {
      final response = await _client.functions.invoke(
        'create-doctor-withdrawal-request',
        body: {
          'amount': amount,
          'bank_name': bankName,
          'account_number': accountNumber,
          'account_name': accountName,
        },
      );
      final data = response.data;
      if (response.status < 200 || response.status >= 300) {
        final error = data is Map ? data['error']?.toString() : null;
        throw WalletException(error?.isNotEmpty == true
            ? error!
            : 'Could not create withdrawal request.');
      }
    } on WalletException {
      rethrow;
    } on FunctionException catch (error) {
      final details = error.details;
      if (details is Map && details['error'] != null) {
        throw WalletException(details['error'].toString());
      }
      throw WalletException(
        error.reasonPhrase ?? 'Could not create withdrawal request.',
      );
    } on PostgrestException catch (error) {
      throw WalletException(error.message);
    }
  }

  Future<List<WalletTransactionModel>> _getTransactionsLegacy({
    required int limit,
    DateTime? before,
  }) async {
    try {
      var query = _client
          .from('wallet_transactions')
          .select()
          .eq('user_id', _userId);
      if (before != null) {
        query = query.lt('created_at', before.toUtc().toIso8601String());
      }
      final response = await query
          .order('created_at', ascending: false)
          .limit(limit);
      final rows = (response as List)
          .map((row) => Map<String, dynamic>.from(row as Map))
          .toList();

      await _attachCounterpartNames(rows);
      return rows.map(WalletTransactionModel.fromMap).toList();
    } on PostgrestException catch (error) {
      throw WalletException(error.message);
    }
  }

  Future<void> _attachCounterpartNames(
    List<Map<String, dynamic>> transactions,
  ) async {
    final bookingIds = transactions
        .map((row) => row['booking_id']?.toString())
        .whereType<String>()
        .where((id) => id.isNotEmpty)
        .toSet()
        .toList();
    if (bookingIds.isEmpty) return;

    try {
      final bookingRows = await _client
          .from('bookings')
          .select('id, patient_id, doctor_id')
          .inFilter('id', bookingIds);
      final bookings = {
        for (final row in bookingRows as List)
          row['id'].toString(): Map<String, dynamic>.from(row as Map),
      };
      final counterpartIds = <String>{};
      for (final booking in bookings.values) {
        final patientId = booking['patient_id']?.toString();
        final doctorId = booking['doctor_id']?.toString();
        if (patientId == _userId && doctorId != null) {
          counterpartIds.add(doctorId);
        } else if (doctorId == _userId && patientId != null) {
          counterpartIds.add(patientId);
        }
      }
      if (counterpartIds.isEmpty) return;

      final userRows = await _client
          .from('users')
          .select('uid, name')
          .inFilter('uid', counterpartIds.toList());
      final names = {
        for (final row in userRows as List)
          row['uid'].toString(): row['name']?.toString(),
      };
      for (final transaction in transactions) {
        final booking = bookings[transaction['booking_id']?.toString()];
        if (booking == null) continue;
        final patientId = booking['patient_id']?.toString();
        final doctorId = booking['doctor_id']?.toString();
        final counterpartId = patientId == _userId ? doctorId : patientId;
        transaction['counterpart_name'] = names[counterpartId];
      }
    } catch (_) {
      // Transaction history remains usable even if participant enrichment is
      // temporarily unavailable under an older database policy.
    }
  }
}
