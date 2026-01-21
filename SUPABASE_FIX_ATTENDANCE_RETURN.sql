-- Actualizar la función register_attendance para retornar el ID del registro creado
-- Esto es crucial para poder actualizar el campo 'notes' con la justificación de tardanza inmediatamente después.

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
    v_schedule_start time := '08:00:00'; -- Hora entrada estándar
    v_limit_bonus time := '07:50:00';    -- Límite para bono
    v_limit_late time := '08:00:00';     -- Límite para tardanza (tolerancia 0)
BEGIN
    -- Forzamos zona horaria Perú para cálculos
    v_now := now() AT TIME ZONE 'America/Lima';
    v_today := v_now::date;
    v_time := v_now::time;

    -- Buscamos registro existente del día
    SELECT * INTO v_attendance_rec
    FROM public.attendance
    WHERE employee_id = p_employee_id 
      AND work_date = v_today
      AND record_type = 'ASISTENCIA'; -- Solo buscar asistencias normales

    IF p_type = 'IN' THEN
        IF v_attendance_rec IS NOT NULL THEN
            RETURN json_build_object('success', false, 'message', 'Ya marcaste entrada hoy');
        END IF;

        -- Reglas de Negocio
        IF v_time > v_limit_late THEN
            v_is_late := true;
        END IF;

        IF v_time <= v_limit_bonus THEN
            v_has_bonus := true;
        END IF;

        INSERT INTO public.attendance (
            employee_id, 
            work_date, 
            check_in, 
            location_in,
            is_late,
            has_bonus,
            status,
            record_type
        ) VALUES (
            p_employee_id,
            v_today,
            now(), -- Guardamos UTC real en la DB
            json_build_object('lat', p_lat, 'lng', p_lng)::text,
            v_is_late,
            v_has_bonus,
            'presente',
            'ASISTENCIA'
        ) RETURNING id INTO v_new_id;

        RETURN json_build_object(
            'success', true, 
            'id', v_new_id, -- RETORNAMOS EL ID
            'is_late', v_is_late,
            'has_bonus', v_has_bonus
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
            location_out = json_build_object('lat', p_lat, 'lng', p_lng)::text
        WHERE id = v_attendance_rec.id;

        RETURN json_build_object(
            'success', true, 
            'id', v_attendance_rec.id
        );
    END IF;

    RETURN json_build_object('success', false, 'message', 'Tipo inválido');
END;
$function$;
