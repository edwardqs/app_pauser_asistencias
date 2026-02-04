-- SCRIPT DE GESTIÓN DE VACACIONES
-- 1. Agregar columnas necesarias a la tabla employees
ALTER TABLE public.employees 
ADD COLUMN IF NOT EXISTS legacy_vacation_days_taken numeric DEFAULT 0;

COMMENT ON COLUMN public.employees.legacy_vacation_days_taken IS 'Días de vacaciones consumidos históricamente (migrados de Excel)';

-- Nota: 'entry_date' ya existe y se usa como fecha de ingreso (hiring_date)

-- 2. Función RPC para obtener el resumen de vacaciones (Kardex Resumido)
CREATE OR REPLACE FUNCTION public.get_vacation_overview(
    p_sede text DEFAULT NULL,
    p_search text DEFAULT NULL
)
RETURNS TABLE (
    employee_id uuid,
    full_name text,
    "position" text,
    sede text,
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
            e.entry_date,
            e.legacy_vacation_days_taken,
            
            -- Calcular años de servicio (Antigüedad)
            ROUND(
                (EXTRACT(EPOCH FROM (CURRENT_DATE - e.entry_date)) / 86400 / 365.25)::numeric, 
                1
            ) as years_service,
            
            -- Calcular días ganados: (Días trabajados / 360) * 30
            -- Usamos 360 días como año comercial estándar para RRHH
            ROUND(
                ((EXTRACT(EPOCH FROM (CURRENT_DATE - e.entry_date)) / 86400) / 360.0 * 30.0)::numeric,
                2
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
        vc.entry_date,
        vc.years_service,
        vc.earned as earned_days,
        COALESCE(vc.legacy_vacation_days_taken, 0) as legacy_taken,
        vc.app_used as app_taken,
        
        -- Saldo: Ganados - (Histórico + App)
        (vc.earned - (COALESCE(vc.legacy_vacation_days_taken, 0) + vc.app_used)) as balance,
        
        -- Semáforo (Lógica de Negocio)
        CASE 
            WHEN (vc.earned - (COALESCE(vc.legacy_vacation_days_taken, 0) + vc.app_used)) >= 30 THEN 'danger' -- Acumulación excesiva (más de un año)
            WHEN (vc.earned - (COALESCE(vc.legacy_vacation_days_taken, 0) + vc.app_used)) >= 15 THEN 'warning' -- Acumulación moderada
            ELSE 'safe' -- Al día
        END as status
    FROM vacation_calculations vc
    ORDER BY balance DESC;
END;
$$;

-- 3. Función RPC para carga masiva desde Excel
-- Recibe un array de objetos JSON: [{ "dni": "12345678", "entry_date": "2023-01-01", "legacy_days": 15 }, ...]
CREATE OR REPLACE FUNCTION public.bulk_update_vacations(
    p_data jsonb
)
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    item jsonb;
    v_updated_count int := 0;
    v_errors text[] := ARRAY[]::text[];
BEGIN
    FOR item IN SELECT * FROM jsonb_array_elements(p_data)
    LOOP
        BEGIN
            -- Actualizar por DNI
            UPDATE public.employees
            SET 
                entry_date = (item->>'entry_date')::date,
                legacy_vacation_days_taken = (item->>'legacy_days')::numeric,
                updated_at = NOW()
            WHERE dni = (item->>'dni')::text;
            
            IF FOUND THEN
                v_updated_count := v_updated_count + 1;
            END IF;
        EXCEPTION WHEN OTHERS THEN
            v_errors := array_append(v_errors, 'Error DNI ' || (item->>'dni') || ': ' || SQLERRM);
        END;
    END LOOP;

    RETURN json_build_object(
        'success', true,
        'updated_count', v_updated_count,
        'errors', v_errors
    );
END;
$$;
