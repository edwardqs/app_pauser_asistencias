-- Habilitar lectura pública de asistencias para el dashboard web
-- (O ajustar para que solo usuarios autenticados puedan ver)

-- 1. Asegurar que RLS está activo (buena práctica)
ALTER TABLE public.attendance ENABLE ROW LEVEL SECURITY;

-- 2. Crear política para PERMITIR SELECT a usuarios autenticados (Web)
-- Esto permite que cualquier usuario logueado en la web vea todas las asistencias.
CREATE POLICY "Permitir lectura de asistencias a autenticados"
ON public.attendance
FOR SELECT
TO authenticated
USING (true);

-- 3. Crear política para EMPLEADOS (App Móvil - si usan anon/public auth o su propio mecanismo)
-- Si la app móvil usa el rol 'anon' para leer (aunque usa RPC para escribir),
-- a veces necesita leer su propio historial.
CREATE POLICY "Permitir lectura publica o anonima (Opcional para desarrollo)"
ON public.attendance
FOR SELECT
TO anon
USING (true);

-- 4. Repetir para la tabla EMPLOYEES para poder hacer el JOIN y mostrar nombres
ALTER TABLE public.employees ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Permitir lectura de empleados a autenticados"
ON public.employees
FOR SELECT
TO authenticated
USING (true);

CREATE POLICY "Permitir lectura de empleados a anonimos"
ON public.employees
FOR SELECT
TO anon
USING (true);
