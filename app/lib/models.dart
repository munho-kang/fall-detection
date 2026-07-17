// 서버가 내려주는 낙상 이벤트 1건

class FallEvent {
  final int id;
  final String roomName;
  final int roomNumber;
  final DateTime occurredAt;
  final DateTime createdAt;
  final double confidence;
  final DateTime? acknowledgedAt;

  const FallEvent({
    required this.id,
    required this.roomName,
    required this.roomNumber,
    required this.occurredAt,
    required this.createdAt,
    required this.confidence,
    this.acknowledgedAt,
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
      );

  bool get isAcknowledged => acknowledgedAt != null;

  String get roomLabel => '$roomName $roomNumber';
}
