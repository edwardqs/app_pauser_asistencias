-- ACTUALIZACIÓN V5: Soporte para Tipos de Registro Genéricos (Motivos)
-- Permite que p_type sea cualquier valor (ej. 'ENFERMEDAD COMUN') y lo guarda como record_type

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
        IF v_existing_record IS NOT NULL THEN
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
            RETURN json_build_object('success', false, 'message', 'No has registrado entrada hoy');
        END IF;
        
        IF v_existing_record.record_type != 'ASISTENCIA' THEN
             RETURN json_build_object('success', false, 'message', 'No puedes marcar salida en un día con registro especial (' || v_existing_record.record_type || ')');
        END IF;

        IF v_existing_record.check_out IS NOT NULL THEN
            RETURN json_build_object('success', false, 'message', 'Ya registraste salida hoy');
        END IF;

        UPDATE public.attendance
        SET 
            check_out = v_now_utc,
            location_out = jsonb_build_object('lat', p_lat, 'lng', p_lng)
        WHERE id = v_existing_record.id;

        RETURN json_build_object(
            'success', true, 
            'message', 'Salida registrada exitosamente',
            'time', to_char(v_now_peru, 'HH24:MI')
        );

    -- =========================================================================
    -- CASO 3: REPORTAR MOTIVO/NOVEDAD (Cualquier otro tipo)
    -- =========================================================================
    ELSE
        IF v_existing_record IS NOT NULL THEN
             RETURN json_build_object('success', false, 'message', 'Ya existe un registro para hoy (' || v_existing_record.record_type || ')');
        END IF;

        -- Si el tipo es 'ABSENCE' (legacy), lo convertimos a 'AUSENCIA'
        -- Si no, usamos el valor exacto (ej. 'ENFERMEDAD COMUN')
        DECLARE
            v_final_type text := CASE WHEN p_type = 'ABSENCE' THEN 'AUSENCIA' ELSE p_type END;
        BEGIN
            INSERT INTO public.attendance (
                employee_id,
                work_date,
                status, 
                notes,
                absence_reason,
                evidence_url,
                record_type, -- Guardamos el tipo específico
                created_at,
                location_in
            ) VALUES (
                p_employee_id,
                v_today,
                'PENDIENTE', -- Pendiente de validación
                v_final_notes,
                v_final_notes,
                p_evidence_url,
                v_final_type,
                v_now_utc,
                jsonb_build_object('lat', p_lat, 'lng', p_lng)
            ) RETURNING id INTO v_attendance_id;

            RETURN json_build_object(
                'success', true, 
                'message', 'Reporte registrado correctamente: ' || v_final_type,
                'time', to_char(v_now_peru, 'HH24:MI')
            );
        END;
        
    END IF;

EXCEPTION WHEN OTHERS THEN
    RETURN json_build_object('success', false, 'message', 'Error interno: ' || SQLERRM);
END;
$function$;
