String normalizeShift(String? shift) {
  final value = shift?.trim();
  if (value == null || value.isEmpty) return 'UNICO';
  return value.toUpperCase();
}

bool hasAttendanceForShift(
  Iterable<Map<String, dynamic>> attendances,
  String? shift,
) {
  final expectedShift = normalizeShift(shift);
  return attendances.any(
    (attendance) => normalizeShift(attendance['shift'] as String?) == expectedShift,
  );
}

DateTime scheduledCheckoutForShift(
  DateTime workDate,
  String checkInTime,
  String checkOutTime,
) {
  final checkIn = _timeOnDate(workDate, checkInTime);
  var checkOut = _timeOnDate(workDate, checkOutTime);

  if (!checkOut.isAfter(checkIn)) {
    checkOut = checkOut.add(const Duration(days: 1));
  }

  return checkOut;
}

Map<String, dynamic>? selectTargetShift({
  required List<Map<String, dynamic>> schedules,
  required DateTime now,
  Set<String> alreadyMarkedShifts = const <String>{},
}) {
  final marked = alreadyMarkedShifts.map(normalizeShift).toSet();
  final available = schedules.where((schedule) {
    return !marked.contains(normalizeShift(schedule['shift'] as String?));
  }).toList();

  if (available.isEmpty) return null;
  if (available.length == 1) return available.first;

  Map<String, dynamic>? active;
  Map<String, dynamic>? next;

  for (final schedule in available) {
    final checkInTime = schedule['check_in_time'] as String?;
    final checkOutTime = schedule['check_out_time'] as String?;
    if (checkInTime == null || checkOutTime == null) continue;

    final checkIn = _timeOnDate(now, checkInTime);
    final checkOut = scheduledCheckoutForShift(now, checkInTime, checkOutTime);

    if (!now.isBefore(checkIn) && now.isBefore(checkOut)) {
      active = schedule;
      break;
    }

    if (next == null && now.isBefore(checkIn)) {
      next = schedule;
    }
  }

  return active ?? next ?? available.last;
}

DateTime _timeOnDate(DateTime date, String value) {
  final parts = value.split(':');
  final hour = int.tryParse(parts.first) ?? 0;
  final minute = parts.length > 1 ? int.tryParse(parts[1]) ?? 0 : 0;
  final second = parts.length > 2 ? int.tryParse(parts[2]) ?? 0 : 0;

  return DateTime(date.year, date.month, date.day, hour, minute, second);
}
