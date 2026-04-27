-- FIX: register_attendance - Manejar registros de inasistencia automática preexistentes
-- Problema: Si el cron de ausencias automáticas ya creó un registro para hoy,
-- el INSERT falla con "duplicate key value violates unique constraint idx_attendance_employee_date"
-- Solución: Si existe un registro de inasistencia, actualizarlo a asistencia en vez de insertar

CREATE OR REPLACE FUNCTION public.register_attendance(
    p_employee_id uuid,
    p_lat double precision,
    p_lng double precision,
    p_type text, -- 'IN', 'OUT', o cualquier motivo de absence_reasons
    p_notes text DEFAULT NULL,
    p_evidence_url text DEFAULT NULL
)
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
AS $function$
DECLARE
    v_now_utc timestamptz;
    v_now_peru timestamp;
    v_today date;
    v_attendance_id uuid;
    v_existing_record record;
    v_is_late boolean := false;
    v_has_bonus boolean := false;
    v_status text := 'asistio';
    v_final_notes text;

    -- Horarios
    c_start_bonus time := '06:30:00';
    c_end_bonus time := '06:50:00';
    c_late_limit time := '07:00:00';

BEGIN
    v_now_utc := now();
    v_now_peru := v_now_utc AT TIME ZONE 'America/Lima';
    v_today := v_now_peru::date;
    v_final_notes := COALESCE(p_notes, '');

    -- Buscamos si ya existe un registro para hoy
    SELECT * INTO v_existing_record
    FROM public.attendance
    WHERE employee_id = p_employee_id
    AND work_date = v_today;

    -- =========================================================================
    -- CASO 1: REGISTRO DE ENTRADA (IN)
    -- =========================================================================
    IF p_type = 'IN' THEN
        -- Si ya existe un registro de ASISTENCIA real (con check_in), no permitir duplicar
        IF v_existing_record IS NOT NULL AND v_existing_record.check_in IS NOT NULL THEN
             RETURN json_build_object('success', false, 'message', 'Ya registraste asistencia hoy');
        END IF;

        -- Lógica de Tiempos
        IF v_now_peru::time > c_late_limit THEN
            v_is_late := true;
            v_status := 'tardanza';
            v_final_notes := CASE WHEN v_final_notes = '' THEN 'Ingreso con Tardanza (>07:00)' ELSE 'Tardanza: ' || v_final_notes END;
        ELSE
            -- Verificar Bono (06:30 - 06:50)
            IF v_now_peru::time >= c_start_bonus AND v_now_peru::time <= c_end_bonus THEN
                v_has_bonus := true;
                v_final_notes := CASE WHEN v_final_notes = '' THEN 'Puntual con Bono' ELSE v_final_notes || ' (Bono)' END;
            END IF;
        END IF;

        -- Si existe un registro previo (inasistencia automática u otro sin check_in),
        -- actualizarlo en vez de insertar
        IF v_existing_record IS NOT NULL THEN
            UPDATE public.attendance SET
                check_in = v_now_utc,
                location_in = jsonb_build_object('lat', p_lat, 'lng', p_lng),
                status = v_status,
                is_late = v_is_late,
                has_bonus = v_has_bonus,
                notes = v_final_notes,
                evidence_url = COALESCE(p_evidence_url, evidence_url),
                record_type = 'ASISTENCIA'
            WHERE id = v_existing_record.id
            RETURNING id INTO v_attendance_id;
        ELSE
            INSERT INTO public.attendance (
                employee_id,
                work_date,
                check_in,
                location_in,
                status,
                is_late,
                has_bonus,
                notes,
                evidence_url,
                record_type,
                created_at
            ) VALUES (
                p_employee_id,
                v_today,
                v_now_utc,
                jsonb_build_object('lat', p_lat, 'lng', p_lng),
                v_status,
                v_is_late,
                v_has_bonus,
                v_final_notes,
                p_evidence_url,
                'ASISTENCIA',
                v_now_utc
            ) RETURNING id INTO v_attendance_id;
        END IF;

        RETURN json_build_object(
            'success', true,
            'message', CASE WHEN v_has_bonus THEN '¡Entrada con Bono registrada!' ELSE 'Entrada registrada exitosamente' END,
            'time', to_char(v_now_peru, 'HH24:MI')
        );

    -- =========================================================================
    -- CASO 2: REGISTRO DE SALIDA (OUT)
    -- =========================================================================
    ELSIF p_type = 'OUT' THEN
        IF v_existing_record IS NULL THEN
            RETURN json_build_object('success', false, 'message', 'No tienes entrada registrada hoy');
        END IF;

        IF v_existing_record.check_out IS NOT NULL THEN
            RETURN json_build_object('success', false, 'message', 'Ya registraste tu salida hoy');
        END IF;

        UPDATE public.attendance SET
            check_out = v_now_utc,
            location_out = jsonb_build_object('lat', p_lat, 'lng', p_lng)
        WHERE id = v_existing_record.id;

        RETURN json_build_object(
            'success', true,
            'message', 'Salida registrada exitosamente',
            'time', to_char(v_now_peru, 'HH24:MI')
        );

    -- =========================================================================
    -- CASO 3: OTROS TIPOS (Inasistencias manuales: ENFERMEDAD, PERMISO, etc.)
    -- =========================================================================
    ELSE
        IF v_existing_record IS NOT NULL THEN
            -- Si ya existe, actualizar el registro
            UPDATE public.attendance SET
                status = 'inasistencia',
                record_type = UPPER(TRIM(p_type)),
                notes = v_final_notes,
                evidence_url = COALESCE(p_evidence_url, evidence_url),
                location_in = jsonb_build_object('lat', p_lat, 'lng', p_lng)
            WHERE id = v_existing_record.id
            RETURNING id INTO v_attendance_id;
        ELSE
            INSERT INTO public.attendance (
                employee_id,
                work_date,
                status,
                record_type,
                notes,
                evidence_url,
                location_in,
                created_at
            ) VALUES (
                p_employee_id,
                v_today,
                'inasistencia',
                UPPER(TRIM(p_type)),
                v_final_notes,
                p_evidence_url,
                jsonb_build_object('lat', p_lat, 'lng', p_lng),
                v_now_utc
            ) RETURNING id INTO v_attendance_id;
        END IF;

        RETURN json_build_object(
            'success', true,
            'message', 'Registro guardado correctamente',
            'time', to_char(v_now_peru, 'HH24:MI')
        );
    END IF;

END;
$function$;
