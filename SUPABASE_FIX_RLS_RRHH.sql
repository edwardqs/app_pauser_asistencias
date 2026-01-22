-- ================================================================
-- SOLUCIÓN DE PERMISOS RLS PARA ANALISTAS DE RRHH
-- ================================================================

-- 1. Habilitar RLS en la tabla de asistencias (por seguridad)
ALTER TABLE public.attendance ENABLE ROW LEVEL SECURITY;

-- 2. Política de LECTURA (SELECT)
-- Permite que Analistas y Jefes de RRHH vean TODAS las asistencias
-- para poder listarlas en el panel de validación.
DROP POLICY IF EXISTS "RRHH View All Attendance" ON public.attendance;

CREATE POLICY "RRHH View All Attendance"
ON public.attendance
FOR SELECT
TO authenticated
USING (
  EXISTS (
    SELECT 1 FROM public.employees e
    WHERE e.email = auth.email() -- Vinculación segura por Email de Auth
    AND e.role IN ('ANALISTA_RRHH', 'JEFE_RRHH', 'ADMIN')
  )
);

-- 3. Política de ESCRITURA (UPDATE)
-- Permite que Analistas y Jefes de RRHH modifiquen asistencias
-- (Aunque se use RPC, esto asegura acceso si se implementa edición directa)
DROP POLICY IF EXISTS "RRHH Update Attendance" ON public.attendance;

CREATE POLICY "RRHH Update Attendance"
ON public.attendance
FOR UPDATE
TO authenticated
USING (
  EXISTS (
    SELECT 1 FROM public.employees e
    WHERE e.email = auth.email()
    AND e.role IN ('ANALISTA_RRHH', 'JEFE_RRHH', 'ADMIN')
  )
);

-- 4. Verificación de Rol (Opcional, para debug)
-- Puedes ejecutar esto para ver qué rol detecta la base de datos para tu usuario
-- SELECT email, role, position FROM public.employees WHERE email = 'equispe@pauserdistribuciones.com';
