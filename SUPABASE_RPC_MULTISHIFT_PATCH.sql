-- =============================================================================
-- PATCH: Soporte multi-horario por día de semana en register_attendance
-- =============================================================================
-- Agrega filtro ISODOW al SELECT del horario activo, permitiendo que un
-- empleado tenga horarios distintos para distintos días (ej. L-J vs V).
-- Los horarios especiales (FERIADO/DOMINGO) tienen prioridad sobre REGULAR.
-- =============================================================================
-- INSTRUCCIONES: Copiar y pegar COMPLETO en Supabase → SQL Editor
-- =============================================================================

CREATE OR REPLACE FUNCTION public.register_attendance(
    p_employee_id   UUID,
    p_record_type   TEXT DEFAULT 'IN',
    p_notes         TEXT DEFAULT NULL,
    p_location      JSONB DEFAULT NULL,
    p_evidence_url  TEXT DEFAULT NULL
)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
AS $function$
DECLARE
    -- Constantes de fallback
    c_default_late_limit  TIME := '07:00:00';
    c_default_tolerance   INT  := 10;
    c_default_checkout    TIME := '17:00:00';
    c_ot_positions        TEXT[] := ARRAY[
        'AUXILIAR DE ALMACEN','AUXILIAR DE ALMACÉN',
        'MONTACARGUISTA','CONFERENTE','COMPAGINADOR'
    ];

    v_now_utc            TIMESTAMPTZ;
    v_now_peru           TIMESTAMP;
    v_today              DATE;
    v_isodow             INT;

    v_schedule           public.work_schedules%ROWTYPE;
    v_late_limit         TIME;
    v_tolerance_mins     INT;
    v_checkout_scheduled TIME;
    v_schedule_id        UUID;

    v_bonus_start        TIMESTAMPTZ;
    v_bonus_end          TIMESTAMPTZ;
    v_business_unit      TEXT;
    v_position           TEXT;
    v_has_bonus          BOOLEAN := false;
    v_is_late            BOOLEAN := false;

    v_existing_record    public.attendance%ROWTYPE;
    v_overtime_minutes   INT := 0;
