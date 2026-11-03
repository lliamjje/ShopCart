/*
    006_MetodosEnvio.sql — Métodos de envío, sin semillas ni SP de negocio.
    Ejecutar COMPLETO como un único lote, sin GO, conectado a ShopCart.
    Iniciar con Auto-commit, sin transacciones abiertas ni implícitas.
    No ejecutar selecciones parciales ni cambios administrativos concurrentes.

    Calcular SHA-256 del archivo FINAL con Get-FileHash y no editarlo después.
    Suministrar los 32 bytes con sp_set_session_context en la MISMA conexión de
    DataGrip, clave ShopCart.Migracion006.SHA256, como binary/varbinary.
    Limpiar el contexto al terminar. No incrustar la huella en este archivo.
    SQL valida tipo y longitud; el ejecutor comprueba su correspondencia con el archivo.

    Decisiones confirmadas: Costo decimal(19,4), tarifa fija GTQ por pedido;
    nombres repetidos permitidos y Codigo como único identificador comercial.
    Se permite costo cero. No se crean relaciones con pedidos todavía.
    Solo se crean los índices asociados a PK y UNIQUE; no hay otro índice justificado.

    Los futuros SP actualizarán FechaActualizacionUTC y validarán que el método
    esté activo al seleccionarlo en un nuevo checkout. El DEFAULT solo inicializa.
    Checkout/pedidos conservarán snapshots de código, nombre y costo, sin alterar
    importes históricos ante cambios de tarifa. No eliminar métodos automáticamente
    al existir pedidos relacionados; definir esas FK sin eliminación en cascada.
*/
IF DB_NAME() <> N'ShopCart'
    THROW 56000, N'006 solo puede ejecutarse en la base ShopCart.', 1;

IF @@TRANCOUNT <> 0 OR (2 & @@OPTIONS) = 2
    THROW 56001, N'Inicie con Auto-commit y sin transacciones abiertas o implícitas.', 1;

SET NOCOUNT ON;
SET XACT_ABORT ON;
-- Opciones de sesión consistentes con las migraciones anteriores.
SET ANSI_NULLS ON;
SET ANSI_PADDING ON;
SET ANSI_WARNINGS ON;
SET ARITHABORT ON;
SET CONCAT_NULL_YIELDS_NULL ON;
SET QUOTED_IDENTIFIER ON;
SET NUMERIC_ROUNDABORT OFF;

IF COALESCE(HAS_PERMS_BY_NAME(DB_NAME(), N'DATABASE', N'CONTROL'), 0) <> 1
    THROW 56002, N'Se requiere CONTROL sobre ShopCart para inspeccionar y crear el esquema.', 1;

IF NOT EXISTS (
    SELECT 1 FROM sys.databases
    WHERE database_id = DB_ID()
      AND collation_name = N'Latin1_General_100_CI_AI_SC'
      AND recovery_model_desc = N'SIMPLE'
      AND state_desc = N'ONLINE' AND user_access_desc = N'MULTI_USER'
      AND is_read_only = 0 AND source_database_id IS NULL
)
    THROW 56003, N'Las propiedades de ShopCart no coinciden con el arranque 001.', 1;

DECLARE @HuellaRecibida sql_variant = SESSION_CONTEXT(N'ShopCart.Migracion006.SHA256');
IF @HuellaRecibida IS NULL
   OR CONVERT(nvarchar(128), SQL_VARIANT_PROPERTY(@HuellaRecibida, 'BaseType')) NOT IN (N'binary', N'varbinary')
    THROW 56004, N'Suministre el SHA-256 real como valor binario en SESSION_CONTEXT antes de ejecutar 006.', 1;

DECLARE @SHA256 varbinary(max) = CONVERT(varbinary(max), @HuellaRecibida);
IF DATALENGTH(@SHA256) <> 32
    THROW 56005, N'La huella SHA-256 debe contener exactamente 32 bytes.', 1;

