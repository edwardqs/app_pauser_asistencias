import 'package:app_asistencias_pauser/core/services/peru_time.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('todayPeruStr tiene formato yyyy-MM-dd', () {
    expect(RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(todayPeruStr()), isTrue);
  });

  test('nowPeru esta 5 horas atras del UTC real (America/Lima sin DST)', () {
    final peru = nowPeru();
    final utc = DateTime.now().toUtc();
    final peruAsUtc = DateTime.utc(peru.year, peru.month, peru.day, peru.hour, peru.minute, peru.second);
    expect(utc.difference(peruAsUtc).inHours, 5);
  });

  test('todayPeruIsodow esta en el rango 1-7', () {
    final isodow = todayPeruIsodow();
    expect(isodow, inInclusiveRange(1, 7));
  });

  test('peruDateStr formatea fechas correctamente', () {
    expect(peruDateStr(DateTime(2026, 8, 3)), '2026-08-03');
    expect(peruDateStr(DateTime(2026, 12, 31)), '2026-12-31');
  });
}
