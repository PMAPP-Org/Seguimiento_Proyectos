"""Gate de cobertura de líneas sobre un `lcov.info` (`flutter test --coverage`).

Excluye el código generado (`*.g.dart`, `*.freezed.dart` de build_runner y
`app_localizations*.dart` de gen-l10n): no lo escribe nadie a mano y contaría a
favor o en contra sin significar nada.

Uso: python infra/scripts/check_lcov.py app/coverage/lcov.info --min 80
"""

from __future__ import annotations

import argparse
import sys
from pathlib import Path

GENERATED_SUFFIXES = (".g.dart", ".freezed.dart")


def _is_generated(path: str) -> bool:
    name = path.replace("\\", "/").rsplit("/", 1)[-1]
    return name.endswith(GENERATED_SUFFIXES) or name.startswith("app_localizations")


def coverage(lcov: Path) -> tuple[int, int]:
    found = hit = 0
    current: str | None = None
    for line in lcov.read_text(encoding="utf-8").splitlines():
        if line.startswith("SF:"):
            current = line[3:]
        elif line.startswith("DA:") and current and not _is_generated(current):
            _, count = line[3:].split(",")[:2]
            found += 1
            hit += int(count) > 0
    return hit, found


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("lcov", type=Path)
    parser.add_argument("--min", type=float, required=True, help="porcentaje mínimo de líneas")
    args = parser.parse_args()

    hit, found = coverage(args.lcov)
    if found == 0:
        print("lcov sin líneas instrumentadas: ¿corrió `flutter test --coverage`?")
        return 1
    pct = 100 * hit / found
    print(f"Cobertura de líneas (sin código generado): {pct:.1f}% ({hit}/{found})")
    if pct < args.min:
        print(f"Por debajo del mínimo {args.min:.1f}%")
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
