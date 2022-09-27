# NFT Features

This is a collection of contracts for publishing ERC721 NFTs with additional functionality for pricing and sales. The contract (ERC721FU.sol) is based on the Rari Capital ERC721 implementation but removes the constructor to enable upgradeability. BaseNFT.sol extends that functionality with Juicebox integration, basic pricing and distribution features. The simplest functionality is implemented in NFToken.sol

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

In addition to setting a bounded mint period, which can be modified after deployment with `updateMintPeriod(uint128 _mintPeriodStart, uint128 _mintPeriodEnd)`, it's possible to implement a simple "reveal" mechanic with this contract. `setBaseURI(string memory _baseUri, bool _reveal)`. On deployment the internal reveal flag is set to false. This causes `tokenURI(uint256 _tokenId)` to return base uri value without modification. The deployment value of base uri can then be used as a placeholder. Calling setBaseURI with reveal true will then append the token id to the base uri in the `tokenURI` view. Reveal can be set only once.

It's possible to store a provenance hash in the contract. It can be set only once using `setProvenanceHash(string memory _provenanceHash)`.

By default token mint price is the value of unitPrice set in the constructor. It can be changed with `updateUnitPrice(uint256 _unitPrice)` at any time to any value by a caller with the `DEFAULT_ADMIN_ROLE` permission. For advanced pricing calculation there is an option to associate a price resolver contract. This is done with `updatePriceResolver(INFTPriceResolver _priceResolver)`. Several sample implementations are provided, They are described in detail below.

Several other features are available. `setContractURI(string memory _contractUri)` can change the OpenSea metadata uri. Mint can be paused and resumed with `setPause(bool pause)`. `mintFor(address _account)` is an admin mint function gated with `MINTER_ROLE` role that allows unbounded mints to arbitrary accounts limited only by maxSupply. Minters can be added and removed by an account with `DEFAULT_ADMIN_ROLE` permission using `addMinter(address _account)` and `removeMinter(address _account)`. These two functions are used by the "Auction Machine" contracts described below. Lastly there is a function to recover ERC20 token balances – `transferTokenBalance(IERC20 token, address to, uint256 amount)`.

The `mint` functions require payment.

## NFUToken

This contract is exactly like NFToken, but instead of a constructor collects parameters via an initializer function. U is for Upgradeable.

## SupplyPriceResolver

This contract can be used together with an NFT contract to generate the mint price based on current NFT supply. The contract accepts a multiplier which increases the price for each tier defined up to a certain price cap. This increase can be linear or exponential.

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

The constructor parameters introduces here in addition to what `SupplyPriceResolver` already has are:

- freeSample: First mint free flag.
- nthFree: Allows every nth mint to be free. Should be set to 0 to remove this functionality.
- freeMintCap: Limits the number of free mints if `nthFree` is set.

This contract will get the minter's current token balance based on parameters passed to `getPrice()` and make a price determination. If the current balance is 0 and `freeSample` is set, the returned price will be 0. Beyond that if `nthFree` is set and the new mint operation results in user balance being a multiple of that and `freeMintCap` has not been reached, the price will also be 0. Logically this is `freeMintCap > 0 && minterBalance + 1 <= nthFree * freeMintCap`.

The functionality is built on top of the `SupplyPriceResolver` and if the initial conditions are not met the logic of that contract will be applied.

## MerklePriceResolver

Coming Soon™️.
