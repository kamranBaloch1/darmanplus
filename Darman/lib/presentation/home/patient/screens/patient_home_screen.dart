import 'dart:async';
import 'package:darmaan/core/constants/images.dart';
import 'package:darmaan/core/models/booking_model.dart';
import 'package:darmaan/core/models/user_model.dart';
import 'package:darmaan/core/theme/app_colors.dart';
import 'package:darmaan/presentation/auth/repository/login/auth_repository.dart';
import 'package:darmaan/presentation/auth/screens/login/splash_screen.dart';
import 'package:darmaan/presentation/home/patient/repository/patient_repository.dart';
import 'package:darmaan/presentation/home/patient/screens/doctor_details_screen.dart';
import 'package:darmaan/presentation/home/patient/screens/patinet_profile_screen.dart';
import 'package:darmaan/presentation/home/patient/screens/patient_consultation_request_screen.dart';
import 'package:darmaan/presentation/home/wallet/screens/wallet_transactions_screen.dart';
import 'package:darmaan/widgets/app_bottom_nav_bar.dart';
import 'package:darmaan/widgets/video_dilog.dart';
import 'package:darmaan/widgets/guest_access.dart';
import 'package:flutter/material.dart';
import 'package:darmaan/widgets/app_icon.dart';
import 'package:darmaan/core/utils/app_error_message.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:darmaan/presentation/home/patient/widgets/patient_doctor_list_tile.dart';
import 'package:connectivity_plus/connectivity_plus.dart';

class PatientHomeScreen extends StatefulWidget {
  const PatientHomeScreen({super.key});

  @override
  State<PatientHomeScreen> createState() => _PatientHomeScreenState();
}

