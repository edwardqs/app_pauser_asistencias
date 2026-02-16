-- =================================================================================
-- FUNCIÓN: Auto-registro de Ausencias Injustificadas
-- Descripción: Registra 'AUSENCIA' - 'Injustificada' para empleados sin asistencia
--              después de las 6:00 PM.
-- =================================================================================

CREATE OR REPLACE FUNCTION public.auto_register_unjustified_absences(
    p_date date DEFAULT (CURRENT_TIMESTAMP AT TIME ZONE 'America/Lima')::date
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_cutoff_time time := '18:00:00';
    v_current_time time := (CURRENT_TIMESTAMP AT TIME ZONE 'America/Lima')::time;
    v_current_date date := (CURRENT_TIMESTAMP AT TIME ZONE 'America/Lima')::date;
    v_count integer;
BEGIN
    -- 1. Validación de hora: Si es el día actual, debe ser pasado las 6:00 PM
    --    Si es un día pasado, se permite correr en cualquier momento (para correcciones)
    IF p_date = v_current_date AND v_current_time < v_cutoff_time THEN
        RAISE NOTICE 'Aún no son las 6:00 PM (Hora actual: %). No se generarán ausencias.', v_current_time;
        RETURN;
    END IF;

    -- 2. Insertar ausencias para empleados activos sin registro
    INSERT INTO public.attendance (
        employee_id,
        work_date,
        record_type,
        absence_reason,
        status,
        validated,
        created_at,
        notes
    )
    SELECT 
        e.id,
        p_date,
        'AUSENCIA',
        'Injustificada',
        'VALIDADO', -- Estado Validado con check verde
        true,       -- Flag validated true
        NOW(),
        'Generado automáticamente por el sistema (Cierre 6:00 PM)'
    FROM public.employees e
    WHERE e.is_active = true
    -- Excluir a los que ya tienen registro (Asistencia, Falta, Licencia, etc.)
    AND NOT EXISTS (
        SELECT 1 FROM public.attendance a 
        WHERE a.employee_id = e.id 
        AND a.work_date = p_date
    );

    GET DIAGNOSTICS v_count = ROW_COUNT;
    RAISE NOTICE 'Se generaron % ausencias injustificadas para la fecha %.', v_count, p_date;

END;
$$;
