-- ==============================================================================
-- OTORGAR PRIVILEGIOS TOTALES A "JEFE DE GENTE Y GESTIÓN"
-- ==============================================================================

-- 1. Actualizar usuarios existentes
-- Asignamos el rol 'JEFE_RRHH' (que ya tiene permisos de ADMIN/Superusuario en las políticas)
-- a cualquier empleado cuyo cargo contenga "JEFE DE GENTE" o "JEFE DE AREA DE GENTE"
UPDATE public.employees
SET role = 'JEFE_RRHH'
WHERE position ILIKE '%JEFE DE GENTE%' 
   OR position ILIKE '%JEFE DE AREA DE GENTE%';

-- 2. Crear función Trigger para mantener esto automático
CREATE OR REPLACE FUNCTION public.auto_assign_admin_role()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
    -- Si el cargo es de Jefe de Gente y Gestión, asignar rol JEFE_RRHH
    IF NEW.position ILIKE '%JEFE DE GENTE%' OR NEW.position ILIKE '%JEFE DE AREA DE GENTE%' THEN
        NEW.role := 'JEFE_RRHH';
    END IF;
    
    -- Si el cargo es Analista de Gente, asignar rol ANALISTA_RRHH
    IF NEW.position ILIKE '%ANALISTA DE GENTE%' OR NEW.position ILIKE '%ANALISTA DE RRHH%' THEN
        NEW.role := 'ANALISTA_RRHH';
    END IF;

    RETURN NEW;
END;
$$;

-- 3. Vincular Trigger a la tabla employees
DROP TRIGGER IF EXISTS trigger_auto_assign_admin_role ON public.employees;

CREATE TRIGGER trigger_auto_assign_admin_role
BEFORE INSERT OR UPDATE OF position ON public.employees
FOR EACH ROW
EXECUTE FUNCTION public.auto_assign_admin_role();

-- 4. Verificación de Políticas RLS (Asegurar que JEFE_RRHH tenga acceso)
-- Ya verificado en scripts anteriores:
-- - attendance: "RRHH View All Attendance" incluye 'JEFE_RRHH'
-- - vacation_requests: "Supervisors can view requests" incluye 'JEFE_RRHH'

-- 5. Actualizar también la tabla de permisos de vacaciones (si existe lógica extra)
-- (La lógica actual en SUPABASE_V2_SCHEMA usa 'JEFE_RRHH', así que estamos cubiertos)
