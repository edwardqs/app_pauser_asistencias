-- =============================================================================
-- SCRIPT DE GESTIÓN Y ELIMINACIÓN EN CADENA (CASCADA) DE SOLICITUD DE VACACIONES
-- Empleado: DELGADO CRUZ JULIO CESAR
-- =============================================================================
--
-- INSTRUCCIONES:
-- 1. Abre el Editor de SQL de tu consola de Supabase.
-- 2. Ejecuta la PARTE 1 (Previsualización) para verificar qué registros existen actualmente.
-- 3. Una vez confirmado, ejecuta la PARTE 2 para borrar de manera segura y en cadena
--    todo lo relacionado con la solicitud de vacaciones de este empleado.
--
-- =============================================================================


-- =============================================================================
-- PARTE 1: PREVISUALIZACIÓN / VERIFICACIÓN DE DATOS (Seguro - Solo lectura)
-- =============================================================================

-- A. Verificar datos del empleado
SELECT id, dni, full_name, sede, business_unit, employee_type, position, entry_date
FROM public.employees
WHERE UPPER(TRIM(full_name)) = 'DELGADO CRUZ JULIO CESAR'
   OR full_name ILIKE '%DELGADO CRUZ JULIO CESAR%';

-- B. Mostrar todas las solicitudes de vacaciones del empleado
SELECT vr.id AS solicitud_id, vr.start_date, vr.end_date, vr.total_days, vr.status, vr.request_type, vr.created_at
FROM public.vacation_requests vr
JOIN public.employees e ON e.id = vr.employee_id
WHERE UPPER(TRIM(e.full_name)) = 'DELGADO CRUZ JULIO CESAR'
   OR e.full_name ILIKE '%DELGADO CRUZ JULIO CESAR%';

-- C. Mostrar logs de actividad que se generaron por cambios en la solicitud
SELECT al.id AS log_id, al.created_at, al.description, al.type, al.metadata
FROM public.activity_logs al
WHERE al.metadata->>'request_id' IN (
    SELECT vr.id::text
    FROM public.vacation_requests vr
    JOIN public.employees e ON e.id = vr.employee_id
    WHERE UPPER(TRIM(e.full_name)) = 'DELGADO CRUZ JULIO CESAR'
       OR e.full_name ILIKE '%DELGADO CRUZ JULIO CESAR%'
);

-- D. Mostrar notificaciones asociadas
SELECT n.id AS notificacion_id, n.title, n.message, n.is_read, n.created_at, n.metadata
FROM public.notifications n
WHERE n.metadata->>'request_id' IN (
    SELECT vr.id::text
    FROM public.vacation_requests vr
    JOIN public.employees e ON e.id = vr.employee_id
    WHERE UPPER(TRIM(e.full_name)) = 'DELGADO CRUZ JULIO CESAR'
       OR e.full_name ILIKE '%DELGADO CRUZ JULIO CESAR%'
);

-- E. Mostrar marcaciones de asistencia de tipo 'VACACIONES' que se solapen
SELECT a.id AS asistencia_id, a.work_date, a.record_type, a.status, a.notes, a.absence_reason
FROM public.attendance a
JOIN public.employees e ON e.id = a.employee_id
WHERE (UPPER(TRIM(e.full_name)) = 'DELGADO CRUZ JULIO CESAR' OR e.full_name ILIKE '%DELGADO CRUZ JULIO CESAR%')
  AND (a.record_type = 'VACACIONES' OR a.absence_reason = 'VACACIONES');


-- =============================================================================
-- PARTE 2: SCRIPT DE ELIMINACIÓN EN CADENA (CASCADA) - EJECUTAR PARA BORRAR
-- =============================================================================
-- Este bloque DO ejecuta una transacción segura. Si algo falla, hace rollback automático.

DO $$
DECLARE
    v_employee_id        uuid;
    v_employee_name      text := 'DELGADO CRUZ JULIO CESAR';
    v_request            RECORD;
    
    -- Contadores para el reporte final
    v_requests_deleted   int := 0;
    v_logs_deleted       int := 0;
    v_notifs_deleted     int := 0;
    v_att_deleted        int := 0;
    v_temp_count         int;
