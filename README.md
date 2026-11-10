# ShopCart

Aplicación web de comercio electrónico desarrollada para el **Tech Challenge 360 de Grupo Pentandra**. El proyecto integra SQL Server, una API REST en Node.js y un frontend en React, con énfasis en seguridad, integridad transaccional, control de inventario y trazabilidad de las compras.

> **Estado del proyecto:** la base de datos y el backend están implementados y han superado pruebas funcionales reales. El frontend se encuentra **en desarrollo**. Las pruebas de expiración temporal real de JWT y reservas aún están pendientes; no se consideran aprobadas.

## Tecnologías

| Componente | Tecnología |
| --- | --- |
| Entorno | Windows 11 nativo, sin Docker ni WSL |
| Base de datos | Microsoft SQL Server 2025 Express (`SQLEXPRESS`) |
| Administración de base de datos | JetBrains DataGrip |
| Backend | Node.js 24 LTS+, Express y TypeScript en modo `strict` |
| Frontend | React 18+, TypeScript, Vite y Tailwind CSS (en desarrollo) |
| Seguridad | Argon2id, JWT, refresh tokens rotativos, CSRF y autorización por roles |
| Pruebas | Pruebas locales automatizadas, integración y pruebas funcionales sobre la API real |
| Control de versiones | Git y Conventional Commits |

**Regla fundamental:** la aplicación accede a las tablas de negocio **exclusivamente mediante procedimientos almacenados parametrizados**. El backend no utiliza ORM ni consultas SQL directas para operar sobre los datos comerciales.

## Funcionalidades implementadas en el backend

- **Seguridad y usuarios:** registro, inicio de sesión, perfil, direcciones, sesiones, renovación y revocación de tokens, roles `Cliente`, `Operador` y `Administrador`.
- **Catálogo:** categorías, productos, variantes, SKU, precios, disponibilidad y metadatos de imágenes.
- **Inventario:** existencias por variante, movimientos de kardex y reservas temporales.
- **Carritos:** clientes e invitados, modificación de artículos, comprobación de disponibilidad y fusión de carritos.
- **Cupones:** descuentos porcentuales y fijos, vigencia, mínimos de compra y límites de uso.
- **Checkout:** cálculo monetario con IVA incluido, métodos de envío, reserva de inventario e idempotencia.
- **Pedidos y pagos:** estados, pagos simulados aprobados o rechazados y prevención de operaciones duplicadas.
- **Cancelaciones y devoluciones:** devoluciones parciales, reintegros, reembolsos simulados y trazabilidad.
- **Reportes y auditoría:** consultas de actividad, resultados operativos y ventas netas.

**Alcance conocido:** la API gestiona metadatos de imágenes, pero no implementa la carga ni la entrega de archivos de imagen. Algunos listados administrativos (por ejemplo, listados completos de usuarios y cupones) no están disponibles mediante los endpoints actuales; el frontend debe respetar estas limitaciones.

## Arquitectura

El repositorio se organiza como un **monorepo**:

```text
shopcart/
├── backend/
│   ├── src/                  # API: rutas, controladores, servicios, repositorios y validaciones
│   ├── test/
│   │   ├── functional/       # Escenarios funcionales sobre la API real
│   │   ├── integration/      # Pruebas de integración con su configuración específica
│   │   ├── manual/           # Ejecutores locales de pruebas controladas
│   │   └── support/          # Utilidades compartidas de pruebas
│   ├── api-contract.json     # Inventario de rutas y contratos HTTP
│   └── .env.example
├── frontend/                 # Aplicación React en desarrollo
├── database/
│   ├── migrations/           # Migraciones SQL numeradas
│   ├── seeds/
│   └── tests/
├── .gitignore
└── README.md
```

En el backend, las **rutas** definen los recursos HTTP; los **controladores** adaptan solicitudes y respuestas; los **servicios** coordinan casos de uso; los **repositorios** invocan procedimientos almacenados; y **SQL Server** aplica restricciones, transacciones e invariantes críticas. El frontend se comunica únicamente con la API REST.

## Base de datos y migraciones

- Base: `ShopCart`.
- Intercalación: `Latin1_General_100_CI_AI_SC`.
- Recuperación local: `SIMPLE`.
- Migraciones **001 a 022 ejecutadas** y controladas en `dbo.VersionesMigracion` con nombre de archivo y SHA-256.
- La migración **022** inicializa de forma controlada y auditada el primer Administrador; no es un mecanismo general de administración de usuarios ni debe repetirse.
- Las migraciones ya ejecutadas **no se editan**. Cualquier evolución del esquema o de los procedimientos requiere una migración posterior.

