#!/bin/bash
# Tells the notch pet what Claude Code is doing.
#
# Usage: claude-pet-hook.sh <working|waiting|done|idle> [detail]
#
# Claude Code sends hook JSON on stdin; we don't need it, but we read and discard it
# so nothing is left unread in the pipe. Everything here is best-effort: if the notch
# app isn't running, curl gives up after a second and we still exit 0, so a missing
# pet can never interfere with a Claude Code session.

STATE="${1:-idle}"
DETAIL="${2:-}"
PORT=51748

cat >/dev/null 2>&1

curl --silent --max-time 1 --output /dev/null \
     --data "{\"state\":\"${STATE}\",\"detail\":\"${DETAIL}\"}" \
     "http://127.0.0.1:${PORT}/" 2>/dev/null

exit 0
