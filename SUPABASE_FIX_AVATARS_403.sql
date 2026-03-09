-- SOLUCIÓN DE ERROR 403 (Unauthorized) en subida de foto de perfil
-- La App usa login personalizado (RPC mobile_login), no Supabase Auth nativo.
-- El usuario es visto como 'anon' al subir archivos, bloqueando las políticas 'TO authenticated'.
-- Mismo patrón resuelto anteriormente en SUPABASE_FIX_STORAGE_403.sql para attendance_evidence.

-- 1. Eliminar políticas anteriores que exigían autenticación
DROP POLICY IF EXISTS "Authenticated users can upload avatars" ON storage.objects;
DROP POLICY IF EXISTS "Authenticated users can update avatars" ON storage.objects;
DROP POLICY IF EXISTS "Avatar images are publicly accessible" ON storage.objects;

-- 2. Política de LECTURA pública (cualquiera puede ver los avatares)
CREATE POLICY "Avatar images are publicly accessible"
ON storage.objects FOR SELECT
USING ( bucket_id = 'avatars' );

-- 3. Política de SUBIDA abierta para el bucket avatars
-- Permite que la App suba fotos sin error 403 (igual que attendance_evidence).
CREATE POLICY "Anyone can upload avatars"
ON storage.objects FOR INSERT
WITH CHECK ( bucket_id = 'avatars' );

-- 4. Política de ACTUALIZACIÓN abierta (para reemplazar fotos existentes con upsert: true)
CREATE POLICY "Anyone can update avatars"
ON storage.objects FOR UPDATE
USING ( bucket_id = 'avatars' );

-- 5. Asegurar que el bucket sea público
UPDATE storage.buckets
SET public = true
WHERE id = 'avatars';
