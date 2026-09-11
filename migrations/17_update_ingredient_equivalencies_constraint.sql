-- Migration: 17_update_ingredient_equivalencies_constraint.sql
-- Description: Modifica la restricción UNIQUE en la tabla ingredient_equivalencies para permitir múltiples equivalencias por ingrediente

BEGIN;

-- 1. Eliminar la restricción UNIQUE existente
ALTER TABLE ingredient_equivalencies 
DROP CONSTRAINT IF EXISTS ingredient_equivalencies_ingredient_id_volume_unit_volume_a_key;

-- 2. Añadir una nueva restricción que incluya también weight_unit para permitir múltiples equivalencias
-- Esto permitirá tener la misma combinación de (ingredient_id, volume_unit, volume_amount) pero con diferentes weight_unit
ALTER TABLE ingredient_equivalencies 
ADD CONSTRAINT ingredient_equivalencies_unique_with_weight 
UNIQUE (ingredient_id, volume_unit, volume_amount, weight_unit);

-- 3. Actualizar la política de seguridad para asegurar que los usuarios con rol de administrador puedan gestionar las equivalencias
DROP POLICY IF EXISTS ingredient_equivalencies_tenant_isolation ON ingredient_equivalencies;
CREATE POLICY ingredient_equivalencies_tenant_isolation ON ingredient_equivalencies
  USING (tenant_id = (SELECT tenant_id FROM tenant_users WHERE user_id = auth.uid() LIMIT 1))
  WITH CHECK (tenant_id = (SELECT tenant_id FROM tenant_users WHERE user_id = auth.uid() LIMIT 1));

COMMIT;
