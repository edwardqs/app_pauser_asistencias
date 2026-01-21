-- ÍNDICE ÚNICO PARA PREVENIR DUPLICADOS DE ASISTENCIA
-- Asegura que un empleado solo tenga un registro (work_date) por día.
-- Esto evitará que la App cree múltiples entradas si el usuario hace clic muchas veces
-- o si la UI no se actualiza a tiempo.

CREATE UNIQUE INDEX IF NOT EXISTS idx_attendance_employee_date 
ON public.attendance (employee_id, work_date);
