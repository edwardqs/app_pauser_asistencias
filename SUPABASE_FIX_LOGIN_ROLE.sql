-- Actualizar función mobile_login para retornar el nuevo campo 'role'
CREATE OR REPLACE FUNCTION public.mobile_login(dni_input text, password_input text)
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
AS $function$
DECLARE
    v_employee record;
    v_response json;
BEGIN
    -- Seleccionamos el registro completo
    SELECT * INTO v_employee
    FROM public.employees
    WHERE dni = dni_input;

    -- Validar existencia
    IF v_employee IS NULL THEN
        RETURN json_build_object(
            'success', false,
            'message', 'Usuario no encontrado'
        );
    END IF;

    -- Validar contraseña (app_password)
    IF v_employee.app_password = password_input THEN
        -- Login exitoso: Incluimos el nuevo campo 'role'
        v_response := json_build_object(
            'success', true,
            'employee_id', v_employee.id,
            'full_name', v_employee.full_name,
            'dni', v_employee.dni,
            'sede', v_employee.sede,
            'business_unit', v_employee.business_unit,
            'employee_type', v_employee.employee_type,
            'position', v_employee.position,
            'profile_picture_url', v_employee.profile_picture_url,
            'role', v_employee.role -- CAMPO NUEVO IMPORTANTE
        );
        
        RETURN v_response;
    ELSE
        -- Contraseña incorrecta
        RETURN json_build_object(
            'success', false,
            'message', 'Contraseña incorrecta'
        );
    END IF;
END;
$function$;
