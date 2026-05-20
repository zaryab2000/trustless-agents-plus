ERC-8004 solved 3 imperatives for on-chain agents:

* a reliable way to prove **identity**,
* a system to accumulate **reputation** from feedback,
* and a standard for cryptographic validation of on-chain work.

However, what still remains is the solution for fragmented on-chain agents across multiple chains.

As of today, there are \~200K agents registered across 23+ chains and \~194K reputation feedbacks locked to individual chain registries. That scale makes the gap visible.

I have my own on-chain agent deployed on three different chains. Its identity is fragmented — three *separate token IDs, three separate reputation scores, zero on-chain proof they belong to the same entity*. many such cases already exists on chains.

This post describes the fragmentation problem and presents a solution for on-chain agents in a multi-chain web3 world.

## Where ERC-8004 Stops today

The current spec leaves a structural gap when agents operate across more than one chain.

Two limitations become visible at multi-chain scale:

### 1. Identity fragmentation

Each chain’s `IdentityRegistry` is a standalone ERC-721 deployed individually on a chain.

An on-chain agent deployed on 5 different chains, has a completely fragmented identity today. ***A contract on Base that wants to check whether agent `#2065` is the same entity as agent `#5249` on BSC has no on-chain path to do so.***

An agent on five chains holds five unrelated token IDs. The only cross-chain hook in the spec today is the off-chain `registrations[]` array in the Agent Registration File — self-asserted by the agent operator, not verifiable on-chain by any contract or consumer.

### 2. Reputation Siloing

Similarly, an agent on five chains accumulates five separate reputation scores. There is no way to derive a cumulative score from multi-chain feedback.

\~194K reputation feedbacks, currently, are locked to their originating chain. An agent with a strong track record on Ethereum and a clean record on Arbitrum gets zero credit for either when a new consumer encounters it on Base.

Each chain’s `ReputationRegistry` is a closed loop — there is no aggregation surface and no way for a contract to query “what is this agent’s reputation across all chains it operates on?”

Given that agents already operate across 23+ chains, an ideal solution is to deliver three things:

1. A **single canonical identity** for an agent across all chains it operates on.
2. An **aggregated reputation score** that reflects performance across every chain.
3. **Synchronous cross-chain reads** for the agent’s unified identity and reputation — not siloed per-chain information.

ERC8004 gave us a standard for “**Trustless Agents”.**

**I propose Trustless Agents Plus ( TAP ).**

## Trustless Agents Plus (TAP)

TAP — Trustless Agents Plus — gives an ERC-8004 agent one canonical identity and one aggregated reputation score across every chain it operates on.

> *Per-chain registries stay exactly as they are. Local registration, agent cards, and per-chain feedback are unchanged.*

**TAP Smart Contracts**

TAP currently is a system of 2 main smart contracts, on Push Chain.

* **TAPRegistry, and**
* **TAPReputationRegistry**

1. **`TAPRegistry`** is the canonical identity layer.

   An agent registers once from its agent-wallet on any chain. The registration happens on Push Chain but the agent registers and pays gas from any chain of their choice.

   The `agentId` is deterministic — derived directly from the UEA address ( *smart accounts on Push Chain for the agent )* `uint256(uint160(ueaAddress)) % 10_000_000`).  The token is soulbound (non-transferable). Per-chain ERC-8004 identities are linked via `bind()`, which verifies an EIP-712 typed-data signature against the agent’s recorded owner key. Both ECDSA and ERC-1271 are supported, so multisigs and AA wallets bind without workarounds.

2. **`TAPReputationRegistry`** is the cross-chain reputation aggregator.

   Authorized reporters submit per-chain reputation snapshots. Every submission is validated against TAPRegistry bindings — reporters cannot inject reputation for chains the agent never bound. The contract normalizes across decimal precisions and derives a single score in `[0, 10,000]` bps combining quality, volume, chain diversity, and persistent slash penalties.

   Both the aggregated score and per-chain breakdowns are exposed — consumers choose their granularity.

```
Per-chain ERC-8004 registries            Settlement chain ( Push Chain )
+------------------+                    +---------------------------+
| Ethereum         | --bind (EIP-712)-> |        TAPRegistry        |
| boundAgentId=17  |                    |   canonicalId=4_928_371   |
+------------------+                    |   soulbound, UEA-anchored |
| Base             | --bind (EIP-712)-> |                           |
| boundAgentId=42  |                    +---------------------------+
+------------------+                    |   TAPReputationRegistry   |
| Arbitrum         | --bind (EIP-712)-> |   score: 7,578 bps        |
| boundAgentId=8   |                    |   3 chains, 1,000 feedb.  |
+------------------+                    +---------------------------+
       ^                                              ^
       |                                              |
  local feedback                            REPORTER_ROLE snapshots
  (unchanged)                               + binding-validated
```

## Novel features of TAP

TAP is designed to improve existing 8004 standard and work seamlessly with existing agents.

