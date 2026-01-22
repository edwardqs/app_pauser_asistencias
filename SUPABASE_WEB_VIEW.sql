-- =================================================================
-- VISTA PARA REPORTES WEB (VIEW_ATTENDANCE_REPORTS)
-- =================================================================
-- Esta vista transforma los datos crudos de 'attendance' en un formato
-- amigable para la Web, separando Estado y Tipo visualmente.

DROP VIEW IF EXISTS public.view_attendance_reports;

CREATE VIEW public.view_attendance_reports AS
SELECT
  a.id,
  a.work_date,
  a.employee_id,
  e.full_name AS employee_name,
  e.dni AS employee_dni,
  e.position AS employee_position,
  
  -- ESTADO VISUAL (Lo que se muestra en el badge de color)
  CASE
    WHEN a.record_type = 'ASISTENCIA' AND a.is_late THEN 'TARDANZA'
    WHEN a.record_type = 'ASISTENCIA' THEN 'PUNTUAL'
    WHEN a.record_type IN ('FALTA JUSTIFICADA', 'AUSENCIA SIN JUSTIFICAR') THEN 'AUSENCIA'
    WHEN a.record_type = 'DESCANSO MÉDICO' THEN 'DESCANSO MÉDICO'
    WHEN a.record_type = 'LICENCIA CON GOCE' THEN 'LICENCIA'
    WHEN a.record_type = 'VACACIONES' THEN 'VACACIONES'
    ELSE 'OTRO'
  END AS estado_visual,

  -- TIPO VISUAL (El detalle o subtipo)
  CASE
    WHEN a.record_type = 'ASISTENCIA' THEN 'Asistencia'
    WHEN a.record_type = 'FALTA JUSTIFICADA' THEN 'Justificada'
    WHEN a.record_type = 'AUSENCIA SIN JUSTIFICAR' THEN 'Injustificada'
    WHEN a.record_type = 'DESCANSO MÉDICO' THEN COALESCE(a.subcategory, 'General')
    WHEN a.record_type = 'LICENCIA CON GOCE' THEN 'Con Goce'
    ELSE a.record_type
  END AS tipo_visual,

  -- MOTIVO / DETALLE (Texto libre o notas)
  a.notes AS motivo_detalle,
  
  a.check_in,
  a.check_out,
  a.evidence_url,
  a.validated,
  a.created_at

FROM attendance a
JOIN employees e ON a.employee_id = e.id;

-- Permisos
ALTER VIEW public.view_attendance_reports OWNER TO postgres;
GRANT SELECT ON public.view_attendance_reports TO authenticated;
GRANT SELECT ON public.view_attendance_reports TO service_role;
