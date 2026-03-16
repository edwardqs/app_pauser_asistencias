-- =============================================================================
-- FERIADOS PERUANOS — SISTEMA AUTOGESTIONADO
-- =============================================================================
-- INSTRUCCIONES: Ejecutar COMPLETO en Supabase → SQL Editor
-- =============================================================================
-- FUNCIONAMIENTO:
--   • Feriados FIJOS   → misma fecha cada año (ej. 25 dic siempre es Navidad)
--   • Feriados VARIABLES → Jueves/Viernes Santo cambian de fecha cada año
--     Se calculan con el algoritmo de Butcher (matemática pura, sin APIs)
--   • Años bisiestos   → el algoritmo los maneja automáticamente.
--     Ningún feriado peruano cae en 29 de febrero, sin impacto.
--   • Auto-incremento  → cron corre el 1 de diciembre cada año y genera
--     los feriados del año siguiente → siempre hay datos disponibles.
-- =============================================================================


-- =============================================================================
-- 1. TABLA peru_holidays
-- =============================================================================
CREATE TABLE IF NOT EXISTS public.peru_holidays (
    id         UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    date       DATE        NOT NULL UNIQUE,
    name       TEXT        NOT NULL,
    year       INT         NOT NULL GENERATED ALWAYS AS (EXTRACT(YEAR FROM date)::int) STORED,
    is_leap    BOOLEAN     NOT NULL GENERATED ALWAYS AS (
                               EXTRACT(YEAR FROM date)::int % 4 = 0 AND (
                                   EXTRACT(YEAR FROM date)::int % 100 <> 0 OR
                                   EXTRACT(YEAR FROM date)::int % 400 = 0
                               )
                           ) STORED,  -- año bisiesto (informativo)
    is_extra   BOOLEAN     NOT NULL DEFAULT false,  -- true = puente/decreto
    created_at TIMESTAMPTZ DEFAULT now()
);

ALTER TABLE public.peru_holidays ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Autenticados leen feriados"
    ON public.peru_holidays FOR SELECT TO authenticated USING (true);
CREATE POLICY "Autenticados gestionan feriados"
    ON public.peru_holidays FOR ALL TO authenticated USING (true);

CREATE INDEX IF NOT EXISTS idx_peru_holidays_date ON public.peru_holidays(date);
CREATE INDEX IF NOT EXISTS idx_peru_holidays_year ON public.peru_holidays(year);


-- =============================================================================
-- 2. FUNCIÓN: Calcular Domingo de Pascua para cualquier año
--    Algoritmo de Butcher/Anonymous — funciona para cualquier año gregoriano
--    incluyendo años bisiestos.
-- =============================================================================
CREATE OR REPLACE FUNCTION public.calculate_easter(p_year INT)
RETURNS DATE
LANGUAGE plpgsql
IMMUTABLE
AS $function$
DECLARE
    a INT; b INT; c INT; d INT; e INT;
    f INT; g INT; h INT; i INT; k INT;
    l INT; m INT;
BEGIN
    a := p_year % 19;
    b := p_year / 100;
    c := p_year % 100;
    d := b / 4;
    e := b % 4;
    f := (b + 8) / 25;
    g := (b - f + 1) / 3;
    h := (19 * a + b - d - g + 15) % 30;
    i := c / 4;
    k := c % 4;
    l := (32 + 2 * e + 2 * i - h - k) % 7;
    m := (a + 11 * h + 22 * l) / 451;

    RETURN make_date(
        p_year,
        (h + l - 7 * m + 114) / 31,
        ((h + l - 7 * m + 114) % 31) + 1
    );
END;
$function$;

/*
  Verificación del algoritmo (incluyendo años bisiestos):
  SELECT p_year, public.calculate_easter(p_year) AS pascua
  FROM   generate_series(2025, 2035) AS p_year;

  Esperado:
  2025 → 2025-04-20   2028 → 2028-04-16  (bisiesto ✓)
  2026 → 2026-04-05   2032 → 2032-03-28  (bisiesto ✓)
  2027 → 2027-03-28
*/


-- =============================================================================
-- 3. FUNCIÓN: Generar los 12 feriados peruanos de un año dado
--    Llamar con: SELECT public.generate_peru_holidays(2027);
--    Si los feriados ya existen → ON CONFLICT DO NOTHING (seguro re-ejecutar)
-- =============================================================================
CREATE OR REPLACE FUNCTION public.generate_peru_holidays(p_year INT)
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
AS $function$
DECLARE
    v_easter   DATE;
    v_count    INT;
    v_is_leap  BOOLEAN;
