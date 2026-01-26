-- =============================================================================
-- CORRECCIÓN URGENTE: AGREGAR COLUMNAS FALTANTES
-- =============================================================================

-- Si la tabla ya existía, el comando CREATE TABLE IF NOT EXISTS no agrega columnas nuevas.
-- Debemos agregarlas explícitamente con ALTER TABLE.

ALTER TABLE public.vacation_requests 
ADD COLUMN IF NOT EXISTS evidence_url text;

ALTER TABLE public.vacation_requests 
ADD COLUMN IF NOT EXISTS request_type text;

-- Asegurarnos una vez más de que el RLS esté desactivado para probar
ALTER TABLE public.vacation_requests DISABLE ROW LEVEL SECURITY;

-- Refrescar la caché del esquema (truco: comentar/descomentar en Supabase a veces ayuda, 
-- pero ejecutar un DDL como este suele forzar la actualización).
NOTIFY pgrst, 'reload config';
