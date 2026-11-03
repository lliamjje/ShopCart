/*
    018_ProcedimientosPedidosPagos.sql. Ejecutar completo, sin GO, con Auto-commit en ShopCart.
    SHA-256 final: suministrar 32 bytes mediante SESSION_CONTEXT,
    clave ShopCart.Migracion018.SHA256, misma conexión DataGrip.
    No incluye huella literal. El ejecutor verifica archivo/huella y limpia contexto.
    SQL preparado para revisión; no ejecutado contra el motor.

    Frontera de confianza: solo conexión de servicio controlada por el backend.
    El backend verifica contraseña/JWT y nunca toma IdActor/IdSesion del body HTTP.
    SQL verifica sesión vigente, usuario activo, rol y propiedad; no autentica JWT.
    No usar SESSION_CONTEXT como identidad. No se conceden permisos aquí.
    Configurar después EXECUTE por procedimiento para la cuenta de privilegios mínimos;
    no conceder EXECUTE a esquema/public ni acceso a helpers, autenticación o tablas.
    La identidad del servicio y su política de permisos siguen pendientes de despliegue.

    Escrituras: operación superior dueña de la transacción, sin transacciones externas.
    Bloqueo exclusivo ShopCart.Negocio común a TODAS las escrituras de estas migraciones:
    serializa decisiones de sesión, catálogo, carrito, cupón, stock y compra.
    No delegar COMMIT a helpers ni llamar operaciones superiores desde otras.
    Favorece corrección en la demostración local; evaluar contención antes de escalar.
    Parámetros de texto amplios para validar longitud antes de convertir al esquema.
    Consulta por IdPedido o NumeroPedido con autorización por propiedad/rol. Pago CREAR/APROBAR/RECHAZAR mantiene contrato estable en reintentos. Pedido/snapshots nacen en 017; cancelación compensada en 019.
*/
IF DB_NAME() <> N'ShopCart'
    THROW 62600, N'018 solo puede ejecutarse en la base ShopCart.', 1;

IF @@TRANCOUNT <> 0 OR (2 & @@OPTIONS) = 2
    THROW 62601, N'Inicie con Auto-commit y sin transacciones abiertas o implícitas.', 1;

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
    THROW 62602, N'Se requiere CONTROL sobre ShopCart para inspeccionar y crear el esquema.', 1;

IF NOT EXISTS (
    SELECT 1 FROM sys.databases
    WHERE database_id = DB_ID()
      AND collation_name = N'Latin1_General_100_CI_AI_SC'
      AND recovery_model_desc = N'SIMPLE'
      AND state_desc = N'ONLINE' AND user_access_desc = N'MULTI_USER'
      AND is_read_only = 0 AND source_database_id IS NULL
)
    THROW 62603, N'Las propiedades de ShopCart no coinciden con el arranque 001.', 1;

DECLARE @HuellaRecibida sql_variant = SESSION_CONTEXT(N'ShopCart.Migracion018.SHA256');
IF @HuellaRecibida IS NULL
   OR CONVERT(nvarchar(128), SQL_VARIANT_PROPERTY(@HuellaRecibida, 'BaseType')) NOT IN (N'binary', N'varbinary')
    THROW 62604, N'Suministre el SHA-256 real como valor binario en SESSION_CONTEXT antes de ejecutar 018.', 1;

