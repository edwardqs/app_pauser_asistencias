-- =============================================================================
-- DIAGNÓSTICO: Identificar marcados con Falsas Tardanzas en Supabase
-- =============================================================================
-- Ejecuta este script en el SQL Editor de Supabase para ver todos los
-- registros donde el sistema marcó "Tardanza" a pesar de que el empleado
-- llegó a tiempo (o dentro de su tolerancia asignada) según su horario real.
-- =============================================================================

SELECT 
    att.work_date AS fecha,
    e.dni AS dni,
    e.full_name AS empleado,
    e.position AS cargo,
    e.business_unit AS unidad,
    (att.check_in AT TIME ZONE 'America/Lima')::time AS hora_marcado,
    ws.name AS horario_nombre,
    ws.shift AS horario_turno,
    ws.check_in_time AS horario_entrada,
    ws.tolerance_minutes AS tolerancia_minutos,
    (ws.check_in_time + (ws.tolerance_minutes * interval '1 minute'))::time AS entrada_maxima_con_tolerancia,
    att.shift AS turno_marcado_enviado,
    att.is_late AS marcado_tardanza,
    att.notes AS notas_sistema
FROM public.attendance att
JOIN public.employees e ON e.id = att.employee_id
-- Relacionamos con la asignación de horario que estuvo activa en la fecha del marcado
JOIN public.employee_schedule_assignments esa ON esa.employee_id = att.employee_id
    AND esa.valid_from <= att.work_date
    AND (esa.valid_to IS NULL OR esa.valid_to >= att.work_date)
JOIN public.work_schedules ws ON ws.id = esa.schedule_id
    AND ws.is_active = true
    -- Filtramos para que corresponda al día de la semana del marcado
    AND (ws.work_days IS NULL OR EXTRACT(ISODOW FROM att.work_date)::int = ANY(ws.work_days))
WHERE 
    -- 1. Buscamos registros donde el sistema asignó tardanza
    (att.is_late = true OR att.status = 'tardanza')
    -- 2. Pero la hora real de marcado en Lima fue menor o igual que la hora de entrada real más su tolerancia
    AND (att.check_in AT TIME ZONE 'America/Lima')::time <= (ws.check_in_time + (ws.tolerance_minutes * interval '1 minute'))::time
ORDER BY 
    att.work_date DESC, 
    hora_marcado DESC;
