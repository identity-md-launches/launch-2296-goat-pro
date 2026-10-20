# Goat Pro (GPRO)

`src/GoatPro.sol:GoatPro` is a fixed-supply ERC-20. It uses the unmodified
OpenZeppelin Contracts v5.0.2 ERC-20 implementation.

| Parameter | Value |
| --- | --- |
| Solidity contract name | `GoatPro` |
| Token name | `Goat Pro` |
| Symbol | `GPRO` |
| Decimals | `18` |
| Whole-token supply | `1,000,000,000` |
| Supply in smallest units | `1000000000000000000000000000` (`10^27`) |
| Constructor arguments | None (`[]`) |
| Initial recipient | Immediate deployer (`msg.sender`) |
| Compiler | Solidity `0.8.26` |
| Build settings | Paris EVM, optimizer enabled, 200 runs, `bytecode_hash = "none"` |

The constructor mints the entire supply once and emits the ERC-20 mint
`Transfer` event. When a factory deploys this contract, the factory receives
all tokens. The transaction origin and the wallet calling the factory receive
none from the constructor.

## Behavior and assumptions

The brief is interpreted as a standard transferable ERC-20: transfers have no
fees, taxes, burns, rebases, limits, or exemptions. There is no owner, minter,
pause, blacklist, confiscation, upgrade mechanism, proxy, or initialization
step. There is no public mint or burn function, so the supply remains fixed.
The only project-specific constant is `INITIAL_SUPPLY`, the requested supply
in smallest units. No address or outside service is required by the contract.

`transfer`, `approve`, and `transferFrom` return `true` on success and revert
with OpenZeppelin ERC-20 custom errors on invalid input. Zero-value transfers
between nonzero addresses succeed and emit `Transfer`; transfers to the zero
address and approvals to the zero spender revert. A self-transfer preserves
the balance. Token transfers do not invoke recipient callbacks.

Allowances are scoped to the holder and spender. `approve` replaces the
previous allowance, and setting it to zero revokes it. `transferFrom` consumes
finite allowance, including when transferring back to the holder, but leaves
`type(uint256).max` allowance unchanged. Even a holder calling `transferFrom`
on its own balance needs allowance; `transfer` needs none. `approve` emits
`Approval`; OpenZeppelin v5 does not emit `Approval` when `transferFrom`
consumes allowance, so integrations should query `allowance` for current state.

## Build and test

Run from the repository root with Foundry and Solidity 0.8.26 available:

```sh
forge build
FOUNDRY_FUZZ_SEED=0xf814015270a398f4a9858e85a8cb353f41a76850778af0ff5c3b4bbe251cb39a forge test
forge fmt --check
```

Both dependencies are vendored as ordinary source files under `lib/`. Builds
and tests need no dependency downloads, RPC, keys, environment configuration,
FFI, or filesystem cheatcode permissions. The compiler must be installed in
the build environment; it is deliberately not vendored. `DEPENDENCIES.json`
records upstream versions, commit IDs, and SHA-256 hashes of all vendored files.
Their licenses are included alongside them. OpenZeppelin includes only the
ERC-20 dependency closure; forge-std includes its test library source.

Tests cover metadata, the constructor mint and immediate-deployer semantics,
transfer and approval events, full/zero/self transfers, contract recipients,
finite and unlimited allowances, revocation, unauthorized spending, invalid
recipients, insufficient funds, and rollback on failure. Fuzz tests exercise
transfer conservation, arbitrary recipients, approval isolation, and failure
atomicity. Stateful invariants exercise randomized transfers, approvals, and
delegated transfers among four holders, checking exact changes and conservation.
The default settings run 512 cases per fuzz test and 128 sequences of up to
64 calls per invariant.

`LaunchFlow.t.sol` checks CREATE2 deployment and exact factory distribution,
claim, and pool/trader token movements using local actors. It is not a
Uniswap pool implementation or a live swap test. The supplied protected
launch tests depend on the separate launch system, manifest, and pool
contracts; this project does not reproduce that external harness.

## Deployment and operational responsibilities

Deploy the creation bytecode for `GoatPro` with no appended constructor
arguments and no native value. The artifact is `out/GoatPro.sol/GoatPro.json`.
There are no library link addresses, application contracts, or post-deployment
initialization calls. The Paris EVM target avoids reliance on newer opcodes;
the token uses no chain-specific precompiles, timestamps, block numbers,
randomness, or oracles.

The assignment identifies Robinhood Chain, chain ID **4663**, as the launch
target. The launch system deploys through its factory and handles distribution
and pool setup. The token itself does not know any launch addresses or allocate
shares. The provided economics describe 10% to the launch distributor,
50% to pool seeding, and 40% to the designated remainder recipient. Those
operations belong to the separate launch workflow. Its manifest is created
after acceptance and is not part of this project.

### After launch

There are no administrative settings or maintenance transactions. The launch
operator must verify the deployed bytecode and metadata, check the constructor
mint and subsequent distribution, and publish the token address and verified
source. If deployment uses a different intermediary, that intermediary receives
the supply and must be able to distribute it.

Holders control transfers and approvals. Wallets should request only needed
allowances, revoke unused approvals, and account for transaction ordering when
replacing an active allowance (revoking first is preferable). Unlimited
allowance lets the spender use future holdings until revoked. There is no
administrator to recover tokens sent to the token contract, another contract
without a withdrawal mechanism, or an incorrect recipient, or to reverse
approved spending.

Local Foundry testing and source review do not replace independent adversarial
review before release. No live-chain deployment, swap, explorer verification,
Slither run, or Mythril run is claimed by this project.
