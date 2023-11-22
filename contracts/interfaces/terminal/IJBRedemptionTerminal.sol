// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IJBPaymentTerminal} from "./IJBPaymentTerminal.sol";
import {IJBRedemptionDelegate3_1_1} from "../IJBRedemptionDelegate3_1_1.sol";
import {JBDidRedeemData3_1_1} from "../../structs/JBDidRedeemData3_1_1.sol";

interface IJBRedemptionTerminal is IJBPaymentTerminal {
    event RedeemTokens(
        uint256 indexed fundingCycleConfiguration,
        uint256 indexed fundingCycleNumber,
        uint256 indexed projectId,
        address holder,
        address beneficiary,
        uint256 tokenCount,
        uint256 reclaimedAmount,
        bytes metadata,
        address caller
    );

    event DelegateDidRedeem(
        IJBRedemptionDelegate3_1_1 indexed delegate,
        JBDidRedeemData3_1_1 data,
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
