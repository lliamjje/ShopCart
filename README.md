# ShopCart

**Aplicación web de comercio electrónico | Tech Challenge 360 — Grupo Pentandra**

ShopCart es una aplicación de comercio electrónico desarrollada con React, Node.js, Express, TypeScript y Microsoft SQL Server. Su arquitectura separa la interfaz de usuario, la API REST y la lógica transaccional de la base de datos mediante procedimientos almacenados.

El sistema contempla gestión de productos, inventario, carritos, cupones, checkout, pagos simulados, pedidos, devoluciones, reembolsos y auditoría.

## 1. Tecnologías

| Componente | Tecnología |
|---|---|
| Frontend | React y TypeScript |
| Backend | Node.js 24, Express y TypeScript |
| Base de datos | Microsoft SQL Server 2025 Express |
| Acceso a datos | Procedimientos almacenados T-SQL |
| Validaciones | TypeScript y validación de entradas |
| Autenticación | Usuarios, sesiones y control de acceso por roles |
| Moneda | Quetzales guatemaltecos (GTQ) |
| Impuestos | IVA del 12 % incluido en los precios |
| Pagos | Simulación, sin procesamiento bancario real |
| Entorno | Windows, ejecución local sin Docker |

## 2. Arquitectura

ShopCart sigue una arquitectura de tres capas:

```text
┌────────────────────────────────────┐
│         FRONTEND                   │
│       React + TypeScript           │
└─────────────────┬──────────────────┘
                  │ HTTP / JSON
                  ▼
┌────────────────────────────────────┐
│            BACKEND                 │
│      Node.js + Express             │
│                                    │
│  Rutas REST                        │
│  Validación de solicitudes         │
│  Autenticación y autorización      │
│  Controladores y servicios         │
│  Acceso mediante Stored Procedures │
└─────────────────┬──────────────────┘
                  │ mssql
                  ▼
┌────────────────────────────────────┐
│          SQL SERVER                │
│                                    │
│  Procedimientos almacenados        │
│  Transacciones                     │
│  Restricciones e índices           │
│  Inventario y reservas             │
│  Pedidos y pagos                   │
│  Historial y auditoría             │
└────────────────────────────────────┘
```

### Frontend

La interfaz React consume la API REST y presenta las operaciones del comercio electrónico. No se conecta directamente a SQL Server ni ejecuta consultas SQL.

### Backend

La API Express recibe solicitudes HTTP, valida los datos de entrada, aplica controles de acceso y ejecuta los procedimientos almacenados correspondientes.

Las responsabilidades se distribuyen entre rutas, controladores, servicios, repositorios de acceso a datos y middleware de seguridad.

### Base de datos

SQL Server administra la integridad referencial, el inventario, los descuentos, las reservas, las operaciones monetarias simuladas y los registros históricos.

Las operaciones de negocio utilizan procedimientos almacenados parametrizados, sin ORM ni consultas directas a las tablas desde la API.

## 3. Requisitos previos

Para instalar y ejecutar ShopCart localmente se necesita:

- Windows 10 u 11.
- Git.
- Node.js 24 y npm.
- Microsoft SQL Server 2025 Express.
- SQL Server Management Studio (SSMS) o JetBrains DataGrip.
- Un editor como Visual Studio Code.

La instancia de SQL Server debe estar iniciada y permitir conexiones desde el equipo donde se ejecutará el backend.

No se requiere Docker, WSL ni infraestructura en la nube.

## 4. Descargar el proyecto

Abrir PowerShell y ejecutar:

```powershell
git clone https://github.com/lliamjje/ShopCart.git
cd ShopCart
```

Estructura general:

```text
ShopCart/
├── backend/
├── frontend/
├── database/
│   └── migrations/
├── .gitignore
└── README.md
```

## 5. Instalación de la base de datos

### 5.1. Preparar SQL Server

Iniciar el servicio de SQL Server Express y conectarse mediante DataGrip o SSMS utilizando una cuenta con permisos para crear bases de datos y objetos SQL.

Para una instalación local de SQL Server Express, el nombre de instancia habitual es:

```text
.\SQLEXPRESS
```

El nombre real de la instancia puede consultarse en SQL Server Configuration Manager.

### 5.2. Crear la base ShopCart

Desde el cliente SQL:

1. Seleccionar la base de datos `master`.
2. Activar el modo Auto-commit.
3. Comprobar que no exista una transacción abierta.
4. Abrir `database/migrations/001_CrearBaseDatos.sql`.
5. Ejecutar el archivo completo como un único lote.

