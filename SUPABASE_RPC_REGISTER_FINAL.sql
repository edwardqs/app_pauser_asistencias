-- =============================================================================
-- FUNCIÓN MAESTRA DE REGISTRO DE ASISTENCIA (FINAL CON ZONA HORARIA)
-- =============================================================================
-- Esta función maneja:
-- 1. Zona Horaria: Convierte UTC a 'America/Lima' para determinar la fecha 'v_today'.
-- 2. Ubicación: Guarda lat/lng en jsonb.
-- 3. Reglas: Verifica duplicados por fecha (work_date).
-- 4. Tipos: 'IN', 'OUT', 'ABSENCE'.

CREATE OR REPLACE FUNCTION public.register_attendance(
    p_employee_id uuid,
    p_lat double precision,
    p_lng double precision,
    p_type text, -- 'IN', 'OUT', o 'ABSENCE'
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
    v_record_type text := 'ASISTENCIA';
    v_final_notes text;
    
    -- Horarios (Configurables aquí)
    c_start_bonus time := '06:30:00';
    c_end_bonus time := '06:50:00';
    c_late_limit time := '07:00:00'; -- A partir de 07:01 es tardanza
    
BEGIN
    -- 1. OBTENER FECHA Y HORA CORRECTA (PERÚ)
    v_now_utc := now(); -- Hora del servidor (UTC)
    v_now_peru := v_now_utc AT TIME ZONE 'America/Lima'; -- Hora Perú
    v_today := v_now_peru::date; -- Fecha Perú (Esto es lo que se guarda en work_date)
    
    v_final_notes := COALESCE(p_notes, '');

    -- 2. BUSCAR REGISTRO EXISTENTE PARA "HOY" (FECHA PERÚ)
    SELECT * INTO v_existing_record
    FROM public.attendance
    WHERE employee_id = p_employee_id
    AND work_date = v_today; -- Compara DATE con DATE

    -- =========================================================================
    -- CASO 1: REGISTRO DE ENTRADA (IN)
    -- =========================================================================
    IF p_type = 'IN' THEN
        IF v_existing_record IS NOT NULL THEN
             RETURN json_build_object('success', false, 'message', 'Ya registraste asistencia hoy');
        END IF;

        -- Evaluar Tardanza (Usando Hora Perú)
        IF v_now_peru::time > c_late_limit THEN
            v_is_late := true;
            v_status := 'tardanza';
            v_final_notes := CASE WHEN v_final_notes = '' THEN 'Ingreso con Tardanza (>07:00)' ELSE 'Tardanza: ' || v_final_notes END;
        ELSE
            -- Evaluar Bono
            IF v_now_peru::time >= c_start_bonus AND v_now_peru::time <= c_end_bonus THEN
                v_has_bonus := true;
                v_final_notes := CASE WHEN v_final_notes = '' THEN 'Puntual con Bono' ELSE v_final_notes || ' (Bono)' END;
            END IF;
        END IF;

        INSERT INTO public.attendance (
            employee_id,
            work_date,      -- Fecha Perú
            check_in,       -- Timestamp UTC (Estándar para apps)
            location_in,
            status,
            is_late,
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
            v_final_notes,
            p_evidence_url,
            'ASISTENCIA',
            v_now_utc
        ) RETURNING id INTO v_attendance_id;

        RETURN json_build_object(
            'success', true, 
            'message', 'Entrada registrada correctamente',
            'time', to_char(v_now_peru, 'HH24:MI')
        );

    -- =========================================================================
    -- CASO 2: REGISTRO DE SALIDA (OUT)
    -- =========================================================================
    ELSIF p_type = 'OUT' THEN
        -- Validar si existe entrada
        IF v_existing_record IS NULL THEN
            RETURN json_build_object('success', false, 'message', 'No has registrado entrada hoy');
        END IF;

        -- Validar si ya marcó salida
        IF v_existing_record.check_out IS NOT NULL THEN
            RETURN json_build_object('success', false, 'message', 'Ya registraste salida hoy');
        END IF;

        -- Actualizar Registro con Salida
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
    -- CASO 3: REPORTAR INASISTENCIA (ABSENCE)
    -- =========================================================================
    ELSIF p_type = 'ABSENCE' THEN
        IF v_existing_record IS NOT NULL THEN
             RETURN json_build_object('success', false, 'message', 'Ya existe un registro de asistencia para hoy');
        END IF;

        INSERT INTO public.attendance (
            employee_id,
            work_date,
            status,
            notes,
            absence_reason,
            evidence_url,
            record_type,
            created_at,
            location_in
        ) VALUES (
            p_employee_id,
            v_today,
            'PENDIENTE', -- Pendiente de validación
            v_final_notes,
            v_final_notes,
            p_evidence_url,
            'AUSENCIA',
            v_now_utc,
            jsonb_build_object('lat', p_lat, 'lng', p_lng)
        ) RETURNING id INTO v_attendance_id;

        RETURN json_build_object(
            'success', true, 
            'message', 'Inasistencia reportada correctamente',
            'time', to_char(v_now_peru, 'HH24:MI')
        );
        
    ELSE
        RETURN json_build_object('success', false, 'message', 'Tipo de registro inválido');
    END IF;

EXCEPTION WHEN OTHERS THEN
    RETURN json_build_object('success', false, 'message', 'Error interno: ' || SQLERRM);
END;
$function$;
