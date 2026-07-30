#!/usr/bin/env bash
# VisitaCampo — lint anti-bypass de validación TLS (RD-01, ADR-009).
#
# Hallazgo que este script mitiga (CRITICAL, docs/07-hallazgos-revision-codigo.md,
# tabla de hallazgos N-14 / "TLS bypass para self-hosted"): QField (referencia de
# arquitectura) aceptaba certificados inválidos incondicionalmente vía
# `ignoreSslErrors()`. docs/08-arquitectura-propuesta-visitacampo.md lo traduce a
# restricción de diseño RD-01 y a esta regla de CI explícita (ADR-009, línea 530):
#
#   "Prohibido cualquier bypass de validación de certificado. En Dart,
#    badCertificateCallback retorna siempre false salvo que exista un pin
#    aprobado por el usuario para ese host exacto. No existe flag de build,
#    --insecure, ni variable de entorno que lo cambie. Regla de CI: la build
#    falla si aparece badCertificateCallback, allowBadCertificates o similar
#    fuera del módulo TrustStore auditado."
#
# Qué hace este script:
#   Busca, en todo archivo *.dart del repo, los identificadores prohibidos.
#   Si aparece alguno FUERA del módulo TrustStore permitido, falla (exit 1)
#   con un mensaje que cita RD-01/ADR-009 y el archivo/línea exactos.
#
# "0 archivos .dart encontrados" (típico hoy: app/ todavía no tiene código,
# se crea en el Paso 10) es un PASS, no un fallo — igual que "0 archivos que
# lintar no es un fallo" en el resto del pipeline de este paso.
#
# Convención de módulo TrustStore permitido (decisión delegada de este paso,
# documentada aquí porque el brief la deja abierta hasta que el módulo real
# se cree en el Paso 16): se considera "TrustStore auditado" cualquier ruta
# que tenga un segmento de directorio `trust_store` o un archivo llamado
# literalmente `trust_store.dart` (insensible a mayúsculas/minúsculas, para
# tolerar variaciones como `TrustStore/` o `trust_store_io.dart`).
# Ejemplos PERMITIDOS:
#   app/lib/core/trust_store/trust_store.dart
#   app/lib/core/trust_store/http_client_factory.dart
#   app/lib/core/trust_store.dart
# Ejemplos PROHIBIDOS (fuera de TrustStore):
#   app/lib/sync/http_client.dart
#   app/lib/features/auth/login_service.dart
#
# Uso:
#   infra/scripts/lint_no_tls_bypass.sh [directorio...]
#   Sin argumentos, escanea todo el repo desde la raíz.
#
# Exit codes: 0 = OK (sin violaciones, incluido el caso "0 archivos .dart"),
# 1 = se encontró al menos una violación fuera de TrustStore.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

if [ "$#" -gt 0 ]; then
	SEARCH_DIRS=("$@")
else
	SEARCH_DIRS=("$REPO_ROOT")
fi

# Patrones prohibidos (RD-01/ADR-009), insensible a mayúsculas.
FORBIDDEN_PATTERN='badCertificateCallback|allowBadCertificates|ignoreSslErrors|ignoreCertificateErrors'

# Ruta permitida: módulo TrustStore auditado (Paso 16).
ALLOWLIST_PATTERN='(^|/)[Tt][Rr][Uu][Ss][Tt]_?[Ss][Tt][Oo][Rr][Ee]([/.]|$)'

violations_found=0
dart_files_scanned=0

for dir in "${SEARCH_DIRS[@]}"; do
	[ -d "$dir" ] || continue
	while IFS= read -r -d '' file; do
		dart_files_scanned=$((dart_files_scanned + 1))
		matches="$(grep -nE "$FORBIDDEN_PATTERN" "$file" 2>/dev/null || true)"
		[ -z "$matches" ] && continue

		rel="${file#"$REPO_ROOT"/}"
		if printf '%s\n' "$rel" | grep -qE "$ALLOWLIST_PATTERN"; then
			echo "OK (módulo TrustStore auditado, permitido): $rel"
			continue
		fi

		violations_found=1
		echo "" >&2
		echo "VIOLACIÓN RD-01 en $rel:" >&2
		printf '%s\n' "$matches" | sed 's/^/  /' >&2
	done < <(find "$dir" -type f -name '*.dart' -print0 2>/dev/null)
done

if [ "$violations_found" -eq 1 ]; then
	echo "" >&2
	echo "ERROR (RD-01 / ADR-009, docs/08 línea 530): se encontró un posible" >&2
	echo "bypass de validación de certificado TLS fuera del módulo TrustStore" >&2
	echo "auditado (Paso 16)." >&2
	echo "" >&2
	echo "Prohibido: badCertificateCallback / allowBadCertificates /" >&2
	echo "ignoreSslErrors (o equivalentes) fuera de una ruta con segmento" >&2
	echo "'trust_store' o archivo 'trust_store.dart'. El único mecanismo de" >&2
	echo "confianza permitido para hosts self-hosted es el pinning de SPKI con" >&2
	echo "consentimiento explícito del usuario, implementado dentro de ese" >&2
	echo "módulo (ADR-009)." >&2
	echo "" >&2
	echo "No borres este gate como solución a un falso positivo: ajusta el" >&2
	echo "patrón/allow-list de este script en un commit de seguimiento (ver" >&2
	echo "plan, Paso 3, estrategia de rollback)." >&2
	exit 1
fi

echo "OK (RD-01): $dart_files_scanned archivo(s) .dart escaneado(s), sin bypass de TLS fuera de TrustStore."
exit 0
