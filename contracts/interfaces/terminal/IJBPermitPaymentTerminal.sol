// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IJBPaymentTerminal} from "./IJBPaymentTerminal.sol";
import {IPermit2} from "@permit2/src/src/interfaces/IPermit2.sol";

interface IJBPermitPaymentTerminal is IJBPaymentTerminal {
    function PERMIT2() external returns (IPermit2);
}
