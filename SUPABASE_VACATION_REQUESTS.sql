-- =============================================================================
-- TABLA DE SOLICITUDES DE VACACIONES Y PERMISOS - SOLUCIÓN TOTAL
-- =============================================================================

-- 1. Asegurar tabla
CREATE TABLE IF NOT EXISTS public.vacation_requests (
    id uuid DEFAULT gen_random_uuid() PRIMARY KEY,
    employee_id uuid REFERENCES public.employees(id) ON DELETE CASCADE,
    start_date date NOT NULL,
    end_date date NOT NULL,
    total_days integer,
    notes text,
    status text DEFAULT 'PENDIENTE',
    created_at timestamp with time zone DEFAULT now(),
    updated_at timestamp with time zone DEFAULT now(),
    evidence_url text,
    request_type text
);

-- 2. DESHABILITAR RLS TEMPORALMENTE (Para confirmar que es el problema)
-- Esto quitará CUALQUIER restricción. Si falla con esto, no es RLS.
ALTER TABLE public.vacation_requests DISABLE ROW LEVEL SECURITY;

-- 3. Índices
CREATE INDEX IF NOT EXISTS idx_vacation_requests_employee_id ON public.vacation_requests(employee_id);
