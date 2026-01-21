-- CORRECCIÓN DE INCONSISTENCIAS DE DATOS
-- Este script normaliza los tipos de registro y estados para corregir
-- casos donde dice "Asistencia" pero el estado es "Ausente".

-- 1. Corregir registros que tienen status 'ausente' pero record_type incorrecto
--    (Ej: La imagen donde dice ESTADO: AUSENTE, TIPO: Asistencia)
UPDATE public.attendance
SET record_type = 'AUSENCIA'
WHERE (status = 'ausente' OR status = 'falta')
  AND record_type != 'AUSENCIA';

-- 2. Normalizar el antiguo tipo 'INASISTENCIA' al nuevo estándar 'AUSENCIA'
--    (Para que todos los reportes y filtros funcionen igual)
UPDATE public.attendance
SET record_type = 'AUSENCIA'
WHERE record_type = 'INASISTENCIA';

-- 3. Asegurar que registros con check_in NULL y sin tipo definido sean AUSENCIA
--    (Limpieza de datos corruptos o incompletos, si los hubiera)
UPDATE public.attendance
SET record_type = 'AUSENCIA', status = 'ausente'
WHERE check_in IS NULL 
  AND record_type = 'ASISTENCIA' 
  AND created_at < NOW();

-- Verificación (Opcional - Ejecutar para comprobar)
-- SELECT * FROM attendance WHERE status = 'ausente' AND record_type != 'AUSENCIA';
