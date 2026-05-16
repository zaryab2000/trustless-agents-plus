# TAP Address Book

Deployed contract addresses for TAP (Trustless Agents Plus). Update this file after every deployment or upgrade.

---

## Push Chain Donut Testnet (Chain ID: 42101)

Deployed: 2026-05-15

### TAPRegistry

| Component           | Address                                      |
| ------------------- | -------------------------------------------- |
| Proxy               | `0xa2B09263a7a41567D5F53b7d9F7CA1c6cc046CE2` |
| Implementation (v1) | `0x8d8d5637966f222c89f03cd39f2df3f2f875ea0a` |
| ProxyAdmin          | `0x45c5a0dcac94c742c786dfb2e251556079d9e07a` |

### TAPReputationRegistry

| Component           | Address                                      |
| ------------------- | -------------------------------------------- |
| Proxy               | `0x591A56D98A14e8A88722F794981F00CabB328a91` |
| Implementation (v1) | `0xbf95b7c742dcfaa45cdab522123c99a439223e42` |
| ProxyAdmin          | `0x3c662ef36a1e6447bb7ce1809ebf4e37a2a1ec66` |

### Roles

| Role               | Holder                                       |
| ------------------ | -------------------------------------------- |
| DEFAULT_ADMIN_ROLE | `0x53CE8AA36CD92A25AF7AA2cFfd08DC46b080c88a` |
| PAUSER_ROLE        | `0x53CE8AA36CD92A25AF7AA2cFfd08DC46b080c88a` |
| REPORTER_ROLE      | `0x53CE8AA36CD92A25AF7AA2cFfd08DC46b080c88a` |
| SLASHER_ROLE       | `0x53CE8AA36CD92A25AF7AA2cFfd08DC46b080c88a` |
| ProxyAdmin Owner   | `0x53CE8AA36CD92A25AF7AA2cFfd08DC46b080c88a` |

### Block Explorer Links

- [TAPRegistry Proxy](https://donut.push.network/address/0xa2B09263a7a41567D5F53b7d9F7CA1c6cc046CE2)
- [TAPRegistry Impl v1](https://donut.push.network/address/0x8d8d5637966f222c89f03cd39f2df3f2f875ea0a)
- [TAPReputationRegistry Proxy](https://donut.push.network/address/0x591A56D98A14e8A88722F794981F00CabB328a91)
- [TAPReputationRegistry Impl v1](https://donut.push.network/address/0xbf95b7c742dcfaa45cdab522123c99a439223e42)

---

## Deployment History

| Date       | Contract              | Impl Address    | Notes                    |
| ---------- | --------------------- | --------------- | ------------------------ |
| 2026-05-15 | TAPRegistry           | `0x8d8d...ea0a` | Fresh deployment (v1)    |
| 2026-05-15 | TAPReputationRegistry | `0xbf95...3e42` | Fresh deployment (v1)    |

---

## Deprecated Deployments

Previous deployments (superseded by 2026-05-15 fresh deploy):

| Contract                          | Address                                      | Status     |
| --------------------------------- | -------------------------------------------- | ---------- |
| TAPRegistry Proxy (old)           | `0x13499d36729467bd5C6B44725a10a0113cE47178` | Deprecated |
| TAPRegistry Impl v2 (old)         | `0x998e9630b6437bb3c42f42cb48bb9f8124397cf5` | Deprecated |
| TAPRegistry Impl v1 (old)         | `0x593a6caa38fd093f8b52b6dc5af6a88d77b1cd15` | Deprecated |
| TAPRegistry ProxyAdmin (old)      | `0x062021b898e2693f41bb69d463c016cda568794e` | Deprecated |
| TAPReputationRegistry Proxy (old) | `0x90B484063622289742516c5dDFdDf1C1A3C2c50C` | Deprecated |
| TAPReputationRegistry Impl (old)  | `0x59ab150c2ba3efd618668a469db29f5c92eedd64` | Deprecated |
| TAPReputationRegistry PA (old)    | `0x32e0b8a0fdd30c8a64bf013ea8d224ed79cbcab8` | Deprecated |
