import 'package:darmaan/core/helpers/patient_completion_coordinator.dart';
import 'package:darmaan/core/helpers/patient_session_start_coordinator.dart';
import 'package:darmaan/core/helpers/push_notification_service.dart';
import 'package:darmaan/core/helpers/chat_notification_coordinator.dart';
import 'package:darmaan/core/helpers/doctor_rating_coordinator.dart';
import 'package:darmaan/core/helpers/consultation_progress_coordinator.dart';
import 'package:darmaan/core/helpers/follow_up_end_coordinator.dart';
import 'package:darmaan/core/models/user_model.dart';
import 'package:darmaan/core/services/offline_cache_service.dart';
import 'package:darmaan/presentation/auth/repository/register/user_repository.dart';
import 'package:darmaan/presentation/auth/screens/register/choose_role_screen.dart';
import 'package:darmaan/presentation/auth/screens/register/doctor_document_screen.dart';
import 'package:darmaan/presentation/auth/screens/register/doctor_verification_screen.dart';
import 'package:darmaan/presentation/auth/screens/register/patient_profile_setup_screen.dart';
import 'package:darmaan/presentation/home/doctor/screens/doctor_home_screen.dart';
import 'package:darmaan/presentation/home/patient/screens/patient_home_screen.dart';
import 'package:darmaan/presentation/home/video_call/incoming_call_coordinator.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class AuthNavigator {
  static final UserRepository _userRepository = UserRepository();

  static Future<void> goToCorrectScreen(
    BuildContext context,
  ) async {
    UserModel? user;
    final prioritizingAcceptedCall =
        PushNotificationService.instance.hasPendingAcceptedIncomingCall;

    try {
      if (prioritizingAcceptedCall) {
        final userId = Supabase.instance.client.auth.currentUser?.id;
        user = await OfflineCacheService.instance.readUser(userId);
      }
      user ??= await _userRepository.getCurrentUser();
    } catch (_) {
      user = null;
    }

    if (!context.mounted) return;

    /*
     * Register the FCM device token for:
     * Every user whose public profile row has been created.
     *
     * Notification registration failure must not prevent
     * the user from entering the application.
     */
    final isOffline = prioritizingAcceptedCall
        ? false
        : await OfflineCacheService.instance.isDeviceOffline;
    if (!context.mounted) return;
    final shouldActivateNotifications =
        !isOffline &&
        user != null;

    if (shouldActivateNotifications && !prioritizingAcceptedCall) {
      try {
        await PushNotificationService.instance
            .activateForSignedInUser();
      } catch (error) {
        debugPrint(
          'Push notification registration failed: $error',
        );
      }

      if (!context.mounted) return;
    }

    final Widget target;

    if (user == null) {
      target = const ChooseRoleScreen();
    } else if (user.isPatient && !_isPatientProfileComplete(user)) {
      target = const PatientProfileSetupScreen();
    } else if (user.isPatient) {
      target = const IncomingCallCoordinator(
        child: ChatNotificationCoordinator(
          child: ConsultationProgressCoordinator(
            child: FollowUpEndCoordinator(
              child: PatientSessionStartCoordinator(
                child: PatientCompletionCoordinator(
                  child: PatientHomeScreen(),
                ),
              ),
            ),
          ),
        ),
      );
    } else if (user.doctorDocuments.isEmpty) {
      target = const DoctorDocumentScreen();
    } else if (!user.isDoctorVerified) {
      target = const DoctorVerificationPendingScreen();
    } else {
      target = const IncomingCallCoordinator(
        child: ChatNotificationCoordinator(
          child: ConsultationProgressCoordinator(
            child: FollowUpEndCoordinator(
              child: DoctorRatingCoordinator(
                child: DoctorHomeScreen(),
              ),
            ),
          ),
        ),
      );
    }

    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(
        builder: (_) => target,
      ),
      (route) => false,
    );
  }

  static bool _isPatientProfileComplete(UserModel user) {
    final name = user.name.trim();
    return user.isProfileCompleted &&
        name.length >= 2 &&
        name.toLowerCase() != 'user' &&
        user.profileImage?.trim().isNotEmpty == true &&
        user.gender?.trim().isNotEmpty == true;
  }
}
