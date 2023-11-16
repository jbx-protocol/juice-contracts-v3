// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IJBTerminal} from "./IJBTerminal.sol";
import {JBFee} from "../../structs/JBFee.sol";

interface IJBFeeTerminal is IJBTerminal {
    event HoldFee(
        uint256 indexed projectId,
        uint256 indexed amount,
        uint256 indexed fee,
        address beneficiary,
        address caller
    );

    event ProcessFee(
        uint256 indexed projectId,
        uint256 indexed amount,
        bool indexed wasHeld,
        address beneficiary,
        address caller
    );

    event RefundHeldFees(
        uint256 indexed projectId,
        uint256 indexed amount,
        uint256 indexed refundedFees,
        uint256 leftoverAmount,
        address caller
    );
    event SetFeelessAddress(address indexed addrs, bool indexed flag, address caller);

    event FeeReverted(
        uint256 indexed projectId,
        uint256 indexed feeProjectId,
        uint256 amount,
        bytes reason,
        address caller
    );

    function FEE() external view returns (uint256);

    function heldFeesOf(uint256 projectId) external view returns (JBFee[] memory);

    function isFeelessAddress(address account) external view returns (bool);

    function processFees(uint256 projectId, address token) external;

    function setFeelessAddress(address account, bool flag) external;
}
