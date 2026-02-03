-- Función RPC para restablecer contraseña con verificación de identidad
-- Requiere coincidencia de DNI y Fecha de Nacimiento

CREATE OR REPLACE FUNCTION public.reset_password_identity(
    p_dni text,
    p_birth_date date,
    p_new_password text
)
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_employee_id uuid;
BEGIN
    -- 1. Buscar empleado que coincida con DNI y Fecha de Nacimiento
    SELECT id INTO v_employee_id
    FROM public.employees
    WHERE dni = p_dni 
    AND birth_date = p_birth_date;

    -- 2. Validar existencia
    IF v_employee_id IS NULL THEN
        RETURN json_build_object(
            'success', false,
            'message', 'Los datos no coinciden. Verifique su DNI y Fecha de Nacimiento.'
        );
    END IF;

    -- 3. Actualizar contraseña
    UPDATE public.employees
    SET app_password = p_new_password
    WHERE id = v_employee_id;

    RETURN json_build_object(
        'success', true,
        'message', 'Contraseña actualizada correctamente'
    );

EXCEPTION WHEN OTHERS THEN
    RETURN json_build_object(
        'success', false,
        'message', 'Error interno: ' || SQLERRM
    );
END;
$$;
