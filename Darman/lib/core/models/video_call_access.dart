class VideoCallAccess {
  const VideoCallAccess({required this.appId, required this.channelName, required this.token, required this.uid, required this.expiresAt});
  final String appId;
  final String channelName;
  final String token;
  final int uid;
  final DateTime expiresAt;
  factory VideoCallAccess.fromMap(Map<String, dynamic> map) => VideoCallAccess(
    appId: map['app_id'] as String,
    channelName: map['channel_name'] as String,
    token: map['token'] as String,
    uid: (map['uid'] as num).toInt(),
    expiresAt: DateTime.parse(map['expires_at'].toString()).toUtc(),
  );
}
