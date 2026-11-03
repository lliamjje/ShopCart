/*
    003_Catalogo.sql — Catálogo, sin datos semilla, inventario ni SP de negocio.
    Ejecutar COMPLETO como un único lote, sin GO, conectado a ShopCart.
    Iniciar en Auto-commit y sin transacciones abiertas; el script controla la suya.
    No ejecutar selecciones parciales ni cambios administrativos concurrentes.

    Calcular SHA-256 de los bytes del archivo FINAL con Get-FileHash. Sin editar
    después, suministrar los 32 bytes con sp_set_session_context en la MISMA conexión
    de DataGrip, clave ShopCart.Migracion003.SHA256, como binary/varbinary.
    No incrustar la huella en el archivo. Limpiar el contexto al terminar.
    El ejecutor debe comprobar la correspondencia archivo/huella; SQL valida formato.

    Decisiones confirmadas: Precio decimal(19,4); imágenes solo por IdProducto.
    Talla y color: recortar espacios U+0020; NULL y cadena vacía son ausencia.
    Se reserva <NULL> (también sus equivalentes CI_AI) para esa ausencia.
    Rutas: relativas, canónicas, con /; sin segmentos . o .. ni codificación URL.
    UNIQUE NONCLUSTERED (IdProducto, RutaImagen): máximo 8 + 1000 = 1008 bytes,
    inferior al límite de 1700 bytes de SQL Server 2025 para claves no agrupadas.
    La API futura debe comprobar además que la ruta resuelva dentro del directorio
    local permitido; CHECK no inspecciona archivos, enlaces ni permisos del sistema.
    DEFAULT de actualización solo inicializa: los futuros SP actualizarán la fecha.
    Activación válida de productos y auditoría se implementarán en SP posteriores.
*/
IF DB_NAME() <> N'ShopCart'
    THROW 53000, N'003 solo puede ejecutarse en la base ShopCart.', 1;

IF @@TRANCOUNT <> 0 OR (2 & @@OPTIONS) = 2
    THROW 53001, N'Inicie con Auto-commit y sin transacciones abiertas o implícitas.', 1;

SET NOCOUNT ON;
SET XACT_ABORT ON;
-- Opciones requeridas por los índices filtrados.
SET ANSI_NULLS ON;
SET ANSI_PADDING ON;
SET ANSI_WARNINGS ON;
SET ARITHABORT ON;
SET CONCAT_NULL_YIELDS_NULL ON;
SET QUOTED_IDENTIFIER ON;
SET NUMERIC_ROUNDABORT OFF;

IF COALESCE(HAS_PERMS_BY_NAME(DB_NAME(), N'DATABASE', N'CONTROL'), 0) <> 1
    THROW 53002, N'Se requiere CONTROL sobre ShopCart para inspeccionar y crear el esquema.', 1;

IF NOT EXISTS (
    SELECT 1 FROM sys.databases
    WHERE database_id = DB_ID()
      AND collation_name = N'Latin1_General_100_CI_AI_SC'
      AND recovery_model_desc = N'SIMPLE'
      AND state_desc = N'ONLINE' AND user_access_desc = N'MULTI_USER'
      AND is_read_only = 0 AND source_database_id IS NULL
)
    THROW 53003, N'Las propiedades de ShopCart no coinciden con el arranque 001.', 1;

DECLARE @HuellaRecibida sql_variant = SESSION_CONTEXT(N'ShopCart.Migracion003.SHA256');
IF @HuellaRecibida IS NULL
   OR CONVERT(nvarchar(128), SQL_VARIANT_PROPERTY(@HuellaRecibida, 'BaseType')) NOT IN (N'binary', N'varbinary')
    THROW 53004, N'Suministre el SHA-256 real como valor binario en SESSION_CONTEXT antes de ejecutar 003.', 1;

