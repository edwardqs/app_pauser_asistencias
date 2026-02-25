-- =============================================================================
-- INTENTO 6: EQUILIBRIO PERFECTO DE PERMISOS
-- Objetivo:
-- 1. ADMIN y JEFE DE GENTE -> Ven TODO (Global)
-- 2. JEFE DE FINANZAS/ADMINISTRACIÓN -> Ven SOLO SU ÁREA (Restringido)
-- Problema anterior: La regla de restricción estaba bloqueando al ADMIN si su cargo contenía 'ADMIN'.
-- Solución: La regla de Admin Global debe tener PRECEDENCIA ABSOLUTA sobre la restricción de Jefes.
-- =============================================================================

CREATE OR REPLACE FUNCTION public.get_main_dashboard_stats(
    p_sede text DEFAULT NULL,
    p_business_unit text DEFAULT NULL
)
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_total_employees int;
    v_attendance_today int;
    v_pending_requests int;
    v_lateness_month int;
    
    v_user_role text;
    v_user_position text;
    v_user_area_id bigint;
    v_user_business_unit text;
    v_is_admin boolean;
BEGIN
    -- 0. Detectar Rol y Área del Usuario
    SELECT 
        e.role, 
        e.position,
        jp.area_id,
        e.business_unit
    INTO 
        v_user_role, 
        v_user_position,
        v_user_area_id,
        v_user_business_unit
    FROM public.employees e
    LEFT JOIN public.job_positions jp ON e.position = jp.name
    WHERE e.email = auth.email();

    -- LÓGICA DE SEGURIDAD JERÁRQUICA (CORREGIDA Y ROBUSTA)
    
    -- Normalización de entradas para evitar errores de mayúsculas/espacios
    v_user_role := UPPER(TRIM(COALESCE(v_user_role, '')));
    v_user_position := UPPER(TRIM(COALESCE(v_user_position, '')));

    -- NIVEL 0: SUPER USUARIO DE SISTEMA (admin@pauser.com)
    -- Este usuario NO existe en la tabla employees, pero debe ser ADMIN.
    IF auth.email() = 'admin@pauser.com' THEN
        v_is_admin := TRUE;

    -- NIVEL 1: ADMINS GLOBALES REALES (Prioridad Máxima)
    -- Estos roles ven TODO, sin importar su cargo específico.
    ELSIF v_user_role IN ('ADMIN', 'SUPER ADMIN', 'JEFE_RRHH', 'GERENTE GENERAL', 'SISTEMAS') THEN
        v_is_admin := TRUE;
        
    -- NIVEL 1.1: CARGOS GLOBALES (Excepciones por Cargo)
    -- Si el cargo dice "Jefe de Gente" o "Analista de Gente", es Admin Global.
    ELSIF (v_user_position LIKE '%JEFE DE GENTE%' OR v_user_position LIKE '%ANALISTA DE GENTE%') THEN
        v_is_admin := TRUE;

    -- NIVEL 2: RESTRICCIÓN PARA JEFES ADMINISTRATIVOS
    -- Si NO es Admin Global, y su cargo es de Finanzas/Admin, forzamos vista restringida.
    ELSIF (v_user_position LIKE '%ADMINISTRACI%' OR v_user_position LIKE '%FINANZAS%') THEN
        v_is_admin := FALSE;
        
    -- NIVEL 3: OTROS ROLES (Fallback)
    ELSE
        v_is_admin := FALSE;
    END IF;
    
    -- Asegurar valor booleano
    v_is_admin := COALESCE(v_is_admin, FALSE);

    -- 1. Total Empleados Activos
    SELECT COUNT(*) INTO v_total_employees
    FROM public.employees e
    LEFT JOIN public.job_positions jp ON e.position = jp.name
    WHERE e.is_active = true
    AND (p_sede IS NULL OR e.sede = p_sede)
    AND (
        (v_is_admin) -- Admin ve todo
        OR (NOT v_is_admin AND ( -- No admin ve solo lo suyo
            CASE 
                WHEN v_user_area_id IS NOT NULL THEN jp.area_id = v_user_area_id
                WHEN v_user_business_unit IS NOT NULL THEN e.business_unit = v_user_business_unit
                ELSE FALSE
            END
        ))
    );

    -- 2. Asistencias Hoy
    SELECT COUNT(*) INTO v_attendance_today
    FROM public.attendance a
    JOIN public.employees e ON a.employee_id = e.id
    LEFT JOIN public.job_positions jp ON e.position = jp.name
    WHERE (
        a.work_date = CURRENT_DATE 
        OR a.work_date = (CURRENT_DATE - INTERVAL '1 day')
    )
    AND a.check_in IS NOT NULL 
    AND a.record_type NOT IN ('AUSENCIA', 'FALTA_INJUSTIFICADA', 'INASISTENCIA', 'FALTA JUSTIFICADA')
    AND a.created_at >= (now() - INTERVAL '24 hours')
    AND (p_sede IS NULL OR e.sede = p_sede)
    AND (
        (v_is_admin)
        OR (NOT v_is_admin AND (
            CASE 
                WHEN v_user_area_id IS NOT NULL THEN jp.area_id = v_user_area_id
                WHEN v_user_business_unit IS NOT NULL THEN e.business_unit = v_user_business_unit
                ELSE FALSE
            END
        ))
    );

    -- 3. Solicitudes Pendientes
    SELECT COUNT(*) INTO v_pending_requests
    FROM public.vacation_requests vr
    JOIN public.employees e ON vr.employee_id = e.id
    LEFT JOIN public.job_positions jp ON e.position = jp.name
    WHERE UPPER(vr.status) = 'PENDIENTE'
    AND (p_sede IS NULL OR e.sede = p_sede)
    AND (
        (v_is_admin)
        OR (NOT v_is_admin AND (
            CASE 
                WHEN v_user_area_id IS NOT NULL THEN jp.area_id = v_user_area_id
                WHEN v_user_business_unit IS NOT NULL THEN e.business_unit = v_user_business_unit
                ELSE FALSE
            END
        ))
    );

    -- 4. Tardanzas Mes Actual
    SELECT COUNT(*) INTO v_lateness_month
    FROM public.attendance a
    JOIN public.employees e ON a.employee_id = e.id
    LEFT JOIN public.job_positions jp ON e.position = jp.name
    WHERE a.is_late = true
    AND date_trunc('month', a.work_date) = date_trunc('month', CURRENT_DATE)
    AND (p_sede IS NULL OR e.sede = p_sede)
    AND (
        (v_is_admin)
        OR (NOT v_is_admin AND (
            CASE 
                WHEN v_user_area_id IS NOT NULL THEN jp.area_id = v_user_area_id
                WHEN v_user_business_unit IS NOT NULL THEN e.business_unit = v_user_business_unit
                ELSE FALSE
            END
        ))
    );

    RETURN json_build_object(
        'total_employees', v_total_employees,
        'attendance_today', v_attendance_today,
        'pending_requests', v_pending_requests,
        'lateness_month', v_lateness_month
    );
END;
$$;
