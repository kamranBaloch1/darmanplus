import 'dart:async';
import 'dart:math' as math;

import 'package:agora_rtc_engine/agora_rtc_engine.dart';
import 'package:darmaan/core/models/consultation_session_model.dart';
import 'package:darmaan/core/models/video_call_access.dart';
import 'package:darmaan/core/utils/app_error_message.dart';
import 'package:darmaan/presentation/home/chat/chat_repository.dart';
import 'package:darmaan/presentation/home/chat/chat_room.dart';
import 'package:darmaan/presentation/home/video_call/video_call_repository.dart';
import 'package:darmaan/widgets/app_icon.dart';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:permission_handler/permission_handler.dart';

class VideoCallScreen extends StatefulWidget {
  const VideoCallScreen({
    super.key,
    required this.bookingId,
    required this.peerName,
    required this.isDoctor,
    this.peerAvatarUrl,
    this.peerSubtitle = '',
    this.peerVerified = false,
  });

  final String bookingId;
  final String peerName;
  final bool isDoctor;
  final String? peerAvatarUrl;
  final String peerSubtitle;
  final bool peerVerified;

  @override
  State<VideoCallScreen> createState() => _VideoCallScreenState();
}

class _VideoCallScreenState extends State<VideoCallScreen> {
  final VideoCallRepository _repository = VideoCallRepository();
  final ChatRepository _chatRepository = ChatRepository();

  RtcEngine? _engine;
  VideoCallAccess? _access;
  int? _remoteUid;
  RtcConnection? _remoteConnection;

  bool _muted = false;
  bool _cameraOff = false;
  bool _speaker = true;
  bool _leaving = false;
  bool _joinedChannel = false;
  bool _chatOpening = false;
  bool _initializing = false;
  bool _usingFrontCamera = true;
  bool _isReconnecting = false;
  bool _poorConnection = false;
  bool _remoteVideoReady = false;
  bool _remoteVideoMuted = false;
  bool _remoteAudioMuted = false;
  bool _permissionPermanentlyDenied = false;
  bool _localVideoReady = false;

  String _status = 'Preparing secure video call…';
  String? _error;
  Offset? _previewOffset;

  Timer? _tokenTimer;
  Timer? _callTimer;
  Timer? _connectionWatchdog;
  Timer? _networkQualityTimer;
  Timer? _remoteVideoWatchdog;
  Duration _callDuration = Duration.zero;
  StreamSubscription<ConsultationSessionModel>? _bookingSubscription;

  @override
  void initState() {
    super.initState();
    _bookingSubscription = _chatRepository
        .watchSession(widget.bookingId)
        .listen(
          (session) {
            if (!mounted) return;
            if (session.isEnded ||
                (_joinedChannel && session.callEndedAt != null)) {
              _leave();
            }
          },
          onError: (_) {
            // Agora remains authoritative for the live media connection when
            // the booking realtime stream is temporarily unavailable.
          },
        );
    _initialize();
  }

  Future<void> _initialize() async {
    if (_initializing || _leaving) return;
    _initializing = true;
    _connectionWatchdog?.cancel();

    if (mounted) {
      setState(() {
        _error = null;
        _permissionPermanentlyDenied = false;
        _status = 'Connecting…';
        _isReconnecting = false;
        _joinedChannel = false;
        _remoteUid = null;
        _remoteConnection = null;
        _remoteVideoReady = false;
        _remoteVideoMuted = false;
        _remoteAudioMuted = false;
        _localVideoReady = false;
      });
    }

    final permissions = await [
      Permission.camera,
      Permission.microphone,
    ].request();
    final denied = permissions.values.any((status) => !status.isGranted);
    if (denied) {
      _permissionPermanentlyDenied = permissions.values.any(
        (status) => status.isPermanentlyDenied,
      );
      if (mounted) {
        setState(() {
          _error = 'Camera and microphone access are required for video calls.';
          _isReconnecting = false;
        });
      }
      _initializing = false;
      return;
    }

    try {
      await _releaseEngine();
      final access = await _repository.getAccess(widget.bookingId);
      if (_leaving) return;

      final engine = createAgoraRtcEngine();
      await engine.initialize(RtcEngineContext(appId: access.appId));
      if (_leaving) {
        await engine.release();
        return;
      }

      _engine = engine;
      _access = access;
      _registerEngineEvents(engine);
      await _configureEngine(engine);

      await engine.enableAudio();
      await engine.enableVideo();
      try {
        await engine.setVideoEncoderConfiguration(
          const VideoEncoderConfiguration(
            dimensions: VideoDimensions(width: 640, height: 360),
            frameRate: 15,
            orientationMode: OrientationMode.orientationModeAdaptive,
            degradationPreference: DegradationPreference.maintainBalanced,
          ),
        );
      } catch (_) {}

      _usingFrontCamera = true;
      try {
        await engine.setLocalRenderMode(
          renderMode: RenderModeType.renderModeHidden,
          mirrorMode: VideoMirrorModeType.videoMirrorModeEnabled,
        );
        if (!_cameraOff) await engine.startPreview();
      } catch (_) {
        // A local preview problem must not prevent an audio/video channel join.
      }
      try {
        await engine.setEnableSpeakerphone(_speaker);
      } catch (_) {}

      if (mounted) setState(() {});
      await engine.joinChannel(
        token: access.token.trim(),
        channelId: access.channelName.trim(),
        uid: access.uid,
        options: ChannelMediaOptions(
          channelProfile: ChannelProfileType.channelProfileCommunication,
          clientRoleType: ClientRoleType.clientRoleBroadcaster,
          publishCameraTrack: !_cameraOff,
          publishMicrophoneTrack: true,
          autoSubscribeAudio: true,
          autoSubscribeVideo: true,
          enableAudioRecordingOrPlayout: true,
        ),
      );
      _scheduleTokenRenewal(access);

      _connectionWatchdog = Timer(const Duration(seconds: 25), () {
        if (mounted && !_joinedChannel && !_leaving) {
          _showFatalCallError(
            'The video service could not connect. Please retry the call.',
          );
        }
      });
    } catch (error) {
      if (mounted && !_leaving) {
        _showFatalCallError(
          AppErrorMessage.from(
            error,
            fallback: 'The video call could not connect. Please try again.',
          ),
        );
      }
    } finally {
      _initializing = false;
    }
  }