DECLARE @SHA256 varbinary(max) = CONVERT(varbinary(max), @HuellaRecibida);
IF DATALENGTH(@SHA256) <> 32
    THROW 62605, N'La huella SHA-256 debe contener exactamente 32 bytes.', 1;

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
        THROW 62606, N'No se pudo obtener el bloqueo exclusivo de migraciones.', 1;

    DECLARE @IDVersiones int = OBJECT_ID(N'dbo.VersionesMigracion', N'U');
    IF @IDVersiones IS NULL
        THROW 62607, N'Falta la tabla técnica creada por 001. No se aplicará 018.', 1;

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
        THROW 62608, N'Las columnas de VersionesMigracion no cumplen el contrato de 001.', 1;

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
        THROW 62609, N'VersionesMigracion requiere la PK clustered de 001 sobre Version.', 1;

    IF EXISTS (SELECT 1 FROM sys.triggers WHERE parent_id = @IDVersiones)
       OR EXISTS (SELECT 1 FROM sys.tables WHERE object_id = @IDVersiones
                  AND (temporal_type <> 0 OR is_memory_optimized = 1))
        THROW 62610, N'VersionesMigracion tiene características inesperadas; revisar manualmente.', 1;

    -- Lote inferior: errores de compilación/resolución quedan dentro del TRY externo.
    EXEC sys.sp_executesql N'
        IF NOT EXISTS (
            SELECT 1 FROM dbo.VersionesMigracion WITH (UPDLOCK, HOLDLOCK)
            WHERE [Version] = 17 AND NombreArchivo = N''017_ProcedimientosCheckout.sql''
        )
            THROW 62613, N''Debe estar registrada la migración 017_ProcedimientosCheckout.sql antes de aplicar 018.'', 1;
        IF EXISTS (SELECT 1 FROM dbo.VersionesMigracion WITH (UPDLOCK, HOLDLOCK)
                   WHERE [Version] >= 18)
            THROW 62611, N''018 o una migración posterior ya está registrada. No se reaplica ni se certifica el esquema existente.'', 1;
    ';


    -- Rechaza nombres conflictivos antes de crear el primer procedimiento.
    IF OBJECT_ID(N'dbo.SP_Pedidos_ProcesarPago') IS NOT NULL THROW 62650, N'Ya existe un objeto de procedimiento; no se sobrescribe.',1;
    IF OBJECT_ID(N'dbo.SP_Pedidos_Consultar') IS NOT NULL THROW 62650, N'Ya existe un objeto de procedimiento; no se sobrescribe.',1;
    IF OBJECT_ID(N'dbo.SP_Pedidos_Listar') IS NOT NULL THROW 62650, N'Ya existe un objeto de procedimiento; no se sobrescribe.',1;
    IF OBJECT_ID(N'dbo.SP_Pedidos_CambiarEstado') IS NOT NULL THROW 62650, N'Ya existe un objeto de procedimiento; no se sobrescribe.',1;

    EXEC sys.sp_executesql N'CREATE PROCEDURE dbo.SP_Pedidos_ProcesarPago
@IdPedido bigint,@ClaveOperacion varbinary(max),@Referencia varchar(max),@Monto decimal(19,4),
@Accion varchar(10),@IdActor bigint=NULL,@IdSesion uniqueidentifier=NULL,@TokenInvitado varbinary(max)=NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    IF @@TRANCOUNT <> 0 OR (2 & @@OPTIONS) = 2 THROW 62001, N''La operación requiere Auto-commit sin transacción externa.'', 1;
    BEGIN TRY
        BEGIN TRANSACTION;
        DECLARE @Bloqueo int;
        EXEC @Bloqueo = sys.sp_getapplock @Resource=N''ShopCart.Negocio'', @LockMode=N''Exclusive'',
             @LockOwner=N''Transaction'', @LockTimeout=10000;
        IF @Bloqueo < 0 THROW 62002, N''No se pudo serializar la operación; reintente la solicitud completa.'', 1;

DECLARE @IdCheckout bigint=(SELECT IdCheckout FROM dbo.Pedidos WHERE IdPedido=@IdPedido);

DECLARE @CarritoPropietario bigint=(SELECT IdCarrito FROM dbo.Checkouts WHERE IdCheckout=@IdCheckout);
IF @CarritoPropietario IS NULL THROW 62700,N''Checkout inexistente.'',1;
DECLARE @IdCarrito bigint=@CarritoPropietario;
IF @IdActor IS NOT NULL BEGIN
 EXEC dbo.SP_Interno_Autorizar @IdActor,@IdSesion,N''USUARIO'';
 IF @TokenInvitado IS NOT NULL THROW 62500,N''Identidad de carrito ambigua.'',1;
 IF NOT EXISTS(SELECT 1 FROM dbo.Carritos WHERE IdCarrito=@IdCarrito AND IdUsuario=@IdActor)
 THROW 62501,N''Carrito no autorizado.'',1;
END ELSE BEGIN
 IF @TokenInvitado IS NULL OR DATALENGTH(@TokenInvitado)<>32 OR @IdSesion IS NOT NULL
 OR NOT EXISTS(SELECT 1 FROM dbo.Carritos WHERE IdCarrito=@IdCarrito AND IdUsuario IS NULL AND TokenInvitadoHash=@TokenInvitado)
 THROW 62501,N''Carrito no autorizado.'',1;
