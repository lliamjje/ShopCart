/*
    005_CarritosCuponesBase.sql — Carritos y cupones, sin semillas ni SP de negocio.
    Ejecutar COMPLETO como un único lote, sin GO, conectado a ShopCart.
    Iniciar con Auto-commit, sin transacciones abiertas ni implícitas.
    No ejecutar selecciones parciales ni cambios administrativos concurrentes.

    Calcular SHA-256 del archivo FINAL con Get-FileHash y no editarlo después.
    Suministrar los 32 bytes con sp_set_session_context en la MISMA conexión de
    DataGrip, clave ShopCart.Migracion005.SHA256, como binary/varbinary.
    Limpiar el contexto al terminar. No incrustar la huella en este archivo.
    SQL valida tipo y longitud; el ejecutor comprueba su correspondencia con el archivo.

    Decisiones confirmadas: estado FUSIONADO; descuento MONTO_FIJO; sin IdCupon
    en Carritos. La selección, validación y reserva de cupones quedan para checkout.
    Solo se almacena el hash del token de invitado, nunca el token original.
    El abandono se deriva de última actividad: no existe estado ABANDONADO.
    Los DEFAULT de fechas solo inicializan; los futuros SP actualizarán actividad
    y fechas de modificación dentro de la misma transacción de negocio.

    Pendientes: autorización por propietario, fusión transaccional, transiciones,
    visibilidad del catálogo, disponibilidad al agregar/aumentar y en checkout.
    Agregar artículos no reserva stock ni congela precios.
    Cupones: vigencia [inicio, fin), mínimo sobre subtotal sin envío, elegibilidad,
    máximo uno por pedido, distribución proporcional determinista y total no negativo.
    ReservasCupon/UsosCupon y sus SP controlarán límites concurrentes y reservas
    de 15 minutos; desactivar impedirá nuevas reservas, respetando las vigentes.
*/
IF DB_NAME() <> N'ShopCart'
    THROW 55000, N'005 solo puede ejecutarse en la base ShopCart.', 1;

IF @@TRANCOUNT <> 0 OR (2 & @@OPTIONS) = 2
    THROW 55001, N'Inicie con Auto-commit y sin transacciones abiertas o implícitas.', 1;

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
    THROW 55002, N'Se requiere CONTROL sobre ShopCart para inspeccionar y crear el esquema.', 1;

IF NOT EXISTS (
    SELECT 1 FROM sys.databases
    WHERE database_id = DB_ID()
      AND collation_name = N'Latin1_General_100_CI_AI_SC'
      AND recovery_model_desc = N'SIMPLE'
      AND state_desc = N'ONLINE' AND user_access_desc = N'MULTI_USER'
      AND is_read_only = 0 AND source_database_id IS NULL
)
    THROW 55003, N'Las propiedades de ShopCart no coinciden con el arranque 001.', 1;

DECLARE @HuellaRecibida sql_variant = SESSION_CONTEXT(N'ShopCart.Migracion005.SHA256');
IF @HuellaRecibida IS NULL
   OR CONVERT(nvarchar(128), SQL_VARIANT_PROPERTY(@HuellaRecibida, 'BaseType')) NOT IN (N'binary', N'varbinary')
    THROW 55004, N'Suministre el SHA-256 real como valor binario en SESSION_CONTEXT antes de ejecutar 005.', 1;

