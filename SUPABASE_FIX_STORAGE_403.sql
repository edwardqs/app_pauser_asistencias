-- SOLUCIÓN DE ERROR 403 (Unauthorized)
-- La App usa un login personalizado (no Supabase Auth nativo), por lo que el usuario 
-- es visto como "anónimo" al intentar subir archivos.
-- Esta corrección permite que la App suba fotos sin requerir sesión de Supabase Auth.

-- 1. Eliminar la política anterior que exigía autenticación
DROP POLICY IF EXISTS "Attendance Evidence Auth Upload" ON storage.objects;
DROP POLICY IF EXISTS "Attendance Evidence Public Upload" ON storage.objects;

-- 2. Crear nueva política ABIERTA para este bucket específico
-- Esto permite que la App suba las fotos de evidencia sin error 403.
CREATE POLICY "Attendance Evidence Public Upload"
ON storage.objects FOR INSERT
WITH CHECK (
  bucket_id = 'attendance_evidence'
);

-- 3. Asegurar lectura pública (ya estaba, pero reforzamos)
DROP POLICY IF EXISTS "Attendance Evidence Public Read" ON storage.objects;
CREATE POLICY "Attendance Evidence Public Read"
ON storage.objects FOR SELECT
USING ( bucket_id = 'attendance_evidence' );

-- 4. Asegurar configuración del bucket
UPDATE storage.buckets
SET public = true
WHERE id = 'attendance_evidence';
