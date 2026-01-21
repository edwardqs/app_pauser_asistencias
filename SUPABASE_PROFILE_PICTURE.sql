-- 1. Agregar columna de foto de perfil a la tabla employees
ALTER TABLE public.employees 
ADD COLUMN IF NOT EXISTS profile_picture_url text;

-- 2. Crear bucket de almacenamiento 'avatars' si no existe
-- Nota: Esto se debe hacer desde el dashboard de Supabase si no se tiene acceso a la API de storage desde SQL puro en todas las versiones,
-- pero intentaremos insertar la configuración si es posible.
-- En Supabase standard, los buckets se crean en la tabla storage.buckets.

INSERT INTO storage.buckets (id, name, public)
VALUES ('avatars', 'avatars', true)
ON CONFLICT (id) DO NOTHING;

-- 3. Políticas de Seguridad (RLS) para el bucket 'avatars'

-- Permitir acceso público de lectura a todos
CREATE POLICY "Avatar images are publicly accessible"
ON storage.objects FOR SELECT
USING ( bucket_id = 'avatars' );

-- Permitir a los usuarios subir sus propios avatares
-- Asumimos que el nombre del archivo será el ID del usuario o contendrá el ID para validar,
-- O simplemente permitimos autenticados. Para mayor seguridad, validamos que el usuario esté autenticado.
CREATE POLICY "Authenticated users can upload avatars"
ON storage.objects FOR INSERT
TO authenticated
WITH CHECK ( bucket_id = 'avatars' );

-- Permitir a los usuarios actualizar sus propios avatares
CREATE POLICY "Authenticated users can update avatars"
ON storage.objects FOR UPDATE
TO authenticated
USING ( bucket_id = 'avatars' );

-- 4. Trigger de Auditoría para cambios de foto (Opcional según requisitos)
CREATE OR REPLACE FUNCTION public.log_profile_picture_change()
RETURNS TRIGGER AS $$
BEGIN
    IF (OLD.profile_picture_url IS DISTINCT FROM NEW.profile_picture_url) THEN
        INSERT INTO public.activity_logs (description, type, metadata)
        VALUES (
            'Foto de perfil actualizada para: ' || NEW.full_name,
            'UPDATE_EMPLOYEE',
            jsonb_build_object(
                'employee_id', NEW.id,
                'old_url', OLD.profile_picture_url,
                'new_url', NEW.profile_picture_url
            )
        );
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

DROP TRIGGER IF EXISTS on_profile_picture_change ON public.employees;
CREATE TRIGGER on_profile_picture_change
    AFTER UPDATE OF profile_picture_url
    ON public.employees
    FOR EACH ROW
    EXECUTE FUNCTION public.log_profile_picture_change();
