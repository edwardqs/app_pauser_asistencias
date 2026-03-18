-- =============================================================================
-- FIX: Error "al cargar datos" para usuarios con cargo JEFE DE...
--
-- CAUSA: El SELECT INTO para obtener el contexto del usuario hacía un LEFT JOIN
--        con job_positions usando OR (position = jp.name), lo que podía retornar
--        múltiples filas si el mismo cargo aparece en varias áreas → PostgreSQL
--        lanzaba "query returned more than one row" → Flutter mostraba error.
--
-- SOLUCIÓN:
--   1. Context lookup usa LIMIT 1 para evitar TOO_MANY_ROWS.
--   2. Para JEFE sin job_position_id: fallback a sede + business_unit (misma sede).
--   3. Para JEFE sin business_unit: fallback a ver solo su sede.
-- =============================================================================
-- Copiar y pegar COMPLETO en Supabase → SQL Editor y ejecutar.
-- =============================================================================

-- Eliminar TODAS las versiones anteriores para evitar conflicto de sobrecarga
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
        EXECUTE 'DROP FUNCTION IF EXISTS ' || r.sig || ' CASCADE';
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
    p_employee_id uuid DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
STABLE
AS $$
DECLARE
    v_offset int;
    v_result jsonb;

    v_user_role          text;
    v_user_position      text;
    v_user_sede          text;
    v_user_area_id       bigint;
    v_user_business_unit text;
    v_is_admin           boolean;
