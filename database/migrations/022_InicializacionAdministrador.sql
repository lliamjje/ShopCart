/*
    022_InicializacionAdministrador.sql — Inicialización administrativa de un solo uso.
    Ejecutar COMPLETO en ShopCart, en Auto-commit y como un único lote SIN GO.
    Preparado para revisión: este archivo no autoriza su ejecución.

    Configurar previamente mediante sys.sp_set_session_context, EN LA MISMA
    conexión administrativa (no desde la API ni con shopcart_service):
      ShopCart.Migracion022.IdUsuario : bigint positivo, no texto ni int.
      ShopCart.Migracion022.Correo    : nvarchar, correo exacto ya normalizado.
      ShopCart.Migracion022.SHA256    : binary/varbinary de exactamente 32 bytes.
    No hay valores predeterminados. Obtener ID y correo mediante revisión previa
    del responsable; elegir una cuenta registrada cuya contraseña controle.
    Calcular SHA-256 sobre los bytes del archivo FINAL aprobado con Get-FileHash;
    no incrustar el hash ni datos personales en este archivo. SQL comprueba el
    formato de la huella; el ejecutor debe comprobar su correspondencia real.
    No mostrar estos parámetros en registros. Limpiar las tres claves después
    del éxito O del error, o cerrar la conexión administrativa dedicada.
    No marcar claves read_only si se pretende limpiarlas en esa misma conexión.

    No crea cuentas, contraseñas, roles, SP ni permisos. Solo cambia Usuarios.IdRol.
    No actualiza fechas, sesiones ni tokens. Como el backend revalida el rol SQL,
    RECHAZA una cuenta con sesiones vigentes para no elevar sesiones ya abiertas.
    Cerrar previamente esas sesiones por el flujo legítimo; después de aplicar,
    iniciar sesión de nuevo. No usar esta migración para administrar otros usuarios.

    Exige evidencia REGISTRAR del SP de registro y hash Argon2id. Esa evidencia
    respeta el contrato existente, pero no es prueba criptográfica del origen HTTP
    frente a un administrador capaz de modificar tablas. Se confía en el ejecutor
    administrativo autorizado, identificado mediante ORIGINAL_LOGIN en auditoría.
    Los bloqueos de tabla también impiden promociones concurrentes que no usen
    los applocks. Las cuentas privilegiadas pueden alterar controles/historial;
    este mecanismo no pretende impedir intervenciones administrativas deliberadas.
*/
IF DB_NAME() <> N'ShopCart'
    THROW 64100, N'022 solo puede ejecutarse en ShopCart.', 1;
IF @@TRANCOUNT <> 0 OR (2 & @@OPTIONS) = 2
    THROW 64101, N'Inicie con Auto-commit y sin transacciones abiertas o implícitas.', 1;

SET NOCOUNT ON;
SET XACT_ABORT ON;
SET ANSI_NULLS ON;
SET ANSI_PADDING ON;
SET ANSI_WARNINGS ON;
SET ARITHABORT ON;
SET CONCAT_NULL_YIELDS_NULL ON;
SET QUOTED_IDENTIFIER ON;
SET NUMERIC_ROUNDABORT OFF;

IF COALESCE(HAS_PERMS_BY_NAME(DB_NAME(), N'DATABASE', N'CONTROL'), 0) <> 1
    THROW 64102, N'Se requiere una conexión administrativa con CONTROL sobre ShopCart.', 1;
IF NOT EXISTS (
    SELECT 1 FROM sys.databases WHERE database_id = DB_ID()
      AND collation_name = N'Latin1_General_100_CI_AI_SC'
      AND recovery_model_desc = N'SIMPLE' AND state_desc = N'ONLINE'
      AND user_access_desc = N'MULTI_USER' AND is_read_only = 0
      AND source_database_id IS NULL
)
    THROW 64103, N'Las propiedades de ShopCart no coinciden con el arranque aprobado.', 1;

