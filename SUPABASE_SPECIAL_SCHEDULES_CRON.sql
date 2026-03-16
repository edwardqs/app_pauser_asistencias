-- =============================================================================
-- HORARIOS ESPECIALES: Funciones de auto-actualización + Faltas justificadas
-- =============================================================================
-- PREREQUISITO: Haber ejecutado SUPABASE_HOLIDAYS_SETUP.sql primero
-- =============================================================================
-- INSTRUCCIONES:
--   Ejecutar este archivo COMPLETO en Supabase → SQL Editor
--   Pasos:
--     A. Función: obtener próximo feriado
--     B. Función: obtener próximo domingo
--     C. Función: actualizar target_date de horarios especiales (cron diario)
--     D. Función: marcar faltas justificadas por feriado (cron fin de día)
--     E. Programar ambos cron jobs
-- =============================================================================


-- =============================================================================
-- PASO A: Próximo feriado peruano desde hoy
-- =============================================================================
CREATE OR REPLACE FUNCTION public.get_next_holiday()
RETURNS TABLE(holiday_date DATE, holiday_name TEXT)
LANGUAGE sql
STABLE
AS $$
    SELECT date, name
    FROM   public.peru_holidays
    WHERE  date >= CURRENT_DATE
    ORDER  BY date ASC
    LIMIT  1;
$$;

-- Test: SELECT * FROM public.get_next_holiday();


-- =============================================================================
-- PASO B: Próximo domingo desde hoy
-- Si hoy es domingo, devuelve el domingo de la semana que viene
-- =============================================================================
CREATE OR REPLACE FUNCTION public.get_next_sunday()
RETURNS DATE
LANGUAGE sql
STABLE
AS $$
    SELECT (
        CURRENT_DATE + (
            CASE
                WHEN EXTRACT(ISODOW FROM CURRENT_DATE)::int = 7 THEN 7   -- hoy es domingo → próximo domingo
                ELSE 7 - EXTRACT(ISODOW FROM CURRENT_DATE)::int           -- días que faltan
            END
        )
    )::date;
$$;

-- Test: SELECT public.get_next_sunday();


-- =============================================================================
-- PASO C: Actualizar target_date de horarios especiales vencidos
-- Se llama desde el cron diario a medianoche Peru (05:10 UTC)
-- =============================================================================
CREATE OR REPLACE FUNCTION public.update_special_schedule_targets()
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
AS $function$
DECLARE
    v_today             DATE;
    v_next_hol_date     DATE;
    v_next_hol_name     TEXT;
    v_next_sunday       DATE;
    v_count_feriado     INT := 0;
    v_count_domingo     INT := 0;
BEGIN
    v_today := (now() AT TIME ZONE 'America/Lima')::date;

    -- Obtener próximo feriado
    SELECT holiday_date, holiday_name
    INTO   v_next_hol_date, v_next_hol_name
    FROM   public.get_next_holiday();

    -- Obtener próximo domingo
    SELECT public.get_next_sunday() INTO v_next_sunday;

    -- Actualizar horarios FERIADO cuyo target_date ya pasó o es NULL
    UPDATE public.work_schedules
    SET
        target_date  = v_next_hol_date,
        holiday_name = v_next_hol_name
    WHERE schedule_type = 'FERIADO'
      AND (target_date IS NULL OR target_date < v_today);

    GET DIAGNOSTICS v_count_feriado = ROW_COUNT;

    -- Actualizar horarios DOMINGO cuyo target_date ya pasó o es NULL
    UPDATE public.work_schedules
    SET
        target_date  = v_next_sunday,
        holiday_name = 'Domingo ' || TO_CHAR(v_next_sunday, 'DD/MM/YYYY')
    WHERE schedule_type = 'DOMINGO'
      AND (target_date IS NULL OR target_date < v_today);

    GET DIAGNOSTICS v_count_domingo = ROW_COUNT;

    RETURN json_build_object(
        'success',           true,
        'updated_feriado',   v_count_feriado,
        'updated_domingo',   v_count_domingo,
        'next_holiday_date', v_next_hol_date,
        'next_holiday_name', v_next_hol_name,
        'next_sunday',       v_next_sunday,
        'run_at',            to_char(now() AT TIME ZONE 'America/Lima', 'YYYY-MM-DD HH24:MI:SS')
    );

EXCEPTION WHEN OTHERS THEN
    RETURN json_build_object('success', false, 'message', SQLERRM);
END;
$function$;

-- Test manual: SELECT public.update_special_schedule_targets();


-- =============================================================================
-- PASO D: Marcar faltas justificadas automáticamente al final del día feriado
-- Lógica:
--   1. ¿Hoy (hora Peru) es feriado?
--   2. Para cada empleado con horario REGULAR activo y ese día en work_days:
--      - ¿No tiene asignación especial (FERIADO) para hoy?
--      - ¿No tiene registro de asistencia hoy?
--      → Insertar FALTA_JUSTIFICADA con motivo "Feriado: {nombre}"
-- =============================================================================
CREATE OR REPLACE FUNCTION public.auto_mark_holiday_absences()
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
AS $function$
DECLARE
    v_today         DATE;
    v_holiday_name  TEXT;
    v_isodow        INT;
    v_count         INT := 0;
    rec             RECORD;
