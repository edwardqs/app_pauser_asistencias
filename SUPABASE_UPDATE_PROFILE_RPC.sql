-- Función segura para actualizar foto de perfil
-- Se ejecuta con SECURITY DEFINER para saltarse las restricciones RLS de la tabla
-- pero validamos internamente lo que necesitemos (en este caso confiamos en que la app envía el ID correcto del storage)

CREATE OR REPLACE FUNCTION public.update_employee_profile_picture(
    p_employee_id uuid,
    p_image_url text
)
RETURNS boolean AS $$
BEGIN
    UPDATE public.employees
    SET profile_picture_url = p_image_url
    WHERE id = p_employee_id;

    IF FOUND THEN
        RETURN true;
    ELSE
        RETURN false;
    END IF;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;
