-- =============================================================================
-- RPC: register_attendance v2 - Con horarios dinámicos desde BD
-- =============================================================================
-- CAMBIOS vs versión anterior:
--   1. Consulta el horario activo del empleado en work_schedules
--   2. Usa check_in_time, bonus_start/end y tolerance_minutes del horario asignado
--   3. Calcula overtime_minutes al registrar salida
--   4. Guarda schedule_id en el registro de attendance
--   5. Fallback a hardcoded si el empleado no tiene horario asignado
--
-- PRE-REQUISITO: Ejecutar antes de este script:
--   ALTER TABLE public.attendance
--     ADD COLUMN IF NOT EXISTS overtime_minutes INT DEFAULT 0,
--     ADD COLUMN IF NOT EXISTS schedule_id UUID REFERENCES public.work_schedules(id) ON DELETE SET NULL;
-- =============================================================================

-- Paso 1: Agregar columnas si no existen
ALTER TABLE public.attendance
    ADD COLUMN IF NOT EXISTS overtime_minutes INT DEFAULT 0,
    ADD COLUMN IF NOT EXISTS schedule_id UUID REFERENCES public.work_schedules(id) ON DELETE SET NULL;

-- Paso 2: Reemplazar la función
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
    v_now_utc           timestamptz;
    v_now_peru          timestamp;
    v_today             date;
    v_attendance_id     uuid;
    v_existing_record   record;
    v_schedule          record;      -- Horario activo del empleado
    v_is_late           boolean := false;
    v_has_bonus         boolean := false;
    v_status            text := 'asistio';
    v_final_notes       text;
    v_overtime_minutes  int := 0;

    -- Variables de horario (con fallback a defaults hardcodeados)
    v_late_limit        time;
    v_tolerance_mins    int;
    v_bonus_start       time;
    v_bonus_end         time;
    v_checkout_scheduled time;
    v_schedule_id       uuid;

    -- Defaults hardcodeados (se usan si el empleado no tiene horario asignado)
    c_default_late_limit   time := '07:00:00';
    c_default_bonus_start  time := '06:30:00';
    c_default_bonus_end    time := '06:50:00';
    c_default_checkout     time := '17:00:00';
    c_default_tolerance    int  := 0;

