-- FUNCIÓN PARA QUE EL SUPERVISOR ACTUALICE/JUSTIFIQUE ASISTENCIA (V2 - Con Evidencia)
-- Permite editar nota, validar y adjuntar evidencia.

CREATE OR REPLACE FUNCTION public.supervisor_update_attendance(
    p_supervisor_id uuid,
    p_attendance_id uuid,
    p_notes text,
    p_validate boolean DEFAULT false,
    p_evidence_url text DEFAULT NULL -- Nuevo parámetro opcional
)
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
AS $function$
DECLARE
    v_attendance_rec record;
    v_employee_rec record;
BEGIN
    -- 1. Verificar que el registro de asistencia existe
    SELECT * INTO v_attendance_rec FROM public.attendance WHERE id = p_attendance_id;
    
    IF v_attendance_rec IS NULL THEN
        RETURN json_build_object('success', false, 'message', 'Registro no encontrado');
    END IF;

    -- 2. Verificar permiso (Supervisor directo)
    SELECT * INTO v_employee_rec FROM public.employees WHERE id = v_attendance_rec.employee_id;
    
    IF v_employee_rec.supervisor_id != p_supervisor_id THEN
        RETURN json_build_object('success', false, 'message', 'No tienes permiso sobre este empleado');
    END IF;

    -- 3. Actualizar registro
    -- Solo actualizamos evidence_url si se envía un valor (no nulo)
    UPDATE public.attendance
    SET 
        notes = p_notes,
        validated = p_validate,
        validation_date = CASE WHEN p_validate THEN now() ELSE validation_date END,
        evidence_url = COALESCE(p_evidence_url, evidence_url) -- Mantiene el anterior si no se envía nuevo
    WHERE id = p_attendance_id;

    -- 4. Auditoría
    INSERT INTO public.audit_logs (table_name, record_id, action, performed_by, details)
    VALUES ('attendance', p_attendance_id, 'SUPERVISOR_UPDATE', p_supervisor_id, json_build_object('notes', p_notes, 'validated', p_validate, 'evidence', p_evidence_url));

    RETURN json_build_object('success', true);
END;
$function$;
