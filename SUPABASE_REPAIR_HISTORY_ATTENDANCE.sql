-- =============================================================================
-- REPARACIÓN HISTÓRICA: Corregir Falsas Tardanzas desde el Jueves 21 de Mayo
-- =============================================================================
-- Ejecuta este script en el SQL Editor de Supabase para corregir
-- retroactivamente los 19 registros de falsa tardanza detectados en la auditoría.
-- =============================================================================

WITH resolved_schedules AS (
    SELECT 
        att.id AS attendance_id,
        ws.id AS correct_schedule_id,
        ws.shift AS correct_shift,
        ws.check_in_time,
        ws.tolerance_minutes,
        (att.check_in AT TIME ZONE 'America/Lima')::time AS hora_marcado
    FROM public.attendance att
    JOIN public.employee_schedule_assignments esa ON esa.employee_id = att.employee_id
        AND esa.valid_from <= att.work_date
        AND (esa.valid_to IS NULL OR esa.valid_to >= att.work_date)
    JOIN public.work_schedules ws ON ws.id = esa.schedule_id
        AND ws.is_active = true
        AND (ws.work_days IS NULL OR EXTRACT(ISODOW FROM att.work_date)::int = ANY(ws.work_days))
    WHERE 
        att.work_date >= '2026-05-21'
        AND (att.is_late = true OR att.status = 'tardanza')
        -- El marcado fue antes del límite programado más la tolerancia real
        AND (att.check_in AT TIME ZONE 'America/Lima')::time <= (ws.check_in_time + (ws.tolerance_minutes * interval '1 minute'))::time
)
UPDATE public.attendance att
SET 
    is_late = false,
    status = 'asistio',
    schedule_id = rs.correct_schedule_id,
    shift = rs.correct_shift,
    notes = NULL -- Eliminamos la nota del sistema del falso positivo de tardanza
FROM resolved_schedules rs
WHERE att.id = rs.attendance_id;

-- =============================================================================
-- VERIFICACIÓN POST-REPARACIÓN
-- =============================================================================
-- Esta consulta de verificación cruzada debería reportar 0 falsos positivos restantes.
SELECT 
    att.work_date AS fecha,
    e.full_name AS empleado,
    (att.check_in AT TIME ZONE 'America/Lima')::time AS hora_marcado,
    att.is_late,
    att.status,
    att.notes
FROM public.attendance att
JOIN public.employees e ON e.id = att.employee_id
JOIN public.employee_schedule_assignments esa ON esa.employee_id = att.employee_id
    AND esa.valid_from <= att.work_date
    AND (esa.valid_to IS NULL OR esa.valid_to >= att.work_date)
JOIN public.work_schedules ws ON ws.id = esa.schedule_id
    AND ws.is_active = true
    AND (ws.work_days IS NULL OR EXTRACT(ISODOW FROM att.work_date)::int = ANY(ws.work_days))
WHERE 
    att.work_date >= '2026-05-21'
    AND (att.is_late = true OR att.status = 'tardanza')
    AND (att.check_in AT TIME ZONE 'America/Lima')::time <= (ws.check_in_time + (ws.tolerance_minutes * interval '1 minute'))::time;
