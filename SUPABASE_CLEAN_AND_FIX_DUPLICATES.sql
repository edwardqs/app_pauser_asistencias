-- LIMPIEZA DE DUPLICADOS DE ASISTENCIA
-- Mantiene solo el primer registro (check-in más antiguo) de cada empleado por día
-- y elimina los registros posteriores que son duplicados erróneos.

DELETE FROM public.attendance a
USING (
    SELECT id,
           ROW_NUMBER() OVER (
               PARTITION BY employee_id, work_date 
               ORDER BY created_at ASC -- Mantenemos el PRIMER intento (el original)
           ) as r_num
    FROM public.attendance
) duplicates
WHERE a.id = duplicates.id
AND duplicates.r_num > 1;

-- AHORA SÍ CREAMOS EL ÍNDICE ÚNICO
CREATE UNIQUE INDEX IF NOT EXISTS idx_attendance_employee_date 
ON public.attendance (employee_id, work_date);
