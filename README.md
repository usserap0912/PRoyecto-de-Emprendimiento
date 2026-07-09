# 🛡️ SafeZone

<p align="center">
  <img src="https://img.shields.io/badge/version-1.0.0-blue?style=for-the-badge&labelColor=1a1a2e" alt="Version">
  <img src="https://img.shields.io/badge/Flutter-3.44+-02569B?style=for-the-badge&logo=flutter&logoColor=white&labelColor=1a1a2e" alt="Flutter">
  <img src="https://img.shields.io/badge/Android-3DDC84?style=for-the-badge&logo=android&logoColor=white&labelColor=1a1a2e" alt="Android">
  <img src="https://img.shields.io/badge/Web-4285F4?style=for-the-badge&logo=google-chrome&logoColor=white&labelColor=1a1a2e" alt="Web">
  <img src="https://img.shields.io/badge/license-Open%20Source-brightgreen?style=for-the-badge&labelColor=1a1a2e" alt="License">
</p>

**Red vecinal de seguridad para Collique, Comas — Lima Norte.**

SafeZone es una aplicación móvil que permite a los vecinos de Collique colaborar en la seguridad de su comunidad mediante reportes anónimos, alertas en tiempo real, un mapa interactivo de las 14 zonas, chat vecinal y más.

---

## ✨ Funcionalidades

| Módulo | Descripción |
|--------|-------------|
| 📰 **Muro en Tiempo Real** | Reportes categorizados con video, imágenes, reacciones emoji (🛡️⚠️😮🙏), comentarios en vivo, filtros temporales y actualización en tiempo real vía Supabase Realtime |
| 🗺️ **Mapa de Riesgo** | Mapa OpenStreetMap con CartoDB (claro/oscuro), marcadores de reportes con clustering, niveles de riesgo (baja/media/alta/crítica), 14 zonas de Collique, POIs (Hospital, Comisaría, Museo), bottom sheet de detalle |
| 🆘 **S.O.S.** | Alerta de emergencia con cuenta regresiva de 3s, vibración háptica, envío de ubicación GPS exacta a Supabase, modo offline |
| 💬 **Chat Vecinal** | Chat anónimo en tiempo real con los vecinos, burbujas diferenciadas (propio/otros), contador de mensajes |
| 📝 **Reportar** | Formulario para reportar incidentes con fotos, videos, selección de categoría (robo, sospechoso, extorsión, alumbrado, otros) y nivel de riesgo |
| 👤 **Mi Perfil** | Estadísticas personales (reportes, reacciones, alertas SOS), información del código y zona, toggle de tema claro/oscuro |
| 🔐 **Ingreso Seguro** | Splash animado con consejos de seguridad → selección de zona (14 zonas) → captcha vecinal → código único permanente por dispositivo |
| 🌙 **Modo Oscuro** | Tema claro/oscuro configurable con persistencia en SharedPreferences, aplicado globalmente |

---

## 🚀 Instalación

### Requisitos

