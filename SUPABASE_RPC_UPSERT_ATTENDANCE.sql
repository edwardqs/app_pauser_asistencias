-- =================================================================
-- ACTUALIZACIÓN RPC: SOPORTE PARA "UPSERT" (ACTUALIZAR SI EXISTE)
-- =================================================================

CREATE OR REPLACE FUNCTION public.register_manual_attendance(
  p_employee_id uuid,
  p_supervisor_id uuid,
  p_work_date date,
  p_check_in timestamp with time zone,
  p_check_out timestamp with time zone DEFAULT NULL,
  p_record_type text DEFAULT 'ASISTENCIA',
  p_subcategory text DEFAULT NULL,
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
  
  -- Lógica de Tipos
  IF p_record_type = 'IN' THEN
     v_final_type := 'ASISTENCIA';
     v_status := 'ON_TIME';
  ELSE
     v_final_type := p_record_type;
     v_status := 'PENDIENTE';
  END IF;

  -- Verificar si ya existe registro
  SELECT * INTO v_existing FROM attendance WHERE employee_id = p_employee_id AND work_date = p_work_date;
  
  IF v_existing IS NOT NULL THEN
    -- =========================================================
    -- MODO EDICIÓN (UPDATE)
    -- =========================================================
    UPDATE attendance
    SET 
      check_in = p_check_in,
      check_out = p_check_out,
      record_type = v_final_type,
      subcategory = p_subcategory,
      notes = COALESCE(p_notes, notes), -- Mantiene nota anterior si no se envía nueva
      evidence_url = COALESCE(p_evidence_url, evidence_url),
      registered_by = p_supervisor_id,
      validated = true,
      validated_by = p_supervisor_id,
      validation_date = NOW(),
      status = v_status,
      is_late = p_is_late
    WHERE id = v_existing.id
    RETURNING id INTO v_new_attendance_id;

    -- Log de actualización
    INSERT INTO activity_logs (description, type, metadata)
    VALUES ('Registro actualizado manualmente por ' || v_supervisor.full_name, 'MANUAL_UPDATE', 
      json_build_object('attendance_id', v_new_attendance_id, 'prev_type', v_existing.record_type, 'new_type', v_final_type));

    RETURN json_build_object('success', true, 'message', 'Registro actualizado correctamente');

  ELSE
    -- =========================================================
    -- MODO INSERCIÓN (INSERT)
    -- =========================================================
    INSERT INTO attendance (
      employee_id, work_date, check_in, check_out, 
      record_type, subcategory, notes, evidence_url, registered_by, 
      validated, validated_by, validation_date, 
      status, is_late, location_in
    ) VALUES (
      p_employee_id, p_work_date, p_check_in, p_check_out,
      v_final_type, p_subcategory,
      COALESCE(p_notes, 'Registro manual por supervisor'),
      p_evidence_url,
      p_supervisor_id,
      true, p_supervisor_id, NOW(),
      v_status,
      p_is_late,
      p_location
    ) RETURNING id INTO v_new_attendance_id;
    
    RETURN json_build_object('success', true, 'message', 'Registro creado correctamente');
  END IF;

END;
$$;