END;
IF @ClaveOperacion IS NULL OR DATALENGTH(@ClaveOperacion)<>32 OR @Referencia IS NULL OR DATALENGTH(@Referencia)>80
OR LEN(LTRIM(RTRIM(@Referencia)))=0 OR DATALENGTH(@Referencia)<>DATALENGTH(LTRIM(RTRIM(@Referencia)))
OR @Accion IS NULL OR @Accion NOT IN (''CREAR'',''APROBAR'',''RECHAZAR'') OR @Monto IS NULL OR @Monto<0
THROW 62800,N''Pago inválido.'',1;
DECLARE @Total decimal(19,4),@EstadoPedido varchar(25),@Expira datetime2(7),@EstadoCheckout varchar(20),@IdCupon bigint;
SELECT @Total=Total,@EstadoPedido=Estado,@IdCupon=IdCupon FROM dbo.Pedidos WITH(UPDLOCK,HOLDLOCK) WHERE IdPedido=@IdPedido;
SELECT @Expira=FechaExpiracionUTC,@EstadoCheckout=Estado FROM dbo.Checkouts WITH(UPDLOCK,HOLDLOCK) WHERE IdCheckout=@IdCheckout;
IF @Monto<>@Total THROW 62801,N''El monto debe coincidir exactamente con el total, incluido cero.'',1;
DECLARE @IdPago bigint,@EstadoPago varchar(20);
SELECT @IdPago=IdPago,@EstadoPago=Estado FROM dbo.Pagos WITH(UPDLOCK,HOLDLOCK) WHERE ClaveIdempotenciaHash=@ClaveOperacion;
IF @IdPago IS NOT NULL BEGIN
 IF NOT EXISTS(SELECT 1 FROM dbo.Pagos WHERE IdPago=@IdPago AND IdPedido=@IdPedido AND Monto=@Monto
 AND ReferenciaPago COLLATE Latin1_General_100_BIN2=@Referencia COLLATE Latin1_General_100_BIN2 AND DATALENGTH(ReferenciaPago)=DATALENGTH(@Referencia))
 THROW 62802,N''Clave de pago reutilizada con contenido distinto.'',1;
 IF @EstadoPago<>''PENDIENTE'' BEGIN
  IF (@Accion=''APROBAR'' AND @EstadoPago<>''APROBADO'') OR (@Accion=''RECHAZAR'' AND @EstadoPago<>''RECHAZADO'')
  THROW 62803,N''La operación ya tiene otro resultado terminal.'',1;
  SELECT IdPago,IdPedido,Estado,Monto,ReferenciaPago,FechaResolucionUTC FROM dbo.Pagos WHERE IdPago=@IdPago; COMMIT TRANSACTION; RETURN;
 END;
END;
IF @EstadoPedido<>''PENDIENTE_PAGO'' OR @EstadoCheckout<>''RESERVADO'' OR @Expira<=SYSUTCDATETIME()
THROW 62804,N''Pedido o checkout no disponible para pago.'',1;
IF @IdPago IS NULL BEGIN
 INSERT dbo.Pagos(IdPedido,ClaveIdempotenciaHash,ReferenciaPago,MetodoPago,Monto)
 VALUES(@IdPedido,@ClaveOperacion,@Referencia,''SIMULADO'',@Monto);
 SET @IdPago=CONVERT(bigint,SCOPE_IDENTITY());
END;
IF @Accion=''CREAR'' BEGIN SELECT IdPago,IdPedido,Estado,Monto,ReferenciaPago,FechaResolucionUTC FROM dbo.Pagos WHERE IdPago=@IdPago; COMMIT TRANSACTION; RETURN; END;
IF @Accion=''RECHAZAR'' BEGIN
 UPDATE dbo.Pagos SET Estado=''RECHAZADO'',CodigoResultado=''SIMULADO_RECHAZADO'',FechaActualizacionUTC=SYSUTCDATETIME(),FechaResolucionUTC=SYSUTCDATETIME()
 WHERE IdPago=@IdPago AND Estado=''PENDIENTE'';
 IF @@ROWCOUNT<>1 THROW 62805,N''Conflicto de pago.'',1;
 INSERT dbo.EventosAuditoria (IdUsuarioActor,Accion,Entidad,IdEntidad,DatosAnteriores,DatosNuevos)
VALUES (@IdActor,N''RECHAZAR'',N''Pagos'',@IdPago,NULL,NULL);

 SELECT IdPago,IdPedido,Estado,Monto,ReferenciaPago,FechaResolucionUTC FROM dbo.Pagos WHERE IdPago=@IdPago; COMMIT TRANSACTION; RETURN;
