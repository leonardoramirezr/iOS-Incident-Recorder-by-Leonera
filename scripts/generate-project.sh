#!/usr/bin/env bash
# Genera IncidentRecorder.xcodeproj con XcodeGen (brew install xcodegen).
# IR_FAMILY_CONTROLS=YES añade la capacidad Family Controls y la extensión de
# pantalla negra (requiere que Apple haya aprobado la capacidad, ver README).
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."
export IR_FAMILY_CONTROLS="${IR_FAMILY_CONTROLS:-NO}"
xcodegen generate --spec project.yml
echo "Proyecto generado (Family Controls: $IR_FAMILY_CONTROLS). Ábrelo con: open IncidentRecorder.xcodeproj"
