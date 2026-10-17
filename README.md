# Incident Recorder by Leonera

App de iPhone (SwiftUI, sin dependencias de terceros) para grabar una incidencia con
las cámaras **trasera y frontal a la vez**, con la pantalla en negro, guardando el video
en **bloques de 1 minuto** en el teléfono y subiéndolos a **Google Drive** en cuanto hay
internet.

- Nombre visible: **Incident Recorder by Leonera**
- Bundle ID: `com.leonardoramirezr.incidentrecorderbyleonera`
  (extensión de pantalla negra: `com.leonardoramirezr.incidentrecorderbyleonera.ShieldConfiguration`)
- iOS 17 o posterior. La grabación con dos cámaras necesita un iPhone XS/XR o más nuevo;
  en modelos sin multicámara se graba solo con la trasera.

## Cómo funciona

1. **Primer arranque.** La app pide, explicando para qué sirve cada cosa:
   - Conectar **Google Drive** (OAuth de Google con PKCE; permiso `drive.file`, la app solo
     ve los archivos que ella misma crea).
   - Permiso de **Tiempo en pantalla** (Family Controls): se usa para bloquear las demás
     apps mientras se graba; se desbloquean con el gesto de las 4 esquinas.
   - **Ubicación siempre**: para imprimir las coordenadas en el video, registrar el recorrido
     aunque la app no esté en pantalla y mantenerla activa en segundo plano para terminar de
     subir los bloques.
   - Cámara y micrófono.
2. **Pantalla principal.** Video en vivo de la cámara trasera (pantalla completa) y la
   frontal (recuadro), con el botón de grabar abajo al centro.
3. **Grabando.** Al pulsar grabar empieza la grabación, se muestra la animación del gesto de
   desbloqueo y la pantalla queda **completamente negra** (no bloqueada; brillo al mínimo y
   sin que el iPhone se bloquee solo). Si alguien abre otra app, iOS muestra una pantalla
   negra (escudo de Tiempo en pantalla).
   - Cada minuto se cierra un bloque `.mov` (HEVC, 1080×1920, con audio), se guarda en el
     iPhone y se sube a Drive de inmediato.
   - Sin internet se sigue grabando; los bloques se suben solos cuando vuelve la conexión,
     aunque la app esté en segundo plano o el teléfono bloqueado.
4. **Desbloqueo.** Toca las 4 esquinas empezando **abajo a la izquierda** y en sentido
   horario: abajo-izquierda → arriba-izquierda → arriba-derecha → abajo-derecha
   (máximo 4 s entre toques; un toque fuera de orden reinicia la secuencia).
5. **Pausa.** Tras el gesto vuelves a la pantalla principal con el botón de pausa. En pausa
   puedes **ver el video completo reconstruido** a partir de los bloques del teléfono,
   reanudar o finalizar la incidencia. Desde *Incidencias* puedes volver a verlas,
   exportarlas y ver el estado de subida de cada bloque.

En Google Drive se crea `Incident Recorder by Leonera/Incidente <fecha>/` con
`bloque-0001_<fecha>.mov`, `bloque-0002_…` y `ubicaciones.csv` (recorrido del incidente).

### Ajustes

| Ajuste | Opciones | Predeterminado |
| --- | --- | --- |
| Fecha y hora en el video (arriba a la izquierda) | `2026-10-16T12:00:00-06:00` | Activado |
| Coordenadas en el video | `19.432608 N, -99.133209 W` (6 decimales) | Activado |
| Precisión | «A unos 10 metros» (`kCLLocationAccuracyNearestTenMeters`) · «La máxima que permita el iPhone» (`kCLLocationAccuracyBest`) | Máxima |
| Frecuencia de coordenadas | 1 s, 5 s, 10 s, 15 s, 30 s, 1 min, 2.5 min, 5 min, 10 min | 1 min |

Batería: 1–10 s mantienen el GPS encendido todo el tiempo (consumo alto); 15–30 s lo apagan
brevemente entre lecturas (medio); desde 1 min el GPS descansa entre lecturas (bajo).
«La máxima» gasta más que «a unos 10 metros». La app lo explica en Ajustes.

### Límites de iOS que conviene conocer

