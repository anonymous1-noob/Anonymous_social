class UserModel {
  final String id;

  final double reputationScore;

  final List<String> interestedTags;

  final int totalPosts;

  final double historicalAvgRating;

  final int reportsReceived;

  final DateTime accountCreatedAt;

  UserModel({
    required this.id,
    required this.reputationScore,
    required this.interestedTags,
    required this.totalPosts,
    required this.historicalAvgRating,
    required this.reportsReceived,
    required this.accountCreatedAt,
  });

  factory UserModel.anonymous() {
    return UserModel(
      id: 'anonymous',
      reputationScore: 0.5,
      interestedTags: [],
      totalPosts: 0,
      historicalAvgRating: 0,
      reportsReceived: 0,
      accountCreatedAt:
          DateTime.now().subtract(
        const Duration(days: 365),
      ),
    );
  }
}