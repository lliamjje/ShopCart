/*
    009_PedidosPagos.sql — Pedidos, detalles históricos y pagos simulados.
    Ejecutar COMPLETO como un único lote, sin GO, conectado a ShopCart.
    Iniciar con Auto-commit, sin transacciones abiertas ni implícitas.
    No ejecutar selecciones parciales ni cambios administrativos concurrentes.

    Tras aprobar el archivo FINAL, calcular SHA-256 con Get-FileHash.
    No editar después; suministrar los 32 bytes binary/varbinary mediante
    sp_set_session_context en la MISMA conexión de DataGrip, clave
    ShopCart.Migracion009.SHA256. Limpiar el contexto al terminar.
    SQL valida formato; el ejecutor comprueba la correspondencia archivo/huella.

    Diseño confirmado: pedido inicialmente PENDIENTE_PAGO, invitados permitidos,
    pagos de monto cero permitidos y como máximo una aprobación por pedido.
    Reembolsos quedan para 010; UsosCupon para una migración estructural posterior
    antes de implementar los SP dependientes. No se crean aquí.

    Instantáneas: TelefonoDestinatario copia TelefonoContacto; Ciudad copia Municipio.
    Se conservan longitudes de origen; NombreCategoria admite 200 frente a 100.
    Los SP capturarán también entrega de invitados y validarán longitud sin truncar.
    Los CHECK de texto recortan espacios normales U+0020, como las migraciones previas.

    Pendientes para SP transaccionales:
    - Validar propiedad de checkout/usuario, incluso invitados, y coherencia de FK.
      Las FK simples no prueban pertenencia ni igualdad con los datos del checkout.
    - Capturar instantáneas definitivas; conservar categoría histórica cuando proceda.
    - Conciliar Subtotal y Descuento de cabecera con SUM de líneas. Distribuir
      descuentos y redondeos determinísticamente, usando precisión ampliada.
    - IVA del 12 % YA incluido: extraerlo del neto de productos y del envío,
      sin sumarlo otra vez. Conciliar bases e IVA de líneas y envío con cabecera.
      Los CHECK verifican igualdades por fila, no la tasa ni sumas entre tablas.
    - Pago aprobado exactamente por Total, incluso ambos cero; comparar contenido
      al reutilizar una clave idempotente y devolver el resultado ya registrado.
    - Validar reservas por estado y vencimiento UTC; consumirlas una sola vez,
      coordinar pedido, pago, existencias, kardex, cupón e historial atómicamente.
    - Restringir transiciones: el CHECK solo limita estados, no sus cambios.
      Preservar importes e instantáneas tras confirmar y actualizar fechas.
      Los DEFAULT de actualización solo inicializan; no actualizan automáticamente.
    Estas restricciones no implementan por sí solas el flujo de compra.
*/
IF DB_NAME() <> N'ShopCart'
    THROW 59000, N'009 solo puede ejecutarse en la base ShopCart.', 1;

IF @@TRANCOUNT <> 0 OR (2 & @@OPTIONS) = 2
    THROW 59001, N'Inicie con Auto-commit y sin transacciones abiertas o implícitas.', 1;

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
    THROW 59002, N'Se requiere CONTROL sobre ShopCart para inspeccionar y crear el esquema.', 1;

IF NOT EXISTS (
    SELECT 1 FROM sys.databases
    WHERE database_id = DB_ID()
      AND collation_name = N'Latin1_General_100_CI_AI_SC'
      AND recovery_model_desc = N'SIMPLE'
      AND state_desc = N'ONLINE' AND user_access_desc = N'MULTI_USER'
      AND is_read_only = 0 AND source_database_id IS NULL
)
    THROW 59003, N'Las propiedades de ShopCart no coinciden con el arranque 001.', 1;

DECLARE @HuellaRecibida sql_variant = SESSION_CONTEXT(N'ShopCart.Migracion009.SHA256');
IF @HuellaRecibida IS NULL
   OR CONVERT(nvarchar(128), SQL_VARIANT_PROPERTY(@HuellaRecibida, 'BaseType')) NOT IN (N'binary', N'varbinary')
    THROW 59004, N'Suministre el SHA-256 real como valor binario en SESSION_CONTEXT antes de ejecutar 009.', 1;

