/// Utility helpers for displaying human-readable time strings
///
/// Usage:
///   formatTimeAgo(DateTime.parse(createdAt))
///
/// Output examples:
///   - Just now
///   - 5m ago
///   - 2h ago
///   - Yesterday
///   - 3d ago
///   - 12 Jan 2026
library time_utils;

class TimeUtils {
  static String formatTimeAgo(DateTime dateTime) {
    final now = DateTime.now();
    final diff = now.difference(dateTime);

    if (diff.inSeconds < 30) {
      return 'Just now';
    }

    if (diff.inMinutes < 1) {
      return '${diff.inSeconds}s ago';
    }

    if (diff.inMinutes < 60) {
      return '${diff.inMinutes}m ago';
    }

    if (diff.inHours < 24) {
      return '${diff.inHours}h ago';
    }

    if (diff.inDays == 1) {
      return 'Yesterday';
    }

    if (diff.inDays < 7) {
      return '${diff.inDays}d ago';
    }

    return _formatDate(dateTime);
  }

  static String _formatDate(DateTime dateTime) {
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];

    final day = dateTime.day.toString().padLeft(2, '0');
    final month = months[dateTime.month - 1];
    final year = dateTime.year;

    return '$day $month $year';
  }
}
