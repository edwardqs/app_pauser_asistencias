    -- =================================================================================
    -- SOLUCIÓN INTEGRAL: AUTOMATIZACIÓN DE CIERRE DE ASISTENCIA (PG_CRON)
    -- =================================================================================
    -- Este script configura el cierre automático diario para registrar "FALTA_INJUSTIFICADA"
    -- a todos los empleados que no hayan marcado asistencia antes de las 6:30 PM (Hora Perú).

    -- 1. Habilitar la extensión para tareas programadas (si no existe)
    CREATE EXTENSION IF NOT EXISTS pg_cron;

    -- 2. Crear la función de cierre diario (Lógica Robusta)
    CREATE OR REPLACE FUNCTION public.handle_daily_closing()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_now_peru timestamp := CURRENT_TIMESTAMP AT TIME ZONE 'America/Lima';
    v_today date := v_now_peru::date;
    v_cutoff_time time := '18:00:00'; -- 6:00 PM
    v_count int;
BEGIN
    -- 1. Validación de seguridad: Impedir ejecución antes de las 6:00 PM hora Perú
    -- Esto protege contra ejecuciones manuales accidentales durante el día
    IF v_now_peru::time < v_cutoff_time THEN
        RAISE NOTICE 'SKIPPED: El cierre automático no puede ejecutarse antes de las 18:00 (Hora Perú: %).', v_now_peru::time;
        RETURN;
    END IF;

    -- 2. Insertar falta injustificada para empleados activos SIN registro hoy
    INSERT INTO public.attendance (
        employee_id,
        work_date,
        status,
        record_type,
        notes,
        absence_reason,
        validated,
        created_at
    )
    SELECT 
        e.id,
        v_today,
        'FALTA_INJUSTIFICADA', -- Estado para UI (Rojo)
        'AUSENCIA',            -- Tipo de Registro
        'Cierre automático: Sin asistencia registrada al corte (6:30 PM)',
        'FALTA INJUSTIFICADA',
        true,                  -- Ya validado por el sistema
        NOW()
    FROM public.employees e
    WHERE e.is_active = true
    -- Excluir a los que YA tienen cualquier registro hoy (Asistencia, Licencia, Vacaciones, etc.)
    AND NOT EXISTS (
        SELECT 1 FROM public.attendance a 
        WHERE a.employee_id = e.id 
        AND a.work_date = v_today
    );
    
    GET DIAGNOSTICS v_count = ROW_COUNT;
    RAISE NOTICE 'Cierre diario ejecutado: % faltas generadas para %', v_count, v_today;
END;
$$;

    -- 3. Programar el Cron Job
-- Primero, intentamos eliminar cualquier job previo usando su ID (más seguro)
-- Nota: 'unschedule' espera un Job ID (integer) o un nombre de job si se usa la versión más reciente de pg_cron.
-- Para evitar el error "could not find valid entry", usamos un bloque DO seguro.

DO $$
DECLARE
    job_id_to_remove bigint;
BEGIN
    SELECT jobid INTO job_id_to_remove FROM cron.job WHERE jobname = 'daily-attendance-closing';
    
    IF job_id_to_remove IS NOT NULL THEN
        PERFORM cron.unschedule(job_id_to_remove);
    END IF;
END $$;

-- Programamos para las 23:30 UTC
-- NOTA: Perú es UTC-5. 
-- 18:30 (6:30 PM) Perú + 5 horas = 23:30 UTC.
-- Se usa 23:30 para dar 30 mins de tolerancia después de la salida (6:00 PM).
SELECT cron.schedule(
    'daily-attendance-closing', -- Nombre único del job
    '30 23 * * *',              -- Minuto 30, Hora 23 (UTC) -> 6:30 PM Perú
    $$SELECT public.handle_daily_closing()$$
);

    -- 4. Verificación (Opcional)
    SELECT * FROM cron.job WHERE jobname = 'daily-attendance-closing';
