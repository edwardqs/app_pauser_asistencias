-- =============================================================================
-- PASO 3: Diagnostico y Limpieza de Fechas Rotas en la Base de Datos
-- =============================================================================
-- EJECUTAR EN EL SQL EDITOR DE SUPABASE
-- =============================================================================

-- 1. AUDITAR: Asignaciones con desajuste (valid_from de mañana en UTC)
SELECT esa.id, e.full_name, esa.valid_from, esa.valid_to, ws.name as schedule_name
FROM public.employee_schedule_assignments esa
JOIN public.employees e ON e.id = esa.employee_id
JOIN public.work_schedules ws ON ws.id = esa.schedule_id
WHERE esa.valid_from > (now() AT TIME ZONE 'America/Lima')::date;

-- 2. CORREGIR: Traer asignaciones del futuro al dia de hoy
UPDATE public.employee_schedule_assignments
SET valid_from = (now() AT TIME ZONE 'America/Lima')::date
WHERE valid_from > (now() AT TIME ZONE 'America/Lima')::date;

-- 3. CORREGIR: Ajustar cierres de asignaciones previas del futuro al dia de hoy
UPDATE public.employee_schedule_assignments
SET valid_to = (now() AT TIME ZONE 'America/Lima')::date
WHERE valid_to > (now() AT TIME ZONE 'America/Lima')::date;
