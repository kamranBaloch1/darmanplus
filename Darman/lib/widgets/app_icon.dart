import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

/// Darman's single icon entry point.
///
/// Existing Material [IconData] values are translated to the Solar icon set so
/// screens can migrate without losing their current semantics. New code should
/// keep using [AppIcon] to preserve one consistent visual language.
class AppIcon extends StatelessWidget {
  const AppIcon(
    this.icon, {
    super.key,
    this.size,
    this.color,
    this.semanticLabel,
    this.textDirection,
    this.shadows,
    this.emphasized,
  });

  final IconData? icon;
  final double? size;
  final Color? color;
  final String? semanticLabel;
  final TextDirection? textDirection;
  final List<Shadow>? shadows;

  /// Forces the Solar weight used by this instance. When omitted, outlined
  /// Material glyphs use Solar Linear and filled glyphs use Bold Duotone.
  final bool? emphasized;

  @override
  Widget build(BuildContext context) {
    if (icon == null) {
      return SizedBox.square(
        dimension: size ?? IconTheme.of(context).size ?? 24,
      );
    }

    final resolvedName = _solarIconNames[icon] ?? 'question-circle';
    final isEmphasized = emphasized ?? !_linearMaterialIcons.contains(icon);

    return _SolarAssetIcon(
      name: resolvedName,
      emphasized: isEmphasized,
      size: size,
      color: color,
      semanticLabel: semanticLabel,
      textDirection: textDirection,
      matchTextDirection: _directionalMaterialIcons.contains(icon),
      shadows: shadows,
    );
  }
}

class _SolarAssetIcon extends StatelessWidget {
  const _SolarAssetIcon({
    required this.name,
    required this.emphasized,
    required this.matchTextDirection,
    this.size,
    this.color,
    this.semanticLabel,
    this.textDirection,
    this.shadows,
  });

  final String name;
  final bool emphasized;
  final bool matchTextDirection;
  final double? size;
  final Color? color;
  final String? semanticLabel;
  final TextDirection? textDirection;
  final List<Shadow>? shadows;

  @override
  Widget build(BuildContext context) {
    final iconTheme = IconTheme.of(context);
    final resolvedSize = size ?? iconTheme.size ?? 24;
    final baseColor = color ?? iconTheme.color ?? const Color(0xDD000000);
    final opacity = iconTheme.opacity ?? 1;
    final resolvedColor = opacity < 1
        ? baseColor.withValues(alpha: baseColor.a * opacity)
        : baseColor;
    final styleFolder = emphasized ? 'bold_duotone' : 'linear';
    final assetPath = 'assets/icons/solar/$styleFolder/$name.svg';

    Widget picture = SvgPicture.asset(
      assetPath,
      width: resolvedSize,
      height: resolvedSize,
      colorFilter: ColorFilter.mode(resolvedColor, BlendMode.srcIn),
      fit: BoxFit.contain,
      matchTextDirection: matchTextDirection,
      semanticsLabel: semanticLabel,
    );
    picture = SizedBox.square(dimension: resolvedSize, child: picture);

    if (shadows case final shadows? when shadows.isNotEmpty) {
      picture = SizedBox.square(
        dimension: resolvedSize,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            for (final shadow in shadows)
              Positioned(
                left: shadow.offset.dx,
                top: shadow.offset.dy,
                child: ImageFiltered(
                  imageFilter: ImageFilter.blur(
                    sigmaX: shadow.blurRadius,
                    sigmaY: shadow.blurRadius,
                  ),
                  child: SvgPicture.asset(
                    assetPath,
                    width: resolvedSize,
                    height: resolvedSize,
                    colorFilter: ColorFilter.mode(
                      shadow.color,
                      BlendMode.srcIn,
                    ),
                    matchTextDirection: matchTextDirection,
                  ),
                ),
              ),
            picture,
          ],
        ),
      );
    }

    if (textDirection case final direction?) {
      picture = Directionality(textDirection: direction, child: picture);
    }

    // Match Flutter's Icon sizing behavior. Parents such as IconButton,
    // TextField and fixed-size circles often give their child tight
    // constraints. Without this shrink-wrapping alignment, SvgPicture expands
    // to those constraints and ignores the requested visual icon size.
    return Align(
      alignment: Alignment.center,
      widthFactor: 1,
      heightFactor: 1,
      child: picture,
    );
  }
}

