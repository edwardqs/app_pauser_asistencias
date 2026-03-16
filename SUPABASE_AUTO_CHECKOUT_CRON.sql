-- =============================================================================
-- AUTO-CHECKOUT: Marca salida automática a empleados que no registraron OUT
-- =============================================================================
-- INSTRUCCIONES:
--   1. Ejecutar este bloque completo en Supabase → SQL Editor
--   2. El paso A crea la función.
--   3. El paso B habilita pg_cron (extensión).
--   4. El paso C programa el job cada 15 minutos.
-- =============================================================================

-- =============================================================================
-- PASO A: Función de auto-checkout
-- =============================================================================
CREATE OR REPLACE FUNCTION public.auto_checkout_employees()
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
AS $function$
DECLARE
    v_now_utc      timestamptz;
    v_now_peru     timestamp;
    v_today        date;
    v_count        int := 0;
    rec            record;
    v_checkout_utc timestamptz;
BEGIN
    v_now_utc  := now();
    v_now_peru := v_now_utc AT TIME ZONE 'America/Lima';
    v_today    := v_now_peru::date;

    -- Buscar registros de hoy con entrada pero sin salida,
    -- cuya hora programada de salida ya pasó.
    FOR rec IN
        SELECT DISTINCT ON (a.id)
            a.id,
            ws.check_out_time
        FROM public.attendance a
        JOIN public.employee_schedule_assignments esa
            ON  esa.employee_id = a.employee_id
            AND esa.valid_from  <= v_today
            AND (esa.valid_to IS NULL OR esa.valid_to >= v_today)
        JOIN public.work_schedules ws
            ON  ws.id        = esa.schedule_id
            AND ws.is_active = true
        WHERE a.work_date    = v_today
          AND a.check_in     IS NOT NULL
          AND a.check_out    IS NULL
          AND a.record_type  = 'ASISTENCIA'
          AND v_now_peru::time >= ws.check_out_time
        ORDER BY a.id, esa.valid_from DESC   -- asignación más reciente por empleado
    LOOP
        -- Construir timestamp UTC de la salida programada (hora Peru → UTC)
        v_checkout_utc := (v_today::text || ' ' || rec.check_out_time::text)::timestamp
                          AT TIME ZONE 'America/Lima';

        UPDATE public.attendance
        SET
            check_out        = v_checkout_utc,
            overtime_minutes = 0,
            notes            = CASE
                                   WHEN notes IS NULL OR notes = ''
                                   THEN '[Salida automática del sistema]'
                                   ELSE notes || ' · [Salida automática]'
                               END
        WHERE id         = rec.id
          AND check_out  IS NULL;   -- seguro doble: no sobreescribir si ya marcó

        v_count := v_count + 1;
    END LOOP;

    RETURN json_build_object(
        'success',   true,
        'processed', v_count,
        'run_at',    to_char(v_now_peru, 'YYYY-MM-DD HH24:MI:SS')
    );

EXCEPTION WHEN OTHERS THEN
    RETURN json_build_object('success', false, 'message', SQLERRM);
END;
$function$;

-- Verificar que se creó
SELECT routine_name, routine_type
FROM information_schema.routines
WHERE routine_schema = 'public' AND routine_name = 'auto_checkout_employees';


-- =============================================================================
-- PASO B: Habilitar extensión pg_cron
-- (Solo necesitas hacerlo una vez — si ya está habilitada, no hace nada)
-- En Supabase: Dashboard → Database → Extensions → buscar "pg_cron" → Enable
-- O con SQL:
-- =============================================================================
CREATE EXTENSION IF NOT EXISTS pg_cron;


-- =============================================================================
-- PASO C: Programar el job (corre cada 15 minutos)
-- =============================================================================

-- Eliminar el job si ya existía (evita duplicados — seguro si no existe)
DO $$
BEGIN
    PERFORM cron.unschedule('auto-checkout-employees');
EXCEPTION WHEN OTHERS THEN
    NULL; -- no existe todavía, ignorar
END;
$$;

-- Crear el job
SELECT cron.schedule(
    'auto-checkout-employees',          -- nombre único del job
    '*/15 * * * *',                     -- cada 15 minutos
    $$SELECT public.auto_checkout_employees()$$
);

-- Verificar que el job quedó registrado
SELECT jobid, jobname, schedule, command, active
FROM cron.job
WHERE jobname = 'auto-checkout-employees';


-- =============================================================================
-- TEST MANUAL (opcional — para probar sin esperar el cron)
-- =============================================================================
-- SELECT public.auto_checkout_employees();
