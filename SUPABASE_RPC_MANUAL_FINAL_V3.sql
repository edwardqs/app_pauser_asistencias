-- =============================================================================
-- FUNCIÓN DE REGISTRO MANUAL DE ASISTENCIA (FINAL V3)
-- Soporta:
-- 1. ASISTENCIA (Entrada/Salida) con cálculo de tardanza.
-- 2. MOTIVOS ESPECIALES (Descanso Médico, Vacaciones, etc.)
-- 3. VALIDACIÓN AUTOMÁTICA (porque lo hace un supervisor).
-- =============================================================================

DROP FUNCTION IF EXISTS public.register_manual_attendance(uuid, uuid, date, timestamptz, text, text, text, text, boolean, jsonb);
DROP FUNCTION IF EXISTS public.register_manual_attendance(uuid, uuid, date, timestamptz, text, text, text, text, boolean); -- Versión anterior sin location

CREATE OR REPLACE FUNCTION public.register_manual_attendance(
    p_employee_id uuid,
    p_supervisor_id uuid,
    p_work_date date,
    p_check_in timestamptz,
    p_record_type text,         -- 'ASISTENCIA', 'DESCANSO MÉDICO', 'VACACIONES', etc.
    p_subcategory text DEFAULT NULL, -- 'Enfermedad común', etc.
    p_notes text DEFAULT NULL,
    p_evidence_url text DEFAULT NULL,
    p_is_late boolean DEFAULT false, -- Override manual de tardanza
    p_location jsonb DEFAULT NULL
)
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
AS $function$
DECLARE
    v_timestamp_peru timestamp;
    v_time_peru time;
    v_is_late boolean := false;
    v_status text;
    v_final_type text;
    v_check_in timestamptz := NULL;
    v_check_out timestamptz := NULL;
    v_new_attendance_id uuid;
    v_existing record;
    
    -- Configuración de hora límite (07:00 AM)
    c_late_limit time := '07:00:00';
BEGIN
  -- Convertir el timestamp ingresado a Hora Perú para validar tardanza
  -- NOTA: p_check_in viene en UTC. AT TIME ZONE 'UTC' lo hace timestamp, luego AT TIME ZONE 'America/Lima' lo localiza.
  -- Si ya viene como timestamptz, directo a America/Lima funciona.
  v_timestamp_peru := p_check_in AT TIME ZONE 'America/Lima';
  v_time_peru := v_timestamp_peru::time;

  -- =========================================================
  -- LÓGICA DE TIPO DE REGISTRO
  -- =========================================================
  IF p_record_type = 'ASISTENCIA' OR p_record_type = 'IN' THEN
     v_final_type := 'ASISTENCIA';
     v_check_in := p_check_in;
     
     -- Lógica de Tardanza:
     -- Si el usuario marcó check "Tarde" en la app (p_is_late) O si la hora supera el límite.
     IF p_is_late OR v_time_peru > c_late_limit THEN
        v_is_late := true;
        v_status := 'tardanza';
     ELSE
        v_is_late := false;
        v_status := 'asistio';
     END IF;

  ELSIF p_record_type = 'OUT' THEN
     -- Si es salida, solo actualizamos un registro existente
     -- (Esta lógica usualmente va en otra función, pero por si acaso)
     RETURN json_build_object('success', false, 'message', 'Use la función de salida para marcar salida');

  ELSE
     -- Cualquier otro motivo (Enfermedad, Viajes, Licencias, Ausencias)
     -- En estos casos, check_in suele ser NULL o irrelevante para el cálculo de tardanza
     v_final_type := p_record_type;
     v_status := 'justificado'; -- O 'ausente' dependiendo de la lógica, pero 'justificado' es neutro
     v_is_late := false; -- No aplica tardanza a licencias
     
     -- Para mantener consistencia visual en calendarios, a veces se guarda check_in
     -- pero para reportes estrictos, mejor dejarlo NULL o igual a work_date start.
     -- Aquí lo dejamos NULL para que la Web pinte "Licencia" en vez de "Hora".
     v_check_in := NULL; 
  END IF;

  -- =========================================================
  -- UPSERT (Insertar o Actualizar)
  -- =========================================================
  
  -- Verificar si ya existe registro
  SELECT * INTO v_existing FROM attendance WHERE employee_id = p_employee_id AND work_date = p_work_date;
  
  IF v_existing IS NOT NULL THEN
    -- UPDATE
    UPDATE attendance
    SET 
      check_in = COALESCE(v_check_in, check_in), -- Si es licencia, no chancamos la entrada si existía (o sí?) -> Mejor chancar si es corrección
      -- Si cambiamos de ASISTENCIA a LICENCIA, check_in debería ser NULL? 
      -- Si v_check_in es NULL (porque es licencia), forzamos NULL en la base de datos?
      -- COALESCE mantiene el valor viejo si el nuevo es null.
      -- Para corrección total:
      record_type = v_final_type,
      subcategory = p_subcategory,
      notes = COALESCE(p_notes, notes),
      evidence_url = COALESCE(p_evidence_url, evidence_url),
      registered_by = p_supervisor_id,
      validated = true,
      status = v_status,
      is_late = v_is_late,
      location_in = COALESCE(p_location, location_in)
    WHERE id = v_existing.id
    RETURNING id INTO v_new_attendance_id;
    
    -- Si es un cambio a tipo NO asistencia, forzamos limpiar check_in/out para evitar inconsistencias visuales
    IF v_final_type != 'ASISTENCIA' THEN
        UPDATE attendance SET check_in = NULL, check_out = NULL, is_late = false WHERE id = v_new_attendance_id;
    ELSE
        -- Si es asistencia, aseguramos que se actualice el check_in
        UPDATE attendance SET check_in = v_check_in WHERE id = v_new_attendance_id;
    END IF;

    RETURN json_build_object('success', true, 'message', 'Registro actualizado correctamente');

  ELSE
    -- INSERT
    INSERT INTO attendance (
      employee_id, work_date, check_in, check_out, 
      record_type, subcategory, notes, evidence_url, registered_by, 
      validated, 
      status, is_late, location_in
    ) VALUES (
      p_employee_id, p_work_date, v_check_in, v_check_out,
      v_final_type, p_subcategory,
      COALESCE(p_notes, 'Registro manual por supervisor'),
      p_evidence_url,
      p_supervisor_id,
      true, -- Validado
      v_status,
      v_is_late,
      p_location
    ) RETURNING id INTO v_new_attendance_id;
    
    RETURN json_build_object('success', true, 'message', 'Registro creado correctamente');
  END IF;

EXCEPTION WHEN OTHERS THEN
    RETURN json_build_object('success', false, 'message', 'Error interno: ' || SQLERRM);
END;
$function$;