Here is how it does it uniquely:

### 1. Soulbound identity tokens

ERC-8004 issues transferable ERC-721 tokens. TAP overrides the entire transfer surface to revert unconditionally. The `agentId ↔ UEA` mapping is immutable after registration — an identity that earned reputation cannot be sold to a successor that did not earn it.

### 2. Multi-Chain Reputation Score

ERC-8004 stores raw weighted averages per chain with no composite score. TAP computes a single, normalized score using a multi-factor formula:

```
finalScore = (baseScore × volumeMultiplier / 10000) + diversityBonus − slashPenalty
```

* **Base score** (0–7,000): Quality alone caps at 70%. `baseScore = weightedAvgValue × 7000 / (100 × 1e18)`.
* **Volume multiplier** (0.5x–1.0x): `5000 + (log2(totalFeedbackCount) × 500)`, capped at 10,000. An agent with 1 feedback gets halved; 1,024+ feedbacks get the full multiplier. This penalizes thin track records — a perfect rating from 2 feedbacks scores lower than a good rating from thousands.

### 3. Diversity Bonus

There is an incentive for agents operating on multiple chains - **the diversity bonus.**

Agents that operate across multiple chains receive a bonus of 500 bps per chain with reputation data, capped at 2,000 bps (4+ chains). This incentivizes genuine cross-chain participation and makes it harder for an agent to farm a high score on a single low-activity chain.

### 4. Cross-Chain Slashing with Persistent Penalties

ERC-8004 has no slashing mechanism. TAP introduces `SLASHER_ROLE` with cumulative severity deductions (1–10,000 bps per event, up to 256 records per agent). Slash records persist even if the associated binding is removed. An agent slashed on chain A cannot escape the deduction by unbinding A and rebinding fresh — negative reputation is bound to the identity, not to any individual binding. Positive reputation is bound to active links.

### 5. Global binding deduplication

A bound identity tuple `(chainNamespace, chainId, registryAddress, boundAgentId)` can only be linked to one canonical UEA ( *smart account of agent on Push* ) at a time. If agent A binds to agent ID 42 on Ethereum’s registry, agent B cannot claim the same binding — the transaction reverts with `BindingAlreadyClaimed`. This prevents impersonation where two canonical agents claim to be the same per-chain entity.

Additionally, ERC-8004 has no concept of cross-chain identity binding. **TAP introduces `bind()`, where the UEA owner signs an EIP-712 typed data** message proving they control the same key on another chain’s ERC-8004 registry.

### **8004 Agent vs 8004 TAP Agent**

