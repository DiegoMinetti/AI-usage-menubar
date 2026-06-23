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
- Panel de configuración para elegir qué plataformas aparecen en el menú y cuáles se resumen en la barra superior.
- Modo de barra superior solo con icono si no se selecciona ninguna plataforma.
- Widget de escritorio propio de la app, activable desde la barra de menú.
- Ventana de inicio de sesión con GitHub para habilitar Copilot.
- Lectura local de ChatGPT/Codex desde `~/.codex/state_5.sqlite`.
- Resumen normalizado por plataforma: usado, restante, límite, periodo, fechas de inicio/reset y última actualización cuando la fuente lo permite.
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

# Build nativo con WidgetKit (requiere Xcode + firma de desarrollo)
./scripts/build_xcode.sh

# Abrir en Xcode como paquete Swift
open Package.swift

# Abrir el proyecto nativo con widget
open "AI Usage.xcodeproj"

# Build rápido con SwiftPM
swift build -c release

# Crear un instalador/DMG (si procede)
./scripts/make_dmg.sh

# Instalar o actualizar desde la última versión disponible en main
./scripts/install_from_main.sh
```

3. Ejecutar la app precompilada (si existe):

```bash
open "build/AI Usage.app"
```

> Para pruebas de desarrollo, abre `Package.swift` en Xcode y ejecuta el target `AI-usage-menubar` en un esquema para Mac.

## Configuración

- Claude: ajusta endpoints o credenciales en [Sources/AI-usage-menubar/Models/ClaudeConfig.swift](Sources/AI-usage-menubar/Models/ClaudeConfig.swift) y recompila si es necesario.
- Copilot / GitHub: inicia sesión desde la app (el diálogo de login está en [Sources/AI-usage-menubar/UI/GitHubLoginWindow.swift](Sources/AI-usage-menubar/UI/GitHubLoginWindow.swift)). El manejo de sesiones/cookies se realiza en [Sources/AI-usage-menubar/Services/CookieStorage.swift](Sources/AI-usage-menubar/Services/CookieStorage.swift).
- Visibilidad: desde el engranaje del menú se puede activar/desactivar cada proveedor en el panel y en la barra superior. Si la barra superior queda sin proveedores, la app muestra solo el icono.
- Actualizaciones: desde el menú se puede ejecutar `Update from main`; también se puede activar la actualización automática desde el panel. El auto-update compara el SHA remoto de `main` y solo instala si detecta un commit nuevo.

Si prefieres no recompilar para cambios menores de configuración, revisa el código de `CookieStorage` y `ClaudeConfig` para opciones de persistencia y carga de configuración.

## Uso

1. Lanza la aplicación; se añadirá un icono en la barra de menú.
2. Haz clic en el icono para abrir el menú principal. Verás secciones con información de:
   - Copilot (consumo y estado)
   - Claude (registros de uso, ciclo de facturación, anomalías)
   - ChatGPT / Codex (tokens locales de threads de Codex)
   - Tokens diarios
3. Para mostrar el widget, selecciona `Show Desktop Widget` desde el menú de la barra. La ventana se puede mover y queda disponible en todos los espacios.
4. Si necesitas datos de Copilot, selecciona la opción para iniciar sesión con GitHub y sigue el flujo dentro de la app.
5. La aplicación obtiene y actualiza las métricas desde los servicios configurados; para cambios de configuración, modifica los archivos correspondientes y recompila.

En el build nativo, la app escribe el snapshot en el App Group `group.com.diegominetti.ai-usage-menubar` y la extensión WidgetKit lo lee desde ahí. En el build SwiftPM/manual, cae al snapshot local `~/Library/Application Support/ai-usage-tracker/usage_snapshot.json`.

## Instalador y actualización

El instalador DMG se genera con:

```bash
./scripts/build.sh
./scripts/make_dmg.sh
```

El actualizador de `main` usa [scripts/install_from_main.sh](scripts/install_from_main.sh): clona la rama `main`, compila la app, reemplaza `/Applications/AI Usage.app` y la vuelve a abrir. Para distribuir fuera de tu Mac, firma con Developer ID, notariza el DMG y ejecuta `stapler`; el script `make_dmg.sh` imprime los comandos base.

## Widget nativo

El widget nativo vive en el target `AIUsageWidget` dentro de `AI Usage.xcodeproj`. Para que macOS lo muestre en la galería de widgets:

1. Abre `AI Usage.xcodeproj` en Xcode.
2. En `Signing & Capabilities`, selecciona tu Apple ID/equipo para los targets `AI Usage` y `AIUsageWidget`.
3. Verifica que ambos targets tengan el App Group `group.com.diegominetti.ai-usage-menubar`.
4. Ejecuta la app desde Xcode o compila con `DEVELOPMENT_TEAM=TU_TEAM_ID ./scripts/build_xcode.sh`.
5. Abre la app una vez para publicar el snapshot.
6. Agrega `AI Usage` desde la galería de widgets de macOS.

Sin certificado de desarrollo, Xcode puede compilar con `CODE_SIGNING_ALLOWED=NO`, pero macOS no instalará el widget nativo porque los App Groups requieren firma válida.

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
