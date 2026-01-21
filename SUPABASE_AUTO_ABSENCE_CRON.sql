-- FUNCIÓN AUTOMÁTICA DE INASISTENCIAS INJUSTIFICADAS
-- Esta función busca empleados que no marcaron asistencia el día anterior
-- y les crea un registro de 'INASISTENCIA' con motivo 'Falta Injustificada'.

CREATE OR REPLACE FUNCTION public.process_unjustified_absences()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
AS $function$
DECLARE
    v_yesterday date;
    v_employee record;
BEGIN
    -- Calculamos el día anterior (ayer)
    v_yesterday := (now() AT TIME ZONE 'America/Lima')::date - INTERVAL '1 day';

    -- Iteramos por todos los empleados ACTIVOS
    FOR v_employee IN 
        SELECT id FROM public.employees WHERE is_active = true
    LOOP
        -- Verificamos si NO tienen ningún registro de asistencia para AYER
        IF NOT EXISTS (
            SELECT 1 FROM public.attendance 
            WHERE employee_id = v_employee.id 
            AND work_date = v_yesterday
        ) THEN
            -- Insertamos la falta injustificada
            INSERT INTO public.attendance (
                employee_id,
                work_date,
                status,
                record_type,
                absence_reason,
                notes,
                created_at
            ) VALUES (
                v_employee.id,
                v_yesterday,
                'INJUSTIFICADA', -- Estado específico
                'INASISTENCIA',
                'Falta Injustificada (Automático)',
                'No se registró asistencia ni justificación en el plazo de 24h.',
                now()
            );
        END IF;
    END LOOP;
END;
$function$;

-- NOTA IMPORTANTE:
-- Para que esto se ejecute solo a las 6:00 AM todos los días, necesitas habilitar la extensión pg_cron en Supabase.
-- Ejecuta este bloque SI Y SOLO SI tienes pg_cron habilitado (Dashboard -> Database -> Extensions).
-- Si no tienes pg_cron, deberás llamar a esta función desde un Edge Function o Cron externo.

-- select cron.schedule(
--   'process-absences-daily', -- nombre del job
--   '0 11 * * *',             -- cron expression (6:00 AM Peru is 11:00 AM UTC usually)
--   'SELECT public.process_unjustified_absences()'
-- );
