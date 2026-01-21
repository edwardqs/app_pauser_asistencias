-- Script de Configuración para Supabase (PostgreSQL) - Actualizado con Estructura Exacta

-- 1. Tabla de Empleados (employees)
-- Estructura basada en la imagen proporcionada:
CREATE TABLE IF NOT EXISTS public.employees (
    id uuid DEFAULT gen_random_uuid() PRIMARY KEY,
    created_at timestamp with time zone DEFAULT timezone('utc'::text, now()) NOT NULL,
    sede text,
    business_unit text,
    employee_type text,
    dni text NOT NULL UNIQUE,
    full_name text NOT NULL,
    birth_date date,
    address text,
    phone text,
    email text,
    entry_date date DEFAULT CURRENT_DATE,
    position text,
    app_password text NOT NULL DEFAULT '123456'
);

-- 2. Tabla de Asistencias (attendance)
-- Estructura basada en la imagen proporcionada:
CREATE TABLE IF NOT EXISTS public.attendance (
    id uuid DEFAULT gen_random_uuid() PRIMARY KEY,
    created_at timestamp with time zone DEFAULT timezone('utc'::text, now()) NOT NULL,
    employee_id uuid REFERENCES public.employees(id) ON DELETE CASCADE NOT NULL,
    work_date date DEFAULT CURRENT_DATE,
    check_in timestamp with time zone,
    check_out timestamp with time zone,
    location_in jsonb,
    location_out jsonb,
    status text DEFAULT 'presente',
    notes text
);

-- 3. Tabla de Logs de Actividad (activity_logs) - Opcional según imagen, útil tenerla definida
CREATE TABLE IF NOT EXISTS public.activity_logs (
    id uuid DEFAULT gen_random_uuid() PRIMARY KEY,
    created_at timestamp with time zone DEFAULT timezone('utc'::text, now()) NOT NULL,
    description text,
    type text,
    metadata jsonb
);

-- 4. Habilitar RLS (Row Level Security)
ALTER TABLE public.employees ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.attendance ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.activity_logs ENABLE ROW LEVEL SECURITY;

-- Políticas de ejemplo (Permisivas para desarrollo)
DROP POLICY IF EXISTS "Enable read access for all users" ON public.employees;
CREATE POLICY "Enable read access for all users" ON public.employees FOR SELECT USING (true);

DROP POLICY IF EXISTS "Enable read access for all users" ON public.attendance;
CREATE POLICY "Enable read access for all users" ON public.attendance FOR SELECT USING (true);

DROP POLICY IF EXISTS "Enable insert for all users" ON public.attendance;
CREATE POLICY "Enable insert for all users" ON public.attendance FOR INSERT WITH CHECK (true);

DROP POLICY IF EXISTS "Enable update for all users" ON public.attendance;
CREATE POLICY "Enable update for all users" ON public.attendance FOR UPDATE USING (true);

-- 5. Función RPC para Login (mobile_login)
DROP FUNCTION IF EXISTS public.mobile_login(text, text);

CREATE OR REPLACE FUNCTION public.mobile_login(dni_input text, password_input text)
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    found_employee RECORD;
BEGIN
    -- Buscar empleado por DNI
    SELECT * INTO found_employee FROM public.employees WHERE dni = dni_input;

    -- Verificar si existe y la contraseña coincide
    IF found_employee IS NOT NULL AND found_employee.app_password = password_input THEN
        RETURN json_build_object(
            'success', true,
            'employee_id', found_employee.id,
            'full_name', found_employee.full_name,
            'dni', found_employee.dni,
            'sede', found_employee.sede,
            'business_unit', found_employee.business_unit,
            'employee_type', found_employee.employee_type,
            'position', found_employee.position
        );
    ELSE
        RETURN json_build_object(
            'success', false,
            'message', 'Credenciales inválidas'
        );
    END IF;
END;
$$;

-- Datos de Prueba (Seed)
-- Usamos ON CONFLICT para insertar o actualizar datos de prueba sin duplicar
INSERT INTO public.employees (
    dni, app_password, full_name, sede, business_unit, employee_type, position, entry_date
)
VALUES 
('12345678', '123456', 'Juan Perez', 'TRUJILLO', 'SNACKS', 'OPERATIVO', 'OPERARIO DE PRODUCCION', CURRENT_DATE),
('87654321', '654321', 'Maria Lopez', 'ADM. CENTRAL', NULL, 'ADMINISTRATIVO', 'ANALISTA DE GENTE Y GESTIÓN', CURRENT_DATE),
('11223344', '123456', 'Carlos Ruiz', 'CHIMBOTE', 'BEBIDAS', 'COMERCIAL', 'VENDEDOR MAYORISTA', CURRENT_DATE)
ON CONFLICT (dni) DO UPDATE 
SET 
    full_name = EXCLUDED.full_name,
    sede = EXCLUDED.sede,
    business_unit = EXCLUDED.business_unit,
    employee_type = EXCLUDED.employee_type,
    position = EXCLUDED.position;