  Future<void> _configureEngine(RtcEngine engine) async {
    try {
      await engine.setAudioProfile(
        profile: AudioProfileType.audioProfileSpeechStandard,
        scenario: AudioScenarioType.audioScenarioMeeting,
      );
    } catch (_) {}
    try {
      await engine.setDefaultAudioRouteToSpeakerphone(true);
    } catch (_) {}
  }

  void _registerEngineEvents(RtcEngine engine) {
    bool isCurrentEngine() => mounted && identical(_engine, engine) && !_leaving;

    engine.registerEventHandler(
      RtcEngineEventHandler(
        onJoinChannelSuccess: (_, _) async {
          if (!isCurrentEngine()) return;
          _connectionWatchdog?.cancel();
          _joinedChannel = true;
          setState(() {
            _isReconnecting = false;
            _error = null;
            _status = _remoteUid == null
                ? 'Waiting for ${widget.peerName}…'
                : (_remoteVideoReady ? 'Connected' : 'Connecting video…');
          });
          try {
            await _repository.markJoined(widget.bookingId);
          } catch (_) {}
        },
        onUserJoined: (connection, uid, _) {
          if (!isCurrentEngine()) return;
          _remoteVideoWatchdog?.cancel();
          setState(() {
            _remoteUid = uid;
            _remoteConnection = connection;
            _remoteVideoReady = false;
            _remoteVideoMuted = false;
            _remoteAudioMuted = false;
            _status = 'Connecting video…';
          });
          _startCallTimer();
          _watchForRemoteVideo(engine, uid);
        },
        onFirstRemoteVideoDecoded: (_, uid, _, _, _) {
          if (!isCurrentEngine() || uid != _remoteUid) return;
          _markRemoteVideoReady();
        },
        onFirstRemoteVideoFrame: (_, uid, _, _, _) {
          if (!isCurrentEngine() || uid != _remoteUid) return;
          _markRemoteVideoReady();
        },
        onRemoteVideoStateChanged: (_, uid, state, reason, _) {
          if (!isCurrentEngine() || uid != _remoteUid) return;
          if (state == RemoteVideoState.remoteVideoStateDecoding) {
            _markRemoteVideoReady();
          } else if (state == RemoteVideoState.remoteVideoStateStarting) {
            setState(() {
              _remoteVideoReady = false;
              _status = 'Connecting video…';
            });
            _watchForRemoteVideo(engine, uid);
          } else if (reason ==
              RemoteVideoStateReason.remoteVideoStateReasonRemoteMuted) {
            setState(() {
              _remoteVideoMuted = true;
              _remoteVideoReady = false;
              _status = '${widget.peerName} turned off their camera';
            });
          } else if (reason ==
              RemoteVideoStateReason.remoteVideoStateReasonAudioFallback) {
            setState(() {
              _remoteVideoReady = false;
              _status = 'Video paused to keep the call connected';
            });
            _showPoorConnection();
          } else if (state == RemoteVideoState.remoteVideoStateFrozen ||
              reason == RemoteVideoStateReason.remoteVideoStateReasonNetworkCongestion) {
            _showPoorConnection();
          } else if (state == RemoteVideoState.remoteVideoStateFailed) {
            setState(() {
              _remoteVideoReady = false;
              _status = 'Video unavailable · Audio is still connected';
            });
          }
        },
        onRemoteVideoStats: (connection, stats) {
          final uid = stats.uid;
          if (!isCurrentEngine() || uid == null || uid != _remoteUid) return;
          if ((stats.rendererOutputFrameRate ?? 0) > 0) {
            _remoteConnection = connection;
            if (!_remoteVideoReady) _markRemoteVideoReady();
          }
        },
        onUserMuteVideo: (_, uid, muted) {
          if (!isCurrentEngine() || uid != _remoteUid) return;
          setState(() {
            _remoteVideoMuted = muted;
            if (muted) {
              _remoteVideoReady = false;
              _status = '${widget.peerName} turned off their camera';
            } else {
              _status = 'Connecting video…';
            }
          });
          if (!muted) _watchForRemoteVideo(engine, uid);
        },
        onUserMuteAudio: (_, uid, muted) {
          if (!isCurrentEngine() || uid != _remoteUid) return;
          setState(() => _remoteAudioMuted = muted);
        },
        onUserOffline: (_, uid, reason) {
          if (!isCurrentEngine() || uid != _remoteUid) return;
          setState(() {
            _remoteUid = null;
            _remoteConnection = null;
            _remoteVideoReady = false;
            _remoteVideoMuted = false;
            _remoteAudioMuted = false;
            _status = reason == UserOfflineReasonType.userOfflineDropped
                ? '${widget.peerName} is reconnecting…'
                : 'Waiting for ${widget.peerName}…';
          });
          _remoteVideoWatchdog?.cancel();
        },
        onLocalVideoStateChanged: (_, state, reason) {
          if (!isCurrentEngine()) return;
          if (state == LocalVideoStreamState.localVideoStreamStateCapturing ||
              state == LocalVideoStreamState.localVideoStreamStateEncoding) {
            if (!_localVideoReady) {
              setState(() => _localVideoReady = true);
            }
          } else if (state ==
                  LocalVideoStreamState.localVideoStreamStateFailed &&
              !_cameraOff) {
            setState(() {
              _localVideoReady = false;
              _status = reason ==
                      LocalVideoStreamReason.localVideoStreamReasonDeviceBusy
                  ? 'Camera is being used by another app'
                  : 'Audio connected · Camera unavailable';
            });
          } else if (state ==
                  LocalVideoStreamState.localVideoStreamStateStopped &&
              !_cameraOff) {
            setState(() => _localVideoReady = false);
          }
        },
        onPermissionError: (permissionType) {
          if (!isCurrentEngine()) return;
          _showMediaPermissionError(permissionType);
        },
        onConnectionStateChanged: (_, state, reason) {
          if (!isCurrentEngine()) return;
          if (_handleConnectionFailure(reason)) return;
          switch (state) {
            case ConnectionStateType.connectionStateConnecting:
              if (_joinedChannel) {
                _beginAgoraReconnect();
              } else {
                setState(() => _status = 'Connecting…');
              }
              break;
            case ConnectionStateType.connectionStateConnected:
              _connectionWatchdog?.cancel();
              setState(() {
                _isReconnecting = false;
                _error = null;
                _status = _remoteUid == null
                    ? 'Waiting for ${widget.peerName}…'
                    : (_remoteVideoReady ? 'Connected' : 'Connecting video…');
              });
              break;
            case ConnectionStateType.connectionStateReconnecting:
              _beginAgoraReconnect();
              break;
            case ConnectionStateType.connectionStateFailed:
              _showFatalCallError(
                'The video service could not connect. Please retry the call.',
              );
              break;
            case ConnectionStateType.connectionStateDisconnected:
              if (_joinedChannel) _beginAgoraReconnect();
              break;
          }
        },
        onConnectionInterrupted: (_) {
          if (isCurrentEngine()) _beginAgoraReconnect();
        },
        onConnectionLost: (_) {
          if (isCurrentEngine()) _beginAgoraReconnect();
        },
        onNetworkQuality: (_, uid, txQuality, rxQuality) {
          if (!isCurrentEngine()) return;
          if (uid == 0 || uid == _remoteUid) {
            if (_isBadQuality(txQuality) || _isBadQuality(rxQuality)) {
              _showPoorConnection();
            }
          }
        },
        onTokenPrivilegeWillExpire: (_, _) => _renewToken(),
        onRequestToken: (_) => _renewToken(),
        onError: (code, _) {
          if (!isCurrentEngine()) return;
          _handleAgoraError(code);
        },
      ),
    );
  }

