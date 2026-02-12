-- CORRECCIÓN: Script para get_vacation_overview sin errores de tipos en fechas
-- ACTUALIZACIÓN: Cálculo de días ganados y saldo truncado a ENTEROS (sin decimales)

-- PRIMERO BORRAMOS LA FUNCIÓN EXISTENTE PARA EVITAR CONFLICTOS DE TIPOS DE RETORNO
DROP FUNCTION IF EXISTS public.get_vacation_overview(text, text);

CREATE OR REPLACE FUNCTION public.get_vacation_overview(
    p_sede text DEFAULT NULL,
    p_search text DEFAULT NULL
)
RETURNS TABLE (
    employee_id uuid,
    full_name text,
    "position" text,
    sede text,
    business_unit text, -- Agregado para restaurar la columna perdida
    entry_date date,
    years_of_service numeric,
    earned_days numeric,
    legacy_taken numeric,
    app_taken numeric,
    balance numeric,
    status text
)
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
    RETURN QUERY
    WITH vacation_calculations AS (
        SELECT 
            e.id,
            e.full_name,
            e.position,
            e.sede,
            e.business_unit, -- Seleccionar de la tabla employees
            e.entry_date,
            e.legacy_vacation_days_taken,
            
            -- Calcular años de servicio (Antigüedad)
            -- Restar fechas directamente devuelve integer (días)
            ROUND(
                ((CURRENT_DATE - e.entry_date)::numeric / 365.25), 
                1
            ) as years_service,
            
            -- Calcular días ganados: (Días trabajados / 360) * 30
            -- TRUNCAMOS a 0 decimales para que sea ENTERO
            TRUNC(
                ((CURRENT_DATE - e.entry_date)::numeric / 360.0 * 30.0),
                0
            ) as earned,
            
            -- Calcular días consumidos desde la App (status = 'APROBADO')
            COALESCE(
                (SELECT SUM(vr.total_days) 
                 FROM public.vacation_requests vr 
                 WHERE vr.employee_id = e.id 
                 AND vr.status = 'APROBADO'), 
                0
            ) as app_used
            
        FROM public.employees e
        WHERE e.is_active = true
        AND e.entry_date IS NOT NULL -- Evitar errores con fechas nulas
        AND (p_sede IS NULL OR e.sede = p_sede)
        AND (p_search IS NULL OR 
             e.full_name ILIKE '%' || p_search || '%' OR 
             e.dni ILIKE '%' || p_search || '%')
    )
    SELECT 
        vc.id as employee_id,
        vc.full_name,
        vc.position,
        vc.sede,
        vc.business_unit, -- Retornar en el SELECT final
        vc.entry_date,
        vc.years_service,
        vc.earned as earned_days,
        COALESCE(vc.legacy_vacation_days_taken, 0) as legacy_taken,
        vc.app_used as app_taken,
        
        -- Saldo: Ganados - (Histórico + App)
        -- TRUNCAMOS el resultado final para asegurar ENTEROS en el saldo
        TRUNC(
            (vc.earned - (COALESCE(vc.legacy_vacation_days_taken, 0) + vc.app_used)),
            0
        ) as balance,
        
        -- Semáforo (Lógica de Negocio)
        CASE 
            WHEN (vc.earned - (COALESCE(vc.legacy_vacation_days_taken, 0) + vc.app_used)) >= 30 THEN 'danger' 
            WHEN (vc.earned - (COALESCE(vc.legacy_vacation_days_taken, 0) + vc.app_used)) >= 15 THEN 'warning' 
            ELSE 'safe'
        END as status
    FROM vacation_calculations vc
    ORDER BY balance DESC;
END;
$$;