END;
IF EXISTS(SELECT 1 FROM dbo.Pagos WHERE IdPedido=@IdPedido AND Estado=''APROBADO'')
THROW 62806,N''El pedido ya tiene un pago aprobado.'',1;
IF NOT EXISTS(SELECT 1 FROM dbo.DetallesPedido WHERE IdPedido=@IdPedido)
OR EXISTS(
 SELECT d.IdVariante,d.Cantidad FROM dbo.DetallesPedido d WHERE d.IdPedido=@IdPedido
 EXCEPT SELECT IdVariante,Cantidad FROM dbo.ReservasInventario WHERE IdCheckout=@IdCheckout AND Estado=''ACTIVA'' AND FechaExpiracionUTC>SYSUTCDATETIME())
OR EXISTS(
 SELECT IdVariante,Cantidad FROM dbo.ReservasInventario WHERE IdCheckout=@IdCheckout AND Estado=''ACTIVA''
 EXCEPT SELECT IdVariante,Cantidad FROM dbo.DetallesPedido WHERE IdPedido=@IdPedido)
THROW 62807,N''Reservas incompletas o vencidas.'',1;
IF @IdCupon IS NOT NULL AND NOT EXISTS(SELECT 1 FROM dbo.ReservasCupon WHERE IdCheckout=@IdCheckout
AND IdCupon=@IdCupon AND Estado=''ACTIVA'' AND FechaExpiracionUTC>SYSUTCDATETIME()
AND (IdUsuario=@IdActor OR (IdUsuario IS NULL AND @IdActor IS NULL)))
THROW 62808,N''Reserva de cupón inexistente o vencida.'',1;
IF EXISTS(SELECT 1 FROM dbo.DetallesPedido d JOIN dbo.Existencias e WITH(UPDLOCK,HOLDLOCK) ON e.IdVariante=d.IdVariante
OUTER APPLY(SELECT SUM(CONVERT(bigint,Cantidad)) Cantidad FROM dbo.ReservasInventario
WHERE IdVariante=e.IdVariante AND Estado=''ACTIVA'' AND FechaExpiracionUTC>SYSUTCDATETIME()) r
WHERE d.IdPedido=@IdPedido AND e.CantidadFisica<COALESCE(r.Cantidad,0))
THROW 62809,N''El saldo no respalda las reservas.'',1;
DECLARE @Mov TABLE(IdVariante bigint PRIMARY KEY,Cantidad int,SaldoAnterior int,SaldoPosterior int);
UPDATE e SET CantidadFisica=e.CantidadFisica-d.Cantidad,FechaActualizacionUTC=SYSUTCDATETIME()
OUTPUT inserted.IdVariante,d.Cantidad,deleted.CantidadFisica,inserted.CantidadFisica INTO @Mov
FROM dbo.Existencias e JOIN dbo.DetallesPedido d ON d.IdVariante=e.IdVariante WHERE d.IdPedido=@IdPedido AND e.CantidadFisica>=d.Cantidad;
DECLARE @Afectadas int=@@ROWCOUNT;
IF @Afectadas<>(SELECT COUNT(*) FROM dbo.DetallesPedido WHERE IdPedido=@IdPedido) THROW 62810,N''No se descontaron todas las líneas.'',1;
INSERT dbo.MovimientosInventario(IdVariante,TipoMovimiento,Cantidad,SaldoAnterior,SaldoPosterior,Motivo,IdUsuarioResponsable,TipoReferencia,IdReferencia)
SELECT IdVariante,''SALIDA'',Cantidad,SaldoAnterior,SaldoPosterior,N''Compra simulada'',@IdActor,''VENTA'',@IdPedido FROM @Mov;
DECLARE @Ahora datetime2(7)=SYSUTCDATETIME();
IF @Expira<=@Ahora OR EXISTS(SELECT 1 FROM dbo.ReservasInventario WHERE IdCheckout=@IdCheckout AND Estado=''ACTIVA'' AND FechaExpiracionUTC<=@Ahora)
OR EXISTS(SELECT 1 FROM dbo.ReservasCupon WHERE IdCheckout=@IdCheckout AND Estado=''ACTIVA'' AND FechaExpiracionUTC<=@Ahora)
THROW 62811,N''La reserva venció durante la confirmación.'',1;
UPDATE dbo.ReservasInventario SET Estado=''CONFIRMADA'',FechaActualizacionUTC=@Ahora,FechaResolucionUTC=@Ahora WHERE IdCheckout=@IdCheckout AND Estado=''ACTIVA'';
IF @@ROWCOUNT<>@Afectadas THROW 62812,N''Conflicto al consumir reservas.'',1;
IF @IdCupon IS NOT NULL BEGIN
 UPDATE dbo.ReservasCupon SET Estado=''CONFIRMADA'',FechaActualizacionUTC=@Ahora,FechaResolucionUTC=@Ahora WHERE IdCheckout=@IdCheckout AND IdCupon=@IdCupon AND Estado=''ACTIVA'';
 IF @@ROWCOUNT<>1 THROW 62813,N''Conflicto al consumir cupón.'',1;
 INSERT dbo.UsosCupon(IdCupon,IdPedido,IdUsuario) VALUES(@IdCupon,@IdPedido,@IdActor);
