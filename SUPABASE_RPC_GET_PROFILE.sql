
-- FUNCIÓN PARA OBTENER PERFIL DE EMPLEADO BASADO EN EMAIL/DNI
-- Esta función ayuda al frontend a vincular el usuario autenticado (Auth) 
-- con su registro en la tabla de empleados (Public), sorteando problemas de RLS.

CREATE OR REPLACE FUNCTION public.get_user_employee_profile(
    p_email text
)
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER -- Se ejecuta con permisos de admin para leer employees sin restricciones RLS
AS $$
DECLARE
    v_employee RECORD;
    v_dni_candidate text;
BEGIN
    -- 1. Intentar buscar por coincidencia exacta de email
    SELECT * INTO v_employee 
    FROM public.employees 
    WHERE email = p_email 
    LIMIT 1;

    -- 2. Si no se encuentra, intentar extraer DNI del email (asumiendo formato DNI@pauser.app o similar)
    IF v_employee IS NULL THEN
        -- Extraer la parte antes del @
        v_dni_candidate := split_part(p_email, '@', 1);
        
        -- Verificar si parece un DNI (al menos 6 caracteres numéricos/texto)
        IF length(v_dni_candidate) >= 6 THEN
            SELECT * INTO v_employee 
            FROM public.employees 
            WHERE dni = v_dni_candidate 
            LIMIT 1;
        END IF;
    END IF;

    -- 3. Retornar resultado
    IF v_employee IS NOT NULL THEN
        RETURN json_build_object(
            'id', v_employee.id,
            'full_name', v_employee.full_name,
            'dni', v_employee.dni,
            'role', COALESCE(v_employee.role, v_employee.employee_type), -- Fallback si role es nulo
            'position', v_employee.position,
            'sede', v_employee.sede,
            'business_unit', v_employee.business_unit,
            'email', v_employee.email
        );
    ELSE
        RETURN NULL;
    END IF;
END;
$$;
