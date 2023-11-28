// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IJBProjects} from "../IJBProjects.sol";
import {IJBDirectory} from "../IJBDirectory.sol";
import {IJBTerminalStore} from "../IJBTerminalStore.sol";

import {IJBRedemptionTerminal} from "./IJBRedemptionTerminal.sol";
import {IJBPayoutTerminal} from "./IJBPayoutTerminal.sol";
import {IJBPaymentTerminal} from "./IJBPaymentTerminal.sol";
import {IJBFeeTerminal} from "./IJBFeeTerminal.sol";
import {IJBPermitPaymentTerminal} from "./IJBPermitPaymentTerminal.sol";
import {IJBSplits} from "../IJBSplits.sol";

interface IJBMultiTerminal is
    IJBPaymentTerminal,
    IJBFeeTerminal,
    IJBRedemptionTerminal,
    IJBPayoutTerminal,
    IJBPermitPaymentTerminal
{
    function STORE() external view returns (IJBTerminalStore);

    function PROJECTS() external view returns (IJBProjects);

    function DIRECTORY() external view returns (IJBDirectory);

    function SPLITS() external view returns (IJBSplits);
}