DECLARE @UsuarioRecibido sql_variant = SESSION_CONTEXT(N'ShopCart.Migracion022.IdUsuario');
DECLARE @CorreoRecibido sql_variant = SESSION_CONTEXT(N'ShopCart.Migracion022.Correo');
DECLARE @HuellaRecibida sql_variant = SESSION_CONTEXT(N'ShopCart.Migracion022.SHA256');
IF @UsuarioRecibido IS NULL
   OR CONVERT(nvarchar(128), SQL_VARIANT_PROPERTY(@UsuarioRecibido, 'BaseType')) <> N'bigint'
    THROW 64104, N'Suministre explícitamente el ID objetivo como bigint en SESSION_CONTEXT.', 1;
DECLARE @IdUsuario bigint = CONVERT(bigint, @UsuarioRecibido);
IF @IdUsuario <= 0
    THROW 64105, N'El ID objetivo debe ser positivo.', 1;
IF @CorreoRecibido IS NULL
   OR CONVERT(nvarchar(128), SQL_VARIANT_PROPERTY(@CorreoRecibido, 'BaseType')) <> N'nvarchar'
    THROW 64106, N'Suministre explícitamente el correo objetivo como nvarchar en SESSION_CONTEXT.', 1;
-- Validar antes de reducir la longitud para evitar truncamientos silenciosos.
DECLARE @CorreoLargo nvarchar(max) = CONVERT(nvarchar(max), @CorreoRecibido);
IF DATALENGTH(@CorreoLargo) NOT BETWEEN 6 AND 508
   OR DATALENGTH(@CorreoLargo) <> DATALENGTH(LTRIM(RTRIM(@CorreoLargo)))
   OR @CorreoLargo COLLATE Latin1_General_100_BIN2 <> LOWER(@CorreoLargo) COLLATE Latin1_General_100_BIN2
   OR CHARINDEX(N'@', @CorreoLargo) < 2
   OR CHARINDEX(N'@', @CorreoLargo) >= LEN(@CorreoLargo)
   OR CHARINDEX(N'@', @CorreoLargo, CHARINDEX(N'@', @CorreoLargo) + 1) > 0
   OR CHARINDEX(N' ', @CorreoLargo) > 0 OR CHARINDEX(NCHAR(9), @CorreoLargo) > 0
   OR CHARINDEX(NCHAR(10), @CorreoLargo) > 0 OR CHARINDEX(NCHAR(13), @CorreoLargo) > 0
    THROW 64107, N'El correo objetivo no cumple el formato normalizado requerido.', 1;
DECLARE @Correo nvarchar(254) = CONVERT(nvarchar(254), @CorreoLargo);
IF @HuellaRecibida IS NULL
   OR CONVERT(nvarchar(128), SQL_VARIANT_PROPERTY(@HuellaRecibida, 'BaseType')) NOT IN (N'binary', N'varbinary')
    THROW 64108, N'Suministre el SHA-256 real como valor binario en SESSION_CONTEXT.', 1;
DECLARE @SHA256 varbinary(max) = CONVERT(varbinary(max), @HuellaRecibida);
IF DATALENGTH(@SHA256) <> 32
    THROW 64109, N'La huella SHA-256 debe contener exactamente 32 bytes.', 1;

