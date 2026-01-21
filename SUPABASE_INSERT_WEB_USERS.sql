-- SCRIPT PARA CREAR PERFILES DE EMPLEADOS PARA USUARIOS WEB
-- Esto vincula los correos de login con registros en la tabla employees

-- 1. Usuario ADMIN (admin@pauser.com)
INSERT INTO public.employees (
    full_name, 
    dni, 
    email, 
    app_password, 
    sede, 
    business_unit, 
    role, 
    position, 
    employee_type,
    entry_date
) VALUES (
    'Administrador Sistema', 
    '99999999', 
    'admin@pauser.com', 
    '123456', 
    'LIMA', 
    'ADMINISTRACION', 
    'ADMIN', 
    'Administrador General', 
    'Planilla',
    CURRENT_DATE
)
ON CONFLICT (dni) DO UPDATE SET
    email = EXCLUDED.email,
    role = EXCLUDED.role,
    full_name = EXCLUDED.full_name;

-- 2. Usuario ANALISTA (analistagente@pauser.com)
-- Le asignamos rol JEFE_VENTAS para que tenga permisos de validación global/amplia
INSERT INTO public.employees (
    full_name, 
    dni, 
    email, 
    app_password, 
    sede, 
    business_unit, 
    role, 
    position, 
    employee_type,
    entry_date
) VALUES (
    'Analista de Gestión', 
    '88888888', 
    'analistagente@pauser.com', 
    '123456', 
    'LIMA', 
    'RRHH', 
    'JEFE_VENTAS', -- Rol con permisos de validación
    'Analista de RRHH', 
    'Planilla',
    CURRENT_DATE
)
ON CONFLICT (dni) DO UPDATE SET
    email = EXCLUDED.email,
    role = EXCLUDED.role,
    full_name = EXCLUDED.full_name;