BEGIN TRY
    BEGIN TRANSACTION;

    -- Serializa ejecuciones que respeten este mismo recurso administrativo.
    DECLARE @ResultadoBloqueo int;
    EXEC @ResultadoBloqueo = sys.sp_getapplock
        @Resource = N'ShopCart.Migraciones',
        @LockMode = N'Exclusive',
        @LockOwner = N'Transaction',
        @LockTimeout = 0;
    IF @ResultadoBloqueo < 0
        THROW 56006, N'No se pudo obtener el bloqueo exclusivo de migraciones.', 1;

    DECLARE @IDVersiones int = OBJECT_ID(N'dbo.VersionesMigracion', N'U');
    IF @IDVersiones IS NULL
        THROW 56007, N'Falta la tabla técnica creada por 001. No se aplicará 006.', 1;

    -- Verifica el contrato utilizado para registrar la migración, no solo el nombre.
    IF EXISTS (
        SELECT 1
        FROM (VALUES
            (N'Version', N'int', 4, 10, 0),
            (N'NombreArchivo', N'nvarchar', 520, 0, 0),
            (N'SHA256', N'binary', 32, 0, 0),
            (N'FechaAplicacionUTC', N'datetime2', 8, 27, 7),
            (N'Ejecutor', N'nvarchar', 256, 0, 0)
        ) AS e(Nombre, Tipo, Longitud, PrecisionTipo, Escala)
        FULL JOIN (
            SELECT c.*, t.name AS Tipo
            FROM sys.columns AS c
            JOIN sys.types AS t ON t.user_type_id = c.user_type_id
            WHERE c.object_id = @IDVersiones
        ) AS a ON a.name = e.Nombre
        WHERE e.Nombre IS NULL OR a.name IS NULL OR a.Tipo <> e.Tipo
           OR a.user_type_id <> a.system_type_id OR a.max_length <> e.Longitud
           OR a.precision <> e.PrecisionTipo OR a.scale <> e.Escala
           OR a.is_nullable <> 0 OR a.is_identity <> 0 OR a.is_computed <> 0
           OR a.is_sparse <> 0 OR a.is_hidden <> 0 OR a.generated_always_type <> 0
    )
        THROW 56008, N'Las columnas de VersionesMigracion no cumplen el contrato de 001.', 1;

    IF NOT EXISTS (
        SELECT 1 FROM sys.indexes AS i
        JOIN sys.index_columns AS ic
          ON ic.object_id = i.object_id AND ic.index_id = i.index_id
        JOIN sys.columns AS c
          ON c.object_id = ic.object_id AND c.column_id = ic.column_id
        WHERE i.object_id = @IDVersiones AND i.is_primary_key = 1
          AND i.type = 1 AND i.is_disabled = 0
          AND c.name = N'Version' AND ic.key_ordinal = 1
          AND ic.is_descending_key = 0
          AND (SELECT COUNT(*) FROM sys.index_columns AS k
               WHERE k.object_id = i.object_id AND k.index_id = i.index_id
                 AND k.key_ordinal > 0) = 1
    )
        THROW 56009, N'VersionesMigracion requiere la PK clustered de 001 sobre Version.', 1;

    IF EXISTS (SELECT 1 FROM sys.triggers WHERE parent_id = @IDVersiones)
       OR EXISTS (SELECT 1 FROM sys.tables WHERE object_id = @IDVersiones
                  AND (temporal_type <> 0 OR is_memory_optimized = 1))
        THROW 56010, N'VersionesMigracion tiene características inesperadas; revisar manualmente.', 1;

    -- Lote inferior: errores de compilación/resolución quedan dentro del TRY externo.
    EXEC sys.sp_executesql N'
        IF NOT EXISTS (
            SELECT 1 FROM dbo.VersionesMigracion WITH (UPDLOCK, HOLDLOCK)
            WHERE [Version] = 5 AND NombreArchivo = N''005_CarritosCuponesBase.sql''
        )
            THROW 56013, N''Debe estar registrada la migración 005_CarritosCuponesBase.sql antes de aplicar 006.'', 1;
        IF EXISTS (SELECT 1 FROM dbo.VersionesMigracion WITH (UPDLOCK, HOLDLOCK)
                   WHERE [Version] >= 6)
            THROW 56011, N''006 o una migración posterior ya está registrada. No se reaplica ni se certifica el esquema existente.'', 1;
    ';

    IF EXISTS (
        SELECT 1 FROM sys.objects AS o
        JOIN sys.schemas AS s ON s.schema_id = o.schema_id
        WHERE s.name = N'dbo'
          AND o.name IN (N'MetodosEnvio')
    )
        THROW 56012, N'Ya existe un objeto dbo.MetodosEnvio sin registro compatible. Revisar manualmente; no se reparará.', 1;

    -- DDL constante en un lote inferior: sus errores alcanzan el CATCH externo.
    EXEC sys.sp_executesql N'
        CREATE TABLE dbo.MetodosEnvio
        (
            IdMetodoEnvio int IDENTITY(1,1) NOT NULL,
            Codigo varchar(30) NOT NULL,
            Nombre nvarchar(100) NOT NULL,
            Descripcion nvarchar(500) NULL,
            Costo decimal(19,4) NOT NULL,
            EstaActivo bit NOT NULL
                CONSTRAINT DF_MetodosEnvio_EstaActivo DEFAULT (1),
            OrdenVisualizacion int NOT NULL
                CONSTRAINT DF_MetodosEnvio_OrdenVisualizacion DEFAULT (0),
            FechaCreacionUTC datetime2(7) NOT NULL
                CONSTRAINT DF_MetodosEnvio_FechaCreacionUTC DEFAULT (SYSUTCDATETIME()),
            FechaActualizacionUTC datetime2(7) NOT NULL
                CONSTRAINT DF_MetodosEnvio_FechaActualizacionUTC DEFAULT (SYSUTCDATETIME()),
            CONSTRAINT PK_MetodosEnvio PRIMARY KEY CLUSTERED (IdMetodoEnvio),
            CONSTRAINT UQ_MetodosEnvio_Codigo UNIQUE NONCLUSTERED (Codigo),
            CONSTRAINT CK_MetodosEnvio_CostoNoNegativo CHECK (Costo >= 0),
            CONSTRAINT CK_MetodosEnvio_OrdenNoNegativo CHECK (OrdenVisualizacion >= 0),
            -- DATALENGTH detecta espacios exteriores que la comparación SQL ignora.
            -- Se recortan espacios normales U+0020, igual que en cupones y catálogo.
            CONSTRAINT CK_MetodosEnvio_CodigoValido CHECK (
                LEN(LTRIM(RTRIM(Codigo))) > 0
                AND DATALENGTH(Codigo) = DATALENGTH(LTRIM(RTRIM(Codigo)))
            )
        );
    ';

    -- Registro técnico y DDL se confirman o revierten juntos.
    EXEC sys.sp_executesql N'
        INSERT INTO dbo.VersionesMigracion
            ([Version], NombreArchivo, SHA256, FechaAplicacionUTC, Ejecutor)
        VALUES
            (6, N''006_MetodosEnvio.sql'', @Huella, SYSUTCDATETIME(), ORIGINAL_LOGIN());
    ', N'@Huella varbinary(32)', @Huella = @SHA256;

    COMMIT TRANSACTION;
    PRINT N'Migración 006 completada: tabla MetodosEnvio y registro técnico confirmados.';
END TRY
BEGIN CATCH
    IF XACT_STATE() <> 0
        ROLLBACK TRANSACTION;
    THROW;
END CATCH;
