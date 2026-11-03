/*
    007_Checkout.sql — Checkouts y detalles, sin semillas ni SP de negocio.
    Ejecutar COMPLETO como un único lote, sin GO, conectado a ShopCart.
    Iniciar con Auto-commit, sin transacciones abiertas ni implícitas.
    No ejecutar selecciones parciales ni cambios administrativos concurrentes.

    Calcular SHA-256 del archivo FINAL con Get-FileHash y no editarlo después.
    Suministrar los 32 bytes con sp_set_session_context en la MISMA conexión de
    DataGrip, clave ShopCart.Migracion007.SHA256, como binary/varbinary.
    Limpiar el contexto al terminar. No incrustar la huella en este archivo.
    SQL valida formato; el ejecutor comprueba la correspondencia archivo/huella.

    Decisiones confirmadas: Checkouts/IdCheckout, estado INICIADO e invitados con
    IdUsuario NULL. La identidad segura del invitado se verificará mediante el carrito.
    No se agregan snapshots no aprobados: dirección, envío, categoría y desglose
    fiscal histórico se incorporarán en 009 o en otra migración estructural antes
    de implementar los SP dependientes. Deben preservarse funcionalmente.
    Los precios incluyen IVA 12 %; no se suma impuesto adicional al total.

    SKU nvarchar(64) y NombreProducto nvarchar(200) coinciden con catálogo.
    DescripcionVariante nvarchar(250) permite talla/color de 50 cada uno y etiquetas.
    Su composición y longitud final deberán validarse en los futuros SP.
    El índice único de activos usa IN, admitido por los filtros de CREATE INDEX.
    Un checkout vencido sigue ocupando el índice hasta cambiar su estado; los SP
    deberán expirar/cancelar el anterior dentro de la transacción antes de crear otro.

    Pendientes para SP: carrito activo, propiedad y permisos de usuario/invitado,
    pertenencia de dirección, captura de entrega de invitado, idempotencia permanente
    con comparación del contenido de la solicitud, importes y suma de líneas,
    snapshots confirmados inmutables, fechas, vencimiento de 15 minutos y transiciones.
    Coordinar reservas de inventario/cupón en 008 y pedidos/pagos simulados en 009.
    Las FK simples no prueban pertenencia entre usuario, carrito y dirección.
    El DEFAULT de actualización solo inicializa; no renueva ni extiende el checkout.
*/
IF DB_NAME() <> N'ShopCart'
    THROW 57000, N'007 solo puede ejecutarse en la base ShopCart.', 1;

IF @@TRANCOUNT <> 0 OR (2 & @@OPTIONS) = 2
    THROW 57001, N'Inicie con Auto-commit y sin transacciones abiertas o implícitas.', 1;

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
    THROW 57002, N'Se requiere CONTROL sobre ShopCart para inspeccionar y crear el esquema.', 1;

IF NOT EXISTS (
    SELECT 1 FROM sys.databases
    WHERE database_id = DB_ID()
      AND collation_name = N'Latin1_General_100_CI_AI_SC'
      AND recovery_model_desc = N'SIMPLE'
      AND state_desc = N'ONLINE' AND user_access_desc = N'MULTI_USER'
      AND is_read_only = 0 AND source_database_id IS NULL
)
    THROW 57003, N'Las propiedades de ShopCart no coinciden con el arranque 001.', 1;

DECLARE @HuellaRecibida sql_variant = SESSION_CONTEXT(N'ShopCart.Migracion007.SHA256');
IF @HuellaRecibida IS NULL
   OR CONVERT(nvarchar(128), SQL_VARIANT_PROPERTY(@HuellaRecibida, 'BaseType')) NOT IN (N'binary', N'varbinary')
    THROW 57004, N'Suministre el SHA-256 real como valor binario en SESSION_CONTEXT antes de ejecutar 007.', 1;

