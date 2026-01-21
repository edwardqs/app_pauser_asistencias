-- ACTUALIZACIÓN DE RPC PARA REGISTRO MANUAL CON MANEJO DE DUPLICADOS
-- Lógica:
-- 1. Si ya existe un registro para ese empleado y fecha, lo ACTUALIZA en lugar de fallar.
-- 2. Maneja correctamente la restricción unique 'idx_attendance_employee_date'.

CREATE OR REPLACE FUNCTION public.register_manual_attendance(
    p_employee_id uuid,
    p_supervisor_id uuid,
    p_work_date date,
    p_check_in timestamptz,
    p_record_type text,     -- 'IN' o 'ABSENCE'
    p_notes text DEFAULT NULL,
    p_evidence_url text DEFAULT NULL
)
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
AS $function$
DECLARE
    v_timestamp_peru timestamp;
    v_time_peru time;
    v_is_late boolean := false;
    v_status text;
    v_final_notes text;
    
    -- Configuración de hora límite (07:00 AM)
    c_late_limit time := '07:00:00';
BEGIN
    -- Convertir el timestamp ingresado a Hora Perú para validar tardanza
    v_timestamp_peru := p_check_in AT TIME ZONE 'America/Lima';
    v_time_peru := v_timestamp_peru::time;
    v_final_notes := COALESCE(p_notes, '');

    -- Lógica de estado según tipo
    IF p_record_type = 'IN' THEN
        IF v_time_peru > c_late_limit THEN
            v_is_late := true;
            v_status := 'tardanza';
            v_final_notes := CASE WHEN v_final_notes = '' THEN 'Registro Manual: Tardanza' ELSE 'Manual: ' || v_final_notes END;
        ELSE
            v_is_late := false;
            v_status := 'asistio';
            v_final_notes := CASE WHEN v_final_notes = '' THEN 'Registro Manual: Puntual' ELSE 'Manual: ' || v_final_notes END;
        END IF;
    ELSIF p_record_type = 'ABSENCE' THEN
        v_status := 'JUSTIFICADA';
    ELSE
        RETURN json_build_object('success', false, 'message', 'Tipo de registro inválido');
    END IF;

    -- Intentar insertar o actualizar (UPSERT)
    INSERT INTO public.attendance (
        employee_id,
        work_date,
        check_in,
        status,
        is_late,
        notes,
        evidence_url,
        record_type,
        created_at,
        absence_reason -- Solo si es absence
    ) VALUES (
        p_employee_id,
        p_work_date,
        CASE WHEN p_record_type = 'IN' THEN p_check_in ELSE NULL END,
        v_status,
        v_is_late,
        v_final_notes,
        p_evidence_url,
        CASE WHEN p_record_type = 'IN' THEN 'ASISTENCIA' ELSE 'INASISTENCIA' END,
        now(),
        CASE WHEN p_record_type = 'ABSENCE' THEN v_final_notes ELSE NULL END
    )
    ON CONFLICT (employee_id, work_date) 
    DO UPDATE SET
        check_in = EXCLUDED.check_in,
        status = EXCLUDED.status,
        is_late = EXCLUDED.is_late,
        notes = EXCLUDED.notes,
        evidence_url = EXCLUDED.evidence_url,
        record_type = EXCLUDED.record_type,
        absence_reason = EXCLUDED.absence_reason,
        updated_at = now();

    RETURN json_build_object('success', true, 'message', 'Registro manual guardado/actualizado exitosamente');

EXCEPTION WHEN OTHERS THEN
    RETURN json_build_object('success', false, 'message', 'Error interno: ' || SQLERRM);
END;
$function$;
