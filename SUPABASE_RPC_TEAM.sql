-- FUNCIÓN PARA OBTENER ASISTENCIA DEL EQUIPO (Jerárquico)
-- Un Supervisor/Jefe llama a esto y recibe la lista de sus subordinados directos con el estado de hoy.

CREATE OR REPLACE FUNCTION public.get_team_attendance(
    p_supervisor_id uuid,
    p_date date DEFAULT CURRENT_DATE
)
RETURNS TABLE (
    employee_id uuid,
    full_name text,
    position text,
    role text,
    profile_picture_url text,
    attendance_id uuid,
    check_in timestamp with time zone,
    check_out timestamp with time zone,
    is_late boolean,
    status text,
    record_type text,
    notes text
)
LANGUAGE plpgsql
SECURITY DEFINER
AS $function$
BEGIN
    RETURN QUERY
    SELECT 
        e.id as employee_id,
        e.full_name,
        e.position,
        e.role,
        e.profile_picture_url,
        a.id as attendance_id,
        a.check_in,
        a.check_out,
        a.is_late,
        COALESCE(a.status, 'pendiente') as status,
        a.record_type,
        a.notes
    FROM 
        public.employees e
    LEFT JOIN 
        public.attendance a ON e.id = a.employee_id AND a.work_date = p_date
    WHERE 
        e.supervisor_id = p_supervisor_id
    ORDER BY 
        e.full_name ASC;
END;
$function$;
