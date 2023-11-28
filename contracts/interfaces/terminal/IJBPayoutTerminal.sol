// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IJBPaymentTerminal} from "./IJBPaymentTerminal.sol";
import {JBSplit} from "../../structs/JBSplit.sol";
import {IJBSplits} from "../IJBSplits.sol";

interface IJBPayoutTerminal is IJBPaymentTerminal {
    event DistributePayouts(
        uint256 indexed rulesetConfiguration,
        uint256 indexed fundingCycleNumber,
        uint256 indexed projectId,
        address beneficiary,
        uint256 amount,
        uint256 distributedAmount,
        uint256 fee,
        uint256 beneficiaryDistributionAmount,
        address caller
    );

    event DistributeToPayoutSplit(
        uint256 indexed projectId,
        uint256 indexed domain,
        uint256 indexed group,
        JBSplit split,
        uint256 amount,
        uint256 netAmount,
        address caller
    );

    event UseAllowance(
        uint256 indexed rulesetConfiguration,
        uint256 indexed fundingCycleNumber,
        uint256 indexed projectId,
        address beneficiary,
        uint256 amount,
        uint256 distributedAmount,
        uint256 netDistributedamount,
        string memo,
        address caller
    );

    event PayoutReverted(
        uint256 indexed projectId, JBSplit split, uint256 amount, bytes reason, address caller
    );

    function distributePayoutsOf(
        uint256 projectId,
        address token,
        uint256 amount,
        uint256 currency,
        uint256 minReturnedTokens
    ) external returns (uint256 netLeftoverDistributionAmount);

    function useAllowanceOf(
        uint256 projectId,
        address token,
        uint256 amount,
        uint256 currency,
        uint256 minReturnedTokens,
        address payable beneficiary,
        string calldata memo
    ) external returns (uint256 netDistributedAmount);
}
