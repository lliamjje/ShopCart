/*
    019_ProcedimientosDevoluciones.sql. Ejecutar completo, sin GO, con Auto-commit en ShopCart.
    SHA-256 final: suministrar 32 bytes mediante SESSION_CONTEXT,
    clave ShopCart.Migracion019.SHA256, misma conexión DataGrip.
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
    Completar reintegra mercancía RECIBIDA y fija reembolso pendiente. La resolución monetaria posterior tiene idempotencia propia. Cancelación pagada reintegra y reembolsa en una transacción; cero no genera reembolso.
*/
IF DB_NAME() <> N'ShopCart'
    THROW 62700, N'019 solo puede ejecutarse en la base ShopCart.', 1;

IF @@TRANCOUNT <> 0 OR (2 & @@OPTIONS) = 2
    THROW 62701, N'Inicie con Auto-commit y sin transacciones abiertas o implícitas.', 1;

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
    THROW 62702, N'Se requiere CONTROL sobre ShopCart para inspeccionar y crear el esquema.', 1;

IF NOT EXISTS (
    SELECT 1 FROM sys.databases
    WHERE database_id = DB_ID()
      AND collation_name = N'Latin1_General_100_CI_AI_SC'
      AND recovery_model_desc = N'SIMPLE'
      AND state_desc = N'ONLINE' AND user_access_desc = N'MULTI_USER'
      AND is_read_only = 0 AND source_database_id IS NULL
)
    THROW 62703, N'Las propiedades de ShopCart no coinciden con el arranque 001.', 1;

DECLARE @HuellaRecibida sql_variant = SESSION_CONTEXT(N'ShopCart.Migracion019.SHA256');
IF @HuellaRecibida IS NULL
   OR CONVERT(nvarchar(128), SQL_VARIANT_PROPERTY(@HuellaRecibida, 'BaseType')) NOT IN (N'binary', N'varbinary')
    THROW 62704, N'Suministre el SHA-256 real como valor binario en SESSION_CONTEXT antes de ejecutar 019.', 1;

DECLARE @SHA256 varbinary(max) = CONVERT(varbinary(max), @HuellaRecibida);
IF DATALENGTH(@SHA256) <> 32
    THROW 62705, N'La huella SHA-256 debe contener exactamente 32 bytes.', 1;

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
        THROW 62706, N'No se pudo obtener el bloqueo exclusivo de migraciones.', 1;

    DECLARE @IDVersiones int = OBJECT_ID(N'dbo.VersionesMigracion', N'U');
    IF @IDVersiones IS NULL
        THROW 62707, N'Falta la tabla técnica creada por 001. No se aplicará 019.', 1;

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
        THROW 62708, N'Las columnas de VersionesMigracion no cumplen el contrato de 001.', 1;

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
        THROW 62709, N'VersionesMigracion requiere la PK clustered de 001 sobre Version.', 1;

    IF EXISTS (SELECT 1 FROM sys.triggers WHERE parent_id = @IDVersiones)
       OR EXISTS (SELECT 1 FROM sys.tables WHERE object_id = @IDVersiones
                  AND (temporal_type <> 0 OR is_memory_optimized = 1))
        THROW 62710, N'VersionesMigracion tiene características inesperadas; revisar manualmente.', 1;

    -- Lote inferior: errores de compilación/resolución quedan dentro del TRY externo.
    EXEC sys.sp_executesql N'
        IF NOT EXISTS (
            SELECT 1 FROM dbo.VersionesMigracion WITH (UPDLOCK, HOLDLOCK)
            WHERE [Version] = 18 AND NombreArchivo = N''018_ProcedimientosPedidosPagos.sql''
        )
            THROW 62713, N''Debe estar registrada la migración 018_ProcedimientosPedidosPagos.sql antes de aplicar 019.'', 1;
        IF EXISTS (SELECT 1 FROM dbo.VersionesMigracion WITH (UPDLOCK, HOLDLOCK)
                   WHERE [Version] >= 19)
            THROW 62711, N''019 o una migración posterior ya está registrada. No se reaplica ni se certifica el esquema existente.'', 1;
    ';


    -- Rechaza nombres conflictivos antes de crear el primer procedimiento.
    IF OBJECT_ID(N'dbo.SP_Devoluciones_Solicitar') IS NOT NULL THROW 62750, N'Ya existe un objeto de procedimiento; no se sobrescribe.',1;
    IF OBJECT_ID(N'dbo.SP_Devoluciones_CambiarEstado') IS NOT NULL THROW 62750, N'Ya existe un objeto de procedimiento; no se sobrescribe.',1;
    IF OBJECT_ID(N'dbo.SP_Devoluciones_Completar') IS NOT NULL THROW 62750, N'Ya existe un objeto de procedimiento; no se sobrescribe.',1;
    IF OBJECT_ID(N'dbo.SP_Devoluciones_ProcesarReembolso') IS NOT NULL THROW 62750, N'Ya existe un objeto de procedimiento; no se sobrescribe.',1;
    IF OBJECT_ID(N'dbo.SP_Pedidos_Cancelar') IS NOT NULL THROW 62750, N'Ya existe un objeto de procedimiento; no se sobrescribe.',1;
    IF OBJECT_ID(N'dbo.SP_Devoluciones_Consultar') IS NOT NULL THROW 62750, N'Ya existe un objeto de procedimiento; no se sobrescribe.',1;
    IF OBJECT_ID(N'dbo.SP_Devoluciones_Listar') IS NOT NULL THROW 62750, N'Ya existe un objeto de procedimiento; no se sobrescribe.',1;

    EXEC sys.sp_executesql N'CREATE PROCEDURE dbo.SP_Devoluciones_Solicitar
