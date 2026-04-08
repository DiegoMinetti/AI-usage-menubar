
# Decisiones técnicas

1. Lenguaje y plataforma
- Decisión: Swift (SwiftPM) para macOS menu bar app.
- Razonamiento: integración nativa más sencilla, mejor experiencia de usuario y acceso a Keychain.

2. Gestión de credenciales
- Decisión: almacenar tokens en Keychain; nunca en código o archivos de configuración.
- Razonamiento: seguridad nativa del sistema, requisito de privacidad.

3. Comunicaciones con APIs externas
- Decisión: llamadas HTTP con reintentos exponenciales + circuit breaker; tiempo de espera configurable.
- Razonamiento: reduce impacto de latencias intermitentes y evita saturar APIs externas.

4. Persistencia local
- Decisión: almacenamiento ligero para caché y cookies (CookieStorage presente); datos críticos en Keychain; historial opcional en SQLite/Archivos JSON.
- Razonamiento: simplicidad vs necesidad; empezar con JSON o UserDefaults para historial pequeño y migrar si crece.

5. Observabilidad
- Decisión: instrumentar métricas internas (latencia, errores, contadores). Logs estructurados para diagnósticos.
- Razonamiento: permite detectar regressiones y cuantificar llamadas/costes.

6. Testing y CI
- Decisión: tests unitarios para lógica y mocks para servicios; pipeline CI que construya con SwiftPM.
- Razonamiento: mantener estabilidad en integraciones con APIs externas.

7. Privacidad y datos
- Decisión: no enviar datos de usuarios ni secretos fuera del dispositivo sin consentimiento; preferir solo métricas de diagnóstico (si acaso, anonimizadas).
- Razonamiento: cumplimiento básico de privacidad y menor riesgo legal.

Notas: registrar futuras decisiones en este documento antes de implementar cambios significativos.