- Flutter 3.38+ ([instalar](https://docs.flutter.dev/get-started/install))
- Dispositivo Android (físico o emulador) o navegador web
- Proyecto Supabase (opcional, la app funciona offline con datos de ejemplo)

### Pasos

```bash
# 1. Clonar el repositorio
git clone <repo-url>
cd safezone

# 2. Instalar dependencias
flutter pub get

# 3. Ejecutar
flutter run                    # Android
flutter run -d chrome          # Web
flutter run -d edge            # Microsoft Edge
```

---

## 🗄️ Configuración de Supabase

### 1. Base de datos

Ejecuta los scripts SQL en el Editor SQL de Supabase en este orden:

1. `supabase_migration.sql` — Tablas principales:
   - `profiles` — Perfiles anónimos de usuarios
   - `reports` — Reportes de incidentes
   - `reactions` — Reacciones emoji
   - `chat_messages` — Mensajes del chat
   - `sos_alerts` — Alertas de emergencia
   - RLS policies, índices y triggers para contadores

2. `supabase_migration_games.sql` — Tabla de juegos (opcional):
   - `user_scores` — Puntajes de minijuegos con RLS
   - Funciones `get_user_best_score` y `get_leaderboard`

3. Crear tabla de comentarios (si no existe):
```sql
CREATE TABLE IF NOT EXISTS report_comments (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  report_id UUID NOT NULL REFERENCES reports(id) ON DELETE CASCADE,
  user_code TEXT NOT NULL,
  content TEXT NOT NULL,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

ALTER TABLE report_comments ENABLE ROW LEVEL SECURITY;

CREATE POLICY "comments_insertable_by_all" ON report_comments
  FOR INSERT WITH CHECK (true);

CREATE POLICY "comments_readable_by_all" ON report_comments
  FOR SELECT USING (true);

CREATE INDEX IF NOT EXISTS idx_report_comments_report_id ON report_comments(report_id);
```

### 2. Storage

Crea un bucket público llamado `safezone-images`:

```sql
INSERT INTO storage.buckets (id, name, public)
VALUES ('safezone-images', 'safezone-images', true);

CREATE POLICY "Allow anonymous uploads"
ON storage.objects FOR INSERT TO anon
WITH CHECK (bucket_id = 'safezone-images');

CREATE POLICY "Allow anonymous reads"
ON storage.objects FOR SELECT TO anon
USING (bucket_id = 'safezone-images');
```

### 3. Credenciales

Las credenciales de Supabase están en `lib/services/supabase_service.dart`.

---

## 🏗️ Estructura del Proyecto

```
lib/
├── main.dart                          # Punto de entrada
├── app.dart                           # Configuración de tema y navegación
├── models/                            # Modelos de datos
│   ├── report.dart
│   ├── report_comment.dart
│   ├── chat_message.dart
│   ├── sos_alert.dart
│   ├── user_profile.dart
│   └── user_score.dart
├── screens/                           # Pantallas
│   ├── entry/                         # Onboarding (splash, zona, captcha, código)
│   │   ├── captcha_screen.dart
│   │   ├── code_assignment_screen.dart
│   │   ├── zone_selection_screen.dart
│   ├── splash/                        # Splash animado con consejos de seguridad
│   ├── home/                          # Navegación principal con BottomNavigationBar
│   ├── wall/                          # Muro de reportes en tiempo real
│   │   ├── wall_screen.dart
│   │   ├── feed_screen.dart
│   │   └── widgets/
│   │       └── post_card.dart
│   ├── map/                           # Mapa interactivo de Collique
│   │   └── risk_map_screen.dart
│   ├── sos/                           # Alerta SOS con GPS
│   ├── chat/                          # Chat vecinal anónimo
│   ├── report/                        # Formulario de reporte de incidentes
│   └── stats/                         # Perfil y estadísticas del usuario
├── services/                          # Servicios y API
│   ├── supabase_service.dart
│   ├── report_service.dart
│   ├── chat_service.dart
│   ├── location_service.dart
│   └── permission_service.dart
├── theme/                             # Temas claro/oscuro
│   └── app_theme.dart
└── widgets/                           # Widgets compartidos
    ├── reaction_buttons.dart
    ├── report_video_player.dart
    └── tag_badge.dart
```

---

## 🗺️ Mapa de Collique

El mapa usa **flutter_map** con tiles de **CartoDB** en dos estilos intercambiables y clustering de marcadores:

| Estilo | URL |
|--------|-----|
| ☀️ Claro (Positron) | `https://{s}.basemaps.cartocdn.com/light_all/...` |
| 🌙 Oscuro (Dark Matter) | `https://{s}.basemaps.cartocdn.com/dark_all/...` |

Incluye:
- **14 zonas** de Collique con marcadores numerados Z1–Z14
- **Puntos de referencia**: Hospital Sergio Bernales, Comisaría de Collique, Museo de los Colli
- **Alertas de riesgo** con códigos de colores (verde/amarillo/naranja/rojo)
- **Clustering** de marcadores con indicador numérico
- **Límites de cámara** para no salir del área de Collique
- **Bottom sheet de detalle** al tocar un marcador: categoría, nivel de riesgo, tiempo, imagen, descripción
- **Confirmación comunitaria**: botón "Confirmar que es real 🛡️"

---

## 🔐 Flujo de Ingreso

```
Splash animado (4s + consejos aleatorios de seguridad)
  → ¿Código existe en SharedPreferences?
    → Sí → HomeScreen directamente
    → No → Selección de zona (14 zonas de Collique)
      → Captcha vecinal (3 preguntas de seguridad)
        → Código único permanente (user_device_code)
          → HomeScreen con BottomNavigationBar
```

El código se guarda en `SharedPreferences` bajo la clave `user_device_code` y es **permanente por dispositivo**. Nunca cambia aunque se cierre la app.

---

## 📱 Stack Tecnológico

| Tecnología | Uso |
|------------|-----|
| **Flutter 3.38+** | Framework de UI multiplataforma |
| **Dart** | Lenguaje de programación |
| **Supabase** | Backend: PostgreSQL, Auth anónimo, Storage, Realtime (suscripciones en vivo) |
| **flutter_map + CartoDB** | Mapas OpenStreetMap con clustering de marcadores |
| **flutter_map_marker_cluster** | Agrupación de marcadores de reportes |
| **video_player** | Reproducción de videos de evidencia |
| **image_picker** | Cámara y galería para reportes |
| **geolocator / geocoding** | GPS y direcciones para SOS y reportes |
| **shared_preferences** | Almacenamiento local (código de dispositivo, tema) |
| **shimmer** | Efectos de carga esqueletales |
| **timeago** | Fechas relativas en español |
| **flutter_local_notifications** | Notificaciones push locales |
| **permission_handler** | Gestión de permisos de cámara, ubicación, notificaciones |

---

## 🧪 Testing

```bash
flutter test
flutter analyze
```

---

## 👥 Contribuir

1. Haz fork del proyecto
2. Crea una rama (`git checkout -b feature/nueva-funcionalidad`)
3. Commitea tus cambios (`git commit -m 'feat: agrega nueva funcionalidad'`)
4. Sube la rama (`git push origin feature/nueva-funcionalidad`)
5. Abre un Pull Request

---

## 📄 Licencia

Proyecto de código abierto para la comunidad de Collique, Comas — Lima Norte.
