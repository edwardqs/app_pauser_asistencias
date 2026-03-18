-- =============================================================================
-- DIAGNÓSTICO: Todos los JEFES y COORDINADORES por área, sede y business_unit
-- Ejecutar ANTES de aplicar SUPABASE_FIX_JEFE_TEAM_ACCESS.sql
-- =============================================================================

-- -----------------------------------------------------------------------------
-- QUERY 1: Todos los cargos únicos que son JEFE o COORDINADOR
--          con su área asignada y cuántos empleados tienen ese cargo
-- -----------------------------------------------------------------------------
SELECT
    e.position                          AS cargo,
    e.role                              AS rol_sistema,
    a.name                              AS area,
    COUNT(DISTINCT e.id)                AS cantidad_personas,
    STRING_AGG(DISTINCT e.sede, ', ' ORDER BY e.sede) AS sedes_presentes
FROM public.employees e
LEFT JOIN public.job_positions jp ON
    CASE
        WHEN e.job_position_id IS NOT NULL THEN e.job_position_id = jp.id
        ELSE e.position = jp.name
    END
LEFT JOIN public.areas a ON jp.area_id = a.id
WHERE
    e.is_active = true
    AND (
        e.position ILIKE '%JEFE%'
        OR e.position ILIKE '%COORDINADOR%'
        OR e.position ILIKE '%GERENTE%'
        OR e.role ILIKE '%JEFE%'
        OR e.role ILIKE '%SUPERVISOR%'
        OR e.role ILIKE '%COORDINADOR%'
    )
GROUP BY
    e.position, e.role, a.name
ORDER BY
    a.name NULLS LAST,
    e.position;

-- -----------------------------------------------------------------------------
-- QUERY 2: Ver si algún JEFE o COORDINADOR NO tiene área asignada
--          (job_position_id null O job_positions sin area_id)
--          Estos son los que van a caer en el ELSE FALSE del RPC
-- -----------------------------------------------------------------------------
SELECT
    e.full_name,
    e.position,
    e.role,
    e.sede,
    e.business_unit,
    e.job_position_id,
    jp.id   AS jp_id,
    jp.name AS jp_name,
    jp.area_id,
    a.name  AS area_name
FROM public.employees e
LEFT JOIN public.job_positions jp ON
    CASE
        WHEN e.job_position_id IS NOT NULL THEN e.job_position_id = jp.id
        ELSE e.position = jp.name
    END
LEFT JOIN public.areas a ON jp.area_id = a.id
WHERE
    e.is_active = true
    AND (
        e.position ILIKE '%JEFE%'
        OR e.position ILIKE '%COORDINADOR%'
        OR e.role ILIKE '%JEFE%'
        OR e.role ILIKE '%COORDINADOR%'
    )
    AND (jp.area_id IS NULL OR jp.id IS NULL)   -- Sin área asignada → problema
ORDER BY
    e.position,
    e.sede;

-- -----------------------------------------------------------------------------
-- QUERY 3: Empleados por área, sede y business_unit (todos los activos)
--          Útil para entender cuántos verá cada jefe según su filtro
-- -----------------------------------------------------------------------------
SELECT
    a.name                              AS area,
    e.sede,
    e.business_unit,
    COUNT(*)                            AS total_empleados
FROM public.employees e
LEFT JOIN public.job_positions jp ON
    CASE
        WHEN e.job_position_id IS NOT NULL THEN e.job_position_id = jp.id
        ELSE e.position = jp.name
    END
LEFT JOIN public.areas a ON jp.area_id = a.id
WHERE e.is_active = true
GROUP BY a.name, e.sede, e.business_unit
ORDER BY a.name NULLS LAST, e.sede, e.business_unit;
