-- SOLUCIÓN ERROR 403 EN SUBIDA DE PAPELETAS FIRMADAS
-- La App móvil usa autenticación personalizada, por lo que Supabase Storage ve al usuario como "anónimo".
-- Necesitamos permitir la subida pública (o restringida solo por bucket_id) para que no falle.

-- 1. Eliminar políticas anteriores restrictivas (si existen)
DROP POLICY IF EXISTS "Papeletas Auth Upload" ON storage.objects;
DROP POLICY IF EXISTS "Papeletas Auth Update" ON storage.objects;
DROP POLICY IF EXISTS "Papeletas Public Upload" ON storage.objects; -- Por si acaso

-- 2. Crear nueva política de SUBIDA ABIERTA para el bucket 'papeletas'
-- Permite INSERT a cualquier usuario (incluso anónimo) siempre que sea en este bucket.
CREATE POLICY "Papeletas Public Upload"
ON storage.objects FOR INSERT
WITH CHECK (
  bucket_id = 'papeletas'
);

-- 3. Crear política de ACTUALIZACIÓN ABIERTA (opcional, por si re-suben el archivo)
CREATE POLICY "Papeletas Public Update"
ON storage.objects FOR UPDATE
USING (
  bucket_id = 'papeletas'
);

-- 4. Asegurar lectura pública (ya debería estar, pero reforzamos)
DROP POLICY IF EXISTS "Papeletas Public Read" ON storage.objects;
CREATE POLICY "Papeletas Public Read"
ON storage.objects FOR SELECT
USING ( bucket_id = 'papeletas' );

-- 5. Asegurar que el bucket sea público
UPDATE storage.buckets
SET public = true
WHERE id = 'papeletas';