- **La cámara no graba en segundo plano.** Si se sale de la app o se bloquea el teléfono con
  el botón lateral, iOS detiene la cámara: el bloque en curso se cierra y se sube, y al volver
  a la app la grabación continúa (sigue en negro) en un bloque nuevo. Por eso la app desactiva
  el bloqueo automático mientras graba y bloquea las demás apps.
- **Tiempo en pantalla requiere aprobación de Apple para Ad Hoc.** La capacidad
  *Family Controls (Development)* solo vale para builds de desarrollo; para instalar por
  Ad Hoc (o TestFlight/App Store) Apple debe aprobar *Family Controls (Distribution)*, y eso
  no se puede registrar solo con la clave de API. Por eso **viene desactivada**: la app pide el
  permiso solo si el build la incluye (ver [Activar Tiempo en pantalla](#activar-tiempo-en-pantalla)).
  Mientras tanto la pantalla negra funciona dentro de la app, pero las demás apps no se
  bloquean.
- Las apps del sistema que el usuario tenga en «Siempre permitidas» (Teléfono, etc.) no se
  bloquean.

## Secrets y variables de GitHub

Configúralos en **Settings › Secrets and variables › Actions** del repositorio (secrets del
repositorio, no de una organización).

### Firma Ad Hoc (Apple)

| Secret | Contenido |
| --- | --- |
| `ASC_KEY_ID` | Key ID de la clave de API de App Store Connect (Team Key, rol Admin). |
| `ASC_ISSUER_ID` | Issuer ID (Users and Access › Integrations › App Store Connect API). |
| `ASC_KEY_P8` | Contenido completo del archivo `AuthKey_XXXX.p8` (también se acepta en base64). |
| `APPLE_TEAM_ID` | Team ID de la cuenta de Apple Developer. |

- Con los cuatro: el workflow firma Ad Hoc y publica en GitHub Pages.
- Sin ninguno: genera un IPA **sin firmar** (artefacto y release, no instalable).
- Con solo algunos: el build falla indicando cuáles faltan.

### Google Drive

| Nombre | Tipo | Contenido |
| --- | --- | --- |
| `GOOGLE_IOS_CLIENT_ID` | Secret (o variable) | Client ID OAuth de tipo **iOS**, p. ej. `1234567890-abc123.apps.googleusercontent.com`. |

No hace falta *client secret*: los clientes iOS de Google no usan secreto (el flujo usa PKCE
y el redirect `com.googleusercontent.apps.<id>:/oauth2redirect`, que la app calcula a partir
del client ID). Sin `GOOGLE_IOS_CLIENT_ID` la app graba y guarda en el iPhone, pero no puede
conectar Drive.

Cómo obtenerlo:

1. En [Google Cloud Console](https://console.cloud.google.com/) crea (o elige) un proyecto.
2. **APIs y servicios › Biblioteca**: habilita **Google Drive API**.
3. **Google Auth Platform › Branding / Audience** (pantalla de consentimiento OAuth):
   tipo *Externo*, nombre de la app y correo de soporte. En **Data access** agrega los
   alcances `openid`, `.../auth/userinfo.email` y `.../auth/drive.file` (no son sensibles,
   no requieren verificación de Google).
4. En **Audience** pulsa **Publish app** (*En producción*). Si la dejas *En prueba*, agrega tu
   cuenta como usuario de prueba y ten en cuenta que Google caduca la sesión cada 7 días.
5. **Clients › Create client** › tipo **iOS** › Bundle ID
   `com.leonardoramirezr.incidentrecorderbyleonera`. Copia el *Client ID*.
6. Guárdalo en GitHub como secret `GOOGLE_IOS_CLIENT_ID` y haz push.

### Variables opcionales

| Variable | Uso |
| --- | --- |
| `ENABLE_FAMILY_CONTROLS` | `true` para incluir Tiempo en pantalla (ver abajo). |
| `XCODE_VERSION` | Versión de Xcode del runner a usar (p. ej. `26.3`); si no, la predeterminada de `macos-15`. |

### Activar Tiempo en pantalla

1. Pide a Apple la capacidad **Family Controls (Distribution)** en
   <https://developer.apple.com/contact/request/family-controls-distribution> para el App ID
   de la app **y** el de la extensión (`…incidentrecorderbyleonera.ShieldConfiguration`).
2. Cuando la aprueben, crea la variable `ENABLE_FAMILY_CONTROLS` = `true` y haz push.
   XcodeGen agrega entonces el entitlement `com.apple.developer.family-controls` y la
   extensión `ShieldConfiguration`, que pinta de negro la pantalla de las apps bloqueadas.

## Builds, versiones e instalación

El workflow [`.github/workflows/build.yml`](.github/workflows/build.yml) corre en cada push
(salvo a `gh-pages`) y con *workflow_dispatch*, en `macos-15`:

1. Valida la clave con la API de App Store Connect y que haya al menos un iPhone registrado
   (`scripts/asc.py`, solo biblioteca estándar + `openssl` para el JWT ES256).
2. Genera el proyecto con XcodeGen y hace `xcodebuild archive` con firma automática
   (`-allowProvisioningUpdates` y la clave de API): Xcode registra los App IDs y crea los perfiles.
3. Exporta con `method=release-testing` (Ad Hoc, certificado de distribución gestionado en
   la nube) y verifica que cada bundle lleve un `embedded.mobileprovision` Ad Hoc, mostrando
   cuántos dispositivos incluye.
4. Publica en GitHub Pages (`scripts/publish-pages.sh`) y crea la release.
5. Siempre al final revoca el certificado de desarrollo temporal que crea xcodebuild
   (solo los que no estaban antes en el llavero).

Etiquetas:

- **`main`** → `0.x.0` (incrementa el número intermedio respecto a la última etiqueta) y release
  estable *Latest*. Los builds de `main` se encolan, nunca se cancelan.
- **Otras ramas** → `build-<run_number>-<sha7>` y *pre-release*.

La app muestra la etiqueta del build instalado en **Ajustes › Acerca de › Build**.

### GitHub Pages

Después del **primer build firmado** (que crea la rama `gh-pages`), activa
**Settings › Pages › Build and deployment › Source: Deploy from a branch**, rama **`gh-pages`**,
carpeta **`/ (root)`**.

- Portada: `https://leonardoramirezr.github.io/iOS-Incident-Recorder-by-Leonera/` con la lista
  de builds y un botón para la última versión estable.
- Cada build: `…/<etiqueta>/` con el IPA, `manifest.plist`, `index.html` (botón
  `itms-services://…`) y `build.json`.
- Se conservan todas las versiones de `main` y los últimos 20 builds de otras ramas. La rama
  `gh-pages` se reescribe como un único commit para que los IPA no se acumulen en el historial.

El enlace de instalación también aparece en el resumen de cada ejecución de Actions y en las
notas de la release. Ábrelo en **Safari** en el iPhone y pulsa *Instalar* (en iOS 16+ quizá
tengas que activar *Ajustes › Privacidad y seguridad › Modo de desarrollador*).

### Agregar un iPhone

Registra su UDID en [Certificates, Identifiers & Profiles › Devices](https://developer.apple.com/account/resources/devices/list)
y haz push: el siguiente build genera un perfil Ad Hoc que lo incluye.

## Desarrollo local

```bash
brew install xcodegen
scripts/generate-project.sh            # IR_FAMILY_CONTROLS=YES para incluir Tiempo en pantalla
open IncidentRecorder.xcodeproj        # elige tu Team en Signing & Capabilities
```

Para probar Google Drive en local, pasa el client ID como build setting
(`GOOGLE_IOS_CLIENT_ID`) en el esquema o en `project.yml`.

## Estructura

```
project.yml / project-familycontrols.yml   Especificación XcodeGen (identificadores como build settings)
Config/                                    Info.plist y entitlements
IncidentRecorder/
  App/          Entrada, AppDelegate, estado central (AppModel), tareas en segundo plano
  Capture/      Sesión multicámara, composición (PiP + textos) y escritura en bloques
  Location/     Ubicación con ahorro de batería y formatos de hora/coordenadas
  Incidents/    Modelo, almacenamiento local y reconstrucción del video completo
  Drive/        OAuth de Google, API de Drive, cola de subidas reanudables y sesión en segundo plano
  ScreenTime/   Permiso de Tiempo en pantalla y bloqueo de apps
  UI/           Onboarding, cámara, pantalla negra y gesto, incidencias, ajustes
ShieldConfiguration/                       Extensión que pinta de negro las apps bloqueadas
scripts/                                   asc.py, publish-pages.sh, verify-adhoc.sh, …
```
