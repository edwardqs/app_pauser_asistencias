-- =============================================================================
-- PASO 2: RPC UNIFICADO Y ROBUSTO: register_attendance (v4)
-- Multi-turno + Reglas de Negocio
-- =============================================================================
-- EJECUTAR ESTE SCRIPT EN EL SQL EDITOR DE SUPABASE
-- =============================================================================

-- 1. ELIMINAR VERSIONES ANTIGUAS DE LA FUNCIÓN PARA EVITAR EL ERROR 42725 (AMBIGÜEDAD) Y PGRST203 (SOBRECARGA)
DROP FUNCTION IF EXISTS public.register_attendance(uuid, double precision, double precision, text);
DROP FUNCTION IF EXISTS public.register_attendance(uuid, double precision, double precision, text, text, text);
DROP FUNCTION IF EXISTS public.register_attendance(uuid, double precision, double precision, text, text, text, text);

CREATE OR REPLACE FUNCTION public.register_attendance(
    p_employee_id uuid,
    p_lat double precision,
    p_lng double precision,
    p_type text,
    p_notes text DEFAULT NULL,
    p_evidence_url text DEFAULT NULL,
    p_shift text DEFAULT 'UNICO'
)
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_now_utc            timestamptz;
    v_now_peru           timestamp;
    v_today              date;
    v_isodow             int;
    v_attendance_id      uuid;
    v_existing_record    record;
    v_schedule           record;
    v_employee           record;

    v_is_late            boolean := false;
    v_has_bonus          boolean := false;
    v_status             text    := 'asistio';
    v_final_notes        text;
    v_overtime_minutes   int     := 0;

    v_late_limit         time;
    v_tolerance_mins     int;
    v_checkout_scheduled time;
    v_schedule_id        uuid;

    v_bonus_start        time;
    v_bonus_end          time;

    c_default_late_limit  time := '07:00:00';
    c_default_checkout    time := '17:00:00';
    c_default_tolerance   int  := 0;

    c_ot_positions        text[] := ARRAY[
        'AUXILIAR DE ALMACEN',
        'AUXILIAR DE ALMACÉN',
        'MONTACARGUISTA',
        'CONFERENTE',
        'COMPAGINADOR'
    ];

