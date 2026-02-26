# Part 1: Aperture and the Tagged-Device Identity Gap

*Figuring out why half our tailnet couldn't talk to our AI gateway.*

---

## Setting the scene

We run a small fleet of AI agents on Kubernetes.  Three agents (IronClaw, PicoClaw, HexStrike) make LLM calls to Anthropic's API.  We wanted to route those calls through [Tailscale Aperture](https://tailscale.com/aperture) — their AI gateway — so we'd get identity-aware metering, usage dashboards, and a single place to manage API keys.

The setup looked straightforward:

```mermaid
graph LR
    Agent["K8s Agent Pod"] --> Egress["Egress Proxy<br/><small>ExternalName Service</small>"]
    Egress --> AI["Aperture<br/><small>ai.ts.net</small>"]
    AI --> Anthropic["api.anthropic.com"]

    style AI fill:#4a9,stroke:#2a7,color:white
```

The Tailscale Operator creates an egress proxy as a K8s Service.  Agents set `ANTHROPIC_BASE_URL` to the in-cluster service.  Traffic tunnels through the tailnet to Aperture.  Aperture adds the real API key and forwards to Anthropic.

We had the ACL rules in place (managed with [Dhall](https://dhall-lang.org), naturally):

```dhall
-- fragments/aperture.dhall
let acls = [
  { action = "accept"
  , src = [ C.tag.dev, C.tag.k8s, C.tag.k8s_operator, ... ]
  , dst = [ "ai:*" ]
  }
]
```

Network connectivity: check.  We could ping Aperture, we could see it respond.

But every request came back **403 Forbidden**: `"access denied: no role granted"`.

## Two layers of auth

It took us a while to realize Aperture has **two separate auth layers**, and we were only solving one.

### Layer 1: Tailnet ACL (network)

This controls which devices can open TCP connections to Aperture.  It's the standard Tailscale ACL — `src` tags, `dst` hosts, port wildcards.  We had this right.  Our Dhall config compiled to the correct policy.  Connections succeeded.

### Layer 2: Aperture's internal roles (application)

This is where it got interesting.  Aperture uses Tailscale's WhoIs API to identify *who* is connecting.  Then it checks its own `temp_grants` config — a separate JSON structure managed through Aperture's web UI or config API — to decide what that identity can do.

These are **not** tailnet grants.  There's no `tailscale.com/cap/aperture` capability domain (unlike Setec's `tailscale.com/cap/secrets` or the K8s Operator's `tailscale.com/cap/kubernetes`).  Aperture manages its own authorization independently.

Our config looked fine:

```json
{
  "temp_grants": [
    {
      "src": ["jess@sulliwood.org", "jsullivan2@gmail.com", "tagged-devices"],
      "grants": [{"role": "admin"}]
    },
    {
      "src": ["tagged-devices"],
      "grants": [{"role": "user"}, {"providers": [...]}]
    }
  ]
}
```

Admin access for our user accounts and `"tagged-devices"`.  User + model access for `"tagged-devices"`.  Should work, right?

## The identity gap

Here's what we missed.  When Aperture does a WhoIs lookup on a connection from a **tagged device**, it sees something like:

```
Machine:
  Name: yoga.example.ts.net
  Tags: tag:dev, tag:dollhouse, tag:qa, ...

(no User field)
```

There's no `User.LoginName`.  Tagged devices aren't owned by a user — they're owned by the tailnet itself.  The string `"tagged-devices"` that shows up in `tailscale status` is a **display label**, not an identity field that Aperture matches on.

Similarly, `"tag:dev"` as a string in `temp_grants.src` doesn't match anything.  Aperture's identity matching only recognizes:

| Pattern | Matches |
|---------|---------|
| `"jess@example.com"` | User-owned devices with that login |
| `"*"` | Everything |
| `"tagged-devices"` | Nothing (it's not a real identity) |
| `"tag:dev"` | Nothing (Aperture doesn't check tags) |

So our entire fleet of tagged K8s workloads — every agent, every operator proxy — was invisible to Aperture's role system.

## The chicken and the egg

This created a fun bootstrapping problem:

1. We need to update Aperture's config to use `"*"` (wildcard) instead of `"tagged-devices"`
2. Aperture's config API (`PUT /api/config`) requires an admin role
3. We don't have an admin role because the config is wrong
4. The web UI (`http://ai/ui`) also requires a role

We couldn't even fix the config because the broken config prevented us from accessing the API.

Every active device on our tailnet was tagged.  The only user-owned devices (phones, old laptops) were offline.  We were locked out of our own AI gateway.

The solution turned out to be surprisingly elegant.  But that's [Part 2](part-2-bootstrap.md).

---

## Key takeaways

- Aperture's auth is **not** part of the tailnet grants system — it's a separate internal config
- `"tagged-devices"` is a display label, not a matchable identity
- Tag strings like `"tag:dev"` don't work in Aperture's `temp_grants.src`
- Only user emails and `"*"` wildcard are recognized
- Network ACLs and Aperture roles are independent — passing one doesn't mean passing the other
- If all your devices are tagged, you need a user-owned device to bootstrap Aperture

*[Continue to Part 2: Bootstrapping Aperture config with tsnet](part-2-bootstrap.md)*
