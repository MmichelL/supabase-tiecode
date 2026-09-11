-- ============================================================================
-- 19 — update_recipe_steps con autorización real
-- ----------------------------------------------------------------------------
-- Defecto C6: la función era SECURITY DEFINER sin ningún chequeo, así que
-- cualquier usuario autenticado podía reordenar pisadas de recetas de OTRO
-- tenant, saltándose las políticas RLS por completo.
--
-- La recreación:
--   1. Rechaza llamadas anónimas.
--   2. Exige can_write(tenant_id, 'update_recipe') para cada paso tocado —
--      el mismo nivel que la política recipe_version_step_update.
--   3. Baja a SECURITY INVOKER como defensa en profundidad: con las políticas
--      de la migración 18 activas, la función ya no necesita privilegios
--      elevados y cualquier agujero nuevo en este chequeo queda cubierto por
--      el RLS de la tabla.
-- ============================================================================

CREATE OR REPLACE FUNCTION update_recipe_steps(steps_data jsonb)
RETURNS void
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = public
AS $$
DECLARE
  step_record jsonb;
  step_tenant uuid;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'update_recipe_steps: se requiere autenticación';
  END IF;

  FOR step_record IN SELECT * FROM jsonb_array_elements(steps_data)
  LOOP
    SELECT tenant_id INTO step_tenant
    FROM recipe_version_steps
    WHERE id = (step_record->>'id')::uuid;

    IF NOT FOUND THEN
      -- Saltar ids que no existen: un paso borrado a mitad de edición no debe
      -- tumbar el guardado del resto de la lista.
      CONTINUE;
    END IF;

    IF NOT can_write(step_tenant, 'update_recipe') THEN
      RAISE EXCEPTION 'update_recipe_steps: sin permiso de edición en este negocio';
    END IF;

    UPDATE recipe_version_steps
    SET order_index = (step_record->>'order_index')::integer
    WHERE id = (step_record->>'id')::uuid;
  END LOOP;
END;
$$;
