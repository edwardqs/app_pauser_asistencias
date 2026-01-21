-- SCRIPT DE POBLADO DE DATOS (SEED) - JERARQUÍA CORRECTA V7 (FIXED)
-- Contraseña para todos: 123456
-- Corrección: Se agrega entry_date obligatorio

-- Limpieza preventiva (opcional)
-- DELETE FROM public.employees WHERE dni IN ('10000001', '20000002', '30000003', '40000004', '50000005', '60000006');

-------------------------------------------------------
-- RAMA COMERCIAL (VENTAS)
-------------------------------------------------------

-- 1. JEFE DE VENTAS (Nivel Superior)
INSERT INTO public.employees (
    full_name, dni, app_password, sede, business_unit, role, position, employee_type, entry_date
) VALUES (
    'RICARDO JEFE', '10000001', '123456', 'LIMA', 'COMERCIAL', 
    'JEFE_VENTAS', 'Jefe Nacional de Ventas', 'Planilla', '2024-01-01'
);

-- 2. SUPERVISOR DE VENTAS (Reporta a Jefe de Ventas)
INSERT INTO public.employees (
    full_name, dni, app_password, sede, business_unit, role, position, employee_type, supervisor_id, entry_date
) VALUES (
    'ROBERTO SUPERVENTAS', '20000002', '123456', 'TRUJILLO', 'SNACKS', 
    'SUPERVISOR_VENTAS', 'Supervisor Regional', 'Planilla',
    (SELECT id FROM public.employees WHERE dni = '10000001'), '2024-01-01'
);

-- 3. VENDEDOR (Reporta a Supervisor de Ventas)
INSERT INTO public.employees (
    full_name, dni, app_password, sede, business_unit, role, position, employee_type, supervisor_id, entry_date
) VALUES (
    'VICTOR VENDEDOR', '30000003', '123456', 'TRUJILLO', 'SNACKS', 
    'VENDEDOR', 'Vendedor Ruta', 'Comisionista',
    (SELECT id FROM public.employees WHERE dni = '20000002'), '2024-01-01'
);

-------------------------------------------------------
-- RAMA OPERACIONES (LOGÍSTICA / DISTRIBUCIÓN)
-------------------------------------------------------

-- 4. SUPERVISOR DE OPERACIONES (Nivel Superior Ops)
INSERT INTO public.employees (
    full_name, dni, app_password, sede, business_unit, role, position, employee_type, entry_date
) VALUES (
    'OSCAR SUPEROPS', '40000004', '123456', 'CHIMBOTE', 'LOGISTICA', 
    'SUPERVISOR_OPERACIONES', 'Jefe de Centro Distribución', 'Planilla', '2024-01-01'
);

-- 5. COORDINADOR DE OPERACIONES (Reporta a Supervisor de Operaciones)
INSERT INTO public.employees (
    full_name, dni, app_password, sede, business_unit, role, position, employee_type, supervisor_id, entry_date
) VALUES (
    'CARLOS COORDINADOR', '50000005', '123456', 'CHIMBOTE', 'LOGISTICA', 
    'COORDINADOR_OPERACIONES', 'Coordinador de Flota', 'Planilla',
    (SELECT id FROM public.employees WHERE dni = '40000004'), '2024-01-01'
);

-- 6. CHOFER (Reporta a Coordinador de Operaciones)
INSERT INTO public.employees (
    full_name, dni, app_password, sede, business_unit, role, position, employee_type, supervisor_id, entry_date
) VALUES (
    'CESAR CHOFER', '60000006', '123456', 'CHIMBOTE', 'LOGISTICA', 
    'CHOFER', 'Conductor A3B', 'Planilla',
    (SELECT id FROM public.employees WHERE dni = '50000005'), '2024-01-01'
);
