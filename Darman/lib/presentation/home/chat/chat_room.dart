import 'dart:async';
import 'dart:io';

import 'package:darmaan/core/models/chat_message_model.dart';
import 'package:darmaan/core/models/chat_room_model.dart';
import 'package:darmaan/core/models/booking_model.dart' show SessionStartStatus;
import 'package:darmaan/core/models/consultation_completion_model.dart';
import 'package:darmaan/core/models/consultation_session_model.dart';
import 'package:darmaan/core/helpers/push_notification_service.dart';
import 'package:darmaan/core/services/server_clock_service.dart';
import 'package:darmaan/core/theme/app_colors.dart';
import 'package:darmaan/core/utils/app_error_message.dart';
import 'package:darmaan/core/utils/auth_navigator.dart';
import 'package:darmaan/presentation/home/chat/chat_repository.dart';
import 'package:darmaan/presentation/home/patient/repository/patient_repository.dart';
import 'package:darmaan/presentation/home/video_call/outgoing_video_call_screen.dart';
import 'package:darmaan/presentation/home/video_call/video_call_invite_repository.dart';
import 'package:darmaan/widgets/app_shimmer.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:file_picker/file_picker.dart' as fp;
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:darmaan/widgets/app_icon.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:gal/gal.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:just_audio/just_audio.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:video_player/video_player.dart';
import 'package:uuid/uuid.dart';

class ChatRoomScreen extends StatefulWidget {
  const ChatRoomScreen({
    super.key,
    required this.bookingId,
    required this.peerName,
    this.peerAvatarUrl,
    required this.peerSubtitle,
    this.peerVerified = false,
    this.onPeerTap,
    this.onReturnToCall,
    this.openFromHistory = false,
  });

  final String bookingId;
  final String peerName;
  final String? peerAvatarUrl;
  final String peerSubtitle;

  /// Pass doctor.isDoctorVerified when opening a doctor's chat.
  final bool peerVerified;
  final VoidCallback? onPeerTap;
  final VoidCallback? onReturnToCall;
  final bool openFromHistory;

  @override
  State<ChatRoomScreen> createState() => _ChatRoomScreenState();
}