BEGIN TRY
    BEGIN TRANSACTION;
    DECLARE @Bloqueo int;
    EXEC @Bloqueo = sys.sp_getapplock
        @Resource = N'ShopCart.Migraciones', @LockMode = N'Exclusive',
        @LockOwner = N'Transaction', @LockTimeout = 0;
    IF @Bloqueo < 0
        THROW 64110, N'No se obtuvo el bloqueo exclusivo de migraciones.', 1;
    EXEC @Bloqueo = sys.sp_getapplock
        @Resource = N'ShopCart.Negocio', @LockMode = N'Exclusive',
        @LockOwner = N'Transaction', @LockTimeout = 10000;
    IF @Bloqueo < 0
        THROW 64111, N'No se obtuvo el bloqueo exclusivo de negocio.', 1;

    IF OBJECT_ID(N'dbo.VersionesMigracion', N'U') IS NULL
       OR OBJECT_ID(N'dbo.Roles', N'U') IS NULL
       OR OBJECT_ID(N'dbo.Usuarios', N'U') IS NULL
       OR OBJECT_ID(N'dbo.SesionesUsuario', N'U') IS NULL
       OR OBJECT_ID(N'dbo.EventosAuditoria', N'U') IS NULL
        THROW 64112, N'Faltan tablas requeridas por las migraciones anteriores.', 1;
    -- No aceptar efectos laterales inesperados al actualizar o insertar.
    IF EXISTS (
        SELECT 1 FROM sys.triggers WHERE parent_id IN (
            OBJECT_ID(N'dbo.Usuarios'), OBJECT_ID(N'dbo.EventosAuditoria'),
            OBJECT_ID(N'dbo.VersionesMigracion'))
    )
        THROW 64113, N'Hay triggers adicionales; revisar sus efectos antes de inicializar.', 1;

    -- SQL constante y parámetros tipados: errores de resolución/compilación de este
    -- ámbito inferior alcanzan el CATCH externo; no se concatena ningún valor.
    EXEC sys.sp_executesql N'
IF NOT EXISTS (
    SELECT 1 FROM dbo.VersionesMigracion WITH (UPDLOCK, HOLDLOCK)
    WHERE [Version] = 21 AND NombreArchivo = N''021_ConfiguracionInicial.sql''
)
    THROW 64114, N''Debe estar registrada 021_ConfiguracionInicial.sql.'', 1;
IF EXISTS (SELECT 1 FROM dbo.VersionesMigracion WITH (UPDLOCK, HOLDLOCK) WHERE [Version] >= 22)
    THROW 64115, N''022 o una versión posterior ya está registrada; no se reutiliza esta inicialización.'', 1;

DECLARE @IdAdministrador tinyint;
DECLARE @IdCliente tinyint;
-- Bloqueos mantenidos hasta COMMIT: no puede aparecer un segundo Administrador
-- entre la comprobación global y la promoción, ni cambiar la identidad del rol.
IF (SELECT COUNT_BIG(*) FROM dbo.Roles WITH (TABLOCKX, HOLDLOCK) WHERE Nombre = N''Administrador'') <> 1
   OR (SELECT COUNT_BIG(*) FROM dbo.Roles WITH (TABLOCKX, HOLDLOCK) WHERE Nombre = N''Cliente'') <> 1
    THROW 64116, N''Se requiere exactamente un rol Administrador y un rol Cliente.'', 1;
SELECT @IdAdministrador = IdRol FROM dbo.Roles
WHERE Nombre COLLATE Latin1_General_100_BIN2 = N''Administrador'' COLLATE Latin1_General_100_BIN2
  AND DATALENGTH(Nombre) = DATALENGTH(N''Administrador'');
SELECT @IdCliente = IdRol FROM dbo.Roles
WHERE Nombre COLLATE Latin1_General_100_BIN2 = N''Cliente'' COLLATE Latin1_General_100_BIN2
  AND DATALENGTH(Nombre) = DATALENGTH(N''Cliente'');
IF @IdAdministrador IS NULL OR @IdCliente IS NULL OR @IdAdministrador = @IdCliente
    THROW 64117, N''Los nombres de los roles no coinciden literalmente con el contrato del backend.'', 1;
IF EXISTS (SELECT 1 FROM dbo.Usuarios WITH (TABLOCKX, HOLDLOCK) WHERE IdRol = @IdAdministrador)
    THROW 64118, N''Ya existe un usuario Administrador, incluso si está inactivo; no se inicializará otro.'', 1;

