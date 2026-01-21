-- ACTUALIZACIÓN FINAL V2 PARA REGISTRO MANUAL
-- Corrige:
-- 1. Tipo de registro 'INASISTENCIA' -> 'AUSENCIA' para consistencia con Web.
-- 2. Agrega soporte para ubicación (location_in).
-- 3. Mantiene lógica de tardanza y UPSERT.

CREATE OR REPLACE FUNCTION public.register_manual_attendance(
    p_employee_id uuid,
    p_supervisor_id uuid,
    p_work_date date,
    p_check_in timestamptz,
    p_record_type text,     -- 'IN' o 'ABSENCE'
    p_notes text DEFAULT NULL,
    p_evidence_url text DEFAULT NULL,
    p_is_late boolean DEFAULT false,
    p_location jsonb DEFAULT NULL -- Nuevo parámetro para ubicación
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
        -- Prioridad: Si la App dice que es tarde (p_is_late=true), es tarde.
        -- Si no, calculamos por hora.
        IF p_is_late OR v_time_peru > c_late_limit THEN
            v_is_late := true;
            v_status := 'tardanza';
            v_final_notes := CASE WHEN v_final_notes = '' THEN 'Registro Manual: Tardanza' ELSE 'Manual: ' || v_final_notes END;
        ELSE
            v_is_late := false;
            v_status := 'asistio'; -- 'asistio' o 'presente' o 'en_jornada' (Web usa badges check_in != null)
            v_final_notes := CASE WHEN v_final_notes = '' THEN 'Registro Manual: Puntual' ELSE 'Manual: ' || v_final_notes END;
        END IF;

        -- UPSERT (Insertar o Actualizar si existe conflicto)
        INSERT INTO public.attendance (
            employee_id,
            work_date,
            check_in,
            location_in, -- Insertamos ubicación
            status,
            is_late,
            notes,
            evidence_url,
            record_type,
            created_at,
            registered_by, -- Rastrear quién registró (auditoría básica)
            validated -- Auto-validado si lo hace un supervisor
        ) VALUES (
            p_employee_id,
            p_work_date,
            p_check_in,
            p_location,
            v_status,
            v_is_late,
            v_final_notes,
            p_evidence_url,
            'ASISTENCIA',
            now(),
            p_supervisor_id,
            true
        )
        ON CONFLICT (employee_id, work_date) 
        DO UPDATE SET
            check_in = EXCLUDED.check_in,
            location_in = EXCLUDED.location_in,
            status = EXCLUDED.status,
            is_late = EXCLUDED.is_late,
            notes = EXCLUDED.notes,
            evidence_url = EXCLUDED.evidence_url,
            record_type = EXCLUDED.record_type,
            registered_by = EXCLUDED.registered_by,
            validated = EXCLUDED.validated;

    ELSIF p_record_type = 'ABSENCE' OR p_record_type = 'INASISTENCIA' THEN
        -- Registrar Inasistencia (UPSERT)
        -- CORRECCIÓN: Usamos 'AUSENCIA' para que la Web lo reconozca (rojo)
        INSERT INTO public.attendance (
            employee_id,
            work_date,
            status,
            notes,
            absence_reason,
            evidence_url,
            record_type,
            created_at,
            registered_by,
            validated
        ) VALUES (
            p_employee_id,
            p_work_date,
            'ausente',
            v_final_notes,
            v_final_notes,
            p_evidence_url,
            'AUSENCIA', -- CORREGIDO: Antes era 'INASISTENCIA'
            now(),
            p_supervisor_id,
            true
        )
        ON CONFLICT (employee_id, work_date) 
        DO UPDATE SET
            status = EXCLUDED.status,
            notes = EXCLUDED.notes,
            absence_reason = EXCLUDED.absence_reason,
            evidence_url = EXCLUDED.evidence_url,
            record_type = EXCLUDED.record_type,
            registered_by = EXCLUDED.registered_by,
            validated = EXCLUDED.validated;
        
    ELSE
        RETURN json_build_object('success', false, 'message', 'Tipo de registro inválido: ' || p_record_type);
    END IF;

    RETURN json_build_object('success', true, 'message', 'Registro manual exitoso');

EXCEPTION WHEN OTHERS THEN
    RETURN json_build_object('success', false, 'message', 'Error interno: ' || SQLERRM);
END;
$function$;
