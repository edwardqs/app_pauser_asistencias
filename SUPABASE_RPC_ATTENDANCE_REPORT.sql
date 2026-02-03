-- =============================================================================
-- VISTA MAESTRA DE ASISTENCIA DIARIA (WEB)
-- Retorna TODOS los empleados activos con su estado de asistencia para una fecha dada.
-- =============================================================================

DROP FUNCTION IF EXISTS public.get_daily_attendance_report(date, text, integer, integer);
DROP FUNCTION IF EXISTS public.get_daily_attendance_report(date, text, integer, integer, text);

CREATE OR REPLACE FUNCTION public.get_daily_attendance_report(
    p_date date DEFAULT (CURRENT_TIMESTAMP AT TIME ZONE 'America/Lima')::date,
    p_search text DEFAULT '',
    p_offset int DEFAULT 0,
    p_limit int DEFAULT 20,
    p_status text DEFAULT 'all'
)
RETURNS TABLE (
    total_rows bigint,      -- Total de empleados encontrados (para paginación)
    employee_id uuid,
    full_name text,
    dni text,
    "position" text,
    sede text,
    profile_picture_url text,
    attendance_id uuid,
    check_in timestamp with time zone,
    check_out timestamp with time zone,
    is_late boolean,
    record_type text,
    status text,
    validated boolean,
    notes text,
    evidence_url text,
    location_in jsonb
)
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_search_term text := '%' || p_search || '%';
BEGIN
    RETURN QUERY
    WITH all_employees AS (
        SELECT 
            e.id,
            e.full_name,
            e.dni,
            e.position,
            e.sede,
            e.profile_picture_url
        FROM public.employees e
        WHERE e.is_active = true
        AND (
            p_search = '' OR 
            e.full_name ILIKE v_search_term OR 
            e.dni ILIKE v_search_term
        )
    ),
    joined_data AS (
        SELECT 
            ae.*,
            a.id as attendance_id,
            a.check_in,
            a.check_out,
            COALESCE(a.is_late, false) as is_late,
            a.record_type,
            COALESCE(a.status, 'PENDIENTE') as status,
            COALESCE(a.validated, false) as validated,
            COALESCE(a.notes, a.absence_reason) as notes,
            a.evidence_url,
            CASE 
                WHEN a.location_in IS NULL THEN NULL 
                ELSE a.location_in::jsonb 
            END as location_in
        FROM all_employees ae
        LEFT JOIN public.attendance a ON ae.id = a.employee_id AND a.work_date = p_date
    ),
    filtered_data AS (
        SELECT * FROM joined_data jd
        WHERE 
            CASE 
                WHEN p_status = 'all' THEN true
                WHEN p_status = 'on_time' THEN jd.record_type = 'ASISTENCIA' AND jd.is_late = false
                WHEN p_status = 'late' THEN jd.is_late = true
                -- 'absent' incluye tanto ausencias registradas como pendientes (sin registro)
                WHEN p_status = 'absent' THEN (jd.record_type IN ('AUSENCIA', 'INASISTENCIA', 'FALTA JUSTIFICADA', 'AUSENCIA SIN JUSTIFICAR', 'FALTA_INJUSTIFICADA') OR jd.attendance_id IS NULL OR jd.record_type IS NULL)
                WHEN p_status = 'medical' THEN jd.record_type = 'DESCANSO MÉDICO'
                WHEN p_status = 'license' THEN jd.record_type = 'LICENCIA CON GOCE'
                WHEN p_status = 'vacation' THEN jd.record_type = 'VACACIONES'
                ELSE true
            END
    ),
    counts AS (
        SELECT count(*) as total FROM filtered_data
    )
    SELECT 
        (SELECT total FROM counts) as total_rows,
        fd.id as employee_id,
        fd.full_name,
        fd.dni,
        fd.position,
        fd.sede,
        fd.profile_picture_url,
        fd.attendance_id,
        fd.check_in,
        fd.check_out,
        fd.is_late,
        fd.record_type,
        fd.status,
        fd.validated,
        fd.notes,
        fd.evidence_url,
        fd.location_in
    FROM filtered_data fd
    ORDER BY 
        CASE WHEN fd.attendance_id IS NOT NULL THEN 0 ELSE 1 END,
        fd.full_name ASC
    LIMIT p_limit
    OFFSET p_offset;
END;
$$;

-- =============================================================================
-- ESTADÍSTICAS GLOBALES DE ASISTENCIA (WEB)
-- Calcula totales reales basados en la plantilla total de empleados.
-- =============================================================================

CREATE OR REPLACE FUNCTION public.get_attendance_stats(
    p_date date DEFAULT (CURRENT_TIMESTAMP AT TIME ZONE 'America/Lima')::date,
    p_search text DEFAULT ''
)
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_total_employees bigint;
    v_on_time bigint;
    v_late bigint;
    v_absent bigint; -- Ausencias explícitas (registradas)
    v_pending bigint; -- Sin registro
    v_search_term text := '%' || p_search || '%';
BEGIN
    -- 1. Total Empleados Activos (Filtrados)
    SELECT count(*) INTO v_total_employees
    FROM public.employees e
    WHERE e.is_active = true
    AND (
        p_search = '' OR 
        e.full_name ILIKE v_search_term OR 
        e.dni ILIKE v_search_term
    );

    -- 2. Contar estados desde la tabla de asistencia (unida con empleados para respetar filtro)
    SELECT 
        COUNT(*) FILTER (WHERE a.record_type = 'ASISTENCIA' AND a.is_late = false),
        COUNT(*) FILTER (WHERE a.is_late = true),
        COUNT(*) FILTER (WHERE 
            a.record_type IN ('AUSENCIA', 'INASISTENCIA', 'FALTA JUSTIFICADA', 'AUSENCIA SIN JUSTIFICAR', 'FALTA_INJUSTIFICADA')
            OR (a.record_type IS NULL AND a.check_in IS NULL) -- Incluir registros vacíos como ausencias
        )
    INTO v_on_time, v_late, v_absent
    FROM public.attendance a
    JOIN public.employees e ON a.employee_id = e.id
    WHERE a.work_date = p_date -- FILTRO CRUCIAL POR FECHA
    AND e.is_active = true
    AND (
        p_search = '' OR 
        e.full_name ILIKE v_search_term OR 
        e.dni ILIKE v_search_term
    );

    -- 3. Calcular Pendientes (Los que faltan registrar)
    -- Total = (Puntuales + Tardanzas + Ausencias_Registradas + Otros_Tipos) + Pendientes
    
    -- Para ser exactos, contamos todos los registros del día
    DECLARE
        v_total_records bigint;
    BEGIN
        SELECT count(*) INTO v_total_records
        FROM public.attendance a
        JOIN public.employees e ON a.employee_id = e.id
        WHERE a.work_date = p_date -- FILTRO CRUCIAL POR FECHA
        AND e.is_active = true
        AND (p_search = '' OR e.full_name ILIKE v_search_term OR e.dni ILIKE v_search_term);
        
        v_pending := v_total_employees - v_total_records;
        if v_pending < 0 THEN v_pending := 0; END IF;
    END;

    RETURN json_build_object(
        'total_employees', v_total_employees,
        'on_time', v_on_time,
        'late', v_late,
        'absent_registered', v_absent,
        'pending', v_pending
    );
END;
$$;
