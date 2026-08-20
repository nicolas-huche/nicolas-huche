#!/bin/bash

set -e

if [[ -z "$1" ]]; then
    echo "Usage: $0 <project> [--docker]"
    exit 1
fi

PROJECT_NAME="$1"
SESSION="$PROJECT_NAME"
PROJECT="$HOME/projects/$PROJECT_NAME"

USE_DOCKER=false

if [[ "$2" == "--docker" ]]; then
    USE_DOCKER=true
fi

echo "Checking dependencies..."

# Homebrew
if ! command -v brew >/dev/null 2>&1; then
    echo "Homebrew is not installed."
    echo "Installing Homebrew..."

    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

    echo
    echo "Homebrew installation finished."
    echo "You may need to restart your shell before running this script again."
    exit 0
fi

# Git
if ! command -v git >/dev/null 2>&1; then
    echo "Git is not installed. Installing..."
    brew install git
fi

# GitHub CLI
if ! command -v gh >/dev/null 2>&1; then
    echo "GitHub CLI is not installed. Installing..."
    brew install gh
fi

# tmux
if ! command -v tmux >/dev/null 2>&1; then
    echo "tmux is not installed. Installing..."
    brew install tmux
fi

# Docker dependencies
if [[ "$USE_DOCKER" == true ]]; then

    if ! command -v docker >/dev/null 2>&1; then
        echo "Docker CLI is not installed. Installing..."
        brew install docker
    fi

    if ! docker compose version >/dev/null 2>&1; then
        echo "Docker Compose is not installed. Installing..."
        brew install docker-compose
    fi

    if ! command -v colima >/dev/null 2>&1; then
        echo "Colima is not installed. Installing..."
        brew install colima
    fi
fi

# GitHub authentication
if ! gh auth status >/dev/null 2>&1; then
    echo "GitHub CLI is not authenticated."
    echo "Starting GitHub authentication..."
    gh auth login
fi

# Configure Git to use GitHub CLI authentication
gh auth setup-git

echo "Dependencies are ready."
echo

# Check whether the local project exists
if [[ ! -d "$PROJECT" ]]; then

    # Check whether the GitHub repository already exists
    if gh repo view "$PROJECT_NAME" >/dev/null 2>&1; then
        echo "GitHub repository '$PROJECT_NAME' already exists."
        echo "Cloning repository into:"
        echo "$PROJECT"
        echo

        mkdir -p "$HOME/projects"

        git clone \
            "$(gh repo view "$PROJECT_NAME" --json sshUrl --jq '.sshUrl')" \
            "$PROJECT"

    else
        echo "Project '$PROJECT_NAME' does not exist locally."
        echo "GitHub repository '$PROJECT_NAME' does not exist."
        echo

        read -r -p "Do you want to create it at $PROJECT? [y/N] " CONFIRM

        if [[ ! "$CONFIRM" =~ ^[Yy]$ ]]; then
            echo "Project creation cancelled."
            exit 0
        fi

        echo
        echo "Creating project: $PROJECT_NAME"

        mkdir -p "$PROJECT"

        cat > "$PROJECT/.gitignore" <<EOF
.DS_Store
EOF
        touch "$PROJECT/README.md"

        GIT_NAME="$(git config --global user.name || true)"

        if [[ -z "$GIT_NAME" ]]; then
            GIT_NAME="$(gh api user --jq '.name // .login')"
        fi

        YEAR="$(date +%Y)"

        cat > "$PROJECT/LICENSE" <<EOF
MIT License

Copyright (c) $YEAR $GIT_NAME

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
EOF
    fi
fi

# Initialize local Git repository if necessary
if [[ ! -d "$PROJECT/.git" ]]; then
    echo "Initializing Git repository..."

    git -C "$PROJECT" init
    git -C "$PROJECT" branch -M main
fi

# Check GitHub repository
if gh repo view "$PROJECT_NAME" >/dev/null 2>&1; then
    echo "GitHub repository '$PROJECT_NAME' already exists."

    if ! git -C "$PROJECT" remote get-url origin >/dev/null 2>&1; then
        echo "Adding GitHub repository as origin..."

        GH_URL="$(gh repo view "$PROJECT_NAME" --json sshUrl --jq '.sshUrl')"

        git -C "$PROJECT" remote add origin "$GH_URL"
    fi
else
    echo "GitHub repository '$PROJECT_NAME' does not exist."
    echo "Creating public GitHub repository..."

    gh repo create "$PROJECT_NAME" \
        --public \
        --source="$PROJECT" \
        --remote=origin
fi

# Create initial commit if necessary
if ! git -C "$PROJECT" rev-parse --verify HEAD >/dev/null 2>&1; then
    echo "Creating initial commit..."

    git -C "$PROJECT" add .
    git -C "$PROJECT" commit -m "chore: initialize project"
fi

# Push if the remote is available
if git -C "$PROJECT" remote get-url origin >/dev/null 2>&1; then
    echo "Synchronizing with GitHub..."

    git -C "$PROJECT" push -u origin main
fi

# Prepare Docker files
if [[ "$USE_DOCKER" == true ]]; then

    if [[ ! -f "$PROJECT/compose.yaml" ]]; then
        echo "Creating compose.yaml..."

        cat > "$PROJECT/compose.yaml" <<EOF
services:
  app:
    build:
      context: .
    container_name: $PROJECT_NAME
    working_dir: /workspace
    volumes:
      - .:/workspace
    stdin_open: true
    tty: true
EOF
    fi

    if [[ ! -f "$PROJECT/Dockerfile" ]]; then
        echo "Creating Dockerfile..."

        cat > "$PROJECT/Dockerfile" <<EOF
FROM ubuntu:24.04

WORKDIR /workspace
EOF
    fi

    if [[ ! -f "$PROJECT/.dockerignore" ]]; then
        echo "Creating .dockerignore..."

        cat > "$PROJECT/.dockerignore" <<EOF
.git
.DS_Store
EOF
    fi
fi

# Start Colima if necessary
if [[ "$USE_DOCKER" == true ]]; then
    if ! colima status >/dev/null 2>&1; then
        echo "Starting Colima..."
        colima start
    fi
fi

# Attach to existing tmux session
if tmux has-session -t "$SESSION" 2>/dev/null; then
    tmux attach-session -t "$SESSION"
    exit 0
fi

# Window 1: Nvim
tmux new-session -d \
    -s "$SESSION" \
    -n "nvim" \
    -c "$PROJECT" \
    "nvim ."

tmux move-window \
    -s "$SESSION:0" \
    -t "$SESSION:1"

# Container pane
if [[ "$USE_DOCKER" == true ]]; then
    tmux split-window -v \
        -t "$SESSION:1" \
        -p 20 \
        -c "$PROJECT" \
        "docker compose up -d && docker compose exec app bash"
fi

# Window 2: Git
tmux new-window \
    -t "$SESSION:2" \
    -n "git" \
    -c "$PROJECT" \
    "git status; exec zsh"

tmux select-window \
    -t "$SESSION:1"

tmux select-pane \
    -t "$SESSION:1.0"

tmux attach-session \
    -t "$SESSION"
