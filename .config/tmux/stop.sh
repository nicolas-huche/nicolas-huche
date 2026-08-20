#!/bin/zsh

SESSION=$(tmux display-message -p '#S')
PROJECT=$(tmux display-message -p '#{pane_current_path}')

cd "$PROJECT" || exit 1

tmux kill-session -t "$SESSION"
docker compose down
colima stop
