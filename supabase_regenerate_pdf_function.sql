-- Función para regenerar PDF de una solicitud
-- Esta función se llamará desde la app móvil cuando necesite regenerar un PDF

CREATE OR REPLACE FUNCTION regenerate_vacation_pdf(request_id_param UUID)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  result JSON;
  request_data RECORD;
BEGIN
  -- Obtener datos de la solicitud
  SELECT 
    vr.*,
    e.full_name,
    e.dni,
    e.position,
    e.sede
  INTO request_data
  FROM vacation_requests vr
  JOIN employees e ON vr.employee_id = e.id
  WHERE vr.id = request_id_param;

  -- Verificar que la solicitud existe
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Solicitud no encontrada';
  END IF;

  -- Verificar que la solicitud está aprobada
  IF request_data.status != 'APROBADO' THEN
    RAISE EXCEPTION 'Solo se pueden generar PDFs para solicitudes aprobadas';
  END IF;

  -- Retornar los datos necesarios para que el cliente genere el PDF
  -- (La generación real del PDF se hará en el cliente web o mediante Edge Function)
  result := json_build_object(
    'success', true,
    'message', 'Datos de solicitud obtenidos correctamente',
    'request_id', request_id_param,
    'employee_name', request_data.full_name,
    'employee_dni', request_data.dni,
    'employee_position', request_data.position,
    'employee_sede', request_data.sede,
    'request_type', request_data.request_type,
    'start_date', request_data.start_date,
    'end_date', request_data.end_date,
    'total_days', request_data.total_days,
    'current_pdf_url', request_data.pdf_url
  );

  RETURN result;
END;
$$;

-- Dar permisos de ejecución a usuarios autenticados
GRANT EXECUTE ON FUNCTION regenerate_vacation_pdf(UUID) TO authenticated;

COMMENT ON FUNCTION regenerate_vacation_pdf IS 'Obtiene los datos necesarios para regenerar el PDF de una solicitud de vacaciones';
