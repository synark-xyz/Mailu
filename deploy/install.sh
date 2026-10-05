#!/usr/bin/env bash
# Kept for convenience: production install. See deploy.sh --help for more options.
exec "$(dirname "$0")/deploy.sh" --prod up "$@"