class _ChatRoomScreenState extends State<ChatRoomScreen>
    with WidgetsBindingObserver {
  static const _uuid = Uuid();
  final ChatRepository _repository = ChatRepository();
  final PatientRepository _patientRepository = PatientRepository();

  final VideoCallInviteRepository _callInviteRepository =
      VideoCallInviteRepository();

  final TextEditingController _textController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final AudioRecorder _recorder = AudioRecorder();

  ChatRoomModel? _room;

  StreamSubscription<List<ChatMessageModel>>? _subscription;
  StreamSubscription<ConsultationSessionModel>? _sessionSubscription;
  Timer? _sessionRequestExpiryTimer;
  RealtimeChannel? _typingChannel;
  Timer? _typingIdleTimer;
  Timer? _typingHeartbeatTimer;
  Timer? _recordingHeartbeatTimer;
  Timer? _peerTypingExpiryTimer;
  bool _sentTyping = false;
  bool _sentRecording = false;
  bool _peerTyping = false;
  bool _peerRecording = false;
  bool _peerOnline = false;

  final List<ChatMessageModel> _messages = [];
  final Map<String, GlobalKey> _messageKeys = {};
  String? _highlightedMessageId;
  Timer? _highlightTimer;

  ChatMessageModel? _replyingTo;

  ConsultationSessionModel? _session;
  int? _preSessionMessageLimit;

  bool _loading = true;
  bool _loadingOlder = false;
  bool _hasMore = true;

  bool _sending = false;

  bool _recording = false;
  bool _recordingPaused = false;
  DateTime? _recordingStartedAt;
  Duration _recordingElapsed = Duration.zero;
  Timer? _recordingTimer;
  StreamSubscription<Amplitude>? _amplitudeSubscription;
  List<double> _recordingWaveform = List<double>.filled(36, .08);

  bool _sessionActionBusy = false;
  bool _sessionDialogVisible = false;
  bool _cancellingAppointment = false;

  bool _callStarting = false;
  bool _endingSession = false;
  bool _completionHandling = false;
  bool _leavingCompletedPatientChat = false;

  String? _error;

  // ===========================================================================
  // INIT
  // ===========================================================================

  @override
  void initState() {
    super.initState();

    PushNotificationService.instance.markChatOpen(widget.bookingId);
    WidgetsBinding.instance.addObserver(this);

    _scrollController.addListener(_onScroll);

    _initialize();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) {
      _setLocalTyping(false);
      _setLocalRecordingStatus(false);
      unawaited(_setChatPresence(false));
    }
    if (state == AppLifecycleState.resumed && _room != null) {
      unawaited(_setChatPresence(true));
      if (_recording) {
        _setLocalRecordingStatus(true);
      }
      _markSeen();
    }
  }

  // ===========================================================================
  // INITIALIZE
  // ===========================================================================

  Future<void> _initialize() async {
    try {
      final results = await Future.wait<Object>([
        _repository.getOrCreateRoom(widget.bookingId),
        _repository.getPreSessionMessageLimit(),
      ]);
      final room = results[0] as ChatRoomModel;
      final preSessionMessageLimit = results[1] as int;

      if (!mounted) return;

      setState(() {
        _room = room;
        _preSessionMessageLimit = preSessionMessageLimit;
        _loading = false;
      });
      _startTypingChannel(room);

      // -----------------------------------------------------------------------
      // WATCH MESSAGES
      // -----------------------------------------------------------------------

      _subscription = _repository
          .watchLatestMessages(room.id)
          .listen(
            (latest) {
              if (!mounted) return;

              final shouldScroll = _messages.isEmpty || _isNearBottom;

              setState(() {
                final older = _messages.where(
                  (old) => !latest.any((current) => current.id == old.id),
                );

                _messages
                  ..clear()
                  ..addAll(
                    [...older, ...latest]
                      ..sort((a, b) => a.createdAt.compareTo(b.createdAt)),
                  );
              });

              if (shouldScroll) {
                _scrollToBottom();
              }

              _markSeen();
            },
            onError: (Object error) {
              if (!mounted) return;

              setState(() {
                _error = _readableError(error);
              });
            },
          );

      // -----------------------------------------------------------------------
      // WATCH CONSULTATION SESSION
      // -----------------------------------------------------------------------

      _sessionSubscription = _repository
          .watchSession(room.bookingId)
          .listen(
            (session) {
              if (!mounted) return;

              setState(() {
                _session = session;
              });
              _scheduleSessionRequestExpiry(session);

              if (!widget.openFromHistory &&
                  _isDoctor &&
                  session.bookingStatus == 'completed' &&
                  !session.hasUnendedFollowUp) {
                _handleConsultationCompleted();
              } else if (!widget.openFromHistory &&
                  !_isDoctor &&
                  session.bookingStatus == 'completed' &&
                  !session.hasUnendedFollowUp) {
                _leaveCompletedPatientChat();
              }
            },
            onError: (Object error) {
              if (mounted) {
                _showError(error);
              }
            },
          );

      await _markSeen();
    } catch (error) {
      if (!mounted) return;

      setState(() {
        _loading = false;
        _error = _readableError(error);
      });
    }
  }

  void _startTypingChannel(ChatRoomModel room) {
    final currentUserId = _repository.currentUserId;
    final peerId = currentUserId == room.doctorId
        ? room.patientId
        : room.doctorId;
    late final RealtimeChannel channel;
    channel = Supabase.instance.client
        .channel('chat-typing:${room.id}')
        .onBroadcast(
          event: 'typing',
          callback: (payload) {
            final nestedPayload = payload['payload'];
            final data = nestedPayload is Map
                ? Map<String, dynamic>.from(nestedPayload)
                : payload;
            if (data['user_id']?.toString() != peerId) return;
            final activity = data['activity']?.toString();
            if (activity == 'recording' || data['is_recording'] == true) {
              _setPeerActivity(recording: true);
            } else if (activity == 'typing' || data['is_typing'] == true) {
              _setPeerActivity(typing: true);
            } else {
              _setPeerActivity();
            }
          },
        )
        .onPresenceSync((_) => _syncPeerPresence(channel, peerId));
    _typingChannel = channel;
    channel.subscribe((status, _) {
      if (status == RealtimeSubscribeStatus.subscribed) {
        unawaited(_setChatPresence(true));
      } else if (status == RealtimeSubscribeStatus.closed ||
          status == RealtimeSubscribeStatus.channelError ||
          status == RealtimeSubscribeStatus.timedOut) {
        _setPeerOnline(false);
      }
    });
  }

  Future<void> _setChatPresence(bool online) async {
    final channel = _typingChannel;
    if (channel == null) return;
    if (online &&
        WidgetsBinding.instance.lifecycleState != AppLifecycleState.resumed) {
      return;
    }
    try {
      if (online) {
        await channel.track({
          'user_id': _repository.currentUserId,
          'online_at': DateTime.now().toUtc().toIso8601String(),
        });
      } else {
        await channel.untrack();
      }
    } catch (_) {
      // Presence is only a UI hint; messaging remains available if it fails.
    }
  }

  void _syncPeerPresence(RealtimeChannel channel, String peerId) {
    final online = channel.presenceState().any(
      (state) =>
          state.key == peerId ||
          state.presences.any(
            (presence) => presence.payload['user_id']?.toString() == peerId,
          ),
    );
    _setPeerOnline(online);
  }

  void _setPeerOnline(bool online) {
    if (!mounted || _peerOnline == online) return;
    setState(() => _peerOnline = online);
  }

  void _onComposerChanged(String value) {
    _typingIdleTimer?.cancel();
    if (value.trim().isEmpty) {
      _setLocalTyping(false);
      return;
    }

    _setLocalTyping(true);
    _typingIdleTimer = Timer(
      const Duration(seconds: 2),
      () => _setLocalTyping(false),
    );
  }

  void _setLocalTyping(bool typing) {
    _typingIdleTimer?.cancel();
    if (typing) {
      if (!_sentTyping) {
        _sentTyping = true;
        unawaited(_sendTypingEvent(true));
      }
      _typingHeartbeatTimer ??= Timer.periodic(
        const Duration(milliseconds: 1500),
        (_) => unawaited(_sendTypingEvent(true)),
      );
      return;
    }

    _typingHeartbeatTimer?.cancel();
    _typingHeartbeatTimer = null;
    if (_sentTyping) {
      _sentTyping = false;
      unawaited(_sendTypingEvent(false));
    }
  }

  Future<void> _sendTypingEvent(bool typing) async {
    await _sendChatActivity(typing ? 'typing' : 'idle');
  }

  void _setLocalRecordingStatus(bool recording) {
    if (recording) {
      if (!_sentRecording) {
        _sentRecording = true;
        unawaited(_sendChatActivity('recording'));
      }
      _recordingHeartbeatTimer ??= Timer.periodic(
        const Duration(milliseconds: 1500),
        (_) => unawaited(_sendChatActivity('recording')),
      );
      return;
    }

    _recordingHeartbeatTimer?.cancel();
    _recordingHeartbeatTimer = null;
    if (_sentRecording) {
      _sentRecording = false;
      unawaited(_sendChatActivity('idle'));
    }
  }

  Future<void> _sendChatActivity(String activity) async {
    final channel = _typingChannel;
    if (channel == null) return;
    try {
      await channel.sendBroadcastMessage(
        event: 'typing',
        payload: {
          'user_id': _repository.currentUserId,
          'activity': activity,
          'is_typing': activity == 'typing',
          'is_recording': activity == 'recording',
        },
      );
    } catch (_) {
      // Typing state is ephemeral; chat messages remain authoritative.
    }
  }

  void _setPeerActivity({bool typing = false, bool recording = false}) {
    _peerTypingExpiryTimer?.cancel();
    if (!mounted) return;
    if (_peerTyping != typing || _peerRecording != recording) {
      setState(() {
        _peerTyping = typing;
        _peerRecording = recording;
      });
    }
    if (typing || recording) {
      _peerTypingExpiryTimer = Timer(const Duration(milliseconds: 3500), () {
        if (mounted && (_peerTyping || _peerRecording)) {
          setState(() {
            _peerTyping = false;
            _peerRecording = false;
          });
        }
      });
    }
  }

  Future<void> _closeTypingChannel() async {
    final channel = _typingChannel;
    _typingChannel = null;
    if (channel == null) return;
    try {
      if (_sentTyping || _sentRecording) {
        await channel.sendBroadcastMessage(
          event: 'typing',
          payload: {
            'user_id': _repository.currentUserId,
            'activity': 'idle',
            'is_typing': false,
            'is_recording': false,
          },
        );
      }
      await channel.untrack();
      await Supabase.instance.client.removeChannel(channel);
    } catch (_) {}
  }

  void _scheduleSessionRequestExpiry(ConsultationSessionModel session) {
    _sessionRequestExpiryTimer?.cancel();
    final requestedAt = session.sessionStartRequestedAt;
    if (session.bookingStatus != 'accepted' ||
        session.sessionStartStatus != SessionStartStatus.pending ||
        requestedAt == null) {
      return;
    }

    final remaining = requestedAt
        .add(ConsultationSessionModel.sessionStartRequestLifetime)
        .difference(DateTime.now().toUtc());
    _sessionRequestExpiryTimer = Timer(
      remaining.isNegative ? Duration.zero : remaining,
      () {
        if (mounted) setState(() {});
      },
    );
  }

  // ===========================================================================
  // READ STATE
  // ===========================================================================

  Future<void> _markSeen() async {
    final room = _room;

    if (room == null) return;

    try {
      await _repository.markRoomDelivered(room.id);

      await _repository.markRoomRead(room.id);
    } catch (_) {}
  }

  // ===========================================================================
  // SCROLL
  // ===========================================================================

  bool get _isNearBottom {
    if (!_scrollController.hasClients) {
      return true;
    }

    final position = _scrollController.position;

    return position.maxScrollExtent - position.pixels < 180;
  }

  void _onScroll() {
    if (!_scrollController.hasClients) {
      return;
    }

    if (_scrollController.position.pixels <= 120 &&
        !_loadingOlder &&
        _hasMore) {
      _loadOlder();
    }
  }

  Future<void> _loadOlder() async {
    final room = _room;

    if (room == null || _messages.isEmpty || _loadingOlder) {
      return;
    }

    setState(() {
      _loadingOlder = true;
    });

    try {
      final older = await _repository.loadOlderMessages(
        roomId: room.id,
        before: _messages.first.createdAt,
      );

      if (!mounted) return;

      setState(() {
        _hasMore = older.length == ChatRepository.pageSize;

        _messages.insertAll(
          0,
          older.where(
            (item) => !_messages.any((current) => current.id == item.id),
          ),
        );
      });
    } finally {
      if (mounted) {
        setState(() {
          _loadingOlder = false;
        });
      }
    }
  }

  Future<void> _goToRepliedMessage(String messageId) async {
    var index = _messages.indexWhere((message) => message.id == messageId);
    while (index < 0 && _hasMore && !_loadingOlder) {
      final previousCount = _messages.length;
      await _loadOlder();
      if (!mounted || _messages.length == previousCount) break;
      index = _messages.indexWhere((message) => message.id == messageId);
    }

    if (!mounted) return;
    if (index < 0) {
      _showSnack('The original message is no longer available.');
      return;
    }

    final key = _messageKeys.putIfAbsent(messageId, () => GlobalKey());
    if (_scrollController.hasClients && _messages.length > 1) {
      final estimatedOffset =
          _scrollController.position.maxScrollExtent *
          (index / (_messages.length - 1));
      await _scrollController.animateTo(
        estimatedOffset
            .clamp(
              _scrollController.position.minScrollExtent,
              _scrollController.position.maxScrollExtent,
            )
            .toDouble(),
        duration: const Duration(milliseconds: 280),
        curve: Curves.easeOutCubic,
      );
    }

    if (!mounted) return;
    await WidgetsBinding.instance.endOfFrame;
    final targetContext = key.currentContext;
    if (targetContext != null) {
      await Scrollable.ensureVisible(
        targetContext,
        alignment: .35,
        duration: const Duration(milliseconds: 260),
        curve: Curves.easeOutCubic,
      );
    }

    _highlightTimer?.cancel();
    setState(() => _highlightedMessageId = messageId);
    _highlightTimer = Timer(const Duration(milliseconds: 1400), () {
      if (mounted && _highlightedMessageId == messageId) {
        setState(() => _highlightedMessageId = null);
      }
    });
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) {
        return;
      }

      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
      );
    });
  }

  // ===========================================================================
  // SEND TEXT
  // ===========================================================================

  Future<bool> _prepareMessageSend() async {
    final currentSession = _session;
    if (currentSession != null &&
        currentSession.bookingStatus != 'completed' &&
        !currentSession.hasUnendedFollowUp) {
      return false;
    }

    await ServerClockService.instance.synchronize(force: true);
    final freshSession = await _repository.getSession(widget.bookingId);
    final isLimitedCompletedChat =
        freshSession.bookingStatus == 'completed' &&
        (freshSession.hasUnendedFollowUp || freshSession.followUpDate == null);
    final freshRoom = isLimitedCompletedChat
        ? await _repository.getOrCreateRoom(widget.bookingId)
        : _room;

    if (mounted) {
      setState(() {
        if (freshRoom != null) _room = freshRoom;
        _session = freshSession;
      });
    }

    if (!isLimitedCompletedChat && freshSession.bookingStatus == 'completed') {
      throw const ChatException(
        'The follow-up chat is not available for this booking.',
      );
    }
    if (!isLimitedCompletedChat) {
      return false;
    }
    if (freshSession.followUpDate != null &&
        !freshSession.isFollowUpOpen &&
        !freshSession.isFollowUpUpcoming) {
      throw const ChatException('The follow-up chat is not open yet.');
    }
    return true;
  }

  Future<void> _sendText() async {
    var room = _room;
    final text = _textController.text.trim();

    if (room == null || text.isEmpty) {
      return;
    }

    late final bool isFollowUp;
    try {
      isFollowUp = await _prepareMessageSend();
      room = _room;
      if (room == null) return;
    } catch (error) {
      _showError(error);
      return;
    }

    final reply = _replyingTo;
    final messageId = _uuid.v4();
    final now = DateTime.now().toUtc();
    final optimisticMessage = ChatMessageModel(
      id: messageId,
      chatRoomId: room.id,
      bookingId: room.bookingId,
      senderId: _repository.currentUserId,
      type: MessageType.text,
      status: MessageStatus.sending,
      text: text,
      replyToMessageId: reply?.id,
      replyTo: reply,
      createdAt: now,
      updatedAt: now,
    );

    _setLocalTyping(false);
    _textController.clear();
    setState(() {
      _replyingTo = null;
      _messages.add(optimisticMessage);
      _messages.sort((a, b) => a.createdAt.compareTo(b.createdAt));
    });
    _scrollToBottom();

    try {
      final sent = await _repository.sendText(
        room: room,
        text: text,
        isFollowUp: isFollowUp,
        id: messageId,
        replyToMessageId: reply?.id,
      );
      if (!mounted) return;
      _replaceLocalMessage(messageId, sent);
    } catch (error) {
      if (!mounted) return;
      final currentIndex = _messages.indexWhere(
        (message) => message.id == messageId,
      );
      if (currentIndex < 0 ||
          _messages[currentIndex].status != MessageStatus.sending) {
        return;
      }
      final failed = optimisticMessage.copyWith(status: MessageStatus.failed);
      _replaceLocalMessage(messageId, failed);
      _showError(error);
    }
  }

  void _replaceLocalMessage(String id, ChatMessageModel replacement) {
    if (!mounted) return;
    setState(() {
      final index = _messages.indexWhere((message) => message.id == id);
      if (index >= 0) _messages[index] = replacement;
    });
  }

  Future<void> _retryTextMessage(ChatMessageModel failedMessage) async {
    if (failedMessage.status != MessageStatus.failed ||
        failedMessage.text?.trim().isEmpty != false) {
      return;
    }
    setState(
      () => _messages.removeWhere((item) => item.id == failedMessage.id),
    );
    _textController.text = failedMessage.text!;
    _textController.selection = TextSelection.collapsed(
      offset: _textController.text.length,
    );
    _replyingTo = failedMessage.replyTo;
    await _sendText();
  }

  Future<void> _retryMessage(ChatMessageModel failedMessage) async {
    if (failedMessage.status != MessageStatus.failed) return;
    if (failedMessage.type == MessageType.text) {
      await _retryTextMessage(failedMessage);
      return;
    }
    if (failedMessage.type != MessageType.image &&
        failedMessage.type != MessageType.voice) {
      return;
    }

    final path = failedMessage.mediaUrl;
    if (path == null || !await File(path).exists()) {
      _showError(
        const ChatException('This attachment is no longer available.'),
      );
      return;
    }

    setState(() {
      _messages.removeWhere((item) => item.id == failedMessage.id);
      _replyingTo = failedMessage.replyTo;
    });
    await _sendFile(
      File(path),
      failedMessage.type,
      failedMessage.fileName ??
          (failedMessage.type == MessageType.voice ? 'voice.m4a' : 'image.jpg'),
      failedMessage.mimeType ??
          (failedMessage.type == MessageType.voice
              ? 'audio/mp4'
              : 'image/jpeg'),
      duration: failedMessage.voiceDurationSeconds,
    );
  }

  // ===========================================================================
  // IMAGE
  // ===========================================================================

  Future<void> _pickImage(ImageSource source) async {
    Navigator.pop(context);

    final picked = await ImagePicker().pickImage(
      source: source,
      imageQuality: 88,
      maxWidth: 2400,
    );

    if (picked == null) return;

    await _sendFile(
      File(picked.path),
      MessageType.image,
      picked.name,
      picked.mimeType ?? 'image/jpeg',
    );
  }

  // ===========================================================================
  // DOCUMENT
  // ===========================================================================

  Future<void> _pickDocument() async {
    Navigator.pop(context);

    final fp.PlatformFile? item = await fp.FilePicker.pickFile(
      type: fp.FileType.custom,
      allowedExtensions: [
        'pdf',
        'doc',
        'docx',
        'jpg',
        'jpeg',
        'png',
        'mp4',
        'mov',
        'm4v',
      ],
    );

    if (item?.path == null) return;

    await _sendFile(
      File(item!.path!),
      MessageType.file,
      item.name,
      _mimeForFileName(item.name),
    );
  }

  // ===========================================================================
  // SEND ATTACHMENT
  // ===========================================================================

  Future<void> _sendFile(
    File file,
    MessageType type,
    String name,
    String mime, {
    int? duration,
  }) async {
    var room = _room;

    if (room == null || _sending) {
      return;
    }

    late final bool isFollowUp;
    try {
      isFollowUp = await _prepareMessageSend();
      room = _room;
      if (room == null) return;
    } catch (error) {
      _showError(error);
      return;
    }

    final reply = _replyingTo;
    final showOptimistically =
        type == MessageType.image || type == MessageType.voice;
    final messageId = showOptimistically ? _uuid.v4() : null;
    final now = DateTime.now().toUtc();
    final optimisticMessage = showOptimistically
        ? ChatMessageModel(
            id: messageId!,
            chatRoomId: room.id,
            bookingId: room.bookingId,
            senderId: _repository.currentUserId,
            type: type,
            status: MessageStatus.sending,
            mediaUrl: file.path,
            fileName: name,
            mimeType: mime,
            voiceDurationSeconds: duration,
            replyToMessageId: reply?.id,
            replyTo: reply,
            createdAt: now,
            updatedAt: now,
          )
        : null;

    setState(() {
      _sending = true;
      if (optimisticMessage != null) {
        _replyingTo = null;
        _messages.add(optimisticMessage);
        _messages.sort((a, b) => a.createdAt.compareTo(b.createdAt));
      }
    });
    if (optimisticMessage != null) _scrollToBottom();

    try {
      final sent = await _repository.sendAttachment(
        room: room,
        file: file,
        type: type,
        fileName: name,
        mimeType: mime,
        isFollowUp: isFollowUp,
        id: messageId,
        voiceDurationSeconds: duration,
        replyToMessageId: reply?.id,
      );

      if (messageId != null) {
        _replaceLocalMessage(messageId, sent);
      } else if (mounted) {
        setState(() {
          _replyingTo = null;
        });
      }

      _scrollToBottom();
    } catch (error) {
      if (optimisticMessage != null && mounted) {
        final currentIndex = _messages.indexWhere(
          (message) => message.id == optimisticMessage.id,
        );
        if (currentIndex >= 0 &&
            _messages[currentIndex].status == MessageStatus.sending) {
          _replaceLocalMessage(
            optimisticMessage.id,
            optimisticMessage.copyWith(status: MessageStatus.failed),
          );
        }
      }
      _showError(error);
    } finally {
      if (mounted) {
        setState(() {
          _sending = false;
        });
      }
    }
  }

  // ===========================================================================
  // VOICE NOTE
  // ===========================================================================

  Future<void> _startRecording() async {
    if (_recording || _sending) return;
    _setLocalTyping(false);
    if (!await _recorder.hasPermission()) {
      _showError(
        const ChatException(
          'Microphone access is required to record a voice message.',
        ),
      );

      return;
    }

    final directory = await getTemporaryDirectory();

    final path =
        '${directory.path}/voice-${DateTime.now().millisecondsSinceEpoch}.m4a';

    await _recorder.start(
      const RecordConfig(encoder: AudioEncoder.aacLc),
      path: path,
    );

    if (!mounted) return;

    HapticFeedback.mediumImpact();

    setState(() {
      _recording = true;
      _recordingPaused = false;
      _recordingStartedAt = DateTime.now();
      _recordingElapsed = Duration.zero;
      _recordingWaveform = List<double>.filled(36, .08);
    });
    _setLocalRecordingStatus(true);

    _amplitudeSubscription?.cancel();
    _amplitudeSubscription = _recorder
        .onAmplitudeChanged(const Duration(milliseconds: 140))
        .listen((amplitude) {
          if (!mounted || !_recording || _recordingPaused) return;
          final raw = ((amplitude.current + 55) / 55).clamp(0.0, 1.0);
          final previous = _recordingWaveform.last;
          final smoothed = (previous * .62 + raw * .38).clamp(.06, 1.0);
          setState(() {
            _recordingWaveform = [..._recordingWaveform.skip(1), smoothed];
          });
        });

    _startRecordingTimer();
  }

  void _startRecordingTimer() async {
    _recordingTimer?.cancel();
    await _amplitudeSubscription?.cancel();
    _amplitudeSubscription = null;
    _recordingTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      final started = _recordingStartedAt;
      if (!mounted || started == null) return;
      setState(() {
        _recordingElapsed = DateTime.now().difference(started);
      });
    });
  }

  Future<void> _togglePauseRecording() async {
    if (!_recording) return;

    try {
      if (_recordingPaused) {
        // Resume: rebase the "started at" so elapsed keeps counting correctly.
        await _recorder.resume();
        _recordingStartedAt = DateTime.now().subtract(_recordingElapsed);
        _startRecordingTimer();
      } else {
        await _recorder.pause();
        _recordingTimer?.cancel();
      }

      HapticFeedback.selectionClick();

      if (mounted) {
        setState(() {
          _recordingPaused = !_recordingPaused;
        });
      }
    } catch (error) {
      _showError(error);
    }
  }

  Future<void> _finishRecording({required bool send}) async {
    if (!_recording) return;

    _recordingTimer?.cancel();
    _setLocalRecordingStatus(false);

    final elapsedSeconds = _recordingElapsed.inSeconds.clamp(1, 3600).toInt();

    final path = await _recorder.stop();

    if (mounted) {
      setState(() {
        _recording = false;
        _recordingPaused = false;
        _recordingStartedAt = null;
        _recordingElapsed = Duration.zero;
      });
    }

    if (path == null) return;

    if (!send) {
      final file = File(path);
      if (await file.exists()) await file.delete();
      HapticFeedback.lightImpact();
      return;
    }

    await _sendFile(
      File(path),
      MessageType.voice,
      'voice.m4a',
      'audio/mp4',
      duration: elapsedSeconds,
    );
  }

  // ===========================================================================
  // ATTACHMENTS
  // ===========================================================================

  void _showAttachments() {
    if (!_canComposeMessages ||
        _preSessionLimitReached ||
        _upcomingFollowUpLimitReached ||
        _postConsultationLimitReached) {
      return;
    }

    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      useSafeArea: true,
      builder: (_) {
        return _AttachmentSheet(
          onCamera: () {
            _pickImage(ImageSource.camera);
          },
          onGallery: () {
            _pickImage(ImageSource.gallery);
          },
          onDocument: _pickDocument,
        );
      },
    );
  }

  // ===========================================================================
  // DELETE MESSAGE
  // ===========================================================================

  Future<void> _delete(ChatMessageModel message) async {
    try {
      await _repository.deleteForEveryone(message);
    } catch (error) {
      _showError(error);
    }
  }

  // ===========================================================================
  // SESSION
  // ===========================================================================

  bool get _isDoctor => _room?.doctorId == _repository.currentUserId;

  bool get _canComposeMessages {
    if (_session?.isRefunded == true) return false;
    return (_room?.isActive == true && _session?.isEnded != true) ||
        _session?.hasUnendedFollowUp == true ||
        _isPostConsultationChat;
  }

  int get _myPreSessionMessageCount {
    return _messages
        .where(
          (message) =>
              message.senderId == _repository.currentUserId &&
              message.type != MessageType.system &&
              message.status != MessageStatus.failed,
        )
        .length;
  }

  bool get _preSessionLimitReached {
    final limit = _preSessionMessageLimit;
    return _isPreConsultationChat &&
        (limit == null || _myPreSessionMessageCount >= limit);
  }

  bool get _isPreConsultationChat {
    final status = _session?.bookingStatus;
    return (status == 'pending' || status == 'accepted') &&
        _session?.startedAt == null;
  }

  int get _myUpcomingFollowUpMessageCount {
    final scheduledAt = _session?.followUpScheduledAt;
    return _messages
        .where(
          (message) =>
              message.senderId == _repository.currentUserId &&
              message.type != MessageType.system &&
              message.status != MessageStatus.failed &&
              (scheduledAt == null || !message.createdAt.isBefore(scheduledAt)),
        )
        .length;
  }

  bool get _upcomingFollowUpLimitReached {
    return _session?.isFollowUpUpcoming == true &&
        _myUpcomingFollowUpMessageCount >=
            ChatRepository.upcomingFollowUpMessageLimit;
  }

  bool get _isPostConsultationChat {
    return _session?.bookingStatus == 'completed' &&
        _session?.followUpDate == null;
  }

  int get _myPostConsultationMessageCount {
    final completedAt = _session?.completedAt;
    return _messages
        .where(
          (message) =>
              message.senderId == _repository.currentUserId &&
              message.type != MessageType.system &&
              message.status != MessageStatus.failed &&
              (completedAt == null || !message.createdAt.isBefore(completedAt)),
        )
        .length;
  }

  bool get _postConsultationLimitReached {
    return _isPostConsultationChat &&
        _myPostConsultationMessageCount >=
            ChatRepository.upcomingFollowUpMessageLimit;
  }

  int? get _messageCounterUsed {
    if (_session?.isRefunded == true) return null;
    if (_isPreConsultationChat) {
      return _myPreSessionMessageCount;
    }
    if (_session?.isFollowUpUpcoming == true) {
      return _myUpcomingFollowUpMessageCount;
    }
    if (_isPostConsultationChat) {
      return _myPostConsultationMessageCount;
    }
    return null;
  }

  int? get _messageCounterTotal {
    if (_session?.isRefunded == true) return null;
    if (_isPreConsultationChat) {
      return _preSessionMessageLimit;
    }
    if (_session?.isFollowUpUpcoming == true || _isPostConsultationChat) {
      return ChatRepository.upcomingFollowUpMessageLimit;
    }
    return null;
  }

  // ===========================================================================
  // REQUEST CONSULTATION START
  // ===========================================================================

  Future<void> _requestSessionStart() async {
    if (_sessionActionBusy) return;

    setState(() {
      _sessionActionBusy = true;
    });

    try {
      await _repository.requestSessionStart(widget.bookingId);
    } catch (error) {
      _showError(error);
    } finally {
      if (mounted) {
        setState(() {
          _sessionActionBusy = false;
        });
      }
    }
  }

  Future<void> _cancelAcceptedAppointment() async {
    if (_isDoctor ||
        _session?.bookingStatus != 'accepted' ||
        _cancellingAppointment) {
      return;
    }

    final confirmed = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: 0.42),
      builder: (sheetContext) => Container(
        padding: const EdgeInsets.fromLTRB(20, 10, 20, 20),
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 42,
              height: 4,
              decoration: BoxDecoration(
                color: const Color(0xFFD9DDE3),
                borderRadius: BorderRadius.circular(20),
              ),
            ),
            const SizedBox(height: 22),
            Container(
              width: 54,
              height: 54,
              decoration: const BoxDecoration(
                color: Color(0xFFF2F4F6),
                shape: BoxShape.circle,
              ),
              child: const AppIcon(
                Icons.event_busy_outlined,
                color: Color(0xFF475467),
                size: 25,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Cancel appointment?',
              textAlign: TextAlign.center,
              style: GoogleFonts.outfit(
                fontSize: 19,
                fontWeight: FontWeight.w500,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Your appointment with ${widget.peerName} will be cancelled. The reserved consultation fee will return to your wallet.',
              textAlign: TextAlign.center,
              style: GoogleFonts.outfit(
                fontSize: 13,
                height: 1.5,
                color: AppColors.textSecondary,
              ),
            ),
            const SizedBox(height: 24),
            Row(
              children: [
                Expanded(
                  child: SizedBox(
                    height: 48,
                    child: FilledButton(
                      onPressed: () => Navigator.pop(sheetContext, true),
                      style: FilledButton.styleFrom(
                        elevation: 0,
                        backgroundColor: const Color(0xFFF2F4F6),
                        foregroundColor: AppColors.textPrimary,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(13),
                        ),
                      ),
                      child: Text(
                        'Cancel',
                        maxLines: 1,
                        style: GoogleFonts.outfit(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: SizedBox(
                    height: 48,
                    child: FilledButton(
                      onPressed: () => Navigator.pop(sheetContext, false),
                      style: FilledButton.styleFrom(
                        elevation: 0,
                        backgroundColor: AppColors.brand,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(13),
                        ),
                      ),
                      child: Text(
                        'Keep',
                        maxLines: 1,
                        style: GoogleFonts.outfit(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );

    if (confirmed != true || !mounted) return;
    setState(() => _cancellingAppointment = true);
    try {
      await _patientRepository.cancelPendingBooking(widget.bookingId);
      if (mounted) _showSnack('Appointment cancelled successfully.');
    } catch (error) {
      _showError(error);
    } finally {
      if (mounted) setState(() => _cancellingAppointment = false);
    }
  }

  // ===========================================================================
  // PATIENT START DIALOG
  // ===========================================================================

  Future<void> _showPatientSessionDialog() async {
    if (_sessionDialogVisible || !mounted) {
      return;
    }

    _sessionDialogVisible = true;

    final accepted = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.black.withValues(alpha: 0.50),
      builder: (dialogContext) {
        return Dialog(
          elevation: 0,
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.symmetric(horizontal: 24),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(24, 28, 24, 20),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(24),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _DialogIcon(
                  icon: Icons.medical_services_outlined,
                  backgroundColor: AppColors.brand.withValues(alpha: 0.08),
                  iconColor: AppColors.brand,
                ),

                const SizedBox(height: 20),

                Text(
                  'Start consultation?',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.outfit(
                    fontSize: 20,
                    fontWeight: FontWeight.w500,
                    letterSpacing: -0.35,
                    color: AppColors.textPrimary,
                  ),
                ),

                const SizedBox(height: 9),

                Text(
                  '${widget.peerName} is ready to begin your consultation.',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.outfit(
                    fontSize: 13,
                    height: 1.5,
                    color: AppColors.textSecondary,
                  ),
                ),

                const SizedBox(height: 7),

                Text(
                  'Once you start, the consultation becomes active and this appointment can no longer be cancelled.',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.outfit(
                    fontSize: 11.5,
                    height: 1.5,
                    color: AppColors.textSecondary,
                  ),
                ),

                const SizedBox(height: 25),

                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: FilledButton(
                    onPressed: () {
                      Navigator.pop(dialogContext, true);
                    },
                    style: FilledButton.styleFrom(
                      elevation: 0,
                      backgroundColor: AppColors.brand,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(13),
                      ),
                    ),
                    child: Text(
                      'Start consultation',
                      style: GoogleFonts.outfit(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ),

                const SizedBox(height: 3),

                SizedBox(
                  width: double.infinity,
                  height: 42,
                  child: TextButton(
                    onPressed: () {
                      Navigator.pop(dialogContext, false);
                    },
                    child: Text(
                      'Not now',
                      style: GoogleFonts.outfit(
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );

    _sessionDialogVisible = false;

    if (accepted == null || !mounted) {
      return;
    }

    try {
      await _repository.respondToSessionStart(
        bookingId: widget.bookingId,
        accept: accepted,
      );
    } catch (error) {
      _showError(error);
    }
  }

  // ===========================================================================
  // VIDEO
  // ===========================================================================

  Future<void> _startVideoCall() async {
    if ((_session?.isInProgress != true && _session?.isFollowUpOpen != true) ||
        _callStarting) {
      return;
    }

    setState(() {
      _callStarting = true;
    });

    try {
      final invite = await _callInviteRepository.startCall(widget.bookingId);

      if (!mounted) return;

      final outcome = await Navigator.push<String>(
        context,
        MaterialPageRoute(
          fullscreenDialog: true,
          builder: (_) {
            return OutgoingVideoCallScreen(
              invite: invite,
              isDoctor: _isDoctor,
              peerDisplayName: widget.peerName,
              peerAvatarUrl: widget.peerAvatarUrl,
              peerSubtitle: widget.peerSubtitle,
              peerVerified: widget.peerVerified,
            );
          },
        ),
      );

      if (!mounted || outcome == null || outcome.trim().isEmpty) {
        return;
      }

      _showSnack(outcome);
    } catch (error) {
      _showError(error);
    } finally {
      if (mounted) {
        setState(() {
          _callStarting = false;
        });
      }
    }
  }

  // ===========================================================================
  // END CONSULTATION
  // ===========================================================================
  Future<void> _endSession() async {
    if (!_isDoctor || _session?.isInProgress != true || _endingSession) {
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.black.withValues(alpha: 0.50),
      builder: (dialogContext) {
        return Dialog(
          elevation: 0,
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.symmetric(horizontal: 24),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(24, 28, 24, 20),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(24),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const _DialogIcon(
                  icon: Icons.stop_circle_outlined,
                  backgroundColor: Color(0xFFFDF1F1),
                  iconColor: Color(0xFFB42318),
                ),

                const SizedBox(height: 20),

                Text(
                  'End consultation?',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.outfit(
                    fontSize: 20,
                    fontWeight: FontWeight.w500,
                    letterSpacing: -0.35,
                    color: AppColors.textPrimary,
                  ),
                ),

                const SizedBox(height: 8),

                // Single, tighter line — combines the "when" and the
                // "what happens" messaging instead of two separate blocks.
                Text(
                  'This finalizes the appointment and settles the fee. '
                  'You can\'t undo this.',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.outfit(
                    fontSize: 13,
                    height: 1.5,
                    color: AppColors.textSecondary,
                  ),
                ),

                const SizedBox(height: 24),

                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: FilledButton(
                    onPressed: () => Navigator.pop(dialogContext, true),
                    style: FilledButton.styleFrom(
                      elevation: 0,
                      backgroundColor: const Color.fromARGB(255, 208, 54, 43),
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(13),
                      ),
                    ),
                    child: Text(
                      'End consultation',
                      style: GoogleFonts.outfit(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ),

                const SizedBox(height: 8),

                SizedBox(
                  width: double.infinity,
                  height: 42,
                  child: TextButton(
                    style: TextButton.styleFrom(
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(13),
                      ),
                    ),
                    onPressed: () => Navigator.pop(dialogContext, false),
                    child: Text(
                      'Continue consultation',
                      style: GoogleFonts.outfit(
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );

    if (confirmed != true || !mounted) {
      return;
    }

    setState(() => _endingSession = true);

    try {
      await _repository.endConsultation(widget.bookingId);
    } catch (error) {
      _showError(error);
    } finally {
      if (mounted) {
        setState(() => _endingSession = false);
      }
    }
  }

  Future<void> _endFollowUp() async {
    if (!_isDoctor || _session?.isFollowUpOpen != true || _endingSession) {
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.black.withValues(alpha: 0.50),
      builder: (dialogContext) => Dialog(
        elevation: 0,
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.symmetric(horizontal: 24),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(24, 28, 24, 20),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(24),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const _DialogIcon(
                icon: Icons.stop_circle_outlined,
                backgroundColor: Color(0xFFFDF1F1),
                iconColor: Color(0xFFB42318),
              ),
              const SizedBox(height: 20),
              Text(
                'End follow-up?',
                textAlign: TextAlign.center,
                style: GoogleFonts.outfit(
                  fontSize: 20,
                  fontWeight: FontWeight.w500,
                  letterSpacing: -0.35,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'This closes the free follow-up chat with '
                '${widget.peerName}. Both of you will be notified.',
                textAlign: TextAlign.center,
                style: GoogleFonts.outfit(
                  fontSize: 13,
                  height: 1.5,
                  color: AppColors.textSecondary,
                ),
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                height: 48,
                child: FilledButton(
                  onPressed: () => Navigator.pop(dialogContext, true),
                  style: FilledButton.styleFrom(
                    elevation: 0,
                    backgroundColor: const Color.fromARGB(255, 208, 54, 43),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(13),
                    ),
                  ),
                  child: Text(
                    'End follow-up',
                    style: GoogleFonts.outfit(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                height: 42,
                child: TextButton(
                  onPressed: () => Navigator.pop(dialogContext, false),
                  child: Text(
                    'Keep follow-up open',
                    style: GoogleFonts.outfit(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
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
    setState(() => _endingSession = true);
    try {
      await _repository.endConsultationFollowUp(widget.bookingId);
    } catch (error) {
      _showError(error);
    } finally {
      if (mounted) setState(() => _endingSession = false);
    }
  }
  // ===========================================================================
  // COMPLETION
  // ===========================================================================

  void _leaveCompletedPatientChat() {
    if (_leavingCompletedPatientChat || !mounted) return;
    _leavingCompletedPatientChat = true;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final navigator = Navigator.of(context);
      if (navigator.canPop()) {
        navigator.popUntil((route) => route.isFirst);
      } else {
        AuthNavigator.goToCorrectScreen(context);
      }
    });
  }

  Future<void> _handleConsultationCompleted() async {
    if (_completionHandling || !mounted) {
      return;
    }

    _completionHandling = true;

    try {
      final receipt = await _repository.getConsultationCompletion(
        widget.bookingId,
      );

      if (!mounted || !receipt.shouldShow) {
        return;
      }

      await _showCompletionReceipt(receipt);

      if (!mounted) return;

      if (receipt.isDoctor) {
        final followUpDate = await _showFollowUpDialog();
        if (!mounted) return;
        if (followUpDate != null) {
          await _repository.scheduleConsultationFollowUp(
            receipt.bookingId,
            followUpDate,
          );
        }
      }

      if (!receipt.isDoctor && !receipt.alreadyRated) {
        await _showDoctorRating();
      }

      await _repository.acknowledgeConsultationCompletion(widget.bookingId);

      if (receipt.isDoctor && mounted) {
        await AuthNavigator.goToCorrectScreen(context);
      }
    } catch (error) {
      _showError(error);
    } finally {
      _completionHandling = false;
    }
  }

  Future<DateTime?> _showFollowUpDialog() {
    DateTime? selectedDate;
    return showDialog<DateTime?>(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.black.withValues(alpha: 0.50),
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) {
          final label = selectedDate == null
              ? 'Choose a date'
              : DateFormat('d MMMM yyyy').format(selectedDate!);
          return Dialog(
            elevation: 0,
            backgroundColor: Colors.transparent,
            insetPadding: const EdgeInsets.symmetric(horizontal: 24),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(24, 28, 24, 20),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(24),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const _DialogIcon(
                    icon: Icons.event_repeat_rounded,
                    backgroundColor: Color(0xFFEAF3FF),
                    iconColor: AppColors.brand,
                  ),
                  const SizedBox(height: 20),
                  Text(
                    'Schedule a follow-up?',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.outfit(
                      fontSize: 20,
                      fontWeight: FontWeight.w500,
                      letterSpacing: -0.35,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'The patient will be notified and can message you free on the selected date.',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.outfit(
                      fontSize: 12.5,
                      height: 1.5,
                      color: AppColors.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 20),
                  Material(
                    color: const Color(0xFFF6F7F9),
                    borderRadius: BorderRadius.circular(14),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(14),
                      onTap: () async {
                        final now = DateTime.now();
                        final firstDate = DateTime(
                          now.year,
                          now.month,
                          now.day + 1,
                        );
                        final picked = await showDatePicker(
                          context: dialogContext,
                          initialDate: selectedDate ?? firstDate,
                          firstDate: firstDate,
                          lastDate: firstDate.add(const Duration(days: 365)),
                        );
                        if (picked != null) {
                          setDialogState(() => selectedDate = picked);
                        }
                      },
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 15,
                        ),
                        child: Row(
                          children: [
                            const AppIcon(
                              Icons.calendar_today_outlined,
                              size: 19,
                              color: AppColors.brand,
                            ),
                            const SizedBox(width: 11),
                            Expanded(
                              child: Text(
                                label,
                                style: GoogleFonts.outfit(
                                  fontSize: 13.5,
                                  fontWeight: FontWeight.w500,
                                  color: selectedDate == null
                                      ? AppColors.textSecondary
                                      : AppColors.textPrimary,
                                ),
                              ),
                            ),
                            const AppIcon(
                              Icons.chevron_right_rounded,
                              color: AppColors.textSecondary,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 18),
                  SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: FilledButton(
                      onPressed: selectedDate == null
                          ? null
                          : () => Navigator.pop(dialogContext, selectedDate),
                      style: FilledButton.styleFrom(
                        elevation: 0,
                        backgroundColor: AppColors.brand,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(13),
                        ),
                      ),
                      child: Text(
                        'Schedule follow-up',
                        style: GoogleFonts.outfit(
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 7),
                  TextButton(
                    onPressed: () => Navigator.pop(dialogContext),
                    child: Text(
                      'No follow-up',
                      style: GoogleFonts.outfit(
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  // ===========================================================================
  // COMPLETION DIALOG
  // ===========================================================================

  Future<void> _showCompletionReceipt(ConsultationCompletionModel receipt) {
    final money = NumberFormat('#,##0.00');

    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.black.withValues(alpha: 0.50),
      builder: (dialogContext) {
        return Dialog(
          elevation: 0,
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.symmetric(horizontal: 24),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(24, 28, 24, 22),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(24),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const _DialogIcon(
                  icon: Icons.check_rounded,
                  backgroundColor: Color(0xFFEAF8EF),
                  iconColor: Color(0xFF18A957),
                ),

                const SizedBox(height: 20),

                Text(
                  'Consultation completed',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.outfit(
                    fontSize: 20,
                    fontWeight: FontWeight.w500,
                    color: AppColors.textPrimary,
                    letterSpacing: -0.35,
                  ),
                ),

                const SizedBox(height: 8),

                Text(
                  receipt.isDoctor
                      ? 'The appointment is complete and your earnings have been settled.'
                      : 'Your consultation is complete and the payment has been settled successfully.',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.outfit(
                    fontSize: 12.5,
                    height: 1.5,
                    color: AppColors.textSecondary,
                  ),
                ),

                const SizedBox(height: 22),

                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF7F8FA),
                    borderRadius: BorderRadius.circular(15),
                  ),
                  child: Column(
                    children: [
                      _ReceiptRow(
                        label: 'Consultation fee',
                        value: 'Rs. ${money.format(receipt.grossFee)}',
                      ),

                      if (receipt.isDoctor) ...[
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 12),
                          child: Divider(height: 1, color: Color(0xFFE6E8EB)),
                        ),

                        _ReceiptRow(
                          label:
                              'Platform commission (${(receipt.commissionRate * 100).toStringAsFixed(0)}%)',
                          value:
                              '- Rs. ${money.format(receipt.commissionAmount)}',
                        ),

                        const SizedBox(height: 12),

                        _ReceiptRow(
                          label: 'Your earnings',
                          value: 'Rs. ${money.format(receipt.doctorEarning)}',
                          emphasized: true,
                        ),
                      ],
                    ],
                  ),
                ),

                const SizedBox(height: 24),

                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: FilledButton(
                    onPressed: () {
                      Navigator.pop(dialogContext);
                    },
                    style: FilledButton.styleFrom(
                      elevation: 0,
                      backgroundColor: AppColors.brand,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(13),
                      ),
                    ),
                    child: Text(
                      'Done',
                      style: GoogleFonts.outfit(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  // ===========================================================================
  // RATING
  // ===========================================================================

  Future<void> _showDoctorRating() async {
    int rating = 0;

    final reviewController = TextEditingController();

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.black.withValues(alpha: 0.50),
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return Dialog(
              elevation: 0,
              backgroundColor: Colors.transparent,
              insetPadding: const EdgeInsets.symmetric(horizontal: 22),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.fromLTRB(22, 27, 22, 20),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(24),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'How was your consultation?',
                      textAlign: TextAlign.center,
                      style: GoogleFonts.outfit(
                        fontSize: 19,
                        fontWeight: FontWeight.w500,
                        color: AppColors.textPrimary,
                        letterSpacing: -0.3,
                      ),
                    ),

                    const SizedBox(height: 7),

                    Text(
                      'Your feedback helps other patients choose with confidence.',
                      textAlign: TextAlign.center,
                      style: GoogleFonts.outfit(
                        fontSize: 12.2,
                        height: 1.45,
                        color: AppColors.textSecondary,
                      ),
                    ),

                    const SizedBox(height: 20),

                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: List.generate(5, (index) {
                        final value = index + 1;

                        return GestureDetector(
                          onTap: () {
                            HapticFeedback.selectionClick();

                            setDialogState(() {
                              rating = value;
                            });
                          },
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 4),
                            child: AppIcon(
                              value <= rating
                                  ? Icons.star_rounded
                                  : Icons.star_border_rounded,
                              size: 36,
                              color: const Color(0xFFFFB400),
                            ),
                          ),
                        );
                      }),
                    ),

                    const SizedBox(height: 20),

                    TextField(
                      controller: reviewController,
                      minLines: 3,
                      maxLines: 5,
                      maxLength: 1000,
                      textCapitalization: TextCapitalization.sentences,
                      style: GoogleFonts.outfit(
                        fontSize: 13,
                        color: AppColors.textPrimary,
                      ),
                      decoration: InputDecoration(
                        counterText: '',
                        hintText:
                            'Share a few words about your experience (optional)',
                        hintStyle: GoogleFonts.outfit(
                          fontSize: 12,
                          color: AppColors.textSecondary,
                        ),
                        filled: true,
                        fillColor: const Color(0xFFF7F8FA),
                        contentPadding: const EdgeInsets.all(14),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: BorderSide.none,
                        ),
                      ),
                    ),

                    const SizedBox(height: 18),

                    SizedBox(
                      width: double.infinity,
                      height: 47,
                      child: FilledButton(
                        onPressed: rating == 0
                            ? null
                            : () async {
                                try {
                                  await _repository.submitConsultationRating(
                                    bookingId: widget.bookingId,
                                    rating: rating,
                                    review: reviewController.text,
                                  );

                                  if (dialogContext.mounted) {
                                    Navigator.pop(dialogContext);
                                  }
                                } catch (error) {
                                  if (!dialogContext.mounted) {
                                    return;
                                  }

                                  ScaffoldMessenger.of(
                                    dialogContext,
                                  ).showSnackBar(
                                    SnackBar(
                                      content: Text(_readableError(error)),
                                    ),
                                  );
                                }
                              },
                        style: FilledButton.styleFrom(
                          elevation: 0,
                          backgroundColor: AppColors.brand,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: Text(
                          'Submit review',
                          style: GoogleFonts.outfit(
                            fontSize: 13.5,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ),

                    SizedBox(
                      width: double.infinity,
                      height: 41,
                      child: TextButton(
                        onPressed: () {
                          Navigator.pop(dialogContext);
                        },
                        child: Text(
                          'Skip for now',
                          style: GoogleFonts.outfit(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w500,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );

    reviewController.dispose();
  }

  // ===========================================================================
  // HELPERS
  // ===========================================================================

  String _mimeForFileName(String fileName) {
    final dot = fileName.lastIndexOf('.');

    final extension = dot < 0 ? '' : fileName.substring(dot + 1).toLowerCase();

    switch (extension) {
      case 'pdf':
        return 'application/pdf';

      case 'doc':
        return 'application/msword';

      case 'docx':
        return 'application/vnd.openxmlformats-officedocument.wordprocessingml.document';

      case 'png':
        return 'image/png';

      case 'mp4':
      case 'm4v':
        return 'video/mp4';

      case 'mov':
        return 'video/quicktime';

      default:
        return 'image/jpeg';
    }
  }

  String _readableError(Object error) {
    return AppErrorMessage.from(error);
  }

  void _showError(Object error) {
    if (!mounted) return;

    _showSnack(_readableError(error), isError: true);
  }

  void _showSnack(String text, {bool isError = false}) {
    if (!mounted) return;

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          elevation: 0,
          backgroundColor: isError
              ? const Color(0xFF3C2020)
              : const Color(0xFF22252A),
          margin: const EdgeInsets.all(16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          content: Text(
            text,
            style: GoogleFonts.outfit(fontSize: 13, color: Colors.white),
          ),
        ),
      );
  }

  bool _sameDay(DateTime first, DateTime second) {
    final a = first.toLocal();
    final b = second.toLocal();

    return a.year == b.year && a.month == b.month && a.day == b.day;
  }

  // ===========================================================================
  // BUILD
  // ===========================================================================

  @override
  Widget build(BuildContext context) {
    final canCompose = _canComposeMessages;
    return Scaffold(
      // WhatsApp-like warm neutral conversation surface.
      backgroundColor: const Color(0xFFF0EEEA),

      appBar: _buildAppBar(),

      body: _loading
          ? const _LoadingView()
          : _error != null
          ? _ErrorView(
              message: _error!,
              retry: () {
                setState(() {
                  _loading = true;
                  _error = null;
                });

                _initialize();
              },
            )
          : Column(
              children: [
                // ---------------------------------------------------------
                // PATIENT APPOINTMENT STATUS
                // ---------------------------------------------------------
                if (!_isDoctor &&
                    _session != null &&
                    _session?.isFollowUpOpen != true)
                  _PatientAppointmentStatusBar(
                    session: _session!,
                    doctorName: widget.peerName,
                    cancelling: _cancellingAppointment,
                    onCancel: _cancelAcceptedAppointment,
                  ),

                // ---------------------------------------------------------
                // WAITING TO START
                // ---------------------------------------------------------
                if (_isDoctor &&
                    _session?.bookingStatus == 'accepted' &&
                    _session?.isInProgress != true)
                  _SessionRequestBar(
                    pending: _session?.isRequestPending == true,
                    busy: _sessionActionBusy,
                    onRequest: _requestSessionStart,
                  ),

                // ---------------------------------------------------------
                // ACTIVE CONSULTATION
                // ---------------------------------------------------------
                if (_isDoctor && _session?.isInProgress == true)
                  _ActiveConsultationBar(
                    ending: _endingSession,
                    onEnd: _endSession,
                    label: 'End consultation',
                    endingLabel: 'Ending consultation…',
                  ),

                if (_isDoctor && _session?.isFollowUpOpen == true)
                  _ActiveConsultationBar(
                    ending: _endingSession,
                    onEnd: _endFollowUp,
                    label: 'End follow-up',
                    endingLabel: 'Ending follow-up…',
                  ),

                // ---------------------------------------------------------
                // MESSAGE AREA
                // ---------------------------------------------------------
                Expanded(
                  child: _messages.isEmpty
                      ? _EmptyChat(
                          peerName: widget.peerName,
                          connected:
                              !_isDoctor &&
                              _session?.bookingStatus == 'accepted',
                        )
                      : ListView.builder(
                          controller: _scrollController,
                          keyboardDismissBehavior:
                              ScrollViewKeyboardDismissBehavior.onDrag,
                          padding: const EdgeInsets.fromLTRB(8, 8, 8, 16),
                          itemCount: _messages.length + (_loadingOlder ? 1 : 0),
                          itemBuilder: (context, index) {
                            if (_loadingOlder && index == 0) {
                              return const Padding(
                                padding: EdgeInsets.symmetric(vertical: 12),
                                child: Center(
                                  child: SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  ),
                                ),
                              );
                            }

                            final offset = _loadingOlder ? 1 : 0;

                            final messageIndex = index - offset;

                            var message = _messages[messageIndex];

                            // ---------------------------------------------
                            // RESOLVE REPLY
                            // ---------------------------------------------

                            if (message.replyToMessageId != null) {
                              final matches = _messages.where(
                                (item) => item.id == message.replyToMessageId,
                              );

                              if (matches.isNotEmpty) {
                                message = message.copyWith(
                                  replyTo: matches.first,
                                );
                              }
                            }

                            final mine =
                                message.senderId == _repository.currentUserId;

                            final showDate =
                                messageIndex == 0 ||
                                !_sameDay(
                                  _messages[messageIndex - 1].createdAt,
                                  message.createdAt,
                                );

                            return KeyedSubtree(
                              key: _messageKeys.putIfAbsent(
                                message.id,
                                () => GlobalKey(),
                              ),
                              child: Column(
                                children: [
                                  if (showDate)
                                    _DateDivider(date: message.createdAt),

                                  if (message.type == MessageType.system)
                                    _SystemMessage(message: message)
                                  else
                                    _MessageBubble(
                                      message: message,
                                      highlighted:
                                          _highlightedMessageId == message.id,
                                      mine: mine,
                                      repository: _repository,
                                      onReply: () {
                                        setState(() {
                                          _replyingTo = message;
                                        });
                                      },
                                      onReplyTap:
                                          message.replyToMessageId == null
                                          ? null
                                          : () => _goToRepliedMessage(
                                              message.replyToMessageId!,
                                            ),
                                      onRetry:
                                          mine &&
                                              message.status ==
                                                  MessageStatus.failed
                                          ? () => _retryMessage(message)
                                          : null,
                                      onDelete: mine && !message.isDeleted
                                          ? () {
                                              if (message.status ==
                                                  MessageStatus.failed) {
                                                setState(() {
                                                  _messages.removeWhere(
                                                    (item) =>
                                                        item.id == message.id,
                                                  );
                                                });
                                              } else {
                                                _delete(message);
                                              }
                                            }
                                          : null,
                                    ),
                                ],
                              ),
                            );
                          },
                        ),
                ),

                // ---------------------------------------------------------
                // INPUT
                // ---------------------------------------------------------
                if (_messageCounterUsed != null && _messageCounterTotal != null)
                  _LimitedMessageCounter(
                    used: _messageCounterUsed!,
                    total: _messageCounterTotal!,
                  ),
                if (_session?.isRefunded == true)
                  const _ClosedNotice(
                    message:
                        'This consultation was refunded. Chat history is view-only.',
                  )
                else if (canCompose &&
                    !_preSessionLimitReached &&
                    !_upcomingFollowUpLimitReached &&
                    !_postConsultationLimitReached)
                  _Composer(
                    controller: _textController,
                    reply: _replyingTo,
                    sending: _sending,
                    recording: _recording,
                    recordingPaused: _recordingPaused,
                    recordingElapsed: _recordingElapsed,
                    waveform: _recordingWaveform,
                    onChanged: _onComposerChanged,
                    onCancelReply: () {
                      setState(() {
                        _replyingTo = null;
                      });
                    },
                    onAttach: _showAttachments,
                    onRecordStart: _startRecording,
                    onRecordSend: () => _finishRecording(send: true),
                    onRecordCancel: () => _finishRecording(send: false),
                    onRecordTogglePause: _togglePauseRecording,
                    onSend: _sendText,
                  )
                else if (_preSessionLimitReached)
                  _MessageLimitNotice(
                    isDoctor: _isDoctor,
                    pending: _session?.isRequestPending == true,
                    busy: _sessionActionBusy,
                    onStart: _requestSessionStart,
                  )
                else if (_upcomingFollowUpLimitReached)
                  _ClosedNotice(
                    message:
                        'Waiting-period message limit reached. Follow-up chat fully opens on ${DateFormat('d MMMM yyyy').format(_session!.followUpDate!)}.',
                  )
                else if (_postConsultationLimitReached)
                  const _ClosedNotice(
                    message:
                        'Post-consultation message limit reached. You can still view this chat from history.',
                  )
                else
                  _ClosedNotice(
                    message: _session?.isFollowUpUpcoming == true
                        ? 'You can send up to 5 messages before the follow-up date. Video call unlocks on ${DateFormat('d MMMM yyyy').format(_session!.followUpDate!)}.'
                        : null,
                  ),
              ],
            ),
    );
  }

  // ===========================================================================
  // APP BAR
  // ===========================================================================

  PreferredSizeWidget _buildAppBar() {
    final inProgress = _session?.isInProgress == true;
    final canCall = inProgress || _session?.isFollowUpOpen == true;
    final showLockedCall =
        ((_session?.bookingStatus == 'accepted' && !_isDoctor) ||
            _session?.isFollowUpUpcoming == true) &&
        !canCall;
    final hasActiveCall =
        widget.onReturnToCall != null && _session?.callEndedAt == null;

    return AppBar(
      elevation: 0,
      scrolledUnderElevation: 0,

      backgroundColor: Colors.white,

      surfaceTintColor: Colors.transparent,

      toolbarHeight: 70,

      titleSpacing: 0,

      leadingWidth: 47,

      leading: IconButton(
        onPressed: () {
          Navigator.pop(context);
        },
        splashRadius: 21,
        icon: const AppIcon(Icons.arrow_back_rounded, size: 23),
        color: AppColors.textPrimary,
      ),

      title: Row(
        children: [
          // -------------------------------------------------------------------
          // DOCTOR IMAGE + ACTIVE DOT
          // -------------------------------------------------------------------
          GestureDetector(
            onTap: widget.onPeerTap,
            behavior: HitTestBehavior.opaque,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: const Color(0xFFF1F3F5),
                    shape: BoxShape.circle,
                    border: Border.all(color: const Color(0xFFE5E8EC)),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: widget.peerAvatarUrl?.trim().isNotEmpty == true
                      ? CachedNetworkImage(
                          imageUrl: widget.peerAvatarUrl!,
                          fit: BoxFit.cover,
                          errorWidget: (_, _, _) {
                            return AppIcon(
                              Icons.person_rounded,
                              size: 23,
                              color: AppColors.brand,
                            );
                          },
                        )
                      : AppIcon(
                          Icons.person_rounded,
                          size: 23,
                          color: AppColors.brand,
                        ),
                ),

                if (!_isDoctor && inProgress)
                  Positioned(
                    right: 0,
                    bottom: 0,
                    child: Container(
                      width: 13,
                      height: 13,
                      padding: const EdgeInsets.all(2),
                      decoration: const BoxDecoration(
                        color: Colors.white,
                        shape: BoxShape.circle,
                      ),
                      child: Container(
                        decoration: const BoxDecoration(
                          color: Color(0xFF18A957),
                          shape: BoxShape.circle,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),

          const SizedBox(width: 11),

          // -------------------------------------------------------------------
          // DOCTOR NAME + VERIFIED
          // -------------------------------------------------------------------
          Expanded(
            child: GestureDetector(
              onTap: widget.onPeerTap,
              behavior: HitTestBehavior.opaque,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          widget.peerName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.outfit(
                            fontSize: 16,
                            height: 1.12,
                            fontWeight: FontWeight.w500,
                            color: AppColors.textPrimary,
                            letterSpacing: -0.2,
                          ),
                        ),
                      ),

                      if (widget.peerVerified) ...[
                        const SizedBox(width: 5),

                        AppIcon(
                          Icons.verified_rounded,
                          size: 17,
                          color: AppColors.brand,
                        ),
                      ],

                      if (_isDoctor && _peerOnline) ...[
                        const SizedBox(width: 7),
                        Semantics(
                          label: 'Patient is online',
                          child: Container(
                            width: 9,
                            height: 9,
                            decoration: const BoxDecoration(
                              color: Color(0xFF18A957),
                              shape: BoxShape.circle,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),

                  const SizedBox(height: 4),

                  Row(
                    children: [
                      Flexible(
                        child: AnimatedSwitcher(
                          duration: const Duration(milliseconds: 160),
                          child: Text(
                            _peerRecording
                                ? 'recording audio…'
                                : (_peerTyping
                                      ? 'typing…'
                                      : widget.peerSubtitle),
                            key: ValueKey(
                              _peerRecording
                                  ? 'recording'
                                  : (_peerTyping ? 'typing' : 'subtitle'),
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.outfit(
                              fontSize: 10.8,
                              height: 1.15,
                              fontWeight: FontWeight.w400,
                              color: _peerTyping || _peerRecording
                                  ? AppColors.brand
                                  : AppColors.textSecondary,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),

      // -----------------------------------------------------------------------
      // VIDEO CALL
      // -----------------------------------------------------------------------
      actions: [
        if (hasActiveCall)
          Padding(
            padding: const EdgeInsets.only(right: 10),
            child: Center(
              child: FilledButton.icon(
                onPressed: widget.onReturnToCall,
                icon: const AppIcon(Icons.videocam_rounded, size: 17),
                label: const Text('Call active'),
                style: FilledButton.styleFrom(
                  elevation: 0,
                  backgroundColor: const Color(0xFFEAF7EF),
                  foregroundColor: const Color(0xFF16834B),
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  minimumSize: const Size(0, 38),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20),
                  ),
                ),
              ),
            ),
          )
        else if (canCall || showLockedCall)
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: Material(
              color: (canCall ? AppColors.brand : AppColors.textSecondary)
                  .withValues(alpha: 0.075),
              shape: const CircleBorder(),
              child: InkWell(
                customBorder: const CircleBorder(),
                onTap: !canCall
                    ? () {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text(
                              'Video call unlocks when the doctor starts the consultation.',
                            ),
                          ),
                        );
                      }
                    : (_callStarting ? null : _startVideoCall),
                child: SizedBox(
                  width: 43,
                  height: 43,
                  child: _callStarting
                      ? Padding(
                          padding: const EdgeInsets.all(12),
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: AppColors.brand,
                          ),
                        )
                      : Stack(
                          alignment: Alignment.center,
                          children: [
                            AppIcon(
                              Icons.videocam_rounded,
                              size: 21,
                              color: canCall
                                  ? AppColors.brand
                                  : AppColors.textSecondary,
                            ),
                            if (showLockedCall)
                              Positioned(
                                right: 9,
                                bottom: 9,
                                child: AppIcon(
                                  Icons.lock_rounded,
                                  size: 10,
                                  color: AppColors.textSecondary,
                                ),
                              ),
                          ],
                        ),
                ),
              ),
            ),
          ),
      ],

      bottom: const PreferredSize(
        preferredSize: Size.fromHeight(1),
        child: Divider(height: 1, thickness: 1, color: Color(0xFFE9ECF0)),
      ),
    );
  }

  // ===========================================================================
  // DISPOSE
  // ===========================================================================

  @override
  void dispose() {
    _typingIdleTimer?.cancel();
    _typingHeartbeatTimer?.cancel();
    _recordingHeartbeatTimer?.cancel();
    _peerTypingExpiryTimer?.cancel();
    unawaited(_closeTypingChannel());
    PushNotificationService.instance.markChatClosed(widget.bookingId);
    WidgetsBinding.instance.removeObserver(this);

    _subscription?.cancel();
    _sessionSubscription?.cancel();
    _sessionRequestExpiryTimer?.cancel();
    _highlightTimer?.cancel();
    _recordingTimer?.cancel();
    _amplitudeSubscription?.cancel();

    _recorder.dispose();
    _textController.dispose();
    _scrollController.dispose();

    super.dispose();
  }
}

// =============================================================================
// DIALOG ICON
// =============================================================================

class _DialogIcon extends StatelessWidget {
  const _DialogIcon({
    required this.icon,
    required this.backgroundColor,
    required this.iconColor,
  });

  final IconData icon;
  final Color backgroundColor;
  final Color iconColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 74,
      height: 74,
      decoration: BoxDecoration(color: backgroundColor, shape: BoxShape.circle),
      alignment: Alignment.center,
      child: Container(
        width: 44,
        height: 44,
        decoration: const BoxDecoration(
          color: Colors.white,
          shape: BoxShape.circle,
        ),
        alignment: Alignment.center,
        child: AppIcon(icon, size: 23, color: iconColor),
      ),
    );
  }
}

// =============================================================================
// DATE
// =============================================================================

class _DateDivider extends StatelessWidget {
  const _DateDivider({required this.date});

  final DateTime date;

  String get _text {
    final value = date.toLocal();

    final now = DateTime.now();

    final today = DateTime(now.year, now.month, now.day);

    final messageDay = DateTime(value.year, value.month, value.day);

    final difference = today.difference(messageDay);

    if (difference.inDays == 0) {
      return 'Today';
    }

    if (difference.inDays == 1) {
      return 'Yesterday';
    }

    if (value.year == now.year) {
      return DateFormat('MMM d').format(value);
    }

    return DateFormat('MMM d, yyyy').format(value);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 9),
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.92),
            borderRadius: BorderRadius.circular(8),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.025),
                blurRadius: 2,
                offset: const Offset(0, 1),
              ),
            ],
          ),
          child: Text(
            _text,
            style: GoogleFonts.outfit(
              fontSize: 10,
              fontWeight: FontWeight.w500,
              color: const Color(0xFF6C727B),
            ),
          ),
        ),
      ),
    );
  }
}

// =============================================================================
// SYSTEM MESSAGE
// =============================================================================

class _SystemMessage extends StatelessWidget {
  const _SystemMessage({required this.message});

  final ChatMessageModel message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        constraints: const BoxConstraints(maxWidth: 280),
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.90),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          message.text ?? 'Consultation update',
          textAlign: TextAlign.center,
          style: GoogleFonts.outfit(
            fontSize: 10.4,
            height: 1.35,
            color: AppColors.textSecondary,
          ),
        ),
      ),
    );
  }
}

// =============================================================================
// WHATSAPP-LIKE MESSAGE BUBBLE
// =============================================================================
class _MessageBubble extends StatelessWidget {
  const _MessageBubble({
    required this.message,
    required this.mine,
    required this.repository,
    required this.onReply,
    required this.highlighted,
    this.onReplyTap,
    this.onRetry,
    this.onDelete,
  });

  final ChatMessageModel message;
  final bool mine;
  final ChatRepository repository;

  final VoidCallback onReply;
  final VoidCallback? onReplyTap;
  final VoidCallback? onRetry;
  final VoidCallback? onDelete;
  final bool highlighted;

  bool get _isImage =>
      message.type == MessageType.image && message.mediaUrl != null;

  bool get _isDocument =>
      message.type == MessageType.file && message.mediaUrl != null && !_isVideo;

  bool get _isVideo =>
      message.type == MessageType.file &&
      message.mediaUrl != null &&
      (message.mimeType?.toLowerCase().startsWith('video/') == true);

  bool get _isVoice =>
      message.type == MessageType.voice && message.mediaUrl != null;

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.sizeOf(context).width;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      color: highlighted
          ? AppColors.brand.withValues(alpha: .16)
          : Colors.transparent,
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: _SwipeToReply(
        enabled: !message.isDeleted,
        swipeLeft: mine,
        onReply: onReply,
        child: GestureDetector(
          behavior: HitTestBehavior.translucent,
          onLongPress: onDelete == null
              ? null
              : () {
                  _showMessageActions(context);
                },
          child: Align(
            alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: screenWidth * 0.80),
              child: Container(
                margin: EdgeInsets.only(
                  left: mine ? 48 : 0,
                  right: mine ? 0 : 48,
                  bottom: 5,
                ),

                padding: _isImage
                    ? const EdgeInsets.all(4)
                    : _isDocument
                    ? const EdgeInsets.fromLTRB(6, 6, 6, 5)
                    : const EdgeInsets.fromLTRB(10, 7, 9, 6),

                decoration: BoxDecoration(
                  color: mine ? AppColors.brand : Colors.white,

                  borderRadius: BorderRadius.only(
                    topLeft: Radius.circular(mine ? 17 : 5),
                    topRight: Radius.circular(mine ? 5 : 17),
                    bottomLeft: const Radius.circular(17),
                    bottomRight: const Radius.circular(17),
                  ),

                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.04),
                      blurRadius: 3,
                      offset: const Offset(0, 1),
                    ),
                  ],
                ),

                child: message.isDeleted
                    ? _DeletedMessage(mine: mine)
                    : Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // -------------------------------------------------------
                          // REPLY
                          // -------------------------------------------------------
                          if (message.replyToMessageId != null) ...[
                            _ReplyBubble(
                              message: message.replyTo,
                              mine: mine,
                              onTap: onReplyTap,
                            ),

                            const SizedBox(height: 5),
                          ],

                          // -------------------------------------------------------
                          // IMAGE
                          // -------------------------------------------------------
                          if (_isImage)
                            _ImageMessage(
                              message: message,
                              repository: repository,
                              mine: mine,
                              onRetry: onRetry,
                            )
                          else if (_isVideo)
                            _VideoMessage(
                              message: message,
                              repository: repository,
                              mine: mine,
                            )
                          // -------------------------------------------------------
                          // DOCUMENT
                          // -------------------------------------------------------
                          else if (_isDocument)
                            _DocumentMessage(
                              message: message,
                              repository: repository,
                              mine: mine,
                            )
                          // -------------------------------------------------------
                          // VOICE
                          // -------------------------------------------------------
                          else if (_isVoice)
                            _VoicePlayer(
                              key: ValueKey(
                                '${message.id}-${message.mediaUrl}',
                              ),
                              path: message.mediaUrl!,
                              repository: repository,
                              duration: message.voiceDurationSeconds,
                              mine: mine,
                              localFile:
                                  message.status == MessageStatus.sending ||
                                  message.status == MessageStatus.failed,
                            )
                          // -------------------------------------------------------
                          // TEXT
                          // -------------------------------------------------------
                          else
                            _TextMessage(
                              message: message,
                              mine: mine,
                              onRetry: onRetry,
                            ),

                          // -------------------------------------------------------
                          // META FOR DOCUMENT / VOICE
                          // -------------------------------------------------------
                          if (_isDocument || _isVoice) ...[
                            const SizedBox(height: 5),

                            Align(
                              alignment: Alignment.centerRight,
                              child: Padding(
                                padding: const EdgeInsets.only(right: 2),
                                child: _MessageMeta(
                                  message: message,
                                  mine: mine,
                                  onRetry: onRetry,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _showMessageActions(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      useSafeArea: true,
      builder: (sheetContext) {
        return Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: const Color(0xFFD8DBDF),
                  borderRadius: BorderRadius.circular(30),
                ),
              ),

              const SizedBox(height: 14),

              if (onDelete != null)
                _MessageAction(
                  icon: Icons.delete_outline_rounded,
                  title: 'Delete for everyone',
                  destructive: true,
                  onTap: () {
                    Navigator.pop(sheetContext);
                    onDelete!();
                  },
                ),
            ],
          ),
        );
      },
    );
  }
}

class _SwipeToReply extends StatefulWidget {
  const _SwipeToReply({
    required this.child,
    required this.enabled,
    required this.swipeLeft,
    required this.onReply,
  });

  final Widget child;
  final bool enabled;
  final bool swipeLeft;
  final VoidCallback onReply;

  @override
  State<_SwipeToReply> createState() => _SwipeToReplyState();
}

class _SwipeToReplyState extends State<_SwipeToReply> {
  double _offset = 0;
  bool _thresholdFeedbackSent = false;

  void _update(DragUpdateDetails details) {
    if (!widget.enabled) return;
    final next = widget.swipeLeft
        ? (_offset + details.delta.dx).clamp(-62.0, 0.0)
        : (_offset + details.delta.dx).clamp(0.0, 62.0);
    final crossed = widget.swipeLeft ? next <= -44 : next >= 44;
    if (crossed && !_thresholdFeedbackSent) {
      HapticFeedback.selectionClick();
      _thresholdFeedbackSent = true;
    } else if (!crossed) {
      _thresholdFeedbackSent = false;
    }
    setState(() => _offset = next);
  }

  void _end(DragEndDetails details) {
    final shouldReply =
        widget.enabled && (widget.swipeLeft ? _offset <= -44 : _offset >= 44);
    setState(() => _offset = 0);
    _thresholdFeedbackSent = false;
    if (shouldReply) widget.onReply();
  }

  @override
  Widget build(BuildContext context) {
    final progress = (_offset.abs() / 62).clamp(0.0, 1.0);
    return Stack(
      alignment: widget.swipeLeft
          ? Alignment.centerRight
          : Alignment.centerLeft,
      children: [
        Padding(
          padding: EdgeInsets.only(
            left: widget.swipeLeft ? 0 : 13,
            right: widget.swipeLeft ? 13 : 0,
            bottom: 5,
          ),
          child: Opacity(
            opacity: progress,
            child: Transform.scale(
              scale: .72 + progress * .28,
              child: Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: AppColors.brand.withValues(alpha: .12),
                  shape: BoxShape.circle,
                ),
                child: const AppIcon(
                  Icons.reply_rounded,
                  size: 19,
                  color: AppColors.brand,
                ),
              ),
            ),
          ),
        ),
        GestureDetector(
          behavior: HitTestBehavior.translucent,
          onHorizontalDragUpdate: _update,
          onHorizontalDragEnd: _end,
          onHorizontalDragCancel: () {
            if (mounted) setState(() => _offset = 0);
          },
          child: AnimatedContainer(
            duration: _offset == 0
                ? const Duration(milliseconds: 170)
                : Duration.zero,
            curve: Curves.easeOutCubic,
            transform: Matrix4.translationValues(_offset, 0, 0),
            child: widget.child,
          ),
        ),
      ],
    );
  }
}
// =============================================================================
// TEXT MESSAGE
// =============================================================================

class _TextMessage extends StatelessWidget {
  const _TextMessage({required this.message, required this.mine, this.onRetry});

  final ChatMessageModel message;
  final bool mine;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      alignment: WrapAlignment.end,
      crossAxisAlignment: WrapCrossAlignment.end,
      spacing: 6,
      runSpacing: 2,
      children: [
        Text(
          message.text ?? '',
          style: GoogleFonts.outfit(
            fontSize: 14,
            height: 1.34,
            fontWeight: FontWeight.w400,
            color: mine ? Colors.white : AppColors.textPrimary,
          ),
        ),

        Padding(
          padding: const EdgeInsets.only(bottom: 1),
          child: _MessageMeta(message: message, mine: mine, onRetry: onRetry),
        ),
      ],
    );
  }
}

// =============================================================================
// IMAGE MESSAGE
// =============================================================================

class _ImageMessage extends StatefulWidget {
  const _ImageMessage({
    required this.message,
    required this.repository,
    required this.mine,
    this.onRetry,
  });

  final ChatMessageModel message;
  final ChatRepository repository;
  final bool mine;
  final VoidCallback? onRetry;

  @override
  State<_ImageMessage> createState() => _ImageMessageState();
}

class _ImageMessageState extends State<_ImageMessage> {
  Future<String>? _urlFuture;

  bool get _usesLocalFile =>
      widget.message.status == MessageStatus.sending ||
      widget.message.status == MessageStatus.failed;

  @override
  void initState() {
    super.initState();
    _prepareSource();
  }

  @override
  void didUpdateWidget(covariant _ImageMessage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.message.mediaUrl != widget.message.mediaUrl ||
        oldWidget.message.status != widget.message.status) {
      _prepareSource();
    }
  }

  void _prepareSource() {
    _urlFuture = _usesLocalFile
        ? null
        : widget.repository.createSignedMediaUrl(widget.message.mediaUrl!);
  }

  @override
  Widget build(BuildContext context) {
    if (_usesLocalFile) {
      return _buildImage(
        child: Image.file(
          File(widget.message.mediaUrl!),
          fit: BoxFit.cover,
          errorBuilder: (_, _, _) => _imagePlaceholder(error: true),
        ),
      );
    }

    return FutureBuilder<String>(
      future: _urlFuture!,
      builder: (context, snapshot) {
        return _buildImage(
          onTap: snapshot.hasData
              ? () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => _FullScreenImageViewer(
                      url: snapshot.data!,
                      cacheKey: widget.message.mediaUrl!,
                      fileName: widget.message.fileName,
                    ),
                  ),
                )
              : null,
          child: snapshot.hasData
              ? CachedNetworkImage(
                  imageUrl: snapshot.data!,
                  cacheKey: widget.message.mediaUrl!,
                  fit: BoxFit.cover,
                  errorWidget: (_, _, _) => _imagePlaceholder(error: true),
                )
              : _imagePlaceholder(),
        );
      },
    );
  }

  Widget _buildImage({required Widget child, VoidCallback? onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Stack(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(14),
            child: SizedBox(width: 238, height: 190, child: child),
          ),

          // -----------------------------------------------------------------
          // TIME / SEND STATUS OVER IMAGE
          // -----------------------------------------------------------------
          Positioned(
            right: 7,
            bottom: 7,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.42),
                borderRadius: BorderRadius.circular(8),
              ),
              child: _MessageMeta(
                message: widget.message,
                mine: widget.mine,
                onMedia: true,
                onRetry: widget.onRetry,
              ),
            ),
          ),
          if (widget.message.status == MessageStatus.sending)
            Positioned.fill(
              child: IgnorePointer(
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _imagePlaceholder({bool error = false}) {
    return Container(
      width: 238,
      height: 190,
      color: const Color(0xFFE8EBEF),
      alignment: Alignment.center,
      child: error
          ? AppIcon(
              Icons.broken_image_outlined,
              size: 30,
              color: AppColors.textSecondary,
            )
          : SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: AppColors.brand,
              ),
            ),
    );
  }
}

class _VideoMessage extends StatefulWidget {
  const _VideoMessage({
    required this.message,
    required this.repository,
    required this.mine,
  });
  final ChatMessageModel message;
  final ChatRepository repository;
  final bool mine;

  @override
  State<_VideoMessage> createState() => _VideoMessageState();
}

class _VideoMessageState extends State<_VideoMessage> {
  late Future<String> _urlFuture;

  @override
  void initState() {
    super.initState();
    _urlFuture = widget.repository.createSignedMediaUrl(
      widget.message.mediaUrl!,
    );
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<String>(
      future: _urlFuture,
      builder: (context, snapshot) => InkWell(
        onTap: snapshot.hasData
            ? () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => _FullScreenVideoViewer(
                    url: snapshot.data!,
                    fileName: widget.message.fileName,
                  ),
                ),
              )
            : null,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          width: 238,
          height: 160,
          decoration: BoxDecoration(
            color: const Color(0xFF20242A),
            borderRadius: BorderRadius.circular(14),
          ),
          child: snapshot.hasError
              ? const AppIcon(
                  Icons.broken_image_outlined,
                  color: Colors.white54,
                )
              : snapshot.hasData
              ? const Center(
                  child: CircleAvatar(
                    radius: 27,
                    backgroundColor: Colors.white24,
                    child: AppIcon(
                      Icons.play_arrow_rounded,
                      size: 35,
                      color: Colors.white,
                    ),
                  ),
                )
              : const Center(
                  child: CircularProgressIndicator(color: Colors.white),
                ),
        ),
      ),
    );
  }
}

Future<void> _saveMedia(
  BuildContext context,
  String url, {
  required bool video,
  String? fileName,
}) async {
  final messenger = ScaffoldMessenger.of(context);
  try {
    var hasGalleryAccess = await Gal.hasAccess();
    if (!hasGalleryAccess) {
      hasGalleryAccess = await Gal.requestAccess();
    }
    if (!hasGalleryAccess) {
      if (context.mounted) {
        messenger.showSnackBar(
          const SnackBar(
            content: Text('Gallery access is required to save this media.'),
          ),
        );
      }
      return;
    }

    final request = await HttpClient().getUrl(Uri.parse(url));
    request.headers.set(HttpHeaders.acceptHeader, '*/*');
    final response = await request.close();
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw HttpException('Download failed with status ${response.statusCode}');
    }
    final bytes = await consolidateHttpClientResponseBytes(response);
    if (bytes.isEmpty)
      throw const FileSystemException('Downloaded file is empty');
    final directory = await getTemporaryDirectory();
    final contentType = response.headers.contentType?.mimeType.toLowerCase();
    final extension = video
        ? (contentType == 'video/quicktime' ? 'mov' : 'mp4')
        : (contentType == 'image/png'
              ? 'png'
              : contentType == 'image/webp'
              ? 'webp'
              : 'jpg');
    var requestedName = fileName?.trim().isNotEmpty == true
        ? fileName!
        : 'darmaan_${DateTime.now().millisecondsSinceEpoch}.$extension';
    if (!requestedName.contains('.'))
      requestedName = '$requestedName.$extension';
    final safeName = requestedName.replaceAll(RegExp(r'[^a-zA-Z0-9._-]'), '_');
    final file = File('${directory.path}/$safeName');
    await file.writeAsBytes(bytes, flush: true);
    if (video) {
      await Gal.putVideo(file.path);
    } else {
      await Gal.putImage(file.path);
    }
    if (context.mounted) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            video ? 'Video saved to gallery.' : 'Photo saved to gallery.',
          ),
        ),
      );
    }
  } on GalException catch (error) {
    if (context.mounted) {
      final message = switch (error.type) {
        GalExceptionType.accessDenied =>
          'Gallery permission was denied. Enable it from app settings.',
        GalExceptionType.notEnoughSpace =>
          'There is not enough storage space to save this media.',
        GalExceptionType.notSupportedFormat =>
          'This media format is not supported by your gallery.',
        GalExceptionType.unexpected => 'The gallery could not save this media.',
      };
      messenger.showSnackBar(SnackBar(content: Text(message)));
    }
  } catch (_) {
    if (context.mounted) {
      messenger.showSnackBar(
        const SnackBar(
          content: Text('The media could not be downloaded. Please try again.'),
        ),
      );
    }
  }
}

class _FullScreenImageViewer extends StatelessWidget {
  const _FullScreenImageViewer({
    required this.url,
    required this.cacheKey,
    this.fileName,
  });
  final String url;
  final String cacheKey;
  final String? fileName;

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: Colors.black,
    appBar: AppBar(
      backgroundColor: Colors.black,
      foregroundColor: Colors.white,
      actions: [
        IconButton(
          tooltip: 'Save to gallery',
          onPressed: () =>
              _saveMedia(context, url, video: false, fileName: fileName),
          icon: const AppIcon(Icons.download_rounded),
        ),
      ],
    ),
    body: Center(
      child: InteractiveViewer(
        minScale: .8,
        maxScale: 5,
        child: CachedNetworkImage(
          imageUrl: url,
          cacheKey: cacheKey,
          fit: BoxFit.contain,
          useOldImageOnUrlChange: true,
          errorWidget: (_, _, _) => const AppIcon(
            Icons.broken_image_outlined,
            color: Colors.white,
          ),
        ),
      ),
    ),
  );
}

class _FullScreenVideoViewer extends StatefulWidget {
  const _FullScreenVideoViewer({required this.url, this.fileName});
  final String url;
  final String? fileName;

  @override
  State<_FullScreenVideoViewer> createState() => _FullScreenVideoViewerState();
}

class _FullScreenVideoViewerState extends State<_FullScreenVideoViewer> {
  late final VideoPlayerController _controller;
  late final Future<void> _initializing;

  @override
  void initState() {
    super.initState();
    _controller = VideoPlayerController.networkUrl(Uri.parse(widget.url));
    _initializing = _controller.initialize().then((_) {
      _controller.play();
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _togglePlayback() async {
    if (_controller.value.isPlaying) {
      await _controller.pause();
    } else {
      await _controller.play();
    }
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: Colors.black,
    appBar: AppBar(
      backgroundColor: Colors.black,
      foregroundColor: Colors.white,
      actions: [
        IconButton(
          tooltip: 'Save to gallery',
          onPressed: () => _saveMedia(
            context,
            widget.url,
            video: true,
            fileName: widget.fileName,
          ),
          icon: const AppIcon(Icons.download_rounded),
        ),
      ],
    ),
    body: FutureBuilder<void>(
      future: _initializing,
      builder: (context, snapshot) {
        if (snapshot.hasError)
          return const Center(
            child: Text(
              'Could not play this video.',
              style: TextStyle(color: Colors.white),
            ),
          );
        if (snapshot.connectionState != ConnectionState.done)
          return const Center(
            child: CircularProgressIndicator(color: Colors.white),
          );
        return GestureDetector(
          onTap: _togglePlayback,
          child: Center(
            child: AspectRatio(
              aspectRatio: _controller.value.aspectRatio,
              child: VideoPlayer(_controller),
            ),
          ),
        );
      },
    ),
  );
}

// =============================================================================
// DOCUMENT MESSAGE
// =============================================================================
class _DocumentMessage extends StatelessWidget {
  const _DocumentMessage({
    required this.message,
    required this.repository,
    required this.mine,
  });

  final ChatMessageModel message;
  final ChatRepository repository;
  final bool mine;

  String get _extension {
    final name = message.fileName ?? '';

    if (!name.contains('.')) {
      return 'FILE';
    }

    return name.split('.').last.toUpperCase();
  }

  String get _fileInfo {
    final bytes = message.fileSizeBytes;

    if (bytes == null || bytes <= 0) {
      return _extension;
    }

    if (bytes < 1024 * 1024) {
      return '${(bytes / 1024).toStringAsFixed(0)} KB • $_extension';
    }

    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB • $_extension';
  }

  bool get _isPdf => _extension == 'PDF';

  Future<void> _download(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final name =
          (message.fileName?.trim().isNotEmpty == true
                  ? message.fileName!
                  : 'document')
              .replaceAll(RegExp(r'[^a-zA-Z0-9._-]'), '_');
      final location = await getSaveLocation(
        suggestedName: name,
        confirmButtonText: 'Download',
      );
      if (location == null) return;

      final url = await repository.createSignedMediaUrl(message.mediaUrl!);
      final request = await HttpClient().getUrl(Uri.parse(url));
      request.headers.set(HttpHeaders.acceptHeader, '*/*');
      final response = await request.close();
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw HttpException(
          'Download failed with status ${response.statusCode}',
        );
      }
      final bytes = await consolidateHttpClientResponseBytes(response);
      if (bytes.isEmpty) {
        throw const FileSystemException('Downloaded document is empty');
      }
      await File(location.path).writeAsBytes(bytes, flush: true);
      if (context.mounted) {
        messenger.showSnackBar(
          SnackBar(content: Text('$name downloaded successfully.')),
        );
      }
    } catch (_) {
      if (context.mounted) {
        messenger.showSnackBar(
          const SnackBar(content: Text('Could not download this document.')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: mine
          ? Colors.white.withValues(alpha: 0.12)
          : const Color(0xFFF3F5F7),
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () async {
          final url = await repository.createSignedMediaUrl(message.mediaUrl!);

          await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
        },
        child: Container(
          width: 245,
          padding: const EdgeInsets.all(10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(
                width: 48,
                height: 52,
                decoration: BoxDecoration(
                  color: mine
                      ? Colors.white.withValues(alpha: 0.15)
                      : Colors.white,
                  borderRadius: BorderRadius.circular(11),
                ),
                alignment: Alignment.center,
                child: AppIcon(
                  _isPdf
                      ? Icons.picture_as_pdf_outlined
                      : Icons.description_outlined,
                  size: 24,
                  color: mine
                      ? Colors.white
                      : _isPdf
                      ? const Color(0xFFD92D20)
                      : AppColors.brand,
                ),
              ),

              const SizedBox(width: 11),

              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      message.fileName ?? 'Document',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.outfit(
                        fontSize: 12.8,
                        height: 1.25,
                        fontWeight: FontWeight.w500,

                        // YOUR DOCUMENT NAME IS WHITE
                        color: mine ? Colors.white : AppColors.textPrimary,
                      ),
                    ),

                    const SizedBox(height: 6),

                    Text(
                      _fileInfo,
                      style: GoogleFonts.outfit(
                        fontSize: 9.7,
                        color: mine ? Colors.white70 : AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(width: 10),

              Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: () => _download(context),
                  customBorder: const CircleBorder(),
                  child: Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: mine
                          ? Colors.white.withValues(alpha: 0.14)
                          : Colors.white,
                      shape: BoxShape.circle,
                    ),
                    alignment: Alignment.center,
                    child: AppIcon(
                      Icons.download_rounded,
                      size: 18,
                      color: mine ? Colors.white : AppColors.textSecondary,
                    ),
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

// =============================================================================
// VOICE PLAYER
// =============================================================================

class _VoicePlayer extends StatefulWidget {
  const _VoicePlayer({
    super.key,
    required this.path,
    required this.repository,
    required this.mine,
    this.localFile = false,
    this.duration,
  });

  final String path;
  final ChatRepository repository;
  final int? duration;
  final bool mine;
  final bool localFile;

  @override
  State<_VoicePlayer> createState() => _VoicePlayerState();
}

class _VoicePlayerState extends State<_VoicePlayer> {
  final AudioPlayer _player = AudioPlayer();
  StreamSubscription<PlayerState>? _playerStateSubscription;

  bool _loading = false;
  bool _resettingAfterCompletion = false;

  @override
  void initState() {
    super.initState();
    _playerStateSubscription = _player.playerStateStream.listen((state) {
      if (state.processingState == ProcessingState.completed) {
        unawaited(_resetCompletedPlayback());
      }
    });
  }

  Future<void> _resetCompletedPlayback() async {
    if (_resettingAfterCompletion) return;
    _resettingAfterCompletion = true;
    try {
      await _player.pause();
      await _player.seek(Duration.zero);
    } catch (_) {
      // The player may already be disposing while the chat is closing.
    } finally {
      _resettingAfterCompletion = false;
    }
  }

  Future<void> _toggle() async {
    try {
      if (_player.processingState == ProcessingState.completed) {
        await _player.pause();
        await _player.seek(Duration.zero);
      }

      if (_player.playing) {
        await _player.pause();
        return;
      }

      if (_player.audioSource == null) {
        setState(() {
          _loading = true;
        });

        if (widget.localFile) {
          await _player.setFilePath(widget.path);
        } else {
          final url = await widget.repository.createSignedMediaUrl(widget.path);
          await _player.setUrl(url);
        }

        if (mounted) {
          setState(() {
            _loading = false;
          });
        }
      }

      await _player.play();
    } catch (_) {
      if (mounted) {
        setState(() {
          _loading = false;
        });
      }
    }
  }

  String _formatDuration(Duration duration) {
    final totalSeconds = duration.inSeconds;

    final minutes = totalSeconds ~/ 60;

    final seconds = totalSeconds % 60;

    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }

  Duration get _fallbackDuration {
    return Duration(seconds: widget.duration ?? 0);
  }

  @override
  void dispose() {
    _playerStateSubscription?.cancel();
    _player.dispose();

    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final primaryColor = widget.mine ? Colors.white : AppColors.brand;

    final secondaryColor = widget.mine
        ? Colors.white70
        : AppColors.textSecondary;

    final inactiveColor = widget.mine
        ? Colors.white.withValues(alpha: 0.28)
        : const Color(0xFFD8DCE1);

    return SizedBox(
      width: 225,
      child: StreamBuilder<PlayerState>(
        stream: _player.playerStateStream,
        builder: (context, playerSnapshot) {
          final state = playerSnapshot.data;
          final playing =
              state?.playing == true &&
              state?.processingState != ProcessingState.completed;

          return Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // -------------------------------------------------------------
              // PLAY BUTTON
              // -------------------------------------------------------------
              Material(
                color: widget.mine
                    ? Colors.white.withValues(alpha: 0.16)
                    : AppColors.brand.withValues(alpha: 0.10),
                shape: const CircleBorder(),
                child: InkWell(
                  onTap: _loading ? null : _toggle,
                  customBorder: const CircleBorder(),
                  child: SizedBox(
                    width: 44,
                    height: 44,
                    child: _loading
                        ? Padding(
                            padding: const EdgeInsets.all(12),
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: primaryColor,
                            ),
                          )
                        : AppIcon(
                            playing
                                ? Icons.pause_rounded
                                : Icons.play_arrow_rounded,
                            size: 25,
                            color: primaryColor,
                          ),
                  ),
                ),
              ),

              const SizedBox(width: 11),

              // -------------------------------------------------------------
              // AUDIO DETAILS
              // -------------------------------------------------------------
              Expanded(
                child: StreamBuilder<Duration>(
                  stream: _player.positionStream,
                  builder: (context, positionSnapshot) {
                    final position = positionSnapshot.data ?? Duration.zero;

                    final playerDuration = _player.duration;

                    final total = playerDuration ?? _fallbackDuration;

                    final totalMs = total.inMilliseconds <= 0
                        ? 1
                        : total.inMilliseconds;

                    final progress = (position.inMilliseconds / totalMs).clamp(
                      0.0,
                      1.0,
                    );

                    return Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // ---------------------------------------------------
                        // WAVEFORM
                        // ---------------------------------------------------
                        SizedBox(
                          height: 25,
                          child: LayoutBuilder(
                            builder: (context, constraints) {
                              const barWidth = 2.2;
                              const spacing = 2.4;

                              final count =
                                  (constraints.maxWidth / (barWidth + spacing))
                                      .floor();

                              return Row(
                                crossAxisAlignment: CrossAxisAlignment.center,
                                children: List.generate(count, (index) {
                                  final fraction = count <= 1
                                      ? 0.0
                                      : index / (count - 1);

                                  final active = fraction <= progress;

                                  final pattern = [
                                    7.0,
                                    12.0,
                                    18.0,
                                    10.0,
                                    15.0,
                                    21.0,
                                    13.0,
                                    8.0,
                                    17.0,
                                    11.0,
                                    20.0,
                                    14.0,
                                  ];

                                  final height =
                                      pattern[index % pattern.length];

                                  return Container(
                                    width: barWidth,
                                    height: height,
                                    margin: const EdgeInsets.only(
                                      right: spacing,
                                    ),
                                    decoration: BoxDecoration(
                                      color: active
                                          ? primaryColor
                                          : inactiveColor,
                                      borderRadius: BorderRadius.circular(20),
                                    ),
                                  );
                                }),
                              );
                            },
                          ),
                        ),

                        const SizedBox(height: 4),

                        // ---------------------------------------------------
                        // TIME
                        // ---------------------------------------------------
                        Row(
                          children: [
                            Text(
                              position > Duration.zero
                                  ? _formatDuration(position)
                                  : _formatDuration(total),
                              style: GoogleFonts.outfit(
                                fontSize: 9.7,
                                height: 1,
                                fontWeight: FontWeight.w400,
                                color: secondaryColor,
                              ),
                            ),

                            const Spacer(),

                            AppIcon(
                              Icons.mic_rounded,
                              size: 12,
                              color: secondaryColor,
                            ),
                          ],
                        ),
                      ],
                    );
                  },
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

// =============================================================================
// REPLY BUBBLE
// =============================================================================
class _ReplyBubble extends StatelessWidget {
  const _ReplyBubble({required this.message, required this.mine, this.onTap});

  final ChatMessageModel? message;
  final bool mine;
  final VoidCallback? onTap;

  String get _text {
    if (message == null) {
      return 'Message';
    }

    if (message!.text?.trim().isNotEmpty == true) {
      return message!.text!;
    }

    if (message!.type == MessageType.image) {
      return 'Photo';
    }

    if (message!.type == MessageType.voice) {
      return 'Voice message';
    }

    if (message!.fileName?.trim().isNotEmpty == true) {
      return message!.fileName!;
    }

    return 'Document';
  }

  IconData get _icon {
    if (message?.type == MessageType.image) {
      return Icons.image_outlined;
    }

    if (message?.type == MessageType.voice) {
      return Icons.mic_none_rounded;
    }

    if (message?.type == MessageType.file) {
      return Icons.description_outlined;
    }

    return Icons.reply_rounded;
  }

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        constraints: const BoxConstraints(minWidth: 130),
        margin: const EdgeInsets.only(bottom: 7),
        padding: const EdgeInsets.fromLTRB(9, 7, 10, 7),
        decoration: BoxDecoration(
          color: mine
              ? Colors.white.withValues(alpha: 0.13)
              : Colors.black.withValues(alpha: 0.045),
          borderRadius: BorderRadius.circular(8),
          border: Border(
            left: BorderSide(
              width: 3,
              color: mine
                  ? Colors.white.withValues(alpha: 0.85)
                  : AppColors.brand,
            ),
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            AppIcon(
              _icon,
              size: 14,
              color: mine ? Colors.white70 : AppColors.textSecondary,
            ),
            const SizedBox(width: 7),
            Expanded(
              child: Text(
                _text,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.outfit(
                  fontSize: 11,
                  height: 1.3,
                  fontWeight: FontWeight.w400,
                  color: mine ? Colors.white : AppColors.textSecondary,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// =============================================================================
// DELETED
// =============================================================================
class _DeletedMessage extends StatelessWidget {
  const _DeletedMessage({required this.mine});

  final bool mine;

  @override
  Widget build(BuildContext context) {
    final color = mine ? Colors.white70 : AppColors.textPrimary;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        AppIcon(Icons.block_rounded, size: 14, color: color),

        const SizedBox(width: 6),

        Text(
          'This message was deleted',
          style: GoogleFonts.outfit(
            fontSize: 12,
            fontStyle: FontStyle.italic,
            color: color,
          ),
        ),
      ],
    );
  }
}

// =============================================================================
// MESSAGE META
// =============================================================================
class _MessageMeta extends StatelessWidget {
  const _MessageMeta({
    required this.message,
    required this.mine,
    this.onMedia = false,
    this.onRetry,
  });

  final ChatMessageModel message;
  final bool mine;
  final bool onMedia;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final metaColor = onMedia
        ? Colors.white
        : mine
        ? Colors.white70
        : AppColors.textSecondary;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          DateFormat('h:mm a').format(message.createdAt.toLocal()),
          style: GoogleFonts.outfit(
            fontSize: 8.8,
            height: 1,
            fontWeight: FontWeight.w400,
            color: metaColor,
          ),
        ),

        if (mine) ...[
          const SizedBox(width: 3),

          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: message.status == MessageStatus.failed ? onRetry : null,
            child: Padding(
              padding: const EdgeInsets.all(2),
              child: AppIcon(
                message.status == MessageStatus.sending
                    ? Icons.access_time_rounded
                    : message.status == MessageStatus.failed
                    ? Icons.error_outline_rounded
                    : message.status == MessageStatus.read ||
                          message.status == MessageStatus.delivered
                    ? Icons.done_all_rounded
                    : Icons.done_rounded,
                size: message.status == MessageStatus.failed ? 15 : 13,
                color: message.status == MessageStatus.failed
                    ? const Color(0xFFFFD2CC)
                    : onMedia
                    ? Colors.white
                    : message.status == MessageStatus.read
                    ? Colors.white
                    : Colors.white70,
              ),
            ),
          ),
        ],
      ],
    );
  }
}
// =============================================================================
// MESSAGE ACTION
// =============================================================================

class _MessageAction extends StatelessWidget {
  const _MessageAction({
    required this.icon,
    required this.title,
    required this.onTap,
    this.destructive = false,
  });

  final IconData icon;
  final String title;
  final VoidCallback onTap;

  final bool destructive;

  @override
  Widget build(BuildContext context) {
    final color = destructive ? const Color(0xFFB42318) : AppColors.textPrimary;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(13),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 13),
          child: Row(
            children: [
              AppIcon(icon, size: 20, color: color),

              const SizedBox(width: 13),

              Text(
                title,
                style: GoogleFonts.outfit(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: color,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// =============================================================================
// COMPOSER
// =============================================================================

class _Composer extends StatelessWidget {
  const _Composer({
    required this.controller,
    required this.reply,
    required this.sending,
    required this.recording,
    required this.recordingPaused,
    required this.recordingElapsed,
    required this.waveform,
    required this.onChanged,
    required this.onCancelReply,
    required this.onAttach,
    required this.onRecordStart,
    required this.onRecordSend,
    required this.onRecordCancel,
    required this.onRecordTogglePause,
    required this.onSend,
  });

  final TextEditingController controller;
  final ChatMessageModel? reply;

  final bool sending;
  final bool recording;
  final bool recordingPaused;
  final Duration recordingElapsed;
  final List<double> waveform;
  final ValueChanged<String> onChanged;

  final VoidCallback onCancelReply;
  final VoidCallback onAttach;
  final VoidCallback onRecordStart;
  final VoidCallback onRecordSend;
  final VoidCallback onRecordCancel;
  final VoidCallback onRecordTogglePause;
  final VoidCallback onSend;

  String get _replyText {
    if (reply == null) {
      return '';
    }

    if (reply!.text?.trim().isNotEmpty == true) {
      return reply!.text!;
    }

    if (reply!.type == MessageType.image) {
      return 'Photo';
    }

    if (reply!.type == MessageType.voice) {
      return 'Voice message';
    }

    return reply!.fileName ?? 'Document';
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Container(
        color: const Color(0xFFF0EEEA),
        padding: const EdgeInsets.fromLTRB(7, 6, 13, 7),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // -----------------------------------------------------------------
            // REPLY PREVIEW
            // -----------------------------------------------------------------
            if (reply != null && !recording)
              Container(
                margin: const EdgeInsets.fromLTRB(4, 0, 4, 6),
                padding: const EdgeInsets.fromLTRB(10, 7, 6, 7),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(10),
                  border: Border(
                    left: BorderSide(color: AppColors.brand, width: 3),
                  ),
                ),
                child: Row(
                  children: [
                    AppIcon(
                      Icons.reply_rounded,
                      size: 15,
                      color: AppColors.brand,
                    ),

                    const SizedBox(width: 7),

                    Expanded(
                      child: Text(
                        _replyText,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.outfit(
                          fontSize: 11,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ),

                    IconButton(
                      visualDensity: VisualDensity.compact,
                      onPressed: onCancelReply,
                      icon: const AppIcon(Icons.close_rounded, size: 17),
                    ),
                  ],
                ),
              ),

            // -----------------------------------------------------------------
            // RECORDING PANEL OR NORMAL INPUT ROW
            // -----------------------------------------------------------------
            if (recording)
              _VoiceRecordingPanel(
                elapsed: recordingElapsed,
                paused: recordingPaused,
                waveform: waveform,
                onDelete: onRecordCancel,
                onTogglePause: onRecordTogglePause,
                onSend: onRecordSend,
              )
            else
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  // ---------------------------------------------------------
                  // MESSAGE FIELD
                  // ---------------------------------------------------------
                  Expanded(
                    child: Container(
                      constraints: const BoxConstraints(minHeight: 47),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(24),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Expanded(
                            child: TextField(
                              controller: controller,
                              onChanged: onChanged,
                              minLines: 1,
                              maxLines: 5,
                              textCapitalization: TextCapitalization.sentences,
                              keyboardType: TextInputType.multiline,
                              style: GoogleFonts.outfit(
                                fontSize: 14,
                                height: 1.35,
                                color: AppColors.textPrimary,
                              ),
                              decoration: InputDecoration(
                                hintText: 'Message',
                                hintStyle: GoogleFonts.outfit(
                                  fontSize: 14,
                                  color: AppColors.textSecondary,
                                ),
                                border: InputBorder.none,
                                isDense: true,
                                contentPadding: const EdgeInsets.fromLTRB(
                                  16,
                                  14,
                                  4,
                                  13,
                                ),
                              ),
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.only(right: 3, bottom: 3),
                            child: IconButton(
                              tooltip: 'Share a file',
                              onPressed: sending ? null : onAttach,
                              visualDensity: VisualDensity.compact,
                              icon: AppIcon(
                                Icons.attach_file_rounded,
                                size: 22,
                                color: AppColors.textSecondary,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(width: 6),

                  // ---------------------------------------------------------
                  // SEND / MIC
                  // ---------------------------------------------------------
                  ValueListenableBuilder<TextEditingValue>(
                    valueListenable: controller,
                    builder: (context, value, _) {
                      final hasText = value.text.trim().isNotEmpty;

                      if (hasText) {
                        return _RoundComposerButton(
                          icon: Icons.send_rounded,
                          onTap: onSend,
                        );
                      }
                      // Single tap starts recording directly in the
                      // "locked" panel state — matches WhatsApp's
                      // current mic UI (tap or drag both land here).
                      return _RoundComposerButton(
                        icon: Icons.mic_rounded,
                        onTap: onRecordStart,
                      );
                    },
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

// =============================================================================
// VOICE RECORDING PANEL (WhatsApp-style)
// =============================================================================

class _VoiceRecordingPanel extends StatefulWidget {
  const _VoiceRecordingPanel({
    required this.elapsed,
    required this.paused,
    required this.waveform,
    required this.onDelete,
    required this.onTogglePause,
    required this.onSend,
  });

  final Duration elapsed;
  final bool paused;
  final List<double> waveform;
  final VoidCallback onDelete;
  final VoidCallback onTogglePause;
  final VoidCallback onSend;

  @override
  State<_VoiceRecordingPanel> createState() => _VoiceRecordingPanelState();
}

class _VoiceRecordingPanelState extends State<_VoiceRecordingPanel> {
  String get _time {
    final minutes = widget.elapsed.inMinutes
        .remainder(60)
        .toString()
        .padLeft(2, '0');
    final seconds = widget.elapsed.inSeconds
        .remainder(60)
        .toString()
        .padLeft(2, '0');
    return '$minutes:$seconds';
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // -----------------------------------------------------------
          // TOP ROW: timer + animated waveform
          // -----------------------------------------------------------
          Row(
            children: [
              Container(
                width: 8,
                height: 8,
                margin: const EdgeInsets.only(right: 6),
                decoration: BoxDecoration(
                  color: widget.paused
                      ? const Color(0xFFD8DCE1)
                      : const Color(0xFFD92D20),
                  shape: BoxShape.circle,
                ),
              ),
              Text(
                _time,
                style: GoogleFonts.outfit(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: widget.paused
                      ? AppColors.textSecondary
                      : const Color(0xFFD92D20),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: SizedBox(
                  height: 24,
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      const barWidth = 2.4;
                      const spacing = 2.6;
                      final count =
                          (constraints.maxWidth / (barWidth + spacing)).floor();

                      return Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: List.generate(count, (index) {
                          final sourceIndex = widget.waveform.isEmpty
                              ? 0
                              : (index * widget.waveform.length / count)
                                    .floor()
                                    .clamp(0, widget.waveform.length - 1);
                          final level = widget.waveform.isEmpty
                              ? .08
                              : widget.waveform[sourceIndex];
                          final height = 4.0 + (level * 18.0);

                          return Container(
                            width: barWidth,
                            height: height,
                            margin: const EdgeInsets.only(right: spacing),
                            decoration: BoxDecoration(
                              color: widget.paused
                                  ? const Color(0xFFD8DCE1)
                                  : AppColors.brand,
                              borderRadius: BorderRadius.circular(20),
                            ),
                          );
                        }),
                      );
                    },
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 9),

          // -----------------------------------------------------------
          // BOTTOM ROW: delete | pause/resume pill | send
          // -----------------------------------------------------------
          Row(
            children: [
              Material(
                color: const Color(0xFFFDEAEA),
                shape: const CircleBorder(),
                child: InkWell(
                  customBorder: const CircleBorder(),
                  onTap: widget.onDelete,
                  child: const SizedBox(
                    width: 40,
                    height: 40,
                    child: AppIcon(
                      Icons.delete_outline_rounded,
                      size: 20,
                      color: Color(0xFFD92D20),
                    ),
                  ),
                ),
              ),

              const SizedBox(width: 8),

              Expanded(
                child: Material(
                  color: const Color(0xFFF2F4F6),
                  borderRadius: BorderRadius.circular(20),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(20),
                    onTap: widget.onTogglePause,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 9),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          AppIcon(
                            widget.paused
                                ? Icons.play_arrow_rounded
                                : Icons.pause_rounded,
                            size: 18,
                            color: AppColors.textPrimary,
                          ),
                          const SizedBox(width: 5),
                          Text(
                            widget.paused ? 'Resume' : 'Pause',
                            style: GoogleFonts.outfit(
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                              color: AppColors.textPrimary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),

              const SizedBox(width: 8),

              Material(
                color: AppColors.brand,
                shape: const CircleBorder(),
                child: InkWell(
                  customBorder: const CircleBorder(),
                  onTap: widget.onSend,
                  child: const SizedBox(
                    width: 40,
                    height: 40,
                    child: AppIcon(
                      Icons.send_rounded,
                      size: 18,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 4),
        ],
      ),
    );
  }
}

class _RoundComposerButton extends StatelessWidget {
  const _RoundComposerButton({
    required this.icon,
    this.onTap,
    this.busy = false,
  });

  final IconData icon;
  final VoidCallback? onTap;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.brand,
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: busy ? null : onTap,
        child: SizedBox(
          width: 47,
          height: 47,
          child: busy
              ? const Padding(
                  padding: EdgeInsets.all(14),
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : AppIcon(icon, size: 22, color: Colors.white),
        ),
      ),
    );
  }
}

// =============================================================================
// ATTACHMENT SHEET
// =============================================================================

class _AttachmentSheet extends StatelessWidget {
  const _AttachmentSheet({
    required this.onCamera,
    required this.onGallery,
    required this.onDocument,
  });

  final VoidCallback onCamera;
  final VoidCallback onGallery;
  final VoidCallback onDocument;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: const EdgeInsets.fromLTRB(18, 10, 18, 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: const Color(0xFFD7DADF),
                borderRadius: BorderRadius.circular(20),
              ),
            ),
          ),

          const SizedBox(height: 18),

          Text(
            'Share in chat',
            style: GoogleFonts.outfit(
              fontSize: 16,
              fontWeight: FontWeight.w500,
              color: AppColors.textPrimary,
            ),
          ),

          const SizedBox(height: 4),

          Text(
            'Choose what you would like to send',
            style: GoogleFonts.outfit(
              fontSize: 11.5,
              color: AppColors.textSecondary,
            ),
          ),

          const SizedBox(height: 18),

          Row(
            children: [
              Expanded(
                child: _AttachmentChoice(
                  icon: Icons.photo_camera_outlined,
                  label: 'Camera',
                  onTap: onCamera,
                ),
              ),

              const SizedBox(width: 10),

              Expanded(
                child: _AttachmentChoice(
                  icon: Icons.photo_library_outlined,
                  label: 'Gallery',
                  onTap: onGallery,
                ),
              ),

              const SizedBox(width: 10),

              Expanded(
                child: _AttachmentChoice(
                  icon: Icons.description_outlined,
                  label: 'Document',
                  onTap: onDocument,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _AttachmentChoice extends StatelessWidget {
  const _AttachmentChoice({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xFFF6F7F9),
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: AppColors.brand.withValues(alpha: 0.08),
                  shape: BoxShape.circle,
                ),
                child: AppIcon(icon, size: 20, color: AppColors.brand),
              ),

              const SizedBox(height: 9),

              Text(
                label,
                style: GoogleFonts.outfit(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w500,
                  color: AppColors.textPrimary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// =============================================================================
// EMPTY CHAT
// =============================================================================

class _EmptyChat extends StatelessWidget {
  const _EmptyChat({required this.peerName, this.connected = false});

  final String peerName;
  final bool connected;

  String get _doctorNameWithoutTitle => peerName
      .trim()
      .replaceFirst(RegExp(r'^dr\.?\s+', caseSensitive: false), '')
      .trim();

  @override
  Widget build(BuildContext context) {
    if (connected) {
      return Column(
        children: [
          _DateDivider(date: DateTime.now()),
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final compact = constraints.maxHeight < 280;
                final verticalPadding = compact ? 8.0 : 0.0;
                final minimumHeight = constraints.maxHeight > verticalPadding * 2
                    ? constraints.maxHeight - verticalPadding * 2
                    : 0.0;
                final outerSize = compact ? 88.0 : 116.0;
                final innerSize = compact ? 62.0 : 80.0;

                return SingleChildScrollView(
                  primary: false,
                  keyboardDismissBehavior:
                      ScrollViewKeyboardDismissBehavior.onDrag,
                  padding: EdgeInsets.symmetric(
                    horizontal: 32,
                    vertical: verticalPadding,
                  ),
                  child: ConstrainedBox(
                    constraints: BoxConstraints(minHeight: minimumHeight),
                    child: Center(
                      child: Padding(
                        padding: EdgeInsets.only(bottom: compact ? 0 : 28),
                        child: Semantics(
                          label: 'Connected with Dr $_doctorNameWithoutTitle',
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(
                                width: outerSize,
                                height: outerSize,
                                decoration: BoxDecoration(
                                  color: AppColors.brand.withValues(alpha: 0.07),
                                  shape: BoxShape.circle,
                                ),
                                alignment: Alignment.center,
                                child: Stack(
                                  clipBehavior: Clip.none,
                                  children: [
                                    Container(
                                      width: innerSize,
                                      height: innerSize,
                                      decoration: BoxDecoration(
                                        color: AppColors.brand,
                                        shape: BoxShape.circle,
                                        boxShadow: [
                                          BoxShadow(
                                            color: AppColors.brand.withValues(
                                              alpha: 0.18,
                                            ),
                                            blurRadius: compact ? 12 : 16,
                                            offset: Offset(0, compact ? 4 : 6),
                                          ),
                                        ],
                                      ),
                                      alignment: Alignment.center,
                                      child: Icon(
                                        Icons.chat_bubble_rounded,
                                        size: compact ? 25 : 31,
                                        color: Colors.white,
                                      ),
                                    ),
                                    Positioned(
                                      right: -2,
                                      bottom: -2,
                                      child: Container(
                                        width: compact ? 22 : 25,
                                        height: compact ? 22 : 25,
                                        padding: const EdgeInsets.all(3),
                                        decoration: const BoxDecoration(
                                          color: Colors.white,
                                          shape: BoxShape.circle,
                                        ),
                                        child: Container(
                                          decoration: const BoxDecoration(
                                            color: Color(0xFF18A957),
                                            shape: BoxShape.circle,
                                          ),
                                          alignment: Alignment.center,
                                          child: Icon(
                                            Icons.check_rounded,
                                            size: compact ? 11 : 13,
                                            color: Colors.white,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              SizedBox(height: compact ? 14 : 22),
                              Text(
                                "You're connected",
                                textAlign: TextAlign.center,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: GoogleFonts.outfit(
                                  fontSize: compact ? 16 : 18,
                                  height: 1.2,
                                  fontWeight: FontWeight.w500,
                                  color: AppColors.textPrimary,
                                ),
                              ),
                              SizedBox(height: compact ? 5 : 8),
                              Text(
                                'Message Dr $_doctorNameWithoutTitle while you wait',
                                textAlign: TextAlign.center,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: GoogleFonts.outfit(
                                  fontSize: compact ? 11.5 : 12.5,
                                  height: 1.35,
                                  fontWeight: FontWeight.w400,
                                  color: AppColors.textSecondary,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      );
    }

    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 42),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 66,
              height: 66,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.9),
                shape: BoxShape.circle,
              ),
              child: AppIcon(
                Icons.chat_bubble_outline_rounded,
                size: 26,
                color: AppColors.brand,
              ),
            ),

            const SizedBox(height: 17),

            Text(
              'Start the conversation',
              textAlign: TextAlign.center,
              style: GoogleFonts.outfit(
                fontSize: 16,
                fontWeight: FontWeight.w500,
                color: AppColors.textPrimary,
              ),
            ),

            const SizedBox(height: 7),

            Text(
              'Share symptoms, reports or questions with $peerName here.',
              textAlign: TextAlign.center,
              style: GoogleFonts.outfit(
                fontSize: 12.3,
                height: 1.5,
                color: AppColors.textSecondary,
              ),
            ),

            const SizedBox(height: 13),

            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                AppIcon(
                  Icons.lock_outline_rounded,
                  size: 13,
                  color: AppColors.textSecondary,
                ),

                const SizedBox(width: 5),

                Text(
                  'Private consultation chat',
                  style: GoogleFonts.outfit(
                    fontSize: 10.3,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// =============================================================================
// WAITING TO START
// =============================================================================

class _PatientAppointmentStatusBar extends StatelessWidget {
  const _PatientAppointmentStatusBar({
    required this.session,
    required this.doctorName,
    required this.cancelling,
    required this.onCancel,
  });

  final ConsultationSessionModel session;
  final String doctorName;
  final bool cancelling;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    if (session.bookingStatus == 'accepted' &&
        !session.isInProgress &&
        !session.isRequestPending) {
      return Container(
        color: Colors.white,
        padding: const EdgeInsets.fromLTRB(14, 8, 12, 7),
        child: Container(
          constraints: const BoxConstraints(minHeight: 62),
          padding: const EdgeInsets.only(left: 11, right: 5),
          decoration: BoxDecoration(
            color: AppColors.brand.withValues(alpha: 0.055),
            borderRadius: BorderRadius.circular(13),
          ),
          child: Row(
            children: [
              Container(
                width: 30,
                height: 30,
                decoration: const BoxDecoration(
                  color: Colors.white,
                  shape: BoxShape.circle,
                ),
                alignment: Alignment.center,
                child: const AppIcon(
                  Icons.schedule_rounded,
                  size: 18,
                  color: AppColors.brand,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Appointment accepted',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.outfit(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w500,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '$doctorName will start the consultation soon.',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.outfit(
                        fontSize: 10.5,
                        height: 1.3,
                        fontWeight: FontWeight.w400,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              SizedBox(
                height: 38,
                child: TextButton(
                  onPressed: cancelling ? null : onCancel,
                  style: TextButton.styleFrom(
                    foregroundColor: AppColors.textSecondary,
                    disabledForegroundColor: AppColors.textSecondary,
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    minimumSize: const Size(48, 38),
                  ),
                  child: cancelling
                      ? const SizedBox.square(
                          dimension: 14,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Text(
                          'Cancel',
                          style: GoogleFonts.outfit(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    final status = _status;
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(12, 9, 12, 8),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
        decoration: BoxDecoration(
          color: status.background,
          borderRadius: BorderRadius.circular(13),
        ),
        child: Row(
          children: [
            Container(
              width: 35,
              height: 35,
              decoration: const BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle,
              ),
              alignment: Alignment.center,
              child: AppIcon(status.icon, size: 18, color: status.color),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    status.title,
                    style: GoogleFonts.outfit(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w500,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    status.message,
                    style: GoogleFonts.outfit(
                      fontSize: 10.5,
                      height: 1.35,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            if (session.bookingStatus == 'accepted') ...[
              const SizedBox(width: 8),
              SizedBox(
                height: 34,
                child: FilledButton(
                  onPressed: cancelling ? null : onCancel,
                  style: FilledButton.styleFrom(
                    elevation: 0,
                    backgroundColor: Colors.white,
                    disabledBackgroundColor: Colors.white,
                    foregroundColor: AppColors.textPrimary,
                    padding: const EdgeInsets.symmetric(horizontal: 11),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(9),
                    ),
                  ),
                  child: cancelling
                      ? const SizedBox.square(
                          dimension: 14,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Text(
                          'Cancel',
                          style: GoogleFonts.outfit(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  _PatientStatusData get _status {
    if (session.bookingStatus == 'completed') {
      return const _PatientStatusData(
        title: 'Appointment completed',
        message: 'Your consultation has been completed.',
        icon: Icons.check_circle_outline_rounded,
        color: Color(0xFF16834B),
        background: Color(0xFFEAF7EF),
      );
    }
    if (session.bookingStatus == 'cancelled') {
      return const _PatientStatusData(
        title: 'Appointment cancelled',
        message: 'This appointment is no longer active.',
        icon: Icons.event_busy_outlined,
        color: Color(0xFF667085),
        background: Color(0xFFF2F4F6),
      );
    }
    if (session.isInProgress) {
      return _PatientStatusData(
        title: 'Consultation active',
        message: 'Your consultation with $doctorName is now in progress.',
        icon: Icons.medical_services_outlined,
        color: AppColors.brand,
        background: AppColors.brand.withValues(alpha: 0.055),
      );
    }
    if (session.isRequestPending) {
      return _PatientStatusData(
        title: 'Doctor is ready',
        message: '$doctorName requested to start your consultation.',
        icon: Icons.notifications_active_outlined,
        color: AppColors.brand,
        background: AppColors.brand.withValues(alpha: 0.055),
      );
    }
    if (session.bookingStatus == 'accepted') {
      return _PatientStatusData(
        title: 'Appointment accepted',
        message: 'Waiting for $doctorName to start the consultation.',
        icon: Icons.schedule_rounded,
        color: AppColors.brand,
        background: AppColors.brand.withValues(alpha: 0.055),
      );
    }
    return const _PatientStatusData(
      title: 'Appointment pending',
      message: 'Waiting for the doctor to accept your appointment.',
      icon: Icons.hourglass_top_rounded,
      color: Color(0xFF667085),
      background: Color(0xFFF2F4F6),
    );
  }
}

class _PatientStatusData {
  const _PatientStatusData({
    required this.title,
    required this.message,
    required this.icon,
    required this.color,
    required this.background,
  });

  final String title;
  final String message;
  final IconData icon;
  final Color color;
  final Color background;
}

class _SessionRequestBar extends StatelessWidget {
  const _SessionRequestBar({
    required this.pending,
    required this.busy,
    required this.onRequest,
  });

  final bool pending;
  final bool busy;
  final VoidCallback onRequest;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(12, 9, 12, 8),
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 10, 10, 10),
        decoration: BoxDecoration(
          color: AppColors.brand.withValues(alpha: 0.055),
          borderRadius: BorderRadius.circular(13),
        ),
        child: Row(
          children: [
            Container(
              width: 35,
              height: 35,
              decoration: const BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle,
              ),
              child: AppIcon(
                pending
                    ? Icons.schedule_rounded
                    : Icons.medical_services_outlined,
                size: 17,
                color: AppColors.brand,
              ),
            ),

            const SizedBox(width: 10),

            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    pending ? 'Start request sent' : 'Ready to start?',
                    style: GoogleFonts.outfit(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: AppColors.textPrimary,
                    ),
                  ),

                  const SizedBox(height: 2),

                  Text(
                    pending
                        ? 'Waiting for the patient to confirm.'
                        : 'Ask the patient to begin the consultation.',
                    style: GoogleFonts.outfit(
                      fontSize: 10.4,
                      height: 1.3,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),

            if (!pending) ...[
              const SizedBox(width: 8),

              SizedBox(
                height: 36,
                child: FilledButton(
                  onPressed: busy ? null : onRequest,
                  style: FilledButton.styleFrom(
                    elevation: 0,
                    backgroundColor: AppColors.brand,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(9),
                    ),
                  ),

                  child: busy
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : Text(
                          'Request',
                          style: GoogleFonts.outfit(
                            fontSize: 11,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// =============================================================================
// ACTIVE CONSULTATION
// =============================================================================
class _ActiveConsultationBar extends StatelessWidget {
  const _ActiveConsultationBar({
    required this.ending,
    required this.onEnd,
    required this.label,
    required this.endingLabel,
  });

  final bool ending;
  final VoidCallback onEnd;
  final String label;
  final String endingLabel;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      child: SizedBox(
        height: 46,
        width: double.infinity,
        child: TextButton.icon(
          onPressed: ending ? null : onEnd,
          style: TextButton.styleFrom(
            foregroundColor: const Color(0xFFB42318),
            backgroundColor: const Color(0xFFFFF1F0),
            disabledForegroundColor: const Color(
              0xFFB42318,
            ).withValues(alpha: 0.6),
            disabledBackgroundColor: const Color(0xFFFFF1F0),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
          ),
          icon: ending
              ? const SizedBox.square(
                  dimension: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Color(0xFFB42318),
                  ),
                )
              : const AppIcon(Icons.stop_circle_outlined, size: 20),
          label: Text(
            ending ? endingLabel : label,
            style: GoogleFonts.outfit(
              fontSize: 13,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ),
    );
  }
}
// =============================================================================
// MESSAGE LIMIT
// =============================================================================

class _MessageLimitNotice extends StatelessWidget {
  const _MessageLimitNotice({
    required this.isDoctor,
    required this.pending,
    required this.busy,
    required this.onStart,
  });

  final bool isDoctor;
  final bool pending;
  final bool busy;
  final VoidCallback onStart;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Container(
        color: Colors.white,
        padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: pending
                        ? AppColors.brand.withValues(alpha: 0.08)
                        : const Color(0xFFF2F4F6),
                    shape: BoxShape.circle,
                  ),
                  alignment: Alignment.center,
                  child: AppIcon(
                    pending
                        ? Icons.schedule_rounded
                        : Icons.info_outline_rounded,
                    size: 16,
                    color: pending ? AppColors.brand : AppColors.textSecondary,
                  ),
                ),

                const SizedBox(width: 10),

                Expanded(
                  child: Text(
                    _messageText,
                    style: GoogleFonts.outfit(
                      fontSize: 11.5,
                      height: 1.4,
                      fontWeight: pending ? FontWeight.w500 : FontWeight.w400,
                      color: pending
                          ? AppColors.textPrimary
                          : AppColors.textSecondary,
                    ),
                  ),
                ),
              ],
            ),

            // Only show request button before request is sent.
            if (isDoctor && !pending) ...[
              const SizedBox(height: 10),

              SizedBox(
                width: double.infinity,
                height: 42,
                child: FilledButton(
                  onPressed: busy ? null : onStart,
                  style: FilledButton.styleFrom(
                    elevation: 0,
                    backgroundColor: const Color(0xFFF2F4F6),
                    foregroundColor: AppColors.textPrimary,
                    disabledBackgroundColor: const Color(0xFFF2F4F6),
                    disabledForegroundColor: AppColors.textSecondary,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(11),
                    ),
                  ),
                  child: busy
                      ? SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: AppColors.textSecondary,
                          ),
                        )
                      : Text(
                          'Request consultation start',
                          style: GoogleFonts.outfit(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w500,
                            color: AppColors.textPrimary,
                          ),
                        ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  String get _messageText {
    if (isDoctor) {
      if (pending) {
        return 'Start request sent. Waiting for the patient to confirm.';
      }

      return 'Message limit reached. Start the consultation to continue.';
    }

    if (pending) {
      return 'The doctor is ready to start your consultation.';
    }

    return 'Message limit reached. The doctor needs to start the consultation to continue.';
  }
}

class _LimitedMessageCounter extends StatelessWidget {
  const _LimitedMessageCounter({
    required this.used,
    required this.total,
  });

  final int used;
  final int total;

  @override
  Widget build(BuildContext context) {
    final safeUsed = used.clamp(0, total);

    return Container(
      width: double.infinity,
      height: 52,
      color: Colors.transparent,
      padding: const EdgeInsets.fromLTRB(14, 0, 20, 6),
      // padding: const EdgeInsets.fromLTRB(left, top, right, bottom)
      child: Align(
        alignment: Alignment.centerRight,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
              color: const Color(0xFFE9EBEE),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.05),
                blurRadius: 10,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 12),
            child: Text(
              '$safeUsed/$total messages used',
              style: GoogleFonts.outfit(
                fontSize: 12,
                height: 1.05,
                fontWeight: FontWeight.w500,
                color: AppColors.textSecondary,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
// =============================================================================
// CLOSED CHAT
// =============================================================================

class _ClosedNotice extends StatelessWidget {
  const _ClosedNotice({this.message});

  final String? message;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Container(
        width: double.infinity,
        color: Colors.white,
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 14),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            AppIcon(
              Icons.lock_outline_rounded,
              size: 15,
              color: AppColors.textSecondary,
            ),

            const SizedBox(width: 7),

            Flexible(
              child: Text(
                message ??
                    'This consultation has ended. Messages are now read-only.',
                textAlign: TextAlign.center,
                style: GoogleFonts.outfit(
                  fontSize: 11.5,
                  color: AppColors.textSecondary,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// =============================================================================
// RECEIPT
// =============================================================================

class _ReceiptRow extends StatelessWidget {
  const _ReceiptRow({
    required this.label,
    required this.value,
    this.emphasized = false,
  });

  final String label;
  final String value;
  final bool emphasized;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Text(
            label,
            style: GoogleFonts.outfit(
              fontSize: 12,
              color: AppColors.textSecondary,
            ),
          ),
        ),

        const SizedBox(width: 14),

        Text(
          value,
          style: GoogleFonts.outfit(
            fontSize: emphasized ? 14 : 12.5,
            fontWeight: emphasized ? FontWeight.w500 : FontWeight.w500,
            color: emphasized ? const Color(0xFF16894A) : AppColors.textPrimary,
          ),
        ),
      ],
    );
  }
}

// =============================================================================
// LOADING
// =============================================================================

class _LoadingView extends StatelessWidget {
  const _LoadingView();

  @override
  Widget build(BuildContext context) {
    return const AppListShimmer(
      itemCount: 6,
      showAvatar: false,
      horizontalPadding: 12,
    );
  }
}

// =============================================================================
// ERROR
// =============================================================================

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.message, required this.retry});

  final String message;
  final VoidCallback retry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 36),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 60,
              height: 60,
              decoration: const BoxDecoration(
                color: Color(0xFFF0F2F4),
                shape: BoxShape.circle,
              ),
              alignment: Alignment.center,
              child: AppIcon(
                Icons.chat_bubble_outline_rounded,
                size: 24,
                color: AppColors.textSecondary,
              ),
            ),

            const SizedBox(height: 16),

            Text(
              'Unable to open chat',
              textAlign: TextAlign.center,
              style: GoogleFonts.outfit(
                fontSize: 16,
                fontWeight: FontWeight.w500,
                color: AppColors.textPrimary,
              ),
            ),

            const SizedBox(height: 7),

            Text(
              message,
              textAlign: TextAlign.center,
              style: GoogleFonts.outfit(
                fontSize: 12.5,
                height: 1.5,
                color: AppColors.textSecondary,
              ),
            ),

            const SizedBox(height: 17),

            TextButton(
              onPressed: retry,
              child: Text(
                'Try again',
                style: GoogleFonts.outfit(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: AppColors.brand,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
