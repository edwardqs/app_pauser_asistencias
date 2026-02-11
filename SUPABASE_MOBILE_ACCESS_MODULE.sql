
-- ==============================================================================
-- MÓDULO DE CONTROL DE ACCESO MÓVIL (MOBILE ACCESS POLICIES)
-- ==============================================================================

-- 1. Crear tabla de políticas
CREATE TABLE IF NOT EXISTS public.mobile_access_policies (
    id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
    scope_type TEXT NOT NULL CHECK (scope_type IN ('SEDE', 'BUSINESS_UNIT', 'POSITION')),
    scope_value TEXT NOT NULL,
    has_physical_time_clock BOOLEAN DEFAULT FALSE, -- TRUE = Bloquea App Móvil (Debe usar Huellero)
    description TEXT,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW(),
    created_by UUID REFERENCES public.employees(id)
);

-- Indices para búsqueda rápida
CREATE INDEX IF NOT EXISTS idx_mobile_access_scope ON public.mobile_access_policies(scope_type, scope_value);

-- Habilitar RLS
ALTER TABLE public.mobile_access_policies ENABLE ROW LEVEL SECURITY;

-- Política: Solo Admins y RRHH pueden gestionar (Ver, Crear, Editar, Eliminar)
DROP POLICY IF EXISTS "Admins manage policies" ON public.mobile_access_policies;
CREATE POLICY "Admins manage policies" ON public.mobile_access_policies
    FOR ALL USING (
        EXISTS (
            SELECT 1 FROM public.employees 
            WHERE id = auth.uid() 
            AND (role IN ('ADMIN', 'SUPER ADMIN', 'JEFE_RRHH') OR position ILIKE '%JEFE DE GENTE%')
        )
    );

-- Política: Lectura pública (para que el login funcione si se consulta directo, aunque usamos RPC)
DROP POLICY IF EXISTS "Public read policies" ON public.mobile_access_policies;
CREATE POLICY "Public read policies" ON public.mobile_access_policies
    FOR SELECT USING (true);


-- 2. Actualizar función RPC de Login Móvil para aplicar las políticas
CREATE OR REPLACE FUNCTION public.mobile_login(dni_input text, password_input text)
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_employee record;
    v_response json;
    v_policy_block record;
BEGIN
    -- 1. Buscar Empleado
    SELECT * INTO v_employee FROM public.employees WHERE dni = dni_input;

    IF v_employee IS NULL THEN
        RETURN json_build_object('success', false, 'message', 'Usuario no encontrado');
    END IF;

    -- 2. Verificar Contraseña
    IF v_employee.app_password <> password_input THEN
        RETURN json_build_object('success', false, 'message', 'Contraseña incorrecta');
    END IF;

    -- 3. VERIFICAR POLÍTICAS DE ACCESO MÓVIL
    -- Buscamos si existe alguna regla que marque "has_physical_time_clock = TRUE"
    -- para la Sede, Unidad o Cargo del empleado.
    -- Si existe, BLOQUEAMOS el acceso.
    
    SELECT * INTO v_policy_block
    FROM public.mobile_access_policies
    WHERE has_physical_time_clock = true
    AND (
        (scope_type = 'SEDE' AND UPPER(scope_value) = UPPER(v_employee.sede)) OR
        (scope_type = 'BUSINESS_UNIT' AND UPPER(scope_value) = UPPER(v_employee.business_unit)) OR
        (scope_type = 'POSITION' AND UPPER(scope_value) = UPPER(v_employee.position))
    )
    LIMIT 1;

    IF v_policy_block IS NOT NULL THEN
        RETURN json_build_object(
            'success', false, 
            'message', 'ACCESO DENEGADO: Su ' || 
                        CASE v_policy_block.scope_type 
                            WHEN 'SEDE' THEN 'Sede (' || v_policy_block.scope_value || ')'
                            WHEN 'BUSINESS_UNIT' THEN 'Unidad (' || v_policy_block.scope_value || ')'
                            WHEN 'POSITION' THEN 'Cargo'
                        END || 
                        ' cuenta con Reloj Biométrico (Huellero). Debe registrar su asistencia allí y no por la App.'
        );
    END IF;

    -- 4. Login Exitoso
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
        'role', v_employee.role
    );
END;
$$;