BEGIN
    v_today  := (now() AT TIME ZONE 'America/Lima')::date;
    v_isodow := EXTRACT(ISODOW FROM v_today)::int;

    -- ¿Hoy es feriado?
    SELECT name INTO v_holiday_name
    FROM   public.peru_holidays
    WHERE  date = v_today;

    IF v_holiday_name IS NULL THEN
        RETURN json_build_object(
            'success',   true,
            'processed', 0,
            'reason',    'Hoy no es feriado — sin acción'
        );
    END IF;

    -- Empleados con horario REGULAR activo hoy, en su día laboral,
    -- sin asignación especial para hoy, sin registro de asistencia hoy
    FOR rec IN
        SELECT DISTINCT ON (esa.employee_id)
            esa.employee_id,
            ws.id AS schedule_id
        FROM  public.employee_schedule_assignments esa
        JOIN  public.work_schedules ws ON ws.id = esa.schedule_id
        WHERE ws.schedule_type = 'REGULAR'
          AND esa.valid_from  <= v_today
          AND (esa.valid_to IS NULL OR esa.valid_to >= v_today)
          -- Hoy es un día laboral de este horario
          AND (ws.work_days IS NULL OR v_isodow = ANY(ws.work_days))
          -- Sin asignación especial para hoy
          AND NOT EXISTS (
              SELECT 1
              FROM   public.employee_schedule_assignments esa2
              JOIN   public.work_schedules ws2 ON ws2.id = esa2.schedule_id
              WHERE  esa2.employee_id = esa.employee_id
                AND  ws2.schedule_type IN ('FERIADO', 'DOMINGO')
                AND  esa2.valid_from = v_today
                AND  esa2.valid_to   = v_today
          )
          -- Sin registro de asistencia hoy
          AND NOT EXISTS (
              SELECT 1
              FROM   public.attendance a
              WHERE  a.employee_id = esa.employee_id
                AND  a.work_date   = v_today
          )
        ORDER BY esa.employee_id, esa.valid_from DESC
    LOOP
        INSERT INTO public.attendance (
            employee_id,
            work_date,
            record_type,
            status,
            notes,
            schedule_id,
            overtime_minutes
        ) VALUES (
            rec.employee_id,
            v_today,
            'FALTA_JUSTIFICADA',
            'APROBADO',
            'Feriado: ' || v_holiday_name,
            rec.schedule_id,
            0
        );

        v_count := v_count + 1;
    END LOOP;

    RETURN json_build_object(
        'success',   true,
        'processed', v_count,
        'holiday',   v_holiday_name,
        'date',      v_today,
        'run_at',    to_char(now() AT TIME ZONE 'America/Lima', 'YYYY-MM-DD HH24:MI:SS')
    );

EXCEPTION WHEN OTHERS THEN
    RETURN json_build_object('success', false, 'message', SQLERRM);
END;
$function$;

-- Test manual: SELECT public.auto_mark_holiday_absences();


-- =============================================================================
-- PASO E: Programar los cron jobs
-- =============================================================================

-- ── Cron 1: Actualizar target_date — medianoche Peru (05:10 UTC) ─────────────
DO $$
BEGIN
    PERFORM cron.unschedule('update-special-schedule-targets');
EXCEPTION WHEN OTHERS THEN NULL;
END;
$$;

SELECT cron.schedule(
    'update-special-schedule-targets',
    '10 5 * * *',   -- 00:10 hora Peru (UTC-5)
    $$SELECT public.update_special_schedule_targets()$$
);

-- ── Cron 2: Faltas justificadas por feriado — 23:05 Peru (04:05 UTC) ─────────
DO $$
BEGIN
    PERFORM cron.unschedule('auto-holiday-absences');
EXCEPTION WHEN OTHERS THEN NULL;
END;
$$;

SELECT cron.schedule(
    'auto-holiday-absences',
    '5 4 * * *',    -- 23:05 hora Peru (UTC-5)
    $$SELECT public.auto_mark_holiday_absences()$$
);

-- Verificar todos los cron jobs activos
SELECT jobid, jobname, schedule, active
FROM   cron.job
ORDER  BY jobname;


-- =============================================================================
-- PASO F: Inicializar target_date en horarios especiales existentes (si hubiera)
-- Ejecutar manualmente tras crear los primeros horarios FERIADO/DOMINGO
-- =============================================================================
-- SELECT public.update_special_schedule_targets();


-- =============================================================================
-- NOTA IMPORTANTE — record_type en tabla attendance
-- =============================================================================
-- Si la tabla attendance tiene un CHECK constraint en record_type
-- que solo permite 'ASISTENCIA' y 'AUSENCIA', agregar el nuevo valor:
--
-- ALTER TABLE public.attendance
--     DROP CONSTRAINT IF EXISTS attendance_record_type_check;
--
-- ALTER TABLE public.attendance
--     ADD CONSTRAINT attendance_record_type_check
--     CHECK (record_type IN ('ASISTENCIA', 'AUSENCIA', 'FALTA_JUSTIFICADA'));
-- =============================================================================
