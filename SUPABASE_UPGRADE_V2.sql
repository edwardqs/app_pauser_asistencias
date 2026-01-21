-- ACTUALIZACIÓN V2: Soporte para Jerarquía, Inasistencias y Evidencias

-- 1. Actualizar tabla EMPLOYEES con roles y jerarquía
ALTER TABLE public.employees 
ADD COLUMN IF NOT EXISTS role text DEFAULT 'OPERARIO', -- 'JEFE_VENTAS', 'SUPERVISOR', 'ANALISTA', 'VENDEDOR', 'CHOFER'
ADD COLUMN IF NOT EXISTS supervisor_id uuid REFERENCES public.employees(id);

-- 2. Actualizar tabla ATTENDANCE para soportar inasistencias y validación
ALTER TABLE public.attendance
ADD COLUMN IF NOT EXISTS record_type text DEFAULT 'ASISTENCIA', -- 'ASISTENCIA', 'INASISTENCIA', 'TARDANZA_JUSTIFICADA'
ADD COLUMN IF NOT EXISTS absence_reason text, -- 'ENFERMEDAD', 'SALUD', 'TRAMITES', etc.
ADD COLUMN IF NOT EXISTS evidence_url text, -- URL del archivo en Supabase Storage
ADD COLUMN IF NOT EXISTS validated boolean DEFAULT false, -- Para el check del Analista
ADD COLUMN IF NOT EXISTS validated_by uuid REFERENCES auth.users(id), -- Usuario web que validó
ADD COLUMN IF NOT EXISTS validation_date timestamp with time zone,
ADD COLUMN IF NOT EXISTS registered_by uuid REFERENCES public.employees(id); -- Si un supervisor registró por otro

-- 3. Crear Bucket de Storage para Evidencias (Si no existe)
-- Nota: Esto generalmente se hace desde el Dashboard, pero intentamos scriptarlo.
INSERT INTO storage.buckets (id, name, public)
VALUES ('evidence', 'evidence', true)
ON CONFLICT (id) DO NOTHING;

-- 4. Política de Storage (Permitir subida a autenticados)
CREATE POLICY "Permitir subida de evidencias a todos"
ON storage.objects FOR INSERT
WITH CHECK ( bucket_id = 'evidence' );

CREATE POLICY "Permitir ver evidencias a todos"
ON storage.objects FOR SELECT
USING ( bucket_id = 'evidence' );

-- 5. Actualizar función de registro para soportar inasistencias (Opcional, si se usa RPC para esto)
-- Se recomienda crear una nueva RPC específica para inasistencias o actualizar la existente.

CREATE OR REPLACE FUNCTION public.register_absence(
    p_employee_id uuid,
    p_reason text,
    p_evidence_url text,
    p_registered_by uuid DEFAULT NULL
)
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
AS $function$
DECLARE
    v_attendance_id uuid;
BEGIN
    INSERT INTO public.attendance (
        employee_id,
        work_date,
        record_type,
        absence_reason,
        evidence_url,
        registered_by,
        status,
        created_at
    ) VALUES (
        p_employee_id,
        CURRENT_DATE,
        'INASISTENCIA',
        p_reason,
        p_evidence_url,
        p_registered_by,
        'ausente', -- Status general
        now()
    ) RETURNING id INTO v_attendance_id;

    RETURN json_build_object(
        'success', true,
        'message', 'Inasistencia registrada correctamente',
        'id', v_attendance_id
    );
END;
$function$;
