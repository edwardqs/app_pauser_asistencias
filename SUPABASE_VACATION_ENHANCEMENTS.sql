-- =============================================================================
-- MEJORAS AL SISTEMA DE VACACIONES (AUDITORÍA, VALIDACIÓN Y PARCIALES)
-- =============================================================================

-- 1. TABLA DE LOGS DE ACTIVIDAD (Si no existe)
CREATE TABLE IF NOT EXISTS public.activity_logs (
    id uuid DEFAULT gen_random_uuid() PRIMARY KEY,
    description text NOT NULL,
    type text NOT NULL,
    metadata jsonb,
    created_at timestamp with time zone DEFAULT now()
);

-- 2. SOPORTE PARA DÍAS PARCIALES
-- Cambiamos total_days de integer a numeric para permitir 0.5, 1.5, etc.
ALTER TABLE public.vacation_requests ALTER COLUMN total_days TYPE numeric(5,2);

-- 3. TRIGGER PARA VALIDAR SUPERPOSICIÓN (OVERLAP)
-- Se asegura de que no se inserten vacaciones que se crucen con otras aprobadas/pendientes.
CREATE OR REPLACE FUNCTION public.tr_check_vacation_overlap_func()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
DECLARE
    v_result json;
BEGIN
    -- Solo verificar si es INSERT o si cambiaron las fechas en UPDATE
    IF (TG_OP = 'INSERT') OR (OLD.start_date <> NEW.start_date OR OLD.end_date <> NEW.end_date) THEN
        -- Llamamos a la función de chequeo existente
        -- Nota: Asegurarse que check_vacation_overlap esté definida (ver SUPABASE_VACATION_VALIDATION_AND_NOTIFICATIONS.sql)
        v_result := public.check_vacation_overlap(NEW.employee_id, NEW.start_date, NEW.end_date);
        
        IF (v_result->>'allowed')::boolean = false THEN
            RAISE EXCEPTION '%', v_result->>'reason';
        END IF;
    END IF;
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS tr_check_vacation_overlap ON public.vacation_requests;
CREATE TRIGGER tr_check_vacation_overlap
BEFORE INSERT OR UPDATE ON public.vacation_requests
FOR EACH ROW
EXECUTE FUNCTION public.tr_check_vacation_overlap_func();

-- 4. TRIGGER PARA AUDITORÍA DE CAMBIOS DE ESTADO
-- Registra en activity_logs cada vez que una solicitud cambia de estado.
CREATE OR REPLACE FUNCTION public.log_vacation_status_change()
RETURNS TRIGGER
LANGUAGE plpgsql
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
                'updated_by', auth.uid() -- ID del usuario que hizo el cambio (Supervisor)
            )
        );
    END IF;
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS tr_log_vacation_status ON public.vacation_requests;
CREATE TRIGGER tr_log_vacation_status
AFTER UPDATE ON public.vacation_requests
FOR EACH ROW
EXECUTE FUNCTION public.log_vacation_status_change();
