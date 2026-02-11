
-- ==============================================================================
-- LOGIN MÓVIL UNIFICADO V5 (Roles + Políticas de Acceso + Fallback + TRIM)
-- ==============================================================================
-- V5 CAMBIOS:
-- 1. Agrega TRIM() en las comparaciones de Sede, Business Unit y Cargo.
--    Esto es crucial para evitar fallos por espacios en blanco accidentales 
--    (ej. "LIMA " vs "LIMA").
-- 2. Mantiene toda la lógica de V4 (Fallback de Rol por nombre).

CREATE OR REPLACE FUNCTION public.mobile_login(dni_input text, password_input text)
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_employee record;
    v_role_access boolean;
    v_role_name text;
    v_policy_block record;
    v_can_mark_attendance boolean;
    v_restriction_message text;
BEGIN
    -- 1. BUSCAR EMPLEADO
    SELECT * INTO v_employee 
    FROM public.employees 
    WHERE dni = dni_input;

    IF v_employee IS NULL THEN
        RETURN json_build_object('success', false, 'message', 'Usuario no encontrado');
    END IF;

    -- 2. VERIFICAR CONTRASEÑA
    IF v_employee.app_password <> password_input THEN
        RETURN json_build_object('success', false, 'message', 'Contraseña incorrecta');
    END IF;

    -- 3. VALIDACIÓN 1: PERMISOS DE ROL (Módulo "Usuarios y Permisos")
    v_role_access := true; -- Por defecto permitido
    v_role_name := 'Sin Rol';

    IF v_employee.role_id IS NOT NULL THEN
        -- A. Búsqueda por ID
        SELECT mobile_access, name INTO v_role_access, v_role_name
        FROM public.roles 
        WHERE id = v_employee.role_id;
    ELSE
        -- B. Fallback: Búsqueda por NOMBRE
        IF v_employee.role IS NOT NULL THEN
             SELECT mobile_access, name INTO v_role_access, v_role_name
             FROM public.roles
             WHERE UPPER(TRIM(name)) = UPPER(TRIM(v_employee.role))
             LIMIT 1;
             
             IF v_role_name IS NULL THEN
                v_role_name := v_employee.role;
             END IF;
        END IF;
    END IF;
    
    -- Si mobile_access es FALSE, BLOQUEAR LOGIN
    IF v_role_access IS FALSE THEN
        RETURN json_build_object(
            'success', false, 
            'message', 'ACCESO DENEGADO: Su rol "' || COALESCE(v_role_name, 'Desconocido') || '" no tiene permisos para usar la App Móvil.'
        );
    END IF;

    -- 4. VALIDACIÓN 2: POLÍTICAS DE ACCESO (Módulo "Control de Acceso Móvil")
    -- ESTO NO BLOQUEA EL LOGIN, SOLO LA MARCACIÓN.
    SELECT * INTO v_policy_block
    FROM public.mobile_access_policies
    WHERE has_physical_time_clock = true
    AND (
        (scope_type = 'SEDE' AND UPPER(TRIM(scope_value)) = UPPER(TRIM(COALESCE(v_employee.sede, '')))) OR
        (scope_type = 'BUSINESS_UNIT' AND UPPER(TRIM(scope_value)) = UPPER(TRIM(COALESCE(v_employee.business_unit, '')))) OR
        (scope_type = 'POSITION' AND UPPER(TRIM(scope_value)) = UPPER(TRIM(COALESCE(v_employee.position, ''))))
    )
    LIMIT 1;

    IF v_policy_block IS NOT NULL THEN
        v_can_mark_attendance := false;
        v_restriction_message := 'Su ' || 
                        CASE v_policy_block.scope_type 
                            WHEN 'SEDE' THEN 'Sede (' || v_policy_block.scope_value || ')'
                            WHEN 'BUSINESS_UNIT' THEN 'Unidad (' || v_policy_block.scope_value || ')'
                            WHEN 'POSITION' THEN 'Cargo'
                        END || 
                        ' requiere registro en Reloj Biométrico.';
    ELSE
        v_can_mark_attendance := true;
        v_restriction_message := null;
    END IF;

    -- 5. LOGIN EXITOSO
    RETURN json_build_object(
        'success', true,
        'employee_id', v_employee.id,
        'full_name', v_employee.full_name,
        'dni', v_employee.dni,
        'sede', v_employee.sede,
        'business_unit', v_employee.business_unit,
        'employee_type', v_employee.employee_type,
        'position', v_employee.position,
        'profile_picture_url', v_employee.profile_picture_url,
        'role', COALESCE(v_role_name, v_employee.role),
        'role_id', v_employee.role_id,
        'can_mark_attendance', v_can_mark_attendance, 
        'restriction_message', v_restriction_message,
        'email', v_employee.dni || '@pauser.app'
    );
END;
$$;
