/*
    017_ProcedimientosCheckout.sql. Ejecutar completo, sin GO, con Auto-commit en ShopCart.
    SHA-256 final: suministrar 32 bytes mediante SESSION_CONTEXT,
    clave ShopCart.Migracion017.SHA256, misma conexión DataGrip.
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
    RevisionCarrito es texto ISO exacto, no Date JS. Iniciar captura entrega, envío y cupón; reserva y crea pedido pendiente. Reintentos devuelven la cotización guardada; reconfigurar requiere cancelar e iniciar otra clave.
*/
IF DB_NAME() <> N'ShopCart'
    THROW 62500, N'017 solo puede ejecutarse en la base ShopCart.', 1;

IF @@TRANCOUNT <> 0 OR (2 & @@OPTIONS) = 2
    THROW 62501, N'Inicie con Auto-commit y sin transacciones abiertas o implícitas.', 1;

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
    THROW 62502, N'Se requiere CONTROL sobre ShopCart para inspeccionar y crear el esquema.', 1;

IF NOT EXISTS (
    SELECT 1 FROM sys.databases
    WHERE database_id = DB_ID()
      AND collation_name = N'Latin1_General_100_CI_AI_SC'
      AND recovery_model_desc = N'SIMPLE'
      AND state_desc = N'ONLINE' AND user_access_desc = N'MULTI_USER'
      AND is_read_only = 0 AND source_database_id IS NULL
)
    THROW 62503, N'Las propiedades de ShopCart no coinciden con el arranque 001.', 1;

DECLARE @HuellaRecibida sql_variant = SESSION_CONTEXT(N'ShopCart.Migracion017.SHA256');
IF @HuellaRecibida IS NULL
   OR CONVERT(nvarchar(128), SQL_VARIANT_PROPERTY(@HuellaRecibida, 'BaseType')) NOT IN (N'binary', N'varbinary')
    THROW 62504, N'Suministre el SHA-256 real como valor binario en SESSION_CONTEXT antes de ejecutar 017.', 1;

DECLARE @SHA256 varbinary(max) = CONVERT(varbinary(max), @HuellaRecibida);
IF DATALENGTH(@SHA256) <> 32
    THROW 62505, N'La huella SHA-256 debe contener exactamente 32 bytes.', 1;

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
        THROW 62506, N'No se pudo obtener el bloqueo exclusivo de migraciones.', 1;

    DECLARE @IDVersiones int = OBJECT_ID(N'dbo.VersionesMigracion', N'U');
    IF @IDVersiones IS NULL
        THROW 62507, N'Falta la tabla técnica creada por 001. No se aplicará 017.', 1;

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
        THROW 62508, N'Las columnas de VersionesMigracion no cumplen el contrato de 001.', 1;

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
        THROW 62509, N'VersionesMigracion requiere la PK clustered de 001 sobre Version.', 1;

    IF EXISTS (SELECT 1 FROM sys.triggers WHERE parent_id = @IDVersiones)
       OR EXISTS (SELECT 1 FROM sys.tables WHERE object_id = @IDVersiones
                  AND (temporal_type <> 0 OR is_memory_optimized = 1))
        THROW 62510, N'VersionesMigracion tiene características inesperadas; revisar manualmente.', 1;

    -- Lote inferior: errores de compilación/resolución quedan dentro del TRY externo.
    EXEC sys.sp_executesql N'
        IF NOT EXISTS (
            SELECT 1 FROM dbo.VersionesMigracion WITH (UPDLOCK, HOLDLOCK)
            WHERE [Version] = 16 AND NombreArchivo = N''016_ProcedimientosCupones.sql''
        )
            THROW 62513, N''Debe estar registrada la migración 016_ProcedimientosCupones.sql antes de aplicar 017.'', 1;
        IF EXISTS (SELECT 1 FROM dbo.VersionesMigracion WITH (UPDLOCK, HOLDLOCK)
                   WHERE [Version] >= 17)
            THROW 62511, N''017 o una migración posterior ya está registrada. No se reaplica ni se certifica el esquema existente.'', 1;
    ';


    -- Rechaza nombres conflictivos antes de crear el primer procedimiento.
    IF OBJECT_ID(N'dbo.SP_Checkout_Iniciar') IS NOT NULL THROW 62550, N'Ya existe un objeto de procedimiento; no se sobrescribe.',1;
    IF OBJECT_ID(N'dbo.SP_Checkout_Consultar') IS NOT NULL THROW 62550, N'Ya existe un objeto de procedimiento; no se sobrescribe.',1;
    IF OBJECT_ID(N'dbo.SP_Checkout_Cancelar') IS NOT NULL THROW 62550, N'Ya existe un objeto de procedimiento; no se sobrescribe.',1;
    IF OBJECT_ID(N'dbo.SP_Checkout_Expirar') IS NOT NULL THROW 62550, N'Ya existe un objeto de procedimiento; no se sobrescribe.',1;
    IF OBJECT_ID(N'dbo.SP_Checkout_ListarMetodosEnvio') IS NOT NULL THROW 62550, N'Ya existe un objeto de procedimiento; no se sobrescribe.',1;

    EXEC sys.sp_executesql N'CREATE PROCEDURE dbo.SP_Checkout_Iniciar
