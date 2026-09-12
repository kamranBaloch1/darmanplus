class ConsultationCompletionModel {
  const ConsultationCompletionModel({
    required this.bookingId,
    required this.grossFee,
    required this.commissionRate,
    required this.commissionAmount,
    required this.doctorEarning,
    required this.isDoctor,
    required this.shouldShow,
    required this.alreadyRated,
    this.doctorName = 'Doctor',
    this.completedAt,
  });

  final String bookingId;
  final double grossFee;
  final double commissionRate;
  final double commissionAmount;
  final double doctorEarning;
  final bool isDoctor;
  final bool shouldShow;
  final bool alreadyRated;
  final String doctorName;
  final DateTime? completedAt;

  factory ConsultationCompletionModel.fromMap(Map<String, dynamic> map) {
    return ConsultationCompletionModel(
      bookingId: map['booking_id']?.toString() ?? '',
      grossFee: (map['gross_fee'] as num?)?.toDouble() ?? 0,
      commissionRate: (map['commission_rate'] as num?)?.toDouble() ?? 0.12,
      commissionAmount: (map['commission_amount'] as num?)?.toDouble() ?? 0,
      doctorEarning: (map['doctor_earning'] as num?)?.toDouble() ?? 0,
      isDoctor: map['is_doctor'] == true,
      shouldShow: map['should_show'] == true,
      alreadyRated: map['already_rated'] == true,
      doctorName: map['doctor_name']?.toString().trim().isNotEmpty == true
          ? map['doctor_name'].toString().trim()
          : 'Doctor',
      completedAt: map['completed_at'] == null
          ? null
          : DateTime.tryParse(map['completed_at'].toString())?.toUtc(),
    );
  }
}
