// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IJBPaymentTerminal} from "./IJBPaymentTerminal.sol";
import {IJBRedeemHook} from "../IJBRedeemHook.sol";
import {JBDidRedeemData} from "../../structs/JBDidRedeemData.sol";

interface IJBRedemptionTerminal is IJBPaymentTerminal {
    event RedeemTokens(
        uint256 indexed rulesetConfiguration,
        uint256 indexed fundingCycleNumber,
        uint256 indexed projectId,
        address holder,
        address beneficiary,
        uint256 tokenCount,
        uint256 reclaimedAmount,
        bytes metadata,
        address caller
    );

    event HookDidRedeem(
        IJBRedeemHook indexed delegate,
        JBDidRedeemData data,
        uint256 delegatedAmount,
        uint256 fee,
        address caller
    );

    function redeemTokensOf(
        address holder,
        uint256 projectId,
        address token,
        uint256 count,
        uint256 minReclaimed,
        address payable beneficiary,
        bytes calldata metadata
    ) external returns (uint256 reclaimAmount);
}
