-- FUNCIÓN RECURSIVA PARA OBTENER TODO EL EQUIPO (Jerárquico Multinivel)
-- Un Supervisor/Jefe llama a esto y recibe la lista de TODOS sus subordinados (directos e indirectos)
-- Ejemplo: Jefe de Ventas -> Ve a Supervisores -> Ve a Vendedores

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
    depth integer -- Nivel de profundidad jerárquica (1 = directo, 2 = subordinado de subordinado)
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
        COALESCE(a.status, 'pendiente') as status,
        a.record_type,
        a.notes,
        th.level as depth
    FROM 
        team_hierarchy th
    LEFT JOIN 
        public.attendance a ON th.id = a.employee_id AND a.work_date = p_date
    ORDER BY 
        th.level ASC, -- Primero los directos
        th.full_name ASC;
END;
$function$;
