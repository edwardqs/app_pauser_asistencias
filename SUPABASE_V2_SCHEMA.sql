-- =================================================================
-- ACTUALIZACIÓN V2: GESTIÓN AVANZADA DE ASISTENCIAS Y VACACIONES
-- =================================================================

-- 1. ACTUALIZACIÓN DE TABLA ATTENDANCE
-- Añadimos columna para subcategorías (ej. 'Accidente común' para 'Descanso Médico')
ALTER TABLE public.attendance 
ADD COLUMN IF NOT EXISTS subcategory text DEFAULT NULL;

-- 2. TABLA DE SOLICITUDES DE VACACIONES
CREATE TABLE IF NOT EXISTS public.vacation_requests (
    id uuid DEFAULT gen_random_uuid() PRIMARY KEY,
    employee_id uuid REFERENCES public.employees(id) NOT NULL,
    start_date date NOT NULL,
    end_date date NOT NULL,
    total_days integer NOT NULL,
    notes text,
    status text DEFAULT 'PENDIENTE', -- PENDIENTE, APROBADO, RECHAZADO
    approved_by uuid REFERENCES public.employees(id),
    approval_date timestamp with time zone,
    created_at timestamp with time zone DEFAULT NOW(),
    updated_at timestamp with time zone DEFAULT NOW()
);

-- Habilitar RLS
ALTER TABLE public.vacation_requests ENABLE ROW LEVEL SECURITY;

-- Políticas RLS para vacaciones
DROP POLICY IF EXISTS "Users can view their own requests" ON public.vacation_requests;
CREATE POLICY "Users can view their own requests"
ON public.vacation_requests FOR SELECT
TO authenticated
USING (employee_id = (SELECT id FROM employees WHERE email = auth.email()));

DROP POLICY IF EXISTS "Users can create requests" ON public.vacation_requests;
CREATE POLICY "Users can create requests"
ON public.vacation_requests FOR INSERT
TO authenticated
WITH CHECK (employee_id = (SELECT id FROM employees WHERE email = auth.email()));

DROP POLICY IF EXISTS "Supervisors can view requests" ON public.vacation_requests;
CREATE POLICY "Supervisors can view requests"
ON public.vacation_requests FOR SELECT
TO authenticated
USING (
    EXISTS (
        SELECT 1 FROM employees supervisor
        WHERE supervisor.email = auth.email()
        AND (
            supervisor.role IN ('ADMIN', 'ANALISTA_RRHH', 'JEFE_RRHH', 'JEFE_VENTAS', 'SUPERVISOR_VENTAS')
        )
    )
);

DROP POLICY IF EXISTS "Supervisors can update requests" ON public.vacation_requests;
CREATE POLICY "Supervisors can update requests"
ON public.vacation_requests FOR UPDATE
TO authenticated
USING (
    EXISTS (
        SELECT 1 FROM employees supervisor
        WHERE supervisor.email = auth.email()
        AND (
            supervisor.role IN ('ADMIN', 'ANALISTA_RRHH', 'JEFE_RRHH', 'JEFE_VENTAS', 'SUPERVISOR_VENTAS')
        )
    )
);

-- 3. ACTUALIZACIÓN DE MOTIVOS (ABSENCE_REASONS)
-- Actualizamos la lista según los nuevos requerimientos
TRUNCATE TABLE public.absence_reasons;

INSERT INTO public.absence_reasons (name, requires_evidence, is_active)
VALUES 
    ('DESCANSO MÉDICO', true, true),   -- Requiere subcategoría
    ('LICENCIA CON GOCE', true, true), -- Requiere evidencia
    ('FALTA JUSTIFICADA', false, true),-- No requiere evidencia, solo texto
    ('AUSENCIA SIN JUSTIFICAR', false, false); -- Uso interno automático

-- 4. FUNCIÓN PARA PROCESO AUTOMÁTICO (CRON JOB)
-- Esta función busca empleados que NO marcaron hoy y les asigna falta injustificada
CREATE OR REPLACE FUNCTION public.process_daily_absences()
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_count integer := 0;
    v_today date := CURRENT_DATE;
    v_employee RECORD;
BEGIN
    -- Iterar sobre todos los empleados activos que NO tienen registro hoy
    FOR v_employee IN 
        SELECT e.id, e.full_name 
        FROM employees e
        WHERE e.is_active = true
        AND NOT EXISTS (
            SELECT 1 FROM attendance a 
            WHERE a.employee_id = e.id 
            AND a.work_date = v_today
        )
    LOOP
        -- Insertar Ausencia Injustificada
        INSERT INTO attendance (
            employee_id,
            work_date,
            record_type,
            notes,
            status,
            validated,
            created_at
        ) VALUES (
            v_employee.id,
            v_today,
            'AUSENCIA SIN JUSTIFICAR',
            'Generado automáticamente por sistema (Cierre 6:00 PM)',
            'PENDIENTE', -- O 'VALIDADO' si se desea que sea firme
            true, -- Se asume validado por sistema
            NOW()
        );
        
        v_count := v_count + 1;
    END LOOP;

    RETURN json_build_object(
        'success', true, 
        'processed_count', v_count, 
        'message', 'Se generaron ' || v_count || ' faltas injustificadas.'
    );
END;
$$;

-- 5. ACTUALIZACIÓN RPC REGISTRO MANUAL (V3)
-- Soporte para subcategorías
CREATE OR REPLACE FUNCTION public.register_manual_attendance(
  p_employee_id uuid,
  p_supervisor_id uuid,
  p_work_date date,
  p_check_in timestamp with time zone,
  p_check_out timestamp with time zone DEFAULT NULL,
  p_record_type text DEFAULT 'ASISTENCIA',
  p_subcategory text DEFAULT NULL, -- NUEVO PARÁMETRO
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
  
  -- Verificar Duplicados
  SELECT * INTO v_existing FROM attendance WHERE employee_id = p_employee_id AND work_date = p_work_date;
  IF v_existing IS NOT NULL THEN
    RETURN json_build_object('success', false, 'message', 'Ya existe un registro para esta fecha: ' || v_existing.record_type);
  END IF;

  -- Lógica de Tipos
  IF p_record_type = 'IN' THEN
     v_final_type := 'ASISTENCIA';
     v_status := 'ON_TIME';
  ELSE
     v_final_type := p_record_type;
     v_status := 'PENDIENTE';
  END IF;

  -- Insertar
  INSERT INTO attendance (
    employee_id, work_date, check_in, check_out, 
    record_type, 
    subcategory, -- Guardar subcategoría
    notes, evidence_url, registered_by, 
    validated, validated_by, validation_date, 
    status, is_late, location_in
  ) VALUES (
    p_employee_id, p_work_date, p_check_in, p_check_out,
    v_final_type,
    p_subcategory, -- Nuevo campo
    COALESCE(p_notes, 'Registro manual por supervisor'),
    p_evidence_url,
    p_supervisor_id,
    true, p_supervisor_id, NOW(),
    v_status,
    p_is_late,
    p_location
  ) RETURNING id INTO v_new_attendance_id;
  
  RETURN json_build_object('success', true, 'message', 'Registro creado correctamente');
END;
$$;
