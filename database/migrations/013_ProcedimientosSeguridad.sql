/*
    013_ProcedimientosSeguridad.sql. Ejecutar completo, sin GO, con Auto-commit en ShopCart.
    SHA-256 final: suministrar 32 bytes mediante SESSION_CONTEXT,
    clave ShopCart.Migracion013.SHA256, misma conexión DataGrip.
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
    Creación de sesión y autenticación son endpoints SQL exclusivos del servicio de autenticación. No hay registro de refresh raíz separado: se crea junto a la sesión; rotación crea sus sucesores. La expiración de sesión es límite absoluto. Desactivar dirección usa GuardarDireccion con Activa=0.
*/
IF DB_NAME() <> N'ShopCart'
    THROW 62100, N'013 solo puede ejecutarse en la base ShopCart.', 1;

IF @@TRANCOUNT <> 0 OR (2 & @@OPTIONS) = 2
    THROW 62101, N'Inicie con Auto-commit y sin transacciones abiertas o implícitas.', 1;

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
    THROW 62102, N'Se requiere CONTROL sobre ShopCart para inspeccionar y crear el esquema.', 1;

IF NOT EXISTS (
    SELECT 1 FROM sys.databases
    WHERE database_id = DB_ID()
      AND collation_name = N'Latin1_General_100_CI_AI_SC'
      AND recovery_model_desc = N'SIMPLE'
      AND state_desc = N'ONLINE' AND user_access_desc = N'MULTI_USER'
      AND is_read_only = 0 AND source_database_id IS NULL
)
    THROW 62103, N'Las propiedades de ShopCart no coinciden con el arranque 001.', 1;

DECLARE @HuellaRecibida sql_variant = SESSION_CONTEXT(N'ShopCart.Migracion013.SHA256');
IF @HuellaRecibida IS NULL
   OR CONVERT(nvarchar(128), SQL_VARIANT_PROPERTY(@HuellaRecibida, 'BaseType')) NOT IN (N'binary', N'varbinary')
    THROW 62104, N'Suministre el SHA-256 real como valor binario en SESSION_CONTEXT antes de ejecutar 013.', 1;

