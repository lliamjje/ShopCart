# ShopCart

Aplicación web de comercio electrónico desarrollada como parte del reto técnico **Tech Challenge 360 de Grupo Pentandra**.

> **Estado del proyecto:** preparación del repositorio y diseño de arquitectura. La base de datos, la API y el frontend todavía no están implementados. Este documento se actualizará conforme se completen y verifiquen las funcionalidades.

## Objetivo

Construir una tienda en línea con catálogo, inventario, carrito, cupones, proceso de compra, administración de pedidos y reportes. El sistema prioriza la integridad de los datos, las reglas de negocio, la seguridad y la capacidad de explicar y defender las decisiones técnicas.

## Tecnologías y entorno

| Componente | Tecnología aprobada |
| --- | --- |
| Sistema de desarrollo | Windows 11, ejecución local sin Docker ni WSL |
| Base de datos | SQL Server 2025 Express (`SQLEXPRESS`) |
| Administración SQL | JetBrains DataGrip |
| Backend | Node.js 24 LTS o superior, Express y TypeScript (`strict`) |
| Frontend | React 18 o superior y TypeScript |
| Autenticación | JWT de acceso de corta duración y refresh tokens con rotación |
| Control de versiones | Git; convenciones de Conventional Commits |

**Acceso a datos:** la aplicación utilizará exclusivamente **Stored Procedures parametrizados** para leer y escribir información en SQL Server. No se utilizarán ORM ni consultas SQL directas desde la API.

## Funcionalidades previstas

1. Autenticación, roles y gestión de usuarios.
2. Catálogo de categorías, productos, variantes e imágenes.
3. Inventario con existencias por variante, kardex y reservas temporales.
4. Carrito de compras para clientes autenticados e invitados.
5. Cupones con vigencia, límites de uso y descuentos.
6. Checkout con reservas de 15 minutos, pagos simulados e idempotencia.
7. Pedidos, cancelaciones y devoluciones parciales o totales.
8. Dashboard y reportes de ventas.
9. Bitácora de auditoría y trazabilidad de cambios.

Estas funcionalidades forman parte del **alcance planificado**, no de características ya implementadas.

## Arquitectura acordada

El proyecto es un monorepositorio. El backend se organizará por capas técnicas: rutas, controladores, servicios, repositorios, validaciones y middlewares.

- **Controladores:** adaptación entre HTTP y casos de uso.
- **Servicios:** reglas de negocio y orquestación.
- **Repositorios:** ejecución de Stored Procedures y mapeo de resultados.
- **SQL Server:** restricciones, integridad referencial y transacciones críticas.

Se utilizará una única función comercial por operación de compra: creación de checkout, reservas de inventario y cupón, confirmación idempotente del pedido y registro de movimientos relacionados.

## Estructura del repositorio

```text
shopcart/
├── .gitignore
├── README.md
├── backend/
├── frontend/
└── database/
    ├── migrations/
    ├── seeds/
    ├── tests/
    └── README.md          # Pendiente de redactar
```

Las carpetas pueden contener archivos `.gitkeep` mientras no tengan código. El archivo local `AGENTS.md` contiene instrucciones de trabajo para Codex y **está excluido del control de versiones**; no es necesario para instalar una entrega terminada.

## Base de datos

Se ha aprobado la creación de la base `ShopCart` con estas opciones iniciales:

- Intercalación: `Latin1_General_100_CI_AI_SC`.
- Modelo de recuperación local: `SIMPLE`.
- Migraciones SQL numeradas, versionadas y ejecutadas manualmente desde DataGrip.
- Registro técnico de migraciones en `dbo.VersionesMigracion`.

La primera migración prevista es `database/migrations/001_CrearBaseDatos.sql`. **Aún no ha sido implementada ni ejecutada.** Las instrucciones reproducibles de creación, migraciones y semillas se documentarán en `database/README.md` cuando hayan sido verificadas.

## Reglas de negocio principales

- Cada variante vendible posee SKU único, precio propio y existencias independientes.
- Los cambios de stock registran movimientos de kardex en la misma transacción.
- La disponibilidad descuenta únicamente las reservas vigentes.
- El checkout requiere autenticación, aunque se admite carrito de invitado.
- El inventario y los cupones se reservan durante 15 minutos.
- Una misma operación de pago no puede crear pedidos ni descuentos de inventario duplicados.
- Los pagos y reembolsos serán **simulados**: no se procesará dinero real.
- Los precios incluyen IVA del 12 % y los cálculos monetarios utilizan decimales y redondeo consistente.
- Las cancelaciones se permiten antes del despacho; las devoluciones admiten cantidades parciales y requieren aprobación.
- Los reportes se calculan desde los datos transaccionales y reflejan cancelaciones y devoluciones.

## Instalación y ejecución

**Pendiente de implementar y verificar.** Una vez que existan los proyectos de backend y frontend, esta sección indicará los requisitos previos, variables de entorno de ejemplo, pasos de instalación, comandos de ejecución y credenciales de demostración no sensibles.

El proyecto se desarrolla para ejecutarse localmente; no se requiere un despliegue público.

## Pruebas

**Pendiente de implementar.** Las pruebas previstas abarcan integridad referencial, no sobreventa bajo concurrencia, reservas expiradas, límites de cupones, idempotencia de pagos, devoluciones parciales, auditoría y exactitud de reportes.

No se declararán pruebas como aprobadas hasta haberlas ejecutado y registrado su resultado.

## Convenciones de Git

Se utiliza **Conventional Commits**, con tipo y alcance en inglés cuando corresponda y descripción en español:

```text
tipo(alcance): descripción breve en español
```

Ejemplos:

```text
feat(inventario): implementar reservas de productos
fix(checkout): evitar pedidos duplicados
docs(readme): documentar configuración inicial
```

Los cambios se realizan en commits pequeños, coherentes y verificables.

## Documentación

Este `README.md` documenta el proyecto para su instalación, revisión y defensa. La guía específica de la base de datos se mantendrá en `database/README.md`. Las decisiones arquitectónicas aprobadas se reflejarán aquí a medida que sean relevantes para comprender la implementación.

> Nunca deben publicarse credenciales reales, claves JWT, cadenas de conexión con contraseñas ni otros secretos.
