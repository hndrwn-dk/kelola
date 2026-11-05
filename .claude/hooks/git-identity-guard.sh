#!/usr/bin/env bash
# Claude Code PreToolUse hook (Bash). Blocks `git commit` / `git push` that
# would publish work under Claude's identity or with Claude trailers.
# Commits must be authored and committed by the repo owner, with no
# "Co-Authored-By: Claude" or "Claude-Session:" lines.
set -u

cmd=$(jq -r '.tool_input.command // ""' 2>/dev/null)
case "$cmd" in
  *"git commit"*|*"git push"*|*"git merge"*|*"git rebase"*|*"git cherry-pick"*|*"git am"*) ;;
  *) exit 0 ;;
esac

deny() {
  jq -n --arg r "$1" '{hookSpecificOutput: {hookEventName: "PreToolUse",
    permissionDecision: "deny", permissionDecisionReason: $r}}'
  exit 0
}

is_claude() { grep -qiE 'noreply@anthropic\.com|(^|[^a-z])claude([^a-z]|$)'; }
trailer_re='^(Co-Authored-By:.*(Claude|anthropic)|Claude-Session:)'

# 1. Identity git would use for a new commit.
for who in GIT_AUTHOR_IDENT GIT_COMMITTER_IDENT; do
  ident=$(git var "$who" 2>/dev/null | sed 's/ [0-9]* [+-][0-9]*$//')
  if [ -z "$ident" ] || printf '%s' "$ident" | is_claude; then
    deny "Git identity is '${ident:-unset}' ($who). Commits must use the repo owner's name and email. Set: git config user.name / user.email to the owner, then retry."
  fi
done

# 2. Claude trailers typed into a commit command's message (-m / -F heredoc).
#    Only for commands that run `git commit`; a push or a grep that merely
#    mentions the words is not a commit message.
case "$cmd" in
  *"git commit"*)
    if printf '%s\n' "$cmd" | grep -qiE 'Co-Authored-By:.*(Claude|anthropic)|Claude-Session:'; then
      deny "Commit message contains a Claude trailer (Co-Authored-By: Claude / Claude-Session). Remove it; commits carry no Claude attribution."
    fi
    ;;
esac

# 3. On push: no local commit not yet on a remote may be Claude's.
case "$cmd" in
  *"git push"*)
    bad=$(git log --branches --not --remotes --format='%h %an <%ae> | %cn <%ce>%n%B%x00' 2>/dev/null \
      | tr '\0' '\n' | grep -iE 'noreply@anthropic\.com|<[^>]*> \| Claude <|^[0-9a-f]+ Claude <|'"$trailer_re" | head -3)
    if [ -n "$bad" ]; then
      deny "Unpushed commits carry Claude authorship or trailers: $(printf '%s' "$bad" | tr '\n' ' ') Rewrite them to the owner's identity and drop the trailers before pushing."
    fi
    ;;
esac
exit 0
