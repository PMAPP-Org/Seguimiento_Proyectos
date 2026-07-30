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
# Convención de módulo TrustStore permitido: doc de plan (Paso 16, tarea 1,
# plans/visitacampo-construccion.md línea 612) fija la ruta canónica exacta:
# "Crear el módulo app/lib/core/security/trust_store.dart — único módulo
# exento del lint anti-badCertificateCallback de Paso 3". El allow-list está
# anclado (con `^`) a ese prefijo exacto desde la raíz del repo, no a un
# nombre de segmento que pueda repetirse en cualquier profundidad del árbol
# (una ruta como `app/lib/features/auth/trust_store/x.dart` NO cuenta como
# TrustStore auditado: no cuelga de `core/security/`, así que sigue
# prohibida). Insensible a mayúsculas/minúsculas solo en el propio segmento
# `trust_store`/`TrustStore`, para tolerar variaciones de casing del nombre
# del módulo si Paso 16 lo divide en varios archivos dentro de un directorio.
# Ejemplos PERMITIDOS:
#   app/lib/core/security/trust_store.dart
#   app/lib/core/security/trust_store/http_client_factory.dart
# Ejemplos PROHIBIDOS (fuera del prefijo canónico, aunque el segmento se
# llame igual):
#   app/lib/sync/http_client.dart
#   app/lib/features/auth/login_service.dart
#   app/lib/features/auth/trust_store/sneaky.dart   <- decoy, NO es el módulo
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

# Ruta permitida: módulo TrustStore auditado (Paso 16), anclada al prefijo
# canónico exacto app/lib/core/security/trust_store — NO un nombre de
# segmento que pueda coincidir en cualquier parte del árbol (eso era el
# hallazgo de revisión: un directorio decoy `.../trust_store/` fuera de
# `core/security/` quedaba permitido). `^` ancla al inicio de la ruta
# relativa al repo; solo se permite el archivo `trust_store.dart` o
# cualquier ruta bajo el directorio `trust_store/` inmediatamente dentro de
# `app/lib/core/security/`.
ALLOWLIST_PATTERN='^app/lib/core/security/[Tt][Rr][Uu][Ss][Tt]_?[Ss][Tt][Oo][Rr][Ee](\.dart$|/)'

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
	echo "ignoreSslErrors (o equivalentes) fuera de" >&2
	echo "app/lib/core/security/trust_store.dart (o app/lib/core/security/" >&2
	echo "trust_store/**), el único módulo TrustStore auditado. Un directorio" >&2
	echo "u archivo llamado 'trust_store' en cualquier otra ruta NO cuenta" >&2
	echo "como excepción. El único mecanismo de" >&2
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
