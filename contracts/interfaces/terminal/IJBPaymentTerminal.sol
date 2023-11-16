// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IJBTerminal} from "./IJBTerminal.sol";
import {IJBPayDelegate3_1_1} from "../IJBPayDelegate3_1_1.sol";
import {JBDidPayData3_1_1} from "../../structs/JBDidPayData3_1_1.sol";

interface IJBPaymentTerminal is IJBTerminal {
    event Pay(
        uint256 indexed fundingCycleConfiguration,
        uint256 indexed fundingCycleNumber,
        uint256 indexed projectId,
        address payer,
        address beneficiary,
        uint256 amount,
        uint256 beneficiaryTokenCount,
        string memo,
        bytes metadata,
        address caller
    );

    event DelegateDidPay(
        IJBPayDelegate3_1_1 indexed delegate,
        JBDidPayData3_1_1 data,
        uint256 delegatedAmount,
        address caller
    );

    function pay(
        uint256 projectId,
        address token,
        uint256 amount,
        address beneficiary,
        uint256 minReturnedTokens,
        string calldata memo,
        bytes calldata metadata
    ) external payable returns (uint256 beneficiaryTokenCount);
}