DECLARE @SHA256 varbinary(max) = CONVERT(varbinary(max), @HuellaRecibida);
IF DATALENGTH(@SHA256) <> 32
    THROW 53005, N'La huella SHA-256 debe contener exactamente 32 bytes.', 1;

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
        THROW 53006, N'No se pudo obtener el bloqueo exclusivo de migraciones.', 1;

    DECLARE @IDVersiones int = OBJECT_ID(N'dbo.VersionesMigracion', N'U');
    IF @IDVersiones IS NULL
        THROW 53007, N'Falta la tabla técnica creada por 001. No se aplicará 003.', 1;

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
        THROW 53008, N'Las columnas de VersionesMigracion no cumplen el contrato de 001.', 1;

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
        THROW 53009, N'VersionesMigracion requiere la PK clustered de 001 sobre Version.', 1;

    IF EXISTS (SELECT 1 FROM sys.triggers WHERE parent_id = @IDVersiones)
       OR EXISTS (SELECT 1 FROM sys.tables WHERE object_id = @IDVersiones
                  AND (temporal_type <> 0 OR is_memory_optimized = 1))
        THROW 53010, N'VersionesMigracion tiene características inesperadas; revisar manualmente.', 1;

    -- Lote inferior: errores de compilación/resolución quedan dentro del TRY externo.
    EXEC sys.sp_executesql N'
        IF NOT EXISTS (
            SELECT 1 FROM dbo.VersionesMigracion WITH (UPDLOCK, HOLDLOCK)
            WHERE [Version] = 2 AND NombreArchivo = N''002_Seguridad.sql''
        )
            THROW 53013, N''Debe estar registrada la migración 002_Seguridad.sql antes de aplicar 003.'', 1;
        IF EXISTS (SELECT 1 FROM dbo.VersionesMigracion WITH (UPDLOCK, HOLDLOCK)
                   WHERE [Version] >= 3)
            THROW 53011, N''003 o una migración posterior ya está registrada. No se reaplica ni se certifica el esquema existente.'', 1;
    ';

    IF EXISTS (
        SELECT 1 FROM sys.objects AS o
        JOIN sys.schemas AS s ON s.schema_id = o.schema_id
        WHERE s.name = N'dbo'
          AND o.name IN (N'Categorias', N'Productos', N'VariantesProducto', N'ImagenesProducto')
    )
        THROW 53012, N'Ya existe parte o todo el esquema de catálogo sin registro compatible. Revisar manualmente; no se reparará.', 1;

    -- DDL constante en un lote inferior: sus errores alcanzan el CATCH externo.
    EXEC sys.sp_executesql N'
        CREATE TABLE dbo.Categorias
        (
            IdCategoria int IDENTITY(1,1) NOT NULL,
            Nombre nvarchar(100) NOT NULL,
            Descripcion nvarchar(500) NULL,
            EstaActiva bit NOT NULL CONSTRAINT DF_Categorias_EstaActiva DEFAULT (1),
            FechaCreacionUTC datetime2(7) NOT NULL
                CONSTRAINT DF_Categorias_FechaCreacionUTC DEFAULT (SYSUTCDATETIME()),
            FechaActualizacionUTC datetime2(7) NOT NULL
                CONSTRAINT DF_Categorias_FechaActualizacionUTC DEFAULT (SYSUTCDATETIME()),
            CONSTRAINT PK_Categorias PRIMARY KEY CLUSTERED (IdCategoria),
            CONSTRAINT UQ_Categorias_Nombre UNIQUE NONCLUSTERED (Nombre)
        );

        CREATE TABLE dbo.Productos
        (
            IdProducto bigint IDENTITY(1,1) NOT NULL,
            IdCategoria int NOT NULL,
            Nombre nvarchar(200) NOT NULL,
            Descripcion nvarchar(max) NULL,
            EstaActivo bit NOT NULL CONSTRAINT DF_Productos_EstaActivo DEFAULT (0),
            FechaCreacionUTC datetime2(7) NOT NULL
                CONSTRAINT DF_Productos_FechaCreacionUTC DEFAULT (SYSUTCDATETIME()),
            FechaActualizacionUTC datetime2(7) NOT NULL
                CONSTRAINT DF_Productos_FechaActualizacionUTC DEFAULT (SYSUTCDATETIME()),
            CONSTRAINT PK_Productos PRIMARY KEY CLUSTERED (IdProducto),
            CONSTRAINT FK_Productos_Categorias FOREIGN KEY (IdCategoria)
                REFERENCES dbo.Categorias (IdCategoria)
                ON DELETE NO ACTION ON UPDATE NO ACTION
        );
        CREATE NONCLUSTERED INDEX IX_Productos_IdCategoria ON dbo.Productos (IdCategoria);

        CREATE TABLE dbo.VariantesProducto
        (
            IdVariante bigint IDENTITY(1,1) NOT NULL,
            IdProducto bigint NOT NULL,
            SKU nvarchar(64) NOT NULL,
            Talla nvarchar(50) NULL,
            Color nvarchar(50) NULL,
            TallaNormalizada AS
                ISNULL(NULLIF(LTRIM(RTRIM(Talla)), N''''), N''<NULL>'') PERSISTED,
            ColorNormalizado AS
                ISNULL(NULLIF(LTRIM(RTRIM(Color)), N''''), N''<NULL>'') PERSISTED,
            Precio decimal(19,4) NOT NULL,
            EstaActiva bit NOT NULL CONSTRAINT DF_VariantesProducto_EstaActiva DEFAULT (1),
            FechaCreacionUTC datetime2(7) NOT NULL
                CONSTRAINT DF_VariantesProducto_FechaCreacionUTC DEFAULT (SYSUTCDATETIME()),
            FechaActualizacionUTC datetime2(7) NOT NULL
                CONSTRAINT DF_VariantesProducto_FechaActualizacionUTC DEFAULT (SYSUTCDATETIME()),
            CONSTRAINT PK_VariantesProducto PRIMARY KEY CLUSTERED (IdVariante),
            CONSTRAINT FK_VariantesProducto_Productos FOREIGN KEY (IdProducto)
                REFERENCES dbo.Productos (IdProducto)
                ON DELETE NO ACTION ON UPDATE NO ACTION,
            CONSTRAINT UQ_VariantesProducto_SKU UNIQUE NONCLUSTERED (SKU),
            -- Incluye variantes inactivas; el prefijo IdProducto cubre su FK y listado.
            CONSTRAINT UQ_VariantesProducto_Producto_Talla_Color
                UNIQUE NONCLUSTERED (IdProducto, TallaNormalizada, ColorNormalizado),
            CONSTRAINT CK_VariantesProducto_PrecioPositivo CHECK (Precio > 0),
            CONSTRAINT CK_VariantesProducto_SKUValido CHECK (
                LEN(LTRIM(RTRIM(SKU))) > 0
                AND DATALENGTH(SKU) = DATALENGTH(LTRIM(RTRIM(SKU)))
            ),
            CONSTRAINT CK_VariantesProducto_TallaNoReservada CHECK (
                Talla IS NULL OR LTRIM(RTRIM(Talla)) <> N''<NULL>''
            ),
            CONSTRAINT CK_VariantesProducto_ColorNoReservado CHECK (
                Color IS NULL OR LTRIM(RTRIM(Color)) <> N''<NULL>''
            )
        );

        CREATE TABLE dbo.ImagenesProducto
        (
            IdImagen bigint IDENTITY(1,1) NOT NULL,
            IdProducto bigint NOT NULL,
            RutaImagen nvarchar(500) NOT NULL,
            TextoAlternativo nvarchar(250) NULL,
            OrdenVisualizacion int NOT NULL
                CONSTRAINT DF_ImagenesProducto_OrdenVisualizacion DEFAULT (0),
            EsPrincipal bit NOT NULL CONSTRAINT DF_ImagenesProducto_EsPrincipal DEFAULT (0),
            EstaActiva bit NOT NULL CONSTRAINT DF_ImagenesProducto_EstaActiva DEFAULT (1),
            FechaCreacionUTC datetime2(7) NOT NULL
                CONSTRAINT DF_ImagenesProducto_FechaCreacionUTC DEFAULT (SYSUTCDATETIME()),
            FechaActualizacionUTC datetime2(7) NOT NULL
                CONSTRAINT DF_ImagenesProducto_FechaActualizacionUTC DEFAULT (SYSUTCDATETIME()),
            CONSTRAINT PK_ImagenesProducto PRIMARY KEY CLUSTERED (IdImagen),
            CONSTRAINT FK_ImagenesProducto_Productos FOREIGN KEY (IdProducto)
                REFERENCES dbo.Productos (IdProducto)
                ON DELETE NO ACTION ON UPDATE NO ACTION,
            CONSTRAINT UQ_ImagenesProducto_Producto_Ruta
                UNIQUE NONCLUSTERED (IdProducto, RutaImagen),
            CONSTRAINT CK_ImagenesProducto_OrdenNoNegativo CHECK (OrdenVisualizacion >= 0),
            CONSTRAINT CK_ImagenesProducto_RutaRelativa CHECK (
                LEN(LTRIM(RTRIM(RutaImagen))) > 0
                AND DATALENGTH(RutaImagen) = DATALENGTH(LTRIM(RTRIM(RutaImagen)))
                AND LEFT(RutaImagen, 1) <> N''/''
                AND RIGHT(RutaImagen, 1) <> N''/''
                AND CHARINDEX(N''\'', RutaImagen) = 0
                AND CHARINDEX(N'':'', RutaImagen) = 0
                AND CHARINDEX(N''%'', RutaImagen) = 0
                AND CHARINDEX(N''?'', RutaImagen) = 0
                AND CHARINDEX(N''#'', RutaImagen) = 0
                AND CHARINDEX(NCHAR(9), RutaImagen) = 0
                AND CHARINDEX(NCHAR(10), RutaImagen) = 0
                AND CHARINDEX(NCHAR(13), RutaImagen) = 0
                AND CHARINDEX(N''//'', RutaImagen) = 0
                AND CHARINDEX(N''/./'', N''/'' + RutaImagen + N''/'') = 0
                AND CHARINDEX(N''/../'', N''/'' + RutaImagen + N''/'') = 0
            )
        );
        CREATE UNIQUE NONCLUSTERED INDEX UX_ImagenesProducto_PrincipalActiva
            ON dbo.ImagenesProducto (IdProducto)
            WHERE EsPrincipal = 1 AND EstaActiva = 1;
        -- Listado de imágenes de un producto en orden estable, con filtro por actividad.
        CREATE NONCLUSTERED INDEX IX_ImagenesProducto_Producto_Orden
            ON dbo.ImagenesProducto (IdProducto, OrdenVisualizacion, IdImagen)
            INCLUDE (EstaActiva, EsPrincipal);
    ';

    EXEC sys.sp_executesql N'
        INSERT INTO dbo.VersionesMigracion
            ([Version], NombreArchivo, SHA256, FechaAplicacionUTC, Ejecutor)
        VALUES
            (3, N''003_Catalogo.sql'', @Huella, SYSUTCDATETIME(), ORIGINAL_LOGIN());
    ', N'@Huella varbinary(32)', @Huella = @SHA256;

    COMMIT TRANSACTION;
    PRINT N'Migración 003 completada: cuatro tablas y registro técnico confirmados.';
END TRY
BEGIN CATCH
    IF XACT_STATE() <> 0
        ROLLBACK TRANSACTION;
    THROW;
END CATCH;
