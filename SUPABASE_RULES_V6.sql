-- ACTUALIZACIÓN DE REGLAS DE NEGOCIO V6 (Roles Específicos)

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
    v_employee_rec record;
    v_attendance_rec record;
    v_new_id uuid;
    v_now timestamp with time zone;
    v_today date;
    v_time time;
    v_is_late boolean := false;
    v_has_bonus boolean := false;
    v_status text := 'presente';
    
    -- Configuración de Horarios
    v_start_shift time := '04:00:00';    
    v_limit_bonus time := '06:50:00';    
    v_limit_on_time time := '07:00:00';  
    v_end_shift_limit time := '18:00:00'; 
BEGIN
    -- 1. Obtener datos del empleado y su ROL
    SELECT * INTO v_employee_rec FROM public.employees WHERE id = p_employee_id;
    
    IF v_employee_rec IS NULL THEN
        RETURN json_build_object('success', false, 'message', 'Empleado no encontrado');
    END IF;

    -- 2. Configurar tiempo (Zona Horaria Perú)
    v_now := now() AT TIME ZONE 'America/Lima';
    v_today := v_now::date;
    v_time := v_now::time;

    -- 3. Validaciones de Horario por ROL
    -- Lista de Roles PRIVILEGIADOS (Gestores)
    IF v_employee_rec.role NOT IN (
        'JEFE_VENTAS', 
        'SUPERVISOR_VENTAS', 
        'SUPERVISOR_OPERACIONES', 
        'COORDINADOR_OPERACIONES', 
        'SUPERVISOR' -- Genérico por compatibilidad
    ) THEN
        
        -- Reglas para TRABAJADORES (Vendedores, Choferes, Operarios)
        
        -- Validación A: Muy temprano
        IF v_time < v_start_shift THEN
            RETURN json_build_object('success', false, 'message', 'El sistema abre a las 04:00 AM');
        END IF;

        -- Validación B: Muy tarde (Bloqueo 6:01 PM) solo para Entrada
        IF p_type = 'IN' AND v_time > v_end_shift_limit THEN
            RETURN json_build_object('success', false, 'message', 'Sistema cerrado (Límite 06:00 PM). Contacte a su supervisor.');
        END IF;

    END IF;

    -- 4. Buscamos registro existente del día
    SELECT * INTO v_attendance_rec
    FROM public.attendance
    WHERE employee_id = p_employee_id 
      AND work_date = v_today
      AND record_type = 'ASISTENCIA';

    -- 5. Lógica de ENTRADA (IN)
    IF p_type = 'IN' THEN
        IF v_attendance_rec IS NOT NULL THEN
            RETURN json_build_object('success', false, 'message', 'Ya marcaste entrada hoy');
        END IF;

        -- Reglas de PUNTUALIDAD
        IF v_time <= v_limit_bonus THEN
            v_has_bonus := true;
        END IF;

        IF v_time > v_limit_on_time THEN
            v_is_late := true;
            v_status := 'tardanza';
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
            now(), 
            json_build_object('lat', p_lat, 'lng', p_lng), 
            v_is_late,
            v_has_bonus,
            v_status,
            'ASISTENCIA'
        ) RETURNING id INTO v_new_id;

        -- Auditoría
        INSERT INTO public.audit_logs (table_name, record_id, action, performed_by, details)
        VALUES ('attendance', v_new_id, 'CHECK_IN', p_employee_id, json_build_object('time', v_now, 'role', v_employee_rec.role));

        RETURN json_build_object(
            'success', true, 
            'id', v_new_id,
            'is_late', v_is_late,
            'status', v_status
        );

    -- 6. Lógica de SALIDA (OUT)
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
            location_out = json_build_object('lat', p_lat, 'lng', p_lng)
        WHERE id = v_attendance_rec.id;

        -- Auditoría
        INSERT INTO public.audit_logs (table_name, record_id, action, performed_by, details)
        VALUES ('attendance', v_attendance_rec.id, 'CHECK_OUT', p_employee_id, json_build_object('time', v_now));

        RETURN json_build_object(
            'success', true, 
            'id', v_attendance_rec.id
        );
    END IF;

    RETURN json_build_object('success', false, 'message', 'Tipo inválido');
END;
$function$;
