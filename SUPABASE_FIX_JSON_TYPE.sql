-- CORRECCIÓN DE TIPO JSONB V4
-- El error indicaba que location_out es JSONB, por lo que debemos insertar JSONB, no TEXT.

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
    v_attendance_rec record;
    v_new_id uuid;
    v_now timestamp with time zone;
    v_today date;
    v_time time;
    v_is_late boolean := false;
    v_has_bonus boolean := false;
    v_status text := 'presente';
    
    -- Configuración de Horarios
    v_start_time time := '04:00:00';     
    v_limit_bonus time := '06:50:00';    
    v_limit_on_time time := '07:00:00';  
BEGIN
    -- Forzamos zona horaria Perú
    v_now := now() AT TIME ZONE 'America/Lima';
    v_today := v_now::date;
    v_time := v_now::time;

    -- Buscamos registro existente
    SELECT * INTO v_attendance_rec
    FROM public.attendance
    WHERE employee_id = p_employee_id 
      AND work_date = v_today
      AND record_type = 'ASISTENCIA';

    IF p_type = 'IN' THEN
        IF v_attendance_rec IS NOT NULL THEN
            RETURN json_build_object('success', false, 'message', 'Ya marcaste entrada hoy');
        END IF;

        -- Reglas de Negocio
        IF v_time <= v_limit_bonus THEN
            v_has_bonus := true;
        END IF;

        IF v_time > v_limit_on_time THEN
            v_is_late := true;
            v_status := 'falta'; 
        END IF;

        INSERT INTO public.attendance (
            employee_id, 
            work_date, 
            check_in, 
            location_in, -- Es JSONB
            is_late,
            has_bonus,
            status,
            record_type
        ) VALUES (
            p_employee_id,
            v_today,
            now(), 
            json_build_object('lat', p_lat, 'lng', p_lng), -- CORREGIDO: Sin ::text
            v_is_late,
            v_has_bonus,
            v_status,
            'ASISTENCIA'
        ) RETURNING id INTO v_new_id;

        RETURN json_build_object(
            'success', true, 
            'id', v_new_id,
            'is_late', v_is_late,
            'status', v_status
        );

    ELSIF p_type = 'OUT' THEN
        IF v_attendance_rec IS NULL THEN
            RETURN json_build_object('success', false, 'message', 'No has marcado entrada');
        END IF;

        IF v_attendance_rec.check_out IS NOT NULL THEN
            RETURN json_build_object('success', false, 'message', 'Ya marcaste salida');
        END IF;

        UPDATE public.attendance
        SET 
            check_out = now(),
            location_out = json_build_object('lat', p_lat, 'lng', p_lng) -- CORREGIDO: Sin ::text
        WHERE id = v_attendance_rec.id;

        RETURN json_build_object(
            'success', true, 
            'id', v_attendance_rec.id
        );
    END IF;

    RETURN json_build_object('success', false, 'message', 'Tipo inválido');
END;
$function$;
