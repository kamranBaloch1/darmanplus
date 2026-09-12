class ConsultationReviewModel {
  const ConsultationReviewModel({
    required this.id,
    required this.bookingId,
    required this.patientId,
    required this.doctorId,
    required this.rating,
    required this.createdAt,
    required this.updatedAt,
    this.review,
    this.patientName = 'Patient',
  });

  final String id;
  final String bookingId;
  final String patientId;
  final String doctorId;
  final int rating;
  final String? review;
  final String patientName;
  final DateTime createdAt;
  final DateTime updatedAt;

  factory ConsultationReviewModel.fromMap(Map<String, dynamic> map) {
    return ConsultationReviewModel(
      id: map['id']?.toString() ?? '',
      bookingId: map['booking_id']?.toString() ?? '',
      patientId: map['patient_id']?.toString() ?? '',
      doctorId: map['doctor_id']?.toString() ?? '',
      rating: (map['rating'] as num?)?.toInt() ?? 0,
      review: _clean(map['review']),
      patientName: _clean(map['patient_name']) ?? 'Patient',
      createdAt: _date(map['created_at']),
      updatedAt: _date(map['updated_at']),
    );
  }

  static String? _clean(dynamic value) {
    final text = value?.toString().trim() ?? '';
    return text.isEmpty ? null : text;
  }

  static DateTime _date(dynamic value) =>
      DateTime.tryParse(value?.toString() ?? '')?.toUtc() ??
      DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
}
