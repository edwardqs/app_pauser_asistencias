-- =============================================================================
-- FIX: get_daily_attendance_report para app móvil
-- PROBLEMA: auth.email() siempre es NULL en la app móvil porque mobile_login
--           no devuelve email, así auth.signInWithPassword nunca se llama y
--           el contexto de auth queda vacío → v_is_admin=FALSE → lista vacía.
-- SOLUCIÓN: Agregar p_employee_id UUID DEFAULT NULL como fallback. Cuando
--           auth.email() es NULL pero p_employee_id está presente, se busca
--           el contexto del usuario por su employee_id.
-- =============================================================================
-- INSTRUCCIONES: Copiar y pegar COMPLETO en Supabase → SQL Editor
-- =============================================================================

-- Eliminar TODAS las versiones anteriores del RPC para evitar conflicto de sobrecarga.
-- Postgres crea versiones separadas cuando cambia el número de parámetros,
-- y PostgREST puede llamar a la versión vieja ignorando p_employee_id.
DROP FUNCTION IF EXISTS public.get_daily_attendance_report(date, text, text, text, text, int, int);
DROP FUNCTION IF EXISTS public.get_daily_attendance_report(date, text, int, int, text);
DROP FUNCTION IF EXISTS public.get_daily_attendance_report(date, text, int, int);
DROP FUNCTION IF EXISTS public.get_daily_attendance_report(date, text, text, text, text, int, int, uuid);
DROP FUNCTION IF EXISTS public.get_daily_attendance_report(date, text, int, int, text, text, text);
-- Eliminar cualquier otra versión restante (búsqueda exhaustiva por nombre)
DO $drop$
DECLARE
    r RECORD;
BEGIN
    FOR r IN
        SELECT oid::regprocedure AS sig
        FROM pg_proc
        WHERE proname = 'get_daily_attendance_report'
          AND pronamespace = 'public'::regnamespace
    LOOP
        EXECUTE 'DROP FUNCTION IF EXISTS ' || r.sig;
    END LOOP;
END $drop$;

