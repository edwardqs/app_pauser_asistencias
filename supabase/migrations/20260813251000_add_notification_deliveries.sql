-- Tabla de entregas idempotentes para recordatorios de asistencia.
CREATE TABLE IF NOT EXISTS public.attendance_notification_deliveries (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    employee_id uuid NOT NULL REFERENCES public.employees(id) ON DELETE CASCADE,
    work_date date NOT NULL,
    schedule_id uuid REFERENCES public.work_schedules(id) ON DELETE CASCADE,
    shift text NOT NULL DEFAULT 'UNICO',
    kind text NOT NULL CHECK (kind IN ('CHECK_IN', 'CHECK_OUT')),
    sent_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (employee_id, work_date, schedule_id, shift, kind)
);

CREATE INDEX IF NOT EXISTS idx_attendance_notification_deliveries_employee
    ON public.attendance_notification_deliveries (employee_id, work_date);

ALTER TABLE public.attendance_notification_deliveries ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "deliveries_service_all" ON public.attendance_notification_deliveries;
CREATE POLICY "deliveries_service_all"
    ON public.attendance_notification_deliveries
    FOR ALL
    TO service_role
    USING (true)
    WITH CHECK (true);
