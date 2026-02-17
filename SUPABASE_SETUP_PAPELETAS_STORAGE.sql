-- CONFIGURACIÓN COMPLETA PARA EL FLUJO DE FIRMA DIGITAL (PAPELETAS)

-- 1. Crear el bucket 'papeletas' si no existe
INSERT INTO storage.buckets (id, name, public)
VALUES ('papeletas', 'papeletas', true)
ON CONFLICT (id) DO UPDATE SET public = true;

-- 2. Asegurar columnas en la tabla vacation_requests
DO $$
BEGIN
    -- Columna para la URL del archivo firmado (subido por el usuario)
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'vacation_requests' AND column_name = 'signed_file_url') THEN
        ALTER TABLE public.vacation_requests ADD COLUMN signed_file_url text;
    END IF;
    
    -- Columna para la fecha de firma
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'vacation_requests' AND column_name = 'signed_at') THEN
        ALTER TABLE public.vacation_requests ADD COLUMN signed_at timestamp with time zone;
    END IF;

    -- Columna para la URL del PDF generado por el sistema (si no existiera)
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'vacation_requests' AND column_name = 'pdf_url') THEN
        ALTER TABLE public.vacation_requests ADD COLUMN pdf_url text;
    END IF;
END $$;

-- 3. Configurar Políticas de Seguridad (RLS) para el Storage
-- Primero eliminamos políticas antiguas para evitar conflictos
DROP POLICY IF EXISTS "Papeletas Public Read" ON storage.objects;
DROP POLICY IF EXISTS "Papeletas Auth Upload" ON storage.objects;
DROP POLICY IF EXISTS "Papeletas Auth Update" ON storage.objects;

-- Política de Lectura Pública (para que RRHH y el usuario puedan ver los PDFs)
CREATE POLICY "Papeletas Public Read"
ON storage.objects FOR SELECT
USING ( bucket_id = 'papeletas' );

-- Política de Escritura (Subida) para usuarios autenticados
CREATE POLICY "Papeletas Auth Upload"
ON storage.objects FOR INSERT
WITH CHECK (
  bucket_id = 'papeletas' 
  AND auth.role() = 'authenticated'
);

-- Política de Actualización (por si necesitan reemplazar el archivo)
CREATE POLICY "Papeletas Auth Update"
ON storage.objects FOR UPDATE
USING (
  bucket_id = 'papeletas' 
  AND auth.role() = 'authenticated'
);
