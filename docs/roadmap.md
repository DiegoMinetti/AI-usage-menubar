
# Roadmap por fases

Fase 0 — Preparación (1 semana)
- Crear documentación básica (análisis, decisiones, tareas, progreso). (Hecho: carpeta /docs)
- Definir owner(s), criterios de aceptación y proceso de releases.

Fase 1 — Estabilización y seguridad (2 semanas)
- Asegurar almacenamiento seguro de tokens (Keychain, no en repositorio).
- Añadir reintentos exponenciales y circuit breaker para llamadas a APIs externas.
- Añadir validaciones y manejo de errores visibles para el usuario.

Hit: despliegue interno de build funcional en ejecutable macOS.

Fase 2 — Observabilidad y tests (2–3 semanas)
- Instrumentar métricas (latencia, tasas de error, llamadas).
- Añadir tests unitarios para servicios clave (parsing, persistencia).
- Configurar CI básico (build macOS, lint).

Fase 3 — Experiencia de usuario y funcionalidades (3–4 semanas)
- Mejorar UX del menú (estado, detalles por día, alertas por umbral).
- Añadir historial y exportación CSV de consumo.
- Notificaciones push/local para anomalías o límites próximos.

Fase 4 — Optimización y lanzamiento (2 semanas)
- Perfilado de consumo y optimización de llamadas.
- Preparar release notarizado y firma de la app (si aplica).
- Documentación de usuario y changelog.

Fase 5 — Mantenimiento continuo
- Calendarización de revisiones de dependencias, rotación de tokens y monitoreo de costes.
