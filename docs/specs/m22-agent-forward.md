# M22 — Agent forwarding

Free. Per-host toggle, default off. The phone offers the
StrongBox/Keystore identity over OpenSSH agent forwarding so a hop
from that host can sign without the private key leaving the device.

## Rules

- Private key never leaves StrongBox. The agent lists one identity
  and signs through `HardwareSshIdentity`.
- Default off. Enabling is a trust grant: that host may request
  signatures. Confirm when turning on.
- dartssh2 already requests `auth-agent-req@openssh.com` when
  `SSHClient.agentHandler` is set. Attach the handler only when the
  host toggle is on, and never on password bootstrap.
- ProxyJump TCP relay does not request agent forwarding. The jump
  host only gets an agent if the user opened that jump as the
  destination with the toggle on.
- sshd must allow `AllowAgentForwarding`. A refused request fails
  the command with the existing channel-request error — do not
  silently retry without the agent.
- Vault packs `agentForward` on the host record without bumping
  `vaultSchemaVersion`.
