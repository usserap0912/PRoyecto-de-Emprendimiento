# 🛡️ SafeZone

**Red vecinal de seguridad para Collique, Comas.**

SafeZone es una aplicación móvil que permite a los vecinos de Collique colaborar en la seguridad de su comunidad mediante reportes anónimos, alertas en tiempo real, un mapa de riesgo y un chat vecinal.

---

## ✨ Funcionalidades

| Módulo | Descripción |
|--------|-------------|
| 📰 **Muro** | Reportes de la comunidad con filtros por nivel de peligro |
| 🗺️ **Mapa de Riesgo** | Visualización de zonas seguras y peligrosas con markers |
| 🆘 **S.O.S.** | Alerta de emergencia con ubicación GPS y cuenta regresiva |
| 💬 **Chat Vecinal** | Chat anónimo en tiempo real con los vecinos |
| 📝 **Reportar** | Formulario para reportar incidentes con fotos y videos |
| 📊 **Estadísticas** | Perfil del usuario con contadores y preferencias |
| 🌙 **Modo Oscuro** | Tema claro/oscuro configurable |

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

Ejecuta el script `supabase_migration.sql` en el SQL Editor de Supabase. Esto crea:

- `profiles` — Perfiles anónimos de usuarios
- `reports` — Reportes de incidentes
- `reactions` — Reacciones (escudo, alerta, resuelto)
- `chat_messages` — Mensajes del chat
- `sos_alerts` — Alertas de emergencia
- RLS policies, índices y triggers para contadores

### 2. Storage

Crea un bucket público llamado `safezone-images`:

```sql
-- En SQL Editor:
INSERT INTO storage.buckets (id, name, public)
VALUES ('safezone-images', 'safezone-images', true);

-- Políticas para subida y lectura anónima:
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
├── main.dart                    # Punto de entrada
├── app.dart                     # Configuración de tema y navegación
├── models/                      # Modelos de datos
│   ├── report.dart
│   ├── chat_message.dart
│   ├── sos_alert.dart
│   └── user_profile.dart
├── screens/                     # Pantallas
│   ├── entry/                   # Onboarding (zona, captcha, código)
│   ├── home/                    # Navegación principal
│   ├── wall/                    # Muro de reportes
│   ├── map/                     # Mapa de riesgo
│   ├── sos/                     # Alerta SOS
│   ├── chat/                    # Chat vecinal
│   ├── report/                  # Formulario de reporte
│   └── stats/                   # Estadísticas y perfil
├── services/                    # Servicios y API
│   ├── supabase_service.dart
│   ├── report_service.dart
│   ├── chat_service.dart
│   └── location_service.dart
├── theme/                       # Temas claro/oscuro
│   └── app_theme.dart
└── widgets/                     # Widgets compartidos
    ├── reaction_buttons.dart
    └── tag_badge.dart
```

---

## 📱 Stack Tecnológico

| Tecnología | Uso |
|------------|-----|
| **Flutter** | Framework de UI multiplataforma |
| **Dart** | Lenguaje de programación |
| **Supabase** | Backend: PostgreSQL, Auth, Storage, Realtime |
| **flutter_map** | Mapas OpenStreetMap |
| **image_picker** | Cámara y galería |
| **geolocator/geocoding** | GPS y direcciones |
| **shared_preferences** | Almacenamiento local |
| **shimmer** | Efectos de carga |
| **timeago** | Fechas relativas en español |

---

## 🧪 Testing

```bash
flutter test
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

Proyecto de código abierto para la comunidad de Collique, Comas.
