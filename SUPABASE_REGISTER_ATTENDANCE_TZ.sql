-- Función RPC robusta para registrar asistencia con hora de servidor (Perú)
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
    v_now_peru timestamp; -- Hora local sin zona horaria para cálculos de fecha/hora
    v_today date;
    v_attendance_id uuid;
    v_existing_record record;
    v_is_late boolean := false;
    v_has_bonus boolean := false;
    v_status text := 'asistio';
    v_notes text := '';
    
    -- Configuración de horarios (Idealmente debería venir de una tabla de configuración o del empleado)
    c_start_time time := '08:00:00';
    c_late_limit time := '08:15:00'; -- 15 minutos de tolerancia
    
BEGIN
    -- 1. Obtener hora actual real del servidor
    v_now_utc := now();
    
    -- 2. Convertir a hora Perú para cálculos de negocio (día laboral, tardanzas)
    -- AT TIME ZONE 'America/Lima' convierte el timestamptz a timestamp local de Perú
    v_now_peru := v_now_utc AT TIME ZONE 'America/Lima';
    v_today := v_now_peru::date;

    -- 3. Buscar si ya existe registro para HOY (Fecha Perú)
    SELECT * INTO v_existing_record
    FROM public.attendance
    WHERE employee_id = p_employee_id
    AND work_date = v_today;

    IF p_type = 'IN' THEN
        -- Validar si ya marcó entrada
        IF v_existing_record IS NOT NULL THEN
             RETURN json_build_object('success', false, 'message', 'Ya registraste entrada hoy');
        END IF;

        -- Calcular Tardanza (Comparando hora Perú)
        IF v_now_peru::time > c_start_time THEN
            v_is_late := true;
            v_status := 'tardanza';
            v_notes := 'Ingreso con Tardanza (>08:00)';
            
            -- Si pasó el límite de tolerancia, podría ser falta o requiere justificación (regla de negocio simple aquí)
        ELSE
            -- Bono de puntualidad (ejemplo: si llega antes de las 7:50)
            IF v_now_peru::time <= '07:50:00'::time THEN
                v_has_bonus := true;
            END IF;
        END IF;

        -- Insertar Nuevo Registro
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
            v_now_utc, -- Guardamos siempre en UTC estándar
            jsonb_build_object('lat', p_lat, 'lng', p_lng),
            v_status,
            v_is_late,
            v_has_bonus,
            v_notes,
            v_now_utc
        ) RETURNING id INTO v_attendance_id;

        RETURN json_build_object(
            'success', true, 
            'message', 'Entrada registrada exitosamente',
            'time', to_char(v_now_peru, 'HH24:MI')
        );

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
            check_out = v_now_utc, -- Guardamos UTC
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
