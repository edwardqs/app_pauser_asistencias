-- =============================================================================
-- DIAGNÓSTICO: Distribución de empleados área COMERCIAL
-- Ejecutar en Supabase → SQL Editor para entender la estructura antes de
-- ajustar el RPC.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- QUERY 1: Total de empleados en área COMERCIAL
--          Excluye a JEFE DE VENTAS y JEFE COMERCIAL
-- -----------------------------------------------------------------------------
SELECT
    COUNT(*) AS total_comercial_sin_jefes
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
        a.name ILIKE '%COMERCIAL%'
        OR e.business_unit ILIKE '%COMERCIAL%'
    )
    AND e.position NOT ILIKE '%JEFE%'
    AND e.role NOT ILIKE '%JEFE%';

-- -----------------------------------------------------------------------------
-- QUERY 2: Distribución por sede y unidad de negocio en área COMERCIAL
--          Excluye JEFE DE VENTAS y JEFE COMERCIAL
--          Útil para ver cuántos empleados debe ver cada JEFE DE VENTAS
-- -----------------------------------------------------------------------------
SELECT
    e.sede,
    e.business_unit,
    a.name AS area,
    COUNT(*) AS total_empleados,
    STRING_AGG(DISTINCT e.position, ', ' ORDER BY e.position) AS cargos_presentes
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
        a.name ILIKE '%COMERCIAL%'
        OR e.business_unit ILIKE '%COMERCIAL%'
    )
    AND e.position NOT ILIKE '%JEFE%'
    AND e.role NOT ILIKE '%JEFE%'
GROUP BY
    e.sede,
    e.business_unit,
    a.name
ORDER BY
    e.sede,
    e.business_unit;

-- -----------------------------------------------------------------------------
-- QUERY 3 (Referencia): Todos los JEFES del área COMERCIAL
--          Para confirmar qué cargos/roles se usarán en el RPC
-- -----------------------------------------------------------------------------
SELECT
    e.full_name,
    e.position,
    e.role,
    e.sede,
    e.business_unit,
    a.name AS area
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
        a.name ILIKE '%COMERCIAL%'
        OR e.business_unit ILIKE '%COMERCIAL%'
        OR e.position ILIKE '%JEFE%'
        OR e.position ILIKE '%COMERCIAL%'
    )
    AND (
        e.position ILIKE '%JEFE%'
        OR e.role ILIKE '%JEFE%'
    )
ORDER BY
    e.position,
    e.sede;