Los scripts se ejecutan **manualmente desde DataGrip**, en orden numérico y siguiendo las instrucciones específicas de cada archivo. No basta con ejecutar la carpeta completa sin revisar sus precondiciones, parámetros, huellas y permisos. La inicialización del Administrador necesita una cuenta legítimamente registrada y autorización administrativa en SQL Server; **no se deben publicar sus credenciales ni incorporar datos personales a los scripts**.

La cuenta SQL utilizada por la API, `shopcart_service`, opera con privilegios mínimos y permisos de ejecución de los procedimientos públicos necesarios. No requiere acceso directo de lectura o escritura sobre las tablas de negocio ni privilegios `db_owner` o `sysadmin`.

## Requisitos locales

1. **Windows 11** con **Node.js 24 LTS o superior**, npm y Git.
2. **SQL Server 2025 Express**, con la instancia `SQLEXPRESS` y la base de datos `ShopCart` configuradas.
3. **DataGrip** u otra herramienta SQL compatible para administrar la instancia y aplicar migraciones.
4. Puerto HTTP del backend disponible, por defecto `127.0.0.1:3000`.
5. Para el frontend en desarrollo, puerto `127.0.0.1:5173`.

La instancia de demostración utiliza TCP local en `127.0.0.1:1433`. Ajusta los valores de entorno según tu instalación; no presupongas que la base, el login SQL ni las migraciones se crean automáticamente con `npm install`.

## Configuración y ejecución del backend

Desde la raíz del repositorio, en PowerShell:

```powershell
cd backend
npm.cmd ci
Copy-Item .env.example .env
```

Edita **`backend/.env`** con valores locales válidos, sin subirlo a Git. Las variables previstas incluyen:

| Variable | Función |
| --- | --- |
| `NODE_ENV`, `HOST`, `PORT` | Entorno y servidor HTTP |
| `SQL_SERVER`, `SQL_PORT`, `SQL_DATABASE` | Conexión a SQL Server |
| `SQL_USER`, `SQL_PASSWORD` | Cuenta SQL de la API |
| `SQL_ENCRYPT`, `SQL_TRUST_SERVER_CERTIFICATE` | Opciones de conexión cifrada |
| `SQL_CONNECT_TIMEOUT_MS`, `SQL_REQUEST_TIMEOUT_MS` | Tiempos de espera de SQL |
| `CORS_ORIGIN` | Origen permitido del frontend |
| `JWT_SECRET`, `ACCESS_TOKEN_SECONDS`, `SESSION_DAYS` | Firma y duración de la autenticación |

Los nombres y valores de referencia están documentados en `backend/.env.example`; consulta ese archivo para la configuración vigente. La aceptación de certificados SQL no verificados solo es apropiada para un entorno local controlado, no para producción.

Para iniciar la API:

```powershell
npm.cmd run dev
```

Con la base de datos disponible, el punto de comprobación es:

```text
GET http://127.0.0.1:3000/api/v1/health?database=true
```

La base de la API es `http://127.0.0.1:3000/api/v1`. El inventario de endpoints se mantiene en `backend/api-contract.json` (**64 rutas documentadas en la fase de backend**); el contrato y el código vigente prevalecen sobre ejemplos antiguos.

## Frontend

La interfaz se está construyendo con **React, TypeScript, Vite y Tailwind CSS**, a partir de una arquitectura modular. La propuesta incluye tienda pública, catálogo, detalle de producto, autenticación, carrito, checkout, cuenta del cliente y pantallas de operación/administración en función de los endpoints disponibles.

Durante el desarrollo local, el frontend se integrará con la API en `127.0.0.1:3000` desde `127.0.0.1:5173`. El navegador debe conservar las cookies necesarias para CSRF, renovación de sesión y carrito invitado. Los JWT de acceso se mantendrán en memoria; no deben persistirse en `localStorage`.

**Nota:** no se documenta aún un comando de instalación o una lista de pantallas como entrega verificada del frontend. Esta sección se actualizará cuando Codex complete la implementación y se comprueben sus scripts, compilación y navegación. No se utilizarán productos, precios ni pedidos simulados como sustituto de las respuestas reales de la API.

## Reglas de negocio destacadas

