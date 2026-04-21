class RewardLedger {
  RewardLedger({
    this.balanceSeconds = 0,
    this.shieldLiftedUntil,
  });

  final int balanceSeconds;
  final DateTime? shieldLiftedUntil;

  bool get isShieldLifted {
    final until = shieldLiftedUntil;
    if (until == null) return false;
    return DateTime.now().isBefore(until);
  }

  Duration get remainingLift {
    final until = shieldLiftedUntil;
    if (until == null) return Duration.zero;
    final diff = until.difference(DateTime.now());
    return diff.isNegative ? Duration.zero : diff;
  }

  /// `clearShieldLiftedUntil: true` forces the [shieldLiftedUntil] field to
  /// `null`. Without it, a `null` passed for [shieldLiftedUntil] is treated
  /// as "not provided" and the existing value is retained.
  RewardLedger copyWith({
    int? balanceSeconds,
    DateTime? shieldLiftedUntil,
    bool clearShieldLiftedUntil = false,
  }) =>
      RewardLedger(
        balanceSeconds: balanceSeconds ?? this.balanceSeconds,
        shieldLiftedUntil: clearShieldLiftedUntil
            ? null
            : (shieldLiftedUntil ?? this.shieldLiftedUntil),
      );

  Map<String, dynamic> toJson() => {
        'balanceSeconds': balanceSeconds,
        'shieldLiftedUntil': shieldLiftedUntil?.toIso8601String(),
      };

  factory RewardLedger.fromJson(Map<String, dynamic> json) => RewardLedger(
        balanceSeconds: json['balanceSeconds'] as int? ?? 0,
        shieldLiftedUntil: json['shieldLiftedUntil'] == null
            ? null
            : DateTime.parse(json['shieldLiftedUntil'] as String),
      );
}
