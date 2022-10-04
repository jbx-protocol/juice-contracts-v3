# NFT Features

This is a collection of contracts for publishing ERC721 NFTs with additional functionality for pricing and sales. The contract (ERC721FU.sol) is based on the Rari Capital ERC721 implementation but removes the constructor to enable upgradeability. BaseNFT.sol extends that functionality with Juicebox integration, basic pricing and distribution features. The simplest functionality is implemented in NFToken.sol

Contracts in this section are (alphabetically):

- components/BaseNFT - Abstract opinionated ERC721 functionality with Juicebox integration.
- components/ERC721FU - Abstract baseline ERC721 functionality.
- [BalancePriceResolver](#balancepriceresolver) - NFT pricing contract based on address balance.
- [DutchActionMachine](#dutchactionmachine) - Perpetual NFT minting Dutch auction.
- [EnglishAuctionMachine](#englishauctionmachine) - Perpetual NFT minting English auction.
- [NFToken](#nftoken) - Deployable NFT contract.
- [NFUToken](#nfutoken) - Deployable, upgradeable NFT contract.
- [SupplyPriceResolver](#supplypriceresolver) - NFT pricing contract based on total supply.

## NFToken

The constructor takes several parameters.

- name: Name of the token.
- symbol: Token symbol.
- baseUri: Token asset base uri.
- contractUri: OpenSea-compatible metadata uri.
- jbxProjectId: Juicebox project id that will receive initial sale proceeds.
- jbxDirectory: Juicebox directory contract to get Terminal information for proceeds distribution.
- maxSupply: Supply cap.
- unitPrice: Base NFT mint price.
- mintAllowance: Per-address mint allowance.
- mintPeriodStart: Mint period start time stamp expressed in seconds. Can be set to 0 to allow immediate minting.
- mintPeriodEnd: Mint period end time stamp expressed in seconds. Can be set to 0 for an unbounded minting period.

This contract supports several common ERC standards: ERC721, ERC165, EIP2981.

It is possible to set royalty information after contract deployment. This is done with `setRoyalties(address _royaltyReceiver, uint16 _royaltyRate)`. This method is gated with OpenZeppelin AccessControl for `DEFAULT_ADMIN_ROLE`. The first parameter must be an EOA or a payable contract. Consider using a deployment of `MixedPaymentSplitter` to pay multiple collaborators. The second parameter is royalty rate expressed as basis points where 10,000 is 100%. The `royaltyInfo(uint256 _tokenId, uint256 _salePrice)` view returns the actual royalty being collected and the address where it should be sent.

In addition to setting a bounded mint period, which can be modified after deployment with `updateMintPeriod(uint128 _mintPeriodStart, uint128 _mintPeriodEnd)`, it's possible to implement a simple "reveal" mechanic with this contract. `setBaseURI(string memory _baseUri, bool _reveal)`. On deployment the internal reveal flag is set to false. This causes `tokenURI(uint256 _tokenId)` to return base uri value without modification. The deployment value of base uri can then be used as a placeholder. Calling setBaseURI with reveal true will then append the token id to the base uri in the `tokenURI` view. Reveal can be set only once. There is a role, `REVEALER_ROLE`, that is allowed to perform this operation.

It's possible to store a provenance hash in the contract. It can be set only once using `setProvenanceHash(string memory _provenanceHash)`.

By default token mint price is the value of unitPrice set in the constructor. It can be changed with `updateUnitPrice(uint256 _unitPrice)` at any time to any value by a caller with the `DEFAULT_ADMIN_ROLE` permission. For advanced pricing calculation there is an option to associate a price resolver contract. This is done with `updatePriceResolver(INFTPriceResolver _priceResolver)`. Several sample implementations are provided, They are described in detail below. It is possible to set price resolver to `address(0)`. If the token is to have perpetual free mints setting both price resolver and unitPrice to 0 is the most cost-effective way to do it.

Several other features are available. `setContractURI(string memory _contractUri)` can change the OpenSea metadata uri. Mint can be paused and resumed with `setPause(bool pause)`. `mintFor(address _account)` is an admin mint function gated with `MINTER_ROLE` role that allows unbounded mints to arbitrary accounts limited only by maxSupply. Minters can be added and removed by an account with `DEFAULT_ADMIN_ROLE` permission using `addMinter(address _account)` and `removeMinter(address _account)`. These two functions are used by the "Auction Machine" contracts described below. Lastly there is a function to recover ERC20 token balances – `transferTokenBalance(IERC20 token, address to, uint256 amount)`.

The `mint` functions require payment.

## NFUToken

This contract is exactly like NFToken, but instead of a constructor collects parameters via an initializer function. U is for Upgradeable.

## SupplyPriceResolver

This contract can be used together with an NFT contract to generate the mint price based on current NFT supply. The contract accepts a multiplier which increases the price for each tier defined up to a certain price cap. This increase can be linear or exponential.

Note that the per-user mint limit is enforced in NFToken, not in this price resolver.

The constructor arguments are as follows.

- basePrice: Minimum price to return.
- multiplier: Price multiplier.
- tierSize: Number of tokens per price tier. Crossing the boundary increases the price.
- priceCap: Maximum price to return.
- priceFunction: Values are LINEAR, EXP and CONSTANT.

The contract is immutable, parameters cannot be changed after deployment. `NFToken` and related contracts will call the `getPrice(address _token, address, uint256)` and `getPriceWithParams(address _token, address _minter, uint256 _tokenid, bytes calldata)` views. In this implementation the latter simply calls the former.

`getPrice` will get the current token supply, hence the contract name, determine the price tier by dividing the supply by `tierSize` set in the constructor. The returned value will be at least `basePrice` and at most `priceCap`. If the `priceFunction` is "LINEAR" then the price will always be `basePrice`. If it's "LINEAR", current tier is multiplied by `multiplier` and then basePrice. If it is "EXP", `multiplier` will be raised to the power of current tier and then multiplied by `basePrice`.

## BalancePriceResolver

This contract calculates the NFT mint price based on the user's current NFT balance. It has options to allow for free initial, subsequent or repeated mints. It's based on `SupplyPriceResolver` and inherits the tier-based pricing functions if the per-user mint conditions are not met.

Note that the per-user mint limit is enforced in NFToken, not in this price resolver.

The constructor parameters introduces here in addition to what `SupplyPriceResolver` already has are:

- freeSample: First mint free flag.
- nthFree: Allows every nth mint to be free. Should be set to 0 to remove this functionality.
- freeMintCap: Limits the number of free mints if `nthFree` is set.

This contract will get the minter's current token balance based on parameters passed to `getPrice()` and make a price determination. If the current balance is 0 and `freeSample` is set, the returned price will be 0. Beyond that if `nthFree` is set and the new mint operation results in user balance being a multiple of that and `freeMintCap` has not been reached, the price will also be 0. Logically this is `freeMintCap > 0 && minterBalance + 1 <= nthFree * freeMintCap`.

The functionality is built on top of the `SupplyPriceResolver` and if the initial conditions are not met the logic of that contract will be applied.

## MerklePriceResolver

Coming Soon™️.

## DutchActionMachine

This contract enables the perpetual Dutch auction function for the NFT contracts in this repo. This works by minting a new NFT against the specified contract and then accepting bids for it until the auction ends. At this point, if there is a valid bid, the contract will send the NFT to the bidder, if not it will retain the NFT and mint a new one and start the new auction. All this actions happen on `bid()` call. To bootstrap the process, whoever deploys the contract can simply call bid with 0 Ether. Retained NFTs can be transferred out by the admin by calling `recoverToken(address _account, uint256 _tokenId)`.

The constructor parameters are as follows.

- maxAuctions: Maximum number of auctions to perform automatically, 0 for no limit. Note this cannot be changed after deployment, but multiple auction machine contracts can be deployed for the same NFT contract.
- auctionDuration: Auction duration in seconds.
- periodDuration: Price reduction period in seconds.
- maxPriceMultiplier: Starting price multiplier. Token unit price is multiplied by this value to become the auction starting price.
- projectId: Juicebox project id, used to transfer auction proceeds.
- jbxDirectory: Juicebox directory, used to transfer auction proceeds to the correct terminal.
- token: Token contract to operate on.

This contract expect to work with NFToken and NFUToken contracts, but it will be compatible with other contracts as long as it supports the following functions:

- `mintFor(address) => uint256`: This will be called by the auction machine to get a new token to offer for sale. NFToken contract has a minter role that must be granted to the auction machine.
- `unitPrice() => uint256`: This will be called to set the auction reserve price. transferFrom will be called to transfer the token to the auction winner if any.
- `function transferFrom(address, address, uint256)`: Standard ERC721/1155 transfer function.

## EnglishAuctionMachine

This contract enables the perpetual English auction function for the NFT contracts in this repo. This is the same concept as the DutchActionMachine but sells a token for an increasing price rather than accepting decreasing bids.

The constructor parameters are as follows.

- maxAuctions: Maximum number of auctions to perform automatically, 0 for no limit.
- auctionDuration: Auction duration in seconds.
- projectId: Juicebox project id, used to transfer auction proceeds.
- jbxDirectory: Juicebox directory, used to transfer auction proceeds to the correct terminal.
- token: Token contract to operate on.
