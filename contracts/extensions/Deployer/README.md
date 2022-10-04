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

- projectId
- feeReceiver
- feeRate
- allowPublicAuctions
- periodDuration
- owner
- directory

`deployEnglishAuction`

- projectId,
- feeReceiver,
- feeRate,
- allowPublicAuctions,
- owner,
- directory

## NFTs

The first version of the deployer introduced the ability to create NFT contracts, the logic is in `NFTokenFactory`. The `createNFToken` function accepts the parameters necessary to deploy a copy of the `NFToken` contract which is described in more detail in the NFT section.

Version four of the deployer added the option of deploying a cloned NFT in `NFUTokenFactory`. `deployNFUToken` takes the necessary arguments but omits `mintPeriodStart` and `mintPeriodEnd` which can be set by the NFT admin after deployment if needed. Contracts created via this process are storage proxies that forward function calls with `delegatecall`. This is a lower fee option compared to the one above.

## Payment Splitter

Deployer version two added the option to deploy a `MixedPaymentSplitter` contract. This is a full copy and it's done via `deployMixedPaymentSplitter` function which calls into `MixedPaymentSplitterFactory`. The parameters are below, for more details see the top-level readme of the extensions directory.

- name
- payees
- projects
- shares
- jbxDirectory
- owner
