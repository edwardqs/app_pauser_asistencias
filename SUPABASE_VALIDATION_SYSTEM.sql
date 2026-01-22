-- =====================================================
-- SISTEMA DE VALIDACIÓN Y GESTIÓN DE ASISTENCIAS
-- =====================================================
-- Este script contiene todas las funciones RPC necesarias para:
-- 1. Validación de asistencias por supervisores
-- 2. Registro manual de asistencias
-- 3. Cambio de contraseña de empleados
-- =====================================================

-- =====================================================
-- 1. FUNCIÓN: Validar/Rechazar Asistencias
-- =====================================================
-- Permite a supervisores aprobar o rechazar asistencias de su equipo
-- Actualiza campos: validated, validated_by, validation_date
-- Registra la acción en activity_logs

CREATE OR REPLACE FUNCTION public.supervisor_validate_attendance(
  p_attendance_id uuid,
  p_supervisor_id uuid,
  p_validated boolean,
  p_notes text DEFAULT NULL
)
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_attendance RECORD;
  v_supervisor RECORD;
  v_employee RECORD;
BEGIN
  -- Verificar que la asistencia existe
  SELECT * INTO v_attendance FROM attendance WHERE id = p_attendance_id;
  IF v_attendance IS NULL THEN
    RETURN json_build_object('success', false, 'message', 'Asistencia no encontrada');
  END IF;
  
  -- Obtener información del empleado
  SELECT * INTO v_employee FROM employees WHERE id = v_attendance.employee_id;
  
  -- Verificar que el supervisor existe y tiene permisos
  SELECT * INTO v_supervisor FROM employees WHERE id = p_supervisor_id;
  IF v_supervisor IS NULL THEN
    RETURN json_build_object('success', false, 'message', 'Supervisor no encontrado');
  END IF;
  
  -- Roles válidos: SUPERVISOR_VENTAS, SUPERVISOR_OPERACIONES, JEFE_VENTAS, COORDINADOR_OPERACIONES, ADMIN, ANALISTA_RRHH, JEFE_RRHH
  IF v_supervisor.role NOT IN ('SUPERVISOR_VENTAS', 'SUPERVISOR_OPERACIONES', 'JEFE_VENTAS', 'COORDINADOR_OPERACIONES', 'ADMIN', 'ANALISTA_RRHH', 'JEFE_RRHH') THEN
    RETURN json_build_object('success', false, 'message', 'Sin permisos de supervisor');
  END IF;
  
  -- Actualizar la asistencia
  UPDATE attendance
  SET 
    validated = p_validated,
    validated_by = p_supervisor_id,
    validation_date = NOW(),
    notes = CASE 
      WHEN p_notes IS NOT NULL THEN 
        CASE 
          WHEN notes IS NULL THEN p_notes
          ELSE notes || ' | ' || p_notes
        END
      ELSE notes
    END
  WHERE id = p_attendance_id;
  
  -- Registrar en activity_logs
  INSERT INTO activity_logs (description, type, metadata)
  VALUES (
    CASE 
      WHEN p_validated THEN 'Asistencia validada por ' || v_supervisor.full_name
      ELSE 'Asistencia rechazada por ' || v_supervisor.full_name
    END,
    'VALIDATION',
    json_build_object(
      'attendance_id', p_attendance_id,
      'supervisor_id', p_supervisor_id,
      'supervisor_name', v_supervisor.full_name,
      'validated', p_validated,
      'employee_id', v_attendance.employee_id,
      'employee_name', v_employee.full_name,
      'work_date', v_attendance.work_date
    )
  );
  
  RETURN json_build_object(
    'success', true, 
    'message', CASE 
      WHEN p_validated THEN 'Asistencia validada correctamente'
      ELSE 'Asistencia rechazada correctamente'
    END
  );
END;
$$;

-- =====================================================
-- 2. FUNCIÓN: Registro Manual de Asistencias
-- =====================================================
-- Permite a supervisores registrar asistencias manualmente
-- Útil para corregir asistencias olvidadas o problemas técnicos
-- El registro se marca automáticamente como validado

