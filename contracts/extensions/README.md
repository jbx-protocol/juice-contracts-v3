# Extensions for Juicebox v2

This is a collection of contracts providing extra functionality on top of Juicebox v2 that is fully integrated with the rest of the platform.

## Contributing

The code here attempts to follow some conventions to make code reviews easier.

- Function arguments start with an underscore.
- Storage parameters do not start with an underscore regardless of visibility.
- Constants in storage are all caps.
- `revert` is used instead of `require`.
- Error names are capitalized in snake case.
- `for` loops increment at the end as `++i` and test for continuation with `!=`.
- Solidity version is defined with a caret, currently as `^0.8.6`.

## Contracts

### Auctions

NFT auction contracts for ERC721 tokens.

#### DutchAuction

Allows listing NFTs with a starting price, an ending price and an auction duration. This auction type expects bidders to place decreasing bids. It is possible to set a lower bid than the current price to "reserve" your place for the case where the price decreases to that point. When settling an auction, the contract will send the sale proceeds to the listing party, the NFT to the buyer and a commission to a Juicebox project. The commission rate is configurable and capped at 10%. It is possible to perform the auction settlement trustlessly.

#### EnglishAuction

Allows listing NFTs with a starting price, a reserve price and an auction duration. This auction type expects bidders to place increasing bids. When settling an auction, the contract will send the sale proceeds to the listing party, the NFT to the buyer and a commission to a Juicebox project. The commission rate is configurable and capped at 10%. It is possible to perform the auction settlement trustlessly.

### DaiTreasuryDelegate

An automated DAI treasury that will convert incoming Ether into DAI on Uniswap. This contract is an implementation of `IJBFundingCycleDataSource`,
  `IJBPayDelegate` and `IJBRedemptionDelegate` providing deposit and withdraw functionality as part of a [Funding Cycle](#) via `didPay` and `didRedeem`. This contract is meant to be shared across all projects on the platform that would like to diversify some their holdings from Ether into DAI.

### Deployer

An upgradeable proxy contract to deploy reusable system components like NFTs, payment processors, etc.

### JBRoleManager

A contract to enable a dynamic access control mechanism. While conceptually similar to `JBOperatorStore`, JBRoleManager allows on-the-fly creation of project-specific roles, their assignment to users and validation.

### LogPublisher

A generic contract to push events to the log.

### MixedPaymentSplitter

Based on OpenZeppelin finance/PaymentSplitter.sol v4.7.0, this contract allows registered parties to claim Ether or ERC20 token balances held by the Splitter instance prorated to their share. Registered parties can be EOAs, smart contracts or Juicebox projects.

### NFT

#### NFToken

An ERC721 NFT contract with extra features like mint periods, mint caps, ability to set asset revelation. It also provides a flexible mint pricing mechanism, two examples are provided. The NFT represents IPFS-based assets.

#### BalancePriceResolver

This contract calculates the NFT mint price based on the user's current NFT balance. It has options to allow for free initial, subsequent or repeated mints. It's based on `SupplyPriceResolver` and inherits the tier-based pricing functions if the per-user mint conditions are not met.

#### SupplyPriceResolver

This contract can be used together with an NFT contract to generate the mint price based on current NFT supply. The contract accepts a multiplier which increases the price for each tier defined up to a certain price cap. This increase can be linear or exponential.

### NFT Rewards

Juicebox rewards project contributors with ERC20 tokens, the contracts here allow project controllers to also issue NFTs. These can be used a simple rewards, memberships, etc. There are several examples of price resolvers to demonstrate different use cases.

### PaymentProcessor

This contract is meant to be a proxy that receives payments and forwards them to the pre-configured Juicebox project. The proxy can accept payment in ERC20 tokens and optionally liquidate them. The proxy also optionally allows payment in case of project misconfiguration.

### Utils

#### JBSplitPayerUtil

This contract allows processing of JBSplit objects and execute the associated payment outside the context of `JBPayoutRedemptionTerminal`. Currently this is used in the auction contracts described above.

### Vest Tokens

Allows creation of vesting schedules that release ERC20 tokens to a destination address on a regular interval. The vesting schedule can have a cliff, interval duration and total duration. Token amount per vesting event is calculated evenly across the number of events. It is possible to perform the vesting payout trustlessly.