CREATE OR REPLACE FUNCTION public.get_daily_attendance_report(
    p_date date,
    p_sede text DEFAULT NULL,
    p_business_unit text DEFAULT NULL,
    p_search text DEFAULT NULL,
    p_status text DEFAULT NULL,
    p_page int DEFAULT 1,
    p_limit int DEFAULT 20,
    p_employee_id uuid DEFAULT NULL  -- NUEVO: fallback para app móvil
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
STABLE
AS $$
DECLARE
    v_offset int;
    v_total int;
    v_result jsonb;

    -- Contexto de seguridad
    v_user_role text;
    v_user_position text;
    v_user_sede text;
    v_user_area_id bigint;
    v_user_business_unit text;
    v_is_admin boolean;
BEGIN
    v_offset := (p_page - 1) * p_limit;

    -- 0. OBTENER CONTEXTO DEL USUARIO
    --    Prioridad: auth.email() (web/sesión activa) → p_employee_id (app móvil)
    IF auth.email() IS NOT NULL THEN
        SELECT
            e.role,
            e.position,
            e.sede,
            jp.area_id,
            e.business_unit
        INTO
            v_user_role,
            v_user_position,
            v_user_sede,
            v_user_area_id,
            v_user_business_unit
        FROM public.employees e
        LEFT JOIN public.job_positions jp ON (
            e.job_position_id = jp.id
            OR (e.job_position_id IS NULL AND e.position = jp.name)
        )
        WHERE e.email = auth.email();
    ELSIF p_employee_id IS NOT NULL THEN
        SELECT
            e.role,
            e.position,
            e.sede,
            jp.area_id,
            e.business_unit
        INTO
            v_user_role,
            v_user_position,
            v_user_sede,
            v_user_area_id,
            v_user_business_unit
        FROM public.employees e
        LEFT JOIN public.job_positions jp ON (
            e.job_position_id = jp.id
            OR (e.job_position_id IS NULL AND e.position = jp.name)
        )
        WHERE e.id = p_employee_id;
    END IF;

    -- Normalización
    v_user_role          := UPPER(TRIM(COALESCE(v_user_role, '')));
    v_user_position      := UPPER(TRIM(COALESCE(v_user_position, '')));
    v_user_sede          := UPPER(TRIM(COALESCE(v_user_sede, '')));
    v_user_business_unit := UPPER(TRIM(COALESCE(v_user_business_unit, '')));

    -- 1. DETERMINAR SI ES ADMIN
    v_is_admin := FALSE;
    IF auth.email() = 'admin@pauser.com' THEN
        v_is_admin := TRUE;
    ELSIF v_user_role IN ('ADMIN', 'SUPER ADMIN', 'JEFE_RRHH', 'GERENTE GENERAL', 'SISTEMAS') THEN
        v_is_admin := TRUE;
    -- JEFE DE GENTE Y GESTIÓN → siempre ve todo
    ELSIF v_user_position ILIKE '%JEFE DE GENTE%' THEN
        v_is_admin := TRUE;
    -- ANALISTA DE GENTE Y GESTIÓN → solo ve todo si es de ADM. CENTRAL + ADMINISTRACIÓN
    -- Los demás analistas ven únicamente su sede y unidad de negocio (CASO 2)
    ELSIF v_user_position ILIKE '%ANALISTA DE GENTE%' THEN
        -- Usamos ILIKE para tolerar variaciones de tilde, espacio o capitalización
        IF v_user_sede ILIKE '%ADM%CENTRAL%' AND v_user_business_unit ILIKE '%ADMINISTRACI%' THEN
            v_is_admin := TRUE;
        END IF;
    ELSIF (v_user_position ILIKE '%PART TIME%' AND v_user_sede = 'ADM. CENTRAL' AND v_user_business_unit LIKE 'ADMINISTRACI%') THEN
        v_is_admin := TRUE;
    END IF;

    -- 2. QUERY CON FILTROS DE SEGURIDAD
    WITH base_data AS (
        SELECT
            e.id as employee_id,
            e.full_name,
            e.dni,
            COALESCE(jp.name, e.position) as position,
            e.sede,
            e.business_unit,
            e.profile_picture_url,
            a.id as attendance_id,
            a.check_in,
            a.check_out,
            a.is_late,
            a.record_type,
            a.validated,
            a.location_in,
            a.absence_reason,
            CASE
                WHEN a.id IS NOT NULL THEN
                    CASE
                        WHEN a.record_type = 'ASISTENCIA' AND a.is_late THEN 'late'
                        WHEN a.record_type = 'ASISTENCIA' AND NOT a.is_late THEN 'on_time'
                        ELSE 'present'
                    END
                ELSE 'absent'
            END as computed_status
        FROM employees e
        LEFT JOIN public.job_positions jp ON (
            e.job_position_id = jp.id
            OR (e.job_position_id IS NULL AND e.position = jp.name)
        )
        LEFT JOIN attendance a ON e.id = a.employee_id AND a.work_date = p_date
        WHERE
            e.is_active = true

            -- Filtros de UI
            AND (p_sede IS NULL OR e.sede = p_sede)
            AND (p_business_unit IS NULL OR e.business_unit = p_business_unit)
            AND (
                p_search IS NULL OR
                e.full_name ILIKE '%' || p_search || '%' OR
                e.dni ILIKE '%' || p_search || '%'
            )

            -- LÓGICA DE SEGURIDAD
            AND (
                -- CASO 1: ADMIN → Ve todo el personal
                v_is_admin
                OR
                -- CASO 2: NO ADMIN → filtrado según cargo
                (NOT v_is_admin AND (
                    CASE
                        -- ANALISTA DE GENTE Y GESTIÓN (no-admin): ve toda su sede + unidad de negocio
                        -- No filtra por área — gestiona a todo el personal de su sede/unidad
                        WHEN v_user_position ILIKE '%ANALISTA DE GENTE%' THEN
                            e.sede = v_user_sede AND e.business_unit = v_user_business_unit

                        -- JEFE / GERENTE DE ÁREA: ve TODA su área en TODAS las sedes
                        -- Sin restricción de sede — un JEFE gestiona su área a nivel nacional
                        WHEN (v_user_position ILIKE '%JEFE%' OR v_user_position ILIKE '%GERENTE%') THEN
                            CASE
                                WHEN v_user_area_id IS NOT NULL THEN
                                    jp.area_id = v_user_area_id
                                WHEN v_user_business_unit != '' THEN
                                    e.business_unit = v_user_business_unit
                                ELSE FALSE
                            END

                        -- SUPERVISOR / COORDINADOR: ve su área en su sede
                        -- Si tiene area_id asignada usa eso; si no, cae a sede + unidad
                        WHEN (v_user_position ILIKE '%SUPERVISOR%' OR v_user_position ILIKE '%COORDINADOR%') THEN
                            CASE
                                WHEN v_user_area_id IS NOT NULL THEN
                                    jp.area_id = v_user_area_id AND e.sede = v_user_sede
                                WHEN v_user_business_unit != '' THEN
                                    e.business_unit = v_user_business_unit AND e.sede = v_user_sede
                                ELSE FALSE
                            END

                        -- Otros ANALISTAS (no de Gente): ve su área en su sede
                        WHEN v_user_position ILIKE '%ANALISTA%' THEN
                            CASE
                                WHEN v_user_area_id IS NOT NULL THEN
                                    jp.area_id = v_user_area_id AND e.sede = v_user_sede
                                WHEN v_user_business_unit != '' THEN
                                    e.business_unit = v_user_business_unit AND e.sede = v_user_sede
                                ELSE FALSE
                            END

                        ELSE FALSE
                    END
                ))
            )
    ),
    filtered_data AS (
        SELECT * FROM base_data
        WHERE
            p_status IS NULL
            OR (p_status = 'all')
            OR (p_status = 'present' AND attendance_id IS NOT NULL)
            OR (p_status = 'absent' AND attendance_id IS NULL)
            OR (p_status = 'late' AND is_late = true)
            OR (p_status = 'on_time' AND is_late = false AND attendance_id IS NOT NULL)
    )
    SELECT
        jsonb_build_object(
            'data', COALESCE(jsonb_agg(sub), '[]'::jsonb),
            'total', (SELECT COUNT(*) FROM filtered_data)
        ) INTO v_result
    FROM (
        SELECT * FROM filtered_data
        ORDER BY full_name ASC
        LIMIT p_limit OFFSET v_offset
    ) sub;

    RETURN v_result;
END;
$$;