DECLARE @SHA256 varbinary(max) = CONVERT(varbinary(max), @HuellaRecibida);
IF DATALENGTH(@SHA256) <> 32
    THROW 62105, N'La huella SHA-256 debe contener exactamente 32 bytes.', 1;

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
        THROW 62106, N'No se pudo obtener el bloqueo exclusivo de migraciones.', 1;

    DECLARE @IDVersiones int = OBJECT_ID(N'dbo.VersionesMigracion', N'U');
    IF @IDVersiones IS NULL
        THROW 62107, N'Falta la tabla técnica creada por 001. No se aplicará 013.', 1;

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
        THROW 62108, N'Las columnas de VersionesMigracion no cumplen el contrato de 001.', 1;

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
        THROW 62109, N'VersionesMigracion requiere la PK clustered de 001 sobre Version.', 1;

    IF EXISTS (SELECT 1 FROM sys.triggers WHERE parent_id = @IDVersiones)
       OR EXISTS (SELECT 1 FROM sys.tables WHERE object_id = @IDVersiones
                  AND (temporal_type <> 0 OR is_memory_optimized = 1))
        THROW 62110, N'VersionesMigracion tiene características inesperadas; revisar manualmente.', 1;

    -- Lote inferior: errores de compilación/resolución quedan dentro del TRY externo.
    EXEC sys.sp_executesql N'
        IF NOT EXISTS (
            SELECT 1 FROM dbo.VersionesMigracion WITH (UPDLOCK, HOLDLOCK)
            WHERE [Version] = 12 AND NombreArchivo = N''012_ProcedimientosCatalogo.sql''
        )
            THROW 62113, N''Debe estar registrada la migración 012_ProcedimientosCatalogo.sql antes de aplicar 013.'', 1;
        IF EXISTS (SELECT 1 FROM dbo.VersionesMigracion WITH (UPDLOCK, HOLDLOCK)
                   WHERE [Version] >= 13)
            THROW 62111, N''013 o una migración posterior ya está registrada. No se reaplica ni se certifica el esquema existente.'', 1;
    ';


    -- Rechaza nombres conflictivos antes de crear el primer procedimiento.
    IF OBJECT_ID(N'dbo.SP_Seguridad_RegistrarUsuario') IS NOT NULL THROW 62150, N'Ya existe un objeto de procedimiento; no se sobrescribe.',1;
    IF OBJECT_ID(N'dbo.SP_Seguridad_ObtenerAutenticacion') IS NOT NULL THROW 62150, N'Ya existe un objeto de procedimiento; no se sobrescribe.',1;
    IF OBJECT_ID(N'dbo.SP_Seguridad_ConsultarPerfil') IS NOT NULL THROW 62150, N'Ya existe un objeto de procedimiento; no se sobrescribe.',1;
    IF OBJECT_ID(N'dbo.SP_Seguridad_ActualizarPerfil') IS NOT NULL THROW 62150, N'Ya existe un objeto de procedimiento; no se sobrescribe.',1;
    IF OBJECT_ID(N'dbo.SP_Seguridad_CrearSesion') IS NOT NULL THROW 62150, N'Ya existe un objeto de procedimiento; no se sobrescribe.',1;
    IF OBJECT_ID(N'dbo.SP_Seguridad_ConsultarSesion') IS NOT NULL THROW 62150, N'Ya existe un objeto de procedimiento; no se sobrescribe.',1;
    IF OBJECT_ID(N'dbo.SP_Seguridad_RotarToken') IS NOT NULL THROW 62150, N'Ya existe un objeto de procedimiento; no se sobrescribe.',1;
    IF OBJECT_ID(N'dbo.SP_Seguridad_RevocarSesiones') IS NOT NULL THROW 62150, N'Ya existe un objeto de procedimiento; no se sobrescribe.',1;
    IF OBJECT_ID(N'dbo.SP_Seguridad_RevocarToken') IS NOT NULL THROW 62150, N'Ya existe un objeto de procedimiento; no se sobrescribe.',1;
    IF OBJECT_ID(N'dbo.SP_Seguridad_AdministrarUsuario') IS NOT NULL THROW 62150, N'Ya existe un objeto de procedimiento; no se sobrescribe.',1;
    IF OBJECT_ID(N'dbo.SP_Seguridad_ListarDirecciones') IS NOT NULL THROW 62150, N'Ya existe un objeto de procedimiento; no se sobrescribe.',1;
    IF OBJECT_ID(N'dbo.SP_Seguridad_GuardarDireccion') IS NOT NULL THROW 62150, N'Ya existe un objeto de procedimiento; no se sobrescribe.',1;

    EXEC sys.sp_executesql N'CREATE PROCEDURE dbo.SP_Seguridad_RegistrarUsuario
@Nombre nvarchar(max),@Apellido nvarchar(max),@Correo nvarchar(max),@HashContrasena nvarchar(max)
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
IF @Nombre IS NULL OR LEN(LTRIM(RTRIM(@Nombre)))=0 OR DATALENGTH(@Nombre)>200
THROW 62003,N''Texto obligatorio vacío o longitud no válida.'',1;
IF @Apellido IS NULL OR LEN(LTRIM(RTRIM(@Apellido)))=0 OR DATALENGTH(@Apellido)>200
THROW 62003,N''Texto obligatorio vacío o longitud no válida.'',1;
IF @Correo IS NULL OR LEN(LTRIM(RTRIM(@Correo)))=0 OR DATALENGTH(@Correo)>508
THROW 62003,N''Texto obligatorio vacío o longitud no válida.'',1;
IF @HashContrasena IS NULL OR LEN(LTRIM(RTRIM(@HashContrasena)))=0 OR DATALENGTH(@HashContrasena)>510
THROW 62003,N''Texto obligatorio vacío o longitud no válida.'',1;

