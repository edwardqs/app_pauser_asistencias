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

/// Ventana de marcacion: true si [now] esta dentro de [checkIn, checkOut).
/// Soporta cruce de medianoche (turno iniciado ayer y activo hoy).
bool isShiftActive(
  DateTime now,
  String checkInTime,
  String checkOutTime,
) {
  final checkIn = _timeOnDate(now, checkInTime);
  final checkOut = scheduledCheckoutForShift(now, checkInTime, checkOutTime);
  if (!now.isBefore(checkIn) && now.isBefore(checkOut)) return true;

  // Turno nocturno: si no fue activo con la fecha de hoy, probar el de ayer.
  final yesterday = now.subtract(const Duration(days: 1));
  final inYesterday = _timeOnDate(yesterday, checkInTime);
  final outYesterday = scheduledCheckoutForShift(yesterday, checkInTime, checkOutTime);
  return !now.isBefore(inYesterday) && now.isBefore(outYesterday);
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

    if (isShiftActive(now, checkInTime, checkOutTime)) {
      active = schedule;
      break;
    }

    final checkIn = _timeOnDate(now, checkInTime);
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
