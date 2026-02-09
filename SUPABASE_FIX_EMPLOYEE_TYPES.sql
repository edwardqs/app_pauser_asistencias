-- =============================================================================
-- FIX: CORRECCIÓN DE TIPOS DE EMPLEADO (OPERATIVO/ADMINISTRATIVO)
-- Versión Corregida: Asegura creación de columnas en ambas tablas
-- =============================================================================

-- 1. Asegurar que job_positions tenga la columna employee_type
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'job_positions' AND column_name = 'employee_type') THEN
        ALTER TABLE public.job_positions ADD COLUMN employee_type TEXT DEFAULT 'OPERATIVO';
    END IF;
END $$;

-- 2. Asegurar que employees tenga la columna employee_type (CORRECCIÓN CRÍTICA)
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'employees' AND column_name = 'employee_type') THEN
        ALTER TABLE public.employees ADD COLUMN employee_type TEXT DEFAULT 'OPERATIVO';
    END IF;
END $$;

-- 3. Actualizar tipos en job_positions basado en palabras clave (si están nulos o vacíos)
UPDATE public.job_positions
SET employee_type = 'ADMINISTRATIVO'
WHERE (employee_type IS NULL OR employee_type = '')
AND (
    name ILIKE '%JEFE%' 
    OR name ILIKE '%ANALISTA%' 
    OR name ILIKE '%GERENTE%' 
    OR name ILIKE '%ASISTENTE%' 
    OR name ILIKE '%COORDINADOR%' 
    OR name ILIKE '%SUPERVISOR%'
);

UPDATE public.job_positions
SET employee_type = 'OPERATIVO'
WHERE employee_type IS NULL OR employee_type = '';

-- 4. Actualizar employees cruzando con job_positions por NOMBRE del cargo
-- (Ya que employees.position guarda el nombre del cargo)
UPDATE public.employees e
SET employee_type = jp.employee_type
FROM public.job_positions jp
WHERE e.position = jp.name
AND (e.employee_type IS NULL OR e.employee_type = '');

-- 5. Asegurar default para los que quedaron sin match
UPDATE public.employees
SET employee_type = 'OPERATIVO'
WHERE employee_type IS NULL OR employee_type = '';