class _PatientHomeScreenState extends State<PatientHomeScreen>
    with WidgetsBindingObserver {
  final AuthRepository _loginRepository = AuthRepository();
  final PatientRepository _patientRepository = PatientRepository();

  bool isLoggingOut = false;

  final TextEditingController _searchController = TextEditingController();
  late Future<List<UserModel>> _doctorsFuture;
  StreamSubscription<List<BookingModel>>? _activeBookingsSubscription;
  StreamSubscription<List<ConnectivityResult>>? _connectivitySubscription;
  RealtimeChannel? _doctorChangesChannel;
  Timer? _doctorRefreshDebounce;
  List<UserModel> _lastDoctors = const [];
  Map<String, BookingModel> _activeBookingByDoctor = const {};
  bool _isRefreshingDoctors = false;
  String _searchQuery = '';
  bool _showSearch = false;

  int _currentTabIndex = 0;
  int _walletRefreshToken = 0;
  int _profileRefreshToken = 0;

  bool get _isGuest => Supabase.instance.client.auth.currentUser == null;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _watchConnectivity();
    _doctorsFuture = _loadInitialDoctors();
    _watchDoctorChanges();
    if (!_isGuest) {
      _activeBookingsSubscription = _patientRepository
          .watchActivePatientBookings()
          .listen(
            (bookings) {
              if (!mounted) return;
              final priorityByDoctor = <String, BookingModel>{};
              for (final booking in bookings) {
                final existing = priorityByDoctor[booking.doctorId];
                if (existing == null ||
                    (booking.hasUpcomingFollowUp &&
                        !existing.hasUpcomingFollowUp) ||
                    (booking.hasUpcomingFollowUp &&
                        existing.hasUpcomingFollowUp &&
                        booking.followUpDate!.isBefore(
                          existing.followUpDate!,
                        ))) {
                  priorityByDoctor[booking.doctorId] = booking;
                }
              }
              setState(() {
                _activeBookingByDoctor = priorityByDoctor;
              });
            },
            onError: (_) {
              // Doctor discovery remains available if realtime reconnects slowly.
            },
          );
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _activeBookingsSubscription?.cancel();
    _connectivitySubscription?.cancel();
    _doctorChangesChannel?.unsubscribe();
    _doctorRefreshDebounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _watchConnectivity() async {
    var hadConnection = true;

    void update(List<ConnectivityResult> results) {
      final connected =
          results.isNotEmpty &&
          results.any((result) => result != ConnectivityResult.none);
      final reconnected = connected && !hadConnection;
      hadConnection = connected;
      if (!mounted || !reconnected) return;
      _refreshDoctors();
      setState(() {
        _walletRefreshToken++;
        _profileRefreshToken++;
      });
    }

    try {
      update(await Connectivity().checkConnectivity());
      _connectivitySubscription = Connectivity().onConnectivityChanged.listen(
        update,
      );
    } catch (_) {}
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _currentTabIndex == 0) {
      _refreshDoctors();
    }
  }

  void _watchDoctorChanges() {
    _doctorChangesChannel = Supabase.instance.client
        .channel('patient-home-doctor-changes')
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'users',
          filter: const PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'role',
            value: 'doctor',
          ),
          callback: (_) {
            _doctorRefreshDebounce?.cancel();
            _doctorRefreshDebounce = Timer(
              const Duration(milliseconds: 350),
              () {
                if (mounted && _currentTabIndex == 0) {
                  unawaited(_refreshDoctors());
                }
              },
            );
          },
        )
        .subscribe();
  }

  Future<List<UserModel>> _loadInitialDoctors() async {
    final doctors = await _patientRepository.getAllDoctors();
    _lastDoctors = doctors;
    return doctors;
  }

  Future<void> _refreshDoctors() async {
    if (_isRefreshingDoctors) return;
    _isRefreshingDoctors = true;
    try {
      final doctors = await _patientRepository.getAllDoctors();
      if (!mounted) return;
      if (_sameDoctorCatalogue(_lastDoctors, doctors)) return;
      _lastDoctors = doctors;
      setState(() {
        _doctorsFuture = Future.value(doctors);
      });
    } catch (error) {
      debugPrint('Patient doctor refresh failed: $error');
    } finally {
      _isRefreshingDoctors = false;
    }
  }

  static bool _sameDoctorCatalogue(
    List<UserModel> previous,
    List<UserModel> current,
  ) {
    if (identical(previous, current)) return true;
    if (previous.length != current.length) return false;
    for (var index = 0; index < previous.length; index++) {
      final a = previous[index];
      final b = current[index];
      if (a.uid != b.uid ||
          a.name != b.name ||
          a.profileImage != b.profileImage ||
          a.isProfileCompleted != b.isProfileCompleted ||
          a.gender != b.gender ||
          a.title != b.title ||
          a.specialization != b.specialization ||
          a.qualification != b.qualification ||
          a.experienceYears != b.experienceYears ||
          a.consultationFee != b.consultationFee ||
          a.bio != b.bio ||
          a.introVideoUrl != b.introVideoUrl ||
          a.isDoctorVerified != b.isDoctorVerified ||
          a.isAvailable != b.isAvailable ||
          a.doctorRating != b.doctorRating ||
          a.doctorReviewCount != b.doctorReviewCount ||
          a.doctorCompletedConsultationCount !=
              b.doctorCompletedConsultationCount) {
        return false;
      }
    }
    return true;
  }

  static const _navItems = [
    NavBarItem(
      icon: Icons.medical_services_outlined,
      activeIcon: Icons.medical_services_outlined,
      label: 'Doctors',
    ),
    NavBarItem(
      icon: Icons.account_balance_wallet_outlined,
      activeIcon: Icons.account_balance_wallet_rounded,
      label: 'Wallet',
    ),
    NavBarItem(
      icon: Icons.person_outline_rounded,
      activeIcon: Icons.person_rounded,
      label: 'Profile',
    ),
  ];

  Future<void> _logout() async {
    if (isLoggingOut) return;

    final confirmed = await showDialog<bool>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: .52),
      builder: (dialogContext) => Dialog(
        elevation: 0,
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.symmetric(horizontal: 24),
        child: Container(
          padding: const EdgeInsets.fromLTRB(22, 25, 22, 18),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(22),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 58,
                height: 58,
                decoration: BoxDecoration(
                  color: const Color(0xFFF2F4F6),
                  shape: BoxShape.circle,
                  border: Border.all(color: const Color(0xFFE6E9ED)),
                ),
                child: const AppIcon(
                  Icons.logout_rounded,
                  color: Color(0xFF344054),
                  size: 27,
                ),
              ),
              const SizedBox(height: 17),
              Text(
                'Sign out?',
                style: GoogleFonts.outfit(
                  fontSize: 20,
                  fontWeight: FontWeight.w500,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'You can sign back in anytime to manage appointments, messages, and your wallet.',
                textAlign: TextAlign.center,
                style: GoogleFonts.outfit(
                  fontSize: 13,
                  height: 1.45,
                  color: AppColors.textSecondary,
                ),
              ),
              const SizedBox(height: 22),
              SizedBox(
                width: double.infinity,
                height: 47,
                child: FilledButton(
                  onPressed: () => Navigator.pop(dialogContext, true),
                  style: FilledButton.styleFrom(
                    elevation: 0,
                    backgroundColor: const Color(0xFFF2F4F6),
                    foregroundColor: AppColors.textPrimary,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(13),
                    ),
                  ),
                  child: Text(
                    'Sign out',
                    style: GoogleFonts.outfit(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 6),
              SizedBox(
                width: double.infinity,
                height: 42,
                child: TextButton(
                  onPressed: () => Navigator.pop(dialogContext, false),
                  child: Text(
                    'Stay signed in',
                    style: GoogleFonts.outfit(
                      fontSize: 13,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() {
      isLoggingOut = true;
    });

    try {
      await _loginRepository.logout();

      if (!mounted) return;

      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (_) => const SplashScreen()),
        (route) => false,
      );
    } catch (e) {
      if (!mounted) return;

      setState(() {
        isLoggingOut = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          backgroundColor: Colors.black87,
          content: Text(AppErrorMessage.from(e)),
        ),
      );
    }
  }

  void _openDoctorDetails(UserModel doctor) {
    // Tapping a doctor's row opens their details screen. If the doctor has an
    // intro video, DoctorDetailsScreen should play it at the top of the page,
    // with the rest of the profile/details content below it.
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => DoctorDetailsScreen(doctor: doctor)),
    );
  }

  void _openConsultation(UserModel doctor, {BookingModel? booking}) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => booking?.hasScheduledFollowUp == true
            ? DoctorDetailsScreen(doctor: doctor)
            : PatientConsultationRequestScreen(doctor: doctor),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        bottom: false,
        child: IndexedStack(
          index: _currentTabIndex,
          children: [
            _buildPinnedHomeTab(),
            _isGuest
                ? const GuestAccessView(
                    icon: Icons.account_balance_wallet_outlined,
                    title: 'Your wallet',
                    message: 'Login to view your balance and wallet activity.',
                  )
                : WalletTransactionsScreen(
                    refreshToken: _walletRefreshToken,
                    embedded: true,
                  ),
            _isGuest
                ? const GuestAccessView(
                    icon: Icons.person_outline_rounded,
                    title: 'Your profile',
                    message:
                        'Login to view and update your personal information.',
                  )
                : PatientProfileScreen(
                    refreshToken: _profileRefreshToken,
                    onLogout: _logout,
                    isLoggingOut: isLoggingOut,
                  ),
          ],
        ),
      ),
      bottomNavigationBar: AppBottomNavBar(
        showShadow: false,
        items: _navItems,
        currentIndex: _currentTabIndex,
        onTap: (index) {
          final returningHome = index == 0 && _currentTabIndex != 0;
          setState(() {
            _currentTabIndex = index;
            if (index == 1) _walletRefreshToken++;
            if (index == 2) _profileRefreshToken++;
          });
          if (returningHome) _refreshDoctors();
        },
      ),
    );
  }

  Widget _buildPinnedHomeTab() {
    return Column(
      children: [
        Container(
          color: Colors.white,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 12, 8),
                child: Row(
                  children: [
                    Image.asset(logoHome, height: 30, fit: BoxFit.contain),
                    const Spacer(),
                    IconButton(
                      tooltip: _showSearch ? 'Close search' : 'Search doctors',
                      constraints: const BoxConstraints.tightFor(
                        width: 48,
                        height: 48,
                      ),
                      onPressed: () => setState(() {
                        _showSearch = !_showSearch;
                        if (!_showSearch) {
                          _searchController.clear();
                          _searchQuery = '';
                        }
                      }),
                      icon: AppIcon(
                        _showSearch
                            ? Icons.close_rounded
                            : Icons.search_rounded,
                        size: _showSearch ? 24 : 21,
                        color: const Color(0xFF344054),
                      ),
                    ),
                  ],
                ),
              ),
              if (_showSearch)
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 10),
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(18),
                    ),
                    child: TextField(
                      controller: _searchController,
                      autofocus: true,
                      keyboardType: TextInputType.text,
                      textInputAction: TextInputAction.search,
                      onTapOutside: (_) => FocusScope.of(context).unfocus(),
                      onChanged: (value) => setState(
                        () => _searchQuery = value.trim().toLowerCase(),
                      ),
                      style: GoogleFonts.outfit(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        color: const Color(0xFF202A36),
                      ),
                      decoration: InputDecoration(
                        hintText: 'Search doctors or specialties',
                        hintStyle: GoogleFonts.outfit(
                          fontSize: 13.5,
                          color: const Color(0xFF98A1AD),
                        ),
                        prefixIcon: const Padding(
                          padding: EdgeInsets.only(left: 14, right: 10),
                          child: AppIcon(
                            Icons.search_rounded,
                            size: 20,
                            color: Color(0xFF485565),
                          ),
                        ),
                        prefixIconConstraints: const BoxConstraints(
                          minWidth: 44,
                          minHeight: 48,
                        ),
                        suffixIcon: _searchQuery.isEmpty
                            ? null
                            : IconButton(
                                tooltip: 'Clear search',
                                onPressed: () {
                                  _searchController.clear();
                                  setState(() => _searchQuery = '');
                                },
                                icon: const AppIcon(
                                  Icons.cancel_rounded,
                                  size: 20,
                                  color: Color(0xFF9AA3AE),
                                ),
                              ),
                        filled: true,
                        fillColor: const Color(0xFFF6F8FA),
                        contentPadding: const EdgeInsets.symmetric(
                          vertical: 14,
                          horizontal: 14,
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(18),
                          borderSide: BorderSide.none,
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(18),
                          borderSide: BorderSide.none,
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(18),
                          borderSide: BorderSide.none,
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
        Expanded(
          child: FutureBuilder<List<UserModel>>(
            future: _doctorsFuture,
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting &&
                  !snapshot.hasData) {
                return const _DoctorListShimmer();
              }
              if (snapshot.hasError) {
                return RefreshIndicator(
                  color: AppColors.brand,
                  onRefresh: _refreshDoctors,
                  child: ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    children: [
                      SizedBox(
                        height: MediaQuery.sizeOf(context).height * 0.18,
                      ),
                      _MessageState(
                        icon: Icons.error_outline_rounded,
                        message: AppErrorMessage.from(snapshot.error),
                      ),
                    ],
                  ),
                );
              }

              final rankedDoctors = snapshot.data ?? [];
              final originalRank = {
                for (var index = 0; index < rankedDoctors.length; index++)
                  rankedDoctors[index].uid: index,
              };
              final doctors =
                  rankedDoctors.where((doctor) {
                    if (_activeBookingByDoctor.containsKey(doctor.uid)) {
                      return true;
                    }
                    if (_searchQuery.isEmpty) return true;
                    return '${doctor.name} ${doctor.specialization ?? ''} ${doctor.title ?? ''}'
                        .toLowerCase()
                        .contains(_searchQuery);
                  }).toList()..sort((a, b) {
                    final aBooking = _activeBookingByDoctor[a.uid];
                    final bBooking = _activeBookingByDoctor[b.uid];
                    if (aBooking != null && bBooking == null) return -1;
                    if (aBooking == null && bBooking != null) return 1;
                    if (aBooking != null && bBooking != null) {
                      if (aBooking.hasUpcomingFollowUp !=
                          bBooking.hasUpcomingFollowUp) {
                        return aBooking.hasUpcomingFollowUp ? -1 : 1;
                      }
                      final statusOrder = _activeStatusPriority(
                        aBooking.status,
                      ).compareTo(_activeStatusPriority(bBooking.status));
                      if (statusOrder != 0) return statusOrder;
                      return bBooking.updatedAt.compareTo(aBooking.updatedAt);
                    }
                    return (originalRank[a.uid] ?? 0).compareTo(
                      originalRank[b.uid] ?? 0,
                    );
                  });

              if (doctors.isEmpty) {
                return RefreshIndicator(
                  color: AppColors.brand,
                  onRefresh: _refreshDoctors,
                  child: ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    children: [
                      SizedBox(
                        height: MediaQuery.sizeOf(context).height * 0.18,
                      ),
                      const _MessageState(
                        icon: Icons.search_off_rounded,
                        message: 'No doctors found.',
                      ),
                    ],
                  ),
                );
              }

              return RefreshIndicator(
                color: AppColors.brand,
                onRefresh: _refreshDoctors,
                child: ListView.builder(
                  physics: const AlwaysScrollableScrollPhysics(),
                  keyboardDismissBehavior:
                      ScrollViewKeyboardDismissBehavior.onDrag,
                  padding: const EdgeInsets.only(bottom: 24),
                  itemCount: doctors.length,

                  itemBuilder: (context, index) {
                    final doctor = doctors[index];
                    final priorityBooking = _activeBookingByDoctor[doctor.uid];
                    return PatientDoctorListTile(
                      key: ValueKey(doctor.uid),
                      doctor: doctor,
                      appointmentStatus: priorityBooking?.status,
                      followUpDate: priorityBooking?.followUpDate,
                      onTap: () =>
                          _openConsultation(doctor, booking: priorityBooking),
                      onTapPhoto: () {
                        final hasVideo =
                            doctor.introVideoUrl != null &&
                            doctor.introVideoUrl!.trim().isNotEmpty;
                        if (hasVideo) {
                          showDoctorVideoDialog(
                            context,
                            doctor,
                            onViewDetails: () => _openDoctorDetails(doctor),
                          );
                        } else {
                          _openDoctorDetails(doctor);
                        }
                      },
                    );
                  },
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  static int _activeStatusPriority(BookingStatus status) => switch (status) {
    BookingStatus.inProgress => 0,
    BookingStatus.accepted => 1,
    BookingStatus.pending => 2,
    _ => 3,
  };
}

class _DoctorListShimmer extends StatefulWidget {
  const _DoctorListShimmer();

  @override
  State<_DoctorListShimmer> createState() => _DoctorListShimmerState();
}

class _DoctorListShimmerState extends State<_DoctorListShimmer>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1350),
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final slide = (_controller.value * 4) - 2;
        return ShaderMask(
          blendMode: BlendMode.srcATop,
          shaderCallback: (bounds) => LinearGradient(
            begin: Alignment(slide - 1, 0),
            end: Alignment(slide + 1, 0),
            colors: const [
              Color(0xFFE9EDF1),
              Color(0xFFF8F9FA),
              Color(0xFFE9EDF1),
            ],
            stops: const [0.25, 0.5, 0.75],
          ).createShader(bounds),
          child: ListView.builder(
            physics: const NeverScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(22, 0, 22, 24),
            itemCount: 7,
            itemBuilder: (_, _) => const _DoctorSkeletonRow(),
          ),
        );
      },
    );
  }
}

class _DoctorSkeletonRow extends StatelessWidget {
  const _DoctorSkeletonRow();

  static const _color = Color(0xFFE2E6EA);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 15),
      child: Row(
        children: [
          const CircleAvatar(radius: 28, backgroundColor: _color),
          const SizedBox(width: 20),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 150,
                  height: 15,
                  decoration: BoxDecoration(
                    color: _color,
                    borderRadius: BorderRadius.circular(7),
                  ),
                ),
                const SizedBox(height: 9),
                Container(
                  width: 120,
                  height: 11,
                  decoration: BoxDecoration(
                    color: _color,
                    borderRadius: BorderRadius.circular(6),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _MessageState extends StatelessWidget {
  final IconData icon;
  final String message;

  const _MessageState({required this.icon, required this.message});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 20),
      child: Column(
        children: [
          AppIcon(icon, size: 34, color: AppColors.textSecondary),
          const SizedBox(height: 10),
          Text(
            message,
            textAlign: TextAlign.center,
            style: GoogleFonts.outfit(
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: AppColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}