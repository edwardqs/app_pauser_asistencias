-- Actualización de Lógica de Negocio de Asistencia
-- Nuevos horarios: 
-- 04:00 - 06:29: Normal
-- 06:30 - 06:50: Bono (Puntual con Bono)
-- 06:51 - 07:00: Normal (Puntual)
-- 07:01 - 18:00: Tardanza
-- > 18:00: Inasistencia (Manejado por UI/Lógica de Negocio, DB marca lo que reciba o cierra día)

CREATE OR REPLACE FUNCTION public.register_attendance(
    p_employee_id uuid,
    p_lat double precision,
    p_lng double precision,
    p_type text -- 'IN' o 'OUT'
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
    v_notes text := '';
    
    -- Horarios
    c_start_bonus time := '06:30:00';
    c_end_bonus time := '06:50:00';
    c_late_limit time := '07:00:00'; -- A partir de 07:01 es tardanza
    
BEGIN
    v_now_utc := now();
    v_now_peru := v_now_utc AT TIME ZONE 'America/Lima';
    v_today := v_now_peru::date;

    SELECT * INTO v_existing_record
    FROM public.attendance
    WHERE employee_id = p_employee_id
    AND work_date = v_today;

    IF p_type = 'IN' THEN
        IF v_existing_record IS NOT NULL THEN
             RETURN json_build_object('success', false, 'message', 'Ya registraste entrada hoy');
        END IF;

        -- Lógica de Tiempos
        IF v_now_peru::time > c_late_limit THEN
            v_is_late := true;
            v_status := 'tardanza';
            v_notes := 'Ingreso con Tardanza (>07:00)';
        ELSE
            -- Verificar Bono (06:30 - 06:50)
            IF v_now_peru::time >= c_start_bonus AND v_now_peru::time <= c_end_bonus THEN
                v_has_bonus := true;
                v_notes := 'Puntual con Bono';
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
            created_at
        ) VALUES (
            p_employee_id,
            v_today,
            v_now_utc,
            jsonb_build_object('lat', p_lat, 'lng', p_lng),
            v_status,
            v_is_late,
            v_has_bonus,
            v_notes,
            v_now_utc
        ) RETURNING id INTO v_attendance_id;

        RETURN json_build_object(
            'success', true, 
            'message', CASE WHEN v_has_bonus THEN '¡Entrada con Bono registrada!' ELSE 'Entrada registrada exitosamente' END,
            'time', to_char(v_now_peru, 'HH24:MI')
        );

    ELSIF p_type = 'OUT' THEN
        IF v_existing_record IS NULL THEN
            RETURN json_build_object('success', false, 'message', 'No has registrado entrada hoy');
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
        
    ELSE
        RETURN json_build_object('success', false, 'message', 'Tipo de registro inválido');
    END IF;

EXCEPTION WHEN OTHERS THEN
    RETURN json_build_object('success', false, 'message', 'Error interno: ' || SQLERRM);
END;
$function$;
