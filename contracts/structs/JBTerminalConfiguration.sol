// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IJBPaymentTerminal} from './../interfaces/IJBPaymentTerminal.sol';
import {JBAccountingContext} from './JBAccountingContext.sol';

/// @custom:member terminal The terminal to configure.
/// @custom:member accountingContexts The token accounting contexts to configure the terminal with.
struct JBTerminalConfiguration {
  IJBPaymentTerminal terminal;
  JBAccountingContext[] accountingContexts;
}
