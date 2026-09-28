# M14 — Jump-host polish

ProxyJump already ships (M1): the phone SSHs to the jump, opens
`forwardLocal` to the real host, then SSHs to the real host from the
phone. The jump only relays TCP. This milestone is the chain, the
label, and first-connect through a jump.

## Rules

- One `jumpHostId` per host. A chain is A → B → C by setting each
  hop's jump, not a new column.
- Walk at most `kMaxJumpHops` (8). Longer is refused.
- Cycles are refused in the picker and at connect.
- `ssh_config` `ProxyJump a,b` uses **b** as the immediate jump
  (OpenSSH last hop). Newly imported hop hosts with no jump yet get
  the previous hop. Existing hosts are not rewritten.
- Host list, dashboard, details, edit, and enrollment show
  `via` outermost-first (`via bastion · inner`).
- Add host can pick a jump so Test connection / password install
  already traverse the hop.
- No userspace WireGuard. No `VpnService`. Docs: a jump host or an
  OS tunnel is the NAT answer.

## Out of scope

M8 T2 (embedded WireGuard). M9 PTY. Agent on the jump hop (M22).
