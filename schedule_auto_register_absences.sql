-- =================================================================================
-- PROGRAMACIÓN DE TAREA AUTOMÁTICA (CRON JOB) - VERSIÓN SEGURA
-- Descripción: Ejecuta la función 'auto_register_unjustified_absences' 
--              todos los días a las 6:05 PM (Hora Perú).
-- Requisito: La extensión 'pg_cron' debe estar habilitada en Supabase.
-- =================================================================================

-- 1. Habilitar la extensión pg_cron (si no está activa)
CREATE EXTENSION IF NOT EXISTS pg_cron;

-- 2. Eliminar programación anterior de forma segura
-- Nota: Usamos una subconsulta para obtener el ID. Si no existe, no hace nada (evita el error).
SELECT cron.unschedule(jobid) 
FROM cron.job 
WHERE jobname = 'cierre-asistencia-diario';

-- 3. Programar la tarea
-- Formato Cron: Minuto Hora Día Mes DíaSemana
-- '5 18 * * *' = A las 18:05 (6:05 PM) todos los días
SELECT cron.schedule(
    'cierre-asistencia-diario', -- Nombre único de la tarea
    '5 18 * * *',               -- Expresión Cron
    $$SELECT public.auto_register_unjustified_absences()$$ -- Comando SQL a ejecutar
);

-- 4. Verificación
-- Debería mostrar la tarea recién creada
SELECT * FROM cron.job WHERE jobname = 'cierre-asistencia-diario';
