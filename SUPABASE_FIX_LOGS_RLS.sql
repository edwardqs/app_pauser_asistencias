-- =============================================================================
-- FIX: ERROR RLS EN ACTIVITY_LOGS
-- =============================================================================

-- El error "new row violates row-level security policy for table activity_logs"
-- ocurre porque el trigger se ejecuta con los permisos del usuario (SECURITY INVOKER),
-- y la tabla activity_logs tiene RLS activado pero sin política de INSERT para el usuario.

-- SOLUCIÓN:
-- Convertimos la función del trigger a SECURITY DEFINER.
-- Esto hace que se ejecute con los permisos del creador de la función (Admin/Postgres),
-- ignorando las restricciones RLS del usuario que dispara el evento.

CREATE OR REPLACE FUNCTION public.log_vacation_status_change()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER -- << CAMBIO CLAVE
AS $$
BEGIN
    IF (TG_OP = 'UPDATE' AND OLD.status <> NEW.status) THEN
        INSERT INTO public.activity_logs (description, type, metadata)
        VALUES (
            'Solicitud de vacaciones ' || NEW.id || ' cambió de ' || OLD.status || ' a ' || NEW.status,
            'VACATION_STATUS_CHANGE',
            json_build_object(
                'request_id', NEW.id,
                'employee_id', NEW.employee_id,
                'old_status', OLD.status,
                'new_status', NEW.status,
                'updated_by', auth.uid(),
                'timestamp', now()
            )
        );
    END IF;
    RETURN NEW;
END;
$$;

-- OPCIONAL: Asegurar que se puedan leer los logs (para futuros reportes)
ALTER TABLE public.activity_logs ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Admins can view logs" ON public.activity_logs;
CREATE POLICY "Admins can view logs"
ON public.activity_logs FOR SELECT
TO authenticated
USING (
    -- Permitir ver a todos por ahora, o restringir a roles específicos
    true
);

-- NOTA: No creamos política de INSERT porque confiamos en el trigger SECURITY DEFINER.
