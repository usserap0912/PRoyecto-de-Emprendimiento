# Guía: Crear la animación de ZoneBot en Rive.app

## Requisitos

1. Crear una cuenta gratuita en [Rive.app](https://rive.app)
2. Tener el archivo `.riv` listo para colocar en `assets/animations/zonebot.riv`

---

## Paso 1: Crear el diseño de ZoneBot

1. Ve a [Rive.app](https://rive.app) e inicia sesión
2. Clic en **"New File"** → **"Blank File"**
3. Nombra el artboard como **"ZoneBot"**
4. Diseña un personaje robot guardián con forma de escudo:
   - **Cuerpo**: Círculo con gradiente rojo (#C3110C) a rojo oscuro (#740A03)
   - **Ojos**: Dos círculos blancos con pupilas negras
   - **Escudo**: Un ícono de escudo en el centro (puedes importar un SVG)
   - **Antena**: Una pequeña línea con círculo en la parte superior

---

## Paso 2: Crear los 3 estados de animación

### Estado: `idle` (respiración suave)
1. En la línea de tiempo, crea un **nuevo clic de animación** llamado `idle`
2. Keyframes:
   - `0s`: Escala 100%, posición normal
   - `1s`: Escala 102%, ligeramente hacia arriba (inhalar)
   - `2s`: Escala 100%, posición normal (exhalar)
3. Activa **Loop** para que se repita infinitamente
4. Ajusta la curva a **Ease In Out** para un movimiento suave

### Estado: `thinking` (carga/pensamiento)
1. Crea otro clic de animación llamado `thinking`
2. Keyframes:
   - `0s`: Rotación 0°, opacidad normal
   - `0.5s`: Rotación 15°, opacidad 80% (ladea la cabeza)
   - `1.5s`: Rotación -15°, opacidad 80% (ladea al otro lado)
   - `2s`: Rotación 0°, opacidad normal
3. Agrega un **círculo punteado giratorio** alrededor del escudo
4. Activa **Loop**

### Estado: `happy` (celebración)
1. Crea otro clic de animación llamado `happy`
2. Keyframes:
   - `0s`: Escala 100%, brillo normal
   - `0.15s`: Escala 110% (rebote)
   - `0.3s`: Escala 95% (rebote inverso)
   - `0.5s`: Escala 105%
   - `0.7s`: Escala 100%
3. Agrega **destellos/estrellas** alrededor (partículas pequeñas)
4. El ojo derecho forma un arco feliz (^)
5. Desactiva Loop (reproducir una vez)

---

## Paso 3: Configurar la State Machine

1. Abre la pestaña **State Machine** (ícono de engranaje)
2. Crea los **inputs de tipo Trigger** (no Boolean):
   - `idle`
   - `thinking`  
   - `happy`
3. Conecta cada trigger a su animación correspondiente
4. Configura las transiciones:
   - `idle → thinking` (trigger: thinking)
   - `thinking → idle` (trigger: idle, auto después de completar)
   - `idle → happy` (trigger: happy)
   - `happy → idle` (trigger: idle, auto después de completar)
5. Nombra la State Machine como **"State"**

---

## Paso 4: Exportar

1. Archivo → **Export** → **Rive (.riv)**
2. Guardar como `zonebot.riv`
3. Copiar a `assets/animations/zonebot.riv` en el proyecto

---

## Conexión con el código

El archivo `lib/widgets/zonebot_avatar.dart` ya tiene el código listo para usar el `.riv`:

```dart
// En initState, reemplazar el CustomPainter con:
rive.RiveAnimation.asset(
  'assets/animations/zonebot.riv',
  artboard: 'ZoneBot',
  stateMachines: ['State'],
  onInit: (artboard) {
    final controller = rive.StateMachineController.fromArtboard(
      artboard, 'State',
    );
    if (controller != null) {
      artboard.addController(controller!);
    }
  },
)

// Para cambiar estado (desde zonebot_screen.dart):
// _riveController?.fire('thinking'); // o 'happy' o 'idle'
```

El estado `_botAnimationState` de `zonebot_screen.dart` ('idle', 'thinking', 'happy') se conecta automáticamente a los triggers de la State Machine.

---

## Recursos útiles

- [Rive Tutorial: Introduction to State Machines](https://rive.app/learn/rive-tutorials/)
- [Rive Tutorial: Character Animation](https://rive.app/learn/rive-tutorials/)
- [Formato Rive .riv - Documentación](https://rive.app/docs/)
