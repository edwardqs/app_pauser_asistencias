-- DIAGNÓSTICO: Por qué job_position_id / location_id / department_id salen null
-- Ejecutar en Supabase SQL Editor y compartir los resultados

-- 1. Ver las columnas REALES de la tabla org_structure
SELECT column_name, data_type
FROM information_schema.columns
WHERE table_schema = 'public' AND table_name = 'org_structure'
ORDER BY ordinal_position;

-- 2. Ver las columnas REALES de employees (confirmar que existen job_position_id etc.)
SELECT column_name, data_type
FROM information_schema.columns
WHERE table_schema = 'public' AND table_name = 'employees'
AND column_name IN ('job_position_id', 'location_id', 'department_id')
ORDER BY column_name;

-- 3. ¿Existe la sede "ADM. CENTRAL" en la tabla locations?
SELECT id, name FROM public.locations
WHERE name ILIKE '%ADM%' OR name ILIKE '%CENTRAL%';

-- 4. ¿Existe el cargo "TRAINEE" en job_positions?
SELECT id, name FROM public.job_positions
WHERE name ILIKE '%TRAINEE%' OR name ILIKE '%DESARROLLO%' OR name ILIKE '%PART TIME%';

-- 5. Ver TODOS los registros de locations
SELECT id, name FROM public.locations ORDER BY name;

-- 6. Ver TODOS los job_positions
SELECT id, name FROM public.job_positions ORDER BY name;

-- 7. Ver primeras 10 filas de org_structure (columnas reales)
SELECT * FROM public.org_structure LIMIT 10;

-- 8. Simular lookup exacto (locations y job_positions por separado)
SELECT 'location_lookup' AS tipo, id::text AS id, name
FROM public.locations WHERE UPPER(TRIM(name)) = 'ADM. CENTRAL'
UNION ALL
SELECT 'job_position_lookup', id::text, name
FROM public.job_positions WHERE UPPER(TRIM(name)) = 'TRAINEE DE DESARROLLO PART TIME';
