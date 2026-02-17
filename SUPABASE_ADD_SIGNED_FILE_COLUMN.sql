-- Agregar columna para archivo firmado (PDF o Imagen) si no existe
-- Usamos 'signed_file_url' para coincidir con la app móvil
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'vacation_requests' AND column_name = 'signed_file_url') THEN
        ALTER TABLE public.vacation_requests ADD COLUMN signed_file_url text;
    END IF;
    
    -- Agregar columna de fecha de firma si no existe
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'vacation_requests' AND column_name = 'signed_at') THEN
        ALTER TABLE public.vacation_requests ADD COLUMN signed_at timestamp with time zone;
    END IF;
END $$;

-- Asegurar que la columna anterior (si se creó por error) se migre o elimine si está vacía
-- (Opcional, pero limpio)
-- DO $$
-- BEGIN
--     IF EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'vacation_requests' AND column_name = 'signed_pdf_url') THEN
--         -- Aquí podrías migrar datos si hubiera
--         -- ALTER TABLE public.vacation_requests DROP COLUMN signed_pdf_url;
--     END IF;
-- END $$;
