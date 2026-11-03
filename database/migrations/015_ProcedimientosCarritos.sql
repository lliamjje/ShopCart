/*
    015_ProcedimientosCarritos.sql. Ejecutar completo, sin GO, con Auto-commit en ShopCart.
    SHA-256 final: suministrar 32 bytes mediante SESSION_CONTEXT,
    clave ShopCart.Migracion015.SHA256, misma conexión DataGrip.
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
    Consultar devuelve RevisionCarrito como texto ISO con precisión completa: transportarlo sin convertirlo a Date de JavaScript. Fusión devuelve destino auditado en reintentos. Conversión solo al pagar.
*/
IF DB_NAME() <> N'ShopCart'
    THROW 62300, N'015 solo puede ejecutarse en la base ShopCart.', 1;

IF @@TRANCOUNT <> 0 OR (2 & @@OPTIONS) = 2
    THROW 62301, N'Inicie con Auto-commit y sin transacciones abiertas o implícitas.', 1;

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
    THROW 62302, N'Se requiere CONTROL sobre ShopCart para inspeccionar y crear el esquema.', 1;

IF NOT EXISTS (
    SELECT 1 FROM sys.databases
    WHERE database_id = DB_ID()
      AND collation_name = N'Latin1_General_100_CI_AI_SC'
      AND recovery_model_desc = N'SIMPLE'
      AND state_desc = N'ONLINE' AND user_access_desc = N'MULTI_USER'
      AND is_read_only = 0 AND source_database_id IS NULL
)
    THROW 62303, N'Las propiedades de ShopCart no coinciden con el arranque 001.', 1;

DECLARE @HuellaRecibida sql_variant = SESSION_CONTEXT(N'ShopCart.Migracion015.SHA256');
IF @HuellaRecibida IS NULL
   OR CONVERT(nvarchar(128), SQL_VARIANT_PROPERTY(@HuellaRecibida, 'BaseType')) NOT IN (N'binary', N'varbinary')
    THROW 62304, N'Suministre el SHA-256 real como valor binario en SESSION_CONTEXT antes de ejecutar 015.', 1;

DECLARE @SHA256 varbinary(max) = CONVERT(varbinary(max), @HuellaRecibida);
IF DATALENGTH(@SHA256) <> 32
    THROW 62305, N'La huella SHA-256 debe contener exactamente 32 bytes.', 1;

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
        THROW 62306, N'No se pudo obtener el bloqueo exclusivo de migraciones.', 1;

    DECLARE @IDVersiones int = OBJECT_ID(N'dbo.VersionesMigracion', N'U');
    IF @IDVersiones IS NULL
        THROW 62307, N'Falta la tabla técnica creada por 001. No se aplicará 015.', 1;

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
        THROW 62308, N'Las columnas de VersionesMigracion no cumplen el contrato de 001.', 1;

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
        THROW 62309, N'VersionesMigracion requiere la PK clustered de 001 sobre Version.', 1;

    IF EXISTS (SELECT 1 FROM sys.triggers WHERE parent_id = @IDVersiones)
       OR EXISTS (SELECT 1 FROM sys.tables WHERE object_id = @IDVersiones
                  AND (temporal_type <> 0 OR is_memory_optimized = 1))
        THROW 62310, N'VersionesMigracion tiene características inesperadas; revisar manualmente.', 1;

    -- Lote inferior: errores de compilación/resolución quedan dentro del TRY externo.
    EXEC sys.sp_executesql N'
        IF NOT EXISTS (
            SELECT 1 FROM dbo.VersionesMigracion WITH (UPDLOCK, HOLDLOCK)
            WHERE [Version] = 14 AND NombreArchivo = N''014_ProcedimientosInventario.sql''
        )
            THROW 62313, N''Debe estar registrada la migración 014_ProcedimientosInventario.sql antes de aplicar 015.'', 1;
        IF EXISTS (SELECT 1 FROM dbo.VersionesMigracion WITH (UPDLOCK, HOLDLOCK)
                   WHERE [Version] >= 15)
            THROW 62311, N''015 o una migración posterior ya está registrada. No se reaplica ni se certifica el esquema existente.'', 1;
    ';


    -- Rechaza nombres conflictivos antes de crear el primer procedimiento.
    IF OBJECT_ID(N'dbo.SP_Carritos_ObtenerActivo') IS NOT NULL THROW 62350, N'Ya existe un objeto de procedimiento; no se sobrescribe.',1;
    IF OBJECT_ID(N'dbo.SP_Carritos_Consultar') IS NOT NULL THROW 62350, N'Ya existe un objeto de procedimiento; no se sobrescribe.',1;
    IF OBJECT_ID(N'dbo.SP_Carritos_Modificar') IS NOT NULL THROW 62350, N'Ya existe un objeto de procedimiento; no se sobrescribe.',1;
    IF OBJECT_ID(N'dbo.SP_Carritos_Fusionar') IS NOT NULL THROW 62350, N'Ya existe un objeto de procedimiento; no se sobrescribe.',1;

    EXEC sys.sp_executesql N'CREATE PROCEDURE dbo.SP_Carritos_ObtenerActivo
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
 IF @TokenInvitado IS NOT NULL THROW 62500,N''Identidad ambigua.'',1;
