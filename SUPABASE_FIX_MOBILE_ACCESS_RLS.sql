
-- ==============================================================================
-- FIX: PERMISOS Y RLS PARA MOBILE ACCESS POLICIES
-- ==============================================================================

-- 1. Habilitar RLS en la tabla (por si acaso)
ALTER TABLE public.mobile_access_policies ENABLE ROW LEVEL SECURITY;

-- 2. Eliminar política anterior defectuosa
DROP POLICY IF EXISTS "Admins manage policies" ON public.mobile_access_policies;

-- 3. Crear nueva política más robusta usando EMAIL en lugar de ID
-- Esto soluciona el problema cuando auth.uid() no coincide con employees.id
CREATE POLICY "Admins manage policies" ON public.mobile_access_policies
    FOR ALL USING (
        EXISTS (
            SELECT 1 FROM public.employees 
            WHERE email = auth.jwt() ->> 'email'
            AND (
                role IN ('ADMIN', 'SUPER ADMIN', 'JEFE_RRHH') 
                OR position ILIKE '%JEFE DE GENTE%'
                OR position ILIKE '%ANALISTA DE GENTE%' -- También dar acceso a analistas
            )
        )
    );

-- 4. Asegurar política de lectura pública
DROP POLICY IF EXISTS "Public read policies" ON public.mobile_access_policies;
CREATE POLICY "Public read policies" ON public.mobile_access_policies
    FOR SELECT USING (true);

-- 5. Otorgar permisos básicos a roles autenticados
GRANT ALL ON public.mobile_access_policies TO authenticated;
GRANT ALL ON public.mobile_access_policies TO service_role;
