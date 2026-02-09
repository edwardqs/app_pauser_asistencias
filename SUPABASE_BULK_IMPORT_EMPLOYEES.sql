-- Función RPC para carga masiva de empleados desde Excel
-- Recibe un array de objetos JSON: 
-- [{ 
--    "full_name": "JUAN PEREZ", 
--    "dni": "12345678", 
--    "document_type": "DNI",
--    "sede": "LIMA",
--    "business_unit": "BEBIDAS", -- Opcional, inyectado por frontend
--    "position": "CHOFER",
--    ...
-- }, ...]

CREATE OR REPLACE FUNCTION public.bulk_import_employees(
    p_data jsonb
)
RETURNS TABLE (
    success_count integer,
    errors text[]
)
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_item jsonb;
    v_dni text;
    v_document_type text;
    v_full_name text;
    v_sede text;
    v_position text;
    v_entry_date date;
    v_email text;
    v_phone text;
    v_birth_date date;
    v_address text;
    v_business_unit_input text;

    -- Variables para IDs y relaciones
    v_location_id bigint;
    v_job_position_id bigint;
    v_department_id bigint;
    v_department_name text;
    v_final_business_unit text;
    
    v_success_count integer := 0;
    v_errors text[] := ARRAY[]::text[];
BEGIN
    -- Iterar sobre cada registro del JSON
    FOR v_item IN SELECT * FROM jsonb_array_elements(p_data) 
    LOOP 
        BEGIN 
            -- 1. Extraer y limpiar valores básicos
            v_dni := TRIM(v_item->>'dni');
            v_document_type := COALESCE(NULLIF(TRIM(v_item->>'document_type'), ''), 'DNI'); -- Default DNI
            v_full_name := UPPER(TRIM(v_item->>'full_name'));
            v_sede := UPPER(TRIM(v_item->>'sede'));
            v_position := UPPER(TRIM(v_item->>'position'));
            v_entry_date := (v_item->>'entry_date')::date;
            v_email := LOWER(TRIM(v_item->>'email'));
            v_phone := TRIM(v_item->>'phone');
            v_birth_date := (v_item->>'birth_date')::date;
            v_address := UPPER(TRIM(v_item->>'address'));
            v_business_unit_input := UPPER(TRIM(v_item->>'business_unit'));

            -- 2. Validaciones básicas
            IF v_dni IS NULL OR v_dni = '' THEN 
                v_errors := array_append(v_errors, 'Fila ignorada: DNI vacío'); 
                CONTINUE; 
            END IF;

            IF length(v_dni) < 5 THEN
                v_errors := array_append(v_errors, format('Fila ignorada: DNI "%s" inválido (muy corto)', v_dni));
                CONTINUE;
            END IF;

            IF v_full_name IS NULL OR v_full_name = '' THEN 
                v_errors := array_append(v_errors, format('DNI %s: Nombre vacío', v_dni)); 
                CONTINUE; 
            END IF;

            -- 3. Lógica de Autocompletado de Relaciones (Lookups)
            v_location_id := NULL;
            v_job_position_id := NULL;
            v_department_id := NULL;
            v_department_name := NULL;

            -- 3.1 Buscar Location ID por nombre de Sede
            IF v_sede IS NOT NULL AND v_sede != '' THEN
                SELECT id INTO v_location_id FROM public.locations 
                WHERE UPPER(name) = v_sede LIMIT 1;
            END IF;

            -- 3.2 Buscar Job Position ID por nombre de Cargo
            IF v_position IS NOT NULL AND v_position != '' THEN
                SELECT id INTO v_job_position_id FROM public.job_positions 
                WHERE UPPER(name) = v_position LIMIT 1;

                -- LOGICA DE RECUPERACIÓN INTELIGENTE (SMART MATCHING)
                IF v_job_position_id IS NULL THEN
                    -- Caso CHOFER: "CHOFER A2B", "CHOFER A3C" -> "CHOFER"
                    IF v_position LIKE 'CHOFER%' THEN
                        SELECT id INTO v_job_position_id FROM public.job_positions 
                        WHERE UPPER(name) = 'CHOFER' LIMIT 1;
                    END IF;
                END IF;
            END IF;

            -- 3.3 Buscar Department ID desde org_structure
            IF v_location_id IS NOT NULL AND v_job_position_id IS NOT NULL THEN
                SELECT os.department_id, d.name 
                INTO v_department_id, v_department_name
                FROM public.org_structure os
                JOIN public.departments d ON d.id = os.department_id
                WHERE os.location_id = v_location_id 
                AND os.job_position_id = v_job_position_id
                LIMIT 1;
            END IF;

            -- 4. Determinar Business Unit Final
            -- Prioridad 1: Input del Excel/Frontend (si estamos en vista filtrada)
            -- Prioridad 2: Nombre del departamento deducido
            IF v_business_unit_input IS NOT NULL AND v_business_unit_input != '' THEN
                v_final_business_unit := v_business_unit_input;
            ELSE
                v_final_business_unit := v_department_name;
            END IF;

            -- Upsert (Insertar o Actualizar si existe DNI)
            INSERT INTO public.employees (
                dni, 
                document_type,
                full_name, 
                sede, 
                position, 
                entry_date, 
                email, 
                phone, 
                birth_date, 
                address,
                is_active,
                created_at,
                updated_at,
                location_id,
                job_position_id,
                department_id,
                business_unit
            ) VALUES (
                v_dni,
                v_document_type,
                v_full_name,
                v_sede,
                v_position,
                v_entry_date,
                v_email,
                v_phone,
                v_birth_date,
                v_address,
                true, -- Activo por defecto
                NOW(),
                NOW(),
                v_location_id,
                v_job_position_id,
                v_department_id,
                v_final_business_unit
            )
            ON CONFLICT (dni) DO UPDATE SET
                document_type = EXCLUDED.document_type,
                full_name = EXCLUDED.full_name,
                sede = EXCLUDED.sede,
                position = EXCLUDED.position,
                entry_date = EXCLUDED.entry_date,
                email = COALESCE(EXCLUDED.email, public.employees.email), 
                phone = EXCLUDED.phone,
                birth_date = EXCLUDED.birth_date,
                address = EXCLUDED.address,
                updated_at = NOW(),
                -- Actualizar relaciones si se encontraron nuevos valores
                location_id = EXCLUDED.location_id,
                job_position_id = EXCLUDED.job_position_id,
                department_id = EXCLUDED.department_id,
                business_unit = EXCLUDED.business_unit;

            v_success_count := v_success_count + 1;

        EXCEPTION WHEN OTHERS THEN 
            v_errors := array_append(v_errors, format('Error DNI %s: %s', v_dni, SQLERRM)); 
        END; 
    END LOOP; 

    RETURN QUERY SELECT v_success_count, v_errors;
END;
$$;