- Cada variante posee un SKU único, precio propio y saldo de inventario independiente.
- **Disponible = existencia física − reservas vigentes**.
- Las reservas de checkout tienen una vigencia de **15 minutos**; la expiración efectiva depende de las fechas evaluadas por SQL Server.
- Los importes se almacenan y calculan con tipos decimales; los precios incluyen **IVA del 12 %**.
- El checkout, los pagos y los reembolsos usan mecanismos de idempotencia; los reintentos con resultados inciertos no deben generar operaciones duplicadas.
- Los pagos y reembolsos son **simulados**; la aplicación no procesa dinero real.
- La autorización se valida en el backend y los procedimientos almacenados, no únicamente en el menú o en las rutas del frontend.
- Los cambios de estado, cancelaciones y devoluciones afectan al inventario, al historial y a los reportes según las reglas del negocio.

## Pruebas y estado de validación

La base de datos y la API fueron comprobadas mediante pruebas automatizadas locales y ejecuciones funcionales contra SQL Server real. Los resultados registrados son:

| Cobertura | Resultado observado |
| --- | --- |
| Suite funcional principal | **33 aprobadas**, 0 fallidas en la ejecución completa satisfactoria |
| Escenario adicional: metadatos de imágenes | **Aprobado** |
| Escenario adicional: reembolso rechazado y nuevo intento | **Aprobado** |
| Escenario adicional: concurrencia acotada de checkout | **Aprobado** |
| Permisos SQL directos de auditoría (`shopcart_service`) | Ausencia de permisos efectivos consultados; cobertura parcial de metadatos |
| Pruebas locales automatizadas | **88 aprobadas** en la última validación reportada |
| Expiración real por tiempo de JWT | **Pendiente** (solo cobertura local con reloj controlado) |
| Expiración real de reservas tras 15 minutos | **Pendiente** |

La suite funcional principal recorrió 225 solicitudes HTTP y terminó con código de salida 0. Las pruebas extendidas se ejecutaron con lotes de datos propios; estas ejecuciones pueden conservar usuarios, pedidos, pagos simulados y movimientos en la base local. **No existe rollback global**, por lo que deben ejecutarse únicamente en un entorno de desarrollo autorizado y tras revisar sus efectos.

Desde `backend/`:

```powershell
npm.cmd run typecheck
npm.cmd run build
npm.cmd test
npm.cmd run test:functional -- -List
npm.cmd run test:functional -- -Preflight
```

La ejecución completa de escenarios funcionales, que **sí puede escribir datos**, se inicia explícitamente con:

```powershell
npm.cmd run test:functional
```

El ejecutor solicita autorización y las credenciales administrativas mediante entrada oculta. También permite seleccionar escenarios extendidos individuales mediante `-NewScenario`; revisa `backend/test/functional/` antes de ejecutarlos. Evita repetir una suite completa tras un error sin inspeccionar el lote y los cambios parciales. Las pruebas de integración aisladas tienen su propia configuración y **no deben ejecutarse indiscriminadamente sobre la base principal**.

## Seguridad

- Las contraseñas se almacenan mediante **Argon2id**.
- El acceso utiliza JWT de corta duración, refresh tokens con rotación y revocación de sesiones.
- La API aplica protección **CSRF**, controles CORS y autorización por rol y por pertenencia del recurso.
- `shopcart_service` debe mantener privilegios mínimos; nunca se deben otorgar permisos de tabla solo para facilitar una prueba.
- Los archivos `.env`, contraseñas, claves JWT y tokens **no deben publicarse**.
- Los mecanismos administrativos iniciales y sus cuentas están destinados al entorno de desarrollo y no deben considerarse una configuración lista para Internet sin una revisión de seguridad y despliegue.

## Control de versiones y documentación

Se utiliza **Conventional Commits**, con descripciones breves en español:

```text
feat(catalogo): implementar búsqueda de productos
fix(backend): corregir validación de inventario
test(backend): ampliar pruebas funcionales
docs(readme): actualizar estado y ejecución de ShopCart
```

Las decisiones del proyecto se documentan en Markdown. `AGENTS.md` contiene instrucciones de trabajo **solo locales** y permanece excluido de Git. Para revisar la evolución de la implementación y sus verificaciones, consulta también el historial de commits del repositorio.

> **Importante:** este README distingue entre componentes implementados, pruebas realizadas y trabajo pendiente. Antes de una entrega o demostración final, verificar de nuevo la instalación desde una copia limpia y actualizar el apartado del frontend con los comandos y pantallas efectivamente terminados.
