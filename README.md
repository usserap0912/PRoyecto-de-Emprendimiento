# 🛡️ SafeZone

**Red vecinal de seguridad para Collique, Comas — Lima Norte.**

SafeZone es una aplicación móvil que permite a los vecinos de Collique colaborar en la seguridad de su comunidad mediante reportes anónimos, alertas en tiempo real, un mapa interactivo de las 14 zonas, minijuegos educativos y chat vecinal.

---

## ✨ Funcionalidades

| Módulo | Descripción |
|--------|-------------|
| 📰 **Muro en Tiempo Real** | Reportes con video, imágenes, reacciones emoji (🛡️⚠️😮🙏) y comentarios en vivo |
| 🗺️ **Mapa de Collique** | Mapa OpenStreetMap con CartoDB (claro/oscuro), 14 zonas, POIs, alertas de riesgo |
| 🎮 **Zona de Juegos** | Trivia de Seguridad Collique + Patrullaje de la Revolución (arcade 2D) |
| 🆘 **S.O.S.** | Alerta de emergencia con ubicación GPS y cuenta regresiva |
| 💬 **Chat Vecinal** | Chat anónimo en tiempo real con los vecinos |
| 📝 **Reportar** | Formulario para reportar incidentes con fotos y videos |
| 🔐 **Ingreso Seguro** | Captcha vecinal + código único persistente por dispositivo |
| 🌙 **Modo Oscuro** | Tema claro/oscuro configurable con persistencia |

---

## 🚀 Instalación

### Requisitos

- Flutter 3.38+ ([instalar](https://docs.flutter.dev/get-started/install))
- Dispositivo Android (físico o emulador)
- Proyecto Supabase (opcional, la app funciona offline con datos de ejemplo)

### Pasos

```bash
# 1. Clonar el repositorio
git clone <repo-url>
cd safezone

# 2. Instalar dependencias
flutter pub get

# 3. Ejecutar en Android
flutter run
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

2. `supabase_migration_games.sql` — Tabla de juegos:
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
│   ├── home/                          # Navegación principal (BottomNav)
│   ├── wall/                          # Muro de reportes en tiempo real
│   │   ├── wall_screen.dart
│   │   └── widgets/
│   │       └── post_card.dart
│   ├── map/                           # Mapa interactivo de Collique
│   │   └── risk_map_screen.dart
│   ├── games/                         # Módulo gamificado
│   │   ├── games_hub_screen.dart
│   │   ├── trivia_game_screen.dart
│   │   └── patrol_game_screen.dart
│   ├── sos/                           # Alerta SOS
│   ├── chat/                          # Chat vecinal
│   ├── report/                        # Formulario de reporte
│   └── stats/                         # Estadísticas y perfil
├── services/                          # Servicios y API
│   ├── supabase_service.dart
│   ├── report_service.dart
│   ├── chat_service.dart
│   └── location_service.dart
├── theme/                             # Temas claro/oscuro
│   └── app_theme.dart
└── widgets/                           # Widgets compartidos
    ├── reaction_buttons.dart
    ├── report_video_player.dart
    └── tag_badge.dart
```

---

## 🗺️ Mapa de Collique

El mapa usa **flutter_map** con tiles de **CartoDB** en dos estilos intercambiables:

| Estilo | URL |
|--------|-----|
| ☀️ Claro (Positron) | `https://{s}.basemaps.cartocdn.com/light_all/...` |
| 🌙 Oscuro (Dark Matter) | `https://{s}.basemaps.cartocdn.com/dark_all/...` |

Incluye:
- **14 zonas** de Collique con marcadores numerados
- **Puntos de referencia**: Hospital Sergio Bernales, Comisaría de Collique, Museo de los Colli
- **Alertas de riesgo** en zonas altas con códigos de colores
- **Límites de cámara** para no salir del área de Collique
- **Walk With Me** — Comparte tu ubicación en tiempo real

---

## 🎮 Minijuegos

### 🧠 Trivia de Seguridad Collique
- 15 preguntas sobre prevención de riesgos, números de emergencia y geografía local
- 3 vidas, sistema de rachas y puntaje por tiempo
- Animaciones al acertar/fallar con explicaciones

### 🚓 Patrullaje de la Revolución
- Juego arcade 2D con GameLoop vía AnimationController
- 4 carriles en la Av. Revolución
- Esquiva peligros (🔴⚡🔥💀⚠️) y recolecta escudos (🛡️)
- Velocidad progresiva con puntuación infinita

---

## 🔐 Flujo de Ingreso

```
Splash (4s + consejos) 
  → ¿Código existe? 
    → Sí → HomeScreen 
    → No → Selección de zona (14 zonas)
      → Captcha vecinal
        → Código único permanente (user_device_code)
          → HomeScreen
```

El código se guarda en `SharedPreferences` bajo la clave `user_device_code` y es **permanente por dispositivo**. Nunca cambia aunque se cierre la app.

---

## 📱 Stack Tecnológico

| Tecnología | Uso |
|------------|-----|
| **Flutter 3.38+** | Framework de UI multiplataforma |
| **Dart** | Lenguaje de programación |
| **Supabase** | Backend: PostgreSQL, Auth, Storage, Realtime |
| **flutter_map + CartoDB** | Mapas OpenStreetMap con 2 estilos visuales |
| **video_player** | Reproducción de videos de evidencia |
| **image_picker** | Cámara y galería |
| **geolocator / geocoding** | GPS y direcciones |
| **shared_preferences** | Almacenamiento local (código, tema) |
| **shimmer** | Efectos de carga esqueletales |
| **timeago** | Fechas relativas en español |
| **flutter_local_notifications** | Notificaciones push locales |

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
