-- =============================================================================
-- Agregar columna "shift" (turno) a work_schedules
-- Valores posibles: 'MAÑANA', 'TARDE', 'NOCHE', NULL
-- =============================================================================
ALTER TABLE public.work_schedules
    ADD COLUMN IF NOT EXISTS shift TEXT CHECK (shift IN ('MAÑANA', 'TARDE', 'NOCHE'));

-- Verificar
SELECT column_name, data_type, is_nullable
FROM information_schema.columns
WHERE table_schema = 'public'
  AND table_name   = 'work_schedules'
  AND column_name  = 'shift';

-- =============================================================================
-- Limpiar campos bonus_start / bonus_end obsoletos
-- (El RPC V3 ya no los usa — calcula automáticamente para OPL)
-- =============================================================================
UPDATE public.work_schedules
SET bonus_start = NULL,
    bonus_end   = NULL
WHERE bonus_start IS NOT NULL
   OR bonus_end   IS NOT NULL;

-- Verificar que quedaron en NULL
SELECT id, name, business_unit, check_in_time, bonus_start, bonus_end
FROM public.work_schedules;
