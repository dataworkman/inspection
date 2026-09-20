const _months = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', //
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
];

/// Parses an ISO date/time from the API into local time (null if absent).
DateTime? parseApiTime(Object? value) {
  if (value == null) return null;
  return DateTime.tryParse(value.toString())?.toLocal();
}

/// "Sep 18, 2026"
String formatDate(DateTime date) =>
    '${_months[date.month - 1]} ${date.day}, ${date.year}';

/// "Today", "Yesterday", "3 days ago", otherwise the date.
String relativeDay(DateTime date, {DateTime? now}) {
  final today = now ?? DateTime.now();
  final days = DateTime(today.year, today.month, today.day)
      .difference(DateTime(date.year, date.month, date.day))
      .inDays;
  if (days <= 0) return 'Today';
  if (days == 1) return 'Yesterday';
  if (days < 7) return '$days days ago';
  return formatDate(date);
}

String initials(String? name) {
  final parts = (name ?? '')
      .trim()
      .split(RegExp(r'\s+'))
      .where((p) => p.isNotEmpty)
      .toList();
  if (parts.isEmpty) return '?';
  if (parts.length == 1) return parts.first[0].toUpperCase();
  return (parts.first[0] + parts.last[0]).toUpperCase();
}

String roleLabel(String? role) => switch (role) {
      'admin' => 'Administrator',
      'inspector' => 'Inspector',
      'store_manager' => 'Store manager',
      _ => '',
    };

/// "in_progress" -> "In progress".
String humanize(Object? value) {
  final text = (value ?? '').toString().replaceAll('_', ' ');
  return text.isEmpty ? '-' : text[0].toUpperCase() + text.substring(1);
}