@IdCarrito bigint,@RevisionCarrito nvarchar(max),@ClaveIdempotencia varbinary(max),@IdMetodoEnvio int,
@NombreDestinatario nvarchar(max),@Telefono nvarchar(max),@Departamento nvarchar(max),@Ciudad nvarchar(max),
@Direccion1 nvarchar(max),@Direccion2 nvarchar(max)=NULL,@CodigoPostal nvarchar(max)=NULL,
@IdDireccion bigint=NULL,@CodigoCupon nvarchar(max)=NULL,
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
IF @IdActor IS NOT NULL BEGIN
 EXEC dbo.SP_Interno_Autorizar @IdActor,@IdSesion,N''USUARIO'';
 IF @TokenInvitado IS NOT NULL THROW 62500,N''Identidad de carrito ambigua.'',1;
 IF NOT EXISTS(SELECT 1 FROM dbo.Carritos WHERE IdCarrito=@IdCarrito AND IdUsuario=@IdActor)
 THROW 62501,N''Carrito no autorizado.'',1;
END ELSE BEGIN
 IF @TokenInvitado IS NULL OR DATALENGTH(@TokenInvitado)<>32 OR @IdSesion IS NOT NULL
 OR NOT EXISTS(SELECT 1 FROM dbo.Carritos WHERE IdCarrito=@IdCarrito AND IdUsuario IS NULL AND TokenInvitadoHash=@TokenInvitado)
 THROW 62501,N''Carrito no autorizado.'',1;
END;IF @NombreDestinatario IS NULL OR LEN(LTRIM(RTRIM(@NombreDestinatario)))=0 OR DATALENGTH(@NombreDestinatario)>300
THROW 62003,N''Texto obligatorio vacío o longitud no válida.'',1;
IF @Telefono IS NULL OR LEN(LTRIM(RTRIM(@Telefono)))=0 OR DATALENGTH(@Telefono)>50
THROW 62003,N''Texto obligatorio vacío o longitud no válida.'',1;
IF @Departamento IS NULL OR LEN(LTRIM(RTRIM(@Departamento)))=0 OR DATALENGTH(@Departamento)>200
THROW 62003,N''Texto obligatorio vacío o longitud no válida.'',1;
IF @Ciudad IS NULL OR LEN(LTRIM(RTRIM(@Ciudad)))=0 OR DATALENGTH(@Ciudad)>200
THROW 62003,N''Texto obligatorio vacío o longitud no válida.'',1;
IF @Direccion1 IS NULL OR LEN(LTRIM(RTRIM(@Direccion1)))=0 OR DATALENGTH(@Direccion1)>500
THROW 62003,N''Texto obligatorio vacío o longitud no válida.'',1;

