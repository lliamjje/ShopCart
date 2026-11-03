/*
    001_CrearBaseDatos.sql — Arranque especial de ShopCart.
    Ejecutar el archivo COMPLETO como un único lote, desde master, en DataGrip
    con Auto-commit y sin transacciones abiertas. No ejecutar selecciones parciales.
    No agregar separadores GO: un error debe detener todos los pasos dependientes.
    El SQL dinámico es constante, sin entradas ni concatenación de parámetros;
    proporciona lotes propios para CREATE DATABASE y para el contexto ShopCart.
    No ejecutar simultáneamente con otro arranque o cambio administrativo.

    No se registra 001: VersionesMigracion queda destinada a migraciones posteriores.
    SHA256 se almacena como 32 bytes, no como una cadena hexadecimal de 64 caracteres.
    Los archivos de datos y log utilizan las rutas predeterminadas de la instancia.
*/
SET NOCOUNT ON;

IF DB_NAME() <> N'master'
    THROW 51000, N'Ejecute el archivo completo desde la base master.', 1;

IF @@TRANCOUNT <> 0 OR (2 & @@OPTIONS) = 2
    THROW 51001, N'Se requiere Auto-commit, sin transacciones explícitas ni implícitas.', 1;

-- Permite distinguir una base ausente de una base oculta por permisos.
IF COALESCE(HAS_PERMS_BY_NAME(NULL, NULL, N'VIEW ANY DATABASE'), 0) <> 1
    THROW 51002, N'Se requiere VIEW ANY DATABASE para comprobar la existencia de ShopCart.', 1;

IF NOT EXISTS (
    SELECT 1 FROM sys.fn_helpcollations()
    WHERE name = N'Latin1_General_100_CI_AI_SC'
)
    THROW 51003, N'La intercalación requerida no está disponible en esta instancia.', 1;

DECLARE @BaseCreada bit = 0;