  void _markRemoteVideoReady() {
    if (!mounted) return;
    _remoteVideoWatchdog?.cancel();
    _networkQualityTimer?.cancel();
    setState(() {
      _remoteVideoReady = true;
      _remoteVideoMuted = false;
      _poorConnection = false;
      _status = 'Connected';
    });
  }

  void _watchForRemoteVideo(RtcEngine engine, int uid) {
    _remoteVideoWatchdog?.cancel();
    _remoteVideoWatchdog = Timer(const Duration(seconds: 12), () async {
      if (!mounted ||
          _leaving ||
          !identical(_engine, engine) ||
          _remoteUid != uid ||
          _remoteVideoReady ||
          _remoteVideoMuted) {
        return;
      }
      try {
        await engine.muteRemoteVideoStream(uid: uid, mute: false);
        await engine.setRemoteVideoStreamType(
          uid: uid,
          streamType: VideoStreamType.videoStreamLow,
        );
      } catch (_) {}
      if (mounted && _remoteUid == uid && !_remoteVideoReady) {
        setState(() => _status = 'Audio connected · Waiting for video…');
        _showPoorConnection();
      }
    });
  }

  bool _handleConnectionFailure(ConnectionChangedReasonType reason) {
    switch (reason) {
      case ConnectionChangedReasonType.connectionChangedInvalidAppId:
      case ConnectionChangedReasonType.connectionChangedInvalidChannelName:
      case ConnectionChangedReasonType.connectionChangedInconsistentAppid:
        _showFatalCallError(
          'The video service is not configured correctly. Please end the call and try again later.',
        );
        return true;
      case ConnectionChangedReasonType.connectionChangedInvalidToken:
      case ConnectionChangedReasonType.connectionChangedTokenExpired:
        _showFatalCallError(
          'The secure call session could not be verified. Please retry the call.',
        );
        return true;
      case ConnectionChangedReasonType.connectionChangedJoinFailed:
      case ConnectionChangedReasonType.connectionChangedRejectedByServer:
      case ConnectionChangedReasonType.connectionChangedBannedByServer:
      case ConnectionChangedReasonType.connectionChangedSameUidLogin:
      case ConnectionChangedReasonType.connectionChangedTooManyBroadcasters:
      case ConnectionChangedReasonType.connectionChangedLicenseValidationFailure:
      case ConnectionChangedReasonType.connectionChangedCertificationVeryfyFailure:
      case ConnectionChangedReasonType.connectionChangedStreamChannelNotAvailable:
        _showFatalCallError(
          'The video call could not be joined. Please retry the call.',
        );
        return true;
      default:
        return false;
    }
  }

