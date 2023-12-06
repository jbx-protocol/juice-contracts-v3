// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";
import {IJBPriceFeed} from "./interfaces/IJBPriceFeed.sol";
import {JBFixedPointNumber} from "./libraries/JBFixedPointNumber.sol";

/// @notice A generalized price feed for the Chainlink AggregatorV3Interface.
contract JBChainlinkV3PriceFeed is IJBPriceFeed {
    // A library that provides utility for fixed point numbers.
    using JBFixedPointNumber for uint256;

    //*********************************************************************//
    // --------------------------- custom errors ------------------------- //
    //*********************************************************************//
    error STALE_PRICE();
    error INCOMPLETE_ROUND();
    error NEGATIVE_PRICE();

    //*********************************************************************//
    // ---------------- public stored immutable properties --------------- //
    //*********************************************************************//

    /// @notice The feed that prices are reported from.
    AggregatorV3Interface public immutable feed;

    //*********************************************************************//
    // ------------------------- external views -------------------------- //
    //*********************************************************************//

    /// @notice Gets the current price (per unit) from the feed, normalized to the specified number of decimals.
    /// @param _decimals The number of decimals the returned fixed point price should include.
    /// @return The current price of the feed, as a fixed point number with the specified number of decimals.
    function currentUnitPrice(uint256 _decimals) external view override returns (uint256) {
        // Get the latest round information.
        (uint80 roundId, int256 _price,, uint256 updatedAt, uint80 answeredInRound) = feed.latestRoundData();

        // Make sure the price isn't stale.
        if (answeredInRound < roundId) revert STALE_PRICE();

        // Make sure the round is finished.
        if (updatedAt == 0) revert INCOMPLETE_ROUND();

        // Make sure the price is positive.
        if (_price < 0) revert NEGATIVE_PRICE();

        // Get a reference to the number of decimals the feed uses.
        uint256 _feedDecimals = feed.decimals();

        // Return the price, adjusted to the target decimals.
        return uint256(_price).adjustDecimals(_feedDecimals, _decimals);
    }

    //*********************************************************************//
    // -------------------------- constructor ---------------------------- //
    //*********************************************************************//

    /// @param _feed The feed to report prices from.
    constructor(AggregatorV3Interface _feed) {
        feed = _feed;
    }
}
