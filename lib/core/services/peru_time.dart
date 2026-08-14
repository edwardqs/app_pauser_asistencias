/// Hora y fecha centralizadas en America/Lima (UTC-5 fijo; Peru no usa
/// horario de verano). Todas las consultas de jornada deben usar estas
/// funciones para que el dispositivo tenga cualquier zona horaria.
DateTime nowPeru() => DateTime.now().toUtc().add(const Duration(hours: -5));

String peruDateStr(DateTime date) {
  return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
}

/// Fecha actual en America/Lima como 'yyyy-MM-dd'.
String todayPeruStr() => peruDateStr(nowPeru());

/// Dia ISO de la semana en America/Lima (Lunes=1 ... Domingo=7).
int todayPeruIsodow() => nowPeru().weekday;
