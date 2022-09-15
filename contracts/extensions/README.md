# Movement extensions for Juicebox v2

This is a collection of contracts providing extra functionality on top of Juicebox v2 that is fully integrated with the rest of the platform.

## Contributing

The code here attempts to follow some conventions to make code reviews easier.

- Function arguments start with an underscore.
- Storage parameters do not start with an underscore regardless of visibility.
- `revert` is used instead of `require`.
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

### MixedPaymentSplitter

Based on OpenZeppelin finance/PaymentSplitter.sol v4.7.0, this contract allows registered parties to claim Ether or ERC20 token balances held by the Splitter instance prorated to their share. Registered parties can be EOAs, smart contracts or Juicebox projects.

### NFT

#### NFToken

blah

### NFT Rewards

Juicebox rewards project contributors with ERC20 tokens, the contracts here allow project controllers to also issue NFTs. These can be used a simple rewards, memberships, etc. There are several examples of price resolvers to demonstrate different use cases.

### PaymentProcessor

This contract is meant to be a proxy that receives payments and forwards them to the preconfigured Juicebox project. The proxy can accept payment in ERC20 tokens and optionally liquidate them. The proxy also optionally allows payment in case of project misconfiguration.

### Utils

#### JBSplitPayerUtil

This contract allows processing of JBSplit objects and execute the associated payment outside the context of `JBPayoutRedemptionTerminal`. Currently this is used in the auction contracts described above.

### Vest Tokens

Allows creation of vesting schedules that release ERC20 tokens to a destination address on a regular interval. The vesting schedule can have a cliff, interval duration and total duration. Token amount per vesting event is calculated evenly across the number of events. It is possible to perform the vesting payout trustlessly.
