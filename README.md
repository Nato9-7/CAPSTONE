# RB Alertas

Sistema móvil de seguridad ciudadana y alertas comunitarias para Puerto Montt.

---

## 1. Información Académica

- **Institución:** Duoc UC
- **Carrera:** Ingeniería en Informática
- **Proyecto:** Capstone APT122
- **Integrantes:**
  - Bárbara Palma
  - Renato Díaz
- **Ubicación:** Puerto Montt, Chile

---

## 2. Problemática y Justificación

### Problemática

En la comuna de Puerto Montt, los vecinos enfrentan desafíos constantes en materia de seguridad ciudadana, tiempos de respuesta ante emergencias y falta de canales directos de comunicación entre las comunidades locales y los organismos pertinentes. La coordinación vecinal suele realizarse a través de plataformas no especializadas, lo que dificulta la centralización y la rápida visualización de eventos de riesgo.

### Justificación

**RB Alertas** nace como una solución tecnológica accesible y centralizada para empoderar a la comunidad. Mediante el uso de dispositivos móviles, la aplicación permite emitir alertas geolocalizadas inmediatas, acceder rápidamente a los servicios de emergencia y mantener informados a los vecinos en tiempo real, fortaleciendo la prevención y la colaboración comunitaria.

---

## 3. Objetivos del Proyecto

### Objetivo General

Desarrollar una aplicación móvil multiplataforma para la gestión de alertas de seguridad ciudadana y emergencias vecinales en la comuna de Puerto Montt, facilitando la comunicación en tiempo real y la colaboración entre vecinos.

### Objetivos Específicos

- Diseñar una interfaz de usuario intuitiva, accesible y orientada a la rápida acción en situaciones de emergencia.
- Implementar la emisión de alertas tempranas con geolocalización y el aviso a los vecinos cercanos.
- Proveer un mapa interactivo para la visualización de incidentes reportados en la zona.
- Gestionar el registro y acceso seguro de vecinos pertenecientes a la comunidad.
- Facilitar el acceso rápido a números y contactos de los principales servicios de emergencia locales.

---

## 4. Funcionalidades Principales

- **Cuenta y acceso:** registro con verificación por correo, inicio de sesión con sesión guardada y recuperación de contraseña.
- **Reporte de incidentes:** reporte geolocalizado con categoría, descripción y foto o video como evidencia.
- **Mapa de incidentes:** reportes vigentes en el mapa, con filtros, zonas de riesgo y mapa de calor. Los reportes del mismo hecho se muestran como un solo incidente.
- **Validación comunitaria:** los vecinos confirman o desmienten cada reporte y conversan en sus comentarios (con respuestas y fotos).
- **Alertas y notificaciones push:** aviso a quien tiene una zona segura (casa, trabajo, estudio) cerca del incidente o pertenece al grupo donde se compartió.
- **Grupos de vecinos:** grupos con código de invitación y reportes privados del grupo.
- **Contactos de emergencia:** acceso directo a Carabineros, Bomberos, SAMU y Seguridad Ciudadana de la comuna.
- **Privacidad:** quien reporta o comenta aparece con un alias; su nombre real nunca se muestra.
- **Panel de administración:** moderación de reportes, comentarios, denuncias, usuarios y grupos, y una red en Neo4j para detectar cuentas sospechosas, calcular la reputación de los vecinos y ver dónde ocurren más incidentes.

---

## 5. Arquitectura y Tecnologías

```
App Flutter (Android, iOS, web)  ──HTTPS──▶  Caddy  ──▶  API FastAPI  ──▶  MySQL
                                                              │
                                                              ├──▶  Neo4j (grafo del panel, copia de MySQL)
                                                              ├──▶  Firebase Cloud Messaging (push)
                                                              └──▶  SMTP (correos)
```

