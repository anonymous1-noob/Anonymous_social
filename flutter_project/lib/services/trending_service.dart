import 'dart:math' as math;

class TrendingService {
  static double calculateHotScore({
    required int likes,
    required int comments,
    required int shares,
    required DateTime createdAt,
  }) {
    final engagement =
        likes + (comments * 2) + (shares * 3);

    final ageHours =
        DateTime.now().difference(createdAt).inHours;

    return engagement / math.pow(ageHours + 2, 1.5);
  }
}