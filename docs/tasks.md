
# Backlog accionable (desglose en tareas chicas y prompts para agentes)

Formato: [ID] - Título — Prioridad — Estimación — Estado — Dependencias  
Cada tarea contiene subtareas pequeñas y un "Prompt para agente" listo para enviar.

- [task-001] Seguridad de tokens (Keychain) — Alta — 2d — in_progress — []
  - subtasks:
    1. Crear wrapper Keychain en Sources/AI-usage-menubar/Services/KeychainStorage.swift — 3h  
       Prompt para agente: "Crear un archivo Swift KeychainStorage.swift que exponga get/set/delete para Strings seguro, usando SecItemAdd/CopyMatching/Update/Delete. Incluir manejo de errores claro y tests unitarios básicos."
    2. Migrar CookieStorage a usar KeychainStorage para tokens — 2h  
       Prompt para agente: "Modificar CookieStorage.swift para almacenar tokens (access/refresh) en KeychainStorage; mantener compatibilidad con lectura vieja si existe."
    3. Añadir migración en arranque que borre tokens temporales — 1h  
       Prompt para agente: "Agregar rutina de migración que en el primer arranque detecte tokens en almacenamiento previo y los mueva a KeychainStorage, luego borre orígenes inseguros."
    4. Tests unitarios de KeychainStorage (mockable) — 2h  
       Prompt para agente: "Crear tests unitarios que prueben get/set/delete de KeychainStorage en entorno macOS con entitlements simulados o mocking del API Security."

- [task-002] Reintentos y tolerancia (Retry + Circuit Breaker) — Alta — 3d — pending — []
  - subtasks:
    1. Implementar RetryPolicy util (exponencial con jitter) en Sources/AI-usage-menubar/Services/RetryPolicy.swift — 4h  
       Prompt para agente: "Crear RetryPolicy.swift con función retry(async block) que reintente HTTP calls con backoff exponencial, jitter y límite de intentos configurable."
    2. Añadir CircuitBreaker simple para servicios (closed/open/half-open) — 4h  
       Prompt para agente: "Crear CircuitBreaker.swift con estados y ventana de fallo; exponer shouldAllowRequest() y recordSuccess()/recordFailure()."
    3. Integrar RetryPolicy y CircuitBreaker en ClaudeUsageService y CopilotUsageService — 6h  
       Prompt para agente: "Modificar servicios de uso para envolver llamadas HTTP con CircuitBreaker y RetryPolicy; añadir logs de cada reintento y métricas de fallo/éxito."
    4. Tests simulando timeouts y errores — 6h  
       Prompt para agente: "Escribir tests que mockeen respuestas timeout/500 y verifiquen reintentos y comportamiento del circuit breaker."

- [task-003] Instrumentación básica — Media — 3d — pending — [task-002]
  - subtasks:
    1. Añadir métricas in-app (contadores latencia/errores) y logging estructurado — 1d  
       Prompt para agente: "Agregar Metrics.swift que permita contar requests, errores, latencias; integrar en servicios existentes."
    2. Exponer endpoint local (opcional) o archivo de logs rotativo — 1d  
       Prompt para agente: "Implementar simple exportador que guarde métricas en JSON en ~/Library/Logs/AI-usage-menubar/metrics.json."

- [task-004] Tests unitarios servicios — Media — 4d — pending — [task-001, task-002]
  - subtasks:
    1. Crear mocks de HTTP y fixtures de respuestas (Claude/Copilot) — 1d  
       Prompt para agente: "Agregar mocks para URLSession o wrapper HTTP para inyectar respuestas en tests."
    2. Tests para parsing y cálculo de consumos — 2d  
       Prompt para agente: "Escribir tests que validen parsing de JSON en ClaudeUsage/CopilotUsage y cálculo de totales/por-dia."
    3. Integración rápida usando CI local (swift test) — 1d  
       Prompt para agente: "Configurar target de tests y verificar que `swift test` corre localmente."

- [task-005] Exportar historial a CSV — Baja — 2d — pending — [task-004]
  - Prompt para agente: "Crear función que exporte registros de uso a CSV con columnas (fecha, servicio, tokens, coste estimado) y añadir botón en UI para descargar."

- [task-006] Notificaciones de umbral — Media — 3d — pending — [task-001]
  - subtasks:
    1. Configuración de umbrales por servicio en preferencias — 4h  
       Prompt para agente: "Añadir modelo Preferences con thresholds; UI mínima para editar umbrales."
    2. Enviar notificaciones locales cuando se alcance umbral — 1.5d  
       Prompt para agente: "Implementar disparo de NSUserNotification/UNUserNotification cuando consumo proyectado cruce umbral."

- [task-007] CI macOS build — Alta — 3d — pending — []
  - subtasks:
    1. Crear workflow GitHub Actions para `swift build` y `swift test` (macos-latest) — 4h  
       Prompt para agente: "Generar .github/workflows/ci.yml que use macos-latest, instale dependencias y ejecute `swift build --configuration debug` y `swift test`."
    2. Agregar badge y documentación en README — 1h  
       Prompt para agente: "Actualizar README.md con badge de CI y comandos para build/test local."

Dependencias y orden recomendado:
- Priorizar task-001 (Keychain) y task-002 (Reintentos). task-003 y task-004 dependen de las dos anteriores. task-007 puede ejecutarse en paralelo.

Proceso de iteración (pequeñas PRs):
- Cada subtask debe ser una PR pequeña (<200 líneas) que incluya tests cuando aplica.
- Los prompts para agentes están listos; enviar uno por subtarea y revisar resultados localmente.

Registro de agentes utilizados:
- Agent-code (crear/editar archivos Swift)
- Agent-test (escribir tests y mocks)
- Agent-ci (crear workflow)
- Agent-docs (actualizar README y docs)

Actualizaciones futuras:
- Añadir checklist de revisión de seguridad antes de merge (Keychain, no secrets).