La migración inicial crea o valida la base de datos `ShopCart` y la tabla técnica `dbo.VersionesMigracion`.

La configuración de la base incluye:

| Propiedad | Valor |
|---|---|
| Nombre | `ShopCart` |
| Collation | `Latin1_General_100_CI_AI_SC` |
| Modelo de recuperación | `SIMPLE` |
| Acceso | `MULTI_USER` |
| Estado | `ONLINE` |

La migración 001 es el procedimiento de inicialización y no se registra como versión 1 dentro de `dbo.VersionesMigracion`.

### 5.3. Ejecutar las migraciones

Una vez creada la base de datos, conectarse a `ShopCart` y ejecutar las migraciones restantes en orden:

| Versión | Archivo | Propósito |
|---|---|---|
| 002 | `002_Seguridad.sql` | Roles, usuarios, direcciones y sesiones |
| 003 | `003_Catalogo.sql` | Productos, categorías, variantes e imágenes |
| 004 | `004_InventarioBase.sql` | Existencias y movimientos de inventario |
| 005 | `005_CarritosCuponesBase.sql` | Carritos y cupones |
| 006 | `006_MetodosEnvio.sql` | Métodos de envío |
| 007 | `007_Checkout.sql` | Checkouts y sus detalles |
| 008 | `008_Reservas.sql` | Reservas de inventario y cupones |
| 009 | `009_PedidosPagos.sql` | Pedidos, detalles y pagos |
| 010 | `010_DevolucionesAuditoria.sql` | Devoluciones, reembolsos y auditoría |
| 011 | `011_RelacionesRestricciones.sql` | Relaciones y estructuras complementarias |
| 012 | `012_ProcedimientosCatalogo.sql` | Procedimientos de catálogo |
| 013 | `013_ProcedimientosSeguridad.sql` | Procedimientos de seguridad |
| 014 | `014_ProcedimientosInventario.sql` | Procedimientos de inventario |
| 015 | `015_ProcedimientosCarritos.sql` | Procedimientos de carritos |
| 016 | `016_ProcedimientosCupones.sql` | Procedimientos de cupones |
| 017 | `017_ProcedimientosCheckout.sql` | Procedimientos de checkout |
| 018 | `018_ProcedimientosPedidosPagos.sql` | Procedimientos de pedidos y pagos |
| 019 | `019_ProcedimientosDevoluciones.sql` | Procedimientos de devoluciones |
| 020 | `020_ProcedimientosReportesAuditoria.sql` | Procedimientos de reportes y auditoría |

Las migraciones 002–020 implementan un mecanismo de verificación mediante SHA-256 y `SESSION_CONTEXT`.

### 5.4. Calcular el SHA-256 de una migración

Desde PowerShell, en la raíz del proyecto, ejecutar:

```powershell
Get-FileHash .\database\migrations\002_Seguridad.sql -Algorithm SHA256
```

El comando devuelve una cadena hexadecimal de 64 caracteres que representa los 32 bytes del SHA-256 del archivo.

La huella debe calcularse sobre el archivo definitivo, sin modificarlo posteriormente.

### 5.5. Registrar el hash en la sesión SQL

Desde DataGrip o SSMS, conectado a la base `ShopCart`, ejecutar:

```sql
DECLARE @SHA256 varbinary(32) =
    CONVERT(
        varbinary(32),
        'REEMPLAZAR_CON_SHA256_DEL_ARCHIVO',
        2
    );

EXEC sys.sp_set_session_context
    @key = N'ShopCart.Migracion002.SHA256',
    @value = @SHA256;
```

Sustituir `REEMPLAZAR_CON_SHA256_DEL_ARCHIVO` por el valor obtenido en PowerShell.

El parámetro `@key` debe corresponder a la migración que se ejecutará:

```text
ShopCart.Migracion002.SHA256
ShopCart.Migracion003.SHA256
...
ShopCart.Migracion020.SHA256
```

Es indispensable utilizar **la misma conexión y sesión de SQL Server** para establecer el hash y ejecutar la migración. Abrir otra consola o conexión puede producir una sesión SQL distinta.

Después de establecer el hash:

1. Abrir el archivo de la migración correspondiente.
2. Copiar su contenido completo.
3. Ejecutarlo en la misma sesión SQL.
4. Comprobar que termina sin errores.
5. Continuar con la siguiente migración.

Cada migración debe ejecutarse una sola vez, en orden numérico y con Auto-commit activado.

No deben agregarse instrucciones `GO` ni ejecutarse fragmentos aislados de los archivos.

