# Movement extensions for Juicebox v2

This is a collection of contracts providing extra functionality on top of Juicebox v3 that is fully integrated with the rest of the platform.

## Contracts

Each section has its own README outlining functionality and usage.

### Auctions

NFT English (increasing price) and Dutch (decreasing price) auction contracts for ERC721 tokens.

### Deployer

An upgradeable proxy contract to deploy reusable system components like NFTs, payment processors, etc.

### NFT

blah

### NFT Rewards

Juicebox rewards project contributors with ERC20 tokens, the contracts here allow project controllers to also issue NFTs. These can be used a simple rewards, memberships, etc. There are several examples of price resolvers to demonstrate different use cases.

### Utils

#### JBSplitPayerUtil

This contract allows processing of JBSplit objects and execute the associated payment outside the context of `JBPayoutRedemptionTerminal`. Currently this is used in the auction contracts described above.

### Misc contracts

#### DaiTreasuryDelegate

An automated DAI treasury that will convert incoming Ether into DAI on Uniswap. This contract is an implementation of `IJBFundingCycleDataSource`,
  `IJBPayDelegate` and `IJBRedemptionDelegate` providing deposit and withdraw functionality as part of a [Funding Cycle](#) via `didPay` and `didRedeem`. This contract is meant to be shared across all projects on the platform that would like to diversify some their holdings from Ether into DAI.

#### JBRoleManager

A contract to enable a dynamic access control mechanism. While conceptually similar to `JBOperatorStore`, JBRoleManager allows on-the-fly creation of project-specific roles, their assignment to users and validation.

#### LogPublisher

A generic contract to push events to the log.

#### MixedPaymentSplitter

Based on OpenZeppelin finance/PaymentSplitter.sol v4.7.0, this contract allows registered parties to claim Ether or ERC20 token balances held by the Splitter instance prorated to their share. Registered parties can be EOAs, smart contracts or Juicebox projects.

#### PaymentProcessor

This contract is meant to be a proxy that receives payments and forwards them to the pre-configured Juicebox project. The proxy can accept payment in ERC20 tokens and optionally liquidate them. The proxy also optionally allows payment in case of project misconfiguration.

#### TokenLiquidator

blah

#### Vest Tokens

Allows creation of vesting schedules that release ERC20 tokens to a destination address on a regular interval. The vesting schedule can have a cliff, interval duration and total duration. Token amount per vesting event is calculated evenly across the number of events. It is possible to perform the vesting payout trustlessly.

## Notes

Unless stated otherwise, `0` is not considered a valid value. For example in the `NFToken` contract setting `mintAllowance` to 0 will effectively prevent minting.

## Contributing

The code here attempts to follow some conventions to make code reviews easier.

- Function arguments start with an underscore.
- Storage parameters do not start with an underscore regardless of visibility.
- Constants in storage are all caps.
- `revert` is used instead of `require`.
- Error names are capitalized in snake case.
- `for` loops increment at the end as `++i` and test for continuation with `!=`.
- Solidity version is defined with a caret, currently as `^0.8.6`.