END;
UPDATE dbo.Pagos SET Estado=''APROBADO'',CodigoResultado=''SIMULADO_APROBADO'',FechaActualizacionUTC=@Ahora,FechaResolucionUTC=@Ahora WHERE IdPago=@IdPago AND Estado=''PENDIENTE'';
IF @@ROWCOUNT<>1 THROW 62814,N''Conflicto al aprobar pago.'',1;
UPDATE dbo.Pedidos SET Estado=''PAGADO'',FechaActualizacionUTC=@Ahora WHERE IdPedido=@IdPedido AND Estado=''PENDIENTE_PAGO'';
IF @@ROWCOUNT<>1 THROW 62815,N''Conflicto al confirmar pedido.'',1;
UPDATE dbo.Checkouts SET Estado=''CONFIRMADO'',FechaActualizacionUTC=@Ahora WHERE IdCheckout=@IdCheckout AND Estado=''RESERVADO'';
IF @@ROWCOUNT<>1 THROW 62816,N''Conflicto al confirmar checkout.'',1;
UPDATE dbo.Carritos SET Estado=''CONVERTIDO'',FechaUltimaActividadUTC=@Ahora WHERE IdCarrito=@IdCarrito AND Estado=''ACTIVO'';
IF @@ROWCOUNT<>1 THROW 62817,N''Conflicto al convertir carrito.'',1;
UPDATE dbo.Pagos SET Estado=''CANCELADO'',FechaActualizacionUTC=@Ahora,FechaResolucionUTC=@Ahora WHERE IdPedido=@IdPedido AND IdPago<>@IdPago AND Estado=''PENDIENTE'';
INSERT dbo.HistorialEstadosPedido(IdPedido,EstadoAnterior,EstadoNuevo,IdUsuarioActor) VALUES(@IdPedido,''PENDIENTE_PAGO'',''PAGADO'',@IdActor);
INSERT dbo.EventosAuditoria(IdUsuarioActor,Accion,Entidad,IdEntidad,DatosAnteriores,DatosNuevos)
SELECT @IdActor,''CONSUMIR'',''Existencias'',m.IdVariante,
(SELECT m.SaldoAnterior CantidadFisica FOR JSON PATH,WITHOUT_ARRAY_WRAPPER),
(SELECT m.SaldoPosterior CantidadFisica FOR JSON PATH,WITHOUT_ARRAY_WRAPPER) FROM @Mov m;
INSERT dbo.EventosAuditoria (IdUsuarioActor,Accion,Entidad,IdEntidad,DatosAnteriores,DatosNuevos)
VALUES (@IdActor,N''PAGAR'',N''Pedidos'',@IdPedido,N''{"Estado":"PENDIENTE_PAGO"}'',N''{"Estado":"PAGADO"}'');
INSERT dbo.EventosAuditoria (IdUsuarioActor,Accion,Entidad,IdEntidad,DatosAnteriores,DatosNuevos)
VALUES (@IdActor,N''APROBAR'',N''Pagos'',@IdPago,NULL,NULL);

SELECT IdPago,IdPedido,Estado,Monto,ReferenciaPago,FechaResolucionUTC FROM dbo.Pagos WHERE IdPago=@IdPago;
        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF XACT_STATE() <> 0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH;
END;';

    EXEC sys.sp_executesql N'CREATE PROCEDURE dbo.SP_Pedidos_Consultar
