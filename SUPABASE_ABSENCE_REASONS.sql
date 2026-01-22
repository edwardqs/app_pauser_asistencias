-- Crear tabla para gestionar los tipos de motivos de asistencia
-- Esto permitirá configurar dinámicamente qué motivos requieren evidencia (archivos)

CREATE TABLE IF NOT EXISTS public.absence_reasons (
    id SERIAL PRIMARY KEY,
    name text NOT NULL UNIQUE,       -- Nombre del motivo (ej: 'ENFERMEDAD COMUN')
    requires_evidence boolean DEFAULT false, -- Si requiere subir archivo
    is_active boolean DEFAULT true,  -- Si está activo para seleccionarse
    created_at timestamp with time zone DEFAULT NOW()
);

-- Insertar motivos iniciales basados en tu requerimiento
INSERT INTO public.absence_reasons (name, requires_evidence)
VALUES 
    ('ASISTENCIA', false),
    ('AUSENCIA SIN AVISO', false),
    ('ENFERMEDAD COMUN', true),      -- Requiere archivo
    ('MOTIVOS DE SALUD', true),      -- Requiere archivo
    ('MOTIVOS FAMILIARES Y/O PERSONALES', false),
    ('RENUNCIAS', true),             -- Requiere archivo
    ('TRÁMITES', true),              -- Requiere archivo
    ('VIAJES', false),
    ('PERMISO', false),
    ('VACACIONES', false),
    ('LICENCIA', true)               -- Asumimos que licencia médica requiere archivo
ON CONFLICT (name) DO UPDATE 
SET requires_evidence = EXCLUDED.requires_evidence;

-- Habilitar acceso de lectura a usuarios autenticados
ALTER TABLE public.absence_reasons ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Allow read access for authenticated users"
ON public.absence_reasons
FOR SELECT
TO authenticated
USING (true);