IF (SELECT COUNT_BIG(*) FROM dbo.Usuarios WITH (TABLOCKX, HOLDLOCK)
    WHERE IdUsuario = @Objetivo
      AND CorreoElectronico COLLATE Latin1_General_100_BIN2 = @CorreoObjetivo COLLATE Latin1_General_100_BIN2
      AND DATALENGTH(CorreoElectronico) = DATALENGTH(@CorreoObjetivo)
      AND EstaActivo = 1 AND IdRol = @IdCliente
      AND LEFT(HashContrasena, 10) = N''$argon2id$'') <> 1
    THROW 64119, N''ID y correo no identifican una cuenta Cliente activa compatible con el registro.'', 1;
IF NOT EXISTS (SELECT 1 FROM dbo.EventosAuditoria WITH (UPDLOCK, HOLDLOCK)
    WHERE Entidad = ''Usuarios'' AND Accion = ''REGISTRAR''
      AND IdEntidad = @Objetivo AND IdUsuarioActor = @Objetivo)
    THROW 64120, N''La cuenta no tiene la evidencia de registro requerida; no se promoverá.'', 1;
DECLARE @Ahora datetime2(7) = SYSUTCDATETIME();
IF EXISTS (SELECT 1 FROM dbo.SesionesUsuario WITH (TABLOCKX, HOLDLOCK)
    WHERE IdUsuario = @Objetivo AND FechaRevocacionUTC IS NULL AND FechaExpiracionUTC > @Ahora)
    THROW 64121, N''La cuenta tiene sesiones vigentes. Ciérrelas antes de promoverla y vuelva a iniciar sesión después.'', 1;

DECLARE @Antes nvarchar(max) = (
    SELECT IdUsuario, IdRol, N''Cliente'' AS Rol, EstaActivo
    FROM dbo.Usuarios WHERE IdUsuario = @Objetivo FOR JSON PATH, WITHOUT_ARRAY_WRAPPER);
UPDATE dbo.Usuarios SET IdRol = @IdAdministrador
WHERE IdUsuario = @Objetivo AND IdRol = @IdCliente AND EstaActivo = 1
  AND CorreoElectronico COLLATE Latin1_General_100_BIN2 = @CorreoObjetivo COLLATE Latin1_General_100_BIN2
  AND DATALENGTH(CorreoElectronico) = DATALENGTH(@CorreoObjetivo);
IF @@ROWCOUNT <> 1
    THROW 64122, N''La promoción no afectó exactamente a la cuenta validada.'', 1;
IF (SELECT COUNT_BIG(*) FROM dbo.Usuarios WHERE IdRol = @IdAdministrador) <> 1
    THROW 64123, N''No se pudo garantizar un único Administrador inicial.'', 1;
DECLARE @Despues nvarchar(max) = (
    SELECT IdUsuario, IdRol, N''Administrador'' AS Rol, EstaActivo,
           ORIGINAL_LOGIN() AS EjecutorSQL
    FROM dbo.Usuarios WHERE IdUsuario = @Objetivo FOR JSON PATH, WITHOUT_ARRAY_WRAPPER);
INSERT dbo.EventosAuditoria
    (IdUsuarioActor, Accion, Entidad, IdEntidad, DatosAnteriores, DatosNuevos, IdCorrelacion, FechaEventoUTC)
VALUES
    (NULL, ''INICIALIZAR_ADMINISTRADOR'', ''Usuarios'', @Objetivo, @Antes, @Despues, NEWID(), @Ahora);
INSERT dbo.VersionesMigracion ([Version], NombreArchivo, SHA256, FechaAplicacionUTC, Ejecutor)
VALUES (22, N''022_InicializacionAdministrador.sql'', @Huella, @Ahora, ORIGINAL_LOGIN());
', N'@Objetivo bigint, @CorreoObjetivo nvarchar(254), @Huella varbinary(32)',
        @Objetivo = @IdUsuario, @CorreoObjetivo = @Correo, @Huella = @SHA256;

    COMMIT TRANSACTION;
    PRINT N'Migración 022 completada: primer Administrador, auditoría y registro técnico confirmados.';
END TRY
BEGIN CATCH
    IF XACT_STATE() <> 0 ROLLBACK TRANSACTION;
    THROW;
END CATCH;