@IdPedido bigint=NULL,@IdActor bigint=NULL,@IdSesion uniqueidentifier=NULL,@TokenInvitado varbinary(max)=NULL,@NumeroPedido varchar(max)=NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;


IF DATALENGTH(@NumeroPedido)>30 THROW 62823,N''Número de pedido inválido.'',1;
IF @IdPedido IS NULL SELECT @IdPedido=IdPedido FROM dbo.Pedidos WHERE NumeroPedido=@NumeroPedido;
IF @NumeroPedido IS NOT NULL AND NOT EXISTS(SELECT 1 FROM dbo.Pedidos WHERE IdPedido=@IdPedido AND NumeroPedido=@NumeroPedido)
THROW 62824,N''Identificador y número no corresponden.'',1;
DECLARE @CarritoPedido bigint=(SELECT c.IdCarrito FROM dbo.Pedidos p JOIN dbo.Checkouts c ON c.IdCheckout=p.IdCheckout WHERE p.IdPedido=@IdPedido);
IF @CarritoPedido IS NULL THROW 62900,N''Pedido inexistente.'',1;
IF @IdActor IS NOT NULL BEGIN
 EXEC dbo.SP_Interno_Autorizar @IdActor,@IdSesion,N''USUARIO'';
 IF @TokenInvitado IS NOT NULL THROW 62901,N''Identidad ambigua.'',1;
 IF NOT EXISTS(SELECT 1 FROM dbo.Pedidos WHERE IdPedido=@IdPedido AND IdUsuario=@IdActor)
 AND NOT EXISTS(SELECT 1 FROM dbo.Usuarios u JOIN dbo.Roles r ON r.IdRol=u.IdRol WHERE u.IdUsuario=@IdActor AND r.Nombre IN(N''Operador'',N''Administrador''))
 THROW 62902,N''Pedido no autorizado.'',1;
END ELSE IF @TokenInvitado IS NULL OR DATALENGTH(@TokenInvitado)<>32 OR @IdSesion IS NOT NULL
OR NOT EXISTS(SELECT 1 FROM dbo.Carritos WHERE IdCarrito=@CarritoPedido AND IdUsuario IS NULL AND TokenInvitadoHash=@TokenInvitado)
THROW 62902,N''Pedido no autorizado.'',1;

SELECT * FROM dbo.Pedidos WHERE IdPedido=@IdPedido;
SELECT * FROM dbo.DetallesPedido WHERE IdPedido=@IdPedido ORDER BY IdVariante;
SELECT IdPago,ReferenciaPago,MetodoPago,Estado,Monto,Moneda,CodigoResultado,MensajeResultado,FechaCreacionUTC,FechaResolucionUTC FROM dbo.Pagos WHERE IdPedido=@IdPedido ORDER BY IdPago;
SELECT IdHistorialEstadoPedido,EstadoAnterior,EstadoNuevo,IdUsuarioActor,Observacion,FechaCambioUTC FROM dbo.HistorialEstadosPedido WHERE IdPedido=@IdPedido ORDER BY FechaCambioUTC,IdHistorialEstadoPedido;
END;';

    EXEC sys.sp_executesql N'CREATE PROCEDURE dbo.SP_Pedidos_Listar
@IdActor bigint,@IdSesion uniqueidentifier,@Administrativo bit=0,@IdUsuario bigint=NULL,
@Estado varchar(25)=NULL,@Desde datetime2(7)=NULL,@Hasta datetime2(7)=NULL,@Pagina int=1,@TamanoPagina int=50
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
EXEC dbo.SP_Interno_Autorizar @IdActor, @IdSesion, N''USUARIO'';

IF @Administrativo IS NULL OR @Pagina IS NULL OR @Pagina<1 OR @TamanoPagina IS NULL OR @TamanoPagina NOT BETWEEN 1 AND 100
OR (@Desde IS NOT NULL AND @Hasta IS NOT NULL AND @Desde>=@Hasta) THROW 62818,N''Filtros inválidos.'',1;
IF @Administrativo=1 EXEC dbo.SP_Interno_Autorizar @IdActor,@IdSesion,N''OPERADOR'';
ELSE SET @IdUsuario=@IdActor;
SELECT IdPedido,NumeroPedido,IdUsuario,Estado,Total,FechaPedidoUTC,COUNT_BIG(*) OVER() TotalFilas FROM dbo.Pedidos
WHERE (@IdUsuario IS NULL OR IdUsuario=@IdUsuario) AND (@Estado IS NULL OR Estado=@Estado)
AND (@Desde IS NULL OR FechaPedidoUTC>=@Desde) AND (@Hasta IS NULL OR FechaPedidoUTC<@Hasta)
ORDER BY FechaPedidoUTC,IdPedido OFFSET ((CONVERT(bigint,@Pagina)-1)*@TamanoPagina) ROWS FETCH NEXT @TamanoPagina ROWS ONLY;
END;';

    EXEC sys.sp_executesql N'CREATE PROCEDURE dbo.SP_Pedidos_CambiarEstado
