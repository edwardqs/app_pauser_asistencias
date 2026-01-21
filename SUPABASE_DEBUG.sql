-- Script de Diagnóstico Definitivo

-- 1. Ver qué hay EXACTAMENTE en la tabla (incluyendo espacios invisibles)
-- Esto nos mostrará el DNI entre corchetes [ ] para ver si hay espacios
SELECT 
    id, 
    '[' || dni || ']' as dni_debug, 
    '[' || app_password || ']' as pass_debug, 
    full_name 
FROM public.employees;

-- 2. Forzar actualización limpia para el usuario de prueba
UPDATE public.employees 
SET 
    dni = '12345678', -- Sin espacios
    app_password = '123456' -- Sin espacios
WHERE dni LIKE '%12345678%'; -- Busca aunque tenga basura alrededor

-- 3. Verificar de nuevo
SELECT id, dni, app_password FROM public.employees WHERE dni = '12345678';
