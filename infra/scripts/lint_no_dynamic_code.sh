#!/usr/bin/env bash
# Gate RD-06 / ADR-012 en la app (mobile.yml, ci_local.sh): **una plantilla de
# formulario es dato, nunca código** (corrección de H-06).
#
# El renderer (app/lib/core/forms/, app/lib/ui/forms/) interpreta la plantilla
# con un árbol de clases selladas y un `switch` exhaustivo. Este lint impide
# que se cuele por la puerta de atrás un mecanismo que convierta texto o
# nombres de la plantilla en llamadas:
#
#   - `dart:mirrors` (reflexión: invocar por nombre);
#   - `Function.apply` (llamar a una función elegida en tiempo de ejecución);
#   - `noSuchMethod` (despacho dinámico de miembros que no existen);
#   - `Isolate.spawnUri` (cargar y ejecutar código desde una URI);
#   - `dart:js_interop` / `dart:js_util` / `package:js` y `evalJavascript` /
#     `runJavaScript` (evaluar JavaScript).
#
# En toda app/lib/: ninguna parte de la app tiene motivo para usarlos, y una
# allow-list por archivo invitaría a "solo esta vez". Mismo enfoque que
# lint_no_tls_bypass.sh. El servidor tiene su equivalente por AST en
# server/visitacampo/forms/tests/ (Paso 20).
#
# Uso: bash infra/scripts/lint_no_dynamic_code.sh   (sale con 1 si hay violaciones)
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
cd "$REPO_ROOT" || exit 1

PATTERN="dart:mirrors|Function\.apply|noSuchMethod|spawnUri|dart:js_interop|dart:js_util|package:js/|evalJavascript|runJavaScript"

# Se ignoran las líneas de comentario para que la documentación pueda nombrarlos.
hits="$(grep -rnE --include='*.dart' "$PATTERN" app/lib 2>/dev/null | grep -vE '^[^:]+:[0-9]+:\s*//' || true)"

files="$(find app/lib -name '*.dart' | wc -l)"
if [ -n "$hits" ]; then
	echo "✗ Ejecución dinámica de código en app/lib (RD-06, ADR-012: la plantilla es dato, nunca código):"
	while IFS= read -r line; do echo "    $line"; done <<< "$hits"
	exit 1
fi
echo "OK: ${files} archivos .dart sin mecanismos de ejecución dinámica (RD-06)."
