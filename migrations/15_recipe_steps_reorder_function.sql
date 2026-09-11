-- Función para actualizar el orden de los pasos de una receta
CREATE OR REPLACE FUNCTION update_recipe_steps(steps_data jsonb)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  step_record jsonb;
BEGIN
  -- Iterar sobre cada paso en el array de datos
  FOR step_record IN SELECT * FROM jsonb_array_elements(steps_data)
  LOOP
    -- Actualizar el número de paso para cada registro
    UPDATE recipe_version_steps
    SET order_index = (step_record->>'order_index')::integer
    WHERE id = (step_record->>'id')::uuid;
  END LOOP;
END;
$$;
