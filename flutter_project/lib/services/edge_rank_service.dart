import 'dart:math' as math;

import 'package:anonymous_social/models/post_model.dart';
import 'package:anonymous_social/models/user_model.dart';

class EdgeRankService {
  static double calculatePostScore({
    required PostModel post,
    required UserModel currentUser,
    required UserModel author,
  }) {
    final qualityScore = _calculateQualityScore(post);

    final engagementScore = _calculateEngagementScore(post);

    final recencyScore = _calculateRecencyScore(post);

    final reputationScore = _calculateReputationScore(author);

    final personalizationScore = _calculatePersonalizationScore(
      post,
      currentUser,
    );

    final antiSpamMultiplier = _calculateAntiSpamMultiplier(
      post,
      author,
    );

    final ratingBoost = _calculateRatingBoost(post);

    final finalScore = (
          qualityScore * 0.55 +
          ratingBoost * 0.25 +
          engagementScore * 0.08 +
          recencyScore * 0.05 +
          reputationScore * 0.05 +
          personalizationScore * 0.02
        ) *
        antiSpamMultiplier;

      print('''
      POST: ${post.content}

      avgRating: ${post.avgRating}
      ratingCount: ${post.ratingCount}

      qualityScore: $qualityScore
      engagementScore: $engagementScore
      recencyScore: $recencyScore
      reputationScore: $reputationScore

      FINAL SCORE: $finalScore
      ''');
    return finalScore;
  }

  // =====================================================
  // RATING BOOST
  // =====================================================

  static double _calculateRatingBoost(PostModel post) {
    final avgRating = post.avgRating;

    final ratingCount = post.ratingCount;

    // Normalize from -5 to +5 => 0 to 1
    final normalized = (avgRating + 5) / 10;

    // Strong confidence multiplier
    final confidence =
        1 - (1 / (1 + (ratingCount / 3)));

    // Exponential rating amplification
    final boosted =
        math.pow(normalized, 2).toDouble();

    return boosted * confidence;
  }

  // =====================================================
  // QUALITY SCORE
  // =====================================================

    static double _calculateQualityScore(PostModel post) {
    // Convert -5 to +5 into 0 to 10 scale
    final ratingScore = post.avgRating + 5;

    // Confidence boost based on rating volume
    final confidenceMultiplier =
        1 + (post.ratingCount / 20);

    // Heavy penalty for negatively rated posts
    double penalty = 1.0;

    if (post.avgRating < 0) {
      penalty = 0.4;
    }

    if (post.avgRating < -2) {
      penalty = 0.15;
    }

    if (post.avgRating < -4) {
      penalty = 0.05;
    }

    return ratingScore * confidenceMultiplier * penalty;
  }

  // =====================================================
  // ENGAGEMENT SCORE
  // =====================================================

  static double _calculateEngagementScore(PostModel post) {
    final score =
        (post.likesCount * 1.0) +
        (post.commentsCount * 2.5) +
        (post.sharesCount * 4.0) +
        (post.bookmarksCount * 3.0) +
        (post.dwellTime * 0.5);

    return math.log(score + 1) / 10;
  }

  // =====================================================
  // RECENCY SCORE
  // =====================================================

  static double _calculateRecencyScore(PostModel post) {
    final ageHours =
        DateTime.now().difference(post.createdAt).inHours;

    return math.exp(-ageHours / 24);
  }

  // =====================================================
  // REPUTATION SCORE
  // =====================================================

  static double _calculateReputationScore(UserModel author) {
    final accountAgeDays =
        DateTime.now().difference(author.accountCreatedAt).inDays;

    final accountTrust = math.min(accountAgeDays / 365, 1.0);

    final normalizedHistoricalRating =
        (author.historicalAvgRating + 5) / 10;

    final reportPenalty =
        math.max(0.0, 1 - (author.reportsReceived / 100));

    return (
      normalizedHistoricalRating * 0.5 +
      author.reputationScore * 0.3 +
      accountTrust * 0.2
    ) * reportPenalty;
  }

  // =====================================================
  // PERSONALIZATION SCORE
  // =====================================================

  static double _calculatePersonalizationScore(
    PostModel post,
    UserModel currentUser,
  ) {
    int matches = 0;

    for (final tag in post.tags) {
      if (currentUser.interestedTags.contains(tag)) {
        matches++;
      }
    }

    if (post.tags.isEmpty) {
      return 0.3;
    }

    return matches / post.tags.length;
  }

  // =====================================================
  // ANTI-SPAM MULTIPLIER
  // =====================================================

  static double _calculateAntiSpamMultiplier(
    PostModel post,
    UserModel author,
  ) {
    double multiplier = 1.0;

    // Too many reports
    if (post.reportCount > 10) {
      multiplier *= 0.7;
    }

    // Very low rating
    if (post.avgRating < -2) {
      multiplier *= 0.5;
    }

    // New account spam protection
    final accountAgeDays =
        DateTime.now().difference(author.accountCreatedAt).inDays;

    if (accountAgeDays < 3 && post.likesCount > 100) {
      multiplier *= 0.6;
    }

    // Deleted content history
    if (post.isDeleted) {
      multiplier *= 0.1;
    }

    return multiplier;
  }
}