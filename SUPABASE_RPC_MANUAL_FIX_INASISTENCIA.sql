-- ACTUALIZACIÓN DE RPC PARA REGISTRO MANUAL CON CORRECCIÓN DE TIPO 'INASISTENCIA'
-- Esta versión corrige el error: "Tipo de registro inválido" cuando la app envía 'INASISTENCIA' en lugar de 'ABSENCE'.

CREATE OR REPLACE FUNCTION public.register_manual_attendance(
    p_employee_id uuid,
    p_supervisor_id uuid,
    p_work_date date,
    p_check_in timestamptz,
    p_record_type text,     -- 'IN', 'ABSENCE' o 'INASISTENCIA'
    p_notes text DEFAULT NULL,
    p_evidence_url text DEFAULT NULL,
    p_is_late boolean DEFAULT false
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
    -- Aceptamos 'IN' para entradas
    IF p_record_type = 'IN' THEN
        -- Prioridad: Si la App dice que es tarde (p_is_late=true), es tarde.
        -- Si no, calculamos por hora.
        IF p_is_late OR v_time_peru > c_late_limit THEN
            v_is_late := true;
            v_status := 'tardanza';
            v_final_notes := CASE WHEN v_final_notes = '' THEN 'Registro Manual: Tardanza' ELSE 'Manual: ' || v_final_notes END;
        ELSE
            v_is_late := false;
            v_status := 'asistio';
            v_final_notes := CASE WHEN v_final_notes = '' THEN 'Registro Manual: Puntual' ELSE 'Manual: ' || v_final_notes END;
        END IF;

        -- UPSERT (Insertar o Actualizar si existe conflicto)
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
        )
        ON CONFLICT (employee_id, work_date) 
        DO UPDATE SET
            check_in = EXCLUDED.check_in,
            status = EXCLUDED.status,
            is_late = EXCLUDED.is_late,
            notes = EXCLUDED.notes,
            evidence_url = EXCLUDED.evidence_url,
            record_type = EXCLUDED.record_type;

    -- Aceptamos 'ABSENCE' O 'INASISTENCIA' (lo que envía la app)
    ELSIF p_record_type = 'ABSENCE' OR p_record_type = 'INASISTENCIA' THEN
        -- Registrar Inasistencia (UPSERT)
        INSERT INTO public.attendance (
            employee_id,
            work_date,
            status,
            notes,
            absence_reason,
            evidence_url,
            record_type,
            created_at
        ) VALUES (
            p_employee_id,
            p_work_date,
            'ausente',
            v_final_notes,
            v_final_notes,
            p_evidence_url,
            'INASISTENCIA',
            now()
        )
        ON CONFLICT (employee_id, work_date) 
        DO UPDATE SET
            status = EXCLUDED.status,
            notes = EXCLUDED.notes,
            absence_reason = EXCLUDED.absence_reason,
            evidence_url = EXCLUDED.evidence_url,
            record_type = EXCLUDED.record_type;
        
    ELSE
        RETURN json_build_object('success', false, 'message', 'Tipo de registro inválido: ' || p_record_type);
    END IF;

    RETURN json_build_object('success', true, 'message', 'Registro manual exitoso');

EXCEPTION WHEN OTHERS THEN
    RETURN json_build_object('success', false, 'message', 'Error interno: ' || SQLERRM);
END;
$function$;
