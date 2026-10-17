# CLAUDE.md

## Reglas

- Cada vez que termines una tarea y escribas el resumen de los cambios implementados, incluye
  el nombre del build que contiene esos cambios, por ejemplo `build-30-1bca82e`
  (en `main` la etiqueta es `0.x.0`). Es la etiqueta que genera
  `.github/workflows/build.yml`: `build-<run_number>-<sha7>` en ramas y `0.x.0` en `main`.

## Proyecto

- App iOS en SwiftUI, sin dependencias de terceros. iOS 17+, Swift 5 (modo de lenguaje).
- El proyecto Xcode se genera con XcodeGen (`project.yml`; `scripts/generate-project.sh`) y no
  se versiona. Los identificadores se pasan como build settings (`APP_BUNDLE_ID`,
  `GOOGLE_IOS_CLIENT_ID`, `IR_BUILD_TAG`, `MARKETING_VERSION`, `CURRENT_PROJECT_VERSION`).
- Family Controls (Tiempo en pantalla) solo se incluye con `IR_FAMILY_CONTROLS=YES`
  (variable de repositorio `ENABLE_FAMILY_CONTROLS=true`), porque Ad Hoc requiere que Apple
  apruebe la capacidad. No agregar App Groups ni capacidades que Xcode no pueda registrar
  solo con la clave de API.
- No hay toolchain de Xcode fuera de CI: la compilación real ocurre en el workflow
  (`macos-15`). Revisa los logs del job si falla.
- Textos de la interfaz en español.
