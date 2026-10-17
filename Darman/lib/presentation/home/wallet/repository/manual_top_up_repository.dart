import 'dart:io';

import 'package:supabase_flutter/supabase_flutter.dart';
class ManualTopUpRequest {
  final String id;
  final int? amount;
  final String status;
  final String receiptUrl;
  final DateTime createdAt;

  ManualTopUpRequest({
    required this.id,
    required this.amount,
    required this.status,
    required this.receiptUrl,
    required this.createdAt,
  });

  factory ManualTopUpRequest.fromMap(Map<String, dynamic> map) {
    return ManualTopUpRequest(
      id: map['id']?.toString() ?? '',
      amount: map['amount'] == null
          ? null
          : (map['amount'] as num).toInt(),
      status: map['status']?.toString() ?? 'pending',
      receiptUrl: map['receipt_url']?.toString() ?? '',
      createdAt: DateTime.parse(
        map['created_at'].toString(),
      ),
    );
  }
}


class ManualTopUpRepository {
  final SupabaseClient _supabase;

  ManualTopUpRepository({SupabaseClient? client})
      : _supabase = client ?? Supabase.instance.client;

  Future<String> getPaymentQrUrl() async {
    final response = await _supabase.functions.invoke('get-manual-payment-qr');
    final data = response.data;
    if (response.status < 200 || response.status >= 300 || data is! Map) {
      final message = data is Map ? data['error']?.toString() : null;
      throw Exception(message ?? 'Payment QR is temporarily unavailable.');
    }
    final qrUrl = data['qr_url']?.toString().trim() ?? '';
    if (qrUrl.isEmpty) throw Exception('Payment QR has not been configured yet.');
    return qrUrl;
  }

  /// Upload receipt to a PRIVATE Supabase Storage bucket.
  /// Create a bucket called `wallet-receipts` and keep it private.
  Future<String> uploadReceipt(File file) async {
    final user = _supabase.auth.currentUser;
    if (user == null) throw Exception('Not authenticated');

    final extension = file.path.split('.').last.toLowerCase();
    final path =
        '${user.id}/${DateTime.now().millisecondsSinceEpoch}.$extension';

    await _supabase.storage
        .from('wallet-receipts')
        .upload(
          path,
          file,
          fileOptions: const FileOptions(
            upsert: false,
            cacheControl: '31536000',
          ),
        );

    // Store the storage path, not a permanent public URL.
    return path;
  }
Future<ManualTopUpRequest> createTopUp({
  required String receiptPath,
}) async {
  try {
    final response = await _supabase.functions.invoke(
      'create-manual-wallet-top-up',
      body: {
        'receipt_url': receiptPath,
      },
    );

    final data = response.data;

    print('MANUAL TOP UP STATUS: ${response.status}');
    print('MANUAL TOP UP RESPONSE: $data');

    if (data == null) {
      throw Exception(
        'Server returned an empty response (HTTP ${response.status})',
      );
    }

    if (data is! Map) {
      throw Exception(
        'Invalid server response: $data',
      );
    }

    final responseMap = Map<String, dynamic>.from(data);

    // Edge Function returned an error
    if (responseMap['error'] != null) {
      throw Exception(
        responseMap['error'].toString(),
      );
    }

    final topUpData = responseMap['top_up'];

    if (topUpData == null || topUpData is! Map) {
      throw Exception(
        'Server did not return a top-up request: $responseMap',
      );
    }

    return ManualTopUpRequest.fromMap(
      Map<String, dynamic>.from(topUpData),
    );
  } on FunctionException catch (e) {
    print('FUNCTION ERROR: ${e.details}');
    print('FUNCTION REASON: ${e.reasonPhrase}');

    final details = e.details;

    if (details is Map && details['error'] != null) {
      throw Exception(details['error'].toString());
    }

    throw Exception(
      e.reasonPhrase ?? 'Unable to create top-up',
    );
  } catch (e) {
    print('MANUAL TOP UP ERROR: $e');
    rethrow;
  }
}

  Future<ManualTopUpRequest> submitReceipt({
  required File receipt,
}) async {
  try {
    print('Uploading receipt...');

    final path = await uploadReceipt(receipt);

    print('Receipt uploaded: $path');

    final result = await createTopUp(
      receiptPath: path,
    );

    print('Top-up created: ${result.id}');

    return result;
  } catch (e) {
    print('SUBMIT RECEIPT ERROR: $e');
    rethrow;
  }
}
  Future<ManualTopUpRequest?> getTopUp(String id) async {
    final row = await _supabase
        .from('wallet_top_up_requests')
        .select()
        .eq('id', id)
        .maybeSingle();

    if (row == null) return null;
    return ManualTopUpRequest.fromMap(row);
  }

  Future<List<ManualTopUpRequest>> getMyTopUps() async {
    final rows = await _supabase
        .from('wallet_top_up_requests')
        .select()
        .order('created_at', ascending: false);

    return rows
        .map((row) => ManualTopUpRequest.fromMap(row))
        .toList();
  }
}
