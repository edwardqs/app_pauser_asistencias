-- =============================================================================
-- OBTENER ACTIVIDAD RECIENTE (DASHBOARD)
-- Retorna las últimas N actividades con datos de empleado enriquecidos.
-- =============================================================================

DROP FUNCTION IF EXISTS public.get_dashboard_activity(integer);

CREATE OR REPLACE FUNCTION public.get_dashboard_activity(
    p_limit integer DEFAULT 10
)
RETURNS TABLE (
    id uuid,
    created_at timestamp with time zone,
    check_in timestamp with time zone,
    check_out timestamp with time zone,
    record_type text,
    status text,
    is_late boolean,
    notes text,
    absence_reason text,
    subcategory text,
    location_in jsonb,
    location_out jsonb,
    employee_id uuid,
    full_name text,
    profile_picture_url text,
    "position" text
)
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
    RETURN QUERY
    SELECT 
        a.id,
        a.created_at,
        a.check_in,
        a.check_out,
        a.record_type,
        a.status,
        COALESCE(a.is_late, false) as is_late,
        a.notes,
        a.absence_reason,
        a.subcategory, -- Asegúrate que esta columna exista, si no, quítala o pon NULL
        CASE 
            WHEN a.location_in IS NULL THEN NULL 
            ELSE a.location_in::jsonb 
        END as location_in,
        CASE 
            WHEN a.location_out IS NULL THEN NULL 
            ELSE a.location_out::jsonb 
        END as location_out,
        e.id as employee_id,
        e.full_name,
        e.profile_picture_url,
        e.position
    FROM public.attendance a
    JOIN public.employees e ON a.employee_id = e.id
    ORDER BY a.created_at DESC
    LIMIT p_limit;
END;
$$;
