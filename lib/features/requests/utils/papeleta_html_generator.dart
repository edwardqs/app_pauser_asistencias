import 'package:intl/intl.dart';

class PapeletaHtmlGenerator {
  static String generate({
    required String employeeName,
    required String employeeDni,
    required String employeePosition,
    required String employeeSede,
    required String requestType,
    required DateTime startDate,
    required DateTime endDate,
    required DateTime emissionDate,
  }) {
    final formattedStart = DateFormat('dd/MM/yyyy').format(startDate);
    final formattedEnd = DateFormat('dd/MM/yyyy').format(endDate);

    // Formato de fecha larga: "26 DE ENERO DE 2026"
    final day = emissionDate.day;
    final months = [
      "ENERO",
      "FEBRERO",
      "MARZO",
      "ABRIL",
      "MAYO",
      "JUNIO",
      "JULIO",
      "AGOSTO",
      "SEPTIEMBRE",
      "OCTUBRE",
      "NOVIEMBRE",
      "DICIEMBRE",
    ];
    final month = months[emissionDate.month - 1];
    final year = emissionDate.year;
    final formattedEmission = "$day DE $month DE $year";

    final isPersonal =
        !requestType.contains('VACACIONES') && !requestType.contains('SALUD');
    final isSalud =
        requestType.contains('SALUD') || requestType.contains('MEDICO');
    final isVacaciones = requestType.contains('VACACIONES');

    // Datos del empleador (Hardcoded como en la web)
    const employerNombre = "PAUSER DISTRIBUCIONES S.A.C.";
    const employerRuc = "20600869940";
    const employerDomicilio =
        "JR. PEDRO MUÑIZ NRO. 253 DPTO. 1601 SEC. JORGE CHAVEZ LA LIBERTAD - TRUJILLO";
    const employerRepresentante = "GIANCARLO URBINA GAITAN";
    const employerDniRep = "18161904";

    // Estilos EXACTOS de RequestsList.jsx
    final styles = """
      <style>
        body { font-family: Arial, sans-serif; margin: 0; padding: 20px; background: white; color: black; }
        .container { border: 3px solid black; background: white; width: 100%; max-width: 750px; margin: 0 auto; }
        .header { border-bottom: 3px solid black; padding: 5px; text-align: center; background: #f9fafb; }
        .title { font-size: 20px; font-weight: 900; letter-spacing: 2px; text-transform: uppercase; margin: 0; }
        
        .section { display: flex; border-bottom: 2px solid black; }
        .letter-box { width: 40px; border-right: 2px solid black; display: flex; align-items: center; justify-content: center; font-weight: 900; font-size: 24px; }
        .content { flex: 1; }
        
        .row { display: flex; border-bottom: 1px solid black; }
        .row:last-child { border-bottom: none; }
        
        .label { width: 100px; padding: 4px; font-weight: bold; border-right: 1px solid black; font-size: 11px; display: flex; align-items: center; }
        .value { padding: 4px; font-weight: bold; color: #1e40af; font-size: 11px; flex: 1; }
        
        .sub-row { width: 50%; display: flex; border-right: 1px solid black; }
        .sub-row:last-child { border-right: none; }
        .sub-label { width: 60px; padding: 4px; font-weight: bold; border-right: 1px solid black; font-size: 10px; }
        .sub-value { padding: 4px; font-size: 10px; }
        
        .date-box { display: flex; align-items: center; gap: 10px; }
        .date-label { font-size: 9px; font-weight: bold; color: #2563eb; text-align: right; line-height: 1.1; }
        .date-value { border: 2px solid black; padding: 4px 12px; font-size: 16px; font-weight: 900; background: white; }
        
        .check-group { display: flex; justify-content: space-between; padding: 5px 20px; }
        .check-item { display: flex; align-items: center; gap: 5px; }
        .check-label { font-weight: bold; font-size: 10px; }
        .check-box { width: 16px; height: 16px; border: 1px solid black; display: flex; align-items: center; justify-content: center; font-weight: 900; font-size: 12px; }
        
        .footer-info { padding: 10px 20px; }
        .date-line { font-weight: bold; font-size: 10px; text-transform: uppercase; margin-bottom: 20px; }
        
        .signatures { display: flex; justify-content: space-between; align-items: flex-end; gap: 20px; margin-bottom: 10px; }
        .sig-block { flex: 1; text-align: center; }
        .sig-line { border-top: 1px dotted black; padding-top: 4px; }
        .sig-name { font-weight: bold; font-size: 9px; margin: 0; }
        .sig-dni { font-size: 8px; margin: 0; }
        
        .fingerprint { border: 1px solid black; width: 60px; height: 80px; display: flex; flex-direction: column; align-items: center; justify-content: space-between; padding: 4px; background: white; }
        .fp-label { font-size: 6px; color: #9ca3af; }
        .fp-circle { width: 30px; height: 30px; border-radius: 50%; border: 1px solid #e5e7eb; }
        
        .page-footer { border-top: 3px solid black; height: 30px; display: flex; align-items: center; }
        .brand { flex: 1; padding: 0 20px; display: flex; align-items: center; gap: 10px; }
        .brand-text { font-size: 12px; font-weight: 900; }
        .brand-sub { font-size: 8px; font-weight: bold; color: #6b7280; }
        .copy-type { border-left: 3px solid black; padding: 0 20px; height: 100%; display: flex; align-items: center; background: #f3f4f6; font-size: 9px; font-weight: 900; font-style: italic; text-transform: uppercase; }
        
        .divider { width: 100%; border-bottom: 2px dashed #d1d5db; margin: 20px 0; }
      </style>
    """;

    String renderCopy(String type) {
      return """
      <div class="container">
        <div class="header"><h1 class="title">PAPELETA DE VACACIONES</h1></div>
        
        <!-- A -->
        <div class="section">
          <div class="letter-box">A</div>
          <div class="content">
            <div class="row"><div class="label">EL EMPLEADOR</div><div class="value">$employerNombre</div></div>
            <div class="row">
              <div class="sub-row"><div class="sub-label">con RUC</div><div class="sub-value">$employerRuc</div></div>
              <div class="sub-row" style="flex:1"><div class="sub-label">Domicilio</div><div class="sub-value" style="font-size:8px">$employerDomicilio</div></div>
            </div>
            <div class="row" style="border:none"><div class="label">Representante</div><div class="value" style="color:black; font-weight:normal; font-size:10px">$employerRepresentante (DNI: $employerDniRep)</div></div>
          </div>
        </div>

        <!-- B -->
        <div class="section">
          <div class="letter-box">B</div>
          <div class="content">
            <div class="row"><div class="label">EL TRABAJADOR</div><div class="value">$employeeName</div></div>
            <div class="row">
              <div class="sub-row"><div class="sub-label">DNI Nº</div><div class="value">$employeeDni</div></div>
              <div class="sub-row" style="flex:1"><div class="sub-label">CARGO</div><div class="value" style="color:black">$employeePosition</div></div>
            </div>
            <div class="row" style="justify-content: space-around; padding: 8px; border:none">
              <div class="date-box">
                <div class="date-label">FECHA DE<br>SALIDA</div>
                <div class="date-value">$formattedStart</div>
              </div>
              <div class="date-box">
                <div class="date-label">FECHA DE<br>RETORNO</div>
                <div class="date-value">$formattedEnd</div>
              </div>
            </div>
          </div>
        </div>

        <!-- C -->
        <div class="section">
          <div class="letter-box">C</div>
          <div class="content">
            <div class="row" style="background:#f9fafb"><div class="label">MOTIVO</div><div class="value" style="color:#6b7280; font-weight:normal; font-style:italic">Seleccione el tipo</div></div>
            <div class="check-group">
              <div class="check-item"><span class="check-label">PERSONALES</span><div class="check-box">${isPersonal ? 'X' : ''}</div></div>
              <div class="check-item"><span class="check-label">SALUD</span><div class="check-box">${isSalud ? 'X' : ''}</div></div>
              <div class="check-item"><span class="check-label">VACACIONES</span><div class="check-box">${isVacaciones ? 'X' : ''}</div></div>
            </div>
          </div>
        </div>

        <!-- Footer -->
        <div class="footer-info">
          <div class="date-line">$employeeSede, $formattedEmission</div>
          <div class="signatures">
            <div class="sig-block"><div style="height:30px"></div><div class="sig-line"><p class="sig-name">$employerRepresentante</p><p class="sig-dni">DNI: $employerDniRep</p></div></div>
            <div class="sig-block"><div style="height:30px"></div><div class="sig-line"><p class="sig-name" style="color:#1e3a8a">$employeeName</p><p class="sig-dni">DNI: $employeeDni</p></div></div>
            <div class="fingerprint">
              <span class="fp-label">HUELLA</span>
              <div class="fp-circle"></div>
              <span class="fp-label" style="text-align:center">INDICE DERECHO</span>
            </div>
          </div>
        </div>

        <div class="page-footer">
          <div class="brand"><span class="brand-text">PAUSER</span><span style="color:#9ca3af">|</span><span class="brand-sub">RECURSOS HUMANOS</span></div>
          <div class="copy-type">COPIA $type</div>
        </div>
      </div>
      """;
    }

    return """
      <!DOCTYPE html>
      <html>
      <head>
        <meta charset="UTF-8">
        $styles
      </head>
      <body>
        ${renderCopy('EMPRESA')}
        <div class="divider"></div>
        ${renderCopy('EMPLEADO')}
      </body>
      </html>
    """;
  }
}
