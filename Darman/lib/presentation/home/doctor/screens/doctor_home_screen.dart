import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:darmaan/presentation/home/doctor/screens/doctor_appointments_screen.dart';
import 'package:darmaan/presentation/home/doctor/screens/doctor_follow_ups_screen.dart';
import 'package:darmaan/presentation/home/doctor/screens/doctor_profile_screen.dart';
import 'package:darmaan/presentation/home/wallet/screens/wallet_transactions_screen.dart';
import 'package:darmaan/widgets/app_bottom_nav_bar.dart';
import 'package:darmaan/widgets/complete_doctor_profile_dialog.dart';
import 'package:darmaan/widgets/app_shimmer.dart';
import 'package:darmaan/presentation/home/doctor/repository/doctor_profile_repository.dart';
import 'package:flutter/material.dart';

class DoctorHomeScreen extends StatefulWidget {
  const DoctorHomeScreen({super.key});

  @override
  State<DoctorHomeScreen> createState() => _DoctorHomeScreenState();
}

class _DoctorHomeScreenState extends State<DoctorHomeScreen> {
  final DoctorProfileRepository _profileRepository = DoctorProfileRepository();
  int _currentIndex = 0;
  int _homeRefreshToken = 0;
  int _followUpsRefreshToken = 0;
  int _walletRefreshToken = 0;
  bool _checkingProfile = true;
  bool _profileComplete = false;
  bool _profileDialogVisible = false;
  bool _isOnline = false;
  bool _isUpdatingAvailability = false;
  bool _hasNetwork = true;
  StreamSubscription<List<ConnectivityResult>>? _connectivitySubscription;

  @override
  void initState() {
    super.initState();
    _watchConnectivity();
    _checkProfileCompletion();
  }

  Future<void> _watchConnectivity() async {
    void update(List<ConnectivityResult> results) {
      final connected =
          results.isNotEmpty &&
          results.any((result) => result != ConnectivityResult.none);
      if (!mounted || connected == _hasNetwork) return;
      setState(() {
        _hasNetwork = connected;
        if (!connected) {
          _isOnline = false;
        } else {
          _homeRefreshToken++;
          _followUpsRefreshToken++;
          _walletRefreshToken++;
        }
      });
      if (connected) _checkProfileCompletion();
    }

    try {
      update(await Connectivity().checkConnectivity());
      _connectivitySubscription = Connectivity().onConnectivityChanged.listen(
        update,
      );
    } catch (_) {}
  }

  @override
  void dispose() {
    _connectivitySubscription?.cancel();
    super.dispose();
  }

  Future<void> _checkProfileCompletion() async {
    var complete = false;
    var isAvailable = false;
    try {
      final user = await _profileRepository.getDoctorProfile();
      complete = user.isProfileCompleted && user.doctorProfileCompletion >= 1;
      isAvailable = user.isAvailable;
      if (!complete && user.isAvailable) {
        await _profileRepository.updateAvailability(false);
      }
    } catch (_) {
      complete = false;
    }
    if (!mounted) return;
    setState(() {
      _profileComplete = complete;
      _isOnline = _hasNetwork && complete && isAvailable;
      _checkingProfile = false;
      if (!complete) _currentIndex = 3;
    });
    if (!complete) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _showCompletionDialog();
      });
    }
  }

  Future<void> _showCompletionDialog() async {
    if (_profileDialogVisible || !mounted) return;
    _profileDialogVisible = true;
    await showCompleteDoctorProfileDialog(context);
    _profileDialogVisible = false;
  }

  void _onProfileCompletionChanged(bool complete) {
    if (!mounted) return;
    final becameComplete = !_profileComplete && complete;
    setState(() {
      _profileComplete = complete;
      if (!complete) _currentIndex = 3;
    });
    if (becameComplete && !_isOnline) {
      _toggleAvailability(true);
    }
  }

  Future<void> _toggleAvailability(bool value) async {
    if (_isUpdatingAvailability || _isOnline == value) return;
    if (!_hasNetwork) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(
            behavior: SnackBarBehavior.floating,
            content: Text('Connect to the internet to change availability'),
          ),
        );
      return;
    }
    if (value && !_profileComplete) {
      await _showCompletionDialog();
      return;
    }

    final previous = _isOnline;
    setState(() {
      _isOnline = value;
      _isUpdatingAvailability = true;
    });

    try {
      await _profileRepository.updateAvailability(value);
    } catch (error) {
      if (!mounted) return;
      setState(() => _isOnline = previous);
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(
            behavior: SnackBarBehavior.floating,
            content: Text('Could not update availability'),
          ),
        );
      debugPrint('Availability update failed: $error');
    } finally {
      if (mounted) setState(() => _isUpdatingAvailability = false);
    }
  }

  static const List<NavBarItem> _navItems = [
    NavBarItem(
      icon: Icons.calendar_today_outlined,
      activeIcon: Icons.calendar_today_outlined,
      label: 'Appointments',
    ),
    NavBarItem(
      icon: Icons.event_repeat_outlined,
      activeIcon: Icons.event_repeat_rounded,
      label: 'Follow-ups',
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

  @override
  Widget build(BuildContext context) {
    if (_checkingProfile) {
      return const Scaffold(
        backgroundColor: Colors.white,
        body: SafeArea(child: AppProfileShimmer()),
      );
    }
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: IndexedStack(
          index: _currentIndex,
          children: [
            DoctorAppointmentsScreen(
              homeOnly: true,
              refreshToken: _homeRefreshToken,
              isOnline: _isOnline,
              isUpdatingAvailability: _isUpdatingAvailability,
              onAvailabilityChanged: _toggleAvailability,
            ),
            DoctorFollowUpsScreen(
              refreshToken: _followUpsRefreshToken,
            ),
            WalletTransactionsScreen(
              isDoctor: true,
              embedded: true,
              refreshToken: _walletRefreshToken,
            ),
            DoctorProfileScreen(
              onCompletionChanged: _onProfileCompletionChanged,
            ),
          ],
        ),
      ),
      bottomNavigationBar: AppBottomNavBar(
        items: _navItems,
        currentIndex: _currentIndex,
        onTap: (index) {
          if (!_profileComplete && index != 3) {
            setState(() => _currentIndex = 3);
            _showCompletionDialog();
            return;
          }
          setState(() {
            _currentIndex = index;
            if (index == 0) _homeRefreshToken++;
            if (index == 1) _followUpsRefreshToken++;
            if (index == 2) _walletRefreshToken++;
          });
        },
      ),
    );
  }
}
