CREATE OR REPLACE FUNCTION public.register_absence(
    p_employee_id uuid,
    p_reason text,
    p_evidence_url text,
    p_notes text,
    p_registered_by uuid DEFAULT NULL
)
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
AS $function$
DECLARE
    v_attendance_id uuid;
BEGIN
    INSERT INTO public.attendance (
        employee_id,
        work_date,
        record_type,
        absence_reason,
        evidence_url,
        notes,
        registered_by,
        status,
        created_at
    ) VALUES (
        p_employee_id,
        CURRENT_DATE,
        'INASISTENCIA',
        p_reason,
        p_evidence_url,
        p_notes,
        p_registered_by,
        'ausente',
        now()
    ) RETURNING id INTO v_attendance_id;

    RETURN json_build_object(
        'success', true,
        'message', 'Inasistencia registrada correctamente',
        'id', v_attendance_id
    );
END;
$function$;