BEGIN
    v_offset := (p_page - 1) * p_limit;

    -- -------------------------------------------------------------------------
    -- 0. OBTENER CONTEXTO DEL USUARIO
    --    Usamos LIMIT 1 para evitar TOO_MANY_ROWS cuando el cargo del empleado
    --    aparece en múltiples filas de job_positions (ej. JEFE DE X en varias áreas).
    --    Prioridad: job_position_id (exacto) > match por nombre (primero encontrado).
    -- -------------------------------------------------------------------------
    IF auth.email() IS NOT NULL THEN
        SELECT
            e.role,
            e.position,
            e.sede,
            jp.area_id,
            e.business_unit
        INTO
            v_user_role, v_user_position, v_user_sede, v_user_area_id, v_user_business_unit
        FROM public.employees e
        LEFT JOIN public.job_positions jp ON
            CASE
                WHEN e.job_position_id IS NOT NULL THEN e.job_position_id = jp.id
                ELSE e.position = jp.name
            END
        WHERE e.email = auth.email()
        ORDER BY
            CASE WHEN e.job_position_id IS NOT NULL THEN 0 ELSE 1 END,
            jp.area_id NULLS LAST
        LIMIT 1;

    ELSIF p_employee_id IS NOT NULL THEN
        SELECT
            e.role,
            e.position,
            e.sede,
            jp.area_id,
            e.business_unit
        INTO
            v_user_role, v_user_position, v_user_sede, v_user_area_id, v_user_business_unit
        FROM public.employees e
        LEFT JOIN public.job_positions jp ON
            CASE
                WHEN e.job_position_id IS NOT NULL THEN e.job_position_id = jp.id
                ELSE e.position = jp.name
            END
        WHERE e.id = p_employee_id
        ORDER BY
            CASE WHEN e.job_position_id IS NOT NULL THEN 0 ELSE 1 END,
            jp.area_id NULLS LAST
        LIMIT 1;
    END IF;

    -- Normalización (quita tildes implícitamente al pasar a UPPER, tolera espacios)
    v_user_role          := UPPER(TRIM(COALESCE(v_user_role, '')));
    v_user_position      := UPPER(TRIM(COALESCE(v_user_position, '')));
    v_user_sede          := UPPER(TRIM(COALESCE(v_user_sede, '')));
    v_user_business_unit := UPPER(TRIM(COALESCE(v_user_business_unit, '')));

    -- -------------------------------------------------------------------------
    -- 1. DETERMINAR SI ES ADMIN (ve TODOS los empleados de la empresa)
    --
    -- Jerarquía confirmada con datos reales:
    --   GERENTE GENERAL   → is_admin
    --   JEFE COMERCIAL    → is_admin (cargo nacional, ADM. CENTRAL)
    --   JEFE DE GENTE     → is_admin
    --   ANALISTA DE GENTE (ADM. CENTRAL + ADMINISTRACIÓN) → is_admin
    --
    -- NO son admin (filtrados en CASO 2):
    --   JEFE DE VENTAS       → su sede + business_unit
    --   JEFE DE OPERACIONES  → toda el área OPERACIONES (nacional, desde ADM. CENTRAL)
    --   JEFE DE ADM/FINANZAS → toda el área FINANZAS (nacional, desde ADM. CENTRAL)
    --   COORDINADOR DE X     → misma lógica que JEFE: área + (nacional si ADM. CENTRAL, sede si regional)
    -- -------------------------------------------------------------------------
    v_is_admin := FALSE;
    IF auth.email() = 'admin@pauser.com' THEN
        v_is_admin := TRUE;
    ELSIF v_user_role IN ('ADMIN', 'SUPER ADMIN', 'JEFE_RRHH', 'GERENTE GENERAL', 'SISTEMAS') THEN
        v_is_admin := TRUE;
    ELSIF v_user_role = 'GERENTE' THEN
        v_is_admin := TRUE;
    -- JEFE COMERCIAL: único jefe de área que ve toda la empresa (no solo su área)
    ELSIF v_user_position = 'JEFE COMERCIAL' THEN
        v_is_admin := TRUE;
    -- JEFE DE GENTE Y GESTIÓN: ve toda la empresa
    ELSIF v_user_position ILIKE '%JEFE DE GENTE%' THEN
        v_is_admin := TRUE;
    -- ANALISTA DE GENTE (ADM. CENTRAL + ADMINISTRACIÓN): ve toda la empresa
    ELSIF v_user_position ILIKE '%ANALISTA DE GENTE%' THEN
        IF v_user_sede ILIKE '%ADM%CENTRAL%' AND v_user_business_unit ILIKE '%ADMINISTRACI%' THEN
            v_is_admin := TRUE;
        END IF;
    ELSIF (v_user_position ILIKE '%PART TIME%' AND v_user_sede ILIKE '%ADM%CENTRAL%' AND v_user_business_unit ILIKE 'ADMINISTRACI%') THEN
        v_is_admin := TRUE;
    END IF;

    -- -------------------------------------------------------------------------
    -- 2. QUERY PRINCIPAL CON LÓGICA DE VISIBILIDAD
    -- -------------------------------------------------------------------------
    WITH base_data AS (
        SELECT
            e.id as employee_id,
            e.full_name,
            e.dni,
            COALESCE(jp2.name, e.position) as position,
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
            jp2.area_id as emp_area_id,
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
        LEFT JOIN LATERAL (
            SELECT jp_i.id, jp_i.name, jp_i.area_id
            FROM public.job_positions jp_i
            WHERE (e.job_position_id IS NOT NULL AND jp_i.id = e.job_position_id)
               OR (e.job_position_id IS NULL AND jp_i.name = e.position)
            ORDER BY
                CASE WHEN e.job_position_id IS NOT NULL THEN 0 ELSE 1 END,
                jp_i.area_id NULLS LAST
            LIMIT 1
        ) jp2 ON true
        LEFT JOIN attendance a ON e.id = a.employee_id AND a.work_date = p_date
        WHERE
            e.is_active = true
            AND (p_sede IS NULL OR e.sede = p_sede)
            AND (p_business_unit IS NULL OR e.business_unit = p_business_unit)
            AND (
                p_search IS NULL OR
                e.full_name ILIKE '%' || p_search || '%' OR
                e.dni ILIKE '%' || p_search || '%'
            )
            AND (
                -- ADMIN: ve todo
                v_is_admin
                OR
                -- NO ADMIN: filtrado por cargo
                (NOT v_is_admin AND (
                    CASE
                        -- ── ANALISTA DE GENTE (no-admin) ──────────────────────────────
                        -- Ve toda su sede + unidad (ej. analista GENTE en Chimbote)
                        WHEN v_user_position ILIKE '%ANALISTA DE GENTE%' THEN
                            e.sede = v_user_sede AND e.business_unit = v_user_business_unit

                        -- ── JEFE DE VENTAS ────────────────────────────────────────────
                        -- Caso especial: ve solo su sede + business_unit (no toda el área COMERCIAL)
                        -- Ejemplo: JEFE DE VENTAS CHIMBOTE/BEBIDAS → solo ve BEBIDAS en CHIMBOTE
                        WHEN v_user_position = 'JEFE DE VENTAS' THEN
                            e.sede = v_user_sede
                            AND e.business_unit = v_user_business_unit

                        -- ── JEFE DE X / COORDINADOR DE X (misma jerarquía) ───────────
                        -- Regla unificada: si está en ADM. CENTRAL → ve toda su área (nacional)
                        --                 si está en sede regional  → ve su área solo en su sede
                        -- Ejemplos:
                        --   JEFE DE OPERACIONES (ADM. CENTRAL)    → toda el área OPERACIONES
                        --   COORDINADOR DE OPERACIONES (CHIMBOTE) → OPERACIONES solo en CHIMBOTE
                        --   JEFE DE ADM. Y FINANZAS (ADM. CENTRAL) → toda el área FINANZAS
                        --   COORDINADOR SST (ADM. CENTRAL)         → toda el área GENTE
                        WHEN (
                            v_user_position ILIKE '%JEFE%'
                            OR v_user_position ILIKE '%COORDINADOR%'
                        ) THEN
                            CASE
                                WHEN v_user_area_id IS NOT NULL AND v_user_sede ILIKE '%ADM%CENTRAL%' THEN
                                    jp2.area_id = v_user_area_id              -- Nacional: todas las sedes
                                WHEN v_user_area_id IS NOT NULL THEN
                                    jp2.area_id = v_user_area_id
                                    AND e.sede = v_user_sede                  -- Regional: solo su sede
                                WHEN v_user_business_unit != '' THEN
                                    e.business_unit = v_user_business_unit
                                    AND e.sede = v_user_sede                  -- Fallback: BU + sede
                                WHEN v_user_sede != '' THEN
                                    e.sede = v_user_sede                      -- Fallback final: solo sede
                                ELSE FALSE
                            END

                        -- ── SUPERVISOR ────────────────────────────────────────────────
                        -- Siempre ve su área en su sede (no tiene alcance nacional)
                        WHEN v_user_position ILIKE '%SUPERVISOR%' THEN
                            CASE
                                WHEN v_user_area_id IS NOT NULL THEN
                                    jp2.area_id = v_user_area_id AND e.sede = v_user_sede
                                WHEN v_user_business_unit != '' THEN
                                    e.business_unit = v_user_business_unit AND e.sede = v_user_sede
                                WHEN v_user_sede != '' THEN
                                    e.sede = v_user_sede
                                ELSE FALSE
                            END

                        -- ── OTROS ANALISTAS ───────────────────────────────────────────
                        WHEN v_user_position ILIKE '%ANALISTA%' THEN
                            CASE
                                WHEN v_user_area_id IS NOT NULL THEN
                                    jp2.area_id = v_user_area_id AND e.sede = v_user_sede
                                WHEN v_user_business_unit != '' THEN
                                    e.business_unit = v_user_business_unit AND e.sede = v_user_sede
                                WHEN v_user_sede != '' THEN
                                    e.sede = v_user_sede
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
            OR (p_status = 'present'  AND attendance_id IS NOT NULL)
            OR (p_status = 'absent'   AND attendance_id IS NULL)
            OR (p_status = 'late'     AND is_late = true)
            OR (p_status = 'on_time'  AND is_late = false AND attendance_id IS NOT NULL)
    )
    SELECT
        jsonb_build_object(
            'data',  COALESCE(jsonb_agg(sub), '[]'::jsonb),
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

-- Grant access
GRANT EXECUTE ON FUNCTION public.get_daily_attendance_report TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_daily_attendance_report TO anon;
