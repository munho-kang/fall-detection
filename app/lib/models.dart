// 서버가 내려주는 데이터 모델 — 낙상 이벤트·방·보호자 프로필

class FallEvent {
  final int id;
  final String roomName;
  final int roomNumber;
  final DateTime occurredAt;
  final DateTime createdAt;
  final double confidence;
  final DateTime? acknowledgedAt;
  final DateTime? reported119At;
  final DateTime? voiceOkAt;

  const FallEvent({
    required this.id,
    required this.roomName,
    required this.roomNumber,
    required this.occurredAt,
    required this.createdAt,
    required this.confidence,
    this.acknowledgedAt,
    this.reported119At,
    this.voiceOkAt,
  });

  factory FallEvent.fromJson(Map<String, dynamic> json) => FallEvent(
        id: json['id'] as int,
        roomName: json['room_name'] as String,
        roomNumber: json['room_number'] as int,
        occurredAt: DateTime.parse(json['occurred_at'] as String).toLocal(),
        createdAt: DateTime.parse(json['created_at'] as String).toLocal(),
        confidence: (json['confidence'] as num).toDouble(),
        acknowledgedAt: json['acknowledged_at'] == null
            ? null
            : DateTime.parse(json['acknowledged_at'] as String).toLocal(),
        reported119At: json['reported_119_at'] == null
            ? null
            : DateTime.parse(json['reported_119_at'] as String).toLocal(),
        voiceOkAt: json['voice_ok_at'] == null
            ? null
            : DateTime.parse(json['voice_ok_at'] as String).toLocal(),
      );

  bool get isAcknowledged => acknowledgedAt != null;

  bool get isReported119 => reported119At != null;

  bool get isVoiceOk => voiceOkAt != null;

  String get roomLabel => '$roomName $roomNumber';
}

// 방 1건. 감지 페이지가 이 목록에서 카메라 위치를 고른다.
class Room {
  final int id;
  final String name;
  final int number;

  const Room({required this.id, required this.name, required this.number});

  factory Room.fromJson(Map<String, dynamic> json) => Room(
        id: json['id'] as int,
        name: json['name'] as String,
        number: json['number'] as int,
      );

  String get label => '$name $number';
}

// 보호자 프로필 — 지금은 어르신 전화번호 하나다.
class Profile {
  final String elderPhone;

  const Profile({required this.elderPhone});

  factory Profile.fromJson(Map<String, dynamic> json) =>
      Profile(elderPhone: (json['elder_phone'] as String?) ?? '');
}
