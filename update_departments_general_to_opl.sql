-- =================================================================================
-- MIGRACIÓN: GENERAL -> OPL (Excluyendo 'ADMINISTRACION' / 'ADM. CENTRAL')
-- Descripción: Renombra o fusiona 'GENERAL' a 'OPL' para todas las sedes excepto Admin.
-- =================================================================================

DO $$
DECLARE
    v_general_id bigint;
    v_opl_id bigint;
    v_admin_loc_id bigint;
    v_admin_name text;
    v_updated_count integer;
BEGIN
    -- 1. Obtener IDs
    SELECT id INTO v_general_id FROM public.departments WHERE name = 'GENERAL';
    
    -- Si no existe GENERAL, no hay nada que hacer
    IF v_general_id IS NULL THEN
        RAISE NOTICE 'No se encontró el departamento GENERAL. No se requieren cambios.';
        RETURN;
    END IF;

    -- Obtener o Crear OPL
    SELECT id INTO v_opl_id FROM public.departments WHERE name = 'OPL';
    IF v_opl_id IS NULL THEN
        INSERT INTO public.departments (name) VALUES ('OPL') RETURNING id INTO v_opl_id;
        RAISE NOTICE 'Creado departamento OPL con ID: %', v_opl_id;
    END IF;

    -- Obtener ID de Sede 'ADM. CENTRAL' (para excluirla)
    -- Buscamos por nombres comunes de la sede administrativa
    SELECT id, name INTO v_admin_loc_id, v_admin_name FROM public.locations WHERE name IN ('ADM. CENTRAL', 'ADMINISTRACION', 'LIMA - SEDE CENTRAL') LIMIT 1;
    
    RAISE NOTICE 'ID GENERAL: %, ID OPL: %, ID ADMIN LOC: %', v_general_id, v_opl_id, COALESCE(v_admin_loc_id::text, 'No encontrado');

    -- 2. Actualizar org_structure (Mover GENERAL -> OPL, excepto Admin)
    
    -- 2.1 Actualizar registros donde NO sea la sede administrativa
    -- Solo actualizamos si no existe ya conflicto (duplicado OPL en la misma sede+cargo)
    UPDATE public.org_structure os
    SET department_id = v_opl_id
    WHERE department_id = v_general_id
    AND (v_admin_loc_id IS NULL OR location_id != v_admin_loc_id) -- Excluir Admin
    AND NOT EXISTS (
        SELECT 1 FROM public.org_structure os2 
        WHERE os2.department_id = v_opl_id 
        AND os2.location_id = os.location_id
        AND os2.job_position_id = os.job_position_id
    );
    
    GET DIAGNOSTICS v_updated_count = ROW_COUNT;
    RAISE NOTICE 'Actualizados % registros en org_structure de GENERAL a OPL.', v_updated_count;

    -- 2.2 Eliminar registros antiguos de GENERAL que quedaron redundantes (porque ya existía OPL)
    -- Solo para sedes NO Admin
    DELETE FROM public.org_structure
    WHERE department_id = v_general_id
    AND (v_admin_loc_id IS NULL OR location_id != v_admin_loc_id);

    -- 3. Actualizar tabla employees (si usan business_unit como texto o department_id)
    
    -- 3.1 Actualizar business_unit texto
    -- Usamos el nombre real de la sede administrativa si se encontró, o 'ADM. CENTRAL' por defecto
    UPDATE public.employees 
    SET business_unit = 'OPL' 
    WHERE business_unit = 'GENERAL'
    AND (
        (v_admin_name IS NOT NULL AND sede != v_admin_name) OR
        (v_admin_name IS NULL AND sede NOT IN ('ADM. CENTRAL', 'ADMINISTRACION', 'LIMA - SEDE CENTRAL'))
    );
    
    GET DIAGNOSTICS v_updated_count = ROW_COUNT;
    RAISE NOTICE 'Actualizados % empleados de GENERAL a OPL.', v_updated_count;

    -- 3.2 Actualizar department_id en employees si existe la columna
    BEGIN
        UPDATE public.employees 
        SET department_id = v_opl_id 
        WHERE department_id = v_general_id
        AND (v_admin_loc_id IS NULL OR location_id != v_admin_loc_id);
    EXCEPTION WHEN others THEN
        -- Ignorar si la columna no existe o hay error
        NULL;
    END;

    -- 4. Limpieza final (Opcional)
    -- Verificar si 'GENERAL' sigue en uso por alguien (ej. Admin)
    IF NOT EXISTS (SELECT 1 FROM public.org_structure WHERE department_id = v_general_id) THEN
        RAISE NOTICE 'El departamento GENERAL ya no está en uso. Se procederá a eliminarlo.';
        DELETE FROM public.departments WHERE id = v_general_id;
    ELSE
        RAISE NOTICE 'El departamento GENERAL sigue en uso (posiblemente por ADM. CENTRAL). No se elimina.';
    END IF;

END $$;