BEGIN
    -- 1. Buscar al empleado por nombre completo (exacto)
    SELECT id INTO v_employee_id
    FROM public.employees
    WHERE UPPER(TRIM(full_name)) = UPPER(TRIM(v_employee_name));

    -- Si no se encuentra exactamente, intentar búsqueda parcial inteligente
    IF v_employee_id IS NULL THEN
        SELECT id INTO v_employee_id
        FROM public.employees
        WHERE full_name ILIKE '%' || v_employee_name || '%';
    END IF;

    -- Si no existe en la base de datos, lanzar error controlado
    IF v_employee_id IS NULL THEN
        RAISE EXCEPTION 'ERROR: El empleado "%" no fue encontrado en la base de datos. Por favor, verifica el nombre.', v_employee_name;
    END IF;

    RAISE NOTICE '======================================================================';
    RAISE NOTICE 'Iniciando eliminación en cadena para el empleado: % (ID: %)', v_employee_name, v_employee_id;
    RAISE NOTICE '======================================================================';

    -- 2. Recorrer todas las solicitudes de vacaciones asociadas al empleado
    -- NOTA: Si deseas filtrar una solicitud específica por fecha de inicio, puedes agregar a la consulta:
    -- AND start_date = '2026-06-01'::date  (por ejemplo)
    FOR v_request IN 
        SELECT id, start_date, end_date, total_days, status 
        FROM public.vacation_requests 
        WHERE employee_id = v_employee_id
    LOOP
        RAISE NOTICE 'Procesando solicitud ID: % | % al % (% días) | Estado: %', 
            v_request.id, v_request.start_date, v_request.end_date, v_request.total_days, v_request.status;

        -- A. Eliminar logs de actividad asociados
        DELETE FROM public.activity_logs 
        WHERE metadata->>'request_id' = v_request.id::text;
        GET DIAGNOSTICS v_temp_count = ROW_COUNT;
        v_logs_deleted := v_logs_deleted + v_temp_count;

        -- B. Eliminar notificaciones asociadas en la app (tanto por JSON como por texto crudo)
        DELETE FROM public.notifications 
        WHERE employee_id = v_employee_id 
          AND (
               metadata->>'request_id' = v_request.id::text 
               OR metadata::text LIKE '%' || v_request.id::text || '%'
          );
        GET DIAGNOSTICS v_temp_count = ROW_COUNT;
        v_notifs_deleted := v_notifs_deleted + v_temp_count;

        -- C. Eliminar registros de asistencia tipo 'VACACIONES' que se crucen con el rango de fechas de la solicitud
        DELETE FROM public.attendance 
        WHERE employee_id = v_employee_id 
          AND work_date BETWEEN v_request.start_date AND v_request.end_date 
          AND (record_type = 'VACACIONES' OR absence_reason = 'VACACIONES');
        GET DIAGNOSTICS v_temp_count = ROW_COUNT;
        v_att_deleted := v_att_deleted + v_temp_count;

        -- D. Eliminar la solicitud de vacaciones física
        DELETE FROM public.vacation_requests 
        WHERE id = v_request.id;
        GET DIAGNOSTICS v_temp_count = ROW_COUNT;
        v_requests_deleted := v_requests_deleted + v_temp_count;
        
    END LOOP;

    -- 3. Reporte final
    RAISE NOTICE '----------------------------------------------------------------------';
    RAISE NOTICE 'RESUMEN DE ELIMINACIÓN EXITOSA:';
    RAISE NOTICE ' - Solicitudes de vacaciones eliminadas: %', v_requests_deleted;
    RAISE NOTICE ' - Logs de actividad eliminados: %', v_logs_deleted;
    RAISE NOTICE ' - Notificaciones eliminadas: %', v_notifs_deleted;
    RAISE NOTICE ' - Registros de asistencia (VACACIONES) eliminados: %', v_att_deleted;
    RAISE NOTICE '----------------------------------------------------------------------';
    RAISE NOTICE 'La transacción se completó con éxito. Todos los cambios son permanentes.';
    RAISE NOTICE '======================================================================';

EXCEPTION
    WHEN OTHERS THEN
        RAISE NOTICE 'ERROR detectado durante la ejecución. Se realizó ROLLBACK automático.';
        RAISE EXCEPTION 'Detalle del error: %', SQLERRM;
END $$;