| Componente | Tecnologías |
| --- | --- |
| Aplicación móvil y web | Flutter, Dart, flutter_map (OpenStreetMap), Firebase Messaging |
| API | Python, FastAPI, Uvicorn, mysql-connector-python, bcrypt |
| Datos | MySQL (base principal), Neo4j (análisis en grafo) |
| Servidor | VM de Azure con Docker, Caddy (HTTPS), dominio `rbalerta.duckdns.org` |
| Control de versiones y CI | Git, GitHub y GitHub Actions (compilación del `.ipa` de iPhone) |

---

## 6. Estructura del Repositorio

```
CAPSTONE/
├── rb_alertas/                Aplicación Flutter.
│   ├── lib/
│   │   ├── main.dart          Punto de entrada de la app.
│   │   ├── config/            URL de la API, versión de la app y capa base del mapa.
│   │   ├── servicios/         Comunicación con la API (sesión, reportes, grupos, push...).
│   │   ├── vistas/            Pantallas (mapa, alertas, perfil, grupos, panel admin...).
│   │   ├── widgets/           Componentes reutilizables (comentarios, votos, capas del mapa...).
│   │   └── tema/              Colores y estilos de la app.
│   ├── assets/                Íconos, imágenes y fuentes.
│   ├── test/                  Pruebas de widgets (con una API falsa en test/soporte/).
│   ├── android/  ios/  web/   Proyectos de cada plataforma.
│   └── pubspec.yaml           Dependencias de la app.
├── rb_alertas_api/            API REST (ver rb_alertas_api/README.md).
│   ├── app/
│   │   ├── rutas/             Endpoints: usuarios, reportes, grupos y admin.
│   │   ├── servicios/         Reglas de negocio, correo, push y grafo Neo4j.
│   │   └── comun/             Utilidades compartidas (alias, archivos, SQL).
│   ├── sql/                   Scripts de cambios en la base de datos.
│   └── tests/                 Pruebas con pytest.
├── Fase 1/                    Evidencias académicas de la Fase 1 (grupales e individuales).
├── Fase 2/                    Evidencias de la Fase 2, incluida la documentación del
│                              proyecto (modelo de datos, despliegue con Docker, APK).
├── .github/workflows/         GitHub Actions: compilación del .ipa de iPhone.
├── PENDIENTES.md              Estado del proyecto y tareas pendientes.
└── README.md
```

---

## 7. Guía de Instalación y Ejecución

### Requisitos previos

- SDK de Flutter estable (con Dart 3.13 o superior).
- Google Chrome para pruebas web, o Android Studio / un emulador para el entorno móvil.
- Para la API: Python 3.12 o superior (ver `rb_alertas_api/README.md`).

### Aplicación

1. **Clonar el repositorio:**

   ```bash
   git clone https://github.com/Nato9-7/CAPSTONE.git
   cd CAPSTONE/rb_alertas
   ```

2. **Descargar las dependencias:**

   ```bash
   flutter pub get
   ```

3. **Verificar el entorno de desarrollo:**

   ```bash
   flutter doctor
   ```

4. **Ejecutar la aplicación** (por defecto usa la API de producción, `https://rbalerta.duckdns.org`):

   ```bash
   flutter run -d chrome      # navegador
   flutter run                # dispositivo móvil o emulador
   ```

   Para usar una API local:

   ```bash
   flutter run --dart-define=API_URL=http://localhost:3000
   ```

5. **Ejecutar las pruebas:**

   ```bash
   flutter test
   ```

### API

La instalación, configuración (`.env`) y ejecución de la API están en
[`rb_alertas_api/README.md`](rb_alertas_api/README.md).

---

## 8. Forma de Trabajo y Despliegue

- Una rama por tarea (`feature/<nombre>`), commits en español; se fusiona a `dev` y luego a `main`.
- **Subir a `main` publica la API en producción:** el servidor revisa los cambios cada 5 minutos,
  reconstruye la API con Docker y, si la versión nueva no responde, vuelve sola a la anterior.
- El estado actual del proyecto y lo que falta está en [`PENDIENTES.md`](PENDIENTES.md).
