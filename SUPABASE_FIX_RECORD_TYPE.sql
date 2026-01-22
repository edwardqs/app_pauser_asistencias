-- =================================================================
-- SOLUCIÓN CRÍTICA: Eliminar restricciones de record_type
-- =================================================================

-- 1. Eliminar cualquier restricción CHECK en la columna record_type
-- (Probamos con nombres comunes de constraints)
ALTER TABLE public.attendance DROP CONSTRAINT IF EXISTS attendance_record_type_check;
ALTER TABLE public.attendance DROP CONSTRAINT IF EXISTS check_record_type;
ALTER TABLE public.attendance DROP CONSTRAINT IF EXISTS attendance_record_type_check1;

-- 2. Asegurar que la columna sea TEXT y acepte cualquier valor
ALTER TABLE public.attendance ALTER COLUMN record_type TYPE text;

-- 3. Actualizar RPC de Registro Manual (register_manual_attendance)
--    Para que no valide 'IN'/'OUT'/'ASISTENCIA' y acepte cualquier string.

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
BEGIN
  -- Verificar que el empleado existe
  SELECT * INTO v_employee FROM employees WHERE id = p_employee_id;
  IF v_employee IS NULL THEN
    RETURN json_build_object('success', false, 'message', 'Empleado no encontrado');
  END IF;
  
  -- Verificar permisos del supervisor
  SELECT * INTO v_supervisor FROM employees WHERE id = p_supervisor_id;
  IF v_supervisor IS NULL THEN
    RETURN json_build_object('success', false, 'message', 'Supervisor no encontrado');
  END IF;
  
  -- Roles válidos
  IF v_supervisor.role NOT IN ('SUPERVISOR_VENTAS', 'SUPERVISOR_OPERACIONES', 'JEFE_VENTAS', 'COORDINADOR_OPERACIONES', 'ADMIN', 'ANALISTA_RRHH', 'JEFE_RRHH') THEN
    RETURN json_build_object('success', false, 'message', 'Sin permisos de supervisor');
  END IF;
  
  -- Verificar si ya existe registro para esa fecha
  SELECT * INTO v_existing FROM attendance 
  WHERE employee_id = p_employee_id AND work_date = p_work_date;
  
  IF v_existing IS NOT NULL THEN
    RETURN json_build_object(
      'success', false, 
      'message', 'Ya existe un registro para esta fecha (' || v_existing.record_type || ')'
    );
  END IF;
  
  -- Normalizar tipo de registro
  -- Si es 'ABSENCE', lo guardamos como 'AUSENCIA' o el valor que venga
  IF p_record_type = 'ABSENCE' THEN
     v_final_type := 'AUSENCIA';
  ELSIF p_record_type = 'IN' THEN
     v_final_type := 'ASISTENCIA';
  ELSE
     v_final_type := p_record_type; -- 'ENFERMEDAD COMUN', etc.
  END IF;

  -- Insertar registro manual
  INSERT INTO attendance (
    employee_id,
    work_date,
    check_in,
    check_out,
    record_type,
    notes,
    evidence_url,
    registered_by,
    validated,
    validated_by,
    validation_date,
    status,
    is_late,
    location_in -- Opcional: Guardar ubicación si viene del móvil
  ) VALUES (
    p_employee_id,
    p_work_date,
    p_check_in,
    p_check_out,
    v_final_type, -- Usamos el tipo normalizado
    COALESCE(p_notes, 'Registro manual por supervisor'),
    p_evidence_url,
    p_supervisor_id,
    true, 
    p_supervisor_id,
    NOW(),
    CASE WHEN v_final_type = 'ASISTENCIA' THEN 'ON_TIME' ELSE 'PENDIENTE' END,
    p_is_late,
    p_location
  ) RETURNING id INTO v_new_attendance_id;
  
  -- Registrar en activity_logs
  INSERT INTO activity_logs (description, type, metadata)
  VALUES (
    'Registro manual por ' || v_supervisor.full_name,
    'MANUAL_REGISTRATION',
    json_build_object(
      'attendance_id', v_new_attendance_id,
      'supervisor_id', p_supervisor_id,
      'employee_id', p_employee_id,
      'record_type', v_final_type
    )
  );
  
  RETURN json_build_object(
    'success', true, 
    'message', 'Registro manual creado correctamente',
    'attendance_id', v_new_attendance_id
  );
END;
$$;
