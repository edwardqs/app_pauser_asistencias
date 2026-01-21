-- CREACIÓN DE BUCKET DE STORAGE PARA EVIDENCIAS
-- Este script asegura que el bucket exista y tenga las políticas de seguridad correctas.

-- 1. Crear el bucket 'attendance_evidence' si no existe
INSERT INTO storage.buckets (id, name, public)
VALUES ('attendance_evidence', 'attendance_evidence', true)
ON CONFLICT (id) DO NOTHING;

-- 2. Habilitar políticas de seguridad (RLS)
-- Usamos nombres ÚNICOS y ESPECÍFICOS para evitar errores de "Policy already exists"
-- Primero limpiamos nuestras propias políticas por si acaso
DROP POLICY IF EXISTS "Attendance Evidence Public Read" ON storage.objects;
DROP POLICY IF EXISTS "Attendance Evidence Auth Upload" ON storage.objects;

-- Permitir lectura pública (para que los jefes vean las fotos)
CREATE POLICY "Attendance Evidence Public Read"
ON storage.objects FOR SELECT
USING ( bucket_id = 'attendance_evidence' );

-- Permitir subida a cualquier usuario autenticado
CREATE POLICY "Attendance Evidence Auth Upload"
ON storage.objects FOR INSERT
WITH CHECK (
  bucket_id = 'attendance_evidence' 
  AND auth.role() = 'authenticated'
);
