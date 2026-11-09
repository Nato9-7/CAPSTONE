# RB Alertas — Pendientes

Estado al 01-11-2026. Lo que ya funciona en producción: registro con verificación por
correo, inicio de sesión con token (la sesión queda guardada), recuperar contraseña,
reportar incidentes con foto y ubicación, mapa con pines y filtros (los reportes del mismo
hecho se muestran como un solo incidente), detalle del incidente, confirmar o desmentir,
comentarios, pantalla de Alertas, zonas seguras, grupos de vecinos, notificaciones push
(Firebase), perfil, rediseño de la app y panel de administración con la red en Neo4j.

**Producción corre en una VM de Azure** y la API está en
`https://rbalerta.duckdns.org`. El servidor se actualiza solo al subir a `main`.
El servidor anterior de Oracle ya no se usa.

Marca con `[x]` lo que vayas terminando.

---

## 1. Para mostrar la app en un celular

- [x] **Plataforma Android** (carpeta `android/` en `main`).
- [x] **HTTPS con dominio** (`https://rbalerta.duckdns.org`, Caddy).
- [x] **Workflow para generar el `.ipa` de iPhone** (`.github/workflows/ios-ipa.yml`).
- [x] **Generar un APK nuevo** con todo lo de octubre y noviembre (comentarios, grupos,
      notificaciones, rediseño, incidentes agrupados y panel nuevo).
- [x] **Probar el APK en un celular real** (mapa, ubicación, foto, inicio de sesión, avisos).
- [x] **Firma propia del APK** (keystore de release guardado fuera del repositorio).
- [x] **Publicar la app web**, para no depender de un computador.

## 2. Funcionalidades comprometidas que faltan

- [x] **Pantalla de Alertas.**
- [x] **Notificaciones push** (Firebase, con registro de envío ENVIADA/FALLIDA).
- [x] **Confirmar o desmentir un reporte.**
- [x] **Comentarios en los reportes** (con respuestas, fotos y moderación del admin).
- [x] **Reputación** (`puntaje_reputacion`, de 0 a 100; la calcula el grafo cada 10 minutos).
- [x] **Recuperar contraseña.**
- [x] **Grupos de vecinos** (con reportes privados del grupo).
- [x] **Agrupar reportes del mismo hecho** en un solo incidente (misma categoría, < 300 m,
      < 3 h); quien ya recibió la alerta no la recibe de nuevo.
- [ ] **Editar perfil** y **Privacidad y seguridad**: hoy avisan «disponible pronto».
- [ ] **Buscador del mapa** y los íconos de **menú** y **ajustes**: revisar si quedaron
      con función tras el rediseño.
- [x] **Marcar como `EXPIRADO` los reportes vencidos.**
- [ ] **Pedir la comuna al registrarse.** Las cuentas quedan sin comuna.

## 3. Panel de administración

- [x] Cuenta admin `rbalertas.notificaciones@gmail.com` (entra directo al panel, también
      con la sesión guardada).
- [x] Resumen, reportes (con comentarios), usuarios y grupos.
- [x] **Red (Neo4j):** menú lateral en computador; hallazgos (cuentas sospechosas con la
      evidencia, reputación con su desglose, incidentes agrupados); explorador con
      buscador, capas, línea de tiempo, comunidades, «¿Cómo se conecta con…?» (camino más
      corto) y grupos de vecinos; red en miniatura en el resumen.
- [ ] **Revisar el panel con los datos reales** en la presentación. Ojo: hoy aparece un
      «grupo sospechoso» de 2 cuentas que son las de prueba del equipo (se confirman solo
      entre ellas). Conviene tener votos de más cuentas o explicarlo.

## 4. Seguridad y operación del servidor

- [x] **Proteger las credenciales del equipo** (contraseñas y llaves de los servidores
      guardadas fuera del repositorio y de las carpetas compartidas).
- [ ] **Respaldar las fotos y el grafo.** `scripts/backup.sh` respalda solo MySQL; los
      volúmenes `uploads_data` y `neo4j_data` quedan fuera (el grafo se puede rehacer desde
      MySQL, las fotos no).
- [x] **Borrar las fotos al eliminar.** Al eliminar un reporte desde el panel se borran sus
      evidencias y las fotos de sus comentarios; al eliminar un comentario (su autor o el
      admin) se borra su foto.
- [ ] **Limitar cuántos reportes puede crear un usuario** (por tiempo e IP).
- [ ] **Acotar CORS.** Hoy `allow_origins=["*"]`; dejar solo los orígenes reales.
- [ ] **Más pruebas.** Ya hay pruebas en `rb_alertas_api/tests/` (agrupación de incidentes,
      zonas de riesgo, sospechosos y reputación, alias, archivos subidos y errores de BD:
      `pytest tests`); faltan las de reportes, sesiones, verificación de correo, comentarios
      y grupos contra una base de prueba.
- [ ] **Revisar el borrado en cadena.** Al eliminar una cuenta se borran también sus
      reportes; evaluar si conviene conservarlos como anónimos.

## 5. Repositorio y entregas académicas

- [x] **README de la API** y **README del proyecto** en el repositorio.
- [ ] **Actualizar el UML y la Arquitectura** con: sesiones con token, verificación de
      correo, evidencias, comentarios, grupos, notificaciones push (Firebase), Neo4j como
      copia en grafo de MySQL (reputación, sospechosos, incidentes), Caddy con HTTPS,
      despliegue automático desde `main` y el traslado a Azure.
- [ ] **Informe Final: 24-11-2026.**

---

## Cómo se trabaja en este proyecto

- Una rama por tarea (`feature/<nombre>`), commits en español, y fusionar a `dev` y luego
  a `main`. El panel de administración se trabaja en la rama `admin`.
- **Subir a `main` publica en producción**: el servidor revisa cada 5 minutos y, si cambió
  algo dentro de `rb_alertas_api/`, reconstruye y reinicia la API. Si la API nueva no
  responde, vuelve sola a la versión anterior. Registro:
  `~/rbalerta-stack/backups/auto_despliegue.log` en la VM de Azure.
- En el servidor: MySQL, la API, Caddy (HTTPS) y Neo4j corren con Docker en
  `/home/alertarb/rbalerta-stack`. Neo4j está en `docker-compose.override.yml` y solo
  escucha en 127.0.0.1.
- Base de datos desde el PC: Beekeeper Studio, conexión «RB Alertas (Azure)» (túnel SSH con
  la llave de la VM, que no va en el repositorio).
- Para generar el APK en el PC de Bárbara: Android SDK y Java 21 en `C:\Users\barba\Android`,
  y `flutter build apk --split-per-abi` (el que va al Drive es `app-arm64-v8a-release.apk`).