BEGIN
    v_easter  := public.calculate_easter(p_year);
    v_is_leap := (p_year % 4 = 0) AND (p_year % 100 <> 0 OR p_year % 400 = 0);

    INSERT INTO public.peru_holidays (date, name, is_extra) VALUES
        -- ── Fijos (misma fecha todos los años) ────────────────────────────────
        (make_date(p_year,  1,  1), 'Año Nuevo',               false),
        (make_date(p_year,  5,  1), 'Día del Trabajo',         false),
        (make_date(p_year,  6, 29), 'San Pedro y San Pablo',   false),
        (make_date(p_year,  7, 28), 'Fiestas Patrias',         false),
        (make_date(p_year,  7, 29), 'Fiestas Patrias',         false),
        (make_date(p_year,  8, 30), 'Santa Rosa de Lima',      false),
        (make_date(p_year, 10,  8), 'Combate de Angamos',      false),
        (make_date(p_year, 11,  1), 'Todos los Santos',        false),
        (make_date(p_year, 12,  8), 'Inmaculada Concepción',   false),
        (make_date(p_year, 12, 25), 'Navidad',                 false),
        -- ── Variables (Semana Santa — calculados con Butcher) ─────────────────
        (v_easter - 3,              'Jueves Santo',            false),
        (v_easter - 2,              'Viernes Santo',           false)
    ON CONFLICT (date) DO NOTHING;

    GET DIAGNOSTICS v_count = ROW_COUNT;

    RETURN json_build_object(
        'year',     p_year,
        'is_leap',  v_is_leap,
        'easter',   v_easter,
        'jueves',   v_easter - 3,
        'viernes',  v_easter - 2,
        'inserted', v_count
    );
END;
$function$;


-- =============================================================================
-- 4. GENERAR FERIADOS AL INSTALAR (año actual + siguiente)
-- =============================================================================
SELECT public.generate_peru_holidays(EXTRACT(YEAR FROM CURRENT_DATE)::int);
SELECT public.generate_peru_holidays(EXTRACT(YEAR FROM CURRENT_DATE)::int + 1);

-- Verificar resultado
SELECT
    year,
    is_leap,
    COUNT(*)                                     AS total,
    STRING_AGG(name || ' (' || TO_CHAR(date, 'DD/MM') || ')',
               ', ' ORDER BY date)               AS feriados
FROM   public.peru_holidays
GROUP  BY year, is_leap
ORDER  BY year;


-- =============================================================================
-- 5. CRON: El 1 de diciembre de cada año genera el año siguiente
--    2026-dic-01 → genera 2027
--    2027-dic-01 → genera 2028
--    ...indefinidamente
-- =============================================================================
DO $$
BEGIN
    PERFORM cron.unschedule('generate-next-year-holidays');
EXCEPTION WHEN OTHERS THEN NULL;
END;
$$;

SELECT cron.schedule(
    'generate-next-year-holidays',
    '0 6 1 12 *',   -- 01 diciembre · 01:00 hora Peru (06:00 UTC)
    $$SELECT public.generate_peru_holidays(EXTRACT(YEAR FROM CURRENT_DATE)::int + 1)$$
);


-- =============================================================================
-- 6. COLUMNAS NUEVAS EN work_schedules
-- =============================================================================

-- Tipo de horario
ALTER TABLE public.work_schedules
    ADD COLUMN IF NOT EXISTS schedule_type TEXT NOT NULL DEFAULT 'REGULAR'
        CHECK (schedule_type IN ('REGULAR', 'FERIADO', 'DOMINGO'));

-- Fecha objetivo (solo horarios especiales, auto-actualizable)
ALTER TABLE public.work_schedules
    ADD COLUMN IF NOT EXISTS target_date DATE;

-- Nombre del evento ("Jueves Santo", "Domingo 15/03/2026")
ALTER TABLE public.work_schedules
    ADD COLUMN IF NOT EXISTS holiday_name TEXT;

-- Días laborables: 1=Lun 2=Mar 3=Mié 4=Jue 5=Vie 6=Sáb 7=Dom
ALTER TABLE public.work_schedules
    ADD COLUMN IF NOT EXISTS work_days INT[] DEFAULT '{1,2,3,4,5,6}';

-- Asegurar valores en registros existentes
UPDATE public.work_schedules
SET
    schedule_type = 'REGULAR',
    work_days     = '{1,2,3,4,5,6}'
WHERE schedule_type = 'REGULAR'
  AND (work_days IS NULL OR work_days = '{}');

-- Verificar work_schedules
SELECT id, name, schedule_type, target_date, holiday_name, work_days
FROM   public.work_schedules
ORDER  BY schedule_type, name;


-- =============================================================================
-- 7. CONSTRAINT record_type EN attendance (si no existe ya)
-- =============================================================================
DO $$
BEGIN
    -- Eliminar constraint anterior si solo tenía ASISTENCIA/AUSENCIA
    ALTER TABLE public.attendance
        DROP CONSTRAINT IF EXISTS attendance_record_type_check;

    -- Agregar con el nuevo valor FALTA_JUSTIFICADA
    ALTER TABLE public.attendance
        ADD CONSTRAINT attendance_record_type_check
        CHECK (record_type IN ('ASISTENCIA', 'AUSENCIA', 'FALTA_JUSTIFICADA'));
EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE 'Constraint no modificado: %', SQLERRM;
END;
$$;


-- =============================================================================
-- REFERENCIA RÁPIDA
-- =============================================================================
-- Ver próximos 5 feriados desde hoy:
-- SELECT date, name, is_leap FROM public.peru_holidays
-- WHERE date >= CURRENT_DATE ORDER BY date LIMIT 5;

-- Agregar puente decretado manualmente:
-- INSERT INTO public.peru_holidays (date, name, is_extra)
-- VALUES ('2026-07-27', 'Puente Fiestas Patrias', true);

-- Generar un año específico manualmente:
-- SELECT public.generate_peru_holidays(2030);
