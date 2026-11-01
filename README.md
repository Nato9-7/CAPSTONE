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

**RB Alertas** nace como una solución tecnológica accesible y centralizada para empoderar a la comunidad. Mediante el uso de dispositivos móviles, la aplicación permite emitir alertas geolocalizadas inmediatas, activar botones de emergencia y mantener informados a los vecinos en tiempo real, fortaleciendo la prevención y la colaboración comunitaria.

---

## 3. Objetivos del Proyecto

### Objetivo General

Desarrollar una aplicación móvil multiplataforma para la gestión de alertas de seguridad ciudadana y emergencias vecinales en la comuna de Puerto Montt, facilitando la comunicación en tiempo real y la colaboración entre vecinos.

### Objetivos Específicos

- Diseñar una interfaz de usuario intuitiva, accesible y orientada a la rápida acción en situaciones de emergencia.
- Implementar un sistema de botón de pánico y emisión de alertas tempranas con geolocalización.
- Proveer un mapa interactivo para la visualización de incidentes reportados en la zona.
- Gestionar el registro y acceso seguro de vecinos pertenecientes a la comunidad.
- Facilitar el acceso rápido a números y contactos de los principales servicios de emergencia locales.

---

## 4. Funcionalidades Principales

- **Pantalla de Bienvenida y Acceso:** Identidad visual de RB Alertas con flujos de inicio de sesión y registro de usuarios.
- **Botón de Pánico:** Activación rápida de señales de auxilio ante situaciones de peligro inminente.
- **Mapa de Incidentes:** Visualización georreferenciada de reportes y eventos comunitarios en vivo.
- **Notificaciones Comunitarias:** Envío y recepción de avisos de seguridad y alertas preventivas.
- **Contactos de Emergencia:** Acceso directo a números de asistencia (Carabineros, Bomberos, SAMU).

---

## 5. Requisitos del Sistema y Tecnologías

### Tecnologías

- **Framework:** Flutter (versión 3.13.0 o superior)
- **Lenguaje de Programación:** Dart
- **Control de Versiones:** Git & GitHub

### Requisitos Previos para Desarrollo

- Tener instalado el SDK de Flutter.
- Disponer de un navegador web (Google Chrome) para pruebas web, o Android Studio / emulador configurado para entorno móvil.

---

## 6. Guía de Instalación y Ejecución

1. **Clonar el repositorio:**

   ```bash
   git clone https://github.com/Nato9-7/CAPSTONE.git
   cd CAPSTONE/rb_alertas
   ```

2. **Descargar las dependencias del proyecto:**

   ```bash
   flutter pub get
   ```

3. **Verificar el entorno de desarrollo:**

   ```bash
   flutter doctor
   ```

4. **Ejecutar la aplicación:**
   - **En Google Chrome (Web):**

     ```bash
     flutter run -d chrome
     ```

     ```

     ```

   - **En dispositivo móvil o emulador:**
     ```bash
     flutter run
     ```