IF LEFT(@HashContrasena,10)<>N''$argon2id$'' THROW 62300,N''El backend debe aportar un hash Argon2id válido.'',1;
SET @Correo=LOWER(LTRIM(RTRIM(@Correo)));
IF CHARINDEX(N''@'',@Correo)<2 THROW 62301,N''Correo inválido.'',1;
DECLARE @IdRol tinyint=(SELECT IdRol FROM dbo.Roles WHERE Nombre=N''Cliente'');
IF @IdRol IS NULL THROW 62302,N''Falta el rol Cliente; aplique las semillas aprobadas.'',1;
INSERT dbo.Usuarios(IdRol,Nombre,Apellido,CorreoElectronico,HashContrasena)
VALUES(@IdRol,LTRIM(RTRIM(@Nombre)),LTRIM(RTRIM(@Apellido)),@Correo,@HashContrasena);
DECLARE @Id bigint=CONVERT(bigint,SCOPE_IDENTITY());
INSERT dbo.EventosAuditoria(IdUsuarioActor,Accion,Entidad,IdEntidad) VALUES(@Id,N''REGISTRAR'',N''Usuarios'',@Id);
SELECT @Id IdUsuario;
        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF XACT_STATE() <> 0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH;
END;';

    EXEC sys.sp_executesql N'CREATE PROCEDURE dbo.SP_Seguridad_ObtenerAutenticacion
@Correo nvarchar(max)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
IF @Correo IS NULL OR LEN(LTRIM(RTRIM(@Correo)))=0 OR DATALENGTH(@Correo)>508
THROW 62003,N''Texto obligatorio vacío o longitud no válida.'',1;

-- Solo servicio de autenticación: nunca publicar este resultado como respuesta HTTP.
SELECT IdUsuario,HashContrasena,EstaActivo FROM dbo.Usuarios WHERE CorreoElectronico=LOWER(LTRIM(RTRIM(@Correo)));
END;';

    EXEC sys.sp_executesql N'CREATE PROCEDURE dbo.SP_Seguridad_ConsultarPerfil
@IdActor bigint,@IdSesion uniqueidentifier
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
EXEC dbo.SP_Interno_Autorizar @IdActor, @IdSesion, N''USUARIO'';

SELECT u.IdUsuario,u.Nombre,u.Apellido,u.CorreoElectronico,u.EstaActivo,r.Nombre Rol
FROM dbo.Usuarios u JOIN dbo.Roles r ON r.IdRol=u.IdRol WHERE u.IdUsuario=@IdActor;
SELECT IdRol,Nombre FROM dbo.Roles ORDER BY IdRol;
END;';

    EXEC sys.sp_executesql N'CREATE PROCEDURE dbo.SP_Seguridad_ActualizarPerfil
@IdActor bigint,@IdSesion uniqueidentifier,@Nombre nvarchar(max),@Apellido nvarchar(max)
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
IF @Nombre IS NULL OR LEN(LTRIM(RTRIM(@Nombre)))=0 OR DATALENGTH(@Nombre)>200
THROW 62003,N''Texto obligatorio vacío o longitud no válida.'',1;
IF @Apellido IS NULL OR LEN(LTRIM(RTRIM(@Apellido)))=0 OR DATALENGTH(@Apellido)>200
THROW 62003,N''Texto obligatorio vacío o longitud no válida.'',1;

DECLARE @Antes nvarchar(max)=(SELECT Nombre,Apellido FROM dbo.Usuarios WHERE IdUsuario=@IdActor FOR JSON PATH,WITHOUT_ARRAY_WRAPPER);
UPDATE dbo.Usuarios SET Nombre=LTRIM(RTRIM(@Nombre)),Apellido=LTRIM(RTRIM(@Apellido)),FechaActualizacionUTC=SYSUTCDATETIME() WHERE IdUsuario=@IdActor;
DECLARE @Despues nvarchar(max)=(SELECT Nombre,Apellido FROM dbo.Usuarios WHERE IdUsuario=@IdActor FOR JSON PATH,WITHOUT_ARRAY_WRAPPER);
INSERT dbo.EventosAuditoria (IdUsuarioActor,Accion,Entidad,IdEntidad,DatosAnteriores,DatosNuevos)
VALUES (@IdActor,N''PERFIL'',N''Usuarios'',@IdActor,@Antes,@Despues);

        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF XACT_STATE() <> 0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH;
