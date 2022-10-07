# Deployer

These contracts demonstrate an upgradeable deployer pattern for the various contracts included in the extensions collection.

## Design

The deployer contract is meant to be a trusted mechanism for platform users to create instances of contracts they require. This is a managed, upgradeable contract. The first four iterations are meant to demonstrate this functionality. Subsequent development will only create new versions as they are deployed, aggregating multiple features per release where possible.

The contract has two types parts. The deployer contract itself, which has deploy*** functions for each of the contracts it's aware of and supporting libraries. Breaking out the actual contract deployment functionality into library contracts allows us to reuse them across versions, replace them if needed and generally keep upgrade costs lower.

All deployment functions return the address of the just-created contract and emit an event with the contract type name and the address.

## Auctions

Version three of the contract introduced the ability to deploy auction house contracts. It's expected that DAO Labs will offer a platform-level Dutch and English auction house contracts that can be used by the projects on the platform, we still want an easy option for people interested in deploying their own.

There are two functions, `deployDutchAuction` and `deployEnglishAuction` that will create these contracts. This is done with the clone pattern where the deployer contract is given a known-good version of the logic contract and calls to these functions will deploy proxies that will `delegatecall` into it. The function parameters are the same as the ones going into the auction contract initializers. Actual deployment logic is in the `AuctionsFactory` contract.

`deployDutchAuction`:

- projectId: Project that manages this auction contract.
- feeReceiver: An instance of IJBPaymentTerminal which will get auction fees.
- feeRate: Fee percentage expressed in terms of JBConstants.SPLITS_TOTAL_PERCENT (1000000000).
- allowPublicAuctions: A flag to allow anyone to create an auction on this contract rather than only accounts with the `AUTHORIZED_SELLER_ROLE` permission.
- periodDuration: Number of seconds for each pricing period for price reduction.
- owner: Contract admin.
- directory: JBDirectory instance to enable JBX integration.

`deployEnglishAuction`

- projectId: Project that manages this auction contract.
- feeReceiver: An instance of IJBPaymentTerminal which will get auction fees.
- feeRate: Fee percentage expressed in terms of JBConstants.SPLITS_TOTAL_PERCENT (1000000000).
- allowPublicAuctions: A flag to allow anyone to create an auction on this contract rather than only accounts with the `AUTHORIZED_SELLER_ROLE` permission.
- owner: Contract admin.
- directory: JBDirectory instance to enable JBX integration.

## NFTs

The first version of the deployer introduced the ability to create NFT contracts, the logic is in `NFTokenFactory`. The `createNFToken` function accepts the parameters necessary to deploy a copy of the `NFToken` contract which is described in more detail in the NFT section.

Version four of the deployer added the option of deploying a cloned NFT in `NFUTokenFactory`. `deployNFUToken` takes the necessary arguments but omits `mintPeriodStart` and `mintPeriodEnd` which can be set by the NFT admin after deployment if needed. Contracts created via this process are storage proxies that forward function calls with `delegatecall`. This is a lower fee option compared to the one above.

## Mixed Payment Splitter

Deployer version two added the option to deploy a `MixedPaymentSplitter` contract. This is a full copy and it's done via `deployMixedPaymentSplitter` function which calls into `MixedPaymentSplitterFactory`. The parameters are below, for more details see the top-level readme of the extensions directory.

- name: Name for this split configuration.
- payees: List of payable addresses to send payment portion to.
- projects: List of Juicebox project ids to send payment portion to.
- shares: Share assignment in the same order as payees and projects parameters. Must be the same length as `payees` and `projects` combined Share total is 1_000_000.
- jbxDirectory: Juicebox directory contract
- owner: Admin of the contract.

## Payment Processor

This contract serves as a proxy between the payer and the Juicebox platform. It allows payment acceptance in case of Juicebox project misconfiguration. It allows acceptance of ERC20 tokens via liquidation even if there is no corresponding Juicebox payment terminal. There should be one of these per project that is interested in this functionality.

- jbxDirectory: Juicebox directory.
- jbxOperatorStore: Juicebox operator store.
- jbxProjects: Juicebox project registry.
- liquidator: Platform liquidator contract. An instance of `TokenLiquidator`, advanced users are welcome to provider their own implementation. as described in `ITokenLiquidator`.
- jbxProjectId: Juicebox project id to pay into.
- ignoreFailures: If payment forwarding to the Juicebox terminal fails, Ether will be retained in this contract and ERC20 tokens will be processed per stored instructions. Setting this to false will `revert` failed payment operations.
- defaultLiquidation: Setting this to true will automatically attempt to convert the incoming ERC20 tokens into WETH via Uniswap unless there are specific settings for the given token. Setting it to false will attempt to send the tokens to an appropriate Juicebox terminal, on failure, _ignoreFailures will be followed.
