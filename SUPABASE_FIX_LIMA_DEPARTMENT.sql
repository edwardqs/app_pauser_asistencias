-- =================================================================================
-- CORRECCIÓN DE UNIDAD DE NEGOCIO PARA SEDE LIMA (VERSIÓN CORREGIDA - BIGINT)
-- Descripción: Cambia la asociación de "SNACKS" a "GENERAL" para la sede "LIMA".
-- =================================================================================

DO $$
DECLARE
    -- Usamos BIGINT porque las tablas locations y departments usan IDs numéricos
    v_lima_id bigint;
    v_general_id bigint;
    v_snacks_id bigint;
    v_count integer;
BEGIN
    -- 1. Obtener ID de la Sede LIMA
    SELECT id INTO v_lima_id FROM public.locations WHERE name = 'LIMA';
    
    IF v_lima_id IS NULL THEN
        INSERT INTO public.locations (name) VALUES ('LIMA') RETURNING id INTO v_lima_id;
        RAISE NOTICE 'Sede LIMA creada con ID: %', v_lima_id;
    ELSE
        RAISE NOTICE 'Sede LIMA encontrada con ID: %', v_lima_id;
    END IF;

    -- 2. Obtener ID del Departamento GENERAL
    SELECT id INTO v_general_id FROM public.departments WHERE name = 'GENERAL';
    
    IF v_general_id IS NULL THEN
        INSERT INTO public.departments (name) VALUES ('GENERAL') RETURNING id INTO v_general_id;
        RAISE NOTICE 'Departamento GENERAL creado con ID: %', v_general_id;
    ELSE
        RAISE NOTICE 'Departamento GENERAL encontrado con ID: %', v_general_id;
    END IF;

    -- 3. Obtener ID del Departamento SNACKS (El incorrecto)
    SELECT id INTO v_snacks_id FROM public.departments WHERE name = 'SNACKS';
    
    IF v_snacks_id IS NOT NULL THEN
        RAISE NOTICE 'Departamento SNACKS encontrado con ID: %', v_snacks_id;
        
        -- 4. Actualizar org_structure
        SELECT count(*) INTO v_count 
        FROM public.org_structure 
        WHERE location_id = v_lima_id AND department_id = v_snacks_id;
        
        RAISE NOTICE 'Registros a migrar: %', v_count;
        
        IF v_count > 0 THEN
            BEGIN
                UPDATE public.org_structure
                SET department_id = v_general_id
                WHERE location_id = v_lima_id AND department_id = v_snacks_id;
                RAISE NOTICE 'Migración completada exitosamente.';
            EXCEPTION WHEN unique_violation THEN
                RAISE NOTICE 'Conflicto detectado, eliminando duplicados...';
                DELETE FROM public.org_structure
                WHERE location_id = v_lima_id AND department_id = v_snacks_id;
            END;
        END IF;
    ELSE
        RAISE NOTICE 'Departamento SNACKS no encontrado.';
    END IF;

    -- 5. Asegurar que exista el vínculo LIMA -> GENERAL
    IF NOT EXISTS (SELECT 1 FROM public.org_structure WHERE location_id = v_lima_id AND department_id = v_general_id) THEN
        -- Insertamos un registro "dummy" o aseguramos el vínculo si la tabla lo permite
        -- (Dependiendo de si org_structure requiere job_position_id o no)
        -- Si job_position_id es nullable:
        -- INSERT INTO public.org_structure (location_id, department_id) VALUES (v_lima_id, v_general_id);
        
        -- Si no sabemos la estructura exacta de org_structure, mejor solo imprimimos
        RAISE NOTICE 'Verificar manualmente que existan cargos en LIMA - GENERAL.';
    END IF;

END $$;
