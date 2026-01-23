CREATE OR REPLACE FUNCTION public.register_auto_absence(
    p_employee_id uuid
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_exists boolean;
    v_today date := (CURRENT_TIMESTAMP AT TIME ZONE 'America/Lima')::date;
BEGIN
    -- Verificar si ya existe registro para hoy (Hora Peru)
    SELECT EXISTS (
        SELECT 1 FROM public.attendance 
        WHERE employee_id = p_employee_id 
        AND work_date = v_today
    ) INTO v_exists;

    IF v_exists THEN
        RETURN; -- Ya existe, no hacer nada
    END IF;

    -- Insertar falta
    INSERT INTO public.attendance (
        employee_id,
        work_date,
        status,
        record_type,
        notes,
        absence_reason,
        validated,
        created_at,
        registered_by
    ) VALUES (
        p_employee_id,
        v_today,
        'FALTA_INJUSTIFICADA',
        'AUSENCIA',
        'Falta injustificada automática: Sin registro antes de las 18:00',
        'FALTA INJUSTIFICADA',
        true,
        NOW(),
        p_employee_id -- Auto-registrado por el usuario (app) o sistema
    );
END;
$$;
