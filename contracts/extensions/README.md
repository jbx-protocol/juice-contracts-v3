# DAOLABS extensions for Juicebox v3

This is a collection of additional contracts providing functionality on top of Juicebox v3 that is fully integrated with the rest of the platform.

## Auctions

NFT English (increasing price) and Dutch (decreasing price) auction contracts for ERC721 tokens.

## Deployer

An upgradeable proxy contract to deploy reusable system components like NFTs, payment processors, etc. For more details see the [readme there](./Deployer/README.md).

## NFT

A collection of NFT contracts with ERC721 functionality hooked into the Juicebox payment system along with auction mechanics and other features. For more details, see the NFT [readme](./NFT/README.md).

## NFT Rewards

Juicebox rewards project contributors with ERC20 tokens, the contracts here allow project controllers to also issue NFTs. These can be used a simple rewards, memberships, etc. There are several examples of price resolvers to demonstrate different use cases. This is the original implementation which was changed and updated by the core Juicebox team in [xxx](#).

## Utils

### JBSplitPayerUtil

This contract allows processing of JBSplit objects and execute the associated payment outside the context of `JBPayoutRedemptionTerminal`. Currently this is used in the auction contracts described above.

## Misc contracts

### DaiTreasuryDelegate

An automated DAI treasury that will convert incoming Ether into DAI on Uniswap. This contract is an implementation of `IJBFundingCycleDataSource`, `IJBPayDelegate` and `IJBRedemptionDelegate` providing deposit and withdraw functionality as part of a [Funding Cycle](#) via `didPay` and `didRedeem`. This contract is meant to be shared across all projects on the platform that would like to diversify some their holdings from Ether into DAI.

### JBRoleManager

A contract to enable a dynamic access control mechanism. While conceptually similar to `JBOperatorStore`, JBRoleManager allows on-the-fly creation of project-specific roles, their assignment to users and validation.

### LogPublisher

A generic contract to push events to the log.

### MixedPaymentSplitter

Based on OpenZeppelin finance/PaymentSplitter.sol v4.7.0, this contract allows registered parties to claim Ether or ERC20 token balances held by the Splitter instance prorated to their share. Registered parties can be EOAs, smart contracts or Juicebox projects.

### PaymentProcessor

This contract is meant to be a proxy that receives payments and forwards them to the pre-configured Juicebox project. The proxy can accept payment in ERC20 tokens and optionally liquidate them. The proxy also optionally allows payment in case of project misconfiguration.

### TokenLiquidator

This contract integrates with Uniswap to allow seamless liquidation of tokens into WETH or Ether which is then forwarded to a Juicebox terminal. The contract is generic, meaning that a project doesn't need to deploy their own copy of it. Liquidation happens via `liquidateTokens` called by the token holder. This contract has a fee mechanism where a small portion of the proceeds is sent to the platform.

To pay into a project using tokens call `liquidateTokens` with the following arguments:

- token: ERC20 address.
- amount: Token amount to pay.
- minValue: Minimum liquidation value. To sell at "market" price, set this to 0.
- jbxProjectId: Juicebox project to pay into.
- beneficiary: Beneficiary address tha the project terminal will receive. This is used to possibly issue project tokens and most often is expected to be the same as msg.sender.
- memo: Contribution memo text, a Juicebox terminal parameter, can be blank.
- metadata: Contribution metadata, a Juicebox terminal parameter, can be blank.

The contract will attempt to pay into the project with Ether or with WETH, depending on what kind of terminal the project exposes. The operation will fail otherwise. Payment happens via the terminal's pay function which may issue project tokens or other assets to the beneficiary address.

### Vest Tokens

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