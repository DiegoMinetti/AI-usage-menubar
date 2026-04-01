# AI Usage Menubar

Aplicación de macOS que muestra en la barra de menú métricas de uso de servicios de IA (Copilot y Claude). Proporciona un resumen rápido del consumo de tokens, ciclos de facturación, registros de uso y detección de anomalías. Está implementada en Swift/SwiftUI siguiendo un patrón MVVM.

## Alcance

- Monitorización de uso de Copilot (requiere inicio de sesión con GitHub).
- Monitorización de uso de Claude: registros de uso, ciclo de facturación y detección de anomalías.
- Visualización de tokens diarios y resúmenes de consumo.
- Persistencia local de sesiones/cookies para mantener la conexión a servicios.
- Distribución como aplicación de barra de menú para macOS.

## Características principales

- Menú en la barra de macOS con vista resumen y detalles.
- Ventana de inicio de sesión con GitHub para habilitar Copilot.
- Servicios modulados para obtener y almacenar datos (`Services/`).
- Modelos de dominio en `Models/` (uso de Claude, Copilot, tokens diarios, anomalías).

## Requisitos

- macOS con soporte para aplicaciones de barra de menú.
- Xcode (recomendado) o una toolchain de Swift que soporte SwiftPM.
- Acceso a las cuentas/credenciales necesarias: cuenta GitHub para Copilot; credenciales o claves para Claude si corresponde.

## Instalación y ejecución

1. Clona el repositorio:

```bash
git clone https://github.com/DiegoMinetti/AI-usage-menubar.git
cd AI-usage-menubar
```

2. Construir (opciones):

```bash
# Script incluido (recomendado)
./scripts/build.sh

# Abrir en Xcode como paquete Swift
open Package.swift

# Build rápido con SwiftPM
swift build -c release

# Crear un instalador/DMG (si procede)
./scripts/make_dmg.sh
```

3. Ejecutar la app precompilada (si existe):

```bash
open "build/AI Usage.app"
```

> Para pruebas de desarrollo, abre `Package.swift` en Xcode y ejecuta el target `AI-usage-menubar` en un esquema para Mac.

## Configuración

- Claude: ajusta endpoints o credenciales en [Sources/AI-usage-menubar/Models/ClaudeConfig.swift](Sources/AI-usage-menubar/Models/ClaudeConfig.swift) y recompila si es necesario.
- Copilot / GitHub: inicia sesión desde la app (el diálogo de login está en [Sources/AI-usage-menubar/UI/GitHubLoginWindow.swift](Sources/AI-usage-menubar/UI/GitHubLoginWindow.swift)). El manejo de sesiones/cookies se realiza en [Sources/AI-usage-menubar/Services/CookieStorage.swift](Sources/AI-usage-menubar/Services/CookieStorage.swift).

Si prefieres no recompilar para cambios menores de configuración, revisa el código de `CookieStorage` y `ClaudeConfig` para opciones de persistencia y carga de configuración.

## Uso

1. Lanza la aplicación; se añadirá un icono en la barra de menú.
2. Haz clic en el icono para abrir el menú principal. Verás secciones con información de:
   - Copilot (consumo y estado)
   - Claude (registros de uso, ciclo de facturación, anomalías)
   - Tokens diarios
3. Si necesitas datos de Copilot, selecciona la opción para iniciar sesión con GitHub y sigue el flujo dentro de la app.
4. La aplicación obtiene y actualiza las métricas desde los servicios configurados; para cambios de configuración, modifica los archivos correspondientes y recompila.

## Estructura rápida del proyecto

- `Sources/AI-usage-menubar/Models/` — modelos de datos (`ClaudeUsage`, `CopilotUsage`, `DailyTokens`, `ClaudeAnomaly`, etc.)
- `Sources/AI-usage-menubar/Services/` — lógica para consultar APIs, estado y persistencia (`ClaudeUsageService`, `CopilotUsageService`, `CookieStorage`, `ClaudeStatusService`)
- `Sources/AI-usage-menubar/UI/` — vistas SwiftUI y ventanas (`MenuContentView.swift`, `MenuViewModel.swift`, `GitHubLoginWindow.swift`)
- `Sources/AI-usage-menubar/AI_usage_menubar.swift` — entry point de la aplicación

## Desarrollo

- Arquitectura: SwiftUI + MVVM. El view model principal está en [Sources/AI-usage-menubar/UI/MenuViewModel.swift](Sources/AI-usage-menubar/UI/MenuViewModel.swift).
- Para depurar peticiones o comportamiento, añade puntos de ruptura en los servicios dentro de `Services/`.

## Contribuir

- Forkea el repositorio, crea una rama con tu mejora y abre un pull request.
- Abre issues para errores, mejoras o preguntas de diseño.

## Licencia

No se ha incluido un fichero LICENSE en este repositorio. Añade el fichero `LICENSE` si quieres publicar este proyecto con una licencia explícita.

---

Si quieres que ajuste el README (más detalle técnico, instrucciones de empaquetado, o traducciones), dime qué prefieres y lo actualizo.
