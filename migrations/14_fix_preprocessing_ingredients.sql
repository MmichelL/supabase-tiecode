-- Script para alinear la tabla preprocessing_ingredients con la documentación
BEGIN;

-- Verificar si la tabla preprocessing_ingredients existe
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM pg_tables
        WHERE schemaname = 'public'
        AND tablename = 'preprocessing_ingredients'
    ) THEN
        RAISE NOTICE 'La tabla preprocessing_ingredients no existe. Creándola...';
        
        -- Crear la tabla preprocessing_ingredients según la documentación
        CREATE TABLE preprocessing_ingredients (
            id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
            recipe_version_ingredient_id UUID NOT NULL REFERENCES recipe_version_ingredients(id) ON DELETE CASCADE,
            tenant_id UUID NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
            ingredient_id UUID REFERENCES ingredients(id) ON DELETE SET NULL,
            ingredient_name_snapshot TEXT NOT NULL,
            quantity NUMERIC NOT NULL,
            unit TEXT NOT NULL,
            order_index INTEGER NOT NULL,
            UNIQUE (recipe_version_ingredient_id, order_index)
        );
        
        -- Habilitar RLS en la tabla
        ALTER TABLE preprocessing_ingredients ENABLE ROW LEVEL SECURITY;
        
        -- Crear política de acceso
        CREATE POLICY preprocessing_ingredient_tenant_access ON preprocessing_ingredients
            USING (tenant_id IN (
                SELECT tenant_id FROM tenant_users WHERE user_id = auth.uid()
            ));
    ELSE
        -- Verificar si la columna order_index existe y no ha sido renombrada a "order"
        IF EXISTS (
            SELECT 1
            FROM information_schema.columns
            WHERE table_schema = 'public'
            AND table_name = 'preprocessing_ingredients'
            AND column_name = 'order_index'
        ) THEN
            RAISE NOTICE 'Renombrando columna order_index a "order" en preprocessing_ingredients...';
            
            -- Renombrar order_index a order para mantener consistencia con recipe_version_ingredients
            ALTER TABLE preprocessing_ingredients
                RENAME COLUMN order_index TO "order";
                
            -- Eliminar la restricción de unicidad existente si existe
            ALTER TABLE preprocessing_ingredients
                DROP CONSTRAINT IF EXISTS preprocessing_ingredients_recipe_version_ingredient_id_order_index_key;
                
            -- Agregar nueva restricción de unicidad con el nombre de columna actualizado
            ALTER TABLE preprocessing_ingredients
                ADD CONSTRAINT preprocessing_ingredients_recipe_version_ingredient_id_order_key
                UNIQUE (recipe_version_ingredient_id, "order");
        ELSE
            RAISE NOTICE 'La columna ya ha sido renombrada a "order" o tiene otro nombre.';
        END IF;
    END IF;
END $$;

-- Verificar si las políticas de seguridad están correctamente configuradas
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM pg_policies
        WHERE schemaname = 'public'
        AND tablename = 'preprocessing_ingredients'
        AND policyname = 'preprocessing_ingredient_tenant_access'
    ) THEN
        RAISE NOTICE 'Creando política de acceso para preprocessing_ingredients...';
        
        -- Crear política de acceso
        CREATE POLICY preprocessing_ingredient_tenant_access ON preprocessing_ingredients
            USING (tenant_id IN (
                SELECT tenant_id FROM tenant_users WHERE user_id = auth.uid()
            ));
    END IF;
    
    -- Verificar si existen políticas adicionales para administradores
    IF NOT EXISTS (
        SELECT 1
        FROM pg_policies
        WHERE schemaname = 'public'
        AND tablename = 'preprocessing_ingredients'
        AND policyname = 'preprocessing_ingredient_admin_insert'
    ) THEN
        RAISE NOTICE 'Creando políticas adicionales para administradores...';
        
        -- Política para permitir a los administradores insertar ingredientes de preprocesamiento
        CREATE POLICY preprocessing_ingredient_admin_insert ON preprocessing_ingredients
            FOR INSERT
            WITH CHECK (
                tenant_id IN (
                    SELECT tu.tenant_id
                    FROM tenant_users tu
                    JOIN roles r ON tu.role_id = r.id
                    WHERE tu.user_id = auth.uid()
                    AND r.name = 'Admin'
                )
            );
            
        -- Política para permitir a los administradores actualizar ingredientes de preprocesamiento
        CREATE POLICY preprocessing_ingredient_admin_update ON preprocessing_ingredients
            FOR UPDATE
            USING (
                tenant_id IN (
                    SELECT tu.tenant_id
                    FROM tenant_users tu
                    JOIN roles r ON tu.role_id = r.id
                    WHERE tu.user_id = auth.uid()
                    AND r.name = 'Admin'
                )
            )
            WITH CHECK (
                tenant_id IN (
                    SELECT tu.tenant_id
                    FROM tenant_users tu
                    JOIN roles r ON tu.role_id = r.id
                    WHERE tu.user_id = auth.uid()
                    AND r.name = 'Admin'
                )
            );
            
        -- Política para permitir a los administradores eliminar ingredientes de preprocesamiento
        CREATE POLICY preprocessing_ingredient_admin_delete ON preprocessing_ingredients
            FOR DELETE
            USING (
                tenant_id IN (
                    SELECT tu.tenant_id
                    FROM tenant_users tu
                    JOIN roles r ON tu.role_id = r.id
                    WHERE tu.user_id = auth.uid()
                    AND r.name = 'Admin'
                )
            );
    END IF;
END $$;

-- Mostrar el estado final de la tabla
SELECT 
    column_name, 
    data_type, 
    is_nullable
FROM 
    information_schema.columns
WHERE 
    table_schema = 'public'
    AND table_name = 'preprocessing_ingredients'
ORDER BY 
    ordinal_position;

-- Mostrar las políticas de la tabla
SELECT 
    schemaname, 
    tablename, 
    policyname, 
    permissive, 
    roles, 
    cmd, 
    qual, 
    with_check
FROM 
    pg_policies
WHERE 
    schemaname = 'public'
    AND tablename = 'preprocessing_ingredients'
ORDER BY 
    policyname;

COMMIT;
