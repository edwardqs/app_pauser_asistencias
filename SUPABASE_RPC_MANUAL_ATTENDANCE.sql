-- ACTUALIZACIÓN DE RPC PARA REGISTRO MANUAL DE SUPERVISOR
-- Lógica:
-- 1. Solo admite 'IN' (Entrada) o 'ABSENCE' (Inasistencia). Salida eliminada.
-- 2. Calcula automáticamente si es TARDANZA basándose en la hora ingresada (Hora Perú).
-- 3. Recibe URL de evidencia.

CREATE OR REPLACE FUNCTION public.register_manual_attendance(
    p_employee_id uuid,
    p_supervisor_id uuid,
    p_work_date date,
    p_check_in timestamptz, -- Hora indicada por el supervisor
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
    -- Validar que el supervisor tenga permisos (opcional, por ahora confiamos en la app)
    
    -- Convertir el timestamp ingresado a Hora Perú para validar tardanza
    v_timestamp_peru := p_check_in AT TIME ZONE 'America/Lima';
    v_time_peru := v_timestamp_peru::time;
    v_final_notes := COALESCE(p_notes, '');

    -- Lógica según tipo
    IF p_record_type = 'IN' THEN
        -- Verificar Tardanza
        IF v_time_peru > c_late_limit THEN
            v_is_late := true;
            v_status := 'tardanza';
            v_final_notes := CASE WHEN v_final_notes = '' THEN 'Registro Manual: Tardanza' ELSE 'Manual: ' || v_final_notes END;
        ELSE
            v_is_late := false;
            v_status := 'asistio';
            v_final_notes := CASE WHEN v_final_notes = '' THEN 'Registro Manual: Puntual' ELSE 'Manual: ' || v_final_notes END;
        END IF;

        -- Insertar asistencia
        INSERT INTO public.attendance (
            employee_id,
            work_date,
            check_in,
            status,
            is_late,
            notes,
            evidence_url,
            record_type,
            created_at
            -- created_by  <-- Eliminado porque la columna no existe en la tabla attendance
        ) VALUES (
            p_employee_id,
            p_work_date,
            p_check_in,
            v_status,
            v_is_late,
            v_final_notes,
            p_evidence_url,
            'ASISTENCIA',
            now()
            -- p_supervisor_id
        );

    ELSIF p_record_type = 'ABSENCE' THEN
        -- Registrar Inasistencia
        INSERT INTO public.attendance (
            employee_id,
            work_date,
            status,
            notes,
            absence_reason,
            evidence_url,
            record_type,
            created_at
            -- created_by
        ) VALUES (
            p_employee_id,
            p_work_date,
            'JUSTIFICADA', -- Si lo registra el supervisor, se asume justificada/procesada
            v_final_notes,
            v_final_notes,
            p_evidence_url,
            'INASISTENCIA',
            now()
            -- p_supervisor_id
        );
        
    ELSE
        RETURN json_build_object('success', false, 'message', 'Tipo de registro inválido');
    END IF;

    RETURN json_build_object('success', true, 'message', 'Registro manual exitoso');

EXCEPTION WHEN OTHERS THEN
    RETURN json_build_object('success', false, 'message', 'Error interno: ' || SQLERRM);
END;
$function$;
