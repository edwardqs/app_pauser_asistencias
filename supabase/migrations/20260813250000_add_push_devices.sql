-- Devices registered for real push notifications (FCM).
CREATE TABLE IF NOT EXISTS public.push_devices (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    employee_id uuid NOT NULL REFERENCES public.employees(id) ON DELETE CASCADE,
    token text NOT NULL,
    platform text NOT NULL DEFAULT 'android',
    app_version text,
    last_seen_at timestamptz NOT NULL DEFAULT now(),
    created_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (token)
);

CREATE INDEX IF NOT EXISTS idx_push_devices_employee_id
    ON public.push_devices (employee_id);
CREATE INDEX IF NOT EXISTS idx_push_devices_last_seen_at
    ON public.push_devices (last_seen_at DESC);

ALTER TABLE public.push_devices ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "push_devices_select_own" ON public.push_devices;
CREATE POLICY "push_devices_select_own"
    ON public.push_devices
    FOR SELECT
    TO public
    USING (employee_id = (SELECT id FROM public.employees WHERE email = auth.email()));

DROP POLICY IF EXISTS "push_devices_service_all" ON public.push_devices;
CREATE POLICY "push_devices_service_all"
    ON public.push_devices
    FOR ALL
    TO service_role
    USING (true)
    WITH CHECK (true);

-- Registra o actualiza el token de un dispositivo. Solo el empleado con el
-- mismo email del JWT puede registrar tokens.
CREATE OR REPLACE FUNCTION public.upsert_push_device(
    p_token text,
    p_platform text DEFAULT 'android',
    p_app_version text DEFAULT NULL::text
)
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO public
AS $function$
DECLARE
    v_employee_id uuid;
BEGIN
    IF p_token IS NULL OR length(trim(p_token)) = 0 THEN
        RETURN json_build_object('success', false, 'message', 'Token vacio');
    END IF;

    SELECT e.id
    INTO v_employee_id
    FROM public.employees e
    WHERE e.email = auth.email();

    IF v_employee_id IS NULL THEN
        RETURN json_build_object('success', false, 'message', 'Empleado no identificado');
    END IF;

    INSERT INTO public.push_devices (employee_id, token, platform, app_version, last_seen_at)
    VALUES (v_employee_id, trim(p_token), coalesce(p_platform, 'android'), p_app_version, now())
    ON CONFLICT (token) DO UPDATE SET
        employee_id = v_employee_id,
        platform = coalesce(p_platform, push_devices.platform),
        app_version = coalesce(p_app_version, push_devices.app_version),
        last_seen_at = now();

    RETURN json_build_object('success', true, 'token_registered', true);
END;
$function$;

GRANT EXECUTE ON FUNCTION public.upsert_push_device(text, text, text)
    TO anon, authenticated, service_role;
