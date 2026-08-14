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

  group('ventana de marcacion', () {
    test('es activa dentro del rango del turno', () {
      expect(isShiftActive(DateTime(2026, 8, 13, 8), '07:00:00', '13:00:00'), isTrue);
    });

    test('no es activa antes de que empiece el turno', () {
      expect(isShiftActive(DateTime(2026, 8, 13, 6, 30), '07:00:00', '13:00:00'), isFalse);
    });

    test('no es activa despues de que termina el turno', () {
      expect(isShiftActive(DateTime(2026, 8, 13, 13, 1), '07:00:00', '13:00:00'), isFalse);
    });

    test('turno nocturno activo despues de medianoche', () {
      expect(isShiftActive(DateTime(2026, 8, 14, 2), '19:00:00', '03:00:00'), isTrue);
    });

    test('turno nocturno inactivo antes del inicio', () {
      expect(isShiftActive(DateTime(2026, 8, 13, 18), '19:00:00', '03:00:00'), isFalse);
    });
  });

  group('ventana de marcacion (30 min antes)', () {
    test('permite marcar 10 min antes del inicio', () {
      expect(isShiftMarkable(DateTime(2026, 8, 14, 10, 10), '10:20:00', '10:30:00'), isTrue);
    });

    test('permite marcar 29 min antes del inicio', () {
      expect(isShiftMarkable(DateTime(2026, 8, 14, 9, 51), '10:20:00', '10:30:00'), isTrue);
    });

    test('bloquea marcar 31 min antes del inicio', () {
      expect(isShiftMarkable(DateTime(2026, 8, 14, 9, 49), '10:20:00', '10:30:00'), isFalse);
    });

    test('permite marcar dentro del turno', () {
      expect(isShiftMarkable(DateTime(2026, 8, 14, 10, 25), '10:20:00', '10:30:00'), isTrue);
    });

    test('bloquea marcar despues del fin del turno', () {
      expect(isShiftMarkable(DateTime(2026, 8, 14, 10, 31), '10:20:00', '10:30:00'), isFalse);
    });

    test('turno nocturno: permite marcar 20 min antes del inicio de ayer', () {
      expect(isShiftMarkable(DateTime(2026, 8, 14, 2), '19:00:00', '03:00:00'), isTrue);
    });
  });
}