final Map<IconData, String> _solarIconNames = <IconData, String>{
  Icons.access_time_rounded: 'clock-circle',
  Icons.accessibility_new_rounded: 'accessibility',
  Icons.account_balance_wallet_outlined: 'wallet-money',
  Icons.account_balance_wallet_rounded: 'wallet-money',
  Icons.add_rounded: 'add-circle',
  Icons.air_rounded: 'wind',
  Icons.arrow_back_ios_new_rounded: 'alt-arrow-left',
  Icons.arrow_back_rounded: 'arrow-left',
  Icons.arrow_forward_rounded: 'arrow-right',
  Icons.attach_file_rounded: 'paperclip-rounded',
  Icons.bedtime_rounded: 'moon-sleep',
  Icons.biotech_rounded: 'dna',
  Icons.block_rounded: 'forbidden-circle',
  Icons.bloodtype_rounded: 'dropper-3',
  Icons.broken_image_outlined: 'gallery-remove',
  Icons.cake_outlined: 'gift',
  Icons.calendar_month_outlined: 'calendar',
  Icons.calendar_month_rounded: 'calendar',
  Icons.calendar_today_outlined: 'calendar-date',
  Icons.call_end: 'end-call-rounded',
  Icons.call_end_rounded: 'end-call-rounded',
  Icons.camera_alt_rounded: 'camera',
  Icons.cameraswitch_rounded: 'camera-rotate',
  Icons.cancel_rounded: 'close-circle',
  Icons.chat_bubble_outline_rounded: 'chat-round-dots',
  Icons.chat_bubble_rounded: 'chat-round-dots',
  Icons.check_circle_outline_rounded: 'check-circle',
  Icons.check_circle_rounded: 'check-circle',
  Icons.check_rounded: 'check-read',
  Icons.chevron_right_rounded: 'alt-arrow-right',
  Icons.child_care_rounded: 'user-heart-rounded',
  Icons.circle: 'record-circle',
  Icons.circle_outlined: 'record-circle',
  Icons.close_rounded: 'close',
  Icons.coronavirus_rounded: 'virus',
  Icons.delete_outline_rounded: 'trash-bin-trash',
  Icons.description_outlined: 'document-text',
  Icons.directions_run_rounded: 'running-2',
  Icons.done_all_rounded: 'check-read',
  Icons.done_rounded: 'check-read',
  Icons.download_rounded: 'download-minimalistic',
  Icons.edit_rounded: 'pen-2',
  Icons.elderly_rounded: 'walking-round',
  Icons.emergency_rounded: 'siren-rounded',
  Icons.error_outline: 'danger-circle',
  Icons.error_outline_rounded: 'danger-circle',
  Icons.event_available_outlined: 'calendar-mark',
  Icons.event_busy_outlined: 'calendar-search',
  Icons.event_busy_rounded: 'calendar-search',
  Icons.event_repeat_outlined: 'routing',
  Icons.event_repeat_rounded: 'routing',
  Icons.expand_less: 'alt-arrow-up',
  Icons.expand_more: 'alt-arrow-down',
  Icons.expand_more_rounded: 'alt-arrow-down',
  Icons.face_retouching_natural_rounded: 'user-circle',
  Icons.face_rounded: 'user-circle',
  Icons.family_restroom_rounded: 'users-group-two-rounded',
  Icons.favorite_border_rounded: 'heart',
  Icons.favorite_rounded: 'heart',
  Icons.forum_outlined: 'chat-square-2',
  Icons.forward_10_rounded: 'rewind-10-seconds-forward',
  Icons.fullscreen_exit_rounded: 'quit-full-screen',
  Icons.fullscreen_rounded: 'full-screen',
  Icons.healing_rounded: 'adhesive-plaster',
  Icons.health_and_safety_rounded: 'shield-check',
  Icons.hearing_rounded: 'headphones-round-sound',
  Icons.history_rounded: 'history-2',
  Icons.home_outlined: 'home-2',
  Icons.hourglass_top_rounded: 'hourglass',
  Icons.image_outlined: 'gallery',
  Icons.image_search_rounded: 'gallery-minimalistic',
  Icons.info_outline_rounded: 'info-circle',
  Icons.keyboard_arrow_down_rounded: 'alt-arrow-down',
  Icons.local_dining_rounded: 'chef-hat-minimalistic',
  Icons.local_hospital_rounded: 'hospital',
  Icons.lock_outline_rounded: 'lock-keyhole',
  Icons.lock_rounded: 'lock-keyhole',
  Icons.logout_rounded: 'logout-2',
  Icons.manage_accounts_outlined: 'user-id',
  Icons.medical_information_rounded: 'document-medicine',
  Icons.medical_services_outlined: 'stethoscope',
  Icons.medical_services_rounded: 'stethoscope',
  Icons.medication_rounded: 'pills-3',
  Icons.mic_none_rounded: 'microphone',
  Icons.mic_off_rounded: 'microphone-3',
  Icons.mic_rounded: 'microphone',
  Icons.monitor_heart_rounded: 'heart-pulse',
  Icons.north_east_rounded: 'arrow-right-up',
  Icons.notifications_active_outlined: 'bell-ring',
  Icons.notifications_none_rounded: 'bell',
  Icons.open_in_new_rounded: 'square-arrow-right-up',
  Icons.pause_rounded: 'pause',
  Icons.payments_outlined: 'banknote-2',
  Icons.pending_actions_rounded: 'clock-square',
  Icons.person: 'user-rounded',
  Icons.person_off_outlined: 'user-cross-rounded',
  Icons.person_outline_rounded: 'user-rounded',
  Icons.person_rounded: 'user-rounded',
  Icons.phone_in_talk_rounded: 'phone-calling-rounded',
  Icons.phone_outlined: 'phone-rounded',
  Icons.photo_camera_outlined: 'camera',
  Icons.photo_camera_rounded: 'camera',
  Icons.photo_library_outlined: 'gallery',
  Icons.picture_as_pdf_outlined: 'document-text',
  Icons.picture_as_pdf_rounded: 'document-text',
  Icons.play_arrow_rounded: 'play',
  Icons.pregnant_woman_rounded: 'user-heart-rounded',
  Icons.privacy_tip_outlined: 'shield-keyhole',
  Icons.psychology_alt_rounded: 'brain',
  Icons.psychology_rounded: 'brain',
  Icons.radio_button_unchecked_rounded: 'record-circle',
  Icons.rate_review_outlined: 'chat-square-like',
  Icons.record_voice_over_rounded: 'user-speak-rounded',
  Icons.refresh_rounded: 'refresh',
  Icons.replay_10_rounded: 'rewind-10-seconds-back',
  Icons.reply_rounded: 'reply-2',
  Icons.restaurant_menu_rounded: 'chef-hat',
  Icons.restaurant_rounded: 'chef-hat-minimalistic',
  Icons.schedule_rounded: 'clock-circle',
  Icons.school_outlined: 'square-academic-cap',
  Icons.science_rounded: 'test-tube',
  Icons.search_off_rounded: 'magnifier-bug',
  Icons.search_rounded: 'magnifier',
  Icons.self_improvement_rounded: 'meditation-round',
  Icons.send_rounded: 'plane',
  Icons.sentiment_satisfied_alt_rounded: 'smile-circle',
  Icons.settings_rounded: 'settings',
  Icons.shield_outlined: 'shield',
  Icons.signal_wifi_statusbar_connected_no_internet_4_rounded: 'wi-fi-cross',
  Icons.south_west_rounded: 'arrow-left-down',
  Icons.sports_rounded: 'dumbbell',
  Icons.star_border_rounded: 'star',
  Icons.star_rounded: 'star',
  Icons.stop_circle_outlined: 'stop-circle',
  Icons.support_agent_rounded: 'headphones-round-sound',
  Icons.task_alt_rounded: 'checklist-minimalistic',
  Icons.timer_outlined: 'stopwatch',
  Icons.trending_up_rounded: 'chart-2',
  Icons.undo_rounded: 'undo-left',
  Icons.upload_file_rounded: 'file-send',
  Icons.verified_rounded: 'verified-check',
  Icons.verified_user_outlined: 'shield-user',
  Icons.video_call_rounded: 'chat-round-video',
  Icons.videocam: 'videocamera',
  Icons.videocam_off_rounded: 'videocamera-off',
  Icons.videocam_outlined: 'videocamera',
  Icons.videocam_rounded: 'videocamera',
  Icons.visibility_rounded: 'eye',
  Icons.volume_off_rounded: 'volume-cross',
  Icons.volume_up_rounded: 'volume-loud',
  Icons.volunteer_activism_rounded: 'hand-heart',
  Icons.wallet_outlined: 'wallet',
  Icons.water_drop_rounded: 'waterdrop',
  Icons.wifi_off_rounded: 'wi-fi-off',
  Icons.wifi_rounded: 'wi-fi',
  Icons.workspace_premium_rounded: 'crown-star',
};

