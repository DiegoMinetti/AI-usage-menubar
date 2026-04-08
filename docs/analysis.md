
# Diagnóstico completo

Proyecto: AI-usage-menubar  
Objetivo: Proveer una aplicación macOS (menú bar) que monitoriza y muestra el uso de modelos de IA (Copilot, Claude), facturación y anomalías, para que el usuario gestione consumos y límites.

Resumen técnico:
- Código principal en Swift (paquete SwiftPM). UI basada en ventanas/menú (MenuContentView, MenuViewModel, GitHubLoginWindow).
- Servicios para consulta de métricas/estado: ClaudeUsageService, CopilotUsageService, ClaudeStatusService.
- Modelos de dominio: ClaudeUsage, CopilotUsage, ClaudeRecord, DailyTokens, etc.
- Persistencia ligera: CookieStorage.

Hallazgos y problemas actuales:
- Documentación del producto limitada; falta roadmap, backlog y decisiones técnicas registradas.
- No hay pipeline CI/automatizado visible para builds/release (archivos de build locales presentes).
- Manejo de credenciales y almacenamiento de tokens requiere clarificación y endurecimiento.
- Recolección de métricas y tolerancia a fallos (reintentos, caché) no está documentada explícitamente.
- Falta de tests unitarios/integración documentados.

Restricciones y supuestos:
- Aplicación nativa macOS (arm64/x86 posible) con Swift 6.
- Dependencia de APIs externas (Claude, Copilot) sujetas a límites y latencia.
- Privacidad: no almacenar secretos en repositorio.

Métricas críticas a medir:
- Latencia promedio de actualización de uso
- Número de llamadas API por día
- Errores/timeout por servicio
- Uso y coste estimado por periodo

Conclusión: la base de código implementa las piezas clave, pero necesita documentación de producto y técnica para priorizar mejoras, asegurar seguridad de credenciales y robustecer telemetría.
