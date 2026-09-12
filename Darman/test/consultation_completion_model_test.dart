import 'package:darmaan/core/models/consultation_completion_model.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ConsultationCompletionModel', () {
    test('parses a doctor settlement receipt', () {
      final receipt = ConsultationCompletionModel.fromMap({
        'booking_id': 'booking-1',
        'gross_fee': 1000,
        'commission_rate': 0.20,
        'commission_amount': 200,
        'doctor_earning': 800,
        'is_doctor': true,
        'should_show': true,
        'already_rated': false,
        'completed_at': '2026-08-17T10:00:00Z',
      });

      expect(receipt.bookingId, 'booking-1');
      expect(receipt.grossFee, 1000);
      expect(receipt.commissionAmount, 200);
      expect(receipt.doctorEarning, 800);
      expect(receipt.isDoctor, isTrue);
      expect(receipt.shouldShow, isTrue);
      expect(receipt.completedAt, DateTime.utc(2026, 8, 17, 10));
    });

    test('uses safe defaults for optional receipt values', () {
      final receipt = ConsultationCompletionModel.fromMap({
        'booking_id': 'booking-2',
        'gross_fee': 500,
      });

      expect(receipt.commissionRate, 0.20);
      expect(receipt.commissionAmount, 0);
      expect(receipt.doctorEarning, 0);
      expect(receipt.isDoctor, isFalse);
      expect(receipt.shouldShow, isFalse);
      expect(receipt.alreadyRated, isFalse);
    });
  });
}