### 5.6. Verificar las migraciones

Una vez ejecutadas las migraciones, consultar el registro técnico:

```sql
USE ShopCart;

SELECT
    [Version],
    NombreArchivo,
    CONVERT(varchar(64), SHA256, 2) AS SHA256,
    FechaAplicacionUTC,
    Ejecutor
FROM dbo.VersionesMigracion
ORDER BY [Version];
```

Para una instalación completa, el registro debe contener las versiones **002 a 020**.

La versión 001 no aparece en esta tabla porque es la migración de inicialización.

También pueden consultarse los procedimientos disponibles:

```sql
USE ShopCart;

SELECT
    SCHEMA_NAME(schema_id) AS Esquema,
    name AS Procedimiento
FROM sys.procedures
ORDER BY name;
```

## 6. Configuración de la conexión SQL Server

La API utiliza una conexión a SQL Server gestionada desde el backend.

### 6.1. Habilitar TCP/IP

Si la instancia SQL Server Express no acepta conexiones TCP/IP:

1. Abrir SQL Server Configuration Manager.
2. Acceder a **SQL Server Network Configuration**.
3. Seleccionar **Protocols for SQLEXPRESS**.
4. Habilitar **TCP/IP**.
5. Revisar el puerto configurado en las propiedades TCP/IP.
6. Reiniciar el servicio de SQL Server Express.

La configuración del backend debe utilizar el servidor y puerto que realmente corresponden a la instancia instalada.

### 6.2. Usuario de aplicación

Configurar un usuario de SQL Server para la conexión del backend.

La cuenta debe tener acceso a la base `ShopCart` y los permisos necesarios para ejecutar los procedimientos almacenados utilizados por la API.

Para una instalación con separación de privilegios, la cuenta de aplicación no debe utilizar credenciales administrativas de SQL Server.

Los permisos deben corresponder a las operaciones que la aplicación puede realizar.

## 7. Instalación del backend

Abrir PowerShell desde la raíz del proyecto:

```powershell
cd backend
npm install
```

### 7.1. Configurar variables de entorno

Crear un archivo `.env` a partir de la plantilla del proyecto:

```powershell
Copy-Item .env.example .env
```

Abrir `.env` y configurar los valores requeridos por la aplicación, especialmente:

- Servidor o instancia de SQL Server.
- Puerto de conexión.
- Nombre de la base de datos `ShopCart`.
- Usuario y contraseña de SQL Server.
- Parámetros de cifrado para conexiones locales.
- Puerto HTTP de la API.
- Origen permitido para el frontend.
- Secretos utilizados por la autenticación.

Los nombres exactos de las variables y las opciones admitidas están definidos en `backend/.env.example`.

Las contraseñas y claves de autenticación deben mantenerse en el archivo local `.env`, que no debe publicarse en el repositorio.

### 7.2. Iniciar el servidor de desarrollo

Desde `backend/`:

```powershell
npm run dev
```

El proceso inicia la API Express utilizando la configuración del entorno.

El servidor SQL debe estar disponible y las migraciones requeridas deben haberse ejecutado para utilizar las operaciones de negocio.

### 7.3. Compilar el backend

Para comprobar los tipos de TypeScript:

```powershell
npm run typecheck
```

Para compilar:

```powershell
npm run build
```

Para iniciar la versión compilada:

```powershell
npm run start
```

Los scripts de ejecución están definidos en `backend/package.json`.

## 8. Instalación del frontend

Abrir una segunda terminal PowerShell desde la raíz del repositorio:

```powershell
cd frontend
npm install
npm run dev
```

El frontend y el backend deben permanecer ejecutándose en terminales independientes.

La dirección de la API utilizada por React debe corresponder al host y puerto configurados para Express.

El navegador se conecta al frontend, y este envía las solicitudes de negocio a la API REST. SQL Server no debe exponerse directamente al navegador.

## 9. API REST

La API sigue una organización modular, con rutas HTTP agrupadas por funcionalidades.

| Módulo | Responsabilidad |
|---|---|
| Catálogo | Consultar categorías, productos y variantes |
| Seguridad | Registro, inicio de sesión, perfil y sesiones |
| Inventario | Consultar existencias y registrar movimientos |
| Carritos | Administrar artículos y cantidades |
| Cupones | Validar códigos y condiciones de descuento |
| Checkout | Cotizar y reservar inventario |
| Pedidos y pagos | Procesar pagos simulados y consultar pedidos |
| Devoluciones | Gestionar solicitudes y reembolsos |
| Reportes | Consultar información operativa y financiera |
| Auditoría | Consultar eventos registrados |

