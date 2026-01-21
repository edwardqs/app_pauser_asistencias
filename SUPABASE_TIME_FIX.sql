-- Función RPC para registrar asistencia con hora segura del servidor
-- Parámetros: empleado, lat, lng, tipo ('IN' o 'OUT')

CREATE OR REPLACE FUNCTION public.register_attendance(
    p_employee_id uuid,
    p_lat double precision,
    p_lng double precision,
    p_type text
)
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_now_utc timestamp with time zone := now();
    v_now_peru timestamp with time zone := timezone('America/Lima', now()); -- Solo para referencia si se necesitara, pero guardamos en UTC
    v_today_date date;
    v_existing_attendance_id uuid;
BEGIN
    -- Calcular la fecha de trabajo basada en la hora de Perú (UTC-5)
    -- Esto asegura que si alguien marca a las 11 PM de Perú, siga siendo el mismo día
    v_today_date := (v_now_utc AT TIME ZONE 'America/Lima')::date;

    IF p_type = 'IN' THEN
        -- Verificar si ya existe un registro abierto para hoy (prevención de doble check-in)
        SELECT id INTO v_existing_attendance_id
        FROM public.attendance
        WHERE employee_id = p_employee_id 
          AND work_date = v_today_date
        LIMIT 1;

        IF v_existing_attendance_id IS NOT NULL THEN
            RETURN json_build_object('success', false, 'message', 'Ya existe un registro de asistencia para hoy.');
        END IF;

        -- Insertar nuevo registro
        INSERT INTO public.attendance (
            employee_id,
            work_date,
            check_in,
            location_in,
            status,
            notes
        ) VALUES (
            p_employee_id,
            v_today_date,
            v_now_utc, -- Se guarda el timestamp real del servidor (UTC)
            jsonb_build_object('lat', p_lat, 'lng', p_lng),
            'presente',
            'Ingreso vía App (Server Time)'
        );

        RETURN json_build_object('success', true, 'message', 'Entrada registrada correctamente');

    ELSIF p_type = 'OUT' THEN
        -- Buscar el registro activo de hoy (o del día correspondiente si trabaja de madrugada)
        -- Buscamos el último registro sin check_out
        SELECT id INTO v_existing_attendance_id
        FROM public.attendance
        WHERE (employee_id = p_employee_id OR id = p_employee_id) -- Soporta pasar ID de empleado o ID de asistencia
          AND check_out IS NULL
        ORDER BY check_in DESC
        LIMIT 1;

        IF v_existing_attendance_id IS NULL THEN
             RETURN json_build_object('success', false, 'message', 'No se encontró un registro de entrada pendiente.');
        END IF;

        -- Actualizar salida
        UPDATE public.attendance
        SET 
            check_out = v_now_utc,
            location_out = jsonb_build_object('lat', p_lat, 'lng', p_lng),
            status = 'completado'
        WHERE id = v_existing_attendance_id;

        RETURN json_build_object('success', true, 'message', 'Salida registrada correctamente');
    
    ELSE
        RETURN json_build_object('success', false, 'message', 'Tipo de operación inválida');
    END IF;

EXCEPTION WHEN OTHERS THEN
    RETURN json_build_object('success', false, 'message', SQLERRM);
END;
$$;

-- Permisos
GRANT EXECUTE ON FUNCTION public.register_attendance(uuid, double precision, double precision, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.register_attendance(uuid, double precision, double precision, text) TO service_role;
