-- =============================================================================
-- EXPORTACIÓN DE ASISTENCIA POR RANGO DE FECHAS
-- Retorna TODOS los empleados activos con su estado de asistencia para un rango.
-- =============================================================================

DROP FUNCTION IF EXISTS public.get_attendance_export_report(date, date, text);

CREATE OR REPLACE FUNCTION public.get_attendance_export_report(
    p_start_date date,
    p_end_date date,
    p_status text DEFAULT 'all'
)
RETURNS TABLE (
    employee_id uuid,
    full_name text,
    dni text,
    "position" text,
    sede text,
    work_date date,
    attendance_id uuid,
    check_in timestamp with time zone,
    check_out timestamp with time zone,
    is_late boolean,
    record_type text,
    status text,
    validated boolean,
    notes text
)
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
    RETURN QUERY
    -- Generar serie de fechas para el rango
    WITH date_series AS (
        SELECT generate_series(p_start_date, p_end_date, '1 day')::date as day
    ),
    -- Producto cartesiano: Todos los empleados x Todos los días del rango
    all_employee_days AS (
        SELECT 
            e.id as emp_id,
            e.full_name as emp_name,
            e.dni as emp_dni,
            e.position as emp_position,
            e.sede as emp_sede,
            ds.day as work_day
        FROM public.employees e
        CROSS JOIN date_series ds
        WHERE e.is_active = true
    ),
    -- Unir con registros reales de asistencia
    joined_data AS (
        SELECT 
            aed.emp_id,
            aed.emp_name,
            aed.emp_dni,
            aed.emp_position,
            aed.emp_sede,
            aed.work_day,
            a.id as att_id,
            a.check_in as att_check_in,
            a.check_out as att_check_out,
            COALESCE(a.is_late, false) as att_is_late,
            a.record_type as att_record_type,
            COALESCE(a.status, 'PENDIENTE') as att_status,
            COALESCE(a.validated, false) as att_validated,
            COALESCE(a.notes, a.absence_reason) as att_notes
        FROM all_employee_days aed
        LEFT JOIN public.attendance a ON aed.emp_id = a.employee_id AND a.work_date = aed.work_day
    )
    -- Filtrar según status solicitado
    SELECT 
        jd.emp_id,
        jd.emp_name,
        jd.emp_dni,
        jd.emp_position,
        jd.emp_sede,
        jd.work_day,
        jd.att_id,
        jd.att_check_in,
        jd.att_check_out,
        jd.att_is_late,
        jd.att_record_type,
        jd.att_status,
        jd.att_validated,
        jd.att_notes
    FROM joined_data jd
    WHERE 
        CASE 
            WHEN p_status = 'all' THEN true
            WHEN p_status = 'on_time' THEN jd.att_record_type = 'ASISTENCIA' AND jd.att_is_late = false
            WHEN p_status = 'late' THEN jd.att_is_late = true
            -- 'absent' incluye registros de ausencia O días sin registro (null)
            WHEN p_status = 'absent' THEN (jd.att_record_type IN ('AUSENCIA', 'INASISTENCIA', 'FALTA JUSTIFICADA', 'AUSENCIA SIN JUSTIFICAR', 'FALTA_INJUSTIFICADA') OR jd.att_id IS NULL)
            WHEN p_status = 'medical' THEN jd.att_record_type = 'DESCANSO MÉDICO'
            WHEN p_status = 'license' THEN jd.att_record_type = 'LICENCIA CON GOCE'
            WHEN p_status = 'vacation' THEN jd.att_record_type = 'VACACIONES'
            ELSE true
        END
    ORDER BY jd.work_day DESC, jd.emp_name ASC;
END;
$$;
