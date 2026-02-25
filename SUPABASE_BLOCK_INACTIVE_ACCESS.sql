-- ==============================================================================
-- BLOQUEO DE ACCESO A USUARIOS INACTIVOS (BAJAS)
-- ==============================================================================
-- Este script actualiza las funciones críticas de Login y Registro de Asistencia
-- para impedir que usuarios con is_active = false puedan acceder o marcar.

-- 1. ACTUALIZAR LOGIN MÓVIL (mobile_login)
-- Basado en la versión unificada V5
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

    -- NUEVO: VERIFICAR SI EL USUARIO ESTÁ ACTIVO
    IF v_employee.is_active IS FALSE THEN
        RETURN json_build_object('success', false, 'message', 'ACCESO DENEGADO: El usuario se encuentra inactivo. Contacte a RRHH.');
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

-- 2. ACTUALIZAR REGISTRO DE ASISTENCIA (register_attendance)
-- Bloquear marcación para usuarios inactivos
CREATE OR REPLACE FUNCTION public.register_attendance(
    p_employee_id uuid,
    p_lat double precision,
    p_lng double precision,
    p_type text, -- 'IN', 'OUT', o 'ABSENCE'
    p_notes text DEFAULT NULL,
    p_evidence_url text DEFAULT NULL
)
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
AS $function$
DECLARE
    v_now_utc timestamptz;
    v_now_peru timestamp;
    v_today date;
    v_attendance_id uuid;
    v_existing_record record;
    v_is_late boolean := false;
    v_has_bonus boolean := false;
    v_status text := 'asistio';
    v_record_type text := 'ASISTENCIA';
    v_final_notes text;
    v_is_active boolean;
    
    -- Horarios (Configurables aquí)
    c_start_bonus time := '06:30:00';
    c_end_bonus time := '06:50:00';
    c_late_limit time := '07:00:00'; -- A partir de 07:01 es tardanza
    
BEGIN
    -- NUEVO: VERIFICAR SI EL USUARIO ESTÁ ACTIVO
    SELECT is_active INTO v_is_active FROM public.employees WHERE id = p_employee_id;
    
    IF v_is_active IS FALSE THEN
        RETURN json_build_object('success', false, 'message', 'ACCESO DENEGADO: Usuario inactivo no puede registrar asistencia.');
    END IF;

    -- 1. OBTENER FECHA Y HORA CORRECTA (PERÚ)
    v_now_utc := now(); -- Hora del servidor (UTC)
    v_now_peru := v_now_utc AT TIME ZONE 'America/Lima'; -- Hora Perú
    v_today := v_now_peru::date; -- Fecha Perú (Esto es lo que se guarda en work_date)
    
    v_final_notes := COALESCE(p_notes, '');

    -- 2. BUSCAR REGISTRO EXISTENTE PARA "HOY" (FECHA PERÚ)
    SELECT * INTO v_existing_record
    FROM public.attendance
    WHERE employee_id = p_employee_id
    AND work_date = v_today; -- Compara DATE con DATE

    -- =========================================================================
    -- CASO 1: REGISTRO DE ENTRADA (IN)
    -- =========================================================================
    IF p_type = 'IN' THEN
        IF v_existing_record IS NOT NULL THEN
             RETURN json_build_object('success', false, 'message', 'Ya registraste asistencia hoy');
        END IF;

        -- Evaluar Tardanza (Usando Hora Perú)
        IF v_now_peru::time > c_late_limit THEN
            v_is_late := true;
            v_status := 'tardanza';
            v_final_notes := CASE WHEN v_final_notes = '' THEN 'Ingreso con Tardanza (>07:00)' ELSE 'Tardanza: ' || v_final_notes END;
        ELSE
            -- Evaluar Bono
            IF v_now_peru::time >= c_start_bonus AND v_now_peru::time <= c_end_bonus THEN
                v_has_bonus := true;
                v_final_notes := CASE WHEN v_final_notes = '' THEN 'Puntual con Bono' ELSE v_final_notes || ' (Bono)' END;
            END IF;
        END IF;

        INSERT INTO public.attendance (
            employee_id,
            work_date,      -- Fecha Perú
            check_in,       -- Timestamp UTC (Estándar para apps)
            location_in,
            status,
            is_late,
            notes,
            evidence_url,
            record_type,
            created_at
        ) VALUES (
            p_employee_id,
            v_today,
            v_now_utc,
            jsonb_build_object('lat', p_lat, 'lng', p_lng),
            v_status,
            v_is_late,
            v_final_notes,
            p_evidence_url,
            'ASISTENCIA',
            v_now_utc
        ) RETURNING id INTO v_attendance_id;

        RETURN json_build_object(
            'success', true, 
            'message', 'Entrada registrada correctamente',
            'attendance_id', v_attendance_id
        );

    -- =========================================================================
    -- CASO 2: REGISTRO DE SALIDA (OUT)
    -- =========================================================================
    ELSIF p_type = 'OUT' THEN
        IF v_existing_record IS NULL THEN
             RETURN json_build_object('success', false, 'message', 'No tienes registro de entrada hoy');
        END IF;
        
        IF v_existing_record.check_out IS NOT NULL THEN
             RETURN json_build_object('success', false, 'message', 'Ya registraste salida hoy');
        END IF;

        UPDATE public.attendance
        SET check_out = v_now_utc,
            location_out = jsonb_build_object('lat', p_lat, 'lng', p_lng),
            updated_at = v_now_utc
        WHERE id = v_existing_record.id;

        RETURN json_build_object(
            'success', true, 
            'message', 'Salida registrada correctamente'
        );
    
    -- =========================================================================
    -- CASO 3: REGISTRO DE ABSENCE (Ausencia justificada rápida)
    -- =========================================================================
    ELSIF p_type = 'ABSENCE' THEN
         -- Implementación futura si se requiere
         RETURN json_build_object('success', false, 'message', 'Tipo de registro no soportado aún');
    
    ELSE
        RETURN json_build_object('success', false, 'message', 'Tipo de registro inválido');
    END IF;

EXCEPTION WHEN OTHERS THEN
    RETURN json_build_object('success', false, 'message', 'Error interno: ' || SQLERRM);
END;
$function$;
