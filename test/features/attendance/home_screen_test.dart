import 'package:app_asistencias_pauser/core/services/storage_service.dart';
import 'package:app_asistencias_pauser/features/attendance/data/attendance_repository.dart';
import 'package:app_asistencias_pauser/features/attendance/presentation/home_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

// Mock StorageService
class MockStorageService implements StorageService {
  @override
  String? get employeeId => 'test-employee-id';

  @override
  String? get fullName => 'Test User';

  @override
  String? get position => 'Developer';

  @override
  String? get profilePicture => null;

  @override
  String? get businessUnit => null;

  @override
  String? get dni => null;

  @override
  String? get employeeType => null;

  @override
  bool get isAuthenticated => true;

  @override
  String? get role => null;

  @override
  String? get userName => 'Test User';

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

// Fake AttendanceRepository
class FakeAttendanceRepository implements AttendanceRepository {
  @override
  Future<Map<String, dynamic>> getEmployeeDayStatus(String employeeId) async {
    // Return a default "Vacation" status for testing
    return {
      'date': '2025-01-30',
      'attendance': null,
      'vacation': {
        'id': 'vac-123',
        'start_date': '2025-01-28',
        'end_date': '2025-02-05',
        'days': 7,
      },
      'is_on_vacation': true,
    };
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  setUp(() async {
    await initializeDateFormatting('es', null);
  });

  testWidgets('HomeScreen displays Vacation Mode when user is on vacation', (
    WidgetTester tester,
  ) async {
    await tester.runAsync(() async {
      // Override the providers
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            storageServiceProvider.overrideWithValue(MockStorageService()),
            attendanceRepositoryProvider.overrideWithValue(
              FakeAttendanceRepository(),
            ),
          ],
          child: const MaterialApp(home: HomeScreen()),
        ),
      );

      // Wait for the future to resolve.
      // We use runAsync to handle the infinite timer in AnalogClock
      await Future.delayed(const Duration(seconds: 1));
      await tester.pump();

      // Verify Vacation Mode UI
      expect(find.text('¡MODO VACACIONES!'), findsOneWidget);
      expect(find.byIcon(Icons.beach_access), findsOneWidget);
      expect(
        find.text('Disfruta tu descanso. No necesitas registrar asistencia.'),
        findsOneWidget,
      );

      // Cleanup
      await tester.pumpWidget(const SizedBox());
    });
  });
}