END ELSE IF @TokenInvitado IS NULL OR DATALENGTH(@TokenInvitado)<>32 OR @IdSesion IS NOT NULL
THROW 62501,N''Identidad de invitado inválida.'',1;
DECLARE @IdCarrito bigint=(SELECT IdCarrito FROM dbo.Carritos WHERE Estado=''ACTIVO''
AND ((@IdActor IS NOT NULL AND IdUsuario=@IdActor) OR (@IdActor IS NULL AND IdUsuario IS NULL AND TokenInvitadoHash=@TokenInvitado)));
IF @IdCarrito IS NULL BEGIN
 INSERT dbo.Carritos(IdUsuario,TokenInvitadoHash,Estado) VALUES(@IdActor,@TokenInvitado,''ACTIVO'');
 SET @IdCarrito=CONVERT(bigint,SCOPE_IDENTITY());
END;
SELECT @IdCarrito IdCarrito;
        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF XACT_STATE() <> 0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH;
END;';

    EXEC sys.sp_executesql N'CREATE PROCEDURE dbo.SP_Carritos_Consultar
@IdCarrito bigint,@IdActor bigint=NULL,@IdSesion uniqueidentifier=NULL,@TokenInvitado varbinary(max)=NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
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
SELECT IdCarrito,Estado,FechaUltimaActividadUTC,CONVERT(varchar(33),FechaUltimaActividadUTC,126) RevisionCarrito FROM dbo.Carritos WHERE IdCarrito=@IdCarrito;
SELECT d.IdDetalleCarrito,d.IdVariante,v.SKU,p.Nombre,v.Precio,d.Cantidad,
CONVERT(decimal(30,4),v.Precio)*CONVERT(decimal(10,0),d.Cantidad) SubtotalLinea,
CONVERT(bigint,e.CantidadFisica)-COALESCE(r.Reservada,0) Disponible,
CONVERT(bit,CASE WHEN v.EstaActiva=1 AND p.EstaActivo=1 AND c.EstaActiva=1 AND CONVERT(bigint,e.CantidadFisica)-COALESCE(r.Reservada,0)>=d.Cantidad THEN 1 ELSE 0 END) EstaDisponible
FROM dbo.DetallesCarrito d JOIN dbo.VariantesProducto v ON v.IdVariante=d.IdVariante
JOIN dbo.Productos p ON p.IdProducto=v.IdProducto JOIN dbo.Categorias c ON c.IdCategoria=p.IdCategoria
LEFT JOIN dbo.Existencias e ON e.IdVariante=v.IdVariante
OUTER APPLY(SELECT SUM(CONVERT(bigint,Cantidad)) Reservada FROM dbo.ReservasInventario
WHERE IdVariante=v.IdVariante AND Estado=''ACTIVA'' AND FechaExpiracionUTC>SYSUTCDATETIME()) r
WHERE d.IdCarrito=@IdCarrito ORDER BY d.IdVariante;
SELECT COALESCE(SUM(CONVERT(decimal(30,4),v.Precio)*CONVERT(decimal(10,0),d.Cantidad)),0) Subtotal,
CONVERT(decimal(19,4),0) Descuento
FROM dbo.DetallesCarrito d JOIN dbo.VariantesProducto v ON v.IdVariante=d.IdVariante WHERE d.IdCarrito=@IdCarrito;
END;';

    EXEC sys.sp_executesql N'CREATE PROCEDURE dbo.SP_Carritos_Modificar