@IdActor bigint,@IdSesion uniqueidentifier,@IdPedido bigint,@EstadoNuevo varchar(25),@Observacion nvarchar(max)=NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    IF @@TRANCOUNT <> 0 OR (2 & @@OPTIONS) = 2 THROW 62001, N''La operación requiere Auto-commit sin transacción externa.'', 1;
    BEGIN TRY
        BEGIN TRANSACTION;
        DECLARE @Bloqueo int;
        EXEC @Bloqueo = sys.sp_getapplock @Resource=N''ShopCart.Negocio'', @LockMode=N''Exclusive'',
             @LockOwner=N''Transaction'', @LockTimeout=10000;
        IF @Bloqueo < 0 THROW 62002, N''No se pudo serializar la operación; reintente la solicitud completa.'', 1;
EXEC dbo.SP_Interno_Autorizar @IdActor, @IdSesion, N''OPERADOR'';

IF DATALENGTH(@Observacion)>1000 THROW 62819,N''Observación demasiado larga.'',1;
DECLARE @Anterior varchar(25)=(SELECT Estado FROM dbo.Pedidos WITH(UPDLOCK,HOLDLOCK) WHERE IdPedido=@IdPedido);
IF @Anterior IS NULL THROW 62820,N''Pedido inexistente.'',1;
IF @Anterior=@EstadoNuevo BEGIN COMMIT TRANSACTION; RETURN; END;
IF @EstadoNuevo IS NULL OR NOT((@Anterior=''PAGADO'' AND @EstadoNuevo=''EN_PREPARACION'')
OR (@Anterior=''EN_PREPARACION'' AND @EstadoNuevo=''ENVIADO'') OR (@Anterior=''ENVIADO'' AND @EstadoNuevo=''ENTREGADO''))
THROW 62821,N''Transición no permitida; la cancelación requiere su operación específica.'',1;
UPDATE dbo.Pedidos SET Estado=@EstadoNuevo,FechaActualizacionUTC=SYSUTCDATETIME() WHERE IdPedido=@IdPedido AND Estado=@Anterior;
IF @@ROWCOUNT<>1 THROW 62822,N''Conflicto de estado.'',1;
INSERT dbo.HistorialEstadosPedido(IdPedido,EstadoAnterior,EstadoNuevo,IdUsuarioActor,Observacion) VALUES(@IdPedido,@Anterior,@EstadoNuevo,@IdActor,@Observacion);
DECLARE @AntesJSON nvarchar(max)=(SELECT @Anterior Estado FOR JSON PATH,WITHOUT_ARRAY_WRAPPER),@DespuesJSON nvarchar(max)=(SELECT @EstadoNuevo Estado FOR JSON PATH,WITHOUT_ARRAY_WRAPPER);
INSERT dbo.EventosAuditoria (IdUsuarioActor,Accion,Entidad,IdEntidad,DatosAnteriores,DatosNuevos)
VALUES (@IdActor,N''ESTADO'',N''Pedidos'',@IdPedido,@AntesJSON,@DespuesJSON);

        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF XACT_STATE() <> 0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH;
END;';

    EXEC sys.sp_executesql N'
        INSERT dbo.VersionesMigracion ([Version],NombreArchivo,SHA256,FechaAplicacionUTC,Ejecutor)
        VALUES (18,N''018_ProcedimientosPedidosPagos.sql'',@Huella,SYSUTCDATETIME(),ORIGINAL_LOGIN());
    ',N'@Huella varbinary(32)',@Huella=@SHA256;
    COMMIT TRANSACTION;
    PRINT N'Migración 18 completada.';
END TRY
BEGIN CATCH
    IF XACT_STATE() <> 0 ROLLBACK TRANSACTION;
    THROW;
END CATCH;