IF @RevisionCarrito IS NULL OR DATALENGTH(@RevisionCarrito)>66 OR TRY_CONVERT(datetime2(7),@RevisionCarrito,126) IS NULL OR @ClaveIdempotencia IS NULL OR DATALENGTH(@ClaveIdempotencia)<>32
OR DATALENGTH(@Direccion2)>500 OR DATALENGTH(@CodigoPostal)>30 OR DATALENGTH(@CodigoCupon)>100
THROW 62701,N''Solicitud de checkout inválida.'',1;
SET @RevisionCarrito=CONVERT(nvarchar(33),TRY_CONVERT(datetime2(7),@RevisionCarrito,126),126);
SET @Direccion2=NULLIF(LTRIM(RTRIM(@Direccion2)),N''''); SET @CodigoPostal=NULLIF(LTRIM(RTRIM(@CodigoPostal)),N'''');
DECLARE @Solicitud nvarchar(max)=(SELECT @IdCarrito Carrito,@RevisionCarrito Revision,@IdActor Usuario,@IdMetodoEnvio Metodo,
LTRIM(RTRIM(@NombreDestinatario)) Destinatario,LTRIM(RTRIM(@Telefono)) Telefono,
LTRIM(RTRIM(@Departamento)) Departamento,LTRIM(RTRIM(@Ciudad)) Ciudad,LTRIM(RTRIM(@Direccion1)) Direccion1,
@Direccion2 Direccion2,@CodigoPostal Postal,@IdDireccion Direccion,UPPER(LTRIM(RTRIM(@CodigoCupon))) Cupon
FOR JSON PATH,WITHOUT_ARRAY_WRAPPER,INCLUDE_NULL_VALUES);
DECLARE @Huella varchar(64)=CONVERT(varchar(64),HASHBYTES(''SHA2_256'',@Solicitud),2);
DECLARE @IdCheckout bigint=(SELECT IdCheckout FROM dbo.Checkouts WHERE ClaveIdempotenciaHash=@ClaveIdempotencia);
IF @IdCheckout IS NOT NULL BEGIN
 IF NOT EXISTS(SELECT 1 FROM dbo.EventosAuditoria WHERE Entidad=''Checkouts'' AND IdEntidad=@IdCheckout AND Accion=''INICIAR''
 AND JSON_VALUE(DatosNuevos,''$.HuellaSolicitud'')=@Huella) THROW 62702,N''Clave de checkout reutilizada con contenido diferente.'',1;
 SELECT @IdCheckout IdCheckout,p.IdPedido,p.Total,c.FechaExpiracionUTC FROM dbo.Pedidos p
JOIN dbo.Checkouts c ON c.IdCheckout=p.IdCheckout WHERE p.IdCheckout=@IdCheckout;
 COMMIT TRANSACTION; RETURN;
END;
IF NOT EXISTS(SELECT 1 FROM dbo.Carritos WITH(UPDLOCK,HOLDLOCK) WHERE IdCarrito=@IdCarrito AND Estado=''ACTIVO'' AND FechaUltimaActividadUTC=TRY_CONVERT(datetime2(7),@RevisionCarrito,126))
THROW 62703,N''Carrito modificado o inactivo; consulte su revisión actual.'',1;
DECLARE @Ahora datetime2(7)=SYSUTCDATETIME(),@Expira datetime2(7);
SET @Expira=DATEADD(minute,15,@Ahora);
-- Resuelve vencidos sin eliminar líneas referenciadas por reservas históricas.
UPDATE r SET Estado=''EXPIRADA'',FechaResolucionUTC=@Ahora,FechaActualizacionUTC=@Ahora
FROM dbo.ReservasInventario r JOIN dbo.Checkouts c ON c.IdCheckout=r.IdCheckout
WHERE c.IdCarrito=@IdCarrito AND r.Estado=''ACTIVA'' AND r.FechaExpiracionUTC<=@Ahora;
UPDATE r SET Estado=''EXPIRADA'',FechaResolucionUTC=@Ahora,FechaActualizacionUTC=@Ahora
FROM dbo.ReservasCupon r JOIN dbo.Checkouts c ON c.IdCheckout=r.IdCheckout
WHERE c.IdCarrito=@IdCarrito AND r.Estado=''ACTIVA'' AND r.FechaExpiracionUTC<=@Ahora;
DECLARE @Vencidos TABLE(IdPedido bigint,EstadoAnterior varchar(25));
UPDATE p SET Estado=''CANCELADO'',FechaActualizacionUTC=@Ahora OUTPUT inserted.IdPedido,deleted.Estado INTO @Vencidos
FROM dbo.Pedidos p JOIN dbo.Checkouts c ON c.IdCheckout=p.IdCheckout
WHERE c.IdCarrito=@IdCarrito AND c.Estado IN (''INICIADO'',''RESERVADO'') AND c.FechaExpiracionUTC<=@Ahora AND p.Estado=''PENDIENTE_PAGO'';
UPDATE pa SET Estado=''CANCELADO'',FechaActualizacionUTC=@Ahora,FechaResolucionUTC=@Ahora
FROM dbo.Pagos pa JOIN @Vencidos v ON v.IdPedido=pa.IdPedido WHERE pa.Estado=''PENDIENTE'';
INSERT dbo.HistorialEstadosPedido(IdPedido,EstadoAnterior,EstadoNuevo,IdUsuarioActor,Observacion)
SELECT IdPedido,EstadoAnterior,''CANCELADO'',@IdActor,N''Checkout vencido'' FROM @Vencidos;
INSERT dbo.EventosAuditoria(IdUsuarioActor,Accion,Entidad,IdEntidad)
SELECT @IdActor,''EXPIRAR'',''Pedidos'',IdPedido FROM @Vencidos;
UPDATE dbo.Checkouts SET Estado=''EXPIRADO'',FechaActualizacionUTC=@Ahora WHERE IdCarrito=@IdCarrito AND Estado IN (''INICIADO'',''RESERVADO'') AND FechaExpiracionUTC<=@Ahora;
IF EXISTS(SELECT 1 FROM dbo.Checkouts WHERE IdCarrito=@IdCarrito AND Estado IN (''INICIADO'',''RESERVADO''))
THROW 62704,N''Ya existe un checkout vigente; recupérelo o cancélelo.'',1;
IF @IdDireccion IS NOT NULL AND (@IdActor IS NULL OR NOT EXISTS(SELECT 1 FROM dbo.Direcciones WHERE IdDireccion=@IdDireccion AND IdUsuario=@IdActor AND EstaActiva=1))
THROW 62705,N''Dirección no autorizada.'',1;
IF @IdDireccion IS NOT NULL AND NOT EXISTS(SELECT 1 FROM dbo.Direcciones WHERE IdDireccion=@IdDireccion
AND NombreDestinatario=@NombreDestinatario AND TelefonoContacto=@Telefono AND Departamento=@Departamento AND Municipio=@Ciudad
AND DireccionLinea1=@Direccion1 AND COALESCE(DireccionLinea2,N'''')=COALESCE(@Direccion2,N'''') AND COALESCE(CodigoPostal,N'''')=COALESCE(@CodigoPostal,N''''))
THROW 62706,N''La entrega no coincide con la dirección seleccionada.'',1;
DECLARE @Costo decimal(19,4),@CodigoEnvio varchar(30),@NombreEnvio nvarchar(100);
SELECT @Costo=Costo,@CodigoEnvio=Codigo,@NombreEnvio=Nombre FROM dbo.MetodosEnvio WHERE IdMetodoEnvio=@IdMetodoEnvio AND EstaActivo=1;
IF @Costo IS NULL THROW 62707,N''Método de envío no disponible.'',1;
DECLARE @L TABLE(IdVariante bigint PRIMARY KEY,SKU nvarchar(64),Nombre nvarchar(200),Descripcion nvarchar(250),
IdCategoria int,NombreCategoria nvarchar(200),Cantidad int,Precio decimal(19,4),Subtotal decimal(19,4),
Descuento decimal(19,4) DEFAULT 0,Total decimal(19,4),Base decimal(19,4),IVA decimal(19,4),Unidades decimal(19,0),Residuo decimal(38,0));
IF EXISTS(SELECT 1 FROM dbo.DetallesCarrito d JOIN dbo.VariantesProducto v ON v.IdVariante=d.IdVariante
JOIN dbo.Productos p ON p.IdProducto=v.IdProducto JOIN dbo.Categorias c ON c.IdCategoria=p.IdCategoria
WHERE d.IdCarrito=@IdCarrito AND (v.EstaActiva=0 OR p.EstaActivo=0 OR c.EstaActiva=0))
THROW 62708,N''El carrito contiene artículos inactivos.'',1;
INSERT @L(IdVariante,SKU,Nombre,Descripcion,IdCategoria,NombreCategoria,Cantidad,Precio,Subtotal)
SELECT v.IdVariante,v.SKU,p.Nombre,CONCAT(N''Talla: '',COALESCE(v.Talla,N''-''),N''; Color: '',COALESCE(v.Color,N''-'')),
c.IdCategoria,c.Nombre,d.Cantidad,v.Precio,CONVERT(decimal(30,4),d.Cantidad)*v.Precio
FROM dbo.DetallesCarrito d JOIN dbo.VariantesProducto v ON v.IdVariante=d.IdVariante
JOIN dbo.Productos p ON p.IdProducto=v.IdProducto JOIN dbo.Categorias c ON c.IdCategoria=p.IdCategoria WHERE d.IdCarrito=@IdCarrito;
IF NOT EXISTS(SELECT 1 FROM @L) THROW 62709,N''Carrito vacío.'',1;
IF EXISTS(SELECT 1 FROM @L l LEFT JOIN dbo.Existencias e WITH(UPDLOCK,HOLDLOCK) ON e.IdVariante=l.IdVariante
OUTER APPLY(SELECT SUM(CONVERT(bigint,Cantidad)) Cantidad FROM dbo.ReservasInventario
WHERE IdVariante=l.IdVariante AND Estado=''ACTIVA'' AND FechaExpiracionUTC>@Ahora) r
WHERE e.IdVariante IS NULL OR l.Cantidad>CONVERT(bigint,e.CantidadFisica)-COALESCE(r.Cantidad,0))
THROW 62710,N''Inventario insuficiente.'',1;
DECLARE @Subtotal decimal(19,4)=(SELECT SUM(CONVERT(decimal(30,4),Subtotal)) FROM @L),
@Descuento decimal(19,4)=0,@Elegible decimal(19,4),@IdCupon bigint,@CategoriaCupon int;
IF @CodigoCupon IS NOT NULL BEGIN
 SELECT @IdCupon=IdCupon,@CategoriaCupon=IdCategoria FROM dbo.Cupones WHERE Codigo=UPPER(LTRIM(RTRIM(@CodigoCupon)));
 IF @IdCupon IS NULL THROW 62711,N''Cupón inexistente.'',1;
 SELECT @Elegible=SUM(CONVERT(decimal(30,4),Subtotal)) FROM @L WHERE @CategoriaCupon IS NULL OR IdCategoria=@CategoriaCupon;
 EXEC dbo.SP_Interno_EvaluarCupon @IdCupon,@IdActor,@Subtotal,@Elegible,NULL,@Descuento OUTPUT;
END;
-- Reparto exacto en unidades de 0.0001 GTQ: cociente entero y mayores residuos.
IF @Descuento>0 BEGIN
 DECLARE @DU decimal(19,0)=@Descuento*10000,@EU decimal(19,0)=@Elegible*10000;
 UPDATE @L SET Unidades=Subtotal*10000 WHERE @CategoriaCupon IS NULL OR IdCategoria=@CategoriaCupon;
 UPDATE @L SET Residuo=(@DU*Unidades)%@EU,
 Descuento=CONVERT(decimal(19,4),CONVERT(decimal(19,0),((@DU*Unidades-((@DU*Unidades)%@EU))/@EU))/10000.0)
 WHERE Unidades IS NOT NULL;
 DECLARE @Faltan int=CONVERT(int,(CONVERT(decimal(21,4),@Descuento)-CONVERT(decimal(21,4),(SELECT SUM(Descuento) FROM @L)))*10000);
 ;WITH R AS(SELECT IdVariante,ROW_NUMBER() OVER(ORDER BY Residuo DESC,IdVariante) rn FROM @L WHERE Unidades IS NOT NULL)
 UPDATE l SET Descuento=Descuento+0.0001 FROM @L l JOIN R ON R.IdVariante=l.IdVariante WHERE R.rn<=@Faltan;
END;
UPDATE @L SET Total=Subtotal-Descuento;
UPDATE @L SET Base=CONVERT(decimal(19,4),ROUND(CONVERT(decimal(25,4),Total)/1.12,4));
UPDATE @L SET IVA=Total-Base;
DECLARE @Total decimal(19,4)=CONVERT(decimal(23,4),@Subtotal)-@Descuento+@Costo;
DECLARE @BaseEnvio decimal(19,4)=CONVERT(decimal(19,4),ROUND(CONVERT(decimal(25,4),@Costo)/1.12,4));
DECLARE @Base decimal(19,4)=(SELECT SUM(CONVERT(decimal(30,4),Base)) FROM @L),@IVA decimal(19,4);
SET @Base=CONVERT(decimal(21,4),@Base)+CONVERT(decimal(21,4),@BaseEnvio);
SET @IVA=@Total-@Base;
INSERT dbo.Checkouts(IdCarrito,IdUsuario,IdDireccion,IdMetodoEnvio,IdCupon,ClaveIdempotenciaHash,Estado,Subtotal,Descuento,CostoEnvio,Total,FechaExpiracionUTC)
VALUES(@IdCarrito,@IdActor,@IdDireccion,@IdMetodoEnvio,@IdCupon,@ClaveIdempotencia,''RESERVADO'',@Subtotal,@Descuento,@Costo,@Total,@Expira);
SET @IdCheckout=CONVERT(bigint,SCOPE_IDENTITY());
INSERT dbo.DetallesCheckout(IdCheckout,IdVariante,SKU,NombreProducto,DescripcionVariante,Cantidad,PrecioUnitario,SubtotalLinea)
SELECT @IdCheckout,IdVariante,SKU,Nombre,Descripcion,Cantidad,Precio,Subtotal FROM @L;
INSERT dbo.ReservasInventario(IdCheckout,IdVariante,Cantidad,FechaExpiracionUTC)
SELECT @IdCheckout,IdVariante,Cantidad,@Expira FROM @L;
IF @IdCupon IS NOT NULL INSERT dbo.ReservasCupon(IdCheckout,IdCupon,IdUsuario,FechaExpiracionUTC) VALUES(@IdCheckout,@IdCupon,@IdActor,@Expira);
DECLARE @Numero varchar(30)=CONCAT(''SC-'',CONVERT(varchar(20),@IdCheckout));
INSERT dbo.Pedidos(NumeroPedido,IdCheckout,IdUsuario,IdMetodoEnvio,IdCupon,Subtotal,Descuento,CostoEnvio,Total,BaseImponible,MontoIVA,
NombreDestinatario,TelefonoDestinatario,DireccionLinea1,DireccionLinea2,Ciudad,Departamento,CodigoPostal,Pais,CodigoMetodoEnvio,NombreMetodoEnvio)
VALUES(@Numero,@IdCheckout,@IdActor,@IdMetodoEnvio,@IdCupon,@Subtotal,@Descuento,@Costo,@Total,@Base,@IVA,
LTRIM(RTRIM(@NombreDestinatario)),LTRIM(RTRIM(@Telefono)),LTRIM(RTRIM(@Direccion1)),@Direccion2,LTRIM(RTRIM(@Ciudad)),LTRIM(RTRIM(@Departamento)),@CodigoPostal,''GT'',@CodigoEnvio,@NombreEnvio);
DECLARE @IdPedido bigint=CONVERT(bigint,SCOPE_IDENTITY());
INSERT dbo.DetallesPedido(IdPedido,IdVariante,SKU,NombreProducto,DescripcionVariante,IdCategoria,NombreCategoria,Cantidad,PrecioUnitario,SubtotalLinea,DescuentoLinea,TotalLinea,BaseImponibleLinea,MontoIVALinea)
SELECT @IdPedido,IdVariante,SKU,Nombre,Descripcion,IdCategoria,NombreCategoria,Cantidad,Precio,Subtotal,Descuento,Total,Base,IVA FROM @L;
INSERT dbo.HistorialEstadosPedido(IdPedido,EstadoAnterior,EstadoNuevo,IdUsuarioActor) VALUES(@IdPedido,NULL,''PENDIENTE_PAGO'',@IdActor);
DECLARE @Auditoria nvarchar(max)=(SELECT @Huella HuellaSolicitud FOR JSON PATH,WITHOUT_ARRAY_WRAPPER);
INSERT dbo.EventosAuditoria (IdUsuarioActor,Accion,Entidad,IdEntidad,DatosAnteriores,DatosNuevos)
VALUES (@IdActor,N''INICIAR'',N''Checkouts'',@IdCheckout,NULL,@Auditoria);

INSERT dbo.EventosAuditoria(IdUsuarioActor,Accion,Entidad,IdEntidad) VALUES(@IdActor,''CREAR'',''Pedidos'',@IdPedido);
SELECT @IdCheckout IdCheckout,@IdPedido IdPedido,@Total Total,@Expira FechaExpiracionUTC;
        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF XACT_STATE() <> 0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH;
END;';

    EXEC sys.sp_executesql N'CREATE PROCEDURE dbo.SP_Checkout_Consultar
@IdCheckout bigint,@IdActor bigint=NULL,@IdSesion uniqueidentifier=NULL,@TokenInvitado varbinary(max)=NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

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
SELECT IdCheckout,Estado,Subtotal,Descuento,CostoEnvio,Total,FechaExpiracionUTC,
CONVERT(bit,CASE WHEN Estado=''RESERVADO'' AND FechaExpiracionUTC>SYSUTCDATETIME() THEN 1 ELSE 0 END) EstaVigente
FROM dbo.Checkouts WHERE IdCheckout=@IdCheckout;
SELECT IdDetalleCheckout,IdVariante,SKU,NombreProducto,DescripcionVariante,Cantidad,PrecioUnitario,SubtotalLinea
FROM dbo.DetallesCheckout WHERE IdCheckout=@IdCheckout ORDER BY IdVariante;
SELECT IdReservaInventario,IdVariante,Cantidad,Estado,FechaExpiracionUTC FROM dbo.ReservasInventario WHERE IdCheckout=@IdCheckout ORDER BY IdReservaInventario;
SELECT IdReservaCupon,IdCupon,Estado,FechaExpiracionUTC FROM dbo.ReservasCupon WHERE IdCheckout=@IdCheckout ORDER BY IdReservaCupon;
SELECT IdPedido,NumeroPedido,Estado,Total FROM dbo.Pedidos WHERE IdCheckout=@IdCheckout;
END;';

    EXEC sys.sp_executesql N'CREATE PROCEDURE dbo.SP_Checkout_Cancelar
@IdCheckout bigint,@IdActor bigint=NULL,@IdSesion uniqueidentifier=NULL,@TokenInvitado varbinary(max)=NULL
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
DECLARE @Estado varchar(20)=(SELECT Estado FROM dbo.Checkouts WITH(UPDLOCK,HOLDLOCK) WHERE IdCheckout=@IdCheckout);
IF @Estado=''CONFIRMADO'' THROW 62712,N''Use cancelación de pedido para una compra confirmada.'',1;
IF @Estado IN (''CANCELADO'',''EXPIRADO'') BEGIN COMMIT TRANSACTION; RETURN; END;
DECLARE @Ahora datetime2(7)=SYSUTCDATETIME(),@IdPedido bigint=(SELECT IdPedido FROM dbo.Pedidos WHERE IdCheckout=@IdCheckout);
UPDATE dbo.ReservasInventario SET Estado=''LIBERADA'',FechaResolucionUTC=@Ahora,FechaActualizacionUTC=@Ahora WHERE IdCheckout=@IdCheckout AND Estado=''ACTIVA'';
UPDATE dbo.ReservasCupon SET Estado=''LIBERADA'',FechaResolucionUTC=@Ahora,FechaActualizacionUTC=@Ahora WHERE IdCheckout=@IdCheckout AND Estado=''ACTIVA'';
UPDATE dbo.Checkouts SET Estado=''CANCELADO'',FechaActualizacionUTC=@Ahora WHERE IdCheckout=@IdCheckout AND Estado IN (''INICIADO'',''RESERVADO'');
IF @@ROWCOUNT<>1 THROW 62713,N''Conflicto de cancelación.'',1;
UPDATE dbo.Pagos SET Estado=''CANCELADO'',FechaActualizacionUTC=@Ahora,FechaResolucionUTC=@Ahora
WHERE IdPedido=@IdPedido AND Estado=''PENDIENTE'';
UPDATE dbo.Pedidos SET Estado=''CANCELADO'',FechaActualizacionUTC=@Ahora WHERE IdPedido=@IdPedido AND Estado=''PENDIENTE_PAGO'';
IF @@ROWCOUNT=1 INSERT dbo.HistorialEstadosPedido(IdPedido,EstadoAnterior,EstadoNuevo,IdUsuarioActor) VALUES(@IdPedido,''PENDIENTE_PAGO'',''CANCELADO'',@IdActor);
INSERT dbo.EventosAuditoria (IdUsuarioActor,Accion,Entidad,IdEntidad,DatosAnteriores,DatosNuevos)
VALUES (@IdActor,N''CANCELAR'',N''Checkouts'',@IdCheckout,NULL,NULL);

        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF XACT_STATE() <> 0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH;
END;';

    EXEC sys.sp_executesql N'CREATE PROCEDURE dbo.SP_Checkout_Expirar
@IdActor bigint,@IdSesion uniqueidentifier,@Limite int=100
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

IF @Limite IS NULL OR @Limite NOT BETWEEN 1 AND 1000 THROW 62714,N''Límite inválido.'',1;
DECLARE @Ahora datetime2(7)=SYSUTCDATETIME();
DECLARE @Objetivos TABLE(IdCheckout bigint PRIMARY KEY);
INSERT @Objetivos SELECT TOP(@Limite) IdCheckout FROM dbo.Checkouts WITH(UPDLOCK,HOLDLOCK)
WHERE Estado IN (''INICIADO'',''RESERVADO'') AND FechaExpiracionUTC<=@Ahora ORDER BY FechaExpiracionUTC,IdCheckout;
UPDATE r SET Estado=''EXPIRADA'',FechaResolucionUTC=@Ahora,FechaActualizacionUTC=@Ahora FROM dbo.ReservasInventario r JOIN @Objetivos o ON o.IdCheckout=r.IdCheckout WHERE r.Estado=''ACTIVA'';
UPDATE r SET Estado=''EXPIRADA'',FechaResolucionUTC=@Ahora,FechaActualizacionUTC=@Ahora FROM dbo.ReservasCupon r JOIN @Objetivos o ON o.IdCheckout=r.IdCheckout WHERE r.Estado=''ACTIVA'';
DECLARE @Pedidos TABLE(IdPedido bigint);
UPDATE p SET Estado=''CANCELADO'',FechaActualizacionUTC=@Ahora OUTPUT inserted.IdPedido INTO @Pedidos
FROM dbo.Pedidos p JOIN @Objetivos o ON o.IdCheckout=p.IdCheckout WHERE p.Estado=''PENDIENTE_PAGO'';
UPDATE pa SET Estado=''CANCELADO'',FechaActualizacionUTC=@Ahora,FechaResolucionUTC=@Ahora
FROM dbo.Pagos pa JOIN @Pedidos o ON o.IdPedido=pa.IdPedido WHERE pa.Estado=''PENDIENTE'';
INSERT dbo.HistorialEstadosPedido(IdPedido,EstadoAnterior,EstadoNuevo,IdUsuarioActor,Observacion)
SELECT IdPedido,''PENDIENTE_PAGO'',''CANCELADO'',@IdActor,N''Expiración de checkout'' FROM @Pedidos;
INSERT dbo.EventosAuditoria(IdUsuarioActor,Accion,Entidad,IdEntidad) SELECT @IdActor,''EXPIRAR'',''Pedidos'',IdPedido FROM @Pedidos;
UPDATE c SET Estado=''EXPIRADO'',FechaActualizacionUTC=@Ahora FROM dbo.Checkouts c JOIN @Objetivos o ON o.IdCheckout=c.IdCheckout;
SELECT COUNT(*) CantidadExpirada FROM @Objetivos;
        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF XACT_STATE() <> 0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH;
END;';

    EXEC sys.sp_executesql N'CREATE PROCEDURE dbo.SP_Checkout_ListarMetodosEnvio

AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
SELECT IdMetodoEnvio,Codigo,Nombre,Descripcion,Costo FROM dbo.MetodosEnvio WHERE EstaActivo=1 ORDER BY OrdenVisualizacion,IdMetodoEnvio;
END;';

    EXEC sys.sp_executesql N'
        INSERT dbo.VersionesMigracion ([Version],NombreArchivo,SHA256,FechaAplicacionUTC,Ejecutor)
        VALUES (17,N''017_ProcedimientosCheckout.sql'',@Huella,SYSUTCDATETIME(),ORIGINAL_LOGIN());
    ',N'@Huella varbinary(32)',@Huella=@SHA256;
    COMMIT TRANSACTION;
    PRINT N'Migración 17 completada.';
END TRY
BEGIN CATCH
    IF XACT_STATE() <> 0 ROLLBACK TRANSACTION;
    THROW;
END CATCH;