DECLARE @SHA256 varbinary(max) = CONVERT(varbinary(max), @HuellaRecibida);
IF DATALENGTH(@SHA256) <> 32
    THROW 57005, N'La huella SHA-256 debe contener exactamente 32 bytes.', 1;

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
        THROW 57006, N'No se pudo obtener el bloqueo exclusivo de migraciones.', 1;

    DECLARE @IDVersiones int = OBJECT_ID(N'dbo.VersionesMigracion', N'U');
    IF @IDVersiones IS NULL
        THROW 57007, N'Falta la tabla técnica creada por 001. No se aplicará 007.', 1;

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
        THROW 57008, N'Las columnas de VersionesMigracion no cumplen el contrato de 001.', 1;

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
        THROW 57009, N'VersionesMigracion requiere la PK clustered de 001 sobre Version.', 1;

    IF EXISTS (SELECT 1 FROM sys.triggers WHERE parent_id = @IDVersiones)
       OR EXISTS (SELECT 1 FROM sys.tables WHERE object_id = @IDVersiones
                  AND (temporal_type <> 0 OR is_memory_optimized = 1))
        THROW 57010, N'VersionesMigracion tiene características inesperadas; revisar manualmente.', 1;

    -- Lote inferior: errores de compilación/resolución quedan dentro del TRY externo.
    EXEC sys.sp_executesql N'
        IF NOT EXISTS (
            SELECT 1 FROM dbo.VersionesMigracion WITH (UPDLOCK, HOLDLOCK)
            WHERE [Version] = 6 AND NombreArchivo = N''006_MetodosEnvio.sql''
        )
            THROW 57013, N''Debe estar registrada la migración 006_MetodosEnvio.sql antes de aplicar 007.'', 1;
        IF EXISTS (SELECT 1 FROM dbo.VersionesMigracion WITH (UPDLOCK, HOLDLOCK)
                   WHERE [Version] >= 7)
            THROW 57011, N''007 o una migración posterior ya está registrada. No se reaplica ni se certifica el esquema existente.'', 1;
    ';

    IF EXISTS (
        SELECT 1 FROM sys.objects AS o
        JOIN sys.schemas AS s ON s.schema_id = o.schema_id
        WHERE s.name = N'dbo'
          AND o.name IN (N'Checkouts', N'DetallesCheckout')
    )
        THROW 57012, N'Ya existe parte o todo el esquema de checkout sin registro compatible. Revisar manualmente; no se reparará.', 1;

    -- Verifica tablas y tipos nativos de las claves que serán destinos de FK.
    IF EXISTS (
        SELECT 1
        FROM (VALUES
            (N'dbo.Carritos', N'IdCarrito', N'bigint'),
            (N'dbo.Usuarios', N'IdUsuario', N'bigint'),
            (N'dbo.Direcciones', N'IdDireccion', N'bigint'),
            (N'dbo.MetodosEnvio', N'IdMetodoEnvio', N'int'),
            (N'dbo.Cupones', N'IdCupon', N'bigint'),
            (N'dbo.VariantesProducto', N'IdVariante', N'bigint')
        ) AS e(Tabla, Columna, Tipo)
        WHERE NOT EXISTS (
            SELECT 1 FROM sys.columns AS c
            WHERE c.object_id = OBJECT_ID(e.Tabla, N'U')
              AND c.name = e.Columna AND c.system_type_id = TYPE_ID(e.Tipo)
              AND c.user_type_id = c.system_type_id
              AND c.is_nullable = 0 AND c.is_computed = 0
        )
    )
        THROW 57014, N'Faltan tablas previas o sus claves no tienen los tipos requeridos.', 1;

    -- DDL constante en un lote inferior: sus errores alcanzan el CATCH externo.
    EXEC sys.sp_executesql N'
        CREATE TABLE dbo.Checkouts
        (
            IdCheckout bigint IDENTITY(1,1) NOT NULL,
            IdCarrito bigint NOT NULL,
            IdUsuario bigint NULL,
            IdDireccion bigint NULL,
            IdMetodoEnvio int NULL,
            IdCupon bigint NULL,
            ClaveIdempotenciaHash binary(32) NOT NULL,
            Estado varchar(20) NOT NULL
                CONSTRAINT DF_Checkouts_Estado DEFAULT (''INICIADO''),
            Subtotal decimal(19,4) NOT NULL
                CONSTRAINT DF_Checkouts_Subtotal DEFAULT (0),
            Descuento decimal(19,4) NOT NULL
                CONSTRAINT DF_Checkouts_Descuento DEFAULT (0),
            CostoEnvio decimal(19,4) NOT NULL
                CONSTRAINT DF_Checkouts_CostoEnvio DEFAULT (0),
            Total decimal(19,4) NOT NULL
                CONSTRAINT DF_Checkouts_Total DEFAULT (0),
            FechaExpiracionUTC datetime2(7) NOT NULL,
            FechaCreacionUTC datetime2(7) NOT NULL
                CONSTRAINT DF_Checkouts_FechaCreacionUTC DEFAULT (SYSUTCDATETIME()),
            FechaActualizacionUTC datetime2(7) NOT NULL
                CONSTRAINT DF_Checkouts_FechaActualizacionUTC DEFAULT (SYSUTCDATETIME()),
            CONSTRAINT PK_Checkouts PRIMARY KEY CLUSTERED (IdCheckout),
            CONSTRAINT UQ_Checkouts_ClaveIdempotenciaHash
                UNIQUE NONCLUSTERED (ClaveIdempotenciaHash),
            CONSTRAINT FK_Checkouts_Carritos FOREIGN KEY (IdCarrito)
                REFERENCES dbo.Carritos (IdCarrito)
                ON DELETE NO ACTION ON UPDATE NO ACTION,
            CONSTRAINT FK_Checkouts_Usuarios FOREIGN KEY (IdUsuario)
                REFERENCES dbo.Usuarios (IdUsuario)
                ON DELETE NO ACTION ON UPDATE NO ACTION,
            CONSTRAINT FK_Checkouts_Direcciones FOREIGN KEY (IdDireccion)
                REFERENCES dbo.Direcciones (IdDireccion)
                ON DELETE NO ACTION ON UPDATE NO ACTION,
            CONSTRAINT FK_Checkouts_MetodosEnvio FOREIGN KEY (IdMetodoEnvio)
                REFERENCES dbo.MetodosEnvio (IdMetodoEnvio)
                ON DELETE NO ACTION ON UPDATE NO ACTION,
            CONSTRAINT FK_Checkouts_Cupones FOREIGN KEY (IdCupon)
                REFERENCES dbo.Cupones (IdCupon)
                ON DELETE NO ACTION ON UPDATE NO ACTION,
            CONSTRAINT CK_Checkouts_EstadoPermitido CHECK (
                Estado IN (''INICIADO'', ''RESERVADO'', ''CONFIRMADO'', ''EXPIRADO'', ''CANCELADO'')
            ),
            CONSTRAINT CK_Checkouts_ImportesNoNegativos CHECK (
                Subtotal >= 0 AND Descuento >= 0 AND CostoEnvio >= 0 AND Total >= 0
            ),
            CONSTRAINT CK_Checkouts_DescuentoNoSuperaSubtotal CHECK (Descuento <= Subtotal),
            -- Las operaciones producen decimal(22,4) y decimal(23,4), sin perder escala.
            CONSTRAINT CK_Checkouts_TotalCoherente CHECK (
                CONVERT(decimal(23,4), Total) =
                    CONVERT(decimal(21,4), Subtotal)
                    - CONVERT(decimal(21,4), Descuento)
                    + CONVERT(decimal(21,4), CostoEnvio)
            )
        );
        -- Un solo índice cubre AMBOS estados; dos índices separados no bastarían.
        CREATE UNIQUE NONCLUSTERED INDEX UX_Checkouts_CarritoActivo
            ON dbo.Checkouts (IdCarrito)
            WHERE Estado IN (''INICIADO'', ''RESERVADO'');
        -- Historial completo por carrito: el índice filtrado no lo cubre.
        CREATE NONCLUSTERED INDEX IX_Checkouts_IdCarrito ON dbo.Checkouts (IdCarrito);
        -- Índices de FK para consultas y comprobaciones de integridad referencial.
        CREATE NONCLUSTERED INDEX IX_Checkouts_IdUsuario ON dbo.Checkouts (IdUsuario);
        CREATE NONCLUSTERED INDEX IX_Checkouts_IdDireccion ON dbo.Checkouts (IdDireccion);
        CREATE NONCLUSTERED INDEX IX_Checkouts_IdMetodoEnvio ON dbo.Checkouts (IdMetodoEnvio);
        CREATE NONCLUSTERED INDEX IX_Checkouts_IdCupon ON dbo.Checkouts (IdCupon);

        CREATE TABLE dbo.DetallesCheckout
        (
            IdDetalleCheckout bigint IDENTITY(1,1) NOT NULL,
            IdCheckout bigint NOT NULL,
            IdVariante bigint NOT NULL,
            SKU nvarchar(64) NOT NULL,
            NombreProducto nvarchar(200) NOT NULL,
            DescripcionVariante nvarchar(250) NULL,
            Cantidad int NOT NULL,
            PrecioUnitario decimal(19,4) NOT NULL,
            SubtotalLinea decimal(19,4) NOT NULL,
            FechaCreacionUTC datetime2(7) NOT NULL
                CONSTRAINT DF_DetallesCheckout_FechaCreacionUTC DEFAULT (SYSUTCDATETIME()),
            CONSTRAINT PK_DetallesCheckout PRIMARY KEY CLUSTERED (IdDetalleCheckout),
            CONSTRAINT UQ_DetallesCheckout_Checkout_Variante
                UNIQUE NONCLUSTERED (IdCheckout, IdVariante),
            CONSTRAINT FK_DetallesCheckout_Checkouts FOREIGN KEY (IdCheckout)
                REFERENCES dbo.Checkouts (IdCheckout)
                ON DELETE NO ACTION ON UPDATE NO ACTION,
            CONSTRAINT FK_DetallesCheckout_VariantesProducto FOREIGN KEY (IdVariante)
                REFERENCES dbo.VariantesProducto (IdVariante)
                ON DELETE NO ACTION ON UPDATE NO ACTION,
            CONSTRAINT CK_DetallesCheckout_CantidadPositiva CHECK (Cantidad > 0),
            CONSTRAINT CK_DetallesCheckout_ImportesNoNegativos CHECK (
                PrecioUnitario >= 0 AND SubtotalLinea >= 0
            ),
            -- decimal(10,0) * decimal(19,4) resulta en decimal(30,4).
            -- Cubre todo int * precio permitido, incluso si no cabe en la columna.
            -- Se compara sin convertir el producto a decimal(19,4).
            CONSTRAINT CK_DetallesCheckout_SubtotalCoherente CHECK (
                CONVERT(decimal(30,4), SubtotalLinea) =
                    CONVERT(decimal(10,0), Cantidad)
                    * CONVERT(decimal(19,4), PrecioUnitario)
            )
        );
        -- La UNIQUE cubre IdCheckout; este índice cubre la otra FK.
        CREATE NONCLUSTERED INDEX IX_DetallesCheckout_IdVariante
            ON dbo.DetallesCheckout (IdVariante);
    ';

    -- Registro técnico y DDL se confirman o revierten juntos.
    EXEC sys.sp_executesql N'
        INSERT INTO dbo.VersionesMigracion
            ([Version], NombreArchivo, SHA256, FechaAplicacionUTC, Ejecutor)
        VALUES
            (7, N''007_Checkout.sql'', @Huella, SYSUTCDATETIME(), ORIGINAL_LOGIN());
    ', N'@Huella varbinary(32)', @Huella = @SHA256;

    COMMIT TRANSACTION;
    PRINT N'Migración 007 completada: Checkouts, DetallesCheckout y registro técnico confirmados.';
END TRY
BEGIN CATCH
    IF XACT_STATE() <> 0
        ROLLBACK TRANSACTION;
    THROW;
END CATCH;
