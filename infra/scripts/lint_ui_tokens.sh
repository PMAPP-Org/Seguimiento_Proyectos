#!/usr/bin/env bash
# Gate del sistema de diseño de la app (mobile.yml, ci_local.sh).
#
# Las pantallas no escriben estilos ni textos sueltos: colores, tipografía,
# espaciados y textos salen del tema (`app/lib/ui/theme/`) y de los .arb
# (`app/lib/l10n/`). Sin este gate, el sistema de diseño se erosiona pantalla
# a pantalla hasta que cambiar un color o un texto exige buscarlo por todo el
# código. Mismo enfoque que el lint RD-01 (`lint_no_tls_bypass.sh`).
#
# Reglas:
#   1. Colores literales (`Color(0x…)`, `Colors.…`) solo en
#      app/lib/ui/theme/app_colors.dart.
#   2. En app/lib/features/ (pantallas):
#      - sin `TextStyle(` ni `fontSize:` → `Theme.of(context).textTheme`;
#      - sin números en `EdgeInsets…(…)` ni en `SizedBox(height|width: …)`
#        → `AppSpacing` / `AppGap` / `AppSizes`;
#      - sin textos literales en `Text('…')`, `labelText:`, `hintText:`,
#        `tooltip:` → `context.l10n.…` (app/lib/l10n/app_es.arb).
#
# Uso: bash infra/scripts/lint_ui_tokens.sh   (sale con 1 si hay violaciones)
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
cd "$REPO_ROOT" || exit 1

LIB=app/lib
FEATURES=app/lib/features
COLORS_FILE=app/lib/ui/theme/app_colors.dart

violations=0

report() { # $1 = regla, $2 = salida de grep -n
	if [ -n "$2" ]; then
		echo "✗ $1"
		while IFS= read -r line; do echo "    $line"; done <<< "$2"
		violations=$((violations + $(echo "$2" | wc -l)))
	fi
}

# Se ignoran las líneas de comentario (`//`) para que la documentación pueda
# citar ejemplos.
scan() { # $1 = patrón ERE, $2… = rutas
	local pattern="$1"
	shift
	grep -rnE --include='*.dart' "$pattern" "$@" 2>/dev/null | grep -vE '^[^:]+:[0-9]+:\s*//' || true
}

colors="$(scan '(^|[^A-Za-z0-9_])(Color\(0x|Colors\.[a-zA-Z])' "$LIB" | grep -v "^${COLORS_FILE}:" || true)"
report "Color literal fuera de ${COLORS_FILE} (usa Theme.of(context).colorScheme o context.statusColors)" "$colors"

report "Estilo de texto suelto en una pantalla (usa Theme.of(context).textTheme)" \
	"$(scan 'TextStyle\(|fontSize:' "$FEATURES")"

report "Medida numérica en una pantalla (usa AppSpacing / AppGap / AppSizes)" \
	"$(scan 'EdgeInsets\.[a-zA-Z]+\([^)]*[0-9]|SizedBox(\.square)?\((height|width|dimension): *[0-9]' "$FEATURES")"

report "Texto literal en una pantalla (añádelo a app/lib/l10n/app_es.arb y usa context.l10n)" \
	"$(scan "Text\(\s*['\"]|(labelText|hintText|helperText|tooltip): *['\"]" "$FEATURES")"

dart_files="$(find "$LIB" -name '*.dart' | wc -l)"
if [ "$violations" -gt 0 ]; then
	echo ""
	echo "FALLO: ${violations} violación(es) del sistema de diseño en ${dart_files} archivo(s) .dart."
	exit 1
fi
echo "OK (sistema de diseño): ${dart_files} archivo(s) .dart sin colores, estilos, medidas ni textos sueltos."
