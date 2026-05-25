-- =============================================================================
-- PARCHE: Optimización de Ausencias Injustificadas & Turno Noche (v3)
-- =============================================================================
-- EJECUTAR ESTE SCRIPT EN EL SQL EDITOR DE SUPABASE PARA DEPLOYAR Y REPARAR
-- =============================================================================

-- 1. ACTUALIZAR FUNCIÓN DE AUSENCIAS AUTOMÁTICAS
-- Lógica: Evaluamos siempre el día anterior ("yesterday") ya finalizado.
-- De esta forma, los turnos nocturnos que comenzaron ayer y terminan hoy en la
-- madrugada (e.g. 03:00 AM) ya están 100% concluidos al momento de la evaluación.
-- =============================================================================
CREATE OR REPLACE FUNCTION public.auto_mark_unjustified_absences()
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
AS $function$
DECLARE
    v_target_date   DATE;
    v_isodow         INT;
    v_holiday_name  TEXT;
    v_count         INT := 0;
    rec             RECORD;
BEGIN
    -- Evaluamos siempre el día de AYER (ya finalizado por completo)
    v_target_date := (now() AT TIME ZONE 'America/Lima')::date - INTERVAL '1 day';
    v_isodow      := EXTRACT(ISODOW FROM v_target_date)::int;

    -- Si ayer fue feriado → no marcar falta injustificada regular
    SELECT name INTO v_holiday_name
    FROM   public.peru_holidays
    WHERE  date = v_target_date;

    IF v_holiday_name IS NOT NULL THEN
        RETURN json_build_object(
            'success',   true,
            'processed', 0,
            'reason',    'El día evaluado (' || v_target_date || ') fue feriado (' || v_holiday_name || ') — omitido'
        );
    END IF;

    -- Procesar empleados que tenían asignado un horario laborable ayer y no registraron asistencia
    FOR rec IN
        SELECT DISTINCT ON (esa.employee_id)
            esa.employee_id,
            ws.id            AS schedule_id,
            ws.check_out_time,
            ws.name          AS schedule_name
        FROM  public.employee_schedule_assignments esa
        JOIN  public.work_schedules ws ON ws.id = esa.schedule_id
        WHERE ws.schedule_type = 'REGULAR'
          AND ws.is_active = true
          AND esa.valid_from  <= v_target_date
          AND (esa.valid_to IS NULL OR esa.valid_to >= v_target_date)
          -- Ayer era un día laborable de este horario
          AND (ws.work_days IS NULL OR v_isodow = ANY(ws.work_days))
          -- Sin ningún registro de asistencia ayer (entrada, salida o ausencia/licencia)
          AND NOT EXISTS (
              SELECT 1
              FROM   public.attendance a
              WHERE  a.employee_id = esa.employee_id
                AND  a.work_date   = v_target_date
          )
          -- Sin solicitud aprobada o pendiente de vacaciones/permiso que cubra ayer
          AND NOT EXISTS (
              SELECT 1
              FROM   public.vacation_requests vr
              WHERE  vr.employee_id = esa.employee_id
                AND  vr.status      IN ('APROBADO', 'PENDIENTE')
                AND  vr.start_date  <= v_target_date
                AND  vr.end_date    >= v_target_date
          )
        ORDER BY esa.employee_id, esa.valid_from DESC
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
            created_at
        ) VALUES (
            rec.employee_id,
            v_target_date,
            'AUSENCIA',
            'FALTA_INJUSTIFICADA',
            'Falta injustificada automática: Sin asistencia registrada en la jornada del ' || TO_CHAR(v_target_date, 'DD/MM/YYYY'),
            'FALTA INJUSTIFICADA',
            rec.schedule_id,
            0,
            true, -- Validado automáticamente por el sistema
            now()
        );

        v_count := v_count + 1;
    END LOOP;

    -- Registrar log de actividad
    BEGIN
        INSERT INTO public.activity_logs (description, type, metadata)
        VALUES (
            'Faltas injustificadas automáticas: ' || v_count || ' registros para el día ' || v_target_date,
            'SYSTEM_AUTO_ABSENCE',
            json_build_object('count', v_count, 'date', v_target_date)
        );
    EXCEPTION WHEN OTHERS THEN NULL;
    END;

    RETURN json_build_object(
        'success',   true,
        'processed', v_count,
        'date',      v_target_date,
        'run_at',    to_char(now() AT TIME ZONE 'America/Lima', 'YYYY-MM-DD HH24:MI:SS')
    );
END;
$function$;


-- 2. DESHABILITAR Y ELIMINAR SECTOR DE CRONS DUPLICADOS/ANTIGUOS
-- =============================================================================
DO $$
DECLARE
    rec RECORD;
BEGIN
    FOR rec IN 
        SELECT jobid, jobname 
        FROM cron.job 
        WHERE jobname IN (
            'mark-absences-daily',
            'daily-attendance-closing',
            'cierre-asistencia-diario',
            'process-absences-daily',
            'process-absences',
            'run-auto-absence-cron'
        )
    LOOP
        PERFORM cron.unschedule(rec.jobid);
    END LOOP;
END $$;


-- 3. CREAR TAREA CRON ÚNICA Y OPTIMIZADA
-- Horario: Se programa a las 10:00 AM UTC (05:00 AM hora de Perú).
-- A esta hora, la jornada del día de ayer está 100% finalizada, inclusive los turnos
-- de noche que concluyeron en la madrugada de hoy (e.g. 03:00 AM o 04:00 AM).
-- =============================================================================
SELECT cron.schedule(
    'mark-absences-daily',
    '0 10 * * *',   -- 10:00 AM UTC todos los días
    $$SELECT public.auto_mark_unjustified_absences()$$
);

-- Verificar crons resultantes (debe figurar solo el nuevo mark-absences-daily y auto-checkout-employees)
SELECT jobid, jobname, schedule, active, command
FROM   cron.job
ORDER  BY jobname;


-- 4. REPARACIÓN RETROACTIVA: ELIMINAR LAS 8 AUSENCIAS FALSAS DE HOY LUNES 25
-- Se borran los registros generados prematuramente hoy Lunes 25 de mayo a la 1:00 AM
-- para permitir que los trabajadores marquen su entrada sin bloqueos hoy en la noche.
-- =============================================================================
DELETE FROM public.attendance
WHERE work_date = '2026-05-25'
  AND record_type = 'AUSENCIA'
  AND status = 'FALTA_INJUSTIFICADA'
  AND notes = 'Falta injustificada automática';