Las rutas HTTP delegan el acceso a datos a procedimientos almacenados.

El cliente no envía consultas SQL. Los identificadores, cantidades, filtros y demás entradas se validan antes de ejecutar la operación correspondiente.

Los procesos críticos, como la confirmación de una compra, mantienen la integridad transaccional en SQL Server.

## 10. Reglas de negocio

### Inventario

Cada variante de producto dispone de SKU, precio y existencias independientes.

Los cambios físicos de inventario generan registros en el kardex. La disponibilidad considera las reservas activas y vigentes para evitar comprometer más unidades de las existentes.

### Carritos

El modelo admite carritos asociados a usuarios registrados e invitados.

Las operaciones permiten agregar productos, modificar cantidades y gestionar el contenido antes de iniciar el checkout.

### Cupones

Los cupones permiten aplicar descuentos sujetos a reglas de vigencia, monto mínimo, categoría y límites de utilización.

Los descuentos se validan contra las reglas registradas en SQL Server.

### Checkout y reservas

El checkout utiliza reservas temporales de inventario y cupones, con una vigencia funcional de **15 minutos**.

La confirmación del pedido depende de que se cumplan las condiciones de disponibilidad, vigencia y consistencia de importes.

### Pagos simulados

Los pagos no se conectan a una pasarela bancaria real.

La simulación permite trabajar con resultados de aprobación y rechazo, manteniendo identificadores y reglas de idempotencia para evitar duplicar operaciones.

### Impuestos

Todos los importes se manejan en quetzales guatemaltecos.

Los precios incluyen IVA del 12 %. El impuesto se desglosa dentro del precio; no se suma nuevamente al total.

### Devoluciones y reembolsos

El modelo admite devoluciones de cantidades parciales o completas, control de estados y reembolsos simulados relacionados con pagos aprobados.

Los reembolsos se registran separadamente de los pagos originales para conservar trazabilidad.

### Auditoría

Las operaciones relevantes pueden generar registros de auditoría con información del actor, entidad, acción y fecha UTC.

El historial de estados de pedidos conserva las transiciones realizadas durante su ciclo de vida.

## 11. Organización de la base de datos

El esquema relacional está distribuido entre los siguientes dominios:

| Dominio | Tablas principales |
|---|---|
| Seguridad | `Roles`, `Usuarios`, `Direcciones`, `SesionesUsuario`, `TokensRenovacion` |
| Catálogo | `Categorias`, `Productos`, `VariantesProducto`, `ImagenesProducto` |
| Inventario | `Existencias`, `MovimientosInventario` |
| Compras | `Carritos`, `DetallesCarrito`, `Checkouts`, `DetallesCheckout` |
| Reservas | `ReservasInventario`, `ReservasCupon` |
| Cupones | `Cupones`, `UsosCupon` |
| Pedidos | `Pedidos`, `DetallesPedido`, `HistorialEstadosPedido` |
| Pagos | `Pagos`, `ReembolsosCancelacion` |
| Devoluciones | `Devoluciones`, `DetallesDevolucion`, `Reembolsos` |
| Auditoría | `EventosAuditoria` |

Las relaciones y restricciones se encuentran definidas en las migraciones SQL versionadas.

El diseño utiliza claves primarias y foráneas, restricciones CHECK y UNIQUE, índices y transacciones para proteger la consistencia de los datos.

## 12. Orden de inicio de la aplicación

Para ejecutar el sistema localmente:

1. Iniciar SQL Server Express.
2. Comprobar que la base `ShopCart` contiene las migraciones requeridas.
3. Configurar el archivo `backend/.env`.
4. Iniciar el backend con `npm run dev` desde `backend/`.
5. Iniciar el frontend con `npm run dev` desde `frontend/`.
6. Abrir en el navegador la dirección que indique el servidor de desarrollo del frontend.

Para detener ambos servidores, utilizar `Ctrl + C` en sus terminales.

## 13. Consideraciones de seguridad

El proyecto utiliza separación entre interfaz, API y base de datos.

Las operaciones protegidas requieren validación de identidad y autorización conforme al rol correspondiente. Los procedimientos almacenados gestionan las operaciones transaccionales sobre los datos.

Las credenciales de base de datos y los secretos de autenticación se configuran mediante variables de entorno. No deben almacenarse en el código fuente ni exponerse al navegador.

Los pagos son exclusivamente simulados; la aplicación no requiere información real de tarjetas bancarias.

---

**ShopCart — Tech Challenge 360 | Grupo Pentandra**
