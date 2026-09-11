-- Migración para actualizar la tabla ingredient_equivalencies
-- Añade el campo volume_fraction para almacenar la representación de fracciones

BEGIN;

-- Añadir la nueva columna volume_fraction y volume_unit_es
ALTER TABLE ingredient_equivalencies
ADD COLUMN IF NOT EXISTS volume_fraction TEXT;
ALTER TABLE ingredient_equivalencies
ADD COLUMN IF NOT EXISTS volume_unit_es TEXT;

-- Actualizar la documentación de la tabla
COMMENT ON TABLE ingredient_equivalencies IS 'Almacena las equivalencias entre unidades de volumen y peso para cada ingrediente';
COMMENT ON COLUMN ingredient_equivalencies.volume_fraction IS 'Representación textual de la fracción (ej: "1/2", "1/4", "1/3")';
COMMENT ON COLUMN ingredient_equivalencies.volume_unit IS 'Unidad de volumen: cup (taza), tbsp (cucharada), tsp (cucharadita)';
COMMENT ON COLUMN ingredient_equivalencies.volume_unit_es IS 'Unidad de volumen en español: taza, cucharada, cucharadita';
COMMENT ON COLUMN ingredient_equivalencies.volume_amount IS 'Cantidad de volumen en formato decimal con 6 dígitos de precisión';
COMMENT ON COLUMN ingredient_equivalencies.weight_unit IS 'Unidad de peso: g (gramos), oz (onzas)';
COMMENT ON COLUMN ingredient_equivalencies.weight_amount IS 'Cantidad de peso';

-- Función para actualizar fracciones y unidades en español
CREATE OR REPLACE FUNCTION update_volume_fractions_and_units()
RETURNS void AS $$
BEGIN
  -- Primero, actualizar las unidades en español para todos los registros
  UPDATE ingredient_equivalencies SET volume_unit_es = 'taza' WHERE volume_unit = 'cup';
  UPDATE ingredient_equivalencies SET volume_unit_es = 'cucharada' WHERE volume_unit = 'tbsp';
  UPDATE ingredient_equivalencies SET volume_unit_es = 'cucharadita' WHERE volume_unit = 'tsp';

  -- Tabla de fracciones estándar exactas con 6 dígitos de precisión

  -- Tazas
  UPDATE ingredient_equivalencies SET volume_fraction = '1/1' WHERE volume_unit = 'cup' AND ROUND(volume_amount::numeric, 6) = 1.000000;
  UPDATE ingredient_equivalencies SET volume_fraction = '1/2' WHERE volume_unit = 'cup' AND ROUND(volume_amount::numeric, 6) = 0.500000;
  UPDATE ingredient_equivalencies SET volume_fraction = '1/3' WHERE volume_unit = 'cup' AND ROUND(volume_amount::numeric, 6) = 0.333333;
  UPDATE ingredient_equivalencies SET volume_fraction = '1/4' WHERE volume_unit = 'cup' AND ROUND(volume_amount::numeric, 6) = 0.250000;
  UPDATE ingredient_equivalencies SET volume_fraction = '1/8' WHERE volume_unit = 'cup' AND ROUND(volume_amount::numeric, 6) = 0.125000;

  -- Cucharadas (tbsp)
  UPDATE ingredient_equivalencies SET volume_fraction = '1/16' WHERE volume_unit = 'tbsp' AND ROUND(volume_amount::numeric, 6) = 1.000000;
  UPDATE ingredient_equivalencies SET volume_fraction = '1/32' WHERE volume_unit = 'tbsp' AND ROUND(volume_amount::numeric, 6) = 0.500000;

  -- Cucharaditas (tsp)
  UPDATE ingredient_equivalencies SET volume_fraction = '1/48' WHERE volume_unit = 'tsp' AND ROUND(volume_amount::numeric, 6) = 1.000000;
  UPDATE ingredient_equivalencies SET volume_fraction = '1/96' WHERE volume_unit = 'tsp' AND ROUND(volume_amount::numeric, 6) = 0.500000;
  UPDATE ingredient_equivalencies SET volume_fraction = '1/192' WHERE volume_unit = 'tsp' AND ROUND(volume_amount::numeric, 6) = 0.250000;

  -- Para valores que ya están en la unidad correcta pero necesitan la fracción
  UPDATE ingredient_equivalencies SET volume_fraction = '1/1' WHERE volume_fraction IS NULL AND ROUND(volume_amount::numeric, 6) = 1.000000;

  -- Valores aproximados (para datos existentes que podrían estar cerca de estos valores)
  UPDATE ingredient_equivalencies SET volume_fraction = '1/3'
    WHERE volume_fraction IS NULL AND volume_unit = 'cup' AND
    ROUND(volume_amount::numeric, 6) BETWEEN 0.333000 AND 0.334000;

  UPDATE ingredient_equivalencies SET volume_fraction = '1/48'
    WHERE volume_fraction IS NULL AND volume_unit = 'tsp' AND
    ROUND(volume_amount::numeric, 6) BETWEEN 0.020800 AND 0.020900;

  UPDATE ingredient_equivalencies SET volume_fraction = '1/96'
    WHERE volume_fraction IS NULL AND volume_unit = 'tsp' AND
    ROUND(volume_amount::numeric, 6) BETWEEN 0.010400 AND 0.010500;

  UPDATE ingredient_equivalencies SET volume_fraction = '1/192'
    WHERE volume_fraction IS NULL AND volume_unit = 'tsp' AND
    ROUND(volume_amount::numeric, 6) BETWEEN 0.005200 AND 0.005300;

  -- Actualizar los valores exactos para asegurar la precisión de 6 dígitos
  UPDATE ingredient_equivalencies SET volume_amount = 1.000000 WHERE volume_fraction = '1/1' AND volume_unit = 'cup';
  UPDATE ingredient_equivalencies SET volume_amount = 0.500000 WHERE volume_fraction = '1/2' AND volume_unit = 'cup';
  UPDATE ingredient_equivalencies SET volume_amount = 0.333333 WHERE volume_fraction = '1/3' AND volume_unit = 'cup';
  UPDATE ingredient_equivalencies SET volume_amount = 0.250000 WHERE volume_fraction = '1/4' AND volume_unit = 'cup';
  UPDATE ingredient_equivalencies SET volume_amount = 0.125000 WHERE volume_fraction = '1/8' AND volume_unit = 'cup';

  UPDATE ingredient_equivalencies SET volume_amount = 0.062500 WHERE volume_fraction = '1/16' AND volume_unit = 'tbsp';
  UPDATE ingredient_equivalencies SET volume_amount = 0.031250 WHERE volume_fraction = '1/32' AND volume_unit = 'tbsp';

  UPDATE ingredient_equivalencies SET volume_amount = 0.020833 WHERE volume_fraction = '1/48' AND volume_unit = 'tsp';
  UPDATE ingredient_equivalencies SET volume_amount = 0.010417 WHERE volume_fraction = '1/96' AND volume_unit = 'tsp';
  UPDATE ingredient_equivalencies SET volume_amount = 0.005208 WHERE volume_fraction = '1/192' AND volume_unit = 'tsp';
END;
$$ LANGUAGE plpgsql;

-- Ejecutar la función para actualizar los datos existentes
SELECT update_volume_fractions_and_units();

-- Eliminar la función temporal
DROP FUNCTION update_volume_fractions_and_units();

COMMIT;
