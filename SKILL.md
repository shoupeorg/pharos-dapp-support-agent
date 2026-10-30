---
name: pharos-dapp-support-agent
description: Diagnose a Pharos Pacific Mainnet transaction hash from official Chain MCP transaction and receipt evidence without preparing or sending transactions.
---
# Pharos dApp Support Agent
1. Validate an exact 32-byte transaction hash.
2. Confirm Pacific Mainnet chain ID 1672 through official Chain MCP.
3. Read the transaction and receipt with `get_transaction` and `get_transaction_receipt`.
4. Treat receipt status as execution outcome. Never infer a revert from a transport/RPC error.
5. If status is failed and the inspected schema supports a block argument, replay with `eth_call` at N and N-1 only as supplementary evidence.
6. Decode only standard Error(string), Panic(uint256), or custom errors backed by an explicitly trusted ABI.
7. State that replay is not exact intra-block prestate and that trace/state diff is unavailable.
8. Return confirmed facts, inference confidence, unavailable evidence, and safe next steps. Never request keys, signatures, approvals, or broadcasts.