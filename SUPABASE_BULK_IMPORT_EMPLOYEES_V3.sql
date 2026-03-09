-- v3: Corrige los nombres de columnas de org_structure
-- org_structure real tiene: sede_id (uuid), business_unit_id (uuid)
-- NO tiene location_id ni job_position_id → se elimina ese join.
-- Los lookups de location_id y job_position_id funcionan correctamente via
-- las tablas locations (bigint) y job_positions (bigint).
-- department_id se busca directamente en la tabla departments por nombre.

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

    v_location_id bigint;
    v_job_position_id bigint;
    v_department_id bigint;
    v_final_business_unit text;

    v_success_count integer := 0;
    v_errors text[] := ARRAY[]::text[];
BEGIN
    FOR v_item IN SELECT * FROM jsonb_array_elements(p_data)
    LOOP
        BEGIN
            -- 1. Extraer y limpiar
            v_dni                := TRIM(v_item->>'dni');
            v_document_type      := COALESCE(NULLIF(TRIM(v_item->>'document_type'), ''), 'DNI');
            v_full_name          := UPPER(TRIM(v_item->>'full_name'));
            v_sede               := UPPER(TRIM(v_item->>'sede'));
            v_position           := UPPER(TRIM(v_item->>'position'));
            v_entry_date         := NULLIF(TRIM(v_item->>'entry_date'), '')::date;
            v_email              := LOWER(NULLIF(TRIM(v_item->>'email'), ''));
            v_phone              := NULLIF(TRIM(v_item->>'phone'), '');
            v_birth_date         := NULLIF(TRIM(v_item->>'birth_date'), '')::date;
            v_address            := UPPER(NULLIF(TRIM(v_item->>'address'), ''));
            v_business_unit_input := UPPER(NULLIF(TRIM(v_item->>'business_unit'), ''));

            -- 2. Validaciones
            IF v_dni IS NULL OR v_dni = '' THEN
                v_errors := array_append(v_errors, 'Fila ignorada: DNI vacío');
                CONTINUE;
            END IF;
            IF length(v_dni) < 5 THEN
                v_errors := array_append(v_errors, format('Fila ignorada: DNI "%s" inválido', v_dni));
                CONTINUE;
            END IF;
            IF v_full_name IS NULL OR v_full_name = '' THEN
                v_errors := array_append(v_errors, format('DNI %s: Nombre vacío', v_dni));
                CONTINUE;
            END IF;

            -- 3. Lookups
            v_location_id    := NULL;
            v_job_position_id := NULL;
            v_department_id  := NULL;

            -- 3.1 location_id desde tabla locations (bigint, por nombre de sede)
            IF v_sede IS NOT NULL AND v_sede != '' THEN
                -- Exacto
                SELECT id INTO v_location_id FROM public.locations
                WHERE UPPER(TRIM(name)) = v_sede LIMIT 1;
                -- ILIKE fallback
                IF v_location_id IS NULL THEN
                    SELECT id INTO v_location_id FROM public.locations
                    WHERE TRIM(name) ILIKE v_sede LIMIT 1;
                END IF;
                -- Parcial fallback
                IF v_location_id IS NULL THEN
                    SELECT id INTO v_location_id FROM public.locations
                    WHERE TRIM(name) ILIKE '%' || v_sede || '%' LIMIT 1;
                END IF;
            END IF;

            -- 3.2 job_position_id desde tabla job_positions (bigint, por nombre de cargo)
            IF v_position IS NOT NULL AND v_position != '' THEN
                -- Exacto
                SELECT id INTO v_job_position_id FROM public.job_positions
                WHERE UPPER(TRIM(name)) = v_position LIMIT 1;
                -- ILIKE fallback
                IF v_job_position_id IS NULL THEN
                    SELECT id INTO v_job_position_id FROM public.job_positions
                    WHERE TRIM(name) ILIKE v_position LIMIT 1;
                END IF;
                -- El cargo del Excel empieza con el nombre de la tabla (ej: "CHOFER A2B" → "CHOFER")
                IF v_job_position_id IS NULL THEN
                    SELECT id INTO v_job_position_id FROM public.job_positions
                    WHERE v_position ILIKE TRIM(name) || '%'
                    ORDER BY length(name) DESC LIMIT 1;
                END IF;
                -- Parcial por primera y segunda palabra
                IF v_job_position_id IS NULL AND array_length(string_to_array(v_position, ' '), 1) >= 2 THEN
                    SELECT id INTO v_job_position_id FROM public.job_positions
                    WHERE TRIM(name) ILIKE '%' || split_part(v_position, ' ', 1) || '%'
                      AND TRIM(name) ILIKE '%' || split_part(v_position, ' ', 2) || '%'
                    LIMIT 1;
                END IF;
            END IF;

            -- 3.3 department_id desde tabla departments por nombre de business_unit
            -- (org_structure usa UUIDs distintos, no es compatible con estos IDs bigint)
            IF v_business_unit_input IS NOT NULL THEN
                SELECT id INTO v_department_id FROM public.departments
                WHERE UPPER(TRIM(name)) = v_business_unit_input LIMIT 1;
                IF v_department_id IS NULL THEN
                    SELECT id INTO v_department_id FROM public.departments
                    WHERE TRIM(name) ILIKE v_business_unit_input LIMIT 1;
                END IF;
            END IF;

            -- 4. Business unit final
            v_final_business_unit := v_business_unit_input;

            -- 5. Upsert
            INSERT INTO public.employees (
                dni, document_type, full_name, sede, position,
                entry_date, email, phone, birth_date, address,
                is_active, created_at, updated_at,
                location_id, job_position_id, department_id, business_unit
            ) VALUES (
                v_dni, v_document_type, v_full_name, v_sede, v_position,
                v_entry_date, v_email, v_phone, v_birth_date, v_address,
                true, NOW(), NOW(),
                v_location_id, v_job_position_id, v_department_id, v_final_business_unit
            )
            ON CONFLICT (dni) DO UPDATE SET
                document_type    = EXCLUDED.document_type,
                full_name        = EXCLUDED.full_name,
                sede             = EXCLUDED.sede,
                position         = EXCLUDED.position,
                entry_date       = EXCLUDED.entry_date,
                email            = COALESCE(EXCLUDED.email, public.employees.email),
                phone            = EXCLUDED.phone,
                birth_date       = EXCLUDED.birth_date,
                address          = EXCLUDED.address,
                updated_at       = NOW(),
                location_id      = COALESCE(EXCLUDED.location_id,     public.employees.location_id),
                job_position_id  = COALESCE(EXCLUDED.job_position_id, public.employees.job_position_id),
                department_id    = COALESCE(EXCLUDED.department_id,   public.employees.department_id),
                business_unit    = COALESCE(EXCLUDED.business_unit,   public.employees.business_unit);

            v_success_count := v_success_count + 1;

        EXCEPTION WHEN OTHERS THEN
            v_errors := array_append(v_errors, format('Error DNI %s: %s', v_dni, SQLERRM));
        END;
    END LOOP;

    RETURN QUERY SELECT v_success_count, v_errors;
END;
$$;
