-- =============================================================================
-- DASHBOARD PRINCIPAL - KPIs
-- Función RPC para obtener contadores principales (Empleados, Asistencia, Pendientes, Tardanzas)
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
BEGIN
    -- 1. Total Empleados Activos
    SELECT COUNT(*) INTO v_total_employees
    FROM public.employees
    WHERE is_active = true
    AND (p_sede IS NULL OR sede = p_sede)
    AND (p_business_unit IS NULL OR business_unit = p_business_unit);

    -- 2. Asistencias Hoy
    SELECT COUNT(*) INTO v_attendance_today
    FROM public.attendance a
    JOIN public.employees e ON a.employee_id = e.id
    WHERE a.work_date = CURRENT_DATE
    AND (p_sede IS NULL OR e.sede = p_sede)
    AND (p_business_unit IS NULL OR e.business_unit = p_business_unit);

    -- 3. Solicitudes Pendientes (Vacaciones)
    SELECT COUNT(*) INTO v_pending_requests
    FROM public.vacation_requests vr
    JOIN public.employees e ON vr.employee_id = e.id
    WHERE vr.status = 'PENDIENTE'
    AND (p_sede IS NULL OR e.sede = p_sede)
    AND (p_business_unit IS NULL OR e.business_unit = p_business_unit);

    -- 4. Tardanzas Mes Actual
    SELECT COUNT(*) INTO v_lateness_month
    FROM public.attendance a
    JOIN public.employees e ON a.employee_id = e.id
    WHERE a.is_late = true
    AND date_trunc('month', a.work_date) = date_trunc('month', CURRENT_DATE)
    AND (p_sede IS NULL OR e.sede = p_sede)
    AND (p_business_unit IS NULL OR e.business_unit = p_business_unit);

    RETURN json_build_object(
        'total_employees', v_total_employees,
        'attendance_today', v_attendance_today,
        'pending_requests', v_pending_requests,
        'lateness_month', v_lateness_month
    );
END;
$$;
