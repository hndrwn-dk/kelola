# M9 — Terminal escape hatch (PTY)

Command sheet stays one-shot SSH exec (`TERM=dumb`). This milestone
adds a real PTY so `vim`, `top`, and `less` work. It is an escape
hatch, not the home screen.

## Rules

- Full-screen Terminal. Command sheet is retitled Command.
- dartssh2 `shell` + `xterm-256color`. Dedicated client, not the
  exec pool.
- Resize sends `SIGWINCH` (`resizeTerminal`) when the view or
  keyboard changes.
- Audit open and close only. Title `Opened terminal` /
  `Closed terminal`. Command is `ssh-pty`, never keystrokes.
- Risk is mutate. Read-only hosts refuse. Never `ProbeScope.fleet`.
- Accessory row: Tab, Esc, Ctrl (sticky), arrows, `|`, `/`, `-`, `~`.
- Keep-awake while the Terminal screen is open. App pause does not
  close the session; leaving the screen does.
- One PTY per host. No `kubectl exec -it`. No session recording.
