-- FIX: MANUAL ATTENDANCE LOGIC
-- Asegura que si la hora es > 07:00, se marque como is_late = TRUE explícitamente
-- Y actualiza el status acorde.

CREATE OR REPLACE FUNCTION public.register_manual_attendance(
    p_employee_id uuid,
    p_supervisor_id uuid,
    p_work_date date,
    p_check_in timestamptz,
    p_record_type text,
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
    c_late_limit time := '07:00:00';
BEGIN
    -- Forzar zona horaria Perú para la validación de hora
    v_timestamp_peru := p_check_in AT TIME ZONE 'America/Lima';
    v_time_peru := v_timestamp_peru::time;
    v_final_notes := COALESCE(p_notes, '');

    IF p_record_type = 'IN' THEN
        IF v_time_peru > c_late_limit THEN
            v_is_late := true;
            v_status := 'tardanza';
        ELSE
            v_is_late := false;
            v_status := 'asistio'; -- 'asistio' es el valor interno estándar, el RPC de lectura lo interpreta
        END IF;

        -- UPSERT (Insert or Update)
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

    ELSIF p_record_type = 'INASISTENCIA' THEN
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
            'JUSTIFICADA',
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
    END IF;

    RETURN json_build_object('success', true, 'message', 'Registro manual exitoso');
END;
$function$;