END;';

    EXEC sys.sp_executesql N'CREATE PROCEDURE dbo.SP_Seguridad_CrearSesion
@IdUsuario bigint,@HashToken varbinary(max),@FechaExpiracionUTC datetime2(7),@DireccionIP varchar(max)=NULL,@Agente nvarchar(max)=NULL
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

-- Punto de confianza: solo servicio que ACABA de verificar contraseña/MFA, nunca EXECUTE de cliente.
IF @HashToken IS NULL OR DATALENGTH(@HashToken)<>32 OR @FechaExpiracionUTC IS NULL
OR @FechaExpiracionUTC<=SYSUTCDATETIME() OR DATALENGTH(@DireccionIP)>45 OR DATALENGTH(@Agente)>1000
OR NOT EXISTS(SELECT 1 FROM dbo.Usuarios WHERE IdUsuario=@IdUsuario AND EstaActivo=1)
THROW 62303,N''Sesión inválida.'',1;
DECLARE @Sesion uniqueidentifier=NEWID();
INSERT dbo.SesionesUsuario(IdSesion,IdUsuario,FechaExpiracionUTC,DireccionIP,AgenteUsuario)
VALUES(@Sesion,@IdUsuario,@FechaExpiracionUTC,@DireccionIP,@Agente);
INSERT dbo.TokensRenovacion(IdSesion,HashToken,FechaExpiracionUTC) VALUES(@Sesion,@HashToken,@FechaExpiracionUTC);
SELECT @Sesion IdSesion;
        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF XACT_STATE() <> 0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH;
END;';

    EXEC sys.sp_executesql N'CREATE PROCEDURE dbo.SP_Seguridad_ConsultarSesion
@IdActor bigint,@IdSesion uniqueidentifier
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
EXEC dbo.SP_Interno_Autorizar @IdActor, @IdSesion, N''USUARIO'';

SELECT IdSesion,IdUsuario,FechaCreacionUTC,FechaExpiracionUTC FROM dbo.SesionesUsuario WHERE IdSesion=@IdSesion;
END;';

    EXEC sys.sp_executesql N'CREATE PROCEDURE dbo.SP_Seguridad_RotarToken
@HashAnterior varbinary(max),@HashNuevo varbinary(max),@NuevaExpiracionUTC datetime2(7)
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

IF @HashAnterior IS NULL OR DATALENGTH(@HashAnterior)<>32 OR @HashNuevo IS NULL OR DATALENGTH(@HashNuevo)<>32
OR @HashAnterior=@HashNuevo OR @NuevaExpiracionUTC IS NULL OR @NuevaExpiracionUTC<=SYSUTCDATETIME()
THROW 62304,N''Parámetros de rotación inválidos.'',1;
DECLARE @Token bigint,@Sesion uniqueidentifier,@Usuario bigint,@Usado datetime2(7),@Revocado datetime2(7),@Exp datetime2(7),@Limite datetime2(7);
SELECT @Token=t.IdTokenRenovacion,@Sesion=t.IdSesion,@Usado=t.FechaUsoUTC,@Revocado=t.FechaRevocacionUTC,
@Exp=t.FechaExpiracionUTC,@Usuario=s.IdUsuario,@Limite=s.FechaExpiracionUTC
FROM dbo.TokensRenovacion t WITH(UPDLOCK,HOLDLOCK) JOIN dbo.SesionesUsuario s ON s.IdSesion=t.IdSesion WHERE t.HashToken=@HashAnterior;
IF @Token IS NULL THROW 62305,N''Token inválido.'',1;
IF @Usado IS NOT NULL OR @Revocado IS NOT NULL BEGIN
 UPDATE dbo.SesionesUsuario SET FechaRevocacionUTC=COALESCE(FechaRevocacionUTC,SYSUTCDATETIME()),MotivoRevocacion=N''Reutilización de refresh'' WHERE IdSesion=@Sesion;
 UPDATE dbo.TokensRenovacion SET FechaRevocacionUTC=COALESCE(FechaRevocacionUTC,SYSUTCDATETIME()),MotivoRevocacion=N''Reutilización'' WHERE IdSesion=@Sesion;
 -- Persistir revocación ANTES de informar el rechazo; THROW posterior no se revierte.
 COMMIT TRANSACTION;
 THROW 62306,N''Reutilización detectada; sesión revocada.'',1;
