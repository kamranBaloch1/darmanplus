class DoctorReviewSummaryModel {
  const DoctorReviewSummaryModel({
    required this.averageRating,
    required this.reviewCount,
    required this.starCounts,
  });

  final double averageRating;
  final int reviewCount;
  final Map<int, int> starCounts;

  double fractionFor(int stars) {
    if (reviewCount == 0) return 0;
    return (starCounts[stars] ?? 0) / reviewCount;
  }

  factory DoctorReviewSummaryModel.fromMap(Map<String, dynamic> map) {
    return DoctorReviewSummaryModel(
      averageRating: (map['average_rating'] as num?)?.toDouble() ?? 0,
      reviewCount: (map['review_count'] as num?)?.toInt() ?? 0,
      starCounts: {
        5: (map['five_star_count'] as num?)?.toInt() ?? 0,
        4: (map['four_star_count'] as num?)?.toInt() ?? 0,
        3: (map['three_star_count'] as num?)?.toInt() ?? 0,
        2: (map['two_star_count'] as num?)?.toInt() ?? 0,
        1: (map['one_star_count'] as num?)?.toInt() ?? 0,
      },
    );
  }
}
