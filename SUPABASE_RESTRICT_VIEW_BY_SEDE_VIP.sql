-- =================================================================================
-- RESTRICCIÓN DE VISTA DE EQUIPO POR SEDE (SEGÚN ROL) - VERSIÓN MEJORADA
-- Descripción: Modifica los RPCs de reporte de asistencia para que ciertos roles 
-- (Jefes/Analistas de Gente y Gestión/SST) solo vean empleados de SU MISMA SEDE.
-- EXCEPCIÓN: Si es 'ANALISTA DE GENTE Y GESTIÓN' de la sede 'ADM. CENTRAL', ve TODO.
-- =================================================================================


-- 1. ACTUALIZAR get_daily_attendance_report
CREATE OR REPLACE FUNCTION public.get_daily_attendance_report(
    p_date date DEFAULT (CURRENT_TIMESTAMP AT TIME ZONE 'America/Lima')::date,
    p_search text DEFAULT '',
    p_offset int DEFAULT 0,
    p_limit int DEFAULT 20,
    p_status text DEFAULT 'all'
)
RETURNS TABLE (
    total_rows bigint,
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
    v_filter_sede text := NULL;
    v_current_user_role text;
    v_current_user_sede text;
    v_current_user_unit text;
BEGIN
    -- 1. Obtener datos del usuario actual
    SELECT 
        COALESCE(r.name, e.position), e.sede, e.business_unit 
    INTO 
        v_current_user_role, v_current_user_sede, v_current_user_unit
    FROM public.employees e
    LEFT JOIN public.roles r ON e.role_id = r.id
    WHERE e.email = auth.email();

    -- 2. Lógica de Filtrado por Rol/Cargo
    -- Verificar si el usuario tiene un rol restringido
    IF (
        UPPER(v_current_user_role) IN (
            'JEFE DE GENTE Y GESTIÓN',
            'ANALISTA DE GENTE Y GESTIÓN',
            'ANALISTA DE GENTE Y GESTIÓN Y SST',
            'COORDINADOR DE SEGURIDAD Y SALUD EN EL TRABAJO',
            'ANALISTA DE SEGURIDAD Y SALUD EN EL TRABAJO'
        )
    ) THEN
        -- SI ES EL ROL RESTRINGIDO, VERIFICAMOS LA EXCEPCIÓN DE "ADM. CENTRAL"
        IF (v_current_user_sede = 'ADM. CENTRAL' AND v_current_user_unit = 'ADMINISTRACION') THEN
            -- ES VIP: NO APLICAR FILTRO (Ve todo)
            v_filter_sede := NULL;
        ELSE
            -- NO ES VIP: APLICAR FILTRO POR SU SEDE
            v_filter_sede := v_current_user_sede;
        END IF;
    ELSE
        -- SI NO ES UN ROL RESTRINGIDO (EJ: ADMIN, SUPER ADMIN), VE TODO
        v_filter_sede := NULL;
    END IF;
    
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
        -- APLICAR FILTRO DE SEDE SI EXISTE
        AND (v_filter_sede IS NULL OR e.sede = v_filter_sede)
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
                WHEN p_status = 'absent' THEN (jd.record_type IN ('AUSENCIA', 'INASISTENCIA', 'FALTA JUSTIFICADA', 'AUSENCIA SIN JUSTIFICAR', 'FALTA_INJUSTIFICADA') OR jd.attendance_id IS NULL)
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



-- 2. ACTUALIZAR get_attendance_stats (Para los contadores del Dashboard)
-- Aplica la misma lógica de excepción VIP
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
    v_absent bigint;
    v_search_term text := '%' || p_search || '%';
    v_filter_sede text := NULL;
    v_current_user_role text;
    v_current_user_sede text;
    v_current_user_unit text;
BEGIN
    -- 1. Obtener datos del usuario actual
    SELECT 
        COALESCE(r.name, e.position), e.sede, e.business_unit 
    INTO 
        v_current_user_role, v_current_user_sede, v_current_user_unit
    FROM public.employees e
    LEFT JOIN public.roles r ON e.role_id = r.id
    WHERE e.email = auth.email();

    -- 2. Lógica de Filtrado por Rol/Cargo con Excepción VIP
    IF (
        UPPER(v_current_user_role) IN (
            'JEFE DE GENTE Y GESTIÓN',
            'ANALISTA DE GENTE Y GESTIÓN',
            'ANALISTA DE GENTE Y GESTIÓN Y SST',
            'COORDINADOR DE SEGURIDAD Y SALUD EN EL TRABAJO',
            'ANALISTA DE SEGURIDAD Y SALUD EN EL TRABAJO'
        )
    ) THEN
        IF (v_current_user_sede = 'ADM. CENTRAL' AND v_current_user_unit = 'ADMINISTRACION') THEN
            v_filter_sede := NULL; -- VE TODO
        ELSE
            v_filter_sede := v_current_user_sede; -- FILTRADO
        END IF;
    ELSE
        v_filter_sede := NULL;
    END IF;

    -- Calcular estadísticas con el filtro aplicado
    WITH target_employees AS (
        SELECT id 
        FROM public.employees e
        WHERE e.is_active = true
        AND (p_search = '' OR e.full_name ILIKE v_search_term OR e.dni ILIKE v_search_term)
        AND (v_filter_sede IS NULL OR e.sede = v_filter_sede)
    ),
    daily_attendance AS (
        SELECT 
            a.*
        FROM public.attendance a
        WHERE a.work_date = p_date
        AND a.employee_id IN (SELECT id FROM target_employees)
    )
    SELECT
        (SELECT count(*) FROM target_employees),
        (SELECT count(*) FROM daily_attendance WHERE record_type = 'ASISTENCIA' AND is_late = false),
        (SELECT count(*) FROM daily_attendance WHERE is_late = true),
        (SELECT count(*) FROM target_employees) - (SELECT count(*) FROM daily_attendance WHERE record_type = 'ASISTENCIA')
    INTO
        v_total_employees,
        v_on_time,
        v_late,
        v_absent;

    RETURN json_build_object(
        'total_employees', v_total_employees,
        'on_time', v_on_time,
        'late', v_late,
        'absent', v_absent
    );
END;
$$;