END;
IF @Exp<=SYSUTCDATETIME() OR @Limite<=SYSUTCDATETIME() OR @NuevaExpiracionUTC>@Limite
OR NOT EXISTS(SELECT 1 FROM dbo.SesionesUsuario s JOIN dbo.Usuarios u ON u.IdUsuario=s.IdUsuario
WHERE s.IdSesion=@Sesion AND s.FechaRevocacionUTC IS NULL AND u.EstaActivo=1)
THROW 62307,N''Sesión o token expirado.'',1;
UPDATE dbo.TokensRenovacion SET FechaUsoUTC=SYSUTCDATETIME(),FechaRevocacionUTC=SYSUTCDATETIME(),MotivoRevocacion=N''Rotación''
WHERE IdTokenRenovacion=@Token AND FechaUsoUTC IS NULL AND FechaRevocacionUTC IS NULL;
IF @@ROWCOUNT<>1 THROW 62308,N''Conflicto de rotación.'',1;
INSERT dbo.TokensRenovacion(IdSesion,HashToken,IdTokenAnterior,FechaExpiracionUTC)
VALUES(@Sesion,@HashNuevo,@Token,@NuevaExpiracionUTC);
UPDATE dbo.SesionesUsuario SET FechaUltimaActividadUTC=SYSUTCDATETIME() WHERE IdSesion=@Sesion;
SELECT @Sesion IdSesion,@Usuario IdUsuario;
        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF XACT_STATE() <> 0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH;
END;';

    EXEC sys.sp_executesql N'CREATE PROCEDURE dbo.SP_Seguridad_RevocarSesiones
@IdActor bigint,@IdSesion uniqueidentifier,@Todas bit=0
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

IF @Todas IS NULL THROW 62309,N''Indicador inválido.'',1;
UPDATE dbo.SesionesUsuario SET FechaRevocacionUTC=COALESCE(FechaRevocacionUTC,SYSUTCDATETIME()),MotivoRevocacion=N''Cierre de sesión''
WHERE IdUsuario=@IdActor AND (@Todas=1 OR IdSesion=@IdSesion);
UPDATE t SET FechaRevocacionUTC=COALESCE(t.FechaRevocacionUTC,SYSUTCDATETIME()),MotivoRevocacion=N''Cierre de sesión''
FROM dbo.TokensRenovacion t JOIN dbo.SesionesUsuario s ON s.IdSesion=t.IdSesion
WHERE s.IdUsuario=@IdActor AND (@Todas=1 OR s.IdSesion=@IdSesion);
        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF XACT_STATE() <> 0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH;
END;';

    EXEC sys.sp_executesql N'CREATE PROCEDURE dbo.SP_Seguridad_RevocarToken
@IdActor bigint,@IdSesion uniqueidentifier,@IdToken bigint
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

IF NOT EXISTS(SELECT 1 FROM dbo.TokensRenovacion t JOIN dbo.SesionesUsuario s ON s.IdSesion=t.IdSesion WHERE t.IdTokenRenovacion=@IdToken AND s.IdUsuario=@IdActor)
THROW 62310,N''Token no autorizado.'',1;
-- Revocar la sesión completa evita dejar descendientes utilizables.
DECLARE @Objetivo uniqueidentifier=(SELECT IdSesion FROM dbo.TokensRenovacion WHERE IdTokenRenovacion=@IdToken);
UPDATE dbo.SesionesUsuario SET FechaRevocacionUTC=COALESCE(FechaRevocacionUTC,SYSUTCDATETIME()),MotivoRevocacion=N''Revocación de token'' WHERE IdSesion=@Objetivo;
UPDATE dbo.TokensRenovacion SET FechaRevocacionUTC=COALESCE(FechaRevocacionUTC,SYSUTCDATETIME()),MotivoRevocacion=N''Revocación de token'' WHERE IdSesion=@Objetivo;
        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF XACT_STATE() <> 0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH;
END;';

    EXEC sys.sp_executesql N'CREATE PROCEDURE dbo.SP_Seguridad_AdministrarUsuario