BEGIN
    v_now_utc  := now();
    v_now_peru := v_now_utc AT TIME ZONE 'America/Lima';
    v_today    := v_now_peru::date;
    v_isodow   := EXTRACT(ISODOW FROM v_today)::int;  -- 1=Lun … 7=Dom

    -- -------------------------------------------------------------------------
    -- 1. DATOS DEL EMPLEADO
    -- -------------------------------------------------------------------------
    SELECT business_unit, position
    INTO   v_business_unit, v_position
    FROM   public.employees
    WHERE  id = p_employee_id;

    -- -------------------------------------------------------------------------
    -- 2. HORARIO ACTIVO DEL EMPLEADO — filtrado por día de semana
    --    Prioridad: horarios especiales (FERIADO/DOMINGO) sobre REGULAR
    -- -------------------------------------------------------------------------
    SELECT ws.*
    INTO   v_schedule
    FROM   public.employee_schedule_assignments esa
    JOIN   public.work_schedules ws ON ws.id = esa.schedule_id
    WHERE  esa.employee_id = p_employee_id
      AND  esa.valid_from  <= v_today
      AND  (esa.valid_to IS NULL OR esa.valid_to >= v_today)
      AND  ws.is_active = true
      -- Solo horarios cuyos días laborables incluyen el día de hoy
      AND  (ws.work_days IS NULL OR v_isodow = ANY(ws.work_days))
    ORDER BY
      -- Especiales primero (FERIADO/DOMINGO tienen prioridad)
      CASE WHEN ws.schedule_type != 'REGULAR' THEN 0 ELSE 1 END,
      esa.valid_from DESC
    LIMIT 1;

    -- Resolver valores (con fallback si no hay horario)
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

    -- Rango bono: 10 min antes de check_in_time (solo OPL)
    v_bonus_end   := (v_today::text || ' ' || v_late_limit::text)::timestamp AT TIME ZONE 'America/Lima';
    v_bonus_start := v_bonus_end - interval '10 minutes';

    -- -------------------------------------------------------------------------
    -- 3. BUSCAR REGISTRO EXISTENTE DE HOY
    -- -------------------------------------------------------------------------
    SELECT * INTO v_existing_record
    FROM   public.attendance
    WHERE  employee_id = p_employee_id
      AND  work_date   = v_today
    LIMIT 1;

    -- -------------------------------------------------------------------------
    -- 4. ENTRADA (IN)
    -- -------------------------------------------------------------------------
    IF p_record_type = 'IN' THEN

        IF v_existing_record.id IS NOT NULL THEN
            RETURN json_build_object(
                'success', false,
                'message', 'Ya existe un registro de entrada para hoy.'
            );
        END IF;

        -- Tardanza
        v_is_late := v_now_peru::time > (v_late_limit + (v_tolerance_mins || ' minutes')::interval);

        -- Bono OPL
        IF v_business_unit ILIKE '%OPL%' THEN
            v_has_bonus := v_now_utc >= v_bonus_start AND v_now_utc <= v_bonus_end;
        END IF;

        INSERT INTO public.attendance (
            employee_id, work_date, check_in, is_late, has_bonus,
            record_type, schedule_id, created_at, notes, evidence_url, location_in
        ) VALUES (
            p_employee_id, v_today, v_now_utc, v_is_late, v_has_bonus,
            'ASISTENCIA', v_schedule_id, v_now_utc, p_notes, p_evidence_url,
            p_location
        );

        RETURN json_build_object(
            'success',       true,
            'type',          'IN',
            'time',          to_char(v_now_peru, 'HH24:MI'),
            'is_late',       v_is_late,
            'has_bonus',     v_has_bonus,
            'schedule_name', COALESCE(v_schedule.name, 'Sin horario asignado')
        );

    -- -------------------------------------------------------------------------
    -- 5. SALIDA (OUT)
    -- -------------------------------------------------------------------------
    ELSIF p_record_type = 'OUT' THEN

        IF v_existing_record.id IS NULL THEN
            RETURN json_build_object(
                'success', false,
                'message', 'No hay registro de entrada para hoy.'
            );
        END IF;

        IF v_existing_record.check_out IS NOT NULL THEN
            RETURN json_build_object(
                'success', false,
                'message', 'Ya se registró la salida de hoy.'
            );
        END IF;

        -- Horas extras (solo cargos calificados)
        IF UPPER(TRIM(v_position)) = ANY(c_ot_positions) THEN
            DECLARE
                v_checkout_peru TIME;
                v_scheduled_mins INT;
                v_actual_mins    INT;
            BEGIN
                v_checkout_peru  := (v_now_utc AT TIME ZONE 'America/Lima')::time;
                v_scheduled_mins := EXTRACT(HOUR FROM v_checkout_scheduled)::int * 60
                                  + EXTRACT(MINUTE FROM v_checkout_scheduled)::int;
                v_actual_mins    := EXTRACT(HOUR FROM v_checkout_peru)::int * 60
                                  + EXTRACT(MINUTE FROM v_checkout_peru)::int;
                v_overtime_minutes := GREATEST(0, v_actual_mins - v_scheduled_mins);
            END;
        END IF;

        UPDATE public.attendance
        SET
            check_out        = v_now_utc,
            overtime_minutes = v_overtime_minutes,
            schedule_id      = COALESCE(v_existing_record.schedule_id, v_schedule_id),
            notes            = COALESCE(p_notes, notes),
            evidence_url     = COALESCE(p_evidence_url, evidence_url),
            location_out     = COALESCE(p_location, location_out)
        WHERE id = v_existing_record.id;

        RETURN json_build_object(
            'success',          true,
            'type',             'OUT',
            'time',             to_char(v_now_peru, 'HH24:MI'),
            'overtime_minutes', v_overtime_minutes,
            'scheduled_out',    to_char(v_checkout_scheduled, 'HH24:MI')
        );

    ELSE
        RETURN json_build_object('success', false, 'message', 'Tipo de registro inválido.');
    END IF;

EXCEPTION WHEN OTHERS THEN
    RETURN json_build_object('success', false, 'message', SQLERRM);
END;
$function$;
