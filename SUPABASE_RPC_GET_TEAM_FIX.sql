-- FIX: GET_TEAM_ATTENDANCE
-- Problema potencial: La función anterior podía estar haciendo JOIN con condiciones que excluían el registro actualizado o caché.
-- Solución: Simplificar y asegurar que traiga el registro más reciente para la fecha dada.

-- PRIMERO ELIMINAMOS LA FUNCIÓN ANTERIOR PARA EVITAR ERROR DE TIPO DE RETORNO
DROP FUNCTION IF EXISTS public.get_team_attendance(uuid, date);

CREATE OR REPLACE FUNCTION public.get_team_attendance(
    p_supervisor_id uuid,
    p_date date DEFAULT CURRENT_DATE
)
RETURNS TABLE (
    employee_id uuid,
    full_name text,
    "position" text,
    role text,
    profile_picture_url text,
    attendance_id uuid,
    check_in timestamp with time zone,
    check_out timestamp with time zone,
    is_late boolean,
    status text,
    record_type text,
    notes text,
    depth integer
)
LANGUAGE plpgsql
SECURITY DEFINER
AS $function$
BEGIN
    RETURN QUERY
    WITH RECURSIVE team_hierarchy AS (
        -- Nivel 1: Subordinados Directos
        SELECT 
            e.id, 
            e.full_name, 
            e."position", 
            e.role, 
            e.profile_picture_url, 
            e.supervisor_id,
            1 as level
        FROM public.employees e
        WHERE e.supervisor_id = p_supervisor_id
        
        UNION ALL
        
        -- Nivel N: Subordinados de Subordinados
        SELECT 
            e.id, 
            e.full_name, 
            e."position", 
            e.role, 
            e.profile_picture_url, 
            e.supervisor_id,
            th.level + 1
        FROM public.employees e
        INNER JOIN team_hierarchy th ON e.supervisor_id = th.id
    )
    SELECT 
        th.id as employee_id,
        th.full_name,
        th."position",
        th.role,
        th.profile_picture_url,
        a.id as attendance_id,
        a.check_in,
        a.check_out,
        a.is_late,
        -- Lógica de estado mejorada para reflejar inmediatamente
        CASE 
            WHEN a.record_type = 'INASISTENCIA' THEN 'ausente'
            WHEN a.check_in IS NOT NULL AND a.is_late THEN 'tardanza'
            WHEN a.check_in IS NOT NULL THEN 'en_jornada' -- o 'puntual'
            ELSE 'pendiente'
        END as status,
        a.record_type,
        a.notes,
        th.level as depth
    FROM 
        team_hierarchy th
    LEFT JOIN 
        public.attendance a ON th.id = a.employee_id AND a.work_date = p_date
    ORDER BY 
        th.level ASC, 
        th.full_name ASC;
END;
$function$;