![image|690x390](upload://w0Ya8hD3KyzB5VO5PDZLvlokqZp.png)

## Design decisions and tradeoffs

### 1. soulbound over transferable

ERC-8004 issues transferable ERC-721 tokens.

TAP chose soulbound tokens because identity transfer creates a trust discontinuity — if agent #42 earned 8,000 bps of reputation over two years and then sells the identity, the new owner inherits trust they did not earn.

Additionally:

1. The cost: secondary markets and explicit delegation via transfer are gone.
2. The mitigation: agent cards can encode delegated operators without touching identity itself.

### 2. Push Chain over other interop layers

The alternative was deploying TAP on an existing L1 and relaying binding events via LayerZero, CCIP, or Hyperlane. I chose Push Chain because its infrastructure eliminates cross-chain friction for agent builders:

* **UEAs preserve agent identity end-to-end:** A [UEA](https://github.com/pushchain/push-chain-core-contracts/blob/audit-main-fixes/docs/2_UEA.md) is a proxy smart account representing the external chain agent on Push Chain. In most cross-chain architectures, a gateway contract makes the call on behalf of the user — `msg.sender` is the gateway, not the user, so identity is lost. With UEAs, the user’s own account makes the call. TAP derives `agentId` deterministically from the UEA address, anchoring canonical identity to the agent operator’s real cross-chain identity — not an intermediary.
* **Fee and wallet abstraction:** Agent operators interact using native tokens (ETH, SOL) via existing wallets (MetaMask, Phantom). Push Chain detects the source-chain signature, maps it to the UEA, and routes the transaction. No bridging, no new wallets, no gas token acquisition. ([docs](https://push.org/docs/chain/important-concepts/#fee-abstraction-and-cross-chain-execution))
* **Source-chain invocation:** Universal Gateway enables agents on Ethereum or Base to call TAP contracts without switching networks.

The net effect: an agent builder registers, binds, and queries reputation using their existing wallet, paying gas in their native token, with identity preserved end-to-end.

Tradeoff: Push Chain currently supports ETH, Arbitrum, BNB, Base, and Solana only.

### 3. settlement-chain aggregation over per-query reads

TAP aggregates reputation once on the settlement chain and exposes a synchronous on-chain read everywhere else.

The tradeoff: aggregated reputation is eventually-consistent, gated on reporter cadence. T

The gain: any contract on Push Chain reads the aggregated score synchronously for zero marginal cost. Staleness is exposed explicitly via `lastUpdated(agentId)` and `isFresh(agentId, maxAge)`, so callers set their own freshness threshold.

> *This also somewhere connects to what @spengrah [raised in the thread](https://ethereum-magicians.org/t/erc-8004-trustless-agents/25098) about async trust-minimized oracles — TAP targets the same problem from a different point in the design space.*

### 4. aggregated score with per-chain granularity

A single aggregate reputation score is a blunt instrument.

TAP computes the aggregate (`getReputationScore(agentId)` returning 0–10,000 bps), but also exposes full per-chain breakdowns via `getChainReputation()` and `getAllChainReputations()` — raw feedback counts, positive/negative splits, and last-update timestamps.

Consumers that want a single gate use the score. Consumers that want context-specific trust have the underlying data. The scoring formula is fully on-chain and auditable.

> *@daniel-ospina’s [concern in the thread](https://ethereum-magicians.org/t/erc-8004-trustless-agents/25098) about single aggregate scores facilitating monopolistic behavior is exactly why the per-chain breakdown exists.*

---

## Explore & Try TAP

* **Quick Start Here with [`create-8004-tap-agent`](https://github.com/zaryab2000/create-8004-TAP-agent)**
* **[`trustless-agents-plus`](http://github.com/zaryab2000/trustless-agents-plus)** main repo
* Extensive Docs on TAP:
  1. [TAPRegistry](https://github.com/zaryab2000/trustless-agents-plus/blob/main/docs/TAPRegistry.md)
  2. [TAPReputationRegistry](https://github.com/zaryab2000/trustless-agents-plus/blob/main/docs/TAPReputationRegistry.md)
* **Push Chain** [Docs](https://push.org/docs/)

**Deployed TAP Contracts**

| Contract              | Proxy Address                                | Explorer                                                                                          |
| --------------------- | -------------------------------------------- | ------------------------------------------------------------------------------------------------- |
| TAPRegistry           | `0xa2B09263a7a41567D5F53b7d9F7CA1c6cc046CE2` | [View on Explorer](https://donut.push.network/address/0xa2B09263a7a41567D5F53b7d9F7CA1c6cc046CE2) |
| TAPReputationRegistry | `0x591A56D98A14e8A88722F794981F00CabB328a91` | [View on Explorer](https://donut.push.network/address/0x591A56D98A14e8A88722F794981F00CabB328a91) |

## Future Directions for TAP

1. **Cross-chain reputation reads**

any contract on any supported chain can call something like `TAPScoreOracle.getScore(agentId)` and get back the aggregated reputation. Contracts on any chain gate function calls based on TAP score thresholds. Example: a DeFi vault only accepts strategies from agents with score ≥ 7,000 bps.

This turns TAP from a passive registry into an active permissioning layer — the “credit score for agents” that protocols compose against. Implementation: a lightweight TAPGate modifier contract that reads score via cross-chain call or cached oracle.

2. **Agent-to-agent trust graphs (delegation and composition)**

Agents that vouch for or delegate to other agents, creating a directed trust graph on top of TAP identities. Example: a “portfolio manager” agent delegates execution to specialized “swap” and “bridge” agents, staking its own reputation on their behavior. If a delegatee gets slashed, the delegator takes aproportional penalty.

This enables composable agent hierarchies with aligned incentives.

4. **Non-EVM chain bindings (Solana, Cosmos, Move)**

Extend BindProofType beyond ECDSA/ERC-1271 to support Ed25519 (Solana), Secp256k1 with different address derivation (Cosmos), and Move-native signatures.

The storage is already namespace-agnostic (CAIP-2 strings), so the gap is purely in signature verification. This unlocks TAP as a truly universal agent registry — not just multi-EVM, but multi-ecosystem.

## Open Questions:

1. **Should reputation be consumable on source chains synchronously?** TAP aggregates on Push Chain, but a DeFi protocol on Base gating agent access needs the score *there*, not on Push Chain. Pull-based cross-chain reads (via Universal Gateway) vs. push-based score caches (relayer-updated per-chain contracts) represent different trust/latency/cost tradeoffs. Is there a third model worth considering ?
2. Should binding proofs be verifiable on the source chain as well? A small verifier contract per source chain would let an ERC-8004 hook on Base confirm that a given boundAgentId has a canonical identity without a cross-chain read — at the cost of extra deployments and a second verification surface to keep in sync?
3. **regarding Non-EVM binding proofs**: ideally i would want to expand this to non-evm chains too. Storage is namespace-agnostic (CAIP-2 strings), but signature verification is EVM-only today (ECDSA + ERC-1271). Extending `BindProofType` to Ed25519 (Solana) or Move signatures is straightforward per-scheme but expands the precompile surface. are there better alternatives for a generalized multi-scheme signature verification standard worth aligning with, rather than adding schemes one by one?
