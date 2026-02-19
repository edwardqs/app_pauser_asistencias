-- =============================================================================
-- FUNCIÓN RPC: IMPORTACIÓN MASIVA DE ASISTENCIAS CON CÁLCULO DE TARDANZA Y AUSENCIA
-- =============================================================================
-- Esta función procesa un array de registros de asistencia desde Excel.
-- Calcula automáticamente si es 'TARDANZA' o 'FALTA_INJUSTIFICADA' basándose en la hora.
-- Maneja la conversión de UTC (enviado por frontend) a Hora Perú.

DROP FUNCTION IF EXISTS public.bulk_import_attendance(jsonb);

CREATE OR REPLACE FUNCTION public.bulk_import_attendance(
    p_records jsonb
)
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_item jsonb;
    v_employee_id uuid;
    v_work_date date;
    v_check_in_str text;
    v_check_in_utc timestamptz;
    v_check_in_peru timestamp;
    v_time_peru time;
    v_is_late boolean;
    v_status text;
    v_record_type text; -- Nuevo campo para manejar el tipo de registro
    v_absence_reason text; -- Nuevo campo para el motivo
    v_imported_count int := 0;
    v_error_count int := 0;
    v_errors text[] := ARRAY[]::text[];
    
    -- Configuración de Tolerancia
    c_late_limit time := '07:00:00'; 
    c_absence_limit time := '18:00:00'; -- Hora límite para considerar asistencia (6:00 PM)
BEGIN
    FOR v_item IN SELECT * FROM jsonb_array_elements(p_records)
    LOOP
        BEGIN
            -- 1. Validar y Buscar Empleado por DNI
            IF (v_item->>'dni') IS NULL OR (v_item->>'dni') = '' THEN
                RAISE EXCEPTION 'DNI vacío en registro';
            END IF;

            SELECT id INTO v_employee_id 
            FROM employees 
            WHERE dni = TRIM(v_item->>'dni') 
            LIMIT 1;
            
            IF v_employee_id IS NULL THEN
                RAISE EXCEPTION 'DNI no encontrado: %', (v_item->>'dni');
            END IF;

            -- 2. Procesar Fechas y Horas
            v_work_date := (v_item->>'work_date')::date;
            v_check_in_str := v_item->>'check_in'; -- Viene como "HH:MM:SS" en UTC desde el frontend
            
            -- Valores por defecto
            v_record_type := COALESCE(v_item->>'record_type', 'ASISTENCIA');
            v_absence_reason := NULL;

            IF v_check_in_str IS NOT NULL THEN
                -- Construir Timestamp UTC: Fecha + Hora UTC
                v_check_in_utc := (v_work_date || ' ' || v_check_in_str || '+00')::timestamptz;
                
                -- Convertir a Hora Perú para evaluar regla de negocio
                v_check_in_peru := v_check_in_utc AT TIME ZONE 'America/Lima';
                v_time_peru := v_check_in_peru::time;

                -- Evaluar Tardanza y Ausencia
                IF v_time_peru > c_absence_limit THEN
                    -- CASO: LLEGADA DESPUÉS DE 18:00 -> FALTA INJUSTIFICADA
                    v_is_late := false;
                    v_status := 'FALTA_INJUSTIFICADA';
                    v_record_type := 'AUSENCIA';
                    v_absence_reason := 'Registro fuera de horario permitido (> 18:00)';
                ELSIF v_time_peru > c_late_limit THEN
                    -- CASO: TARDANZA (07:01 - 18:00)
                    v_is_late := true;
                    v_status := 'tardanza';
                ELSE
                    -- CASO: PUNTUAL (Hasta 07:00)
                    v_is_late := false;
                    v_status := 'asistio';
                END IF;
            ELSE
                -- Caso sin hora de entrada
                v_check_in_utc := NULL;
                v_is_late := false;
                v_status := 'pendiente';
            END IF;

            -- 3. Insertar o Actualizar (Upsert)
            INSERT INTO public.attendance (
                employee_id,
                work_date,
                check_in,
                record_type,
                is_late,
                status,
                validated,
                notes,
                absence_reason,
                created_at
            ) VALUES (
                v_employee_id,
                v_work_date,
                v_check_in_utc,
                v_record_type,
                v_is_late,
                v_status,
                true, -- Importación administrativa se asume validada
                'Importación Masiva Excel',
                v_absence_reason,
                NOW()
            )
            ON CONFLICT (employee_id, work_date) 
            DO UPDATE SET
                check_in = EXCLUDED.check_in,
                record_type = EXCLUDED.record_type, -- Actualizar tipo si cambia
                is_late = EXCLUDED.is_late,
                status = EXCLUDED.status,
                absence_reason = EXCLUDED.absence_reason,
                notes = EXCLUDED.notes || ' (Actualizado por Importación)';

            v_imported_count := v_imported_count + 1;

        EXCEPTION WHEN OTHERS THEN
            v_error_count := v_error_count + 1;
            v_errors := array_append(v_errors, 'DNI ' || COALESCE(v_item->>'dni', '?') || ': ' || SQLERRM);
        END;
    END LOOP;

    RETURN json_build_object(
        'imported_count', v_imported_count,
        'error_count', v_error_count,
        'errors', v_errors
    );
END;
$$;
