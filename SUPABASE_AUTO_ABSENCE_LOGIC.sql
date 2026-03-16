-- =============================================================================
-- FUNCIÓN AUTOMÁTICA: MARCAR FALTA INJUSTIFICADA (v2)
-- =============================================================================
-- CAMBIOS vs versión anterior:
--   ✓ Respeta el horario asignado de cada empleado (check_out_time)
--   ✓ Solo marca si la hora de salida del empleado ya pasó
--   ✓ Omite días feriados (manejados por auto-holiday-absences)
--   ✓ Omite días no laborables según work_days del horario
--   ✓ Omite empleados con solicitud aprobada/pendiente que cubra hoy
--   ✓ Retorna JSON con resultado en lugar de void
-- =============================================================================
-- PREREQUISITO: Haber ejecutado SUPABASE_HOLIDAYS_SETUP.sql
-- =============================================================================


CREATE OR REPLACE FUNCTION public.auto_mark_unjustified_absences()
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
AS $function$
DECLARE
    v_today         DATE;
    v_now_peru      TIME;
    v_isodow        INT;
    v_holiday_name  TEXT;
    v_count         INT := 0;
    rec             RECORD;
BEGIN
    v_today    := (now() AT TIME ZONE 'America/Lima')::date;
    v_now_peru := (now() AT TIME ZONE 'America/Lima')::time;
    v_isodow   := EXTRACT(ISODOW FROM v_today)::int;

    -- Si hoy es feriado → auto-holiday-absences ya lo gestiona, no hacer nada
    SELECT name INTO v_holiday_name
    FROM   public.peru_holidays
    WHERE  date = v_today;

    IF v_holiday_name IS NOT NULL THEN
        RETURN json_build_object(
            'success',   true,
            'processed', 0,
            'reason',    'Día feriado (' || v_holiday_name || ') — gestionado por auto-holiday-absences'
        );
    END IF;

    -- Procesar empleados cuyo horario activo indica que su jornada ya terminó
    FOR rec IN
        SELECT DISTINCT ON (esa.employee_id)
            esa.employee_id,
            ws.id            AS schedule_id,
            ws.check_out_time,
            ws.name          AS schedule_name
        FROM  public.employee_schedule_assignments esa
        JOIN  public.work_schedules ws ON ws.id = esa.schedule_id
        WHERE ws.schedule_type = 'REGULAR'
          AND esa.valid_from  <= v_today
          AND (esa.valid_to IS NULL OR esa.valid_to >= v_today)
          -- Hoy es un día laborable de este horario
          AND (ws.work_days IS NULL OR v_isodow = ANY(ws.work_days))
          -- La hora de salida del empleado ya pasó
          AND v_now_peru >= ws.check_out_time
          -- Sin ningún registro de asistencia hoy (entrada, salida o ausencia)
          AND NOT EXISTS (
              SELECT 1
              FROM   public.attendance a
              WHERE  a.employee_id = esa.employee_id
                AND  a.work_date   = v_today
          )
          -- Sin solicitud aprobada o pendiente que cubra hoy
          -- (vacaciones, permiso médico, permiso personal, etc.)
          AND NOT EXISTS (
              SELECT 1
              FROM   public.vacation_requests vr
              WHERE  vr.employee_id = esa.employee_id
                AND  vr.status      IN ('APROBADO', 'PENDIENTE')
                AND  vr.start_date  <= v_today
                AND  vr.end_date    >= v_today
          )
        ORDER BY esa.employee_id, esa.valid_from DESC  -- asignación más reciente
    LOOP
        INSERT INTO public.attendance (
            employee_id,
            work_date,
            record_type,
            status,
            notes,
            absence_reason,
            schedule_id,
            overtime_minutes,
            validated,
            registered_by,
            created_at
        ) VALUES (
            rec.employee_id,
            v_today,
            'AUSENCIA',
            'FALTA_INJUSTIFICADA',
            'Falta injustificada: Sin registro hasta las ' ||
                TO_CHAR(rec.check_out_time, 'HH24:MI') ||
                ' — Horario: ' || rec.schedule_name,
            'FALTA INJUSTIFICADA',
            rec.schedule_id,
            0,
            true,   -- validado automáticamente por el sistema
            NULL,   -- registered_by NULL = sistema
            now()
        );

        v_count := v_count + 1;
    END LOOP;

    -- Log en activity_logs (opcional, ignorar si no existe la tabla)
    BEGIN
        INSERT INTO public.activity_logs (description, type, metadata)
        VALUES (
            'Faltas injustificadas automáticas: ' || v_count || ' registros.',
            'SYSTEM_AUTO_ABSENCE',
            json_build_object('count', v_count, 'date', v_today)
        );
    EXCEPTION WHEN OTHERS THEN NULL;
    END;

    RETURN json_build_object(
        'success',   true,
        'processed', v_count,
        'date',      v_today,
        'run_at',    to_char(now() AT TIME ZONE 'America/Lima', 'YYYY-MM-DD HH24:MI:SS')
    );

EXCEPTION WHEN OTHERS THEN
    RETURN json_build_object('success', false, 'message', SQLERRM);
END;
$function$;


-- =============================================================================
-- ACTUALIZAR EL CRON JOB existente
-- Antes corría a las 18:30 Peru para todos por igual.
-- Ahora corre a las 23:50 Peru (04:50 UTC) para asegurar que TODOS los
-- horarios (mañana, tarde, noche) hayan terminado su jornada.
-- La función verifica internamente si check_out_time ya pasó por empleado.
-- =============================================================================
DO $$
BEGIN
    PERFORM cron.unschedule('mark-absences-daily');
EXCEPTION WHEN OTHERS THEN NULL;
END;
$$;

SELECT cron.schedule(
    'mark-absences-daily',
    '50 4 * * *',   -- 23:50 hora Peru (04:50 UTC) — todos los días
    $$SELECT public.auto_mark_unjustified_absences()$$
);

-- Verificar
SELECT jobid, jobname, schedule, active
FROM   cron.job
WHERE  jobname = 'mark-absences-daily';


-- =============================================================================
-- TEST MANUAL
-- =============================================================================
-- SELECT public.auto_mark_unjustified_absences();