BEGIN
    -- -------------------------------------------------------------------------
    -- 1. OBTENER FECHA Y HORA EN ZONA PERÚ
    -- -------------------------------------------------------------------------
    v_now_utc   := now();
    v_now_peru  := v_now_utc AT TIME ZONE 'America/Lima';
    v_today     := v_now_peru::date;

    v_final_notes := COALESCE(p_notes, '');

    -- -------------------------------------------------------------------------
    -- 2. BUSCAR HORARIO ACTIVO DEL EMPLEADO
    --    Prioridad: asignación individual > fallback hardcodeado
    -- -------------------------------------------------------------------------
    SELECT ws.*
    INTO v_schedule
    FROM public.employee_schedule_assignments esa
    JOIN public.work_schedules ws ON ws.id = esa.schedule_id
    WHERE esa.employee_id = p_employee_id
      AND esa.valid_from <= v_today
      AND (esa.valid_to IS NULL OR esa.valid_to >= v_today)
      AND ws.is_active = true
    ORDER BY esa.valid_from DESC
    LIMIT 1;

    -- Resolver valores a usar (schedule o fallback)
    IF v_schedule IS NOT NULL THEN
        v_late_limit         := v_schedule.check_in_time;
        v_tolerance_mins     := COALESCE(v_schedule.tolerance_minutes, c_default_tolerance);
        v_bonus_start        := COALESCE(v_schedule.bonus_start, c_default_bonus_start);
        v_bonus_end          := COALESCE(v_schedule.bonus_end, c_default_bonus_end);
        v_checkout_scheduled := v_schedule.check_out_time;
        v_schedule_id        := v_schedule.id;
    ELSE
        -- Sin horario asignado → usar defaults
        v_late_limit         := c_default_late_limit;
        v_tolerance_mins     := c_default_tolerance;
        v_bonus_start        := c_default_bonus_start;
        v_bonus_end          := c_default_bonus_end;
        v_checkout_scheduled := c_default_checkout;
        v_schedule_id        := NULL;
    END IF;

    -- -------------------------------------------------------------------------
    -- 3. BUSCAR REGISTRO EXISTENTE PARA HOY
    -- -------------------------------------------------------------------------
    SELECT * INTO v_existing_record
    FROM public.attendance
    WHERE employee_id = p_employee_id
      AND work_date = v_today;

    -- =========================================================================
    -- CASO 1: REGISTRO DE ENTRADA (IN)
    -- =========================================================================
    IF p_type = 'IN' THEN

        IF v_existing_record IS NOT NULL THEN
            RETURN json_build_object(
                'success', false,
                'message', 'Ya registraste asistencia hoy'
            );
        END IF;

        -- Evaluar tardanza (late_limit + tolerancia)
        IF v_now_peru::time > (v_late_limit + (v_tolerance_mins * interval '1 minute')) THEN
            v_is_late    := true;
            v_status     := 'tardanza';
            v_final_notes := CASE
                WHEN v_final_notes = ''
                THEN 'Ingreso con Tardanza (>' || to_char(v_late_limit, 'HH24:MI') || ')'
                ELSE 'Tardanza: ' || v_final_notes
            END;
        ELSE
            -- Evaluar bono de puntualidad
            IF v_bonus_start IS NOT NULL AND v_bonus_end IS NOT NULL
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
            employee_id,
            work_date,
            check_in,
            location_in,
            status,
            is_late,
            notes,
            evidence_url,
            record_type,
            schedule_id,
            created_at
        ) VALUES (
            p_employee_id,
            v_today,
            v_now_utc,
            jsonb_build_object('lat', p_lat, 'lng', p_lng),
            v_status,
            v_is_late,
            NULLIF(v_final_notes, ''),
            p_evidence_url,
            'ASISTENCIA',
            v_schedule_id,
            v_now_utc
        ) RETURNING id INTO v_attendance_id;

        RETURN json_build_object(
            'success',       true,
            'message',       'Entrada registrada correctamente',
            'time',          to_char(v_now_peru, 'HH24:MI'),
            'is_late',       v_is_late,
            'has_bonus',     v_has_bonus,
            'schedule_name', COALESCE(v_schedule.name, 'Horario por defecto')
        );

    -- =========================================================================
    -- CASO 2: REGISTRO DE SALIDA (OUT)
    -- =========================================================================
    ELSIF p_type = 'OUT' THEN

        IF v_existing_record IS NULL THEN
            RETURN json_build_object('success', false, 'message', 'No has registrado entrada hoy');
        END IF;

        IF v_existing_record.check_out IS NOT NULL THEN
            RETURN json_build_object('success', false, 'message', 'Ya registraste salida hoy');
        END IF;

        -- Calcular horas extras
        -- Solo se cuentan si la salida es DESPUÉS de la hora programada
        v_overtime_minutes := GREATEST(0,
            EXTRACT(EPOCH FROM (v_now_peru::time - v_checkout_scheduled))::int / 60
        );

        -- Protección: si la diferencia da negativa (salida anticipada), forzar 0
        IF v_now_peru::time < v_checkout_scheduled THEN
            v_overtime_minutes := 0;
        END IF;

        UPDATE public.attendance
        SET
            check_out        = v_now_utc,
            location_out     = jsonb_build_object('lat', p_lat, 'lng', p_lng),
            overtime_minutes = v_overtime_minutes,
            -- Actualizar schedule_id si no se guardó en la entrada
            schedule_id      = COALESCE(v_existing_record.schedule_id, v_schedule_id)
        WHERE id = v_existing_record.id;

        RETURN json_build_object(
            'success',          true,
            'message',          'Salida registrada exitosamente',
            'time',             to_char(v_now_peru, 'HH24:MI'),
            'overtime_minutes', v_overtime_minutes,
            'scheduled_out',    to_char(v_checkout_scheduled, 'HH24:MI')
        );

    -- =========================================================================
    -- CASO 3: REPORTAR INASISTENCIA (ABSENCE)
    -- =========================================================================
    ELSIF p_type = 'ABSENCE' THEN

        IF v_existing_record IS NOT NULL THEN
            RETURN json_build_object(
                'success', false,
                'message', 'Ya existe un registro de asistencia para hoy'
            );
        END IF;

        INSERT INTO public.attendance (
            employee_id,
            work_date,
            status,
            notes,
            absence_reason,
            evidence_url,
            record_type,
            schedule_id,
            created_at,
            location_in
        ) VALUES (
            p_employee_id,
            v_today,
            'PENDIENTE',
            v_final_notes,
            v_final_notes,
            p_evidence_url,
            'AUSENCIA',
            v_schedule_id,
            v_now_utc,
            jsonb_build_object('lat', p_lat, 'lng', p_lng)
        ) RETURNING id INTO v_attendance_id;

        RETURN json_build_object(
            'success', true,
            'message', 'Inasistencia reportada correctamente',
            'time',    to_char(v_now_peru, 'HH24:MI')
        );

    ELSE
        RETURN json_build_object('success', false, 'message', 'Tipo de registro inválido');
    END IF;

EXCEPTION WHEN OTHERS THEN
    RETURN json_build_object('success', false, 'message', 'Error interno: ' || SQLERRM);
END;
$function$;

-- =============================================================================
-- Verificación rápida
-- =============================================================================
SELECT routine_name, routine_type
FROM information_schema.routines
WHERE routine_schema = 'public'
  AND routine_name = 'register_attendance';