  void _handleAgoraError(ErrorCodeType code) {
    if (code == ErrorCodeType.errNoPermission) {
      _showMediaPermissionError(PermissionType.camera);
      return;
    }
    if (code == ErrorCodeType.errInvalidAppId ||
        code == ErrorCodeType.errInvalidChannelName) {
      _showFatalCallError(
        'The video service is not configured correctly. Please end the call and try again later.',
      );
      return;
    }
    if (code == ErrorCodeType.errInvalidToken ||
        code == ErrorCodeType.errTokenExpired ||
        code == ErrorCodeType.errJoinChannelRejected) {
      _showFatalCallError(
        'The video call could not connect. Please retry the call.',
      );
    }
  }

  void _showMediaPermissionError(PermissionType permissionType) {
    if (!mounted || _leaving) return;
    _connectionWatchdog?.cancel();
    setState(() {
      _isReconnecting = false;
      _permissionPermanentlyDenied = true;
      _error = permissionType == PermissionType.recordAudio
          ? 'Microphone access is required for video calls.'
          : 'Camera access is required for video calls.';
    });
  }

  void _showFatalCallError(String message) {
    if (!mounted || _leaving) return;
    _connectionWatchdog?.cancel();
    setState(() {
      _isReconnecting = false;
      _error = message;
    });
  }

  bool _isBadQuality(QualityType quality) =>
      quality == QualityType.qualityBad ||
      quality == QualityType.qualityVbad ||
      quality == QualityType.qualityDown;

  void _showPoorConnection() {
    if (!mounted) return;
    _networkQualityTimer?.cancel();
    setState(() => _poorConnection = true);
    _networkQualityTimer = Timer(const Duration(seconds: 6), () {
      if (mounted) setState(() => _poorConnection = false);
    });
  }

  void _beginAgoraReconnect() {
    if (!mounted || _leaving) return;
    setState(() {
      _isReconnecting = true;
      _status = 'Reconnecting…';
      _error = null;
    });
  }

  Future<void> _releaseEngine() async {
    final engine = _engine;
    _engine = null;
    _joinedChannel = false;
    _remoteUid = null;
    _remoteConnection = null;
    _remoteVideoReady = false;
    _localVideoReady = false;
    _remoteVideoWatchdog?.cancel();
    if (engine == null) return;
    try {
      await engine.leaveChannel();
    } catch (_) {}
    try {
      await engine.release();
    } catch (_) {}
  }