@IdCarrito bigint,@Accion varchar(15),@IdVariante bigint=NULL,@Cantidad int=NULL,
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
END;
IF @Accion IS NULL OR @Accion NOT IN (''AGREGAR'',''FIJAR'',''QUITAR'',''VACIAR'') THROW 62502,N''Acción inválida.'',1;
IF NOT EXISTS(SELECT 1 FROM dbo.Carritos WITH(UPDLOCK,HOLDLOCK) WHERE IdCarrito=@IdCarrito AND Estado=''ACTIVO'')
THROW 62503,N''Carrito no activo.'',1;
IF EXISTS(SELECT 1 FROM dbo.Checkouts WHERE IdCarrito=@IdCarrito AND Estado IN (''INICIADO'',''RESERVADO''))
THROW 62504,N''Cancele o expire el checkout antes de modificar el carrito.'',1;
IF @Accion=''VACIAR'' DELETE dbo.DetallesCarrito WHERE IdCarrito=@IdCarrito;
ELSE IF @Accion=''QUITAR'' DELETE dbo.DetallesCarrito WHERE IdCarrito=@IdCarrito AND IdVariante=@IdVariante;
ELSE BEGIN
 IF @Cantidad IS NULL OR @Cantidad<=0 THROW 62505,N''Cantidad inválida.'',1;
 DECLARE @Anterior int=COALESCE((SELECT Cantidad FROM dbo.DetallesCarrito WHERE IdCarrito=@IdCarrito AND IdVariante=@IdVariante),0);
 DECLARE @Nueva bigint=CASE WHEN @Accion=''AGREGAR'' THEN CONVERT(bigint,@Anterior)+@Cantidad ELSE @Cantidad END;
 IF @Nueva>2147483647 OR NOT EXISTS(SELECT 1 FROM dbo.VariantesProducto v JOIN dbo.Productos p ON p.IdProducto=v.IdProducto
 JOIN dbo.Categorias c ON c.IdCategoria=p.IdCategoria WHERE v.IdVariante=@IdVariante AND v.EstaActiva=1 AND p.EstaActivo=1 AND c.EstaActiva=1)
 THROW 62506,N''Variante no disponible o cantidad fuera de rango.'',1;
 DECLARE @Fisica int,@Reservada bigint;
 SELECT @Fisica=CantidadFisica FROM dbo.Existencias WITH(UPDLOCK,HOLDLOCK) WHERE IdVariante=@IdVariante;
 SELECT @Reservada=COALESCE(SUM(CONVERT(bigint,Cantidad)),0) FROM dbo.ReservasInventario
 WHERE IdVariante=@IdVariante AND Estado=''ACTIVA'' AND FechaExpiracionUTC>SYSUTCDATETIME();
 IF @Nueva>@Anterior AND (@Fisica IS NULL OR @Nueva>CONVERT(bigint,@Fisica)-@Reservada)
 THROW 62507,N''Cantidad superior a la disponibilidad efectiva.'',1;
 IF @Anterior=0 INSERT dbo.DetallesCarrito(IdCarrito,IdVariante,Cantidad) VALUES(@IdCarrito,@IdVariante,CONVERT(int,@Nueva));
 ELSE UPDATE dbo.DetallesCarrito SET Cantidad=CONVERT(int,@Nueva),FechaActualizacionUTC=SYSUTCDATETIME() WHERE IdCarrito=@IdCarrito AND IdVariante=@IdVariante;
END;
UPDATE dbo.Carritos SET FechaUltimaActividadUTC=SYSUTCDATETIME() WHERE IdCarrito=@IdCarrito;
        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF XACT_STATE() <> 0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH;
END;';

    EXEC sys.sp_executesql N'CREATE PROCEDURE dbo.SP_Carritos_Fusionar
@IdActor bigint,@IdSesion uniqueidentifier,@IdCarritoInvitado bigint,@TokenInvitado varbinary(max)
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
EXEC dbo.SP_Interno_Autorizar @IdActor, @IdSesion, N''USUARIO'';

IF @TokenInvitado IS NULL OR DATALENGTH(@TokenInvitado)<>32 OR NOT EXISTS(SELECT 1 FROM dbo.Carritos
WHERE IdCarrito=@IdCarritoInvitado AND IdUsuario IS NULL AND TokenInvitadoHash=@TokenInvitado) THROW 62508,N''Invitado no autorizado.'',1;
DECLARE @Destino bigint=(SELECT IdCarrito FROM dbo.Carritos WHERE IdUsuario=@IdActor AND Estado=''ACTIVO'');
IF EXISTS(SELECT 1 FROM dbo.Carritos WHERE IdCarrito=@IdCarritoInvitado AND Estado=''FUSIONADO'') BEGIN
 DECLARE @FusionDestino bigint=(SELECT TOP(1) TRY_CONVERT(bigint,JSON_VALUE(DatosNuevos,''$.IdCarritoDestino''))
 FROM dbo.EventosAuditoria WHERE Entidad=''Carritos'' AND IdEntidad=@IdCarritoInvitado AND Accion=''FUSIONAR'' AND IdUsuarioActor=@IdActor ORDER BY IdEventoAuditoria);
 IF @FusionDestino IS NULL THROW 62509,N''Carrito fusionado por otra operación.'',1;
 SELECT @FusionDestino IdCarrito; COMMIT TRANSACTION; RETURN;
