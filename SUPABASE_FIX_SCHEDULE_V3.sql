-- ACTUALIZACIÓN DE HORARIOS V3
-- Reglas:
-- 1. Ingreso válido: 04:00 AM - 07:00 AM
-- 2. > 07:00 AM: Se permite marcar pero se considera FALTA (status='falta') y TARDANZA (is_late=true)
-- 3. Bonos intactos (asumimos regla anterior, ej. < 06:50 o < 07:00)

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
    v_start_time time := '04:00:00';     -- Inicio de jornada
    v_limit_bonus time := '06:50:00';    -- Límite para bono (Ajustar si es diferente)
    v_limit_on_time time := '07:00:00';  -- Límite de puntualidad
BEGIN
    -- Forzamos zona horaria Perú
    v_now := now() AT TIME ZONE 'America/Lima';
    v_today := v_now::date;
    v_time := v_now::time;

    -- Validar que no sea demasiado temprano (antes de las 4 AM)
    -- Opcional: Si quieres bloquear ingresos de madrugada.
    -- IF v_time < v_start_time THEN
    --     RETURN json_build_object('success', false, 'message', 'Aún no inicia el turno (04:00 AM)');
    -- END IF;

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
        
        -- 1. Bono
        IF v_time <= v_limit_bonus THEN
            v_has_bonus := true;
        END IF;

        -- 2. Tardanza / Falta (> 07:00 AM)
        IF v_time > v_limit_on_time THEN
            v_is_late := true;
            v_status := 'falta'; -- Se automarca como falta según requerimiento
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
            now(), -- UTC
            json_build_object('lat', p_lat, 'lng', p_lng)::text,
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