BEGIN TRY
    IF DB_ID(N'ShopCart') IS NULL
    BEGIN
        IF COALESCE(HAS_PERMS_BY_NAME(NULL, NULL, N'CREATE ANY DATABASE'), 0) <> 1
           AND COALESCE(HAS_PERMS_BY_NAME(N'master', N'DATABASE', N'CREATE DATABASE'), 0) <> 1
            THROW 51004, N'No dispone de permisos para crear ShopCart.', 1;

        -- CREATE DATABASE ocupa su propio lote y no está en una transacción explícita.
        EXEC sys.sp_executesql
            N'CREATE DATABASE [ShopCart] COLLATE Latin1_General_100_CI_AI_SC;';
        SET @BaseCreada = 1;

        -- Solo se configura la base que acaba de crear esta ejecución.
        EXEC sys.sp_executesql N'ALTER DATABASE [ShopCart] SET RECOVERY SIMPLE;';
        PRINT N'Base ShopCart creada; recuperación SIMPLE configurada.';
    END;

    -- Una base preexistente incompatible nunca se corrige automáticamente.
    IF NOT EXISTS (
        SELECT 1
        FROM sys.databases
        WHERE name = N'ShopCart'
          AND collation_name = N'Latin1_General_100_CI_AI_SC'
          AND recovery_model_desc = N'SIMPLE'
          AND state_desc = N'ONLINE'
          AND user_access_desc = N'MULTI_USER'
          AND is_read_only = 0
          AND source_database_id IS NULL
    )
        THROW 51005, N'ShopCart no cumple las propiedades requeridas: intercalación, SIMPLE, ONLINE, MULTI_USER, lectura/escritura y ausencia de snapshot. Revisar manualmente.', 1;

    IF COALESCE(HAS_DBACCESS(N'ShopCart'), 0) <> 1
        THROW 51006, N'No se puede acceder a ShopCart.', 1;

    -- USE se limita a este lote interno; nunca se crea la tabla en master.
    EXEC sys.sp_executesql N'
        USE [ShopCart];
        IF DB_NAME() <> N''ShopCart''
            THROW 51007, N''Contexto de base de datos incorrecto.'', 1;

        -- CONTROL permite inspección completa y creación sin metadatos ocultos.
        IF COALESCE(HAS_PERMS_BY_NAME(DB_NAME(), N''DATABASE'', N''CONTROL''), 0) <> 1
            THROW 51008, N''El arranque requiere CONTROL sobre ShopCart.'', 1;

        IF OBJECT_ID(N''dbo.VersionesMigracion'') IS NOT NULL
           AND OBJECT_ID(N''dbo.VersionesMigracion'', N''U'') IS NULL
            THROW 51009, N''dbo.VersionesMigracion existe y no es una tabla de usuario.'', 1;

        IF OBJECT_ID(N''dbo.VersionesMigracion'', N''U'') IS NULL
        BEGIN
            CREATE TABLE [dbo].[VersionesMigracion]
            (
                [Version] int NOT NULL,
                [NombreArchivo] nvarchar(260) NOT NULL,
                [SHA256] binary(32) NOT NULL,
                [FechaAplicacionUTC] datetime2(7) NOT NULL
                    CONSTRAINT [DF_VersionesMigracion_FechaAplicacionUTC]
                    DEFAULT (SYSUTCDATETIME()),
                [Ejecutor] nvarchar(128) NOT NULL
                    CONSTRAINT [DF_VersionesMigracion_Ejecutor]
                    DEFAULT (ORIGINAL_LOGIN()),
                CONSTRAINT [PK_VersionesMigracion] PRIMARY KEY CLUSTERED ([Version])
            );
            PRINT N''Tabla dbo.VersionesMigracion creada.'';
        END;

        DECLARE @IDTabla int = OBJECT_ID(N''dbo.VersionesMigracion'', N''U'');

        -- Contrato exacto: cinco columnas, tipos nativos, tamaños y nulabilidad.
        IF EXISTS (
            SELECT 1
            FROM (VALUES
                (N''Version'', N''int'', 4, 10, 0),
                (N''NombreArchivo'', N''nvarchar'', 520, 0, 0),
                (N''SHA256'', N''binary'', 32, 0, 0),
                (N''FechaAplicacionUTC'', N''datetime2'', 8, 27, 7),
                (N''Ejecutor'', N''nvarchar'', 256, 0, 0)
            ) AS esperado(Nombre, Tipo, Longitud, PrecisionTipo, Escala)
            FULL JOIN (
                SELECT c.*, t.name AS Tipo
                FROM sys.columns AS c
                JOIN sys.types AS t ON t.user_type_id = c.user_type_id
                WHERE c.object_id = @IDTabla
            ) AS actual ON actual.name = esperado.Nombre
            WHERE esperado.Nombre IS NULL OR actual.name IS NULL
               OR actual.Tipo <> esperado.Tipo
               OR actual.user_type_id <> actual.system_type_id
               OR actual.max_length <> esperado.Longitud
               OR actual.precision <> esperado.PrecisionTipo
               OR actual.scale <> esperado.Escala
               OR actual.is_nullable <> 0 OR actual.is_identity <> 0
               OR actual.is_computed <> 0 OR actual.is_sparse <> 0
               OR actual.generated_always_type <> 0 OR actual.is_hidden <> 0
        )
            THROW 51010, N''Las columnas de VersionesMigracion no coinciden con el contrato de 001.'', 1;

        IF NOT EXISTS (
            SELECT 1
            FROM sys.indexes AS i
            JOIN sys.index_columns AS ic
              ON ic.object_id = i.object_id AND ic.index_id = i.index_id
            JOIN sys.columns AS c
              ON c.object_id = ic.object_id AND c.column_id = ic.column_id
            WHERE i.object_id = @IDTabla AND i.is_primary_key = 1
              AND i.type = 1 AND i.is_disabled = 0
              AND c.name = N''Version'' AND ic.key_ordinal = 1
              AND ic.is_descending_key = 0
              AND (SELECT COUNT(*) FROM sys.index_columns AS k
                   WHERE k.object_id = i.object_id AND k.index_id = i.index_id
                     AND k.key_ordinal > 0) = 1
        )
            THROW 51011, N''Se requiere una PK clustered ascendente únicamente sobre Version.'', 1;

        -- Se aceptan nombres distintos de DEFAULT, pero no expresiones distintas.
        IF (SELECT COUNT(*) FROM sys.default_constraints WHERE parent_object_id = @IDTabla) <> 2
           OR NOT EXISTS (
                SELECT 1 FROM sys.default_constraints AS d
                JOIN sys.columns AS c
                  ON c.object_id = d.parent_object_id AND c.column_id = d.parent_column_id
                WHERE d.parent_object_id = @IDTabla AND c.name = N''FechaAplicacionUTC''
                  AND LOWER(REPLACE(REPLACE(REPLACE(d.definition, N''('', N''''), N'')'', N''''), N'' '', N'''')) = N''sysutcdatetime''
           )
           OR NOT EXISTS (
                SELECT 1 FROM sys.default_constraints AS d
                JOIN sys.columns AS c
                  ON c.object_id = d.parent_object_id AND c.column_id = d.parent_column_id
                WHERE d.parent_object_id = @IDTabla AND c.name = N''Ejecutor''
                  AND LOWER(REPLACE(REPLACE(REPLACE(d.definition, N''('', N''''), N'')'', N''''), N'' '', N'''')) = N''original_login''
           )
            THROW 51012, N''Los DEFAULT de fecha UTC y ejecutor no coinciden con el contrato.'', 1;

        IF EXISTS (SELECT 1 FROM sys.tables WHERE object_id = @IDTabla
                   AND (temporal_type <> 0 OR is_memory_optimized = 1))
           OR EXISTS (SELECT 1 FROM sys.check_constraints WHERE parent_object_id = @IDTabla)
           OR EXISTS (SELECT 1 FROM sys.foreign_keys WHERE parent_object_id = @IDTabla)
           OR EXISTS (SELECT 1 FROM sys.triggers WHERE parent_id = @IDTabla)
           OR EXISTS (SELECT 1 FROM sys.indexes WHERE object_id = @IDTabla
                      AND is_unique = 1 AND is_primary_key = 0)
            THROW 51013, N''La tabla tiene características o restricciones adicionales; revisar manualmente.'', 1;

        PRINT N''Estructura de dbo.VersionesMigracion validada. Sin autorregistro de 001.'';
    ';

    PRINT N'Arranque 001 completado: base y tabla técnica verificadas.';
END TRY
BEGIN CATCH
    IF @BaseCreada = 1
        PRINT N'Fallo parcial: ShopCart fue creada por esta ejecución y se conserva. Revisar su estado antes de repetir; no se elimina ni se repara automáticamente.';
    ELSE
        PRINT N'Arranque no completado. Revisar el error y el estado actual antes de repetir.';
    THROW;
END CATCH;
