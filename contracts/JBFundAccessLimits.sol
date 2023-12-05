// SPDX-License-Identifier: MIT
pragma solidity ^0.8.16;

import {ERC165} from "@openzeppelin/contracts/utils/introspection/ERC165.sol";
import {JBControlled} from "./abstract/JBControlled.sol";
import {IJBFundAccessLimits} from "./interfaces/IJBFundAccessLimits.sol";
import {IJBDirectory} from "./interfaces/IJBDirectory.sol";
import {JBFundAccessLimitGroup} from "./structs/JBFundAccessLimitGroup.sol";
import {JBCurrencyAmount} from "./structs/JBCurrencyAmount.sol";

/// @notice Stores and manages terminal fund access limits for each project.
/// @dev See the `JBFundAccessLimitGroup` struct to learn about payout limits and surplus payout limits.
contract JBFundAccessLimits is JBControlled, ERC165, IJBFundAccessLimits {
    //*********************************************************************//
    // --------------------------- custom errors ------------------------- //
    //*********************************************************************//

    error INVALID_PAYOUT_LIMIT();
    error INVALID_PAYOUT_LIMIT_CURRENCY();
    error INVALID_PAYOUT_LIMIT_CURRENCY_ORDERING();
    error INVALID_SURPLUS_PAYOUT_LIMIT();
    error INVALID_SURPLUS_PAYOUT_LIMIT_CURRENCY();
    error INVALID_SURPLUS_PAYOUT_LIMIT_CURRENCY_ORDERING();

    //*********************************************************************//
    // --------------------- internal stored properties ------------------ //
    //*********************************************************************//

    /// @notice A list of packed payout limits for a given project, ruleset, terminal, and token.
    /// @dev bits 0-223: The maximum amount (in a specific currency) of the terminal's `token`s that the project can pay out during the applicable ruleset.
    /// @dev bits 224-255: The currency that the payout limit is denominated in. If this currency is different from the terminal's `token`, the payout limit will vary depending on their exchange rate.
    /// @custom:param _projectId The ID of the project to get the packed payout limit data of.
    /// @custom:param _rulesetId The ID of the ruleset that the packed payout limit data applies to.
    /// @custom:param _terminal The terminal the payouts are being limited in.
    /// @custom:param _token The token payouts are being limited for.
    mapping(uint256 => mapping(uint256 => mapping(address => mapping(address => uint256[]))))
        internal _packedPayoutLimitsDataOf;

    /// @notice A list of packed surplus payout limits for a given project, ruleset, terminal, and token.
    /// @dev bits 0-223: The maximum amount (in a specific currency) of the terminal's `token`s that the project can access from its surplus during the applicable ruleset.
    /// @dev bits 224-255: The currency that the surplus payout limit is denominated in. If this currency is different from the terminal's `token`, the surplus payout limit will vary depending on their exchange rate.
    /// @custom:param _projectId The ID of the project to get the packed surplus payout limit data of.
    /// @custom:param _rulesetId The ID of the ruleset that the packed surplus payout limit data applies to.
    /// @custom:param _terminal The terminal the surplus payout limit comes from.
    /// @custom:param _token The token that the surplus payout limit applies to.
    mapping(uint256 => mapping(uint256 => mapping(address => mapping(address => uint256[]))))
        internal _packedSurplusPayoutLimitsDataOf;

    //*********************************************************************//
    // ------------------------- external views -------------------------- //
    //*********************************************************************//

    /// @notice A project's payout limits for a given ruleset, terminal, and token.
    /// @notice The total value of `_token`s that a project can pay out from the terminal during the ruleset is dictated by a list of payout limits. Each payout limit is in terms of its own amount and currency.
    /// @dev The fixed point `amount`s of the returned structs will have the same number of decimals as the specified terminal.
    /// @param _projectId The ID of the project to get the payout limits of.
    /// @param _rulesetId The ID of the ruleset the payout limits apply to.
    /// @param _terminal The terminal the payout limits apply to.
    /// @param _token The token the payout limits apply to.
    /// @return payoutLimits The payout limits.
    function payoutLimitsOf(
        uint256 _projectId,
        uint256 _rulesetId,
        address _terminal,
        address _token
    ) external view override returns (JBCurrencyAmount[] memory payoutLimits) {
        // Get a reference to the packed data.
        uint256[] memory _packedPayoutLimitsData =
            _packedPayoutLimitsDataOf[_projectId][_rulesetId][_terminal][_token];

        // Get a reference to the number of payout limits.
        uint256 _numberOfData = _packedPayoutLimitsData.length;

        // Initialize the return value.
        payoutLimits = new JBCurrencyAmount[](_numberOfData);

        // Keep a reference to the data that'll be iterated.
        uint256 _packedPayoutLimitData;

        // Iterate through the stored packed values and format the returned value.
        for (uint256 _i; _i < _numberOfData;) {
            // Set the data being iterated on.
            _packedPayoutLimitData = _packedPayoutLimitsData[_i];

            // The limit amount is in bits 0-231. The currency is in bits 224-255.
            payoutLimits[_i] = JBCurrencyAmount({
                currency: _packedPayoutLimitData >> 224,
                amount: uint256(uint224(_packedPayoutLimitData))
            });

            unchecked {
                ++_i;
            }
        }
    }

    /// @notice A project's payout limit for a specific currency and a given ruleset, terminal, and token.
    /// @dev The fixed point amount returned will have the same number of decimals as the specified terminal.
    /// @param _projectId The ID of the project to get the payout limit of.
    /// @param _rulesetId The ID of the ruleset the payout limit applies to.
    /// @param _terminal The terminal the payout limit applies to.
    /// @param _token The token the payout limit applies to.
    /// @param _currency The currency the payout limit is denominated in.
    /// @return payoutLimit The payout limit, as a fixed point number with the same number of decimals as the provided terminal.
    function payoutLimitOf(
        uint256 _projectId,
        uint256 _rulesetId,
        address _terminal,
        address _token,
        uint256 _currency
    ) external view override returns (uint256 payoutLimit) {
        // Get a reference to the packed data.
        uint256[] memory _data =
            _packedPayoutLimitsDataOf[_projectId][_rulesetId][_terminal][_token];

        // Get a reference to the number of payout limits.
        uint256 _numberOfData = _data.length;

        // Keep a reference to the data that'll be iterated.
        uint256 _packedPayoutLimitData;

        // Iterate through the stored packed values and return the value of the matching currency.
        for (uint256 _i; _i < _numberOfData;) {
            // Set the data being iterated on.
            _packedPayoutLimitData = _data[_i];

            // If the currencies match, return the value.
            if (_currency == _packedPayoutLimitData >> 224) {
                return uint256(uint224(_packedPayoutLimitData));
            }

            unchecked {
                ++_i;
            }
        }
    }

    /// @notice A project's surplus payout limits for a given ruleset, terminal, and token.
    /// @notice The total value of `_token`s that a project can pay out from its surplus in a terminal during the ruleset is dictated by a list of surplus payout limits. Each surplus payout limit is in terms of its own amount and currency.
    /// @dev The number of decimals in the returned fixed point amount is the same as that of the specified terminal.
    /// @param _projectId The ID of the project to get the surplus payout limits of.
    /// @param _rulesetId The ID of the ruleset the surplus payout limits applies to.
    /// @param _terminal The terminal the surplus payout limits applies to.
    /// @param _token The token the surplus payout limits applies to.
    /// @return surplusPayoutLimits The surplus payout limits.
    function surplusPayoutLimitsOf(
        uint256 _projectId,
        uint256 _rulesetId,
        address _terminal,
        address _token
    ) external view override returns (JBCurrencyAmount[] memory surplusPayoutLimits) {
        // Get a reference to the packed data.
        uint256[] memory _packedSurplusPayoutLimitsData =
            _packedSurplusPayoutLimitsDataOf[_projectId][_rulesetId][_terminal][_token];

        // Get a reference to the number of surplus payout limits.
        uint256 _numberOfData = _packedSurplusPayoutLimitsData.length;

        // Initialize the return value.
        surplusPayoutLimits = new JBCurrencyAmount[](_numberOfData);

        // Keep a reference to the data that'll be iterated.
        uint256 _packedSurplusPayoutLimitData;

        // Iterate through the stored packed values and format the returned value.
        for (uint256 _i; _i < _numberOfData;) {
            // Set the data being iterated on.
            _packedSurplusPayoutLimitData = _packedSurplusPayoutLimitsData[_i];

            // The limit is in bits 0-223. The currency is in bits 224-255.
            surplusPayoutLimits[_i] = JBCurrencyAmount({
                currency: _packedSurplusPayoutLimitData >> 224,
                amount: uint256(uint224(_packedSurplusPayoutLimitData))
            });

            unchecked {
                ++_i;
            }
        }
    }

    /// @notice A project's surplus payout limit for a specific currency and a given ruleset, terminal, and token.
    /// @dev The fixed point amount returned will have the same number of decimals as the specified terminal.
    /// @param _projectId The ID of the project to get the surplus payout limit of.
    /// @param _rulesetId The ID of the ruleset the surplus payout limit applies to.
    /// @param _terminal The terminal the surplus payout limit applies to.
    /// @param _token The token the surplus payout limit applies to.
    /// @param _currency The currency that the surplus payout limit is denominated in.
    /// @return surplusPayoutLimit The surplus payout limit, as a fixed point number with the same number of decimals as the provided terminal.
    function surplusPayoutLimitOf(
        uint256 _projectId,
        uint256 _rulesetId,
        address _terminal,
        address _token,
        uint256 _currency
    ) external view override returns (uint256 surplusPayoutLimit) {
        // Get a reference to the packed data.
        uint256[] memory _data =
            _packedSurplusPayoutLimitsDataOf[_projectId][_rulesetId][_terminal][_token];

        // Get a reference to the number of surplus payout limits.
        uint256 _numberOfData = _data.length;

        // Keep a reference to the data that'll be iterated.
        uint256 _packedSurplusPayoutLimitData;

        // Iterate through the stored packed values and format the returned value.
        for (uint256 _i; _i < _numberOfData;) {
            // Set the data being iterated on.
            _packedSurplusPayoutLimitData = _data[_i];

            // If the currencies match, return the value.
            if (_currency == _packedSurplusPayoutLimitData >> 224) {
                return uint256(uint224(_packedSurplusPayoutLimitData));
            }

            unchecked {
                ++_i;
            }
        }
    }

    //*********************************************************************//
    // -------------------------- constructor ---------------------------- //
    //*********************************************************************//

    /// @param _directory A contract storing directories of terminals and controllers for each project.
    // solhint-disable-next-line no-empty-blocks
    constructor(IJBDirectory _directory) JBControlled(_directory) {}

    //*********************************************************************//
    // --------------------- external transactions ----------------------- //
    //*********************************************************************//

    /// @notice Sets limits for the amount of funds a project can access from its terminals during a ruleset.
    /// @dev Only a project's current controller can set its fund access limits.
    /// @dev Payout limits and surplus payout limits must be specified in strictly increasing order (by currency) to prevent duplicates.
    /// @param _projectId The ID of the project whose fund access limits are being set.
    /// @param _rulesetId The ID of the ruleset that the limits will apply within.
    /// @param _fundAccessLimitGroup An array containing payout limits and surplus payout limits for each payment terminal. Amounts are fixed point numbers using the same number of decimals as the accompanying terminal.
    function setFundAccessLimitsFor(
        uint256 _projectId,
        uint256 _rulesetId,
        JBFundAccessLimitGroup[] calldata _fundAccessLimitGroup
    ) external override onlyController(_projectId) {
        // Save the number of limits.
        uint256 _numberOfFundAccessLimitGroups = _fundAccessLimitGroup.length;

        // Keep a reference to the fund access constraint being iterated on.
        JBFundAccessLimitGroup calldata _limits;

        // Set payout limits if there are any.
        for (uint256 _i; _i < _numberOfFundAccessLimitGroups;) {
            // Set the limits being iterated on.
            _limits = _fundAccessLimitGroup[_i];

            // Keep a reference to the number of payout limits.
            uint256 _numberOfPayoutLimits = _limits.payoutLimits.length;

            // Keep a reference to the payout limit being iterated on.
            JBCurrencyAmount calldata _payoutLimit;

            // Iterate through each payout limit to validate and store them.
            for (uint256 _j; _j < _numberOfPayoutLimits;) {
                // Set the payout limit being iterated on.
                _payoutLimit = _limits.payoutLimits[_j];

                // If payout limit amount is larger than 224 bits, revert.
                if (_payoutLimit.amount > type(uint224).max) {
                    revert INVALID_PAYOUT_LIMIT();
                }

                // If payout limit currency's index is larger than 32 bits, revert.
                if (_payoutLimit.currency > type(uint32).max) {
                    revert INVALID_PAYOUT_LIMIT_CURRENCY();
                }

                // Make sure the payout limits are passed in increasing order of currency to prevent duplicates.
                if (_j != 0 && _payoutLimit.currency <= _limits.payoutLimits[_j - 1].currency) {
                    revert INVALID_PAYOUT_LIMIT_CURRENCY_ORDERING();
                }

                // Set the payout limit if there is one.
                if (_payoutLimit.amount > 0) {
                    _packedPayoutLimitsDataOf[_projectId][_rulesetId][_fundAccessLimitGroup[_i]
                        .terminal][_fundAccessLimitGroup[_i].token].push(
                        _payoutLimit.amount | (_payoutLimit.currency << 224)
                    );
                }

                unchecked {
                    ++_j;
                }
            }

            // Keep a reference to the number of surplus payout limits.
            uint256 _numberOfSurplusPayoutLimits = _limits.surplusPayoutLimits.length;

            // Keep a reference to the surplus payout limits being iterated on.
            JBCurrencyAmount calldata _surplusPayoutLimit;

            // Iterate through each surplus payout limit to validate and store them.
            for (uint256 _j; _j < _numberOfSurplusPayoutLimits;) {
                // Set the payout limit being iterated on.
                _surplusPayoutLimit = _limits.surplusPayoutLimits[_j];

                // If surplus payout limit is larger than 224 bits, revert.
                if (_surplusPayoutLimit.amount > type(uint224).max) {
                    revert INVALID_SURPLUS_PAYOUT_LIMIT();
                }

                // If surplus payout limit currency value is larger than 32 bits, revert.
                if (_surplusPayoutLimit.currency > type(uint32).max) {
                    revert INVALID_SURPLUS_PAYOUT_LIMIT_CURRENCY();
                }

                // Make sure the surplus payout limits are passed in increasing order of currency to prevent duplicates.
                if (
                    _j != 0
                        && _surplusPayoutLimit.currency <= _limits.surplusPayoutLimits[_j - 1].currency
                ) revert INVALID_SURPLUS_PAYOUT_LIMIT_CURRENCY_ORDERING();

                // Set the surplus payout limit if there is one.
                if (_surplusPayoutLimit.amount > 0) {
                    _packedSurplusPayoutLimitsDataOf[_projectId][_rulesetId][_fundAccessLimitGroup[_i]
                        .terminal][_fundAccessLimitGroup[_i].token].push(
                        _surplusPayoutLimit.amount | (_surplusPayoutLimit.currency << 224)
                    );
                }

                unchecked {
                    ++_j;
                }
            }

            emit SetFundAccessLimits(_rulesetId, _projectId, _limits, msg.sender);

            unchecked {
                ++_i;
            }
        }
    }
}
