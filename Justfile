set shell := ["bash", "-euo", "pipefail", "-c"]

# List recipes
default:
    @just --list

# Syntax-check all Lua files
check:
    for f in *.lua Modules/*.lua; do luac -p "$f"; done

# Show the version the next release would get, and the commits going into it
next:
    #!/usr/bin/env bash
    set -euo pipefail
    echo "Next version: $(cog bump --auto --dry-run 2>/dev/null)"
    last="$(git describe --tags --abbrev=0 2>/dev/null || true)"
    git log --oneline ${last:+"$last"..HEAD}

# Release: pick the next version from conventional commits, tag it and push (CI publishes to CurseForge)
release: check (_release "")

# Pre-release, e.g. `just release-pre alpha.1` or `just release-pre beta.1` (CurseForge alpha/beta file)
release-pre pre: check (_release pre)

_release pre:
    #!/usr/bin/env bash
    set -euo pipefail
    [ "$(git rev-parse --abbrev-ref HEAD)" = main ] || { echo "Releases are made from main"; exit 1; }
    [ -z "$(git status --porcelain)" ] || { echo "Working tree is not clean"; exit 1; }
    git fetch --quiet origin main --tags
    [ "$(git rev-parse HEAD)" = "$(git rev-parse origin/main)" ] || git push origin main

    pre_args=()
    [ -n "{{pre}}" ] && pre_args=(--pre "{{pre}}")
    version="$(cog bump --auto "${pre_args[@]}" --dry-run 2>/dev/null)"
    echo "Releasing $version"
    git log --oneline "$(git describe --tags --abbrev=0 2>/dev/null || git rev-list --max-parents=0 HEAD)"..HEAD
    read -rp "Tag and push $version? [y/N] " answer
    [ "$answer" = y ] || { echo "Aborted"; exit 1; }

    cog bump --version "${version#v}" --annotated "$version"
    git push origin "$version"
    echo "Pushed $version. Follow the release at: https://github.com/repsejnworb/NraKit/actions"
