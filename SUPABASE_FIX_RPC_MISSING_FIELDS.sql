-- =============================================================================
-- FIX: RPC get_daily_attendance_report faltaban campos notes, evidence_url,
--      validated_by → en modo Roster la web mostraba MOTIVO vacío y no podía
--      mostrar el motivo de rechazo ni links de evidencia.
--
-- CAMPOS AGREGADOS al SELECT de base_data:
--   a.notes          → motivo de rechazo al validar
--   a.evidence_url   → link de evidencia adjunta
--   a.validated_by   → quién validó/rechazó (para lógica de display)
-- =============================================================================
-- Copiar y pegar COMPLETO en Supabase → SQL Editor y ejecutar.
-- =============================================================================

-- Eliminar TODAS las versiones anteriores
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

    v_user_role          := UPPER(TRIM(COALESCE(v_user_role, '')));
    v_user_position      := UPPER(TRIM(COALESCE(v_user_position, '')));
    v_user_sede          := UPPER(TRIM(COALESCE(v_user_sede, '')));
    v_user_business_unit := UPPER(TRIM(COALESCE(v_user_business_unit, '')));

    -- -------------------------------------------------------------------------
    -- 1. DETERMINAR SI ES ADMIN
    -- -------------------------------------------------------------------------
    v_is_admin := FALSE;
    IF auth.email() = 'admin@pauser.com' THEN
        v_is_admin := TRUE;
    ELSIF v_user_role IN ('ADMIN', 'SUPER ADMIN', 'JEFE_RRHH', 'GERENTE GENERAL', 'SISTEMAS') THEN
        v_is_admin := TRUE;
    ELSIF v_user_role = 'GERENTE' THEN
        v_is_admin := TRUE;
    ELSIF v_user_position ILIKE '%JEFE DE GENTE%' THEN
        v_is_admin := TRUE;
    ELSIF v_user_position ILIKE '%ANALISTA DE GENTE%' THEN
        IF v_user_sede ILIKE '%ADM%CENTRAL%' AND v_user_business_unit ILIKE '%ADMINISTRACI%' THEN
            v_is_admin := TRUE;
        END IF;
    ELSIF (v_user_position ILIKE '%PART TIME%' AND v_user_sede ILIKE '%ADM%CENTRAL%' AND v_user_business_unit ILIKE 'ADMINISTRACI%') THEN
        v_is_admin := TRUE;
    END IF;

    -- -------------------------------------------------------------------------
    -- 2. QUERY PRINCIPAL
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
            a.validated_by,       -- ← NUEVO
            a.location_in,
            a.absence_reason,
            a.notes,              -- ← NUEVO
            a.evidence_url,       -- ← NUEVO
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
                v_is_admin
                OR
                (NOT v_is_admin AND (
                    CASE
                        WHEN v_user_position ILIKE '%ANALISTA DE GENTE%' THEN
                            e.sede = v_user_sede AND e.business_unit = v_user_business_unit

                        WHEN v_user_position = 'JEFE DE VENTAS' THEN
                            e.sede = v_user_sede
                            AND e.business_unit = v_user_business_unit

                        WHEN (
                            v_user_position ILIKE '%JEFE%'
                            OR v_user_position ILIKE '%COORDINADOR%'
                        ) THEN
                            CASE
                                WHEN v_user_area_id IS NOT NULL AND v_user_sede ILIKE '%ADM%CENTRAL%' THEN
                                    jp2.area_id = v_user_area_id
                                WHEN v_user_area_id IS NOT NULL THEN
                                    jp2.area_id = v_user_area_id
                                    AND e.sede = v_user_sede
                                WHEN v_user_business_unit != '' THEN
                                    e.business_unit = v_user_business_unit
                                    AND e.sede = v_user_sede
                                WHEN v_user_sede != '' THEN
                                    e.sede = v_user_sede
                                ELSE FALSE
                            END

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
            OR (p_status = 'late'     AND record_type = 'ASISTENCIA' AND is_late = true)
            OR (p_status = 'on_time'  AND record_type = 'ASISTENCIA' AND is_late = false AND attendance_id IS NOT NULL)
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
