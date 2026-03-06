default:
    @just --list

# Build the library
build:
    cabal build all

# Clean build artifacts
clean:
    cabal clean

# Run hlint on all source files
lint:
    hlint src/

# Format all source files with ormolu
format:
    ormolu -i src/

# Format only changed Haskell files (staged + unstaged)
format-changed:
    { git diff --name-only --diff-filter=ACMR HEAD -- '*.hs'; git ls-files --others --exclude-standard -- '*.hs'; } | sort -u | xargs -r ormolu -i

# Check formatting without modifying files
format-check:
    ormolu --mode check src/

# Build and then lint
check: build lint format-check

# Start a GHCi REPL with the library loaded
repl:
    cabal repl

# Update cabal package index
update:
    cabal update

# Watch for changes and rebuild (requires ghcid)
watch:
    ghcid --command="cabal repl"
