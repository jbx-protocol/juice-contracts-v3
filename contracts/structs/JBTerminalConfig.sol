// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IJBPaymentTerminal} from './../interfaces/IJBPaymentTerminal.sol';
import {JBAccountingContextConfig} from './JBAccountingContextConfig.sol';

/// @custom:member terminal The terminal to configure.
/// @custom:member accountingContextConfigs The token accounting contexts to configure the terminal with.
struct JBTerminalConfig {
  IJBPaymentTerminal terminal;
  JBAccountingContextConfig[] accountingContextConfigs;
}