  Future<void> _retryConnection() async {
    _connectionWatchdog?.cancel();
    _tokenTimer?.cancel();
    await _releaseEngine();
    if (mounted) await _initialize();
  }

  void _startCallTimer() {
    if (_callTimer?.isActive == true) return;
    _callTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted && !_leaving) {
        setState(() => _callDuration += const Duration(seconds: 1));
      }
    });
  }

  String get _callTime {
    final hours = _callDuration.inHours;
    final minutes = _callDuration.inMinutes
        .remainder(60)
        .toString()
        .padLeft(2, '0');
    final seconds = _callDuration.inSeconds
        .remainder(60)
        .toString()
        .padLeft(2, '0');
    return hours > 0
        ? '${hours.toString().padLeft(2, '0')}:$minutes:$seconds'
        : '$minutes:$seconds';
  }

  String get _statusText {
    if (_isReconnecting) return 'Reconnecting…';
    if (_remoteUid != null) return _callTime;
    return _status;
  }

  void _scheduleTokenRenewal(VideoCallAccess access) {
    _tokenTimer?.cancel();
    final duration = access.expiresAt.difference(DateTime.now().toUtc()) -
        const Duration(minutes: 2);
    _tokenTimer = Timer(
      duration.isNegative ? Duration.zero : duration,
      _renewToken,
    );
  }

  Future<void> _renewToken() async {
    if (_leaving) return;
    try {
      final access = await _repository.getAccess(widget.bookingId);
      await _engine?.renewToken(access.token);
      _access = access;
      _scheduleTokenRenewal(access);
    } catch (_) {
      _tokenTimer?.cancel();
      _tokenTimer = Timer(const Duration(seconds: 10), _renewToken);
    }
  }

  Future<void> _leave({bool closeScreen = true}) async {
    if (_leaving) return;
    _leaving = true;
    _tokenTimer?.cancel();
    _callTimer?.cancel();
    _connectionWatchdog?.cancel();
    _networkQualityTimer?.cancel();
    _remoteVideoWatchdog?.cancel();
    try {
      await _repository.markLeft(widget.bookingId);
    } catch (_) {}
    await _releaseEngine();
    if (closeScreen && mounted) {
      final route = ModalRoute.of(context);
      if (route?.isCurrent == true) {
        await Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (_) => _buildChatScreen(callActive: false),
          ),
        );
      } else if (route != null) {
        Navigator.of(context).removeRoute(route);
      }
    }
  }

  ChatRoomScreen _buildChatScreen({required bool callActive}) => ChatRoomScreen(
        bookingId: widget.bookingId,
        peerName: widget.peerName,
        peerAvatarUrl: widget.peerAvatarUrl,
        peerSubtitle: widget.peerSubtitle.isEmpty
            ? (widget.isDoctor ? 'Patient' : 'Doctor')
            : widget.peerSubtitle,
        peerVerified: widget.peerVerified,
        onReturnToCall: callActive
            ? () {
                if (mounted) Navigator.pop(context);
              }
            : null,
      );

  Future<void> _openChatDuringCall() async {
    if (_leaving || _chatOpening || !mounted) return;
    _chatOpening = true;
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => _buildChatScreen(callActive: true)),
    );
    _chatOpening = false;
  }

  Future<void> _hangUp() async {
    if (_leaving) return;
    try {
      await _repository.endCall(widget.bookingId);
    } catch (_) {
      // Leaving Agora still ends local media immediately. The remote client
      // receives the offline event even if the database update is delayed.
    }
    await _leave();
  }

  Future<void> _toggleMute() async {
    final previous = _muted;
    setState(() => _muted = !previous);
    try {
      await _engine?.muteLocalAudioStream(_muted);
    } catch (_) {
      if (mounted) {
        setState(() => _muted = previous);
        _showControlError('Could not change the microphone.');
      }
    }
  }

  Future<void> _toggleCamera() async {
    final previous = _cameraOff;
    setState(() => _cameraOff = !previous);
    final engine = _engine;
    if (engine == null) return;
    try {
      if (_cameraOff) {
        await engine.muteLocalVideoStream(true);
        if (_joinedChannel) {
          await engine.updateChannelMediaOptions(
            const ChannelMediaOptions(publishCameraTrack: false),
          );
        }
        await engine.enableLocalVideo(false);
        if (mounted) setState(() => _localVideoReady = false);
      } else {
        await engine.enableLocalVideo(true);
        if (_joinedChannel) {
          await engine.updateChannelMediaOptions(
            const ChannelMediaOptions(publishCameraTrack: true),
          );
        }
        await engine.muteLocalVideoStream(false);
        await engine.startPreview();
      }
    } catch (_) {
      if (mounted) {
        setState(() => _cameraOff = previous);
        _showControlError('Could not change the camera.');
      }
    }
  }

  Future<void> _toggleSpeaker() async {
    final previous = _speaker;
    setState(() => _speaker = !previous);
    try {
      await _engine?.setEnableSpeakerphone(_speaker);
    } catch (_) {
      if (mounted) {
        setState(() => _speaker = previous);
        _showControlError('Could not change the audio output.');
      }
    }
  }

  Future<void> _switchCamera() async {
    final engine = _engine;
    if (engine == null || _leaving || _cameraOff) return;
    try {
      await engine.switchCamera();
      _usingFrontCamera = !_usingFrontCamera;
      await engine.setLocalRenderMode(
        renderMode: RenderModeType.renderModeHidden,
        mirrorMode: _usingFrontCamera
            ? VideoMirrorModeType.videoMirrorModeEnabled
            : VideoMirrorModeType.videoMirrorModeDisabled,
      );
      if (mounted) setState(() {});
    } catch (_) {
      if (mounted) _showControlError('Could not switch the camera.');
    }
  }

  void _showControlError(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          behavior: SnackBarBehavior.floating,
          backgroundColor: const Color(0xFF25313A),
        ),
      );
  }

  @override
  void dispose() {
    _bookingSubscription?.cancel();
    _tokenTimer?.cancel();
    _callTimer?.cancel();
    _connectionWatchdog?.cancel();
    _networkQualityTimer?.cancel();
    _remoteVideoWatchdog?.cancel();
    _leave(closeScreen: false);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _openChatDuringCall();
      },
      child: Scaffold(
        backgroundColor: const Color(0xFF111A20),
        body: SafeArea(
          child: _error != null
              ? _CallErrorState(
                  peerName: widget.peerName,
                  avatarUrl: widget.peerAvatarUrl,
                  message: _error!,
                  permissionDenied: _permissionPermanentlyDenied,
                  retry: _permissionPermanentlyDenied
                      ? openAppSettings
                      : _retryConnection,
                  endCall: _hangUp,
                )
              : LayoutBuilder(
                  builder: (context, constraints) => Stack(
                    children: [
                      Positioned.fill(child: _mainStage()),
                      if (_engine != null && _access != null)
                        _localPreview(constraints),
                      _topBar(),
                      if (_isReconnecting || _poorConnection)
                        Positioned(
                          top: 82,
                          left: 20,
                          right: 20,
                          child: Center(
                            child: _ConnectionPill(
                              reconnecting: _isReconnecting,
                            ),
                          ),
                        ),
                      _bottomControls(),
                    ],
                  ),
                ),
        ),
      ),
    );
  }

  Widget _mainStage() {
    final canRenderRemote = _engine != null &&
        _access != null &&
        _remoteUid != null &&
        _remoteConnection != null;
    return Stack(
      fit: StackFit.expand,
      children: [
        const ColoredBox(color: Color(0xFF111A20)),
        if (canRenderRemote)
          AgoraVideoView(
            controller: VideoViewController.remote(
              rtcEngine: _engine!,
              canvas: VideoCanvas(
                uid: _remoteUid,
                renderMode: RenderModeType.renderModeHidden,
              ),
              // Use Agora's exact connection from onUserJoined. In particular,
              // localUid must match the UID used to join this channel or the
              // native remote renderer can remain black.
              connection: _remoteConnection!,
            ),
          ),
        if (!canRenderRemote || !_remoteVideoReady || _remoteVideoMuted)
          _PeerPlaceholder(
            name: widget.peerName,
            avatarUrl: widget.peerAvatarUrl,
            status: _placeholderStatus,
            showProgress: !_remoteVideoMuted,
          ),
        if (canRenderRemote && _remoteVideoReady)
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.center,
                colors: [Color(0x80000000), Color(0x00000000)],
              ),
            ),
          ),
      ],
    );
  }

  String get _placeholderStatus {
    if (_remoteVideoMuted) return 'Camera is off';
    if (_isReconnecting) return 'Reconnecting…';
    if (_remoteUid != null) return _status;
    if (_joinedChannel) return 'Waiting for ${widget.peerName}…';
    return _status;
  }

  Widget _topBar() {
    return Positioned(
      top: 8,
      left: 8,
      right: 8,
      child: Row(
        children: [
          _TopButton(
            tooltip: 'Return to chat',
            icon: Icons.keyboard_arrow_down_rounded,
            onTap: _openChatDuringCall,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        widget.peerName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                    if (widget.peerVerified) ...[
                      const SizedBox(width: 5),
                      const AppIcon(
                        Icons.verified_rounded,
                        size: 16,
                        color: Color(0xFF64B5F6),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 2),
                Row(
                  children: [
                    if (_remoteAudioMuted) ...[
                      const AppIcon(
                        Icons.mic_off_rounded,
                        size: 13,
                        color: Colors.white70,
                      ),
                      const SizedBox(width: 4),
                    ],
                    Flexible(
                      child: Text(
                        _remoteAudioMuted
                            ? '${widget.peerName} is muted'
                            : _statusText,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          _TopButton(
            tooltip: 'Open chat',
            icon: Icons.chat_bubble_rounded,
            onTap: _chatOpening ? null : _openChatDuringCall,
          ),
        ],
      ),
    );
  }

  Widget _bottomControls() {
    return Positioned(
      left: 12,
      right: 12,
      bottom: 14,
      child: Container(
        padding: const EdgeInsets.fromLTRB(8, 11, 8, 9),
        decoration: BoxDecoration(
          color: const Color(0xE6212A30),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
          boxShadow: const [
            BoxShadow(
              color: Color(0x55000000),
              blurRadius: 20,
              offset: Offset(0, 8),
            ),
          ],
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            _CallControl(
              icon: _muted ? Icons.mic_off_rounded : Icons.mic_rounded,
              label: _muted ? 'Unmute' : 'Mute',
              selected: _muted,
              onTap: _toggleMute,
            ),
            _CallControl(
              icon: _cameraOff
                  ? Icons.videocam_off_rounded
                  : Icons.videocam_rounded,
              label: _cameraOff ? 'Start video' : 'Video',
              selected: _cameraOff,
              onTap: _toggleCamera,
            ),
            _CallControl(
              icon: Icons.cameraswitch_rounded,
              label: 'Flip',
              disabled: _cameraOff,
              onTap: _switchCamera,
            ),
            _CallControl(
              icon: _speaker
                  ? Icons.volume_up_rounded
                  : Icons.phone_in_talk_rounded,
              label: _speaker ? 'Speaker' : 'Phone',
              selected: _speaker,
              onTap: _toggleSpeaker,
            ),
            _CallControl(
              icon: Icons.call_end_rounded,
              label: 'End',
              destructive: true,
              onTap: _hangUp,
            ),
          ],
        ),
      ),
    );
  }

  Widget _localVideo() {
    if (_cameraOff || _engine == null) {
      return Container(
        color: const Color(0xFF263139),
        alignment: Alignment.center,
        child: const AppIcon(
          Icons.videocam_off_rounded,
          color: Colors.white70,
          size: 30,
        ),
      );
    }
    return AgoraVideoView(
      controller: VideoViewController(
        rtcEngine: _engine!,
        canvas: VideoCanvas(
          uid: 0,
          renderMode: RenderModeType.renderModeHidden,
          mirrorMode: _usingFrontCamera
              ? VideoMirrorModeType.videoMirrorModeEnabled
              : VideoMirrorModeType.videoMirrorModeDisabled,
        ),
      ),
    );
  }

  Widget _localPreview(BoxConstraints constraints) {
    const width = 106.0;
    const height = 150.0;
    final fallback = Offset(constraints.maxWidth - width - 14, 74);
    final position = _previewOffset ?? fallback;
    final left = position.dx
        .clamp(8.0, math.max(8.0, constraints.maxWidth - width - 8))
        .toDouble();
    final top = position.dy
        .clamp(68.0, math.max(68.0, constraints.maxHeight - height - 116))
        .toDouble();

    return Positioned(
      left: left,
      top: top,
      width: width,
      height: height,
      child: GestureDetector(
        onPanUpdate: (details) {
          setState(() => _previewOffset = Offset(left, top) + details.delta);
        },
        child: Container(
          decoration: BoxDecoration(
            color: const Color(0xFF263139),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.5),
              width: 1.2,
            ),
            boxShadow: const [
              BoxShadow(color: Colors.black54, blurRadius: 14),
            ],
          ),
          clipBehavior: Clip.antiAlias,
          child: Stack(
            fit: StackFit.expand,
            children: [
              _localVideo(),
              if (!_cameraOff && !_localVideoReady)
                const ColoredBox(
                  color: Color(0x33000000),
                  child: Center(
                    child: SizedBox.square(
                      dimension: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
              Positioned(
                left: 7,
                bottom: 6,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 7,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.black54,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    _muted ? 'You · muted' : 'You',
                    style: const TextStyle(color: Colors.white, fontSize: 10),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PeerPlaceholder extends StatelessWidget {
  const _PeerPlaceholder({
    required this.name,
    required this.avatarUrl,
    required this.status,
    required this.showProgress,
  });

  final String name;
  final String? avatarUrl;
  final String status;
  final bool showProgress;

  @override
  Widget build(BuildContext context) {
    final hasAvatar = avatarUrl?.trim().isNotEmpty == true;
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF20333D), Color(0xFF0D171D)],
        ),
      ),
      child: Center(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 90, 24, 150),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white24, width: 2),
                ),
                child: CircleAvatar(
                  radius: 58,
                  backgroundColor: const Color(0xFF33464F),
                  backgroundImage: hasAvatar
                      ? CachedNetworkImageProvider(avatarUrl!)
                      : null,
                  child: hasAvatar
                      ? null
                      : Text(
                          name.trim().isEmpty
                              ? '?'
                              : name.trim()[0].toUpperCase(),
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 42,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                ),
              ),
              const SizedBox(height: 22),
              Text(
                name,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 24,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 10),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (showProgress) ...[
                    const SizedBox(
                      width: 15,
                      height: 15,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Color(0xFF35C98B),
                      ),
                    ),
                    const SizedBox(width: 9),
                  ] else ...[
                    const AppIcon(
                      Icons.videocam_off_rounded,
                      color: Colors.white60,
                      size: 18,
                    ),
                    const SizedBox(width: 7),
                  ],
                  Flexible(
                    child: Text(
                      status,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 14,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ConnectionPill extends StatelessWidget {
  const _ConnectionPill({required this.reconnecting});

  final bool reconnecting;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: reconnecting
            ? const Color(0xE6B46B12)
            : const Color(0xE63A4650),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (reconnecting)
            const SizedBox(
              width: 13,
              height: 13,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Colors.white,
              ),
            )
          else
            const AppIcon(
              Icons.signal_wifi_statusbar_connected_no_internet_4_rounded,
              size: 16,
              color: Colors.white,
            ),
          const SizedBox(width: 7),
          Text(
            reconnecting ? 'Reconnecting…' : 'Poor connection',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 12,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}

class _TopButton extends StatelessWidget {
  const _TopButton({
    required this.tooltip,
    required this.icon,
    required this.onTap,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.black.withValues(alpha: 0.38),
      shape: const CircleBorder(),
      child: IconButton(
        tooltip: tooltip,
        onPressed: onTap,
        icon: AppIcon(icon, color: Colors.white, size: 22),
      ),
    );
  }
}

class _CallControl extends StatelessWidget {
  const _CallControl({
    required this.icon,
    required this.label,
    required this.onTap,
    this.selected = false,
    this.destructive = false,
    this.disabled = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool selected;
  final bool destructive;
  final bool disabled;

  @override
  Widget build(BuildContext context) {
    final background = destructive
        ? const Color(0xFFE53935)
        : selected
        ? Colors.white
        : Colors.white.withValues(alpha: 0.12);
    final foreground = selected && !destructive
        ? const Color(0xFF172027)
        : Colors.white;

    return Expanded(
      child: Opacity(
        opacity: disabled ? 0.38 : 1,
        child: InkWell(
          onTap: disabled ? null : onTap,
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 2),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: background,
                    shape: BoxShape.circle,
                  ),
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 160),
                    child: AppIcon(
                      icon,
                      key: ValueKey(icon),
                      color: foreground,
                      size: 23,
                    ),
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.82),
                    fontSize: 9.5,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _CallErrorState extends StatelessWidget {
  const _CallErrorState({
    required this.peerName,
    required this.avatarUrl,
    required this.message,
    required this.permissionDenied,
    required this.retry,
    required this.endCall,
  });

  final String peerName;
  final String? avatarUrl;
  final String message;
  final bool permissionDenied;
  final VoidCallback retry;
  final VoidCallback endCall;

  @override
  Widget build(BuildContext context) {
    final hasAvatar = avatarUrl?.trim().isNotEmpty == true;
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircleAvatar(
              radius: 48,
              backgroundColor: const Color(0xFF33464F),
              backgroundImage: hasAvatar
                  ? CachedNetworkImageProvider(avatarUrl!)
                  : null,
              child: hasAvatar
                  ? null
                  : Text(
                      peerName.trim().isEmpty
                          ? '?'
                          : peerName.trim()[0].toUpperCase(),
                      style: const TextStyle(color: Colors.white, fontSize: 32),
                    ),
            ),
            const SizedBox(height: 24),
            const Text(
              'Call interrupted',
              style: TextStyle(
                color: Colors.white,
                fontSize: 23,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 9),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.white70,
                fontSize: 14,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 26),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: retry,
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF21C978),
                  foregroundColor: const Color(0xFF071C13),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                icon: AppIcon(
                  permissionDenied
                      ? Icons.settings_rounded
                      : Icons.refresh_rounded,
                ),
                label: Text(
                  permissionDenied ? 'Open settings' : 'Reconnect',
                ),
              ),
            ),
            const SizedBox(height: 10),
            TextButton(
              onPressed: endCall,
              child: const Text(
                'End call',
                style: TextStyle(color: Color(0xFFFF7C76)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