@IdActor bigint,@IdSesion uniqueidentifier,@IdUsuario bigint,@Rol nvarchar(max),@EstaActivo bit
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
EXEC dbo.SP_Interno_Autorizar @IdActor, @IdSesion, N''ADMINISTRADOR'';
IF @Rol IS NULL OR LEN(LTRIM(RTRIM(@Rol)))=0 OR DATALENGTH(@Rol)>60
THROW 62003,N''Texto obligatorio vacío o longitud no válida.'',1;

DECLARE @IdRol tinyint=(SELECT IdRol FROM dbo.Roles WHERE Nombre=@Rol);
IF @IdRol IS NULL OR @EstaActivo IS NULL OR NOT EXISTS(SELECT 1 FROM dbo.Usuarios WHERE IdUsuario=@IdUsuario)
THROW 62311,N''Usuario o rol inválido.'',1;
IF @IdUsuario=@IdActor AND (@EstaActivo=0 OR @Rol<>N''Administrador'') THROW 62312,N''No puede retirar su propio acceso administrativo.'',1;
DECLARE @Antes nvarchar(max)=(SELECT IdUsuario,IdRol,EstaActivo FROM dbo.Usuarios WHERE IdUsuario=@IdUsuario FOR JSON PATH,WITHOUT_ARRAY_WRAPPER);
UPDATE dbo.Usuarios SET IdRol=@IdRol,EstaActivo=@EstaActivo,FechaActualizacionUTC=SYSUTCDATETIME() WHERE IdUsuario=@IdUsuario;
UPDATE dbo.SesionesUsuario SET FechaRevocacionUTC=COALESCE(FechaRevocacionUTC,SYSUTCDATETIME()),MotivoRevocacion=N''Cambio administrativo'' WHERE IdUsuario=@IdUsuario;
UPDATE t SET FechaRevocacionUTC=COALESCE(t.FechaRevocacionUTC,SYSUTCDATETIME()),MotivoRevocacion=N''Cambio administrativo''
FROM dbo.TokensRenovacion t JOIN dbo.SesionesUsuario s ON s.IdSesion=t.IdSesion WHERE s.IdUsuario=@IdUsuario;
DECLARE @Despues nvarchar(max)=(SELECT IdUsuario,IdRol,EstaActivo FROM dbo.Usuarios WHERE IdUsuario=@IdUsuario FOR JSON PATH,WITHOUT_ARRAY_WRAPPER);
INSERT dbo.EventosAuditoria (IdUsuarioActor,Accion,Entidad,IdEntidad,DatosAnteriores,DatosNuevos)
VALUES (@IdActor,N''ADMINISTRAR'',N''Usuarios'',@IdUsuario,@Antes,@Despues);

        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF XACT_STATE() <> 0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH;
END;';

    EXEC sys.sp_executesql N'CREATE PROCEDURE dbo.SP_Seguridad_ListarDirecciones
@IdActor bigint,@IdSesion uniqueidentifier
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
EXEC dbo.SP_Interno_Autorizar @IdActor, @IdSesion, N''USUARIO'';

SELECT IdDireccion,NombreDestinatario,TelefonoContacto,Departamento,Municipio,DireccionLinea1,DireccionLinea2,Referencias,CodigoPostal,EsPredeterminada,EstaActiva
FROM dbo.Direcciones WHERE IdUsuario=@IdActor ORDER BY EsPredeterminada DESC,IdDireccion;
END;';

    EXEC sys.sp_executesql N'CREATE PROCEDURE dbo.SP_Seguridad_GuardarDireccion
