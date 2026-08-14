import 'package:app_asistencias_pauser/features/attendance/domain/shift_attendance.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('turnos partidos', () {
    final schedules = [
      {
        'name': 'Turno manana',
        'shift': 'MAÑANA',
        'check_in_time': '07:00:00',
        'check_out_time': '13:00:00',
      },
      {
        'name': 'Turno tarde',
        'shift': 'TARDE',
        'check_in_time': '15:00:00',
        'check_out_time': '20:00:00',
      },
    ];

    test('normaliza un turno vacio como UNICO', () {
      expect(normalizeShift(null), 'UNICO');
      expect(normalizeShift(''), 'UNICO');
      expect(normalizeShift(' manana '), 'MANANA');
    });

    test('detecta cualquier registro del mismo turno, aunque este cerrado', () {
      final attendances = [
        {'shift': 'MAÑANA', 'check_out': '2026-08-13T18:00:00Z'},
        {'shift': 'TARDE', 'check_out': null},
      ];

      expect(hasAttendanceForShift(attendances, 'MAÑANA'), isTrue);
      expect(hasAttendanceForShift(attendances, 'TARDE'), isTrue);
      expect(hasAttendanceForShift(attendances, 'NOCHE'), isFalse);
    });

    test('elige el turno activo y permite el segundo turno', () {
      final active = selectTargetShift(
        schedules: schedules,
        now: DateTime(2026, 8, 13, 16),
      );
      final pending = selectTargetShift(
        schedules: schedules,
        now: DateTime(2026, 8, 13, 16),
        alreadyMarkedShifts: {'MAÑANA'},
      );

      expect(active?['shift'], 'TARDE');
      expect(pending?['shift'], 'TARDE');
    });

    test('no selecciona un turno ya registrado', () {
      final target = selectTargetShift(
        schedules: schedules,
        now: DateTime(2026, 8, 13, 8),
        alreadyMarkedShifts: {'MAÑANA', 'TARDE'},
      );

      expect(target, isNull);
    });
  });

  group('medianoche', () {
    test('mantiene work_date de inicio y mueve la salida al dia siguiente', () {
      final checkout = scheduledCheckoutForShift(
        DateTime(2026, 8, 13),
        '19:00:00',
        '03:00:00',
      );

      expect(checkout, DateTime(2026, 8, 14, 3));
    });

    test('un horario diurno mantiene la misma fecha', () {
      final checkout = scheduledCheckoutForShift(
        DateTime(2026, 8, 13),
        '07:00:00',
        '13:00:00',
      );

      expect(checkout, DateTime(2026, 8, 13, 13));
    });
  });
}
