enum UserRole { patient, doctor }

class UserModel {
  final String uid;
  final String name;

  // Contact
  final String? email;
  final bool isEmailVerified;

  final String? phone;
  final bool isPhoneVerified;

  // Account
  final UserRole role;
  final String? profileImage;
  final bool isProfileCompleted;

  // Personal information
  final String? gender;
  final DateTime? dateOfBirth;

  // Doctor specific
  final String? title;
  final String? specialization;
  final String? qualification;
  final String? medicalLicenseNumber;
  final int? experienceYears;
  final double? consultationFee;
  final String? bio;
  final String? introVideoUrl;

  // Doctor verification documents
  final List<String> doctorDocuments;

  // Doctor status
  final bool isDoctorVerified;
  final bool isAvailable;

  // Doctor rating
  final double doctorRating;
  final int doctorReviewCount;
  final int doctorCompletedConsultationCount;

  // Completed bookings
  final List<String> doctorCompletedBookingIds;
  final List<String> patientCompletedBookingIds;

  // Wallet
  final double walletBalance;
  final double walletReservedBalance;

  // Timestamps
  final DateTime? createdAt;
  final DateTime? updatedAt;

  UserModel({
    required this.uid,
    required this.name,
    required this.role,

    this.email,
    this.isEmailVerified = false,

    this.phone,
    this.isPhoneVerified = false,

    this.profileImage,
    this.isProfileCompleted = false,

    this.gender,
    this.dateOfBirth,

    this.title,
    this.specialization,
    this.qualification,
    this.medicalLicenseNumber,
    this.experienceYears,
    this.consultationFee,
    this.bio,
    this.introVideoUrl,

    this.doctorDocuments = const [],

    this.isDoctorVerified = false,
    this.isAvailable = false,

    this.doctorRating = 0.0,
    this.doctorReviewCount = 0,
    this.doctorCompletedConsultationCount = 0,

    this.doctorCompletedBookingIds = const [],
    this.patientCompletedBookingIds = const [],

    this.walletBalance = 0.0,
    this.walletReservedBalance = 0.0,

    this.createdAt,
    this.updatedAt,
  });

  // Role helpers
  bool get isDoctor => role == UserRole.doctor;

  bool get isPatient => role == UserRole.patient;

  // Doctor profile completion
  double get doctorProfileCompletion {
    final checks = <bool>[
      profileImage != null && profileImage!.trim().isNotEmpty,

      specialization != null && specialization!.trim().isNotEmpty,

      title != null && title!.trim().isNotEmpty,

      experienceYears != null && experienceYears! > 0,

      gender != null && gender!.trim().isNotEmpty,

      consultationFee != null && consultationFee! > 0,
    ];

    final completed = checks.where((check) => check).length;

    return completed / checks.length;
  }

  Map<String, dynamic> toMap() {
    return {
      'uid': uid,
      'name': name,

      // Contact
      'email': email,
      'is_email_verified': isEmailVerified,

      'phone': phone,
      'is_phone_verified': isPhoneVerified,

      // Account
      'role': role.name,
      'profile_image': profileImage,
      'is_profile_completed': isProfileCompleted,

      // Personal information
      'gender': gender,
      'date_of_birth': dateOfBirth?.toIso8601String(),

      // Doctor specific
      'title': title,
      'specialization': specialization,
      'qualification': qualification,
      'medical_license_number': medicalLicenseNumber,
      'experience_years': experienceYears,
      'consultation_fee': consultationFee,
      'bio': bio,
      'intro_video_url': introVideoUrl,

      // Doctor documents
      'doctor_documents': doctorDocuments,

      // Doctor status
      'is_doctor_verified': isDoctorVerified,
      'is_available': isAvailable,

      // Doctor rating
      'doctor_rating': doctorRating,
      'doctor_review_count': doctorReviewCount,
      'doctor_completed_consultation_count': doctorCompletedConsultationCount,

      // Completed bookings
      'doctor_completed_booking_ids': doctorCompletedBookingIds,

      'patient_completed_booking_ids': patientCompletedBookingIds,

      // Wallet
      'wallet_balance': walletBalance,

      'wallet_reserved_balance': walletReservedBalance,

      // Timestamps
      'created_at': createdAt?.toIso8601String(),

      'updated_at': updatedAt?.toIso8601String(),
    };
  }

  factory UserModel.fromMap(Map<String, dynamic> map) {
    return UserModel(
      uid: map['uid'] ?? '',
      name: map['name'] ?? '',

      // Contact
      email: map['email'],

      isEmailVerified: map['is_email_verified'] ?? false,

      phone: map['phone'],

      isPhoneVerified: map['is_phone_verified'] ?? false,

      // Account
      role: map['role'] == 'doctor' ? UserRole.doctor : UserRole.patient,

      profileImage: map['profile_image'],

      isProfileCompleted: map['is_profile_completed'] ?? false,

      // Personal information
      gender: map['gender'],

      dateOfBirth: map['date_of_birth'] != null
          ? DateTime.tryParse(map['date_of_birth'].toString())
          : null,

      // Doctor specific
      title: map['title'],

      specialization: map['specialization'],

      qualification: map['qualification'],

      medicalLicenseNumber: map['medical_license_number'],

      experienceYears: map['experience_years'] != null
          ? (map['experience_years'] as num).toInt()
          : null,

      consultationFee: map['consultation_fee'] != null
          ? (map['consultation_fee'] as num).toDouble()
          : null,

      bio: map['bio'],

      introVideoUrl: map['intro_video_url'],

      // Doctor documents
      doctorDocuments: map['doctor_documents'] != null
          ? List<String>.from(map['doctor_documents'])
          : [],

      // Doctor status
      isDoctorVerified: map['is_doctor_verified'] ?? false,

      isAvailable: map['is_available'] ?? false,

      // Doctor rating
      doctorRating: map['doctor_rating'] != null
          ? (map['doctor_rating'] as num).toDouble()
          : 0.0,

      doctorReviewCount: map['doctor_review_count'] != null
          ? (map['doctor_review_count'] as num).toInt()
          : 0,

      doctorCompletedConsultationCount:
          map['doctor_completed_consultation_count'] != null
          ? (map['doctor_completed_consultation_count'] as num).toInt()
          : 0,

      // Completed doctor bookings
      doctorCompletedBookingIds: map['doctor_completed_booking_ids'] != null
          ? List<String>.from(map['doctor_completed_booking_ids'])
          : [],

      // Completed patient bookings
      patientCompletedBookingIds: map['patient_completed_booking_ids'] != null
          ? List<String>.from(map['patient_completed_booking_ids'])
          : [],

      // Wallet
      walletBalance: map['wallet_balance'] != null
          ? (map['wallet_balance'] as num).toDouble()
          : 0.0,

      walletReservedBalance: map['wallet_reserved_balance'] != null
          ? (map['wallet_reserved_balance'] as num).toDouble()
          : 0.0,

      // Timestamps
      createdAt: map['created_at'] != null
          ? DateTime.tryParse(map['created_at'].toString())
          : null,

      updatedAt: map['updated_at'] != null
          ? DateTime.tryParse(map['updated_at'].toString())
          : null,
    );
  }
}
