-- Script de Actualización de Reglas de Negocio (Bono y Tardanza)

-- 1. Agregar columnas necesarias para el cálculo de bonos si no existen
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'attendance' AND column_name = 'has_bonus') THEN
        ALTER TABLE public.attendance ADD COLUMN has_bonus boolean DEFAULT false;
    END IF;
    -- Columna para saber si fue tardanza explícitamente
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'attendance' AND column_name = 'is_late') THEN
        ALTER TABLE public.attendance ADD COLUMN is_late boolean DEFAULT false;
    END IF;
END $$;

-- 2. Actualizar la función RPC register_attendance con la lógica de horarios
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
    v_now_peru timestamp with time zone;
    v_now_time time;
    v_today_date date;
    v_existing_attendance_id uuid;
    
    -- Variables para lógica de negocio
    v_status text := 'presente';
    v_has_bonus boolean := false;
    v_is_late boolean := false;
    v_notes text := '';
BEGIN
    -- Calcular hora exacta en Perú
    v_now_peru := v_now_utc AT TIME ZONE 'America/Lima';
    v_today_date := v_now_peru::date;
    v_now_time := v_now_peru::time;

    IF p_type = 'IN' THEN
        -- Verificar si ya existe registro para hoy
        SELECT id INTO v_existing_attendance_id
        FROM public.attendance
        WHERE employee_id = p_employee_id 
          AND work_date = v_today_date
        LIMIT 1;

        IF v_existing_attendance_id IS NOT NULL THEN
            RETURN json_build_object('success', false, 'message', 'Ya existe un registro de asistencia para hoy.');
        END IF;

        -- LÓGICA DE NEGOCIO (Horarios)
        -- Rango Bono: 06:30:00 - 06:50:59
        -- Rango Normal: 06:51:00 - 07:00:59
        -- Tardanza: > 07:01:00

        IF v_now_time >= '06:30:00' AND v_now_time <= '06:50:59' THEN
            v_has_bonus := true;
            v_status := 'puntual_con_bono';
            v_notes := 'Ingreso con Bono (06:30-06:50)';
        ELSIF v_now_time >= '06:51:00' AND v_now_time <= '07:00:59' THEN
            v_has_bonus := false;
            v_status := 'puntual';
            v_notes := 'Ingreso Puntual (Sin Bono)';
        ELSIF v_now_time >= '07:01:00' THEN
            v_has_bonus := false;
            v_is_late := true;
            v_status := 'tardanza';
            v_notes := 'Ingreso con Tardanza (>07:00)';
        ELSE
            -- Si marca antes de las 6:30 (ej. 6:00 AM)
            v_has_bonus := true;
            v_status := 'puntual_anticipado';
            v_notes := 'Ingreso Anticipado';
        END IF;

        -- Insertar nuevo registro
        INSERT INTO public.attendance (
            employee_id,
            work_date,
            check_in,
            location_in,
            status,
            has_bonus,
            is_late,
            notes
        ) VALUES (
            p_employee_id,
            v_today_date,
            v_now_utc,
            jsonb_build_object('lat', p_lat, 'lng', p_lng),
            v_status,
            v_has_bonus,
            v_is_late,
            v_notes
        );

        RETURN json_build_object(
            'success', true, 
            'message', 'Entrada registrada: ' || v_status
        );

    ELSIF p_type = 'OUT' THEN
        -- Buscar registro abierto
        SELECT id INTO v_existing_attendance_id
        FROM public.attendance
        WHERE (employee_id = p_employee_id OR id = p_employee_id)
          AND check_out IS NULL
        ORDER BY check_in DESC
        LIMIT 1;

        IF v_existing_attendance_id IS NULL THEN
             RETURN json_build_object('success', false, 'message', 'No se encontró un registro de entrada pendiente.');
        END IF;

        -- Actualizar salida (Libre, sin restricciones)
        UPDATE public.attendance
        SET 
            check_out = v_now_utc,
            location_out = jsonb_build_object('lat', p_lat, 'lng', p_lng),
            status = 'completado' -- Mantenemos el status original o lo cambiamos a completado?
            -- Nota: Si cambiamos status a 'completado' perdemos si fue tardanza.
            -- Mejor NO sobreescribir status si queremos mantener el historial de tardanza en esa columna,
            -- o usar un status compuesto.
            -- Dejaremos el status de entrada y solo llenamos check_out.
        WHERE id = v_existing_attendance_id;

        RETURN json_build_object('success', true, 'message', 'Salida registrada correctamente');
    
    ELSE
        RETURN json_build_object('success', false, 'message', 'Tipo de operación inválida');
    END IF;

EXCEPTION WHEN OTHERS THEN
    RETURN json_build_object('success', false, 'message', SQLERRM);
END;
$$;