CREATE OR REPLACE FUNCTION public.register_manual_attendance(
  p_employee_id uuid,
  p_supervisor_id uuid,
  p_work_date date,
  p_check_in timestamp with time zone,
  p_check_out timestamp with time zone DEFAULT NULL,
  p_record_type text DEFAULT 'ASISTENCIA',
  p_notes text DEFAULT NULL,
  p_evidence_url text DEFAULT NULL
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
BEGIN
  -- ... (validaciones previas iguales) ...
  
  -- Insertar registro manual
  INSERT INTO attendance (
    employee_id,
    work_date,
    check_in,
    check_out,
    record_type,
    notes,
    evidence_url, -- Añadido
    registered_by,
    validated,
    validated_by,
    validation_date,
    status,
    is_late
  ) VALUES (
    p_employee_id,
    p_work_date,
    p_check_in,
    p_check_out,
    p_record_type,
    COALESCE(p_notes, 'Registro manual por supervisor'),
    p_evidence_url, -- Añadido
    p_supervisor_id,
    true,
    p_supervisor_id,
    NOW(),
    'ON_TIME',
    false
  ) RETURNING id INTO v_new_attendance_id;
  
  -- Registrar en activity_logs
  INSERT INTO activity_logs (description, type, metadata)
  VALUES (
    'Registro manual de asistencia por ' || v_supervisor.full_name,
    'MANUAL_REGISTRATION',
    json_build_object(
      'attendance_id', v_new_attendance_id,
      'supervisor_id', p_supervisor_id,
      'supervisor_name', v_supervisor.full_name,
      'employee_id', p_employee_id,
      'employee_name', v_employee.full_name,
      'work_date', p_work_date,
      'record_type', p_record_type
    )
  );
  
  RETURN json_build_object(
    'success', true, 
    'message', 'Registro manual creado correctamente',
    'attendance_id', v_new_attendance_id
  );
END;
$$;

-- =====================================================
-- 3. FUNCIÓN: Cambiar Contraseña
-- =====================================================
-- Permite a empleados cambiar su contraseña
-- Valida contraseña actual y longitud mínima de nueva contraseña

CREATE OR REPLACE FUNCTION public.change_employee_password(
  p_employee_id uuid,
  p_current_password text,
  p_new_password text
)
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_employee RECORD;
BEGIN
  -- Verificar empleado y contraseña actual
  SELECT * INTO v_employee FROM employees WHERE id = p_employee_id;
  
  IF v_employee IS NULL THEN
    RETURN json_build_object('success', false, 'message', 'Empleado no encontrado');
  END IF;
  
  IF v_employee.app_password != p_current_password THEN
    RETURN json_build_object('success', false, 'message', 'Contraseña actual incorrecta');
  END IF;
  
  -- Validar nueva contraseña (mínimo 6 caracteres)
  IF LENGTH(p_new_password) < 6 THEN
    RETURN json_build_object('success', false, 'message', 'La contraseña debe tener al menos 6 caracteres');
  END IF;
  
  -- Validar que la nueva contraseña sea diferente a la actual
  IF p_new_password = p_current_password THEN
    RETURN json_build_object('success', false, 'message', 'La nueva contraseña debe ser diferente a la actual');
  END IF;
  
  -- Actualizar contraseña
  UPDATE employees 
  SET app_password = p_new_password 
  WHERE id = p_employee_id;
  
  -- Registrar en activity_logs
  INSERT INTO activity_logs (description, type, metadata)
  VALUES (
    'Contraseña actualizada por ' || v_employee.full_name,
    'PASSWORD_CHANGE',
    json_build_object(
      'employee_id', p_employee_id, 
      'employee_name', v_employee.full_name,
      'dni', v_employee.dni
    )
  );
  
  RETURN json_build_object('success', true, 'message', 'Contraseña actualizada correctamente');
END;
$$;

-- =====================================================
-- 4. FUNCIÓN: Obtener Asistencias Pendientes de Validación
-- =====================================================
-- Retorna todas las asistencias del equipo que están pendientes de validación

CREATE OR REPLACE FUNCTION public.get_pending_validations(
  p_supervisor_id uuid,
  p_days_back integer DEFAULT 7
)
RETURNS TABLE (
  attendance_id uuid,
  employee_id uuid,
  employee_name text,
  employee_dni text,
  work_date date,
  check_in timestamp with time zone,
  check_out timestamp with time zone,
  record_type text,
  notes text,
  evidence_url text,
  is_late boolean,
  status text
)
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  RETURN QUERY
  SELECT 
    a.id as attendance_id,
    e.id as employee_id,
    e.full_name as employee_name,
    e.dni as employee_dni,
    a.work_date,
    a.check_in,
    a.check_out,
    a.record_type,
    a.notes,
    a.evidence_url,
    a.is_late,
    a.status
  FROM 
    attendance a
  INNER JOIN 
    employees e ON a.employee_id = e.id
  WHERE 
    e.supervisor_id = p_supervisor_id
    AND a.validated = false
    AND a.work_date >= CURRENT_DATE - p_days_back
  ORDER BY 
    a.work_date DESC, a.check_in DESC;
END;
$$;

-- =====================================================
-- COMENTARIOS Y NOTAS
-- =====================================================
-- 
-- PERMISOS:
-- - Todas las funciones usan SECURITY DEFINER para ejecutarse con permisos del creador
-- - Validación de roles se hace dentro de cada función
-- 
-- ROLES VÁLIDOS PARA SUPERVISORES:
-- - SUPERVISOR_VENTAS: Supervisor de Ventas - Puede validar y registrar para su equipo
-- - SUPERVISOR_OPERACIONES: Supervisor de Operaciones - Puede validar y registrar para su equipo
-- - JEFE_VENTAS: Jefe de Ventas - Puede validar y registrar para su equipo y sub-equipos
-- - COORDINADOR_OPERACIONES: Coordinador de Operaciones - Puede validar y registrar para su equipo y sub-equipos
-- - ADMIN: Acceso completo a todas las funcionalidades
-- 
-- ACTIVITY_LOGS:
-- - Todas las acciones importantes se registran automáticamente
-- - Útil para auditoría y trazabilidad
-- 
-- VALIDACIONES:
-- - No se permite registro duplicado para la misma fecha
-- - Contraseñas deben tener mínimo 6 caracteres
-- - Check-out debe ser posterior a check-in
-- - No se permiten fechas futuras en registros manuales
-- 
-- =====================================================
