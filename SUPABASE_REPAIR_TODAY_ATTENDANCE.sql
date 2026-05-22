-- =============================================================================
-- REPARACIÓN DE ASISTENCIA: Corregir falsas tardanzas del día 2026-05-22
-- =============================================================================
-- Ejecuta este script EN EL SQL EDITOR DE SUPABASE para corregir retroactivamente
-- los marcados de hoy de los empleados afectados, devolviéndolos a estado puntual
-- y asignándoles su horario y turno real en la base de datos.
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
        att.work_date = '2026-05-22' -- Fecha de hoy
        AND (att.is_late = true OR att.status = 'tardanza')
        -- Marcó antes de la hora de entrada más su tolerancia real
        AND (att.check_in AT TIME ZONE 'America/Lima')::time <= (ws.check_in_time + (ws.tolerance_minutes * interval '1 minute'))::time
)
UPDATE public.attendance att
SET 
    is_late = false,
    status = 'asistio',
    schedule_id = rs.correct_schedule_id,
    shift = rs.correct_shift,
    notes = NULL -- Eliminamos la nota del falso positivo de tardanza
FROM resolved_schedules rs
WHERE att.id = rs.attendance_id;

-- =============================================================================
-- CONSULTA DE VERIFICACIÓN POST-REPARACIÓN
-- =============================================================================
-- Después de ejecutar el UPDATE, esta consulta debería devolver 0 filas,
-- lo que indica que todos los falsos positivos de hoy han sido reparados con éxito.
SELECT 
    att.work_date,
    e.full_name,
    (att.check_in AT TIME ZONE 'America/Lima')::time AS hora_marcado,
    att.is_late,
    att.status,
    att.notes
FROM public.attendance att
JOIN public.employees e ON e.id = att.employee_id
WHERE att.work_date = '2026-05-22'
  AND (att.is_late = true OR att.status = 'tardanza')
  AND e.dni IN ('71505998', '70064933', '70048905', '72559930', '47790275', '70270389');