final Set<IconData> _linearMaterialIcons = <IconData>{
  Icons.account_balance_wallet_outlined,
  Icons.arrow_back_ios_new_rounded,
  Icons.arrow_back_rounded,
  Icons.arrow_forward_rounded,
  Icons.attach_file_rounded,
  Icons.broken_image_outlined,
  Icons.cake_outlined,
  Icons.calendar_month_outlined,
  Icons.calendar_today_outlined,
  Icons.chat_bubble_outline_rounded,
  Icons.check_circle_outline_rounded,
  Icons.chevron_right_rounded,
  Icons.circle_outlined,
  Icons.close_rounded,
  Icons.delete_outline_rounded,
  Icons.description_outlined,
  Icons.error_outline,
  Icons.error_outline_rounded,
  Icons.event_available_outlined,
  Icons.event_busy_outlined,
  Icons.event_repeat_outlined,
  Icons.expand_less,
  Icons.expand_more,
  Icons.expand_more_rounded,
  Icons.favorite_border_rounded,
  Icons.forum_outlined,
  Icons.home_outlined,
  Icons.image_outlined,
  Icons.info_outline_rounded,
  Icons.keyboard_arrow_down_rounded,
  Icons.lock_outline_rounded,
  Icons.manage_accounts_outlined,
  Icons.medical_services_outlined,
  Icons.mic_none_rounded,
  Icons.north_east_rounded,
  Icons.notifications_active_outlined,
  Icons.open_in_new_rounded,
  Icons.payments_outlined,
  Icons.person_off_outlined,
  Icons.person_outline_rounded,
  Icons.phone_outlined,
  Icons.photo_camera_outlined,
  Icons.photo_library_outlined,
  Icons.picture_as_pdf_outlined,
  Icons.privacy_tip_outlined,
  Icons.radio_button_unchecked_rounded,
  Icons.rate_review_outlined,
  Icons.reply_rounded,
  Icons.school_outlined,
  Icons.search_off_rounded,
  Icons.search_rounded,
  Icons.shield_outlined,
  Icons.signal_wifi_statusbar_connected_no_internet_4_rounded,
  Icons.south_west_rounded,
  Icons.star_border_rounded,
  Icons.stop_circle_outlined,
  Icons.timer_outlined,
  Icons.upload_file_rounded,
  Icons.verified_user_outlined,
  Icons.videocam_outlined,
  Icons.wallet_outlined,
  Icons.wifi_off_rounded,
};

final Set<IconData> _directionalMaterialIcons = <IconData>{
  Icons.arrow_back_ios_new_rounded,
  Icons.arrow_back_rounded,
  Icons.arrow_forward_rounded,
  Icons.chevron_right_rounded,
  Icons.north_east_rounded,
  Icons.reply_rounded,
  Icons.south_west_rounded,
};