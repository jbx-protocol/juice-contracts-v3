# NFT Auctions

These contracts allow for creation of ERC721 auctions where proceeds from the auction will be paid to a collection of JBSplit objects. The contracts are intended to be deployed at platform level where the primary platform project would keep the fee from the auction sale. However 3rd party deployments are also possible. Fee would go to a Juicebox terminal via `addToBalanceOf`. It is possible to deploy the either contract with a fee of 0.

## DutchAuction

Allows listing NFTs with a starting price, an ending price and an auction duration. This auction type expects bidders to place decreasing bids. It is possible to set a lower bid than the current price to "reserve" your place for the case where the price decreases to that point. When settling an auction, the contract will send the sale proceeds to the listing party, the NFT to the buyer and a commission to a Juicebox project. The commission rate is configurable and capped at 10%. It is possible to perform the auction settlement trustlessly.

The contract uses the initializer pattern with the following parameters:

- projectId: Project that manages this auction contract.
- feeReceiver: An instance of IJBPaymentTerminal which will get auction fees.
- feeRate: Fee percentage expressed in terms of JBConstants.SPLITS_TOTAL_PERCENT (1000000000).
- allowPublicAuctions: A flag to allow anyone to create an auction on this contract rather than only accounts with the `AUTHORIZED_SELLER_ROLE` permission.
- periodDuration: Number of seconds for each pricing period.
- owner: Contract admin if, should be msg.sender or another address.
- directory: JBDirectory instance to enable JBX integration.

Pricing period above is used as an interval where item price drops. Meaning that for every N seconds the price at which the auction can be closed reduces by some amount.

After deployment it's possible to modify the allowPublicAuctions flag via `setAllowPublicAuctions`.

### Creating Dutch Auctions

Call `create` to start an auction and pass the following arguments:

- collection: ERC721 contract.
- item: Token id to list.
- startingPrice: Starting price for the auction from which it will drop.
- endingPrice: Minimum price for the auction at which it will end at expiration time.
- duration: Auction duration in seconds.
- saleSplits: Juicebox splits collection that will receive auction proceeds.
- memo: Memo to publish in the auction creation event.

The auction starts immediately on successful execution of this function. Ownership of the NFT being sold will be transferred to the auction contract. The auction duration is a number of seconds from `deploymentOffset` of the contract, a public property. This is done to save some storage cost. The price drop amount is calculated automatically as the difference between starting and ending prices divided by the number of periods, duration of which is defined in the initializer and shared across all auctions, between "now" and `expiration`.

Creating an auction fires the `CreateDutchAuction` event. There is no internal auction index, it is expected that auction state would be picked up from events. There is a public `auctions` map where the key is defined as `keccak256(abi.encodePacked(address(collection), item))`.

Note that improperly configured splits, for example attempting to send Ether to a project with a misconfigured terminal, will prevent auction settlement. To mitigate this an `updateAuctionSplits` function is present that can be called by the auction creator.

### Bidding on and ending Dutch Auctions

This auction contract will accept the highest bid for an item as long as it is above the ending price. Meaning that interested parties can register their interest before the price is at the bid amount. If this happens, the auction still needs to be settled manually when enough periods pass to hit the desired price. To get the current price call `currentPrice(IERC721 collection, uint256 item)`. This method will calculate the number of elapsed periods and return the reduced item price accordingly. Place bids by calling `bid(IERC721 collection, uint256 item, string calldata _memo)` which will generate an event, `PlaceBid`, with the provided arguments.

Dutch auctions can be settled ahead of expiration if the required price is met.

Auction settlement is trustless and is performed by `settle(IERC721 collection, uint256 item, string calldata _memo)`. The last parameter is optional text that would get published with the settlement event (`ConcludeAuction`).

### Other Methods

Contract admin can execute several functions to manage the authorized sellers list with `addAuthorizedSeller` and `removeAuthorizedSeller`. They can also change the fee receiver with `setFeeReceiver`. This is in addition to `setAllowPublicAuctions` described above.

## EnglishAuction

Allows listing NFTs with a starting price, a reserve price and an auction duration. This auction type expects bidders to place increasing bids. When settling an auction, the contract will send the sale proceeds to the listing party, the NFT to the buyer and a commission to a Juicebox project. The commission rate is configurable and capped at 10%. It is possible to perform the auction settlement trustlessly. Contracts in this section are designed to be as functionally similar as possible and with the exception of auction-specific mechanics they work in a similar fashion firing similar events.

The contract uses the initializer pattern with the following parameters:

- projectId: Project that manages this auction contract.
- feeReceiver: An instance of IJBPaymentTerminal which will get auction fees.
- feeRate: Fee percentage expressed in terms of JBConstants.SPLITS_TOTAL_PERCENT (1000000000).
- allowPublicAuctions: A flag to allow anyone to create an auction on this contract rather than only accounts with the `AUTHORIZED_SELLER_ROLE` permission.
- owner: Contract admin if, should be msg.sender or another address.
- directory: JBDirectory instance to enable JBX integration.

### Creating English Auctions

Call `create` to start an auction and pass the following arguments:

- collection: ERC721 contract.
- item: Token id to list.
- startingPrice: Minimum auction price. 0 is a valid price.
- reservePrice: Reserve price at which the item will be sold once the auction expires. Below this price, the item will be returned to the seller.
- expiration: Seconds, offset from deploymentOffset, at which the auction concludes.
- saleSplits: Juicebox splits collection that will receive auction proceeds.
- memo: Memo to publish in the auction creation event.

The auction starts immediately on successful execution of this function. Ownership of the NFT being sold will be transferred to the auction contract. The auction duration is a number of seconds from `deploymentOffset` of the contract, a public property. This is done to save some storage cost. This contract accepts increasing item bids up until auction expiration.

Creating an auction fires the `CreateEnglishAuction` event. There is no internal auction index, it is expected that auction state would be picked up from events. There is a public `auctions` map where the key is defined as `keccak256(abi.encodePacked(address(collection), item))`.

Note that improperly configured splits, for example attempting to send Ether to a project with a misconfigured terminal, will prevent auction settlement. To mitigate this an `updateAuctionSplits` function is present that can be called by the auction creator.

### Bidding on and ending English Auctions

A bid will be placed successfully by calling `bid(IERC721 collection, uint256 item, string calldata _memo)` if the auction is still in progress and the new bid is higher than the current bid. The contract only stores the highest bid and automatically refunds the previous bidder in case they are outbid.

Auction settlement is trustless and is performed by `settle(IERC721 collection, uint256 item, string calldata _memo)`. The last parameter is optional text that would get published with the settlement event (`ConcludeAuction`).

### Other Functions

Contract admin can execute several functions to manage the authorized sellers list with `addAuthorizedSeller` and `removeAuthorizedSeller`. They can also change the fee receiver with `setFeeReceiver`. This is in addition to `setAllowPublicAuctions` described above.
