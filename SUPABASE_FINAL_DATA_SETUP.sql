-- =================================================================
-- CONFIGURACIÓN FINAL DE DATOS Y LÓGICA (CLEAN SETUP)
-- =================================================================

-- 1. LIMPIEZA Y CARGA DE MOTIVOS EXACTOS
-- Borramos todo para asegurar que no haya basura
TRUNCATE TABLE public.absence_reasons;

-- Insertamos SOLO los motivos autorizados de la imagen
INSERT INTO public.absence_reasons (name, requires_evidence, is_active)
VALUES 
    ('AUSENCIA SIN AVISO', false, true),
    ('ENFERMEDAD COMUN', true, true),
    ('MOTIVOS DE SALUD', true, true),
    ('MOTIVOS FAMILIARES Y/O PERSONALES', false, true),
    ('RENUNCIAS', true, true),
    ('TRÁMITES', true, true),
    ('VIAJES', false, true);
    -- Nota: Si necesitas 'VACACIONES' o 'PERMISO', agrégalos aquí manualmente.

-- 2. LIBERACIÓN DE RESTRICCIONES (CRÍTICO PARA QUE FUNCIONE EL REGISTRO)
-- Esto permite que el backend acepte los nombres largos como "MOTIVOS FAMILIARES..."
ALTER TABLE public.attendance DROP CONSTRAINT IF EXISTS attendance_record_type_check;
ALTER TABLE public.attendance DROP CONSTRAINT IF EXISTS check_record_type;
ALTER TABLE public.attendance ALTER COLUMN record_type TYPE text;

-- 3. ACTUALIZACIÓN DEL RPC (Manteniendo lógica de horarios)
CREATE OR REPLACE FUNCTION public.register_manual_attendance(
  p_employee_id uuid,
  p_supervisor_id uuid,
  p_work_date date,
  p_check_in timestamp with time zone,
  p_check_out timestamp with time zone DEFAULT NULL,
  p_record_type text DEFAULT 'ASISTENCIA',
  p_notes text DEFAULT NULL,
  p_evidence_url text DEFAULT NULL,
  p_is_late boolean DEFAULT false,
  p_location jsonb DEFAULT NULL
)
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_supervisor RECORD;
  v_employee RECORD;
  v_existing RECORD;
  v_new_attendance_id uuid;
  v_final_type text;
  v_status text;
BEGIN
  -- Verificar Empleado
  SELECT * INTO v_employee FROM employees WHERE id = p_employee_id;
  IF v_employee IS NULL THEN RETURN json_build_object('success', false, 'message', 'Empleado no encontrado'); END IF;
  
  -- Verificar Supervisor
  SELECT * INTO v_supervisor FROM employees WHERE id = p_supervisor_id;
  IF v_supervisor IS NULL THEN RETURN json_build_object('success', false, 'message', 'Supervisor no encontrado'); END IF;
  
  -- Verificar si ya existe registro
  SELECT * INTO v_existing FROM attendance WHERE employee_id = p_employee_id AND work_date = p_work_date;
  IF v_existing IS NOT NULL THEN
    RETURN json_build_object('success', false, 'message', 'Ya existe un registro para esta fecha: ' || v_existing.record_type);
  END IF;

  -- LÓGICA DE NORMALIZACIÓN Y HORARIOS
  IF p_record_type = 'IN' THEN
     v_final_type := 'ASISTENCIA';
     v_status := 'ON_TIME';
     -- Nota: La tardanza (is_late) ya viene calculada desde el App Móvil (p_is_late)
     -- pero podríamos re-verificarla aquí si quisiéramos doble seguridad.
     -- Por ahora confiamos en el parámetro o en la lógica manual.
  ELSE
     -- Cualquier otro motivo (Enfermedad, Viajes, etc.)
     v_final_type := p_record_type;
     v_status := 'PENDIENTE'; -- Motivos especiales quedan pendientes de revisión si se desea
  END IF;

  -- Insertar
  INSERT INTO attendance (
    employee_id, work_date, check_in, check_out, 
    record_type, notes, evidence_url, registered_by, 
    validated, validated_by, validation_date, 
    status, is_late, location_in
  ) VALUES (
    p_employee_id, p_work_date, p_check_in, p_check_out,
    v_final_type, -- Se guarda el nombre exacto del motivo
    COALESCE(p_notes, 'Registro manual por supervisor'),
    p_evidence_url,
    p_supervisor_id,
    true, p_supervisor_id, NOW(),
    v_status,
    p_is_late, -- Se respeta el cálculo de la App
    p_location
  ) RETURNING id INTO v_new_attendance_id;
  
  RETURN json_build_object('success', true, 'message', 'Registro creado correctamente');
END;
$$;
