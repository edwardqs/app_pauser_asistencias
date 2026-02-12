
-- ==============================================================================
-- FIX FINAL: Usar función SECURITY DEFINER para la política RLS
-- Esto evita problemas de permisos al consultar la tabla employees desde una política
-- ==============================================================================

-- 1. Crear función verificadora con permisos elevados
CREATE OR REPLACE FUNCTION public.check_is_admin()
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER -- Se ejecuta con permisos de creador (postgres), ignorando RLS de employees
AS $$
BEGIN
    RETURN EXISTS (
        SELECT 1 FROM public.employees 
        WHERE email = auth.jwt() ->> 'email'
        AND (
            role IN ('ADMIN', 'SUPER ADMIN', 'JEFE_RRHH') 
            OR position ILIKE '%JEFE DE GENTE%'
            OR position ILIKE '%ANALISTA%'
            OR position ILIKE '%JEFE%' 
            OR position ILIKE '%GERENTE%'
            OR position ILIKE '%COORDINADOR%'
        )
    );
END;
$$;

-- 2. Otorgar permisos de ejecución
GRANT EXECUTE ON FUNCTION public.check_is_admin TO authenticated;
GRANT EXECUTE ON FUNCTION public.check_is_admin TO service_role;

-- 3. Actualizar la política RLS en mobile_access_policies
ALTER TABLE public.mobile_access_policies ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Admins manage policies" ON public.mobile_access_policies;

CREATE POLICY "Admins manage policies" ON public.mobile_access_policies
    FOR ALL 
    TO authenticated
    USING (public.check_is_admin())
    WITH CHECK (public.check_is_admin());

-- 4. Asegurar lectura pública
DROP POLICY IF EXISTS "Public read policies" ON public.mobile_access_policies;
CREATE POLICY "Public read policies" ON public.mobile_access_policies
    FOR SELECT USING (true);
