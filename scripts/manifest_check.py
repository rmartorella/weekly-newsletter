#!/usr/bin/env python3
"""Offline structural check of the k8s manifests.

Parses every document and asserts apiVersion, kind and metadata.name are present,
and that namespaced objects target the expected namespace. This is a syntax and
shape check, not schema validation -- CRDs like BackendConfig cannot be
schema-checked without a cluster.

The __IMAGE__ placeholder is expected in the source tree and only treated as an
error when REQUIRE_SUBSTITUTED=1, which the deploy pipeline sets after rendering.

Usage: manifest_check.py <dir> [expected-namespace]
"""

import os
import pathlib
import sys

import yaml

CLUSTER_SCOPED = {"Namespace"}


def main() -> int:
    if not 2 <= len(sys.argv) <= 3:
        sys.stderr.write(f"usage: {sys.argv[0]} <dir> [expected-namespace]\n")
        return 2

    root = pathlib.Path(sys.argv[1])
    want_ns = sys.argv[2] if len(sys.argv) == 3 else None

    files = sorted(root.glob("*.yaml"))
    if not files:
        sys.stderr.write(f"error: no yaml under {root}\n")
        return 1

    errors = []
    count = 0

    for path in files:
        text = path.read_text(encoding="utf-8")
        if "__IMAGE__" in text:
            if os.environ.get("REQUIRE_SUBSTITUTED") == "1":
                errors.append(f"{path.name}: unsubstituted __IMAGE__ placeholder")
            else:
                print(f"  --  {path.name:34} carries __IMAGE__ placeholder")
        try:
            docs = list(yaml.safe_load_all(text))
        except yaml.YAMLError as exc:
            errors.append(f"{path.name}: unparseable: {exc}")
            continue

        for i, doc in enumerate(docs):
            if doc is None:
                continue
            count += 1
            where = f"{path.name}[{i}]"
            for field in ("apiVersion", "kind"):
                if not doc.get(field):
                    errors.append(f"{where}: missing {field}")
            kind = doc.get("kind", "?")
            name = (doc.get("metadata") or {}).get("name")
            if not name:
                errors.append(f"{where}: missing metadata.name")
            ns = (doc.get("metadata") or {}).get("namespace")
            if kind not in CLUSTER_SCOPED:
                if not ns:
                    errors.append(f"{where}: {kind}/{name} has no namespace")
                elif want_ns and ns != want_ns:
                    errors.append(f"{where}: {kind}/{name} namespace {ns} != {want_ns}")
            print(f"  ok  {where:34} {kind}/{name}")

    print(f"{count} document(s) in {len(files)} file(s)")
    if errors:
        sys.stderr.write("\n")
        for e in errors:
            sys.stderr.write(f"FAIL: {e}\n")
        return 1
    print("manifest checks passed")
    return 0


if __name__ == "__main__":
    sys.exit(main())
