-- ELIMINAR VERSIONES ANTIGUAS DE LA FUNCIÓN
-- El error PGRST203 ocurre porque existen múltiples versiones de 'register_attendance'
-- y PostgREST no sabe cuál elegir. Debemos borrar TODAS y dejar solo la última.

-- 1. Borrar versión antigua (sin notas/evidencia)
DROP FUNCTION IF EXISTS public.register_attendance(uuid, double precision, double precision, text);

-- 2. Borrar versión nueva (por si acaso, para recrearla limpia)
DROP FUNCTION IF EXISTS public.register_attendance(uuid, double precision, double precision, text, text, text);

-- 3. RECREAR LA VERSIÓN DEFINITIVA (V3)
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

        IF v_now_peru::time > c_late_limit THEN
            v_is_late := true;
            v_status := 'tardanza';
            v_final_notes := CASE WHEN v_final_notes = '' THEN 'Ingreso con Tardanza (>07:00)' ELSE 'Tardanza: ' || v_final_notes END;
        ELSE
            IF v_now_peru::time >= c_start_bonus AND v_now_peru::time <= c_end_bonus THEN
                v_has_bonus := true;
                v_final_notes := CASE WHEN v_final_notes = '' THEN 'Puntual con Bono' ELSE v_final_notes || ' (Bono)' END;
            END IF;
        END IF;

        INSERT INTO public.attendance (
            employee_id, work_date, check_in, location_in, status, is_late, has_bonus, notes, evidence_url, record_type, created_at
        ) VALUES (
            p_employee_id, v_today, v_now_utc, jsonb_build_object('lat', p_lat, 'lng', p_lng),
            v_status, v_is_late, v_has_bonus, v_final_notes, p_evidence_url, 'ASISTENCIA', v_now_utc
        ) RETURNING id INTO v_attendance_id;

        RETURN json_build_object('success', true, 'message', CASE WHEN v_has_bonus THEN '¡Entrada con Bono registrada!' ELSE 'Entrada registrada exitosamente' END, 'time', to_char(v_now_peru, 'HH24:MI'));

    -- =========================================================================
    -- CASO 2: REGISTRO DE SALIDA (OUT) - DESHABILITADO POR REGLA DE NEGOCIO
    -- =========================================================================
    ELSIF p_type = 'OUT' THEN
        -- Simplemente informamos que ya no se requiere marcar salida.
        -- Podríamos lanzar error, pero 'success: true' con mensaje es más amigable si la app antigua lo llama.
        RETURN json_build_object('success', false, 'message', 'La salida ya no se registra en este sistema');

    -- =========================================================================
    -- CASO 3: REPORTAR INASISTENCIA (ABSENCE)
    -- =========================================================================
    ELSIF p_type = 'ABSENCE' THEN
        IF v_existing_record IS NOT NULL THEN RETURN json_build_object('success', false, 'message', 'Ya existe un registro para hoy'); END IF;

        INSERT INTO public.attendance (
            employee_id, work_date, status, notes, absence_reason, evidence_url, record_type, created_at
        ) VALUES (
            p_employee_id, v_today, 'PENDIENTE', v_final_notes, v_final_notes, p_evidence_url, 'INASISTENCIA', v_now_utc
        ) RETURNING id INTO v_attendance_id;

        RETURN json_build_object('success', true, 'message', 'Inasistencia reportada correctamente', 'time', to_char(v_now_peru, 'HH24:MI'));
        
    ELSE
        RETURN json_build_object('success', false, 'message', 'Tipo de registro inválido');
    END IF;

EXCEPTION WHEN OTHERS THEN
    RETURN json_build_object('success', false, 'message', 'Error interno: ' || SQLERRM);
END;
$function$;