DECLARE @SHA256 varbinary(max) = CONVERT(varbinary(max), @HuellaRecibida);
IF DATALENGTH(@SHA256) <> 32
    THROW 55005, N'La huella SHA-256 debe contener exactamente 32 bytes.', 1;

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
        THROW 55006, N'No se pudo obtener el bloqueo exclusivo de migraciones.', 1;

    DECLARE @IDVersiones int = OBJECT_ID(N'dbo.VersionesMigracion', N'U');
    IF @IDVersiones IS NULL
        THROW 55007, N'Falta la tabla técnica creada por 001. No se aplicará 005.', 1;

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
        THROW 55008, N'Las columnas de VersionesMigracion no cumplen el contrato de 001.', 1;

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
        THROW 55009, N'VersionesMigracion requiere la PK clustered de 001 sobre Version.', 1;

    IF EXISTS (SELECT 1 FROM sys.triggers WHERE parent_id = @IDVersiones)
       OR EXISTS (SELECT 1 FROM sys.tables WHERE object_id = @IDVersiones
                  AND (temporal_type <> 0 OR is_memory_optimized = 1))
        THROW 55010, N'VersionesMigracion tiene características inesperadas; revisar manualmente.', 1;

    -- Lote inferior: errores de compilación/resolución quedan dentro del TRY externo.
    EXEC sys.sp_executesql N'
        IF NOT EXISTS (
            SELECT 1 FROM dbo.VersionesMigracion WITH (UPDLOCK, HOLDLOCK)
            WHERE [Version] = 4 AND NombreArchivo = N''004_InventarioBase.sql''
        )
            THROW 55013, N''Debe estar registrada la migración 004_InventarioBase.sql antes de aplicar 005.'', 1;
        IF EXISTS (SELECT 1 FROM dbo.VersionesMigracion WITH (UPDLOCK, HOLDLOCK)
                   WHERE [Version] >= 5)
            THROW 55011, N''005 o una migración posterior ya está registrada. No se reaplica ni se certifica el esquema existente.'', 1;
    ';

    IF EXISTS (
        SELECT 1 FROM sys.objects AS o
        JOIN sys.schemas AS s ON s.schema_id = o.schema_id
        WHERE s.name = N'dbo'
          AND o.name IN (N'Carritos', N'DetallesCarrito', N'Cupones')
    )
        THROW 55012, N'Ya existe parte o todo el esquema de carritos/cupones sin registro compatible. Revisar manualmente; no se reparará.', 1;

    IF OBJECT_ID(N'dbo.Usuarios', N'U') IS NULL
       OR OBJECT_ID(N'dbo.VariantesProducto', N'U') IS NULL
       OR OBJECT_ID(N'dbo.Categorias', N'U') IS NULL
        THROW 55014, N'Faltan Usuarios, VariantesProducto o Categorias de las migraciones previas.', 1;

    -- Comprueba los tipos nativos de las columnas que serán destinos de FK.
    IF EXISTS (
        SELECT 1
        FROM (VALUES
            (N'dbo.Usuarios', N'IdUsuario', N'bigint'),
            (N'dbo.VariantesProducto', N'IdVariante', N'bigint'),
            (N'dbo.Categorias', N'IdCategoria', N'int')
        ) AS e(Tabla, Columna, Tipo)
        WHERE NOT EXISTS (
            SELECT 1 FROM sys.columns AS c
            WHERE c.object_id = OBJECT_ID(e.Tabla, N'U')
              AND c.name = e.Columna AND c.system_type_id = TYPE_ID(e.Tipo)
              AND c.user_type_id = c.system_type_id
              AND c.is_nullable = 0 AND c.is_computed = 0
        )
    )
        THROW 55015, N'Las columnas referenciadas no coinciden con los tipos requeridos.', 1;

    -- DDL constante en un lote inferior: sus errores alcanzan el CATCH externo.
    -- SQL Server verifica las claves candidatas de destino al crear las FK.
    EXEC sys.sp_executesql N'
        CREATE TABLE dbo.Carritos
        (
            IdCarrito bigint IDENTITY(1,1) NOT NULL,
            IdUsuario bigint NULL,
            TokenInvitadoHash binary(32) NULL,
            Estado varchar(20) NOT NULL,
            FechaCreacionUTC datetime2(7) NOT NULL
                CONSTRAINT DF_Carritos_FechaCreacionUTC DEFAULT (SYSUTCDATETIME()),
            FechaUltimaActividadUTC datetime2(7) NOT NULL
                CONSTRAINT DF_Carritos_FechaUltimaActividadUTC DEFAULT (SYSUTCDATETIME()),
            CONSTRAINT PK_Carritos PRIMARY KEY CLUSTERED (IdCarrito),
            CONSTRAINT FK_Carritos_Usuarios FOREIGN KEY (IdUsuario)
                REFERENCES dbo.Usuarios (IdUsuario)
                ON DELETE NO ACTION ON UPDATE NO ACTION,
            CONSTRAINT CK_Carritos_EstadoPermitido CHECK (
                Estado IN (''ACTIVO'', ''CONVERTIDO'', ''FUSIONADO'')
            ),
            CONSTRAINT CK_Carritos_PropietarioExclusivo CHECK (
                (IdUsuario IS NOT NULL AND TokenInvitadoHash IS NULL)
                OR (IdUsuario IS NULL AND TokenInvitadoHash IS NOT NULL)
            )
        );
        CREATE UNIQUE NONCLUSTERED INDEX UX_Carritos_UsuarioActivo
            ON dbo.Carritos (IdUsuario)
            WHERE IdUsuario IS NOT NULL AND Estado = ''ACTIVO'';
        CREATE UNIQUE NONCLUSTERED INDEX UX_Carritos_InvitadoActivo
            ON dbo.Carritos (TokenInvitadoHash)
            WHERE TokenInvitadoHash IS NOT NULL AND Estado = ''ACTIVO'';
        -- El índice filtrado no cubre el historial completo ni toda la FK de usuario.
        CREATE NONCLUSTERED INDEX IX_Carritos_Usuario_Actividad
            ON dbo.Carritos (IdUsuario, FechaUltimaActividadUTC);
        -- Permite localizar activos anteriores al umbral configurable de abandono.
        CREATE NONCLUSTERED INDEX IX_Carritos_Activos_UltimaActividad
            ON dbo.Carritos (FechaUltimaActividadUTC)
            WHERE Estado = ''ACTIVO'';

        CREATE TABLE dbo.DetallesCarrito
        (
            IdDetalleCarrito bigint IDENTITY(1,1) NOT NULL,
            IdCarrito bigint NOT NULL,
            IdVariante bigint NOT NULL,
            Cantidad int NOT NULL,
            FechaCreacionUTC datetime2(7) NOT NULL
                CONSTRAINT DF_DetallesCarrito_FechaCreacionUTC DEFAULT (SYSUTCDATETIME()),
            FechaActualizacionUTC datetime2(7) NOT NULL
                CONSTRAINT DF_DetallesCarrito_FechaActualizacionUTC DEFAULT (SYSUTCDATETIME()),
            CONSTRAINT PK_DetallesCarrito PRIMARY KEY CLUSTERED (IdDetalleCarrito),
            CONSTRAINT UQ_DetallesCarrito_Carrito_Variante
                UNIQUE NONCLUSTERED (IdCarrito, IdVariante),
            CONSTRAINT FK_DetallesCarrito_Carritos FOREIGN KEY (IdCarrito)
                REFERENCES dbo.Carritos (IdCarrito)
                ON DELETE NO ACTION ON UPDATE NO ACTION,
            CONSTRAINT FK_DetallesCarrito_VariantesProducto FOREIGN KEY (IdVariante)
                REFERENCES dbo.VariantesProducto (IdVariante)
                ON DELETE NO ACTION ON UPDATE NO ACTION,
            CONSTRAINT CK_DetallesCarrito_CantidadPositiva CHECK (Cantidad > 0)
        );
        -- La UNIQUE cubre búsquedas y FK por IdCarrito; solo falta este otro prefijo.
        CREATE NONCLUSTERED INDEX IX_DetallesCarrito_IdVariante
            ON dbo.DetallesCarrito (IdVariante);

        CREATE TABLE dbo.Cupones
        (
            IdCupon bigint IDENTITY(1,1) NOT NULL,
            Codigo nvarchar(50) NOT NULL,
            Descripcion nvarchar(250) NULL,
            TipoDescuento varchar(15) NOT NULL,
            ValorDescuento decimal(19,4) NOT NULL,
            MontoMinimoCompra decimal(19,4) NOT NULL
                CONSTRAINT DF_Cupones_MontoMinimoCompra DEFAULT (0),
            IdCategoria int NULL,
            LimiteUsosTotal int NULL,
            LimiteUsosPorUsuario int NULL,
            FechaInicioUTC datetime2(7) NOT NULL,
            FechaFinUTC datetime2(7) NOT NULL,
            EstaActivo bit NOT NULL CONSTRAINT DF_Cupones_EstaActivo DEFAULT (1),
            FechaCreacionUTC datetime2(7) NOT NULL
                CONSTRAINT DF_Cupones_FechaCreacionUTC DEFAULT (SYSUTCDATETIME()),
            FechaActualizacionUTC datetime2(7) NOT NULL
                CONSTRAINT DF_Cupones_FechaActualizacionUTC DEFAULT (SYSUTCDATETIME()),
            CONSTRAINT PK_Cupones PRIMARY KEY CLUSTERED (IdCupon),
            CONSTRAINT UQ_Cupones_Codigo UNIQUE NONCLUSTERED (Codigo),
            CONSTRAINT FK_Cupones_Categorias FOREIGN KEY (IdCategoria)
                REFERENCES dbo.Categorias (IdCategoria)
                ON DELETE NO ACTION ON UPDATE NO ACTION,
            CONSTRAINT CK_Cupones_TipoDescuento CHECK (
                TipoDescuento IN (''PORCENTAJE'', ''MONTO_FIJO'')
            ),
            CONSTRAINT CK_Cupones_ValorDescuento CHECK (
                (TipoDescuento = ''PORCENTAJE'' AND ValorDescuento > 0 AND ValorDescuento <= 100)
                OR (TipoDescuento = ''MONTO_FIJO'' AND ValorDescuento > 0)
            ),
            CONSTRAINT CK_Cupones_MontoMinimoNoNegativo CHECK (MontoMinimoCompra >= 0),
            CONSTRAINT CK_Cupones_LimiteTotalPositivo CHECK (
                LimiteUsosTotal IS NULL OR LimiteUsosTotal > 0
            ),
            CONSTRAINT CK_Cupones_LimiteUsuarioPositivo CHECK (
                LimiteUsosPorUsuario IS NULL OR LimiteUsosPorUsuario > 0
            ),
            CONSTRAINT CK_Cupones_IntervaloVigencia CHECK (FechaFinUTC > FechaInicioUTC),
            -- DATALENGTH detecta espacios exteriores que la comparación SQL ignora.
            -- Se recortan espacios normales U+0020, igual que en catálogo.
            CONSTRAINT CK_Cupones_CodigoValido CHECK (
                LEN(LTRIM(RTRIM(Codigo))) > 0
                AND DATALENGTH(Codigo) = DATALENGTH(LTRIM(RTRIM(Codigo)))
            )
        );
        CREATE NONCLUSTERED INDEX IX_Cupones_IdCategoria ON dbo.Cupones (IdCategoria);
    ';

    -- Registro técnico y DDL se confirman o revierten juntos.
    EXEC sys.sp_executesql N'
        INSERT INTO dbo.VersionesMigracion
            ([Version], NombreArchivo, SHA256, FechaAplicacionUTC, Ejecutor)
        VALUES
            (5, N''005_CarritosCuponesBase.sql'', @Huella, SYSUTCDATETIME(), ORIGINAL_LOGIN());
    ', N'@Huella varbinary(32)', @Huella = @SHA256;

    COMMIT TRANSACTION;
    PRINT N'Migración 005 completada: tres tablas y registro técnico confirmados.';
END TRY
BEGIN CATCH
    IF XACT_STATE() <> 0
        ROLLBACK TRANSACTION;
    THROW;
END CATCH;
