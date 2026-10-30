export const NETWORK=Object.freeze({name:"Pharos Pacific Mainnet",chainId:1672,chainIdHex:"0x688",nativeSymbol:"PROS",mcpUrl:"https://mcp.pharos.xyz/mcp",explorerTxBase:"https://www.pharosscan.xyz/tx/"});
export const ENGINE_VERSION="dapp-support/1.0.0";
export const REQUIRED_MCP_TOOLS=Object.freeze(["get_chain_info","get_transaction","get_transaction_receipt"]);
export const EXAMPLES=Object.freeze([
{id:"slippage",label:"Slippage Guard",hash:"0xfd9e2b56afea04980e35d9627e6ab822a8b4f73fd1859b4bc953784fb95bf5b4"},
{id:"zero-balance",label:"Zero Input-Token Balance",hash:"0x2a60f5f0f636777e26661f6cc6c496494af4b118e31fcd23162f6988fc48e652"},
{id:"invariant",label:"Application Invariant",hash:"0x77a9d42826280512c22c55c279720985e62365bc43c7c1b27bbe4d3eb1d55528"}
]);