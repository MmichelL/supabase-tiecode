-- Iniciar transacción
BEGIN;

-- Modificar la tabla recipe_version_ingredients para alinearla con la documentación
ALTER TABLE recipe_version_ingredients
  -- Renombrar order_index a order
  RENAME COLUMN order_index TO "order";

-- Eliminar las restricciones de unicidad existentes si existen
ALTER TABLE recipe_version_ingredients
  DROP CONSTRAINT IF EXISTS recipe_version_ingredients_recipe_version_id_order_index_key;

-- Agregar nueva restricción de unicidad con el nombre de columna actualizado
ALTER TABLE recipe_version_ingredients
  ADD CONSTRAINT recipe_version_ingredients_recipe_version_id_order_key
  UNIQUE (recipe_version_id, "order");

-- Modificar las columnas de preprocesamiento
ALTER TABLE recipe_version_ingredients
  -- Agregar columnas nuevas según la documentación
  ADD COLUMN requires_preprocessing BOOLEAN DEFAULT false,
  ADD COLUMN preprocessing_output_quantity NUMERIC,
  ADD COLUMN preprocessing_output_unit TEXT,
  ADD COLUMN preprocess_with_ingredients JSONB;

-- Migrar datos de las columnas antiguas a las nuevas
UPDATE recipe_version_ingredients
SET
  requires_preprocessing = CASE WHEN preprocessing_description IS NOT NULL THEN true ELSE false END,
  preprocessing_output_quantity = CASE
    WHEN preprocessing_output IS NOT NULL THEN
      (SELECT (regexp_matches(preprocessing_output, '^(\d+\.?\d*)'))::text[])[1]::NUMERIC
    ELSE NULL
  END,
  preprocessing_output_unit = CASE
    WHEN preprocessing_output IS NOT NULL THEN
      regexp_replace(preprocessing_output, '^\d+\.?\d*\s+', '')
    ELSE NULL
  END;

-- Eliminar las columnas antiguas
ALTER TABLE recipe_version_ingredients
  DROP COLUMN IF EXISTS preprocessing_output;

-- Mantener preprocessing_description ya que está en la documentación

-- Confirmar la transacción
COMMIT;
