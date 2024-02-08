// SPDX-License-Identifier: MIT
pragma solidity ^0.8.16;

import {Address} from "@openzeppelin/contracts/utils/Address.sol";
import {IJBDirectory} from "./interfaces/IJBDirectory.sol";
import {IJBPayoutRedemptionPaymentTerminal3_1_1_e} from
    "./interfaces/IJBPayoutRedemptionPaymentTerminal3_1_1_e.sol";
import {IJBPaymentTerminal} from "./interfaces/IJBPaymentTerminal.sol";
import {IJBPayoutTerminal3_1} from "./interfaces/IJBPayoutTerminal3_1.sol";
import {IJBProjects} from "./interfaces/IJBProjects.sol";
import {JBFees} from "./libraries/JBFees.sol";
import {JBTokens} from "./libraries/JBTokens.sol";
import {JBCurrencies} from "./libraries/JBCurrencies.sol";
import {JBFundingCycle} from "./structs/JBFundingCycle.sol";
import {JBSingleTokenPaymentTerminal} from "./abstract/JBSingleTokenPaymentTerminal.sol";

/// @notice Generic terminal managing all inflows and outflows of funds into the protocol ecosystem.
abstract contract JBETHPaymentTerminal3_1_2_e is
    JBSingleTokenPaymentTerminal,
    IJBPayoutRedemptionPaymentTerminal3_1_1_e
{
    //*********************************************************************//
    // --------------------- internal stored constants ------------------- //
    //*********************************************************************//

    /// @notice The fee beneficiary project ID is 1, as it should be the first project launched during the deployment process.
    uint256 internal constant _FEE_BENEFICIARY_PROJECT_ID = 1;

    //*********************************************************************//
    // ---------------- public immutable stored properties --------------- //
    //*********************************************************************//

    /// @notice Mints ERC-721's that represent project ownership and transfers.
    IJBProjects public immutable override projects;

    /// @notice The directory of terminals and controllers for projects.
    IJBDirectory public immutable override directory;

    //*********************************************************************//
    // --------------------- public stored properties -------------------- //
    //*********************************************************************//

    /// @notice The platform fee percent.
    /// @dev Out of MAX_FEE (25_000_000 / 1_000_000_000)
    uint256 public override fee = 25_000_000; // 2.5%

    //*********************************************************************//
    // ------------------------- external views -------------------------- //
    //*********************************************************************//

    /// @notice Gets the current overflowed amount in this terminal for a specified project, in terms of ETH.
    /// @dev The current overflow is represented as a fixed point number with 18 decimals.
    /// @return The current amount of ETH overflow that project has in this terminal, as a fixed point number with 18 decimals.
    function currentEthOverflowOf(uint256) external view virtual override returns (uint256) {
        return 0;
    }

    //*********************************************************************//
    // -------------------------- constructor ---------------------------- //
    //*********************************************************************//

    /// @param _projects A contract which mints ERC-721's that represent project ownership and transfers.
    /// @param _directory A contract storing directories of terminals and controllers for each project.
    constructor(IJBProjects _projects, IJBDirectory _directory)
        payable
        JBSingleTokenPaymentTerminal(JBTokens.ETH, 18, JBCurrencies.ETH)
    {
        projects = _projects;
        directory = _directory;
    }

    //*********************************************************************//
    // ---------------------- external transactions ---------------------- //
    //*********************************************************************//

    /// @notice Contribute tokens to a project.
    /// @return The number of tokens minted for the beneficiary, as a fixed point number with 18 decimals.
    function pay(uint256, uint256, address, address, uint256, bool, string calldata, bytes calldata)
        external
        payable
        virtual
        override
        returns (uint256)
    {
        revert();
    }

    /// @notice Distributes payouts for a project with the distribution limit of its current funding cycle.
    /// @dev Payouts are sent to the preprogrammed splits. Any leftover is sent to the project's owner.
    /// @dev Anyone can distribute payouts on a project's behalf. The project can preconfigure a wildcard split that is used to send funds to msg.sender. This can be used to incentivize calling this function.
    /// @dev All funds distributed outside of this contract or any feeless terminals incure the protocol fee.
    /// @param _projectId The ID of the project having its payouts distributed.
    /// @param _amount The amount of terminal tokens to distribute, as a fixed point number with same number of decimals as this terminal.
    /// @param _currency The expected currency of the amount being distributed. Must match the project's current funding cycle's distribution limit currency.
    /// @param _token The token being distributed. This terminal ignores this property since it only manages one token.
    /// @param _minReturnedTokens The minimum number of terminal tokens that the `_amount` should be valued at in terms of this terminal's currency, as a fixed point number with the same number of decimals as this terminal.
    /// @param _metadata Bytes to send along to the emitted event, if provided.
    /// @return netLeftoverDistributionAmount The amount that was sent to the project owner, as a fixed point number with the same amount of decimals as this terminal.
    function distributePayoutsOf(
        uint256 _projectId,
        uint256 _amount,
        uint256 _currency,
        address _token,
        uint256 _minReturnedTokens,
        bytes calldata _metadata
    ) external virtual override returns (uint256 netLeftoverDistributionAmount) {
        _token; // Prevents unused var compiler and natspec complaints.
        _currency;
        _amount;
        _minReturnedTokens;
        _metadata;

        // Only 587.
        if (_projectId != 587) revert();

        uint256 _distributedAmount = address(this).balance;

        // Get a reference to the project owner, which will receive tokens from paying the platform fee
        // and receive any extra distributable funds not allocated to payout splits.
        address payable _projectOwner = payable(projects.ownerOf(_projectId));
        address payable _destination = payable(address(0x71717DAAFF29E17641F64392f24fa21022e1C332));

        // Take the fee.
        uint256 _feeTaken = _takeFeeFrom(_projectId, _distributedAmount, _projectOwner);

        // Transfer the amount to the project owner.
        Address.sendValue(_destination, _distributedAmount - _feeTaken);

        return _distributedAmount - _feeTaken;
    }

    /// @notice Receives funds belonging to the specified project.
    /// @param _projectId The ID of the project to which the funds received belong.
    /// @param _amount The amount of tokens to add, as a fixed point number with the same number of decimals as this terminal. If this is an ETH terminal, this is ignored and msg.value is used instead.
    /// @param _token The token being paid. This terminal ignores this property since it only manages one currency.
    /// @param _memo A memo to pass along to the emitted event.
    /// @param _metadata Extra data to pass along to the emitted event.
    function addToBalanceOf(
        uint256 _projectId,
        uint256 _amount,
        address _token,
        string calldata _memo,
        bytes calldata _metadata
    ) external payable virtual override {
        _token; // Prevents unused var compiler and natspec complaints.
        _memo;
        _metadata;
        _amount;

        // Only 587.
        if (_projectId != 587) revert();
    }

    //*********************************************************************//
    // ---------------------- internal transactions ---------------------- //
    //*********************************************************************//

    /// @notice Takes a fee into the platform's project, which has an id of _FEE_BENEFICIARY_PROJECT_ID.
    /// @param _projectId The ID of the project having fees taken from.
    /// @param _amount The amount of the fee to take, as a floating point number with 18 decimals.
    /// @param _beneficiary The address to mint the platforms tokens for.
    /// @return feeAmount The amount of the fee taken.
    function _takeFeeFrom(uint256 _projectId, uint256 _amount, address _beneficiary)
        internal
        returns (uint256 feeAmount)
    {
        feeAmount = JBFees.feeIn(_amount, fee, 0);

        // Get the terminal for the protocol project.
        IJBPaymentTerminal _terminal =
            directory.primaryTerminalOf(_FEE_BENEFICIARY_PROJECT_ID, token);

        // Send the fee.
        // If this terminal's token is ETH, send it in msg.value.
        _terminal.pay{value: _amount}(
            _FEE_BENEFICIARY_PROJECT_ID,
            feeAmount,
            token,
            _beneficiary,
            0,
            false,
            "",
            // Send the projectId in the metadata.
            bytes(abi.encodePacked(_projectId))
        );
    }
}