DECLARE @SHA256 varbinary(max) = CONVERT(varbinary(max), @HuellaRecibida);
IF DATALENGTH(@SHA256) <> 32
    THROW 59005, N'La huella SHA-256 debe contener exactamente 32 bytes.', 1;

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
        THROW 59006, N'No se pudo obtener el bloqueo exclusivo de migraciones.', 1;

    DECLARE @IDVersiones int = OBJECT_ID(N'dbo.VersionesMigracion', N'U');
    IF @IDVersiones IS NULL
        THROW 59007, N'Falta la tabla técnica creada por 001. No se aplicará 009.', 1;

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
        THROW 59008, N'Las columnas de VersionesMigracion no cumplen el contrato de 001.', 1;

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
        THROW 59009, N'VersionesMigracion requiere la PK clustered de 001 sobre Version.', 1;

    IF EXISTS (SELECT 1 FROM sys.triggers WHERE parent_id = @IDVersiones)
       OR EXISTS (SELECT 1 FROM sys.tables WHERE object_id = @IDVersiones
                  AND (temporal_type <> 0 OR is_memory_optimized = 1))
        THROW 59010, N'VersionesMigracion tiene características inesperadas; revisar manualmente.', 1;

    -- Lote inferior: errores de compilación/resolución quedan dentro del TRY externo.
    EXEC sys.sp_executesql N'
        IF NOT EXISTS (
            SELECT 1 FROM dbo.VersionesMigracion WITH (UPDLOCK, HOLDLOCK)
            WHERE [Version] = 8 AND NombreArchivo = N''008_Reservas.sql''
        )
            THROW 59013, N''Debe estar registrada la migración 008_Reservas.sql antes de aplicar 009.'', 1;
        IF EXISTS (SELECT 1 FROM dbo.VersionesMigracion WITH (UPDLOCK, HOLDLOCK)
                   WHERE [Version] >= 9)
            THROW 59011, N''009 o una migración posterior ya está registrada. No se reaplica ni se certifica el esquema existente.'', 1;
    ';

    IF EXISTS (
        SELECT 1 FROM sys.objects AS o
        JOIN sys.schemas AS s ON s.schema_id = o.schema_id
        WHERE s.name = N'dbo'
          AND o.name IN (N'Pedidos', N'DetallesPedido', N'Pagos')
    )
        THROW 59012, N'Ya existe parte o todo el esquema de pedidos y pagos sin registro compatible. Revisar manualmente; no se reparará.', 1;

    -- Verifica tablas y tipos nativos de las claves que serán destinos de FK.
    -- La creación de las FK comprobará también las claves candidatas de destino.
    IF EXISTS (
        SELECT 1
        FROM (VALUES
            (N'dbo.Checkouts', N'IdCheckout', N'bigint'),
            (N'dbo.Usuarios', N'IdUsuario', N'bigint'),
            (N'dbo.MetodosEnvio', N'IdMetodoEnvio', N'int'),
            (N'dbo.Cupones', N'IdCupon', N'bigint'),
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
        THROW 59014, N'Faltan tablas previas o sus claves no tienen los tipos requeridos.', 1;

    -- DDL constante en un lote inferior: sus errores alcanzan el CATCH externo.
    EXEC sys.sp_executesql N'
        CREATE TABLE dbo.Pedidos
        (
            IdPedido bigint IDENTITY(1,1) NOT NULL,
            NumeroPedido varchar(30) NOT NULL,
            IdCheckout bigint NOT NULL,
            IdUsuario bigint NULL,
            IdMetodoEnvio int NOT NULL,
            IdCupon bigint NULL,
            Estado varchar(25) NOT NULL CONSTRAINT DF_Pedidos_Estado DEFAULT (''PENDIENTE_PAGO''),
            Moneda char(3) NOT NULL CONSTRAINT DF_Pedidos_Moneda DEFAULT (''GTQ''),
            Subtotal decimal(19,4) NOT NULL,
            Descuento decimal(19,4) NOT NULL,
            CostoEnvio decimal(19,4) NOT NULL,
            Total decimal(19,4) NOT NULL,
            BaseImponible decimal(19,4) NOT NULL,
            MontoIVA decimal(19,4) NOT NULL,
            FechaPedidoUTC datetime2(7) NOT NULL
                CONSTRAINT DF_Pedidos_FechaPedidoUTC DEFAULT (SYSUTCDATETIME()),
            FechaActualizacionUTC datetime2(7) NOT NULL
                CONSTRAINT DF_Pedidos_FechaActualizacionUTC DEFAULT (SYSUTCDATETIME()),
            NombreDestinatario nvarchar(150) NOT NULL,
            TelefonoDestinatario nvarchar(25) NOT NULL,
            DireccionLinea1 nvarchar(250) NOT NULL,
            DireccionLinea2 nvarchar(250) NULL,
            Ciudad nvarchar(100) NOT NULL,
            Departamento nvarchar(100) NOT NULL,
            CodigoPostal nvarchar(15) NULL,
            Pais char(2) NOT NULL,
            CodigoMetodoEnvio varchar(30) NOT NULL,
            NombreMetodoEnvio nvarchar(100) NOT NULL,
            CONSTRAINT PK_Pedidos PRIMARY KEY CLUSTERED (IdPedido),
            CONSTRAINT UQ_Pedidos_NumeroPedido UNIQUE NONCLUSTERED (NumeroPedido),
            CONSTRAINT UQ_Pedidos_IdCheckout UNIQUE NONCLUSTERED (IdCheckout),
            CONSTRAINT FK_Pedidos_Checkouts FOREIGN KEY (IdCheckout)
                REFERENCES dbo.Checkouts (IdCheckout) ON DELETE NO ACTION ON UPDATE NO ACTION,
            CONSTRAINT FK_Pedidos_Usuarios FOREIGN KEY (IdUsuario)
                REFERENCES dbo.Usuarios (IdUsuario) ON DELETE NO ACTION ON UPDATE NO ACTION,
            CONSTRAINT FK_Pedidos_MetodosEnvio FOREIGN KEY (IdMetodoEnvio)
                REFERENCES dbo.MetodosEnvio (IdMetodoEnvio) ON DELETE NO ACTION ON UPDATE NO ACTION,
            CONSTRAINT FK_Pedidos_Cupones FOREIGN KEY (IdCupon)
                REFERENCES dbo.Cupones (IdCupon) ON DELETE NO ACTION ON UPDATE NO ACTION,
            CONSTRAINT CK_Pedidos_EstadoPermitido CHECK (
                Estado IN (''PENDIENTE_PAGO'', ''PAGADO'', ''EN_PREPARACION'', ''ENVIADO'', ''ENTREGADO'', ''CANCELADO'')
            ),
            CONSTRAINT CK_Pedidos_MonedaGTQ CHECK (Moneda = ''GTQ''),
            CONSTRAINT CK_Pedidos_PaisGT CHECK (Pais = ''GT''),
            CONSTRAINT CK_Pedidos_ImportesNoNegativos CHECK (
                Subtotal >= 0 AND Descuento >= 0 AND CostoEnvio >= 0
                AND Total >= 0 AND BaseImponible >= 0 AND MontoIVA >= 0
            ),
            CONSTRAINT CK_Pedidos_DescuentoNoSuperaSubtotal CHECK (Descuento <= Subtotal),
            -- Resta decimal(22,4) y suma decimal(23,4), sin reducir escala.
            CONSTRAINT CK_Pedidos_TotalCoherente CHECK (
                CONVERT(decimal(23,4), Total) =
                    CONVERT(decimal(21,4), Subtotal) - CONVERT(decimal(21,4), Descuento)
                    + CONVERT(decimal(21,4), CostoEnvio)
            ),
            CONSTRAINT CK_Pedidos_DesgloseFiscalCoherente CHECK (
                CONVERT(decimal(22,4), Total) =
                    CONVERT(decimal(21,4), BaseImponible) + CONVERT(decimal(21,4), MontoIVA)
            ),
            CONSTRAINT CK_Pedidos_NumeroPedidoValido CHECK (
                LEN(LTRIM(RTRIM(NumeroPedido))) > 0 AND DATALENGTH(NumeroPedido) = DATALENGTH(LTRIM(RTRIM(NumeroPedido)))
            ),
            CONSTRAINT CK_Pedidos_NombreDestinatarioValido CHECK (
                LEN(LTRIM(RTRIM(NombreDestinatario))) > 0 AND DATALENGTH(NombreDestinatario) = DATALENGTH(LTRIM(RTRIM(NombreDestinatario)))
            ),
            CONSTRAINT CK_Pedidos_TelefonoDestinatarioValido CHECK (
                LEN(LTRIM(RTRIM(TelefonoDestinatario))) > 0 AND DATALENGTH(TelefonoDestinatario) = DATALENGTH(LTRIM(RTRIM(TelefonoDestinatario)))
            ),
            CONSTRAINT CK_Pedidos_DireccionLinea1Valido CHECK (
                LEN(LTRIM(RTRIM(DireccionLinea1))) > 0 AND DATALENGTH(DireccionLinea1) = DATALENGTH(LTRIM(RTRIM(DireccionLinea1)))
            ),
            CONSTRAINT CK_Pedidos_CiudadValido CHECK (
                LEN(LTRIM(RTRIM(Ciudad))) > 0 AND DATALENGTH(Ciudad) = DATALENGTH(LTRIM(RTRIM(Ciudad)))
            ),
            CONSTRAINT CK_Pedidos_DepartamentoValido CHECK (
                LEN(LTRIM(RTRIM(Departamento))) > 0 AND DATALENGTH(Departamento) = DATALENGTH(LTRIM(RTRIM(Departamento)))
            ),
            CONSTRAINT CK_Pedidos_CodigoMetodoEnvioValido CHECK (
                LEN(LTRIM(RTRIM(CodigoMetodoEnvio))) > 0 AND DATALENGTH(CodigoMetodoEnvio) = DATALENGTH(LTRIM(RTRIM(CodigoMetodoEnvio)))
            ),
            CONSTRAINT CK_Pedidos_NombreMetodoEnvioValido CHECK (
                LEN(LTRIM(RTRIM(NombreMetodoEnvio))) > 0 AND DATALENGTH(NombreMetodoEnvio) = DATALENGTH(LTRIM(RTRIM(NombreMetodoEnvio)))
            ),
            CONSTRAINT CK_Pedidos_DireccionLinea2Valido CHECK (
                DireccionLinea2 IS NULL OR (LEN(LTRIM(RTRIM(DireccionLinea2))) > 0 AND DATALENGTH(DireccionLinea2) = DATALENGTH(LTRIM(RTRIM(DireccionLinea2))))
            ),
            CONSTRAINT CK_Pedidos_CodigoPostalValido CHECK (
                CodigoPostal IS NULL OR (LEN(LTRIM(RTRIM(CodigoPostal))) > 0 AND DATALENGTH(CodigoPostal) = DATALENGTH(LTRIM(RTRIM(CodigoPostal))))
            )
        );
        -- Consultas por cliente/fecha; los otros índices cubren las FK restantes.
        CREATE NONCLUSTERED INDEX IX_Pedidos_Usuario_Fecha ON dbo.Pedidos (IdUsuario, FechaPedidoUTC);
        CREATE NONCLUSTERED INDEX IX_Pedidos_IdMetodoEnvio ON dbo.Pedidos (IdMetodoEnvio);
        CREATE NONCLUSTERED INDEX IX_Pedidos_IdCupon ON dbo.Pedidos (IdCupon);

        CREATE TABLE dbo.DetallesPedido
        (
            IdDetallePedido bigint IDENTITY(1,1) NOT NULL,
            IdPedido bigint NOT NULL,
            IdVariante bigint NOT NULL,
            SKU nvarchar(64) NOT NULL,
            NombreProducto nvarchar(200) NOT NULL,
            DescripcionVariante nvarchar(250) NULL,
            IdCategoria int NULL,
            NombreCategoria nvarchar(200) NULL,
            Cantidad int NOT NULL,
            PrecioUnitario decimal(19,4) NOT NULL,
            SubtotalLinea decimal(19,4) NOT NULL,
            DescuentoLinea decimal(19,4) NOT NULL,
            TotalLinea decimal(19,4) NOT NULL,
            BaseImponibleLinea decimal(19,4) NOT NULL,
            MontoIVALinea decimal(19,4) NOT NULL,
            FechaCreacionUTC datetime2(7) NOT NULL
                CONSTRAINT DF_DetallesPedido_FechaCreacionUTC DEFAULT (SYSUTCDATETIME()),
            CONSTRAINT PK_DetallesPedido PRIMARY KEY CLUSTERED (IdDetallePedido),
            CONSTRAINT UQ_DetallesPedido_Pedido_Variante UNIQUE NONCLUSTERED (IdPedido, IdVariante),
            CONSTRAINT FK_DetallesPedido_Pedidos FOREIGN KEY (IdPedido)
                REFERENCES dbo.Pedidos (IdPedido) ON DELETE NO ACTION ON UPDATE NO ACTION,
            CONSTRAINT FK_DetallesPedido_VariantesProducto FOREIGN KEY (IdVariante)
                REFERENCES dbo.VariantesProducto (IdVariante) ON DELETE NO ACTION ON UPDATE NO ACTION,
            CONSTRAINT FK_DetallesPedido_Categorias FOREIGN KEY (IdCategoria)
                REFERENCES dbo.Categorias (IdCategoria) ON DELETE NO ACTION ON UPDATE NO ACTION,
            CONSTRAINT CK_DetallesPedido_CantidadPositiva CHECK (Cantidad > 0),
            CONSTRAINT CK_DetallesPedido_ImportesNoNegativos CHECK (
                PrecioUnitario >= 0 AND SubtotalLinea >= 0 AND DescuentoLinea >= 0
                AND TotalLinea >= 0 AND BaseImponibleLinea >= 0 AND MontoIVALinea >= 0
            ),
            CONSTRAINT CK_DetallesPedido_DescuentoNoSuperaSubtotal CHECK (DescuentoLinea <= SubtotalLinea),
            CONSTRAINT CK_DetallesPedido_TotalCoherente CHECK (
                CONVERT(decimal(22,4), TotalLinea) =
                    CONVERT(decimal(21,4), SubtotalLinea) - CONVERT(decimal(21,4), DescuentoLinea)
            ),
            -- int completo convertido a decimal(10,0); producto decimal(30,4).
            -- No convertir el producto a decimal(19,4): se compara sin truncamiento.
            CONSTRAINT CK_DetallesPedido_SubtotalCoherente CHECK (
                CONVERT(decimal(30,4), SubtotalLinea) =
                    CONVERT(decimal(10,0), Cantidad) * CONVERT(decimal(19,4), PrecioUnitario)
            ),
            CONSTRAINT CK_DetallesPedido_DesgloseFiscalCoherente CHECK (
                CONVERT(decimal(22,4), TotalLinea) =
                    CONVERT(decimal(21,4), BaseImponibleLinea) + CONVERT(decimal(21,4), MontoIVALinea)
            )
        );
        -- La UNIQUE ya cubre IdPedido; estos índices cubren las otras FK.
        CREATE NONCLUSTERED INDEX IX_DetallesPedido_IdVariante ON dbo.DetallesPedido (IdVariante);
        CREATE NONCLUSTERED INDEX IX_DetallesPedido_IdCategoria ON dbo.DetallesPedido (IdCategoria);

        CREATE TABLE dbo.Pagos
        (
            IdPago bigint IDENTITY(1,1) NOT NULL,
            IdPedido bigint NOT NULL,
            ClaveIdempotenciaHash binary(32) NOT NULL,
            ReferenciaPago varchar(80) NOT NULL,
            MetodoPago varchar(30) NOT NULL,
            Estado varchar(20) NOT NULL CONSTRAINT DF_Pagos_Estado DEFAULT (''PENDIENTE''),
            Monto decimal(19,4) NOT NULL,
            Moneda char(3) NOT NULL CONSTRAINT DF_Pagos_Moneda DEFAULT (''GTQ''),
            CodigoResultado varchar(40) NULL,
            MensajeResultado nvarchar(250) NULL,
            FechaCreacionUTC datetime2(7) NOT NULL
                CONSTRAINT DF_Pagos_FechaCreacionUTC DEFAULT (SYSUTCDATETIME()),
            FechaActualizacionUTC datetime2(7) NOT NULL
                CONSTRAINT DF_Pagos_FechaActualizacionUTC DEFAULT (SYSUTCDATETIME()),
            FechaResolucionUTC datetime2(7) NULL,
            CONSTRAINT PK_Pagos PRIMARY KEY CLUSTERED (IdPago),
            CONSTRAINT FK_Pagos_Pedidos FOREIGN KEY (IdPedido)
                REFERENCES dbo.Pedidos (IdPedido) ON DELETE NO ACTION ON UPDATE NO ACTION,
            CONSTRAINT UQ_Pagos_ClaveIdempotenciaHash UNIQUE NONCLUSTERED (ClaveIdempotenciaHash),
            CONSTRAINT UQ_Pagos_ReferenciaPago UNIQUE NONCLUSTERED (ReferenciaPago),
            -- Cero aprobado solo será válido si coincide con Total del pedido: regla de SP.
            CONSTRAINT CK_Pagos_MontoNoNegativo CHECK (Monto >= 0),
            CONSTRAINT CK_Pagos_MonedaGTQ CHECK (Moneda = ''GTQ''),
            CONSTRAINT CK_Pagos_EstadoPermitido CHECK (
                Estado IN (''PENDIENTE'', ''APROBADO'', ''RECHAZADO'', ''CANCELADO'')
            ),
            CONSTRAINT CK_Pagos_ResolucionCoherente CHECK (
                (Estado = ''PENDIENTE'' AND FechaResolucionUTC IS NULL)
                OR (Estado IN (''APROBADO'', ''RECHAZADO'', ''CANCELADO'') AND FechaResolucionUTC IS NOT NULL)
            ),
            CONSTRAINT CK_Pagos_ReferenciaPagoValida CHECK (
                LEN(LTRIM(RTRIM(ReferenciaPago))) > 0 AND DATALENGTH(ReferenciaPago) = DATALENGTH(LTRIM(RTRIM(ReferenciaPago)))
            ),
            CONSTRAINT CK_Pagos_MetodoPagoValido CHECK (
                LEN(LTRIM(RTRIM(MetodoPago))) > 0 AND DATALENGTH(MetodoPago) = DATALENGTH(LTRIM(RTRIM(MetodoPago)))
            )
        );
        CREATE UNIQUE NONCLUSTERED INDEX UX_Pagos_PedidoAprobado
            ON dbo.Pagos (IdPedido) WHERE Estado = ''APROBADO'';
        -- Historial de todos los intentos y FK; el índice filtrado no lo cubre.
        CREATE NONCLUSTERED INDEX IX_Pagos_IdPedido ON dbo.Pagos (IdPedido);
    ';

    -- Registro técnico y DDL se confirman o revierten juntos.
    EXEC sys.sp_executesql N'
        INSERT INTO dbo.VersionesMigracion
            ([Version], NombreArchivo, SHA256, FechaAplicacionUTC, Ejecutor)
        VALUES
            (9, N''009_PedidosPagos.sql'', @Huella, SYSUTCDATETIME(), ORIGINAL_LOGIN());
    ', N'@Huella varbinary(32)', @Huella = @SHA256;

    COMMIT TRANSACTION;
    PRINT N'Migración 009 completada: Pedidos, DetallesPedido, Pagos y registro técnico confirmados.';
END TRY
BEGIN CATCH
    IF XACT_STATE() <> 0
        ROLLBACK TRANSACTION;
    THROW;
END CATCH;

