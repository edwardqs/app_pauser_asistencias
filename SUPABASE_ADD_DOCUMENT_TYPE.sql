-- Script para agregar columna 'document_type' a la tabla employees
-- Permite diferenciar entre DNI y Carnét de Extranjería (CE)

-- 1. Agregar columna si no existe
ALTER TABLE public.employees 
ADD COLUMN IF NOT EXISTS document_type text DEFAULT 'DNI';

-- 2. Actualizar registros existentes para que tengan 'DNI' por defecto si son nulos
UPDATE public.employees 
SET document_type = 'DNI' 
WHERE document_type IS NULL;

-- 3. Comentario
COMMENT ON COLUMN public.employees.document_type IS 'Tipo de documento de identidad: DNI o CE';
