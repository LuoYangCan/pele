# Commit message style

- Conventional commits: `type(scope): description`
- One line, short, saying only "what was done". Reason / background / motivation belong in the PR description
- Most of the time a single `git commit -m "..."` line does it; use a HEREDOC only when adding a Co-Authored-By trailer

## The Co-Authored-By trailer depends on the repo

Before every commit, look at the owner in `git remote get-url origin`:

- **Personal / public work repo** (under your own GitHub username, an open-source harness, a personal side project) → **add the trailer**
- **Company / team repo** (under a company organization, closed-source projects, multi-person private repos) → **do not add it**
- **Unsure / no origin / unclear fork relationship** → **do not add it** (conservative default)

## How to write it

With the trailer:

```bash
git commit -m "$(cat <<'EOF'
feat(scope): description

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>
EOF
)"
```

There must be a blank line before the trailer (the Git trailer standard).

Without the trailer:

```bash
git commit -m "feat(scope): description"
```

## Do not backfill existing commits

Forward-looking only. Do **not** rewrite history to add the trailer to commits that are already pushed.
