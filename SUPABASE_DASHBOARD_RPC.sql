-- =============================================================================
-- REPORTE MENSUAL & ANALYTICS
-- Función RPC optimizada para dashboard de gestión
-- =============================================================================

CREATE OR REPLACE FUNCTION public.get_monthly_dashboard_metrics(
    p_year int,
    p_month int,
    p_sede text DEFAULT NULL
)
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_start_date date;
    v_end_date date;
    v_new_hires json;
    v_attendance_summary json;
    v_absence_breakdown json;
    v_vacation_stats json;
    v_vacation_by_unit json;
    v_hires_trend json;
BEGIN
    -- Definir rango de fechas del mes seleccionado
    v_start_date := make_date(p_year, p_month, 1);
    v_end_date := (v_start_date + interval '1 month' - interval '1 day')::date;

    -- 1. NUEVOS INGRESOS (Detalle para exportación y conteo)
    SELECT json_build_object(
        'count', COUNT(*),
        'list', COALESCE(
            json_agg(
                json_build_object(
                    'dni', dni,
                    'full_name', full_name,
                    'position', position,
                    'sede', sede,
                    'entry_date', entry_date,
                    'business_unit', business_unit
                ) ORDER BY entry_date DESC
            ), 
            '[]'::json
        )
    ) INTO v_new_hires
    FROM public.employees
    WHERE entry_date >= v_start_date 
    AND entry_date <= v_end_date
    AND (p_sede IS NULL OR sede = p_sede);

    -- 2. TENDENCIA DE INGRESOS (Últimos 6 meses)
    SELECT json_agg(t) INTO v_hires_trend
    FROM (
        SELECT 
            TO_CHAR(date_trunc('month', entry_date), 'Mon') as name,
            COUNT(*) as ingresos
        FROM public.employees
        WHERE entry_date >= (v_start_date - interval '5 months')
        AND entry_date <= v_end_date
        AND (p_sede IS NULL OR sede = p_sede)
        GROUP BY date_trunc('month', entry_date)
        ORDER BY date_trunc('month', entry_date) ASC
    ) t;

    -- 3. RESUMEN DE ASISTENCIA (Puntual vs Tarde vs Ausente)
    -- Contamos registros de la tabla attendance en ese rango
    SELECT json_build_object(
        'puntual', COUNT(*) FILTER (WHERE record_type = 'ASISTENCIA' AND is_late = false),
        'tardanza', COUNT(*) FILTER (WHERE is_late = true),
        'ausencia', COUNT(*) FILTER (WHERE record_type IN ('AUSENCIA', 'INASISTENCIA', 'FALTA JUSTIFICADA', 'AUSENCIA SIN JUSTIFICAR', 'FALTA_INJUSTIFICADA') OR record_type IS NULL)
    ) INTO v_attendance_summary
    FROM public.attendance a
    JOIN public.employees e ON a.employee_id = e.id
    WHERE a.work_date >= v_start_date 
    AND a.work_date <= v_end_date
    AND (p_sede IS NULL OR e.sede = p_sede);

    -- 4. DESGLOSE DE AUSENCIAS POR TIPO (Top 5)
    SELECT COALESCE(json_agg(t), '[]'::json) INTO v_absence_breakdown
    FROM (
        SELECT 
            COALESCE(a.absence_reason, a.record_type) as name,
            COUNT(*) as value
        FROM public.attendance a
        JOIN public.employees e ON a.employee_id = e.id
        WHERE a.work_date >= v_start_date 
        AND a.work_date <= v_end_date
        AND (p_sede IS NULL OR e.sede = p_sede)
        AND a.record_type NOT IN ('ASISTENCIA', 'PUNTUAL', 'TARDANZA') -- Excluir asistencias normales
        GROUP BY COALESCE(a.absence_reason, a.record_type)
        ORDER BY value DESC
        LIMIT 5
    ) t;

    -- 5. ESTADÍSTICAS DE VACACIONES (Días tomados en el mes)
    -- Buscamos en vacation_requests que se solapen con este mes
    SELECT json_build_object(
        'total_days_taken', COALESCE(SUM(
            -- Calcular intersección de días
            LEAST(end_date, v_end_date) - GREATEST(start_date, v_start_date) + 1
        ), 0),
        'requests_count', COUNT(*)
    ) INTO v_vacation_stats
    FROM public.vacation_requests vr
    JOIN public.employees e ON vr.employee_id = e.id
    WHERE vr.status = 'APROBADO'
    AND vr.start_date <= v_end_date 
    AND vr.end_date >= v_start_date
    AND (p_sede IS NULL OR e.sede = p_sede);

    -- 6. VACACIONES POR UNIDAD DE NEGOCIO
    SELECT COALESCE(json_agg(t), '[]'::json) INTO v_vacation_by_unit
    FROM (
        SELECT 
            COALESCE(e.business_unit, 'Sin Unidad') as name,
            COALESCE(SUM(
                LEAST(vr.end_date, v_end_date) - GREATEST(vr.start_date, v_start_date) + 1
            ), 0) as value
        FROM public.vacation_requests vr
        JOIN public.employees e ON vr.employee_id = e.id
        WHERE vr.status = 'APROBADO'
        AND vr.start_date <= v_end_date 
        AND vr.end_date >= v_start_date
        AND (p_sede IS NULL OR e.sede = p_sede)
        GROUP BY e.business_unit
        ORDER BY value DESC
        LIMIT 10
    ) t;

    -- RETORNAR TODO EL PAQUETE JSON
    RETURN json_build_object(
        'new_hires', v_new_hires,
        'hires_trend', COALESCE(v_hires_trend, '[]'::json),
        'attendance_summary', v_attendance_summary,
        'absence_breakdown', v_absence_breakdown,
        'vacation_stats', v_vacation_stats,
        'vacation_by_unit', v_vacation_by_unit
    );
END;
$$;