@IdActor bigint,@IdSesion uniqueidentifier,@Nombre nvarchar(max),@Telefono nvarchar(max),
@Departamento nvarchar(max),@Municipio nvarchar(max),@Linea1 nvarchar(max),@Linea2 nvarchar(max)=NULL,
@Referencias nvarchar(max)=NULL,@CodigoPostal nvarchar(max)=NULL,@Predeterminada bit=0,@Activa bit=1,@IdDireccion bigint=NULL
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
IF @Nombre IS NULL OR LEN(LTRIM(RTRIM(@Nombre)))=0 OR DATALENGTH(@Nombre)>300
THROW 62003,N''Texto obligatorio vacío o longitud no válida.'',1;
IF @Telefono IS NULL OR LEN(LTRIM(RTRIM(@Telefono)))=0 OR DATALENGTH(@Telefono)>50
THROW 62003,N''Texto obligatorio vacío o longitud no válida.'',1;
IF @Departamento IS NULL OR LEN(LTRIM(RTRIM(@Departamento)))=0 OR DATALENGTH(@Departamento)>200
THROW 62003,N''Texto obligatorio vacío o longitud no válida.'',1;
IF @Municipio IS NULL OR LEN(LTRIM(RTRIM(@Municipio)))=0 OR DATALENGTH(@Municipio)>200
THROW 62003,N''Texto obligatorio vacío o longitud no válida.'',1;
IF @Linea1 IS NULL OR LEN(LTRIM(RTRIM(@Linea1)))=0 OR DATALENGTH(@Linea1)>500
THROW 62003,N''Texto obligatorio vacío o longitud no válida.'',1;

IF DATALENGTH(@Linea2)>500 OR DATALENGTH(@Referencias)>1000 OR DATALENGTH(@CodigoPostal)>30 OR @Predeterminada IS NULL OR @Activa IS NULL
THROW 62313,N''Dirección inválida.'',1;
IF @IdDireccion IS NOT NULL AND NOT EXISTS(SELECT 1 FROM dbo.Direcciones WHERE IdDireccion=@IdDireccion AND IdUsuario=@IdActor)
THROW 62314,N''Dirección no autorizada.'',1;
IF @Predeterminada=1 AND @Activa=1 UPDATE dbo.Direcciones SET EsPredeterminada=0,FechaActualizacionUTC=SYSUTCDATETIME() WHERE IdUsuario=@IdActor AND EsPredeterminada=1;
IF @IdDireccion IS NULL BEGIN
 INSERT dbo.Direcciones(IdUsuario,NombreDestinatario,TelefonoContacto,Departamento,Municipio,DireccionLinea1,DireccionLinea2,Referencias,CodigoPostal,EsPredeterminada,EstaActiva)
 VALUES(@IdActor,LTRIM(RTRIM(@Nombre)),LTRIM(RTRIM(@Telefono)),LTRIM(RTRIM(@Departamento)),LTRIM(RTRIM(@Municipio)),LTRIM(RTRIM(@Linea1)),@Linea2,@Referencias,@CodigoPostal,@Predeterminada,@Activa);
 SET @IdDireccion=CONVERT(bigint,SCOPE_IDENTITY());
END ELSE
 UPDATE dbo.Direcciones SET NombreDestinatario=LTRIM(RTRIM(@Nombre)),TelefonoContacto=LTRIM(RTRIM(@Telefono)),Departamento=LTRIM(RTRIM(@Departamento)),
 Municipio=LTRIM(RTRIM(@Municipio)),DireccionLinea1=LTRIM(RTRIM(@Linea1)),DireccionLinea2=@Linea2,Referencias=@Referencias,CodigoPostal=@CodigoPostal,
 EsPredeterminada=@Predeterminada,EstaActiva=@Activa,FechaActualizacionUTC=SYSUTCDATETIME() WHERE IdDireccion=@IdDireccion AND IdUsuario=@IdActor;
SELECT @IdDireccion IdDireccion;
        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF XACT_STATE() <> 0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH;
END;';

    EXEC sys.sp_executesql N'
        INSERT dbo.VersionesMigracion ([Version],NombreArchivo,SHA256,FechaAplicacionUTC,Ejecutor)
        VALUES (13,N''013_ProcedimientosSeguridad.sql'',@Huella,SYSUTCDATETIME(),ORIGINAL_LOGIN());
    ',N'@Huella varbinary(32)',@Huella=@SHA256;
    COMMIT TRANSACTION;
    PRINT N'Migración 13 completada.';
END TRY
BEGIN CATCH
    IF XACT_STATE() <> 0 ROLLBACK TRANSACTION;
    THROW;
END CATCH;
