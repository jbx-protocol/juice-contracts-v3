// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import {JBPayDelegateAllocation} from "./../structs/JBPayDelegateAllocation.sol";
import {JBPayParamsData} from "./../structs/JBPayParamsData.sol";
import {JBRedeemParamsData} from "./../structs/JBRedeemParamsData.sol";
import {JBRedeemDelegateAllocation} from "./../structs/JBRedeemDelegateAllocation.sol";

/// @title Datasource
/// @notice The datasource is called by JBPayoutRedemptionPaymentTerminals on pay and redemption, and provide an extra layer of logic to use a custom weight, a custom memo and/or a pay/redeem delegate
interface IJBRulesetDataSource is IERC165 {
    /// @notice The datasource implementation for JBPaymentTerminal.pay(...)
    /// @param data the data passed to the data source in terminal.pay(...), as a JBPayParamsData struct:
    /// @return weight the weight to use to override the ruleset weight
    /// @return delegateAllocations The amount to send to delegates instead of adding to the local balance.
    function payParams(JBPayParamsData calldata data)
        external
        view
        returns (uint256 weight, JBPayDelegateAllocation[] memory delegateAllocations);

    /// @notice The datasource implementation for JBPaymentTerminal.redeemTokensOf(...)
    /// @param data the data passed to the data source in terminal.redeemTokensOf(...), as a JBRedeemParamsData struct:
    /// @return reclaimAmount The amount to claim, overriding the terminal logic.
    /// @return delegateAllocations The amount to send to delegates instead of adding to the beneficiary.
    function redeemParams(JBRedeemParamsData calldata data)
        external
        view
        returns (uint256 reclaimAmount, JBRedeemDelegateAllocation[] memory delegateAllocations);
}