END;
IF NOT EXISTS(SELECT 1 FROM dbo.Carritos WHERE IdCarrito=@IdCarritoInvitado AND Estado=''ACTIVO'')
OR EXISTS(SELECT 1 FROM dbo.Checkouts WHERE IdCarrito IN (@IdCarritoInvitado,@Destino) AND Estado IN (''INICIADO'',''RESERVADO''))
THROW 62510,N''Carrito inactivo o checkout pendiente.'',1;
IF @Destino IS NULL BEGIN INSERT dbo.Carritos(IdUsuario,Estado) VALUES(@IdActor,''ACTIVO''); SET @Destino=CONVERT(bigint,SCOPE_IDENTITY()); END;
DECLARE @Lineas TABLE(IdVariante bigint PRIMARY KEY,Cantidad bigint);
INSERT @Lineas SELECT IdVariante,SUM(CONVERT(bigint,Cantidad)) FROM dbo.DetallesCarrito WHERE IdCarrito IN (@Destino,@IdCarritoInvitado) GROUP BY IdVariante;
IF EXISTS(SELECT 1 FROM @Lineas l LEFT JOIN dbo.Existencias e ON e.IdVariante=l.IdVariante
LEFT JOIN dbo.VariantesProducto v ON v.IdVariante=l.IdVariante LEFT JOIN dbo.Productos p ON p.IdProducto=v.IdProducto
LEFT JOIN dbo.Categorias c ON c.IdCategoria=p.IdCategoria
OUTER APPLY(SELECT SUM(CONVERT(bigint,Cantidad)) Reservada FROM dbo.ReservasInventario
WHERE IdVariante=l.IdVariante AND Estado=''ACTIVA'' AND FechaExpiracionUTC>SYSUTCDATETIME()) r
WHERE l.Cantidad>2147483647 OR e.IdVariante IS NULL OR v.EstaActiva<>1 OR p.EstaActivo<>1 OR c.EstaActiva<>1
OR l.Cantidad>CONVERT(bigint,e.CantidadFisica)-COALESCE(r.Reservada,0))
THROW 62511,N''La fusión excede disponibilidad; ajuste cantidades antes de fusionar.'',1;
UPDATE d SET Cantidad=CONVERT(int,l.Cantidad),FechaActualizacionUTC=SYSUTCDATETIME()
FROM dbo.DetallesCarrito d JOIN @Lineas l ON l.IdVariante=d.IdVariante WHERE d.IdCarrito=@Destino;
INSERT dbo.DetallesCarrito(IdCarrito,IdVariante,Cantidad) SELECT @Destino,l.IdVariante,CONVERT(int,l.Cantidad) FROM @Lineas l
WHERE NOT EXISTS(SELECT 1 FROM dbo.DetallesCarrito d WHERE d.IdCarrito=@Destino AND d.IdVariante=l.IdVariante);
UPDATE dbo.Carritos SET Estado=''FUSIONADO'',FechaUltimaActividadUTC=SYSUTCDATETIME() WHERE IdCarrito=@IdCarritoInvitado;
UPDATE dbo.Carritos SET FechaUltimaActividadUTC=SYSUTCDATETIME() WHERE IdCarrito=@Destino;
DECLARE @FusionJSON nvarchar(max)=(SELECT @Destino IdCarritoDestino FOR JSON PATH,WITHOUT_ARRAY_WRAPPER);
INSERT dbo.EventosAuditoria(IdUsuarioActor,Accion,Entidad,IdEntidad,DatosNuevos) VALUES(@IdActor,''FUSIONAR'',''Carritos'',@IdCarritoInvitado,@FusionJSON);
SELECT @Destino IdCarrito;
        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF XACT_STATE() <> 0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH;
END;';

    EXEC sys.sp_executesql N'
        INSERT dbo.VersionesMigracion ([Version],NombreArchivo,SHA256,FechaAplicacionUTC,Ejecutor)
        VALUES (15,N''015_ProcedimientosCarritos.sql'',@Huella,SYSUTCDATETIME(),ORIGINAL_LOGIN());
    ',N'@Huella varbinary(32)',@Huella=@SHA256;
    COMMIT TRANSACTION;
    PRINT N'Migración 15 completada.';
END TRY
BEGIN CATCH
    IF XACT_STATE() <> 0 ROLLBACK TRANSACTION;
    THROW;
END CATCH;
