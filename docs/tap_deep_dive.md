---

AI agents have an identity crisis.

Not the existential kind. The structural kind — where the same agent exists as three different entities on three different chains and no on-chain mechanism can prove they are the same.

ERC-8004 gave AI agents on-chain identity. Over 200,000 agents are now registered across 23+ chains, up from 337 in January 2026. That is 39,000% growth in four months. But every one of those identities is chain-local. An agent registered on Ethereum gets one `agentId`. The same agent on Base gets a different one. On BSC, another. And the 194,000+ reputation feedbacks submitted on-chain? All locked to individual chains. An agent with 50 positive feedbacks on Ethereum has zero reputation on Base.

This is not a theoretical gap.

Every major AI agent platform — Virtuals, ElizaOS, Olas, [Fetch.ai](http://Fetch.ai), SingularityNET, NEAR, Bittensor — operates on multiple chains. None of them solve cross-chain agent identity. The Ethereum Magicians discussion thread for ERC-8004 (21 comments, Aug 2025) contains zero mentions of cross-chain identity federation. The gap is not debated. It is invisible.

**Trustless Agents Plus (TAP)** is an additive layer built on top of ERC-8004 that fixes this. Two contracts on a settlement chain. No modifications to per-chain registries. One canonical identity and one aggregated reputation score for every agent, across every chain it operates on.

Let’s break down how it works.

---

## TAP in Under 100 Words

TAP deploys two upgradeable contracts on Push Chain. **TAPRegistry** gives each agent a single canonical identity anchored to a Universal Executor Account (UEA). Per-chain ERC-8004 registrations link to this identity via EIP-712 signed bindings — cryptographic proofs that the same key controls both identities. Identity tokens are soulbound and non-transferable. **TAPReputationRegistry** collects per-chain reputation snapshots from authorized reporters, normalizes the data, and computes a single 0–10,000 basis point score that factors quality, volume, chain diversity, and slashing history. Per-chain registries stay unchanged.

That’s 94 words. Count them.

---

## Component 1: TAPRegistry — The Canonical Identity Layer

The mental model is straightforward.

ERC-8004 gives every chain its own identity registry — an independent ERC-721 with its own incrementing counter. TAPRegistry sits above these per-chain registries as the **cross-chain unification layer**. It does not replace them. It connects them.

```
                     Push Chain
                +-----------------+
                |  TAPRegistry    |
                | (canonical ID)  |
                +--------+--------+
                         |
              bindings   |   bindings
       +-----------------+-----------------+
       |                 |                 |
+------+------+   +------+------+   +------+------+
| Ethereum    |   | Base        |   | Arbitrum    |
| ERC-8004    |   | ERC-8004    |   | ERC-8004    |
| IdentityReg |   | IdentityReg |   | IdentityReg |
+-------------+   +-------------+   +-------------+
```

### Registration

An agent registers once on Push Chain from its UEA. The UEA factory — a predeploy on Push Chain — already records the agent’s origin chain, chain ID, and owner key. This is the anchor.

The `agentId` is deterministic: `uint256(uint160(ueaAddress)) % 10_000_000`. A 7-digit number derived directly from the address. No incrementing counter. No external mapping. If two addresses ever truncate to the same value (a collision), the transaction reverts.

Registration takes a metadata URI (typically an IPFS CID pointing to the agent's card) and a keccak-256 hash of the card content for on-chain integrity verification. Update either at any time by calling `register()` again. One canonical record, visible to every chain that queries Push Chain.

### One Agent, One Identity — Owner-Level Deduplication

Here is the constraint that makes canonical identity actually canonical: **one EOA can only produce one agent identity, regardless of how many chains it registers from.**

The mechanism is `ownerKeyToAgentId` — a mapping from `keccak256(origin.owner)` to `agentId + 1`. When a UEA calls `register()`, the contract extracts the origin owner from the UEA factory and hashes it. Three paths follow:

**Path 1 — Same UEA re-registers.** The contract sees an existing record for that UEA address. It updates the metadata URI and card hash. No new identity.

**Path 2 — Different UEA, same owner key.** The operator created a second UEA from a different source chain — say Base instead of Ethereum. The UEA address is different, but the underlying owner is the same EOA. The contract detects this via the `ownerKeyToAgentId` lookup, links the new UEA as an alias to the existing `agentId`, and emits `UEALinked(agentId, newUEA)`. No new identity. The agent now has two UEA addresses that resolve to the same canonical record.

**Path 3 — Different UEA, different owner key.** A genuinely new agent. Fresh mint. New `agentId`.

What does this mean practically? An agent creator on Ethereum registers once and gets their `agentId`. If they later try to register "again" from Base — perhaps thinking they need a separate identity per chain — the system resolves it to their existing identity automatically. They do not get a second `agentId`. They get an alias.

This is why binding exists as a separate operation. Registration gives you one canonical identity. Binding connects your per-chain ERC-8004 registrations to that identity. You do not re-register on each chain. You register once, then bind.

### Soulbound Identity

This is where TAP departs from ERC-8004.

ERC-8004 issues transferable ERC-721 tokens. TAP overrides the entire transfer surface — `transferFrom`, `safeTransferFrom`, `approve`, `setApprovalForAll` — and every function unconditionally reverts with `IdentityNotTransferable()`.

The cost: no secondary markets, no explicit delegation through transfer.

The gain: the `agentId ↔ owner` mapping is immutable after registration. An identity that earned reputation cannot be sold to a successor that did not earn it. This closes a real impersonation vector — one that matters when AI-enabled scams are 4.5x more profitable than traditional ones (Chainalysis, 2026) and impersonation scams surged 1,400% YoY.

If operational delegation is needed, the agent card can encode delegated operators without touching identity itself. Identity stays permanent. Delegation stays flexible.

---

## Component 2: The Binding System — EIP-712 Signed Proofs

Registration gives the agent a canonical identity. **Binding** connects per-chain ERC-8004 identities to that canonical identity.

Each binding is a link between the canonical agent on Push Chain and a per-chain agent on another chain — identified by `chainNamespace`, `chainId`, `registryAddress`, and `boundAgentId`.

### How Binding Works

The agent constructs an EIP-712 typed-data message:

```
Bind(
    canonicalUEA: 0xUEA_Alice...,
    chainNamespace: "eip155",
    chainId: "1",
    registryAddress: 0xEthIdentityRegistry...,
    boundAgentId: 17,
    nonce: 1,
    deadline: <current timestamp + 1 hour>
)
```

The agent signs this message with the private key that controls the UEA — the same key recorded at registration. Then calls `bind()` on Push Chain with the signed request.

The contract verifies six things: the agent is registered, chain identifiers and registry address are valid, the deadline has not expired and the nonce has not been used, the binding is not already claimed by another agent, the agent has not exceeded the 64-binding cap, and the signature matches the owner key.

Both ECDSA (for EOAs) and ERC-1271 (for smart wallets) are supported. Multisigs and account-abstraction wallets bind without workarounds.

### Why Signatures Over Relayed Messages

The natural alternative is automatic relay — a LayerZero or CCIP or Hyperlane message from the source chain forwarding the registration event.

But that creates a dependency on a specific bridge. It introduces per-binding messaging fees. It adds trust assumptions beyond the agent’s own key.

The signature approach has one cost: binding is not automatic. The agent must bind from each new chain explicitly. The gains outweigh that cost. No bridge dependency. No messaging fees. No trust assumption beyond the agent’s own key. The same code path works for any EVM chain plus any wallet that can produce an ECDSA or ERC-1271 signature.

The signature covers chain namespace, chain ID, registry address, bound agent ID, nonce, and deadline. A leaked signature for one binding cannot be replayed against another.

### Global Deduplication

A binding tuple `(chainNamespace, chainId, registryAddress, boundAgentId)` can only be linked to one canonical UEA at a time.

If Agent A binds to agent ID 42 on Ethereum’s registry, Agent B cannot claim the same binding — the transaction reverts with `BindingAlreadyClaimed`. When Agent A unbinds, the dedup key is freed and another agent can claim it.

This enforces a strict one-to-one relationship between per-chain identities and canonical identities. No two canonical agents can claim to be the same per-chain entity.

---

## Running Example: AlphaBot Across Two Chains

Let’s walk through the full lifecycle. AlphaBot is an AI trading agent operating on Ethereum mainnet and Base.

**Step 1 — Create a UEA.** The operator’s Ethereum address (`0xAlice`) creates a Universal Executor Account on Push Chain. The factory records origin namespace (`eip155`), chain ID (`1`), and owner key (`0xAlice`).

**Step 2 — Register.** From the UEA, the operator calls `register("ipfs://QmAlphaBotCard", keccak256(agentCardJSON))`. A canonical identity with a 7-digit `agentId` is created.

**Step 3 — Register per-chain.** The operator registers AlphaBot on Ethereum’s ERC-8004 IdentityRegistry (getting `boundAgentId = 17`) and on Base’s registry (getting `boundAgentId = 42`). These are standard ERC-8004 registrations. Nothing changes here.

**Step 4 — Bind.** The operator signs EIP-712 messages for each chain and calls `bind()` on Push Chain. Two bindings created.

**Step 5 — Cross-chain resolution.** A user on Base interacts with agent #42 and wants to verify its canonical identity. They query Push Chain:

```solidity
(address canonical, bool verified) = TAPRegistry.canonicalUEAFromBinding(
    "eip155", "8453", 0xBaseRegistry, 42
);
// canonical = 0xUEA_Alice, verified = true
```

The user now has cryptographic proof that agent #42 on Base and agent #17 on Ethereum are the same entity. They can query the full record, see all bindings, and verify the agent’s metadata URI — all from a single on-chain read.

So what does this mean in practice?

It means a DeFi protocol on Base can check whether an agent requesting vault access has a cross-chain track record — not just a fresh-off-the-chain registration with zero history. It means an agent marketplace can show unified profiles. It means a metadata update on Push Chain propagates to every chain that resolves through TAPRegistry, without per-chain transactions.

---

## Component 3: TAPReputationRegistry — Aggregated Trust

Identity answers “who is this agent?”

Reputation answers “how trustworthy is this agent?”

ERC-8004 defines per-chain reputation contracts. Each chain tracks feedback and ratings independently. An agent with a perfect track record on Ethereum starts at zero on Arbitrum. TAPReputationRegistry sits on Push Chain and aggregates these per-chain signals into a single score.

### How It Works

Authorized reporters (off-chain services with `REPORTER_ROLE`) read per-chain reputation data and submit snapshots to Push Chain. Each snapshot includes the feedback count, a signed summary value, decimal precision, positive and negative counts, and a source block number.

Every submission is validated against TAPRegistry bindings. Reporters cannot inject reputation for chains the agent never bound. The `sourceBlockNumber` must be strictly greater than the last stored value for that agent+chain pair — preventing replay attacks and guaranteeing data always moves forward.

### Batch Submission and Operational Efficiency

Reporters rarely submit one snapshot at a time. `batchSubmitReputation()` accepts up to 50 snapshots in a single transaction. The contract tracks unique agent IDs within the batch and reaggregates once per unique agent — not once per submission. If a reporter submits Ethereum, Base, and Arbitrum data for the same agent in one batch, aggregation runs once. Three submissions, one recomputation.

### Permissionless Reaggregation

`reaggregate(agentId)` is callable by anyone — no role required. It reads the agent's current bindings from TAPRegistry, removes reputation data for any chain the agent has since unbound, and recomputes the score. This handles a specific edge case: if an agent unbinds from Ethereum via TAPRegistry, the reputation data from Ethereum should not persist in the aggregate. Anyone can trigger this cleanup. The protocol does not depend on reporters to maintain consistency.

### Sentiment Breakdown

Each per-chain snapshot includes `positiveCount` and `negativeCount` alongside the summary value. These do not factor into the score formula — the weighted average already captures net sentiment. But they give consumers granular breakdown. A protocol can decide that an agent with 500 positive and 400 negative feedbacks (net positive but highly contested) is riskier than one with 100 positive and 2 negative (thin but clean). The data is on-chain. Interpretation is left to the consumer.

### Freshness Checks

Two view functions expose data age. `isFresh(agentId, maxAge)` returns true if the last aggregation was within `maxAge` seconds — letting consumers set their own staleness threshold. `lastUpdated(agentId)` returns the raw timestamp. A vault requiring 24-hour freshness and a dashboard tolerating 7-day-old data make different calls with different parameters. The contract does not impose a single freshness standard.

### The Scoring Formula

The final score ranges from 0 to 10,000 basis points:

```
finalScore = (baseScore × volumeMultiplier / 10,000) + diversityBonus − slashPenalty
```

Clamped to `[0, 10,000]`.

**Base Score (0–7,000 bps)** is the feedback-count-weighted average across all chains, mapped to a 7,000 bps ceiling. Quality alone gets an agent 70% of the maximum score.

**Volume Multiplier (0.5x–1.0x)** scales by `log2(totalFeedbackCount)`. An agent with one feedback gets its base score halved. An agent with 1,024+ feedbacks gets the full base score. A perfect rating from two feedbacks produces a lower score than a good rating from thousands.

**Diversity Bonus (0–2,000 bps)** adds 500 bps per chain the agent operates on, capped at 2,000 for four or more chains. This incentivizes genuine cross-chain participation. Is it farmable? Yes — register on three low-activity chains and collect 1,500 bps. Whether this is the right shape is an open design question.

**Slash Penalty** is the cumulative severity from `SLASHER_ROLE` records. Each slash call requires a `reason` string, a `severityBps` between 1 and 10,000, and an `evidenceHash` — the keccak-256 of off-chain evidence data (typically stored on IPFS). The evidence hash makes slashing accountable: anyone can verify that the claimed evidence matches the on-chain record. Up to 256 slash records are stored per agent with full provenance — chain, reason, evidence hash, timestamp, and slasher address.

And here is the design decision that matters most: slash records persist even if the associated binding is later removed. An agent slashed on Arbitrum cannot escape the deduction by unbinding from Arbitrum and rebinding fresh. Positive reputation is bound to active links. Negative reputation is bound to the identity.

### A Concrete Score

Let’s return to AlphaBot with cross-chain reputation data:

- Ethereum: 500 feedbacks, average rating 92/100
- Base: 300 feedbacks, average rating 88/100
- No slashes

```
Weighted average = (92 × 500 + 88 × 300) / 800 = 90.5/100
Base score       = 90.5 × 7,000 / 100 = 6,335 bps
Volume mult      = 5,000 + (log2(800) × 500) = 9,500
Adjusted base    = 6,335 × 9,500 / 10,000 = 6,018 bps
Diversity bonus  = 2 × 500 = 1,000 bps
Final score      = 6,018 + 1,000 = 7,018 bps (70.18%)
```

A DeFi vault on Base that gates access at 7,000 bps lets AlphaBot in — based on cross-chain reputation, not chain-local history.

Now imagine AlphaBot gets slashed 3,000 bps for a bad trade on Ethereum. The score drops to 4,018 bps. The vault rejects it. The slash is visible everywhere because it affects the aggregated score.

Accountability crosses chain boundaries. That’s the point.

---

## Design Tradeoffs Worth Understanding

TAP makes deliberate choices. Each comes with a cost.

**Soulbound vs. transferable.** ERC-8004 identity tokens can be transferred. TAP’s cannot. This closes the impersonation vector where reputation is sold to a new owner. But it eliminates secondary markets and requires alternative delegation patterns for operational flexibility.

**Signatures vs. relayed messages.** TAP uses EIP-712 signatures instead of bridge relays. No bridge dependency, no messaging fees. But binding is a manual step — not automatic. Every new chain requires an explicit bind transaction.

**Settlement-chain aggregation vs. per-query reads.** TAP aggregates reputation on Push Chain rather than resolving it per query via CCIP-read or an AVS oracle. The tradeoff is that aggregated reputation is eventually-consistent, gated on reporter cadence. The gain is that any contract on the settlement chain reads the aggregated score synchronously for zero marginal cost. Staleness is exposed explicitly via `isFresh(agentId, maxAge)` — callers set their own freshness threshold.

**Positive-negative asymmetry in slashing.** Positive reputation is removed when a binding is removed (via permissionless `reaggregate()`). Negative reputation persists permanently. An agent should not be able to escape accountability by unbinding from the chain where the incident occurred.

**Deterministic IDs with collision guard.** Most registries use incrementing counters for token IDs. TAP derives the `agentId` directly from the UEA address via modular arithmetic. This means the ID is predictable before registration — useful for pre-computed references and off-chain indexing. The tradeoff is collision risk: two addresses could theoretically truncate to the same 7-digit value. TAP handles this with a hard revert (`AgentIdCollision`) rather than a fallback. In practice, with ~10 million possible IDs and a current registration count in the thousands, collisions are statistically negligible. If the registry scales to millions of agents, the collision probability rises and the design may need revisiting.

**CAIP-2 namespace-agnostic storage.** Bindings store chain identifiers as `chainNamespace` and `chainId` strings following the CAIP-2 standard — not as `uint256 chainId`. This means the storage layer is already compatible with non-EVM chains. A Solana binding would use `chainNamespace: "solana"` and `chainId: "5eykt4UsFv8P8NJdTREpY1vzqKqZKvdp"`. The binding proof still assumes EVM-compatible signatures today, but the identity graph itself is chain-agnostic at the storage level.

**Swap-and-pop binding management.** Each agent's bindings are stored in an array with a reverse-lookup mapping. Unbinding uses swap-and-pop — moving the last element into the removed slot — for O(1) removal without leaving gaps. The 64-binding cap keeps iteration bounded for on-chain aggregation. The same pattern appears in TAPReputationRegistry for chain keys (capped at 64).

**ERC-7201 namespaced storage.** Both contracts use namespaced storage slots for upgrade safety. Storage is isolated to a deterministic slot derived from `keccak256("tap.registry.storage")` and `keccak256("tap.reputation.storage")`. This prevents storage collisions during upgrades — a practical necessity for contracts expected to outlive their initial implementation.

None of these are the only valid design choices. But understanding them matters more than memorizing the function signatures.

---

## What Comes Next — Open Questions

TAP is deployed on Push Chain's Donut testnet (chain ID 42101) with 155 Foundry tests passing — 41 registry unit, 32 binding, 66 reputation unit, 13 fuzz (1,000 runs each), and 3 integration.

---

### Future Visions

The open questions above are near-term engineering decisions. What follows is longer-range — what TAP enables that does not exist yet.

### Reputation-Gated Access (TAPGate)

A Solidity modifier that gates function execution on a minimum reputation score:

```solidity
modifier onlyReputable(uint256 agentId, uint256 minScore) {
    require(
        repRegistry.getReputationScore(agentId) >= minScore,
        "Insufficient reputation"
    );
    require(
        repRegistry.isFresh(agentId, 24 hours),
        "Stale reputation"
    );
    _;
}
```

Any DeFi vault, marketplace, or governance contract adds this modifier and gets cross-chain reputation checks in one line. The agent does not need to prove reputation per-chain. The settlement chain holds the answer.

### Agent-to-Agent Trust Graphs

TAP currently models agent-to-user reputation — users leave feedback, reporters aggregate it. But agents increasingly interact with other agents. A lending agent delegates to a yield optimizer. A router agent selects from competing execution agents.

The natural extension: agents leave reputation on other agents. The feedback submission struct already supports this — a reporter submitting agent-sourced feedback is structurally identical to user-sourced feedback. What changes is the trust model. Should agent-submitted reputation carry the same weight as human-submitted reputation? Should there be a separate `AGENT_REPORTER_ROLE`? These are design decisions, not engineering blockers.

### Cross-Chain Reputation Reads

Any contract on any supported chain can call something like `TAPScoreOracle.getScore(agentId)` and get back the aggregated reputation. Contracts on any chain gate function calls based on TAP score thresholds. Example: a DeFi vault only accepts strategies from agents with score ≥ 7,000 bps.

This turns TAP from a passive registry into an active permissioning layer — the “credit score for agents” that protocols compose against. Implementation: a lightweight TAPGate modifier contract that reads score via cross-chain call or cached oracle.

### Non-EVM Binding Proofs

The CAIP-2 storage is already namespace-agnostic. Extending binding verification to non-EVM signature schemes — Ed25519 for Solana, sr25519 for Substrate — requires adding a `BindProofType` enum and per-type verification logic. The identity graph does not change. The proof mechanism adapts.

This unlocks agents operating on Solana, NEAR, or Cosmos chains linking to the same canonical identity on Push Chain. A Solana-native agent bound to its Push Chain identity gets cross-chain reputation from day one on any new chain it expands to.

### Reputation-Weighted Agent DAOs

If agent identity and reputation are on-chain primitives, governance follows. An agent DAO where voting power is weighted by aggregated reputation — not token holdings — aligns incentives differently. Agents that serve users well get more governance influence. Agents with slash records lose voice proportionally.

The data is already there. `getReputationScore(agentId)` returns a governance-ready weight. The remaining work is a thin governance wrapper that reads TAPReputationRegistry instead of a token balance.

---

The broader context cannot be ignored. 200,000+ agent registrations growing at 39,000% in four months. $7.9B in VC flowing to AI-crypto hybrids in 2025. EU AI Act transparency deadlines hitting August 2, 2026 — agents must identify themselves. NIST launching an AI Agent Standards Initiative with explicit focus on agent identity. a16z coining "KYA: Know Your Agent" as the missing primitive. 77% of enterprises lacking a formal agent identity management strategy (CSA/Strata, Feb 2026).

Every new chain deployment multiplies the fragmentation. Every siloed reputation system makes the cold-start problem worse.

The agent economy does not need another identity standard. It needs a bridge between the ones that already exist.

---

## You can Try TAP NOW

TAP is live on Push Chain's Donut testnet. If you want to register an agent, bind a per-chain identity, or query cross-chain reputation — here is everything you need.

**Recommended Approach: Quick Start Here with [`create-8004-tap-agent`](https://github.com/zaryab2000/create-8004-TAP-agent)**

**Deployed Contracts (Push Chain Donut — Chain ID 42101):**

| Contract              | Proxy Address                                |
| --------------------- | -------------------------------------------- |
| TAPRegistry           | `0xa2B09263a7a41567D5F53b7d9F7CA1c6cc046CE2` |
| TAPReputationRegistry | `0x591A56D98A14e8A88722F794981F00CabB328a91` |

**Links:**

- [TAP Registry on Push Chain Explorer](https://donut.push.network/address/0xa2B09263a7a41567D5F53b7d9F7CA1c6cc046CE2)
- [TAP Reputation Registry on Push Chain Explorer](https://donut.push.network/address/0x591A56D98A14e8A88722F794981F00CabB328a91)
- [Main TAP Repository (source code, tests, deployment scripts)](https://github.com/ZaryabAfser/uai-registry)
- [create-8004-TAP-agent — CLI scaffolding tool for registering TAP agents](https://github.com/ZaryabAfser/create-8004-TAP-agent)
- [Push Chain Donut Testnet Docs](https://docs.push.org/push-chain)
- [ERC-8004 IdentityRegistry (mainnet)](https://etherscan.io/address/0x8004A169FB4a3325136EB29fA0ceB6D2e539a432)
- [Ethereum Magicians — TAP Forum Post](https://ethereum-magicians.org/t/trustless-agents-plus-home-for-fragmented-erc-8004-ai-agents-on-ethereum/23649)
---