@IdPedido bigint,@Lineas nvarchar(max),@Motivo nvarchar(max),@IdOperacion uniqueidentifier,
@IdDevolucion bigint=NULL,@IdActor bigint=NULL,@IdSesion uniqueidentifier=NULL,@TokenInvitado varbinary(max)=NULL
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
IF @Motivo IS NULL OR LEN(LTRIM(RTRIM(@Motivo)))=0 OR DATALENGTH(@Motivo)>1000
THROW 62003,N''Texto obligatorio vacío o longitud no válida.'',1;

IF @IdOperacion IS NULL OR ISJSON(@Lineas)<>1 OR LEFT(LTRIM(@Lineas),1)<>N''['' THROW 62903,N''Solicitud inválida.'',1;
DECLARE @L TABLE(IdDetallePedido bigint PRIMARY KEY,Cantidad int NOT NULL);
INSERT @L SELECT IdDetallePedido,Cantidad FROM OPENJSON(@Lineas) WITH(IdDetallePedido bigint ''$.IdDetallePedido'',Cantidad int ''$.Cantidad'');
IF NOT EXISTS(SELECT 1 FROM @L) OR EXISTS(SELECT 1 FROM @L WHERE IdDetallePedido IS NULL OR Cantidad<=0)
THROW 62904,N''Líneas inválidas.'',1;
DECLARE @Canon nvarchar(max)=(SELECT IdDetallePedido,Cantidad FROM @L ORDER BY IdDetallePedido FOR JSON PATH);
DECLARE @Huella varchar(64)=CONVERT(varchar(64),HASHBYTES(''SHA2_256'',CONCAT(@IdPedido,N''|'',COALESCE(CONVERT(nvarchar(20),@IdDevolucion),N''NUEVA''),N''|'',@Motivo,N''|'',@Canon)),2);
DECLARE @Anterior bigint=(SELECT TOP(1) IdEntidad FROM dbo.EventosAuditoria WHERE IdCorrelacion=@IdOperacion AND Entidad=''Devoluciones'' AND Accion=''SOLICITAR'' ORDER BY IdEventoAuditoria);
IF @Anterior IS NOT NULL BEGIN
 IF NOT EXISTS(SELECT 1 FROM dbo.EventosAuditoria WHERE IdCorrelacion=@IdOperacion AND Entidad=''Devoluciones'' AND Accion=''SOLICITAR''
 AND JSON_VALUE(DatosNuevos,''$.HuellaSolicitud'')=@Huella) THROW 62905,N''Clave de solicitud reutilizada con otro contenido.'',1;
 SELECT @Anterior IdDevolucion; COMMIT TRANSACTION; RETURN;
END;
IF NOT EXISTS(SELECT 1 FROM dbo.Pedidos WITH(UPDLOCK,HOLDLOCK) WHERE IdPedido=@IdPedido AND Estado=''ENTREGADO'')
THROW 62906,N''Solo se devuelven pedidos entregados.'',1;
IF @IdDevolucion IS NOT NULL AND NOT EXISTS(SELECT 1 FROM dbo.Devoluciones WHERE IdDevolucion=@IdDevolucion AND IdPedido=@IdPedido AND Estado=''SOLICITADA'')
THROW 62907,N''Solicitud no editable.'',1;
IF EXISTS(SELECT 1 FROM @L l LEFT JOIN dbo.DetallesPedido d ON d.IdDetallePedido=l.IdDetallePedido AND d.IdPedido=@IdPedido
OUTER APPLY(SELECT SUM(CONVERT(bigint,dd.Cantidad)) Cantidad FROM dbo.DetallesDevolucion dd JOIN dbo.Devoluciones de ON de.IdDevolucion=dd.IdDevolucion
WHERE dd.IdDetallePedido=l.IdDetallePedido AND de.Estado IN(''SOLICITADA'',''APROBADA'',''RECIBIDA'',''COMPLETADA'')) ocupada
WHERE d.IdDetallePedido IS NULL OR CONVERT(bigint,l.Cantidad)+COALESCE(ocupada.Cantidad,0)>d.Cantidad)
THROW 62908,N''Cantidad solicitada superior a la capacidad devolvible.'',1;
IF @IdDevolucion IS NULL BEGIN
 INSERT dbo.Devoluciones(IdPedido,IdUsuarioSolicitante,Motivo) VALUES(@IdPedido,@IdActor,LTRIM(RTRIM(@Motivo)));
 SET @IdDevolucion=CONVERT(bigint,SCOPE_IDENTITY());
END;
-- Agregar solo líneas nuevas; la UNIQUE rechaza una línea repetida en la misma solicitud.
INSERT dbo.DetallesDevolucion(IdDevolucion,IdDetallePedido,Cantidad) SELECT @IdDevolucion,IdDetallePedido,Cantidad FROM @L;
UPDATE dbo.Devoluciones SET FechaActualizacionUTC=SYSUTCDATETIME() WHERE IdDevolucion=@IdDevolucion;
DECLARE @Datos nvarchar(max)=(SELECT @Huella HuellaSolicitud FOR JSON PATH,WITHOUT_ARRAY_WRAPPER);
INSERT dbo.EventosAuditoria(IdUsuarioActor,Accion,Entidad,IdEntidad,DatosNuevos,IdCorrelacion)
VALUES(@IdActor,''SOLICITAR'',''Devoluciones'',@IdDevolucion,@Datos,@IdOperacion);
SELECT @IdDevolucion IdDevolucion;
        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF XACT_STATE() <> 0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH;
END;';

    EXEC sys.sp_executesql N'CREATE PROCEDURE dbo.SP_Devoluciones_CambiarEstado
@IdDevolucion bigint,@EstadoNuevo varchar(25),@Observacion nvarchar(max)=NULL,
@IdActor bigint=NULL,@IdSesion uniqueidentifier=NULL,@TokenInvitado varbinary(max)=NULL
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
DECLARE @IdPedido bigint=(SELECT IdPedido FROM dbo.Devoluciones WHERE IdDevolucion=@IdDevolucion);

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

IF DATALENGTH(@Observacion)>2000 OR @EstadoNuevo IS NULL OR @EstadoNuevo NOT IN (''APROBADA'',''RECHAZADA'',''RECIBIDA'',''CANCELADA'')
THROW 62909,N''Transición u observación inválida.'',1;
IF @EstadoNuevo<>''CANCELADA'' EXEC dbo.SP_Interno_Autorizar @IdActor,@IdSesion,N''OPERADOR'';
DECLARE @Anterior varchar(25)=(SELECT Estado FROM dbo.Devoluciones WITH(UPDLOCK,HOLDLOCK) WHERE IdDevolucion=@IdDevolucion);
IF @Anterior=@EstadoNuevo BEGIN COMMIT TRANSACTION; RETURN; END;
IF NOT((@Anterior=''SOLICITADA'' AND @EstadoNuevo IN(''APROBADA'',''RECHAZADA'',''CANCELADA''))
OR (@Anterior=''APROBADA'' AND @EstadoNuevo IN(''RECIBIDA'',''CANCELADA''))) THROW 62910,N''Transición de devolución no permitida.'',1;
UPDATE dbo.Devoluciones SET Estado=@EstadoNuevo,Observaciones=@Observacion,FechaActualizacionUTC=SYSUTCDATETIME(),
FechaResolucionUTC=CASE WHEN @EstadoNuevo IN(''RECHAZADA'',''CANCELADA'') THEN SYSUTCDATETIME() ELSE NULL END
WHERE IdDevolucion=@IdDevolucion AND Estado=@Anterior;
IF @@ROWCOUNT<>1 THROW 62911,N''Conflicto de devolución.'',1;
DECLARE @Antes nvarchar(max)=(SELECT @Anterior Estado FOR JSON PATH,WITHOUT_ARRAY_WRAPPER),@Despues nvarchar(max)=(SELECT @EstadoNuevo Estado FOR JSON PATH,WITHOUT_ARRAY_WRAPPER);
INSERT dbo.EventosAuditoria (IdUsuarioActor,Accion,Entidad,IdEntidad,DatosAnteriores,DatosNuevos)
VALUES (@IdActor,N''ESTADO'',N''Devoluciones'',@IdDevolucion,@Antes,@Despues);

        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF XACT_STATE() <> 0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH;
END;';

    EXEC sys.sp_executesql N'CREATE PROCEDURE dbo.SP_Devoluciones_Completar
@IdActor bigint,@IdSesion uniqueidentifier,@IdDevolucion bigint,@ClaveReembolso varbinary(max)=NULL,@Referencia varchar(max)=NULL
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

DECLARE @IdPedido bigint,@Estado varchar(25);
SELECT @IdPedido=IdPedido,@Estado=Estado FROM dbo.Devoluciones WITH(UPDLOCK,HOLDLOCK) WHERE IdDevolucion=@IdDevolucion;
IF @Estado=''COMPLETADA'' BEGIN
 IF EXISTS(SELECT 1 FROM dbo.Reembolsos WHERE IdDevolucion=@IdDevolucion)
 AND NOT EXISTS(SELECT 1 FROM dbo.Reembolsos WHERE IdDevolucion=@IdDevolucion AND ClaveIdempotenciaHash=@ClaveReembolso
 AND ReferenciaReembolso COLLATE Latin1_General_100_BIN2=@Referencia COLLATE Latin1_General_100_BIN2 AND DATALENGTH(ReferenciaReembolso)=DATALENGTH(@Referencia))
 THROW 62938,N''Devolución ya completada con otra operación monetaria.'',1;
 SELECT @IdDevolucion IdDevolucion,COALESCE((SELECT MAX(Monto) FROM dbo.Reembolsos WHERE IdDevolucion=@IdDevolucion),CONVERT(decimal(19,4),0)) MontoReembolsable;
 SELECT IdReembolso,Estado,Monto FROM dbo.Reembolsos WHERE IdDevolucion=@IdDevolucion ORDER BY IdReembolso;
 COMMIT TRANSACTION; RETURN;
END;
IF @Estado IS NULL OR @Estado<>''RECIBIDA'' THROW 62912,N''La devolución debe recibirse antes de completarse.'',1;
IF EXISTS(SELECT 1 FROM dbo.DetallesDevolucion dd JOIN dbo.DetallesPedido dp ON dp.IdDetallePedido=dd.IdDetallePedido
WHERE dd.IdDevolucion=@IdDevolucion AND dp.IdPedido<>@IdPedido) THROW 62913,N''Detalle de otro pedido.'',1;

IF EXISTS(SELECT 1 FROM dbo.DetallesDevolucion dd JOIN dbo.DetallesPedido dp ON dp.IdDetallePedido=dd.IdDetallePedido
OUTER APPLY(SELECT SUM(CONVERT(bigint,x.Cantidad)) Cantidad FROM dbo.DetallesDevolucion x
JOIN dbo.Devoluciones de ON de.IdDevolucion=x.IdDevolucion WHERE x.IdDetallePedido=dp.IdDetallePedido
AND de.Estado IN(''SOLICITADA'',''APROBADA'',''RECIBIDA'',''COMPLETADA'')) ocupada
WHERE dd.IdDevolucion=@IdDevolucion AND ocupada.Cantidad>dp.Cantidad)
THROW 62939,N''Las cantidades acumuladas exceden la compra original.'',1;
DECLARE @Monto decimal(19,4);
-- Diferencias de acumulaciones redondeadas: la suma de devoluciones completas
-- coincide exactamente con TotalLinea y nunca devuelve el envío automáticamente.
SELECT @Monto=SUM(CONVERT(decimal(25,4),
CONVERT(decimal(19,0),
 ((n.Nuevo-n.Nuevo%dp.Cantidad)/dp.Cantidad + CASE WHEN (n.Nuevo%dp.Cantidad)*2>=dp.Cantidad THEN 1 ELSE 0 END)
-((n.Anterior-n.Anterior%dp.Cantidad)/dp.Cantidad + CASE WHEN (n.Anterior%dp.Cantidad)*2>=dp.Cantidad THEN 1 ELSE 0 END)
)/10000.0))
FROM dbo.DetallesDevolucion dd JOIN dbo.DetallesPedido dp ON dp.IdDetallePedido=dd.IdDetallePedido
OUTER APPLY(SELECT SUM(CONVERT(bigint,x.Cantidad)) Cantidad FROM dbo.DetallesDevolucion x
JOIN dbo.Devoluciones de ON de.IdDevolucion=x.IdDevolucion WHERE x.IdDetallePedido=dd.IdDetallePedido AND de.Estado=''COMPLETADA'') prev
CROSS APPLY(SELECT CONVERT(decimal(19,0),dp.TotalLinea*10000)*
 CONVERT(decimal(10,0),COALESCE(prev.Cantidad,0)+dd.Cantidad) Nuevo,
 CONVERT(decimal(19,0),dp.TotalLinea*10000)*CONVERT(decimal(10,0),COALESCE(prev.Cantidad,0)) Anterior) n
WHERE dd.IdDevolucion=@IdDevolucion;
IF @Monto IS NULL OR @Monto<0 THROW 62914,N''No hay líneas válidas para completar.'',1;
DECLARE @IdPago bigint,@Pagado decimal(19,4);
SELECT @IdPago=IdPago,@Pagado=Monto FROM dbo.Pagos WITH(UPDLOCK,HOLDLOCK) WHERE IdPedido=@IdPedido AND Estado=''APROBADO'';
IF @IdPago IS NULL THROW 62915,N''Falta el pago original aprobado.'',1;
DECLARE @Comprometido decimal(25,4)=
CONVERT(decimal(24,4),COALESCE((SELECT SUM(CONVERT(decimal(23,4),Monto)) FROM dbo.Reembolsos WHERE IdPago=@IdPago AND Estado IN(''PENDIENTE'',''APROBADO'')),0))
+CONVERT(decimal(24,4),COALESCE((SELECT SUM(CONVERT(decimal(23,4),Monto)) FROM dbo.ReembolsosCancelacion WHERE IdPago=@IdPago AND Estado IN(''PENDIENTE'',''APROBADO'')),0));
IF @Comprometido+@Monto>@Pagado THROW 62916,N''El reembolso excede el cobro restante.'',1;
IF @Monto>0 AND (@ClaveReembolso IS NULL OR DATALENGTH(@ClaveReembolso)<>32 OR @Referencia IS NULL OR DATALENGTH(@Referencia)>80
OR LEN(LTRIM(RTRIM(@Referencia)))=0 OR DATALENGTH(@Referencia)<>DATALENGTH(LTRIM(RTRIM(@Referencia))))
THROW 62917,N''Clave o referencia de reembolso inválida.'',1;
DECLARE @Mov TABLE(IdVariante bigint PRIMARY KEY,Cantidad int,Anterior int,Posterior int);
IF EXISTS(SELECT 1 FROM dbo.DetallesDevolucion dd JOIN dbo.DetallesPedido dp ON dp.IdDetallePedido=dd.IdDetallePedido
JOIN dbo.Existencias e WITH(UPDLOCK,HOLDLOCK) ON e.IdVariante=dp.IdVariante
WHERE dd.IdDevolucion=@IdDevolucion AND CONVERT(bigint,e.CantidadFisica)+dd.Cantidad>2147483647)
THROW 62918,N''El reintegro excede el saldo permitido.'',1;
UPDATE e SET CantidadFisica=e.CantidadFisica+dd.Cantidad,FechaActualizacionUTC=SYSUTCDATETIME()
OUTPUT inserted.IdVariante,dd.Cantidad,deleted.CantidadFisica,inserted.CantidadFisica INTO @Mov
FROM dbo.Existencias e JOIN dbo.DetallesPedido dp ON dp.IdVariante=e.IdVariante
JOIN dbo.DetallesDevolucion dd ON dd.IdDetallePedido=dp.IdDetallePedido WHERE dd.IdDevolucion=@IdDevolucion;
IF @@ROWCOUNT<>(SELECT COUNT(*) FROM dbo.DetallesDevolucion WHERE IdDevolucion=@IdDevolucion) THROW 62919,N''Reintegro incompleto.'',1;
INSERT dbo.MovimientosInventario(IdVariante,TipoMovimiento,Cantidad,SaldoAnterior,SaldoPosterior,Motivo,IdUsuarioResponsable,TipoReferencia,IdReferencia)
SELECT IdVariante,''DEVOLUCION'',Cantidad,Anterior,Posterior,N''Devolución recibida'',@IdActor,''DEVOLUCION'',@IdDevolucion FROM @Mov;
IF @Monto>0 INSERT dbo.Reembolsos(IdDevolucion,IdPago,ClaveIdempotenciaHash,ReferenciaReembolso,Monto)
VALUES(@IdDevolucion,@IdPago,@ClaveReembolso,@Referencia,@Monto);
UPDATE dbo.Devoluciones SET Estado=''COMPLETADA'',FechaActualizacionUTC=SYSUTCDATETIME(),FechaResolucionUTC=SYSUTCDATETIME()
WHERE IdDevolucion=@IdDevolucion AND Estado=''RECIBIDA'';
IF @@ROWCOUNT<>1 THROW 62920,N''Conflicto al completar.'',1;
INSERT dbo.EventosAuditoria(IdUsuarioActor,Accion,Entidad,IdEntidad,DatosAnteriores,DatosNuevos) SELECT @IdActor,''REINTEGRAR'',''Existencias'',m.IdVariante,
(SELECT m.Anterior CantidadFisica FOR JSON PATH,WITHOUT_ARRAY_WRAPPER),(SELECT m.Posterior CantidadFisica FOR JSON PATH,WITHOUT_ARRAY_WRAPPER) FROM @Mov m;
INSERT dbo.EventosAuditoria (IdUsuarioActor,Accion,Entidad,IdEntidad,DatosAnteriores,DatosNuevos)
VALUES (@IdActor,N''COMPLETAR'',N''Devoluciones'',@IdDevolucion,NULL,NULL);

SELECT @IdDevolucion IdDevolucion,@Monto MontoReembolsable;
SELECT IdReembolso,Estado,Monto FROM dbo.Reembolsos WHERE IdDevolucion=@IdDevolucion ORDER BY IdReembolso;
        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF XACT_STATE() <> 0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH;
END;';

    EXEC sys.sp_executesql N'CREATE PROCEDURE dbo.SP_Devoluciones_ProcesarReembolso
@IdActor bigint,@IdSesion uniqueidentifier,@IdDevolucion bigint,
@ClaveOperacion varbinary(max),@Referencia varchar(max),@Accion varchar(10)
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

IF @ClaveOperacion IS NULL OR DATALENGTH(@ClaveOperacion)<>32 OR @Referencia IS NULL OR DATALENGTH(@Referencia)>80
OR LEN(LTRIM(RTRIM(@Referencia)))=0 OR DATALENGTH(@Referencia)<>DATALENGTH(LTRIM(RTRIM(@Referencia)))
OR @Accion IS NULL OR @Accion NOT IN(''CREAR'',''APROBAR'',''RECHAZAR'') THROW 62921,N''Operación de reembolso inválida.'',1;
IF NOT EXISTS(SELECT 1 FROM dbo.Devoluciones WHERE IdDevolucion=@IdDevolucion AND Estado=''COMPLETADA'') THROW 62922,N''Devolución no completada.'',1;
DECLARE @IdPedido bigint=(SELECT IdPedido FROM dbo.Devoluciones WHERE IdDevolucion=@IdDevolucion),
@IdPago bigint,@Pagado decimal(19,4),@Monto decimal(19,4);
SELECT @IdPago=IdPago,@Pagado=Monto FROM dbo.Pagos WITH(UPDLOCK,HOLDLOCK) WHERE IdPedido=@IdPedido AND Estado=''APROBADO'';
-- El importe autorizado se fijó al completar y quedó persistido en el primer intento.
SELECT @Monto=MAX(Monto) FROM dbo.Reembolsos WHERE IdDevolucion=@IdDevolucion;
IF @IdPago IS NULL OR @Monto IS NULL OR @Monto<=0 THROW 62923,N''No hay operación monetaria autorizada.'',1;
DECLARE @IdReembolso bigint,@Estado varchar(20);
SELECT @IdReembolso=IdReembolso,@Estado=Estado FROM dbo.Reembolsos WHERE ClaveIdempotenciaHash=@ClaveOperacion;
IF @IdReembolso IS NOT NULL AND NOT EXISTS(SELECT 1 FROM dbo.Reembolsos WHERE IdReembolso=@IdReembolso AND IdDevolucion=@IdDevolucion AND IdPago=@IdPago AND Monto=@Monto
AND ReferenciaReembolso COLLATE Latin1_General_100_BIN2=@Referencia COLLATE Latin1_General_100_BIN2 AND DATALENGTH(ReferenciaReembolso)=DATALENGTH(@Referencia))
THROW 62924,N''Clave de reembolso reutilizada con otro contenido.'',1;
IF @IdReembolso IS NOT NULL AND @Estado<>''PENDIENTE'' BEGIN
 IF (@Accion=''APROBAR'' AND @Estado<>''APROBADO'') OR (@Accion=''RECHAZAR'' AND @Estado<>''RECHAZADO'') THROW 62925,N''Reembolso resuelto con otro resultado.'',1;
 SELECT @IdReembolso IdReembolso,@Estado Estado; COMMIT TRANSACTION; RETURN;
END;
IF EXISTS(SELECT 1 FROM dbo.Reembolsos WHERE IdDevolucion=@IdDevolucion AND Estado IN(''PENDIENTE'',''APROBADO'') AND (@IdReembolso IS NULL OR IdReembolso<>@IdReembolso))
THROW 62926,N''Ya existe un reembolso aprobado o pendiente para esta devolución.'',1;
DECLARE @Otros decimal(25,4)=CONVERT(decimal(24,4),COALESCE((SELECT SUM(CONVERT(decimal(23,4),Monto)) FROM dbo.Reembolsos WHERE IdPago=@IdPago AND Estado IN(''PENDIENTE'',''APROBADO'') AND (@IdReembolso IS NULL OR IdReembolso<>@IdReembolso)),0))
+CONVERT(decimal(24,4),COALESCE((SELECT SUM(CONVERT(decimal(23,4),Monto)) FROM dbo.ReembolsosCancelacion WHERE IdPago=@IdPago AND Estado IN(''PENDIENTE'',''APROBADO'')),0));
IF @Otros+@Monto>@Pagado THROW 62927,N''Capacidad de reembolso insuficiente.'',1;
IF @IdReembolso IS NULL BEGIN
 INSERT dbo.Reembolsos(IdDevolucion,IdPago,ClaveIdempotenciaHash,ReferenciaReembolso,Monto) VALUES(@IdDevolucion,@IdPago,@ClaveOperacion,@Referencia,@Monto);
 SET @IdReembolso=CONVERT(bigint,SCOPE_IDENTITY());
END;
IF @Accion<>''CREAR'' BEGIN
 UPDATE dbo.Reembolsos SET Estado=CASE WHEN @Accion=''APROBAR'' THEN ''APROBADO'' ELSE ''RECHAZADO'' END,
 CodigoResultado=CASE WHEN @Accion=''APROBAR'' THEN ''SIMULADO_APROBADO'' ELSE ''SIMULADO_RECHAZADO'' END,
 FechaActualizacionUTC=SYSUTCDATETIME(),FechaResolucionUTC=SYSUTCDATETIME() WHERE IdReembolso=@IdReembolso AND Estado=''PENDIENTE'';
 IF @@ROWCOUNT<>1 THROW 62928,N''Conflicto de reembolso.'',1;
END;
INSERT dbo.EventosAuditoria (IdUsuarioActor,Accion,Entidad,IdEntidad,DatosAnteriores,DatosNuevos)
VALUES (@IdActor,N''PROCESAR'',N''Reembolsos'',@IdReembolso,NULL,NULL);
SELECT IdReembolso,Estado,Monto FROM dbo.Reembolsos WHERE IdReembolso=@IdReembolso;
        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF XACT_STATE() <> 0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH;
END;';

    EXEC sys.sp_executesql N'CREATE PROCEDURE dbo.SP_Pedidos_Cancelar
@IdPedido bigint,@ClaveReembolso varbinary(max)=NULL,@Referencia varchar(max)=NULL,
@IdActor bigint=NULL,@IdSesion uniqueidentifier=NULL,@TokenInvitado varbinary(max)=NULL
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

DECLARE @Anterior varchar(25),@IdCheckout bigint,@IdPago bigint,@Monto decimal(19,4);
SELECT @Anterior=Estado,@IdCheckout=IdCheckout FROM dbo.Pedidos WITH(UPDLOCK,HOLDLOCK) WHERE IdPedido=@IdPedido;
IF @Anterior=''CANCELADO'' BEGIN
 IF EXISTS(SELECT 1 FROM dbo.ReembolsosCancelacion WHERE IdPedido=@IdPedido)
 AND NOT EXISTS(SELECT 1 FROM dbo.ReembolsosCancelacion WHERE IdPedido=@IdPedido AND ClaveIdempotenciaHash=@ClaveReembolso
 AND ReferenciaReembolso COLLATE Latin1_General_100_BIN2=@Referencia COLLATE Latin1_General_100_BIN2 AND DATALENGTH(ReferenciaReembolso)=DATALENGTH(@Referencia))
 THROW 62929,N''Cancelación ya registrada con otra operación.'',1;
 SELECT @IdPedido IdPedido,''CANCELADO'' Estado;
 SELECT IdReembolsoCancelacion,Estado,Monto FROM dbo.ReembolsosCancelacion WHERE IdPedido=@IdPedido;
 COMMIT TRANSACTION; RETURN;
END;
IF @Anterior NOT IN(''PENDIENTE_PAGO'',''PAGADO'',''EN_PREPARACION'') THROW 62930,N''Pedido ya enviado o no cancelable.'',1;
IF @Anterior<>''PENDIENTE_PAGO'' BEGIN
 SELECT @IdPago=IdPago,@Monto=Monto FROM dbo.Pagos WITH(UPDLOCK,HOLDLOCK) WHERE IdPedido=@IdPedido AND Estado=''APROBADO'';
 IF @IdPago IS NULL THROW 62931,N''Pedido sin pago aprobado.'',1;
 IF EXISTS(SELECT 1 FROM dbo.Reembolsos WHERE IdPago=@IdPago AND Estado IN(''PENDIENTE'',''APROBADO''))
 OR EXISTS(SELECT 1 FROM dbo.ReembolsosCancelacion WHERE IdPago=@IdPago AND Estado IN(''PENDIENTE'',''APROBADO'')) THROW 62932,N''Ya existen reembolsos que comprometen el pago.'',1;
 IF @Monto>0 BEGIN
 IF @ClaveReembolso IS NULL OR DATALENGTH(@ClaveReembolso)<>32 OR @Referencia IS NULL OR DATALENGTH(@Referencia)>80
 OR LEN(LTRIM(RTRIM(@Referencia)))=0 OR DATALENGTH(@Referencia)<>DATALENGTH(LTRIM(RTRIM(@Referencia)))
 THROW 62933,N''Referencia de cancelación inválida.'',1;
 INSERT dbo.ReembolsosCancelacion(IdPedido,IdPago,ClaveIdempotenciaHash,ReferenciaReembolso,Monto,Estado,CodigoResultado,FechaResolucionUTC)
 VALUES(@IdPedido,@IdPago,@ClaveReembolso,@Referencia,@Monto,''APROBADO'',''SIMULADO_APROBADO'',SYSUTCDATETIME());
 END;
 DECLARE @Mov TABLE(IdVariante bigint PRIMARY KEY,Cantidad int,Anterior int,Posterior int);
 IF EXISTS(SELECT 1 FROM dbo.DetallesPedido d JOIN dbo.Existencias e WITH(UPDLOCK,HOLDLOCK) ON e.IdVariante=d.IdVariante WHERE d.IdPedido=@IdPedido AND CONVERT(bigint,e.CantidadFisica)+d.Cantidad>2147483647)
 THROW 62934,N''Reintegro fuera de rango.'',1;
 UPDATE e SET CantidadFisica=e.CantidadFisica+d.Cantidad,FechaActualizacionUTC=SYSUTCDATETIME()
 OUTPUT inserted.IdVariante,d.Cantidad,deleted.CantidadFisica,inserted.CantidadFisica INTO @Mov
 FROM dbo.Existencias e JOIN dbo.DetallesPedido d ON d.IdVariante=e.IdVariante WHERE d.IdPedido=@IdPedido;
 IF @@ROWCOUNT<>(SELECT COUNT(*) FROM dbo.DetallesPedido WHERE IdPedido=@IdPedido) THROW 62935,N''Reintegro incompleto.'',1;
 INSERT dbo.MovimientosInventario(IdVariante,TipoMovimiento,Cantidad,SaldoAnterior,SaldoPosterior,Motivo,IdUsuarioResponsable,TipoReferencia,IdReferencia)
 SELECT IdVariante,''DEVOLUCION'',Cantidad,Anterior,Posterior,N''Cancelación de pedido'',@IdActor,''CANCELACION'',@IdPedido FROM @Mov;
 INSERT dbo.EventosAuditoria(IdUsuarioActor,Accion,Entidad,IdEntidad,DatosAnteriores,DatosNuevos) SELECT @IdActor,''REINTEGRAR_CANCELACION'',''Existencias'',m.IdVariante,
(SELECT m.Anterior CantidadFisica FOR JSON PATH,WITHOUT_ARRAY_WRAPPER),(SELECT m.Posterior CantidadFisica FOR JSON PATH,WITHOUT_ARRAY_WRAPPER) FROM @Mov m;
END;
UPDATE dbo.ReservasInventario SET Estado=''LIBERADA'',FechaActualizacionUTC=SYSUTCDATETIME(),FechaResolucionUTC=SYSUTCDATETIME() WHERE IdCheckout=@IdCheckout AND Estado=''ACTIVA'';
UPDATE dbo.ReservasCupon SET Estado=''LIBERADA'',FechaActualizacionUTC=SYSUTCDATETIME(),FechaResolucionUTC=SYSUTCDATETIME() WHERE IdCheckout=@IdCheckout AND Estado=''ACTIVA'';
UPDATE dbo.Checkouts SET Estado=''CANCELADO'',FechaActualizacionUTC=SYSUTCDATETIME() WHERE IdCheckout=@IdCheckout AND Estado IN(''INICIADO'',''RESERVADO'');
UPDATE dbo.Pagos SET Estado=''CANCELADO'',FechaActualizacionUTC=SYSUTCDATETIME(),FechaResolucionUTC=SYSUTCDATETIME() WHERE IdPedido=@IdPedido AND Estado=''PENDIENTE'';
UPDATE dbo.Pedidos SET Estado=''CANCELADO'',FechaActualizacionUTC=SYSUTCDATETIME() WHERE IdPedido=@IdPedido AND Estado=@Anterior;
IF @@ROWCOUNT<>1 THROW 62936,N''Conflicto de cancelación.'',1;
INSERT dbo.HistorialEstadosPedido(IdPedido,EstadoAnterior,EstadoNuevo,IdUsuarioActor) VALUES(@IdPedido,@Anterior,''CANCELADO'',@IdActor);
INSERT dbo.EventosAuditoria (IdUsuarioActor,Accion,Entidad,IdEntidad,DatosAnteriores,DatosNuevos)
VALUES (@IdActor,N''CANCELAR'',N''Pedidos'',@IdPedido,
(SELECT @Anterior Estado FOR JSON PATH,WITHOUT_ARRAY_WRAPPER),N''{"Estado":"CANCELADO"}'');

SELECT @IdPedido IdPedido,''CANCELADO'' Estado;
SELECT IdReembolsoCancelacion,Estado,Monto FROM dbo.ReembolsosCancelacion WHERE IdPedido=@IdPedido;
        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF XACT_STATE() <> 0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH;
END;';

    EXEC sys.sp_executesql N'CREATE PROCEDURE dbo.SP_Devoluciones_Consultar
@IdPedido bigint,@IdActor bigint=NULL,@IdSesion uniqueidentifier=NULL,@TokenInvitado varbinary(max)=NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

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

SELECT * FROM dbo.Devoluciones WHERE IdPedido=@IdPedido ORDER BY FechaSolicitudUTC,IdDevolucion;
SELECT dd.* FROM dbo.DetallesDevolucion dd JOIN dbo.Devoluciones d ON d.IdDevolucion=dd.IdDevolucion WHERE d.IdPedido=@IdPedido ORDER BY dd.IdDevolucion,dd.IdDetallePedido;
SELECT r.IdReembolso,r.IdDevolucion,r.IdPago,r.ReferenciaReembolso,r.Estado,r.Monto,r.FechaCreacionUTC,r.FechaResolucionUTC
FROM dbo.Reembolsos r JOIN dbo.Devoluciones d ON d.IdDevolucion=r.IdDevolucion WHERE d.IdPedido=@IdPedido ORDER BY r.IdReembolso;
SELECT IdReembolsoCancelacion,IdPago,ReferenciaReembolso,Estado,Monto,FechaCreacionUTC,FechaResolucionUTC FROM dbo.ReembolsosCancelacion WHERE IdPedido=@IdPedido ORDER BY IdReembolsoCancelacion;
END;';

    EXEC sys.sp_executesql N'CREATE PROCEDURE dbo.SP_Devoluciones_Listar
@IdActor bigint,@IdSesion uniqueidentifier,@Estado varchar(25)=NULL,@Pagina int=1,@TamanoPagina int=50
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
EXEC dbo.SP_Interno_Autorizar @IdActor, @IdSesion, N''OPERADOR'';

IF @Pagina IS NULL OR @Pagina<1 OR @TamanoPagina IS NULL OR @TamanoPagina NOT BETWEEN 1 AND 100 THROW 62937,N''Paginación inválida.'',1;
SELECT IdDevolucion,IdPedido,IdUsuarioSolicitante,Estado,Motivo,FechaSolicitudUTC,FechaResolucionUTC,COUNT_BIG(*) OVER() TotalFilas FROM dbo.Devoluciones
WHERE @Estado IS NULL OR Estado=@Estado ORDER BY FechaSolicitudUTC,IdDevolucion
OFFSET ((CONVERT(bigint,@Pagina)-1)*@TamanoPagina) ROWS FETCH NEXT @TamanoPagina ROWS ONLY;
END;';

    EXEC sys.sp_executesql N'
        INSERT dbo.VersionesMigracion ([Version],NombreArchivo,SHA256,FechaAplicacionUTC,Ejecutor)
        VALUES (19,N''019_ProcedimientosDevoluciones.sql'',@Huella,SYSUTCDATETIME(),ORIGINAL_LOGIN());
    ',N'@Huella varbinary(32)',@Huella=@SHA256;
    COMMIT TRANSACTION;
    PRINT N'Migración 19 completada.';
END TRY
BEGIN CATCH
    IF XACT_STATE() <> 0 ROLLBACK TRANSACTION;
    THROW;
END CATCH;
