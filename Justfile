set shell := ["bash", "-euo", "pipefail", "-c"]

# Never open a pager for git output (e.g. the commit lists in `next`/`release`).
export GIT_PAGER := "cat"
export PAGER := "cat"

# List recipes
default:
    @just --list

# Syntax-check all Lua files
check:
    for f in *.lua Modules/*.lua tests/*.lua tools/*.lua; do luac -p "$f"; done

# Run the tests (each file in a fresh stand-in client, see tests/run.lua). LuaJIT runs
# Lua 5.1 like the game; plain lua (5.4) is stricter in places (e.g. %d with decimals).
test: check
    #!/usr/bin/env bash
    set -uo pipefail
    runner=$(command -v luajit || command -v lua)
    status=0
    for f in tests/*_test.lua; do "$runner" tests/run.lua "$f" || status=1; done
    exit $status

# Show the version the next release would get, and the commits going into it
next:
    #!/usr/bin/env bash
    set -euo pipefail
    echo "Next version: $(cog bump --auto --dry-run 2>/dev/null)"
    last="$(git describe --tags --abbrev=0 2>/dev/null || true)"
    git log --oneline ${last:+"$last"..HEAD}
    echo
    just changelog-check || true

# Fails if there are feat/fix commits since the last release but nothing under Unreleased in Changelog.lua
changelog-check:
    #!/usr/bin/env bash
    set -euo pipefail
    runner=$(command -v luajit || command -v lua)
    last="$(git describe --tags --abbrev=0 2>/dev/null || true)"
    changes=$(git log --format=%s ${last:+"$last"..HEAD} | grep -cE '^(feat|fix)(\(.+\))?!?:' || true)
    entries=$("$runner" tools/changelog.lua count)
    if [ "$changes" -gt 0 ] && [ "$entries" -eq 0 ]; then
        echo "$changes feat/fix commits since ${last:-the start}, but nothing under Unreleased in Changelog.lua."
        echo "Add what players will notice (see the top of Changelog.lua)."
        exit 1
    fi
    echo "Changelog: $entries entries under Unreleased."

# Release: pick the next version from conventional commits, tag it and push (CI publishes to CurseForge)
release: test changelog-check (_release "")

# Pre-release, e.g. `just release-pre alpha.1` or `just release-pre beta.1` (CurseForge alpha/beta file)
release-pre pre: test changelog-check (_release pre)

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

    # Release notes (CurseForge, GitHub) come from Changelog.lua: a release turns the
    # Unreleased block into this version; a pre-release keeps it Unreleased.
    runner=$(command -v luajit || command -v lua)
    if [ -z "{{pre}}" ]; then
        "$runner" tools/changelog.lua release "${version#v}" "$(date +%F)"
        "$runner" tools/changelog.lua markdown "${version#v}" > CHANGELOG.md
    else
        "$runner" tools/changelog.lua markdown Unreleased > CHANGELOG.md
    fi
    git add Changelog.lua CHANGELOG.md
    git commit -m "chore(release): $version"
    git push origin main

    cog bump --version "${version#v}" --annotated "$version"
    git push origin "$version"
    echo "Pushed $version. Follow the release at: https://github.com/repsejnworb/NraKit/actions"