BEGIN
    -- 1. OBTENER TIEMPOS EN HORA PERU
    v_now_utc  := now();
    v_now_peru := v_now_utc AT TIME ZONE 'America/Lima';
    v_today    := v_now_peru::date;
    v_isodow   := EXTRACT(ISODOW FROM v_today)::int;
    v_final_notes := COALESCE(p_notes, '');

    -- 2. OBTENER INFORMACION DEL EMPLEADO
    SELECT business_unit, position
    INTO v_employee
    FROM public.employees
    WHERE id = p_employee_id;

    -- 3. OBTENER HORARIO ACTIVO DEL DIA Y TURNO
    SELECT ws.*
    INTO v_schedule
    FROM public.employee_schedule_assignments esa
    JOIN public.work_schedules ws ON ws.id = esa.schedule_id
    WHERE esa.employee_id = p_employee_id
      AND esa.valid_from <= v_today
      AND (esa.valid_to IS NULL OR esa.valid_to >= v_today)
      AND ws.is_active = true
      AND (ws.work_days IS NULL OR v_isodow = ANY(ws.work_days))
      AND ws.shift = p_shift
    ORDER BY
      CASE WHEN ws.schedule_type != 'REGULAR' THEN 0 ELSE 1 END,
      esa.valid_from DESC
    LIMIT 1;

    -- Valores con fallback
    IF v_schedule IS NOT NULL THEN
        v_late_limit         := v_schedule.check_in_time;
        v_tolerance_mins     := COALESCE(v_schedule.tolerance_minutes, c_default_tolerance);
        v_checkout_scheduled := v_schedule.check_out_time;
        v_schedule_id        := v_schedule.id;
    ELSE
        v_late_limit         := c_default_late_limit;
        v_tolerance_mins     := c_default_tolerance;
        v_checkout_scheduled := c_default_checkout;
        v_schedule_id        := NULL;
    END IF;

    v_bonus_end   := v_late_limit;
    v_bonus_start := v_late_limit - interval '10 minutes';

    -- 4. ASISTENCIA EXISTENTE HOY PARA ESTE TURNO
    SELECT * INTO v_existing_record
    FROM public.attendance
    WHERE employee_id = p_employee_id
      AND work_date = v_today
      AND shift = p_shift;

    -- =========================================================================
    -- ENTRADA (IN)
    -- =========================================================================
    IF p_type = 'IN' THEN

        IF v_existing_record IS NOT NULL THEN
            RETURN json_build_object('success', false, 'message', 'Ya registraste entrada para este turno hoy');
        END IF;

        IF v_now_peru::time > (v_late_limit + (v_tolerance_mins * interval '1 minute')) THEN
            v_is_late     := true;
            v_status      := 'tardanza';
            v_final_notes := CASE
                WHEN v_final_notes = ''
                THEN 'Ingreso con Tardanza (>' || to_char(v_late_limit, 'HH24:MI') || ')'
                ELSE 'Tardanza: ' || v_final_notes
            END;
        ELSE
            IF upper(COALESCE(v_employee.business_unit, '')) LIKE '%OPL%'
               AND v_now_peru::time >= v_bonus_start
               AND v_now_peru::time <= v_bonus_end
            THEN
                v_has_bonus   := true;
                v_final_notes := CASE
                    WHEN v_final_notes = '' THEN 'Puntual con Bono'
                    ELSE v_final_notes || ' (Bono)'
                END;
            END IF;
        END IF;

        INSERT INTO public.attendance (
            employee_id, work_date, check_in, location_in,
            status, is_late, notes, evidence_url,
            record_type, schedule_id, shift, created_at
        ) VALUES (
            p_employee_id, v_today, v_now_utc,
            jsonb_build_object('lat', p_lat, 'lng', p_lng),
            v_status, v_is_late, NULLIF(v_final_notes, ''),
            p_evidence_url, 'ASISTENCIA', v_schedule_id, p_shift, v_now_utc
        ) RETURNING id INTO v_attendance_id;

        RETURN json_build_object(
            'success',       true,
            'message',       'Entrada registrada correctamente',
            'time',          to_char(v_now_peru, 'HH24:MI'),
            'is_late',       v_is_late,
            'has_bonus',     v_has_bonus,
            'schedule_name', COALESCE(v_schedule.name, 'Sin horario asignado')
        );

    -- =========================================================================
    -- SALIDA (OUT)
    -- =========================================================================
    ELSIF p_type = 'OUT' THEN

        IF v_existing_record IS NULL THEN
            RETURN json_build_object('success', false, 'message', 'No has registrado entrada para este turno hoy');
        END IF;

        IF v_existing_record.check_out IS NOT NULL THEN
            RETURN json_build_object('success', false, 'message', 'Ya registraste la salida de este turno hoy');
        END IF;

        IF upper(COALESCE(v_employee.position, '')) = ANY(c_ot_positions)
           OR upper(COALESCE(v_employee.position, '')) LIKE '%AUXILIAR%ALMAC%'
        THEN
            IF v_now_peru::time > v_checkout_scheduled THEN
                v_overtime_minutes := GREATEST(0,
                    EXTRACT(EPOCH FROM (v_now_peru::time - v_checkout_scheduled))::int / 60
                );
            END IF;
        ELSE
            v_overtime_minutes := 0;
        END IF;

        UPDATE public.attendance
        SET
            check_out        = v_now_utc,
            location_out     = jsonb_build_object('lat', p_lat, 'lng', p_lng),
            overtime_minutes = v_overtime_minutes,
            schedule_id      = COALESCE(v_existing_record.schedule_id, v_schedule_id),
            notes            = CASE WHEN v_final_notes != '' THEN v_final_notes ELSE notes END,
            evidence_url     = COALESCE(p_evidence_url, evidence_url)
        WHERE id = v_existing_record.id;

        RETURN json_build_object(
            'success',          true,
            'message',          'Salida registrada correctamente',
            'time',             to_char(v_now_peru, 'HH24:MI'),
            'overtime_minutes', v_overtime_minutes,
            'scheduled_out',    to_char(v_checkout_scheduled, 'HH24:MI')
        );

     ELSE
         IF v_existing_record IS NOT NULL THEN
             RETURN json_build_object('success', false, 'message', 'Ya existe un registro para hoy (' || v_existing_record.record_type || ')');
         END IF;

         DECLARE
             v_final_type text := CASE WHEN p_type = 'ABSENCE' THEN 'AUSENCIA' ELSE p_type END;
         BEGIN
             INSERT INTO public.attendance (
                 employee_id, work_date, status, notes, absence_reason,
                 evidence_url, record_type, schedule_id, shift, created_at, location_in
             ) VALUES (
                 p_employee_id, v_today, 'PENDIENTE',
                 v_final_notes, v_final_notes, p_evidence_url,
                 v_final_type, v_schedule_id, p_shift, v_now_utc,
                 jsonb_build_object('lat', p_lat, 'lng', p_lng)
             ) RETURNING id INTO v_attendance_id;

             RETURN json_build_object(
                 'success',       true,
                 'message',       'Reporte registrado correctamente: ' || v_final_type,
                 'time',          to_char(v_now_peru, 'HH24:MI'),
                 'schedule_name', COALESCE(v_schedule.name, 'Sin horario asignado')
             );
         END;
     END IF;

EXCEPTION WHEN OTHERS THEN
    RETURN json_build_object('success', false, 'message', 'Error: ' || SQLERRM);
END;
$$;

-- Dar permisos de ejecución especificando la firma exacta para evitar el error 42725
GRANT EXECUTE ON FUNCTION public.register_attendance(uuid, double precision, double precision, text, text, text, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.register_attendance(uuid, double precision, double precision, text, text, text, text) TO anon;

