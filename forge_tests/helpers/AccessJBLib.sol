// SPDX-License-Identifier: MIT
pragma solidity ^0.8.6;

import {JBCurrencyIds} from "@juicebox/libraries/JBCurrencyIds.sol";
import {JBConstants} from "@juicebox/libraries/JBConstants.sol";
import {JBTokenList} from "@juicebox/libraries/JBTokenList.sol";
import {JBSplitGroupIds} from "@juicebox/libraries/JBSplitGroupIds.sol";

contract AccessJBLib {
    function NATIVE() external pure returns (uint256) {
        return JBCurrencyIds.NATIVE;
    }

    function USD() external pure returns (uint256) {
        return JBCurrencyIds.USD;
    }

    function NativeToken() external pure returns (address) {
        return JBTokenList.Native;
    }

    function MAX_FEE() external pure returns (uint256) {
        return JBConstants.MAX_FEE;
    }

    function MAX_RESERVED_RATE() external pure returns (uint256) {
        return JBConstants.MAX_RESERVED_RATE;
    }

    function MAX_REDEMPTION_RATE() external pure returns (uint256) {
        return JBConstants.MAX_REDEMPTION_RATE;
    }

    function MAX_DECAY_RATE() external pure returns (uint256) {
        return JBConstants.MAX_DECAY_RATE;
    }

    function SPLITS_TOTAL_PERCENT() external pure returns (uint256) {
        return JBConstants.SPLITS_TOTAL_PERCENT;
    }
}
