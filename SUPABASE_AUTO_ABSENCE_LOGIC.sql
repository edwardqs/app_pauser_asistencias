-- =============================================================================
-- FUNCIÓN AUTOMÁTICA: MARCAR FALTA INJUSTIFICADA
-- Descripción:
-- Esta función debe ejecutarse diariamente después de las 18:00 (6:00 PM).
-- Identifica a todos los empleados activos que NO tienen registro de asistencia
-- para la fecha actual y les crea un registro de 'AUSENCIA' con estado
-- 'FALTA_INJUSTIFICADA'.
-- =============================================================================

CREATE OR REPLACE FUNCTION public.auto_mark_unjustified_absences()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_count integer;
    v_today date := (CURRENT_TIMESTAMP AT TIME ZONE 'America/Lima')::date;
BEGIN
    -- Insertar registros para empleados activos sin asistencia hoy (Hora Perú)
    INSERT INTO public.attendance (
        employee_id,
        work_date,
        status,
        record_type,
        notes,
        absence_reason,
        validated,
        created_at,
        -- updated_at, -- Columna no existe en algunas versiones, omitir si da error
        registered_by
    )
    SELECT 
        e.id,
        v_today,
        'FALTA_INJUSTIFICADA', -- Estado específico para la UI
        'AUSENCIA',            -- Tipo general para reportes
        'Falta injustificada automática: Sin registro antes de las 18:00',
        'FALTA INJUSTIFICADA', -- Razón para mostrar en detalles
        true,                  -- Ya validado (sin derecho a justificación)
        NOW(),
        NULL                   -- registered_by NULL indica sistema
    FROM public.employees e
    WHERE e.is_active = true
    AND NOT EXISTS (
        SELECT 1 
        FROM public.attendance a 
        WHERE a.employee_id = e.id 
        AND a.work_date = v_today
    );

    GET DIAGNOSTICS v_count = ROW_COUNT;
    
    -- Registrar en log de actividades (si la tabla existe)
    BEGIN
        INSERT INTO public.activity_logs (description, type, metadata)
        VALUES (
            'Se generaron ' || v_count || ' faltas injustificadas automáticas.',
            'SYSTEM_AUTO_ABSENCE',
            json_build_object('count', v_count, 'date', v_today)
        );
    EXCEPTION WHEN OTHERS THEN
        -- Ignorar error si no existe la tabla logs
        NULL;
    END;
END;
$$;

-- =============================================================================
-- INSTRUCCIONES PARA AUTOMATIZACIÓN (pg_cron)
-- Si tienes la extensión pg_cron habilitada en Supabase, ejecuta esto:
-- =============================================================================
-- select cron.schedule(
--     'mark-absences-daily', -- Nombre del job
--     '0 18 * * *',          -- Cron expression (18:00 UTC, ajusta a tu zona horaria)
--     $$select public.auto_mark_unjustified_absences()$$
-- );

-- NOTA: Si tu servidor está en UTC, y Perú es UTC-5, 18:00 Perú = 23:00 UTC.
-- Ajusta el horario según la configuración de tu base de datos.

