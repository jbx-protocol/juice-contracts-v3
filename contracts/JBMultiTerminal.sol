// SPDX-License-Identifier: MIT
pragma solidity ^0.8.16;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Address} from "@openzeppelin/contracts/utils/Address.sol";
import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ERC165Checker} from "@openzeppelin/contracts/utils/introspection/ERC165Checker.sol";
import {PRBMath} from "@paulrberg/contracts/math/PRBMath.sol";
import {IPermit2} from "@permit2/src/src/interfaces/IPermit2.sol";
import {IAllowanceTransfer} from "@permit2/src/src/interfaces/IPermit2.sol";
import {IJBController} from "./interfaces/IJBController.sol";
import {IJBDirectory} from "./interfaces/IJBDirectory.sol";
import {IJBSplits} from "./interfaces/IJBSplits.sol";
import {IJBPermissioned} from "./interfaces/IJBPermissioned.sol";
import {IJBPermissions} from "./interfaces/IJBPermissions.sol";
import {IJBProjects} from "./interfaces/IJBProjects.sol";
import {IJBTerminalStore} from "./interfaces/IJBTerminalStore.sol";
import {IJBSplitHook} from "./interfaces/IJBSplitHook.sol";
import {JBConstants} from "./libraries/JBConstants.sol";
import {JBFees} from "./libraries/JBFees.sol";
import {JBRulesetMetadataResolver} from "./libraries/JBRulesetMetadataResolver.sol";
import {JBMetadataResolver} from "./libraries/JBMetadataResolver.sol";
import {JBPermissionIds} from "./libraries/JBPermissionIds.sol";
import {JBTokenList} from "./libraries/JBTokenList.sol";
import {JBTokenStandards} from "./libraries/JBTokenStandards.sol";
import {JBDidRedeemData} from "./structs/JBDidRedeemData.sol";
import {JBDidPayData} from "./structs/JBDidPayData.sol";
import {JBFee} from "./structs/JBFee.sol";
import {JBRuleset} from "./structs/JBRuleset.sol";
import {JBPayHookPayload} from "./structs/JBPayHookPayload.sol";
import {JBRedeemHookPayload} from "./structs/JBRedeemHookPayload.sol";
import {JBSingleAllowanceData} from "./structs/JBSingleAllowanceData.sol";
import {JBSplit} from "./structs/JBSplit.sol";
import {JBSplitHookPayload} from "./structs/JBSplitHookPayload.sol";
import {JBAccountingContext} from "./structs/JBAccountingContext.sol";
import {JBAccountingContextConfig} from "./structs/JBAccountingContextConfig.sol";
import {JBTokenAmount} from "./structs/JBTokenAmount.sol";
import {JBPermissioned} from "./abstract/JBPermissioned.sol";
import {
    IJBMultiTerminal,
    IJBFeeTerminal,
    IJBTerminal,
    IJBRedeemTerminal,
    IJBPayoutTerminal,
    IJBPermitTerminal
} from "./interfaces/terminal/IJBMultiTerminal.sol";

/// @notice Generic terminal managing inflows and outflows of funds into the protocol ecosystem.
contract JBMultiTerminal is JBPermissioned, Ownable, IJBMultiTerminal {
    // A library that parses the packed ruleset metadata into a friendlier format.
    using JBRulesetMetadataResolver for JBRuleset;

    // A library that adds default safety checks to ERC20 functionality.
    using SafeERC20 for IERC20;

    //*********************************************************************//
    // --------------------------- custom errors ------------------------- //
    //*********************************************************************//

    error ACCOUNTING_CONTEXT_ALREADY_SET();
    error FEE_TOO_HIGH();
    error INADEQUATE_PAYOUT_AMOUNT();
    error INADEQUATE_RECLAIM_AMOUNT();
    error UNDER_MIN_RETURNED_TOKENS();
    error NO_MSG_VALUE_ALLOWED();
    error CANNOT_PAY_FOR_ZERO_ADDRESS();
    error PERMIT_ALLOWANCE_NOT_ENOUGH(uint256 transactionAmount, uint256 permitAllowance);
    error CANNOT_REDEEM_FOR_ZERO_ADDRESS();
    error TERMINAL_TOKENS_INCOMPATIBLE();
    error TOKEN_NOT_ACCEPTED();

    //*********************************************************************//
    // --------------------- internal stored constants ------------------- //
    //*********************************************************************//

    /// @notice The ID of the project which receives fees is 1, as it should be the first project launched during the deployment process.
    uint256 internal constant _FEE_BENEFICIARY_PROJECT_ID = 1;

    //*********************************************************************//
    // --------------------- internal stored properties ------------------ //
    //*********************************************************************//

    /// @notice Context describing how a token is accounted for by a project.
    /// @custom:param _projectId The ID of the project that the token accounting context applies to.
    /// @custom:param _token The address of the token being accounted for.
    mapping(uint256 => mapping(address => JBAccountingContext)) internal
        _accountingContextForTokenOf;

    /// @notice A list of tokens accepted by each project.
    /// @custom:param _projectId The ID of the project to get a list of accepted tokens for.
    mapping(uint256 => JBAccountingContext[]) internal _accountingContextsOf;

    /// @notice Fees that are being held for each project.
    /// @dev Projects can temporarily hold fees and unlock them later by adding funds to the project's balance.
    /// @dev Held fees can be processed at any time by this terminal's owner.
    /// @custom:param _projectId The ID of the project that is holding fees.
    mapping(uint256 => JBFee[]) internal _heldFeesOf;

    //*********************************************************************//
    // ------------------------- public constants ------------------------ //
    //*********************************************************************//

    /// @notice The fee percent (out of `JBConstants.MAX_FEE`).
    /// @dev Fees are charged on payouts to addresses, when the surplus allowance is used, and on redemptions where the redemption rate is less than 100%.
    uint256 public constant override FEE = 25_000_000; // 2.5%

    //*********************************************************************//
    // ---------------- public immutable stored properties --------------- //
    //*********************************************************************//

    /// @notice Mints ERC-721s that represent project ownership and transfers.
    IJBProjects public immutable override PROJECTS;

    /// @notice The directory of terminals and controllers for PROJECTS.
    IJBDirectory public immutable override DIRECTORY;

    /// @notice The contract that stores splits for each project.
    IJBSplits public immutable override SPLITS;

    /// @notice The contract that stores and manages the terminal's data.
    IJBTerminalStore public immutable override STORE;

    /// @notice The permit2 utility.
    IPermit2 public immutable override PERMIT2;

    //*********************************************************************//
    // --------------------- public stored properties -------------------- //
    //*********************************************************************//

    /// @notice Feeless addresses for this terminal.
    /// @dev Feeless addresses can receive payouts without incurring a fee.
    /// @dev Feeless addresses can use the surplus allowance without incurring a fee.
    /// @dev Feeless addresses can be the beneficary of redemptions without incurring a fee.
    /// @custom:param _address The address that may or may not be feeless.
    mapping(address => bool) public override isFeelessAddress;

    //*********************************************************************//
    // ------------------------- external views -------------------------- //
    //*********************************************************************//

    /// @notice A project's accounting context for a token.
    /// @dev See the `JBAccountingContext` struct for more information.
    /// @param _projectId The ID of the project to get token accounting context of.
    /// @param _token The token to check the accounting context of.
    /// @return The token's accounting context for the token.
    function accountingContextForTokenOf(uint256 _projectId, address _token)
        external
        view
        override
        returns (JBAccountingContext memory)
    {
        return _accountingContextForTokenOf[_projectId][_token];
    }

    /// @notice The tokens accepted by a project.
    /// @param _projectId The ID of the project to get the accepted tokens of.
    /// @return tokenContexts The accounting contexts of the accepted tokens.
    function accountingContextsOf(uint256 _projectId)
        external
        view
        override
        returns (JBAccountingContext[] memory)
    {
        return _accountingContextsOf[_projectId];
    }

    /// @notice Gets the total current surplus amount in this terminal for a project, in terms of a given currency.
    /// @dev This total surplus only includes tokens that the project accepts (as returned by `accountingContextsOf(...)`).
    /// @param _projectId The ID of the project to get the current total surplus of.
    /// @param _decimals The number of decimals to include in the fixed point returned value.
    /// @param _currency The currency to express the returned value in terms of.
    /// @return The current surplus amount the project has in this terminal, in terms of `_currency` and with the specified number of decimals.
    function currentSurplusOf(uint256 _projectId, uint256 _decimals, uint256 _currency)
        external
        view
        virtual
        override
        returns (uint256)
    {
        return STORE.currentSurplusOf(
            address(this), _projectId, _accountingContextsOf[_projectId], _decimals, _currency
        );
    }

    /// @notice Fees that are being held for a project.
    /// @dev Projects can temporarily hold fees and unlock them later by adding funds to the project's balance.
    /// @dev Held fees can be processed at any time by this terminal's owner.
    /// @param _projectId The ID of the project that is holding fees.
    /// @return An array of fees that are being held.
    function heldFeesOf(uint256 _projectId) external view override returns (JBFee[] memory) {
        return _heldFeesOf[_projectId];
    }

    //*********************************************************************//
    // -------------------------- public views --------------------------- //
    //*********************************************************************//

    /// @notice Indicates if this contract adheres to the specified interface.
    /// @dev See {IERC165-supportsInterface}.
    /// @param _interfaceId The ID of the interface to check for adherance to.
    /// @return A flag indicating if the provided interface ID is supported.
    function supportsInterface(bytes4 _interfaceId) public view virtual override returns (bool) {
        return _interfaceId == type(IJBMultiTerminal).interfaceId
            || _interfaceId == type(IJBPermissioned).interfaceId
            || _interfaceId == type(IJBTerminal).interfaceId
            || _interfaceId == type(IJBRedeemTerminal).interfaceId
            || _interfaceId == type(IJBPayoutTerminal).interfaceId
            || _interfaceId == type(IJBPermitTerminal).interfaceId
            || _interfaceId == type(IJBMultiTerminal).interfaceId
            || _interfaceId == type(IJBFeeTerminal).interfaceId
            || _interfaceId == type(IERC165).interfaceId;
    }

    //*********************************************************************//
    // -------------------------- internal views ------------------------- //
    //*********************************************************************//

    /// @notice Checks this terminal's balance of a specific token.
    /// @param _token The address of the token to get this terminal's balance of.
    /// @return This terminal's balance.
    function _balance(address _token) internal view virtual returns (uint256) {
        // If the `_token` is ETH, get the native token balance.
        return _token == JBTokenList.ETH
            ? address(this).balance
            : IERC20(_token).balanceOf(address(this));
    }

    //*********************************************************************//
    // -------------------------- constructor ---------------------------- //
    //*********************************************************************//

    /// @param _permissions A contract storing permissions.
    /// @param _projects A contract which mints ERC-721s that represent project ownership and transfers.
    /// @param _directory A contract storing directories of terminals and controllers for each project.
    /// @param _splits A contract that stores splits for each project.
    /// @param _store A contract that stores the terminal's data.
    /// @param _permit2 A permit2 utility.
    /// @param _owner The address that will own this contract.
    constructor(
        IJBPermissions _permissions,
        IJBProjects _projects,
        IJBDirectory _directory,
        IJBSplits _splits,
        IJBTerminalStore _store,
        IPermit2 _permit2,
        address _owner
    ) JBPermissioned(_permissions) Ownable(_owner) {
        PROJECTS = _projects;
        DIRECTORY = _directory;
        SPLITS = _splits;
        STORE = _store;
        PERMIT2 = _permit2;
    }

    //*********************************************************************//
    // ---------------------- external transactions ---------------------- //
    //*********************************************************************//

    /// @notice Pay a project with tokens.
    /// @param _projectId The ID of the project being paid.
    /// @param _amount The amount of terminal tokens being received, as a fixed point number with the same number of decimals as this terminal. If this terminal's token is ETH, this is ignored and `msg.value` is used in its place.
    /// @param _token The token being paid. This terminal ignores this property since it only manages one token.
    /// @param _beneficiary The address to mint tokens to, and pass along to the ruleset's data hook and pay hook if applicable.
    /// @param _minReturnedTokens The minimum number of project tokens expected in return for this payment, as a fixed point number with the same number of decimals as this terminal. If the amount of tokens minted for the beneficiary would be less than this amount, the payment is reverted.
    /// @param _memo A memo to pass along to the emitted event.
    /// @param _metadata Bytes to pass along to the emitted event, as well as the data hook and pay hook if applicable.
    /// @return The number of tokens minted to the beneficiary, as a fixed point number with 18 decimals.
    function pay(
        uint256 _projectId,
        address _token,
        uint256 _amount,
        address _beneficiary,
        uint256 _minReturnedTokens,
        string calldata _memo,
        bytes calldata _metadata
    ) external payable virtual override returns (uint256) {
        // Accept the funds.
        _amount = _acceptFundsFor(_projectId, _token, _amount, _metadata);

        // Pay the project.
        return _pay(
            _token,
            _amount,
            msg.sender,
            _projectId,
            _beneficiary,
            _minReturnedTokens,
            _memo,
            _metadata
        );
    }

    /// @notice Adds funds to a project's balance without minting tokens.
    /// @dev Adding to balance can unlock held fees if `_shouldUnlockHeldFees` is true.
    /// @param _projectId The ID of the project to add funds to the balance of.
    /// @param _amount The amount of tokens to add to the balance, as a fixed point number with the same number of decimals as this terminal. If this is an ETH terminal, this is ignored and `msg.value` is used instead.
    /// @param _token The token being added to the balance. This terminal ignores this property since it only manages one currency.
    /// @param _shouldUnlockHeldFees A flag indicating if held fees should be refunded based on the amount being added.
    /// @param _memo A memo to pass along to the emitted event.
    /// @param _metadata Extra data to pass along to the emitted event.
    function addToBalanceOf(
        uint256 _projectId,
        address _token,
        uint256 _amount,
        bool _shouldUnlockHeldFees,
        string calldata _memo,
        bytes calldata _metadata
    ) external payable virtual override {
        // Accept the funds.
        _amount = _acceptFundsFor(_projectId, _token, _amount, _metadata);

        // Add to balance.
        _addToBalanceOf(_projectId, _token, _amount, _shouldUnlockHeldFees, _memo, _metadata);
    }

    /// @notice Holders can redeem a project's tokens to reclaim some of that project's surplus tokens, or to trigger rules determined by the current ruleset's data hook and redeem hook.
    /// @dev Only a token's holder or an operator with the `JBPermissionIds.REDEEM_TOKENS` permission from that holder can redeem those tokens.
    /// @param _holder The account whose tokens are being redeemed.
    /// @param _projectId The ID of the project the project tokens belong to.
    /// @param _tokenCount The number of project tokens to redeem, as a fixed point number with 18 decimals.
    /// @param _token The token being reclaimed. This terminal ignores this property since it only manages one token.
    /// @param _minReturnedTokens The minimum number of terminal tokens expected in return, as a fixed point number with the same number of decimals as this terminal. If the amount of tokens minted for the beneficiary would be less than this amount, the redemption is reverted.
    /// @param _beneficiary The address to send the reclaimed terminal tokens to, and to pass along to the ruleset's data hook and redeem hook if applicable.
    /// @param _metadata Bytes to send along to the emitted event, as well as the data hook and redeem hook if applicable.
    /// @return reclaimAmount The amount of terminal tokens that the project tokens were redeemed for, as a fixed point number with 18 decimals.
    function redeemTokensOf(
        address _holder,
        uint256 _projectId,
        address _token,
        uint256 _tokenCount,
        uint256 _minReturnedTokens,
        address payable _beneficiary,
        bytes calldata _metadata
    )
        external
        virtual
        override
        requirePermission(_holder, _projectId, JBPermissionIds.REDEEM_TOKENS)
        returns (uint256 reclaimAmount)
    {
        return _redeemTokensOf(
            _holder, _projectId, _token, _tokenCount, _minReturnedTokens, _beneficiary, _metadata
        );
    }

    /// @notice Sends payouts to a project's current payout split group, according to its ruleset, up to its current payout limit.
    /// @dev If the percentages of the splits in the project's payout split group do not add up to 100%, the remainder is sent to the project's owner.
    /// @dev Anyone can send payouts on a project's behalf. Projects can include a wildcard split (a split with no `hook`, `projectId`, or `beneficiary`) to send funds to the `msg.sender` which calls this function. This can be used to incentivize calling this function.
    /// @dev Payouts sent to addresses which aren't feeless incur the protocol fee.
    /// @dev Payouts a projects don't incur fees if its terminal is feeless.
    /// @param _projectId The ID of the project having its payouts sent.
    /// @param _token The token being sent. This terminal ignores this property since it only manages one token.
    /// @param _amount The total number of terminal tokens to send, as a fixed point number with same number of decimals as this terminal.
    /// @param _currency The expected currency of the payouts being sent. Must match the currency of one of the project's current ruleset's payout limits.
    /// @param _minReturnedTokens The minimum number of terminal tokens that the `_amount` should be worth (if expressed in terms of this terminal's currency), as a fixed point number with the same number of decimals as this terminal. If the amount of tokens paid out would be less than this amount, the send is reverted.
    /// @return netLeftoverPayoutAmount The amount that was sent to the project owner, as a fixed point number with the same amount of decimals as this terminal.
    function sendPayoutsOf(
        uint256 _projectId,
        address _token,
        uint256 _amount,
        uint256 _currency,
        uint256 _minReturnedTokens
    ) external virtual override returns (uint256 netLeftoverPayoutAmount) {
        return _sendPayoutsOf(_projectId, _token, _amount, _currency, _minReturnedTokens);
    }

    /// @notice Allows a project to pay out funds from its surplus up to the current surplus allowance.
    /// @dev Only a project's owner or an operator with the `JBPermissionIds.USE_ALLOWANCE` permission from that owner can use the surplus allowance.
    /// @dev Incurs the protocol fee unless the caller is a feeless address.
    /// @param _projectId The ID of the project to use the surplus allowance of.
    /// @param _token The token being paid out from the surplus. This terminal ignores this property since it only manages one token.
    /// @param _amount The amount of terminal tokens to use from the project's current surplus allowance, as a fixed point number with the same amount of decimals as this terminal.
    /// @param _currency The expected currency of the amount being paid out. Must match the currency of one of the project's current ruleset's surplus allowances.
    /// @param _minTokensUsed The minimum number of terminal tokens that should be used from the surplus allowance (including fees), as a fixed point number with 18 decimals. If the amount of surplus used would be less than this amount, the transaction is reverted.
    /// @param _beneficiary The address to send the surplus funds to.
    /// @param _memo A memo to pass along to the emitted event.
    /// @return netAmountPaidOut The number of tokens that were sent to the beneficiary, as a fixed point number with the same amount of decimals as the terminal.
    function useAllowanceOf(
        uint256 _projectId,
        address _token,
        uint256 _amount,
        uint256 _currency,
        uint256 _minTokensUsed,
        address payable _beneficiary,
        string calldata _memo
    )
        external
        virtual
        override
        requirePermission(PROJECTS.ownerOf(_projectId), _projectId, JBPermissionIds.USE_ALLOWANCE)
        returns (uint256 netAmountPaidOut)
    {
        return _useAllowanceOf(
            _projectId, _token, _amount, _currency, _minTokensUsed, _beneficiary, _memo
        );
    }

    /// @notice Migrate a project's funds and operations to a new terminal that accepts the same token type.
    /// @dev Only a project's owner or an operator with the `JBPermissionIds.MIGRATE_TERMINAL` permission from that owner can migrate the project's terminal.
    /// @param _projectId The ID of the project being migrated.
    /// @param _token The address of the token being migrated.
    /// @param _to The terminal contract being migrated to, which will receive the project's funds and operations.
    /// @return balance The amount of funds that were migrated, as a fixed point number with the same amount of decimals as this terminal.
    function migrateBalanceOf(uint256 _projectId, address _token, IJBTerminal _to)
        external
        virtual
        override
        requirePermission(PROJECTS.ownerOf(_projectId), _projectId, JBPermissionIds.MIGRATE_TERMINAL)
        returns (uint256 balance)
    {
        // The terminal being migrated to must accept the same token as this terminal.
        if (_to.accountingContextForTokenOf(_projectId, _token).decimals == 0) {
            revert TERMINAL_TOKENS_INCOMPATIBLE();
        }

        // Record the migration in the store.
        balance = STORE.recordTerminalMigration(_projectId, _token);

        // Transfer the balance if needed.
        if (balance != 0) {
            // Trigger any inherited pre-transfer logic.
            _beforeTransferFor(address(_to), _token, balance);

            // If this terminal's token is ETH, send it in `msg.value`.
            uint256 _payValue = _token == JBTokenList.ETH ? balance : 0;

            // Withdraw the balance to transfer to the new terminal;
            _to.addToBalanceOf{value: _payValue}(_projectId, _token, balance, false, "", bytes(""));
        }

        emit MigrateTerminal(_projectId, _token, _to, balance, msg.sender);
    }

    /// @notice Process any fees that are being held for the project.
    /// @dev Only a project's owner, an operator with the `JBPermissionIds.PROCESS_FEES` permission from that owner, or this terminal's owner can process held fees.
    /// @param _projectId The ID of the project to process held fees for.
    function processHeldFees(uint256 _projectId, address _token)
        external
        virtual
        override
        requirePermissionAllowingOverride(
            PROJECTS.ownerOf(_projectId),
            _projectId,
            JBPermissionIds.PROCESS_FEES,
            msg.sender == owner()
        )
    {
        // Get a reference to the project's held fees.
        JBFee[] memory _heldFees = _heldFeesOf[_projectId];

        // Delete the held fees.
        delete _heldFeesOf[_projectId];

        // Keep a reference to the amount.
        uint256 _amount;

        // Keep a reference to the number of held fees.
        uint256 _numberOfHeldFees = _heldFees.length;

        // Keep a reference to the terminal that'll receive the fees.
        IJBTerminal _feeTerminal = DIRECTORY.primaryTerminalOf(_FEE_BENEFICIARY_PROJECT_ID, _token);

        // Process each fee.
        for (uint256 _i; _i < _numberOfHeldFees;) {
            // Get the fee amount.
            _amount =
                (_heldFees[_i].fee == 0 ? 0 : JBFees.feeIn(_heldFees[_i].amount, _heldFees[_i].fee));

            // Process the fee.
            _processFee(_projectId, _token, _amount, _heldFees[_i].beneficiary, _feeTerminal);

            emit ProcessFee(_projectId, _amount, true, _heldFees[_i].beneficiary, msg.sender);

            unchecked {
                ++_i;
            }
        }
    }

    /// @notice Sets an address as feeless or not feeless for this terminal.
    /// @dev Only the owner of this contract can set addresses as feeless or not feeless.
    /// @dev Feeless addresses can receive payouts without incurring a fee.
    /// @dev Feeless addresses can use the surplus allowance without incurring a fee.
    /// @dev Feeless addresses can be the beneficary of redemptions without incurring a fee.
    /// @param _address The address to make feeless or not feeless.
    /// @param _flag A flag indicating whether the `_address` should be made feeless or not feeless.
    function setFeelessAddress(address _address, bool _flag) external virtual override onlyOwner {
        // Set the flag value.
        isFeelessAddress[_address] = _flag;

        emit SetFeelessAddress(_address, _flag, msg.sender);
    }

    /// @notice Adds accounting contexts for a project to this terminal so the project can begin accepting the tokens in those contexts.
    /// @dev Only a project's owner, an operator with the `JBPermissionIds.SET_ACCOUNTING_CONTEXT` permission from that owner, or a project's controller can add accounting contexts for the project.
    /// @param _projectId The ID of the project having to add accounting contexts for.
    /// @param _accountingContextConfigs The accounting contexts to add.
    function addAccountingContextsFor(
        uint256 _projectId,
        JBAccountingContextConfig[] calldata _accountingContextConfigs
    )
        external
        override
        requirePermissionAllowingOverride(
            PROJECTS.ownerOf(_projectId),
            _projectId,
            JBPermissionIds.SET_ACCOUNTING_CONTEXT,
            msg.sender == DIRECTORY.controllerOf(_projectId)
        )
    {
        // Keep a reference to the number of accounting context configurations.
        uint256 _numberOfAccountingContextsConfigs = _accountingContextConfigs.length;

        // Keep a reference to the accounting context being iterated on.
        JBAccountingContextConfig memory _accountingContextConfig;

        // Add each accounting context.
        for (uint256 _i; _i < _numberOfAccountingContextsConfigs;) {
            // Set the accounting context being iterated on.
            _accountingContextConfig = _accountingContextConfigs[_i];

            // Get a storage reference to the currency accounting context for the token.
            JBAccountingContext storage _accountingContext =
                _accountingContextForTokenOf[_projectId][_accountingContextConfig.token];

            // Make sure the token accounting context isn't already set.
            if (_accountingContext.token != address(0)) revert ACCOUNTING_CONTEXT_ALREADY_SET();

            // Define the context from the config.
            _accountingContext.token = _accountingContextConfig.token;
            _accountingContext.decimals = _accountingContextConfig.standard
                == JBTokenStandards.NATIVE
                ? 18
                : IERC20Metadata(_accountingContextConfig.token).decimals();
            _accountingContext.currency = uint32(uint160(_accountingContextConfig.token));
            _accountingContext.standard = _accountingContextConfig.standard;

            // Add the token to the list of accepted tokens of the project.
            _accountingContextsOf[_projectId].push(_accountingContext);

            emit SetAccountingContext(
                _projectId, _accountingContextConfig.token, _accountingContext, msg.sender
            );

            unchecked {
                ++_i;
            }
        }
    }

    //*********************************************************************//
    // ---------------------- internal transactions ---------------------- //
    //*********************************************************************//

    /// @notice Accepts an incoming token.
    /// @param _projectId The ID of the project that the transfer is being accepted for.
    /// @param _token The token being accepted.
    /// @param _amount The number of tokens being accepted.
    /// @param _metadata The metadata in which permit2 context is provided.
    /// @return amount The number of tokens which have been accepted.
    function _acceptFundsFor(
        uint256 _projectId,
        address _token,
        uint256 _amount,
        bytes calldata _metadata
    ) internal returns (uint256) {
        // Make sure the project has an accounting context for the token being paid.
        if (_accountingContextForTokenOf[_projectId][_token].token == address(0)) {
            revert TOKEN_NOT_ACCEPTED();
        }

        // If the terminal's token is ETH, override `_amount` with `msg.value`.
        if (_token == JBTokenList.ETH) return msg.value;

        // If the terminal's token is not ETH, revert if there is a non-zero `msg.value`.
        if (msg.value != 0) revert NO_MSG_VALUE_ALLOWED();

        // If the terminal is rerouting the tokens within its own functions, there's nothing to transfer.
        if (msg.sender == address(this)) return _amount;

        // Unpack the allowance to use, if any, given by the frontend.
        (bool _exists, bytes memory _parsedMetadata) =
            JBMetadataResolver.getMetadata(bytes4(uint32(uint160(address(this)))), _metadata);

        // Check if the metadata contains permit data.
        if (_exists) {
            // Keep a reference to the allowance context parsed from the metadata.
            (JBSingleAllowanceData memory _allowance) =
                abi.decode(_parsedMetadata, (JBSingleAllowanceData));

            // Make sure the permit allowance is enough for this payment. If not we revert early.
            if (_allowance.amount < _amount) {
                revert PERMIT_ALLOWANCE_NOT_ENOUGH(_amount, _allowance.amount);
            }

            // Set the allowance to `spend` tokens for the user.
            _permitAllowance(_allowance, _token);
        }

        // Get a reference to the balance before receiving tokens.
        uint256 _balanceBefore = _balance(_token);

        // Transfer tokens to this terminal from the msg sender.
        _transferFor(msg.sender, payable(address(this)), _token, _amount);

        // The amount should reflect the change in balance.
        return _balance(_token) - _balanceBefore;
    }

    /// @notice Pay a project with tokens.
    /// @param _token The address of the token which the project is being paid with.
    /// @param _amount The amount of terminal tokens being received, as a fixed point number with the same number of decimals as this terminal. If this terminal's token is ETH, `_amount` is ignored and `msg.value` is used in its place.
    /// @param _payer The address making the payment.
    /// @param _projectId The ID of the project being paid.
    /// @param _beneficiary The address to mint tokens to, and pass along to the ruleset's data hook and pay hook if applicable.
    /// @param _minReturnedTokens The minimum number of project tokens expected in return, as a fixed point number with the same amount of decimals as this terminal. If the amount of tokens minted for the beneficiary would be less than this amount, the payment is reverted.
    /// @param _memo A memo to pass along to the emitted event.
    /// @param _metadata Bytes to send along to the emitted event, as well as the data hook and pay hook if applicable.
    /// @return beneficiaryTokenCount The number of tokens minted and sent to the beneficiary, as a fixed point number with 18 decimals.
    function _pay(
        address _token,
        uint256 _amount,
        address _payer,
        uint256 _projectId,
        address _beneficiary,
        uint256 _minReturnedTokens,
        string memory _memo,
        bytes memory _metadata
    ) internal returns (uint256 beneficiaryTokenCount) {
        // Cant send tokens to the zero address.
        if (_beneficiary == address(0)) revert CANNOT_PAY_FOR_ZERO_ADDRESS();

        // Define variables that will be needed outside the scoped section below.
        // Keep a reference to the ruleset the payment is being made during.
        JBRuleset memory _ruleset;

        // Scoped section prevents stack too deep. `_hookPayloads` and `_tokenCount` only used within scope.
        {
            JBPayHookPayload[] memory _hookPayloads;
            JBTokenAmount memory _tokenAmount;

            uint256 _tokenCount;

            // Get a reference to the token's accounting context.
            JBAccountingContext memory _context = _accountingContextForTokenOf[_projectId][_token];

            // Bundle the amount info into a JBTokenAmount struct.
            _tokenAmount = JBTokenAmount(_token, _amount, _context.decimals, _context.currency);

            // Record the payment.
            (_ruleset, _tokenCount, _hookPayloads) =
                STORE.recordPaymentFrom(_payer, _tokenAmount, _projectId, _beneficiary, _metadata);

            // Mint tokens if needed.
            if (_tokenCount != 0) {
                // Set the token count to be the number of tokens minted for the beneficiary instead of the total amount.
                beneficiaryTokenCount = IJBController(DIRECTORY.controllerOf(_projectId))
                    .mintTokensOf(_projectId, _tokenCount, _beneficiary, "", true);
            }

            // The token count for the beneficiary must be greater than or equal to the specified minimum.
            if (beneficiaryTokenCount < _minReturnedTokens) revert UNDER_MIN_RETURNED_TOKENS();

            // If hook payloads were specified by the data hook, fulfill them.
            if (_hookPayloads.length != 0) {
                _fulfillPayHookPayloadsFor(
                    _projectId,
                    _hookPayloads,
                    _tokenAmount,
                    _payer,
                    _ruleset,
                    _beneficiary,
                    beneficiaryTokenCount,
                    _metadata
                );
            }
        }

        emit Pay(
            _ruleset.rulesetId,
            _ruleset.cycleNumber,
            _projectId,
            _payer,
            _beneficiary,
            _amount,
            beneficiaryTokenCount,
            _memo,
            _metadata,
            msg.sender
        );
    }

    /// @notice Adds funds to a project's balance without minting tokens.
    /// @param _projectId The ID of the project to add funds to the balance of.
    /// @param _token The address of the token being added to the project's balance.
    /// @param _amount The amount of tokens to add as a fixed point number with the same number of decimals as this terminal. If this is an ETH terminal, this is ignored and `msg.value` is used instead.
    /// @param _shouldUnlockHeldFees A flag indicating if held fees should be unlocked based on the amount being added.
    /// @param _memo A memo to pass along to the emitted event.
    /// @param _metadata Extra data to pass along to the emitted event.
    function _addToBalanceOf(
        uint256 _projectId,
        address _token,
        uint256 _amount,
        bool _shouldUnlockHeldFees,
        string memory _memo,
        bytes memory _metadata
    ) internal {
        // Unlock held fees if desired. This mechanism means projects don't pay fees multiple times when funds go out of and back into the protocol.
        uint256 _unlockedFees = _shouldUnlockHeldFees ? _unlockHeldFees(_projectId, _amount) : 0;

        // Record the added funds with any refunded fees.
        STORE.recordAddedBalanceFor(_projectId, _token, _amount + _unlockedFees);

        emit AddToBalance(_projectId, _amount, _unlockedFees, _memo, _metadata, msg.sender);
    }

    /// @notice Holders can redeem their tokens to claim some of a project's surplus, or to trigger rules determined by the project's current ruleset's data hook.
    /// @dev Only a token holder or a an operator with the `JBPermissionIds.REDEEM_TOKENS` permission from that holder can redeem those tokens.
    /// @param _holder The account redeeming tokens.
    /// @param _projectId The ID of the project whose tokens are being redeemed.
    /// @param _token The address of the token which is being reclaimed.
    /// @param _tokenCount The number of project tokens to redeem, as a fixed point number with 18 decimals.
    /// @param _minReturnedTokens The minimum amount of terminal tokens expected in return, as a fixed point number with the same amount of decimals as the terminal. If the amount of tokens minted for the beneficiary would be less than this amount, the redemption is reverted.
    /// @param _beneficiary The address to send the reclaimed terminal tokens to.
    /// @param _metadata Bytes to send along to the emitted event, as well as the data hook and redeem hook if applicable.
    /// @return reclaimAmount The number of terminal tokens reclaimed for the `_beneficiary`, as a fixed point number with 18 decimals.
    function _redeemTokensOf(
        address _holder,
        uint256 _projectId,
        address _token,
        uint256 _tokenCount,
        uint256 _minReturnedTokens,
        address payable _beneficiary,
        bytes memory _metadata
    ) internal returns (uint256 reclaimAmount) {
        // Can't send reclaimed funds to the zero address.
        if (_beneficiary == address(0)) revert CANNOT_REDEEM_FOR_ZERO_ADDRESS();

        // Define variables that will be needed outside the scoped section below.
        // Keep a reference to the ruleset the redemption is being made during.
        JBRuleset memory _ruleset;

        // Scoped section prevents stack too deep.
        {
            JBRedeemHookPayload[] memory _hookPayloads;

            // Record the redemption.
            (_ruleset, reclaimAmount, _hookPayloads) = STORE.recordRedemptionFor(
                _holder,
                _projectId,
                _accountingContextForTokenOf[_projectId][_token],
                _accountingContextsOf[_projectId],
                _tokenCount,
                _metadata
            );

            // Set the fee. Fees are not exercised if the redemption rate is at its max (100%), if the beneficiary is feeless, or if the fee beneficiary doesn't accept the given token.
            uint256 _feePercent = isFeelessAddress[_beneficiary]
                || _ruleset.redemptionRate() == JBConstants.MAX_REDEMPTION_RATE ? 0 : FEE;

            // The amount being reclaimed must be at least as much as was expected.
            if (reclaimAmount < _minReturnedTokens) revert INADEQUATE_RECLAIM_AMOUNT();

            // Burn the project tokens.
            if (_tokenCount != 0) {
                IJBController(DIRECTORY.controllerOf(_projectId)).burnTokensOf(
                    _holder, _projectId, _tokenCount, ""
                );
            }

            // Keep a reference to the amount being reclaimed which fees should be exercised on.
            uint256 _amountEligibleForFees;

            // If hook payloads were specified by the data hook, fulfill them.
            if (_hookPayloads.length != 0) {
                // Get a reference to the token's accounting context.
                JBAccountingContext memory _context =
                    _accountingContextForTokenOf[_projectId][_token];

                // Fulfill the redeem hooks.
                _amountEligibleForFees += _fulfillRedemptionHookPayloadsFor(
                    _projectId,
                    JBTokenAmount(_token, reclaimAmount, _context.decimals, _context.currency),
                    _holder,
                    _tokenCount,
                    _metadata,
                    _ruleset,
                    _beneficiary,
                    _hookPayloads,
                    _feePercent
                );
            }

            // Send the reclaimed funds to the beneficiary.
            if (reclaimAmount != 0) {
                if (_feePercent != 0) {
                    _amountEligibleForFees += reclaimAmount;
                    // Subtract the fee for the reclaimed amount.
                    reclaimAmount -= _feePercent == 0 ? 0 : JBFees.feeIn(reclaimAmount, _feePercent);
                }

                // Subtract the fee from the reclaim amount.
                if (reclaimAmount != 0) {
                    _transferFor(address(this), _beneficiary, _token, reclaimAmount);
                }
            }

            // Take the fee from all outbound reclaimings.
            _amountEligibleForFees != 0
                ? _takeFeeFrom(
                    _projectId, _token, _amountEligibleForFees, _feePercent, _beneficiary, false
                )
                : 0;
        }

        emit RedeemTokens(
            _ruleset.rulesetId,
            _ruleset.cycleNumber,
            _projectId,
            _holder,
            _beneficiary,
            _tokenCount,
            reclaimAmount,
            _metadata,
            msg.sender
        );
    }

    /// @notice Sends payouts to a project's current payout split group, according to its ruleset, up to its current payout limit.
    /// @dev If the percentages of the splits in the project's payout split group do not add up to 100%, the remainder is sent to the project's owner.
    /// @dev Anyone can send payouts on a project's behalf. Projects can include a wildcard split (a split with no `hook`, `projectId`, or `beneficiary`) to send funds to the `msg.sender` which calls this function. This can be used to incentivize calling this function.
    /// @dev Payouts sent to addresses which aren't feeless incur the protocol fee.
    /// @param _projectId The ID of the project to send the payouts of.
    /// @param _token The token being paid out.
    /// @param _amount The number of terminal tokens to pay out, as a fixed point number with same number of decimals as this terminal.
    /// @param _currency The expected currency of the amount being paid out. Must match the currency of one of the project's current ruleset's payout limits.
    /// @param _minReturnedTokens The minimum number of terminal tokens that the `_amount` should be worth (if expressed in terms of this terminal's currency), as a fixed point number with the same number of decimals as this terminal. If the amount of tokens paid out would be less than this amount, the send is reverted.
    /// @return netLeftoverPayoutAmount The leftover amount that was sent to the project owner, as a fixed point number with the same amount of decimals as this terminal.
    function _sendPayoutsOf(
        uint256 _projectId,
        address _token,
        uint256 _amount,
        uint256 _currency,
        uint256 _minReturnedTokens
    ) internal returns (uint256 netLeftoverPayoutAmount) {
        // Record the payout.
        (JBRuleset memory _ruleset, uint256 _amountPaidOut) = STORE.recordPayoutFor(
            _projectId, _accountingContextForTokenOf[_projectId][_token], _amount, _currency
        );

        // The amount being paid out must be at least as much as was expected.
        if (_amountPaidOut < _minReturnedTokens) revert INADEQUATE_PAYOUT_AMOUNT();

        // Get a reference to the project's owner.
        // The owner will receive tokens minted by paying the platform fee and receive any leftover funds not sent to payout splits.
        address payable _projectOwner = payable(PROJECTS.ownerOf(_projectId));

        // Keep a reference to the fee.
        // The fee is 0 if the fee beneficiary doesn't accept the given token.
        uint256 _feePercent = FEE;

        // Send payouts to the splits and get a reference to the amount left over after the splits have been paid.
        // Also get a reference to the amount which was paid out to splits that is eligible for fees.
        (uint256 _leftoverPayoutAmount, uint256 _amountEligibleForFees) = _sendPayoutsToSplitGroupOf(
            _projectId, _token, _ruleset.rulesetId, _amountPaidOut, _feePercent
        );

        // Take the fee.
        uint256 _feeTaken = _feePercent != 0
            ? _takeFeeFrom(
                _projectId,
                _token,
                _amountEligibleForFees + _leftoverPayoutAmount,
                _feePercent,
                _projectOwner,
                _ruleset.shouldHoldFees()
            )
            : 0;

        // Send any leftover funds to the project owner and update the net leftover (which is returned) accordingly.
        if (_leftoverPayoutAmount != 0) {
            // Subtract the fee from the net leftover amount.
            netLeftoverPayoutAmount = _leftoverPayoutAmount
                - (_feePercent == 0 ? 0 : JBFees.feeIn(_leftoverPayoutAmount, _feePercent));

            // Transfer the amount to the project owner.
            _transferFor(address(this), _projectOwner, _token, netLeftoverPayoutAmount);
        }

        emit SendPayouts(
            _ruleset.rulesetId,
            _ruleset.cycleNumber,
            _projectId,
            _projectOwner,
            _amount,
            _amountPaidOut,
            _feeTaken,
            netLeftoverPayoutAmount,
            msg.sender
        );
    }

    /// @notice Allows a project to send out funds from its surplus up to the current surplus allowance.
    /// @dev Only a project's owner or an operator with the `JBPermissionIds.USE_ALLOWANCE` permission from that owner can use the surplus allowance.
    /// @dev Incurs the protocol fee unless the caller is a feeless address.
    /// @param _projectId The ID of the project to use the surplus allowance of.
    /// @param _token The token being paid out from the surplus.
    /// @param _amount The amount of terminal tokens to use from the project's current surplus allowance, as a fixed point number with the same amount of decimals as this terminal.
    /// @param _currency The expected currency of the amount being paid out. Must match the currency of one of the project's current ruleset's surplus allowances.
    /// @param _minTokensUsed The minimum number of terminal tokens that should be used from the surplus allowance (including fees), as a fixed point number with 18 decimals. If the amount of surplus used would be less than this amount, the transaction is reverted.
    /// @param _beneficiary The address to send the funds to.
    /// @param _memo A memo to pass along to the emitted event.
    /// @return netAmountPaidOut The number of tokens that were sent to the beneficiary, as a fixed point number with the same amount of decimals as the terminal.
    function _useAllowanceOf(
        uint256 _projectId,
        address _token,
        uint256 _amount,
        uint256 _currency,
        uint256 _minTokensUsed,
        address payable _beneficiary,
        string memory _memo
    ) internal returns (uint256 netAmountPaidOut) {
        // Record the use of the allowance.
        (JBRuleset memory _ruleset, uint256 _amountPaidOut) = STORE.recordUsedAllowanceOf(
            _projectId, _accountingContextForTokenOf[_projectId][_token], _amount, _currency
        );

        // The amount being withdrawn must be at least as much as was expected.
        if (_amountPaidOut < _minTokensUsed) revert INADEQUATE_PAYOUT_AMOUNT();

        // Get a reference to the project owner.
        // The project owner will receive tokens minted by paying the platform fee.
        address _projectOwner = PROJECTS.ownerOf(_projectId);

        // Keep a reference to the fee.
        // The fee is 0 if the sender is marked as feeless or if the fee beneficiary project doesn't accept the `_token`.
        uint256 _feePercent = isFeelessAddress[msg.sender] ? 0 : FEE;

        unchecked {
            // Take a fee from the `_amountPaidOut`, if needed.
            // The net amount is the final amount withdrawn after the fee has been taken.
            netAmountPaidOut = _amountPaidOut
                - (
                    _feePercent == 0
                        ? 0
                        : _takeFeeFrom(
                            _projectId,
                            _token,
                            _amountPaidOut,
                            _feePercent,
                            _projectOwner,
                            _ruleset.shouldHoldFees()
                        )
                );
        }

        // Transfer any remaining balance to the beneficiary.
        if (netAmountPaidOut != 0) {
            _transferFor(address(this), _beneficiary, _token, netAmountPaidOut);
        }

        emit UseAllowance(
            _ruleset.rulesetId,
            _ruleset.cycleNumber,
            _projectId,
            _beneficiary,
            _amount,
            _amountPaidOut,
            netAmountPaidOut,
            _memo,
            msg.sender
        );
    }

    /// @notice Sends payouts to the payout splits group specified in a project's ruleset.
    /// @param _projectId The ID of the project to send the payouts of.
    /// @param _token The address of the token being paid out.
    /// @param _domain The domain of the split group being paid.
    /// @param _amount The total amount being paid out, as a fixed point number with the same number of decimals as this terminal.
    /// @param _feePercent The fee percent, out of `JBConstants.MAX_FEE`, to take from the payout.
    /// @return _amount The leftover amount (zero if the splits add up to 100%).
    /// @return amountEligibleForFees The total amount of funds which were paid out and are eligible for fees.
    function _sendPayoutsToSplitGroupOf(
        uint256 _projectId,
        address _token,
        uint256 _domain,
        uint256 _amount,
        uint256 _feePercent
    ) internal returns (uint256, uint256 amountEligibleForFees) {
        // The total percentage available to split
        uint256 _leftoverPercentage = JBConstants.SPLITS_TOTAL_PERCENT;

        // Get a reference to the project's payout splits.
        JBSplit[] memory _splits = SPLITS.splitsOf(_projectId, _domain, uint256(uint160(_token)));

        // Keep a reference to the split being iterated on.
        JBSplit memory _split;

        // Keep a reference to the number of splits being iterated on.
        uint256 _numberOfSplits = _splits.length;

        // Transfer between all splits.
        for (uint256 _i; _i < _numberOfSplits;) {
            // Get a reference to the split being iterated on.
            _split = _splits[_i];

            // The amount to send to the split.
            uint256 _payoutAmount = PRBMath.mulDiv(_amount, _split.percent, _leftoverPercentage);

            // The final payout amount after taking out any fees.
            uint256 _netPayoutAmount =
                _sendPayoutToSplit(_split, _projectId, _token, _payoutAmount, _feePercent);

            // If the split hook is a feeless address, this payout doesn't incur a fee.
            if (_netPayoutAmount != 0 && _netPayoutAmount != _payoutAmount) {
                amountEligibleForFees += _payoutAmount;
            }

            if (_payoutAmount != 0) {
                // Subtract from the amount to be sent to the beneficiary.
                unchecked {
                    _amount -= _payoutAmount;
                }
            }

            unchecked {
                // Decrement the leftover percentage.
                _leftoverPercentage -= _split.percent;
            }

            emit SendPayoutToSplit(
                _projectId,
                _domain,
                uint256(uint160(_token)),
                _split,
                _payoutAmount,
                _netPayoutAmount,
                msg.sender
            );

            unchecked {
                ++_i;
            }
        }

        return (_amount, amountEligibleForFees);
    }

    /// @notice Sends a payout to a split.
    /// @param _split The split to pay.
    /// @param _projectId The ID of the project the split was specified by.
    /// @param _token The address of the token being paid out.
    /// @param _amount The total amount that the split is being paid, as a fixed point number with the same number of decimals as this terminal.
    /// @param _feePercent The fee percent, out of `JBConstants.MAX_FEE`, to take from the payout.
    /// @return netPayoutAmount The amount sent to the split after subtracting fees.
    function _sendPayoutToSplit(
        JBSplit memory _split,
        uint256 _projectId,
        address _token,
        uint256 _amount,
        uint256 _feePercent
    ) internal returns (uint256 netPayoutAmount) {
        // By default, the net payout amount is the full amount. This will be adjusted if fees are taken.
        netPayoutAmount = _amount;

        // If there's a split hook set, transfer to its `process` function.
        if (_split.splitHook != IJBSplitHook(address(0))) {
            // This payouts is eligible for a fee since the funds are leaving this contract and the split hook isn't listed as feeless.
            if (_feePercent != 0 && !isFeelessAddress[address(_split.splitHook)]) {
                unchecked {
                    netPayoutAmount -= JBFees.feeIn(_amount, _feePercent);
                }
            }

            // Trigger any inherited pre-transfer logic.
            _beforeTransferFor(address(_split.splitHook), _token, netPayoutAmount);

            // Create the data to send to the split hook.
            JBSplitHookPayload memory _data = JBSplitHookPayload({
                token: _token,
                amount: netPayoutAmount,
                decimals: _accountingContextForTokenOf[_projectId][_token].decimals,
                projectId: _projectId,
                group: uint256(uint160(_token)),
                split: _split
            });

            // Trigger the split hook's `process` function.
            bytes memory _reason;

            if (
                ERC165Checker.supportsInterface(
                    address(_split.splitHook), type(IJBSplitHook).interfaceId
                )
            ) {
                // Keep a reference to the value that'll be paid to the split hook as a `msg.value`.
                uint256 _payValue = _token == JBTokenList.ETH ? netPayoutAmount : 0;

                // If this terminal's token is ETH, send it in `msg.value`.
                try _split.splitHook.process{value: _payValue}(_data) {}
                catch (bytes memory __reason) {
                    _reason = __reason.length == 0 ? abi.encode("Process fail") : __reason;
                }
            } else {
                _reason = abi.encode("IERC165 fail");
            }

            // If the split hook's `process` failed, or if its `IERC165` check failed:
            if (_reason.length != 0) {
                // Revert the payout.
                _revertPayoutFrom(
                    _projectId, _token, address(_split.splitHook), netPayoutAmount, _amount
                );

                // Set the net payout amount to 0 to signal the reversion.
                netPayoutAmount = 0;

                emit PayoutReverted(_projectId, _split, _amount, _reason, msg.sender);
            }

            // Otherwise, if a project is specified, make a payment to it.
        } else if (_split.projectId != 0) {
            // Get a reference to the `IJBTerminal` being used.
            IJBTerminal _terminal = DIRECTORY.primaryTerminalOf(_split.projectId, _token);

            // The project must have a terminal to send funds to.
            if (_terminal == IJBTerminal(address(0))) {
                // If it doesn't have a terminal for the token:
                // Set the net payout amount to 0 to signal the reversion.
                netPayoutAmount = 0;

                // Revert the payout.
                _revertPayoutFrom(_projectId, _token, address(0), 0, _amount);

                // Specify the reason for reverting.
                bytes memory _reason = "Terminal not found";

                emit PayoutReverted(_projectId, _split, _amount, _reason, msg.sender);
            } else {
                // This payout is eligible for a fee since the funds are leaving this terminal and the receiving terminal isn't a feeless address.
                if (_terminal != this && _feePercent != 0 && !isFeelessAddress[address(_terminal)])
                {
                    unchecked {
                        netPayoutAmount -= JBFees.feeIn(_amount, _feePercent);
                    }
                }

                // Trigger any inherited pre-transfer logic.
                _beforeTransferFor(address(_terminal), _token, netPayoutAmount);

                // Keep a reference to the amount that'll be paid as a `msg.value`.
                uint256 _payValue = _token == JBTokenList.ETH ? netPayoutAmount : 0;

                // Add to balance if prefered.
                if (_split.preferAddToBalance) {
                    bytes memory _metadata = bytes(abi.encodePacked(_projectId));
                    try _terminal.addToBalanceOf{value: _payValue}(
                        _split.projectId,
                        _token,
                        netPayoutAmount,
                        false,
                        "",
                        // Send `_projectId` in the metadata as a referral.
                        _metadata
                    ) {} catch (bytes memory _reason) {
                        // If an error occurred, revert the payout.
                        _revertPayoutFrom(
                            _projectId, _token, address(_terminal), netPayoutAmount, _amount
                        );

                        // Set the net payout amount to 0 to signal the reversion.
                        netPayoutAmount = 0;

                        emit PayoutReverted(_projectId, _split, _amount, _reason, msg.sender);
                    }
                } else {
                    try _terminal.pay{value: _payValue}(
                        _split.projectId,
                        _token,
                        netPayoutAmount,
                        _split.beneficiary != address(0) ? _split.beneficiary : msg.sender,
                        0,
                        "",
                        // Send `_projectId` in the metadata as a referral.
                        bytes(abi.encodePacked(_projectId))
                    ) {} catch (bytes memory _reason) {
                        // If an error occurred, revert the payout.
                        _revertPayoutFrom(
                            _projectId, _token, address(_terminal), netPayoutAmount, _amount
                        );

                        // Set the net payout amount to 0 to signal the reversion.
                        netPayoutAmount = 0;

                        emit PayoutReverted(_projectId, _split, _amount, _reason, msg.sender);
                    }
                }
            }
        } else {
            // This payout is eligible for a fee since the funds are leaving this contract and the beneficiary isn't a feeless address.
            if (_feePercent != 0) {
                unchecked {
                    netPayoutAmount -= JBFees.feeIn(_amount, _feePercent);
                }
            }

            // If there's a beneficiary, send the funds directly to the beneficiary. Otherwise send them to the `msg.sender`.
            _transferFor(
                address(this),
                _split.beneficiary != address(0) ? _split.beneficiary : payable(msg.sender),
                _token,
                netPayoutAmount
            );
        }
    }

    /// @notice Fulfills a list of pay hook payloads.
    /// @param _projectId The ID of the project being paid and forwarding payloads to pay hooks.
    /// @param _payloads The payloads being fulfilled.
    /// @param _tokenAmount The amount of tokens that the project was paid.
    /// @param _payer The address that sent the payment.
    /// @param _ruleset The ruleset the payment is being accepted during.
    /// @param _beneficiary The address which receives tokens that the payment yields.
    /// @param _beneficiaryTokenCount The amount of tokens that are being minted and sent to the beneificary.
    /// @param _metadata Bytes to send along to the emitted event, as well as the data hook and pay hook if applicable.
    function _fulfillPayHookPayloadsFor(
        uint256 _projectId,
        JBPayHookPayload[] memory _payloads,
        JBTokenAmount memory _tokenAmount,
        address _payer,
        JBRuleset memory _ruleset,
        address _beneficiary,
        uint256 _beneficiaryTokenCount,
        bytes memory _metadata
    ) internal {
        // The accounting context.
        JBDidPayData memory _data = JBDidPayData(
            _payer,
            _projectId,
            _ruleset.rulesetId,
            _tokenAmount,
            _tokenAmount,
            _ruleset.weight,
            _beneficiaryTokenCount,
            _beneficiary,
            bytes(""),
            _metadata
        );

        // Keep a reference to the payload being iterated on.
        JBPayHookPayload memory _payload;

        // Keep a reference to the number of payloads to iterate through.
        uint256 _numberOfPayloads = _payloads.length;

        // Fulfill each payload.
        for (uint256 _i; _i < _numberOfPayloads;) {
            // Set the payload being iterated on.
            _payload = _payloads[_i];

            // Pass the correct token `forwardedAmount` to the hook.
            _data.forwardedAmount = JBTokenAmount({
                value: _payload.amount,
                token: _tokenAmount.token,
                decimals: _tokenAmount.decimals,
                currency: _tokenAmount.currency
            });

            // Pass the correct metadata from the data hook.
            _data.dataHookMetadata = _payload.metadata;

            // Trigger any inherited pre-transfer logic.
            _beforeTransferFor(address(_payload.hook), _tokenAmount.token, _payload.amount);

            // Keep a reference to the amount that'll be paid as a `msg.value`.
            uint256 _payValue = _tokenAmount.token == JBTokenList.ETH ? _payload.amount : 0;

            // Fulfill the payload.
            _payload.hook.didPay{value: _payValue}(_data);

            emit HookDidPay(_payload.hook, _data, _payload.amount, msg.sender);

            unchecked {
                ++_i;
            }
        }
    }

    /// @notice Fulfills a list of redeem hook payloads.
    /// @param _projectId The ID of the project being redeemed from and forwarding payloads to redeem hooks.
    /// @param _beneficiaryTokenAmount The number of tokens that are being reclaimed from the project.
    /// @param _holder The address that holds the tokens being redeemed.
    /// @param _tokenCount The number of tokens being redeemed.
    /// @param _metadata Bytes to send along to the emitted event, as well as the data hook and redeem hook if applicable.
    /// @param _ruleset The ruleset the redemption is being made during as a `JBRuleset` struct.
    /// @param _beneficiary The address receiving any terminal tokens that are reclaimed by this redemption.
    /// @param _payloads The payloads being fulfilled.
    /// @param _feePercent The fee percent, out of `JBConstants.MAX_FEE`, to take from the redemption.
    /// @return amountEligibleForFees The amount of funds which were allocated to redeem hooks and are eligible for fees.
    function _fulfillRedemptionHookPayloadsFor(
        uint256 _projectId,
        JBTokenAmount memory _beneficiaryTokenAmount,
        address _holder,
        uint256 _tokenCount,
        bytes memory _metadata,
        JBRuleset memory _ruleset,
        address payable _beneficiary,
        JBRedeemHookPayload[] memory _payloads,
        uint256 _feePercent
    ) internal returns (uint256 amountEligibleForFees) {
        // Keep a reference to the data that'll get send to redeem hooks.
        JBDidRedeemData memory _data = JBDidRedeemData(
            _holder,
            _projectId,
            _ruleset.rulesetId,
            _tokenCount,
            _beneficiaryTokenAmount,
            _beneficiaryTokenAmount,
            _ruleset.redemptionRate(),
            _beneficiary,
            "",
            _metadata
        );

        // Keep a reference to the payload being iterated on.
        JBRedeemHookPayload memory _payload;

        // Keep a reference to the number of payloads being iterated through.
        uint256 _numberOfPayloads = _payloads.length;

        for (uint256 _i; _i < _numberOfPayloads;) {
            // Set the payload being iterated on.
            _payload = _payloads[_i];

            // Trigger any inherited pre-transfer logic.
            _beforeTransferFor(
                address(_payload.hook), _beneficiaryTokenAmount.token, _payload.amount
            );

            // Get the fee for the payload amount.
            uint256 _payloadAmountFee =
                _feePercent == 0 ? 0 : JBFees.feeIn(_payload.amount, _feePercent);

            // Add the payload's amount to the amount eligible for having a fee taken.
            if (_payloadAmountFee != 0) {
                amountEligibleForFees += _payload.amount;
                _payload.amount -= _payloadAmountFee;
            }

            // Pass the correct token `forwardedAmount` to the hook.
            _data.forwardedAmount = JBTokenAmount({
                value: _payload.amount,
                token: _beneficiaryTokenAmount.token,
                decimals: _beneficiaryTokenAmount.decimals,
                currency: _beneficiaryTokenAmount.currency
            });

            // Pass the correct metadata from the data hook.
            _data.dataHookMetadata = _payload.metadata;

            // Keep a reference to the amount that'll be paid as a `msg.value`.
            uint256 _payValue =
                _beneficiaryTokenAmount.token == JBTokenList.ETH ? _payload.amount : 0;

            // Fulfill the payload.
            _payload.hook.didRedeem{value: _payValue}(_data);

            emit HookDidRedeem(_payload.hook, _data, _payload.amount, _payloadAmountFee, msg.sender);

            unchecked {
                ++_i;
            }
        }
    }

    /// @notice Takes a fee into the platform's project (with the `_FEE_BENEFICIARY_PROJECT_ID`).
    /// @param _projectId The ID of the project paying the fee.
    /// @param _token The address of the token that the fee is being paid in.
    /// @param _amount The fee's token amount, as a fixed point number with 18 decimals.
    /// @param _feePercent The fee percent, out of `JBConstants.MAX_FEE`, to take.
    /// @param _beneficiary The address to mint the platform's project's tokens for.
    /// @param _shouldHoldFees If fees should be tracked and held instead of being exercised immediately.
    /// @return feeAmount The amount of the fee taken.
    function _takeFeeFrom(
        uint256 _projectId,
        address _token,
        uint256 _amount,
        uint256 _feePercent,
        address _beneficiary,
        bool _shouldHoldFees
    ) internal returns (uint256 feeAmount) {
        // Get a reference to the fee amount.
        feeAmount = JBFees.feeIn(_amount, _feePercent);

        if (_shouldHoldFees) {
            // Store the held fee.
            _heldFeesOf[_projectId].push(JBFee(_amount, uint32(_feePercent), _beneficiary));

            emit HoldFee(_projectId, _amount, _feePercent, _beneficiary, msg.sender);
        } else {
            // Get the terminal that'll receive the fee if one wasn't provided.
            IJBTerminal _feeTerminal =
                DIRECTORY.primaryTerminalOf(_FEE_BENEFICIARY_PROJECT_ID, _token);

            // Process the fee.
            _processFee(_projectId, _token, feeAmount, _beneficiary, _feeTerminal);

            emit ProcessFee(_projectId, feeAmount, false, _beneficiary, msg.sender);
        }
    }

    /// @notice Process a fee of the specified amount from a project.
    /// @param _projectId The ID of the project paying the fee.
    /// @param _token The token the fee is being paid in.
    /// @param _amount The fee amount, as a fixed point number with 18 decimals.
    /// @param _beneficiary The address which will receive any platform tokens minted.
    /// @param _feeTerminal The terminal that'll receive the fee.
    function _processFee(
        uint256 _projectId,
        address _token,
        uint256 _amount,
        address _beneficiary,
        IJBTerminal _feeTerminal
    ) internal {
        if (address(_feeTerminal) == address(0)) {
            _revertPayoutFrom(_projectId, _token, address(0), 0, _amount);

            // Specify the reason for reverting.
            bytes memory _reason = "Fee not accepted";

            emit FeeReverted(_projectId, _FEE_BENEFICIARY_PROJECT_ID, _amount, _reason, msg.sender);
            return;
        }

        // Trigger any inherited pre-transfer logic if funds will be transferred.
        if (address(_feeTerminal) != address(this)) {
            _beforeTransferFor(address(_feeTerminal), _token, _amount);
        }

        // Keep a reference to the amount that'll be paid as a `msg.value`.
        uint256 _payValue = _token == JBTokenList.ETH ? _amount : 0;

        try _feeTerminal
            // Send the fee.
            // If this terminal's token is ETH, send it in `msg.value`.
            .pay{value: _payValue}(
            _FEE_BENEFICIARY_PROJECT_ID,
            _token,
            _amount,
            _beneficiary,
            0,
            "",
            // Send the `projectId` in the metadata.
            bytes(abi.encodePacked(_projectId))
        ) {} catch (bytes memory _reason) {
            _revertPayoutFrom(
                _projectId,
                _token,
                address(_feeTerminal) != address(this) ? address(_feeTerminal) : address(0),
                address(_feeTerminal) != address(this) ? _amount : 0,
                _amount
            );
            emit FeeReverted(_projectId, _FEE_BENEFICIARY_PROJECT_ID, _amount, _reason, msg.sender);
        }
    }

    /// @notice Unlock held fees based on the specified amount.
    /// @param _projectId The project held fees are being unlocked for.
    /// @param _amount The amount to base the calculation on, as a fixed point number with the same number of decimals as this terminal.
    /// @return unlockedFees The amount of held fees that were unlocked, as a fixed point number with the same number of decimals as this terminal
    function _unlockHeldFees(uint256 _projectId, uint256 _amount)
        internal
        returns (uint256 unlockedFees)
    {
        // Get a reference to the project's held fees.
        JBFee[] memory _heldFees = _heldFeesOf[_projectId];

        // Delete the current held fees.
        delete _heldFeesOf[_projectId];

        // Get a reference to the leftover amount once all fees have been settled.
        uint256 leftoverAmount = _amount;

        // Keep a reference to the number of held fees.
        uint256 _numberOfHeldFees = _heldFees.length;

        // Process each fee.
        for (uint256 _i; _i < _numberOfHeldFees;) {
            if (leftoverAmount == 0) {
                _heldFeesOf[_projectId].push(_heldFees[_i]);
            } else {
                // Notice here we take `feeIn` on the stored `.amount`.
                uint256 _feeAmount = (
                    _heldFees[_i].fee == 0
                        ? 0
                        : JBFees.feeIn(_heldFees[_i].amount, _heldFees[_i].fee)
                );

                if (leftoverAmount >= _heldFees[_i].amount - _feeAmount) {
                    unchecked {
                        leftoverAmount = leftoverAmount - (_heldFees[_i].amount - _feeAmount);
                        unlockedFees += _feeAmount;
                    }
                } else {
                    // And here we overwrite with `feeFrom` the `leftoverAmount`
                    _feeAmount = _heldFees[_i].fee == 0
                        ? 0
                        : JBFees.feeFrom(leftoverAmount, _heldFees[_i].fee);

                    unchecked {
                        _heldFeesOf[_projectId].push(
                            JBFee(
                                _heldFees[_i].amount - (leftoverAmount + _feeAmount),
                                _heldFees[_i].fee,
                                _heldFees[_i].beneficiary
                            )
                        );
                        unlockedFees += _feeAmount;
                    }
                    leftoverAmount = 0;
                }
            }

            unchecked {
                ++_i;
            }
        }

        emit UnlockHeldFees(_projectId, _amount, unlockedFees, leftoverAmount, msg.sender);
    }

    /// @notice Reverts an expected payout from a project.
    /// @param _projectId The ID of the project having its payout reverted.
    /// @param _token The address of the token the payout was expected to be made in.
    /// @param _expectedDestination The address the payout was expected to go to.
    /// @param _allowanceAmount The amount that the `_expectedDestination` has been allowed to use.
    /// @param _depositAmount The amount of the payout as debited from the project's balance.
    function _revertPayoutFrom(
        uint256 _projectId,
        address _token,
        address _expectedDestination,
        uint256 _allowanceAmount,
        uint256 _depositAmount
    ) internal {
        // Cancel allowance if needed.
        if (_allowanceAmount != 0 && _token != JBTokenList.ETH) {
            IERC20(_token).safeDecreaseAllowance(_expectedDestination, _allowanceAmount);
        }

        // Add the reverted amount back to project's balance.
        STORE.recordAddedBalanceFor(_projectId, _token, _depositAmount);
    }

    /// @notice Transfers tokens.
    /// @param _from The address the transfer should originate from.
    /// @param _to The address the transfer should go to.
    /// @param _token The token being transfered.
    /// @param _amount The number of tokens being transferred, as a fixed point number with the same number of decimals as this terminal.
    function _transferFor(address _from, address payable _to, address _token, uint256 _amount)
        internal
        virtual
    {
        // If the token is ETH, assume the native token standard.
        if (_token == JBTokenList.ETH) return Address.sendValue(_to, _amount);

        if (_from == address(this)) return IERC20(_token).safeTransfer(_to, _amount);

        // If there's sufficient approval, transfer normally.
        if (IERC20(_token).allowance(address(_from), address(this)) >= _amount) {
            return IERC20(_token).safeTransferFrom(_from, _to, _amount);
        }

        // Otherwise we attempt to use the PERMIT2 method.
        PERMIT2.transferFrom(_from, _to, uint160(_amount), _token);
    }

    /// @notice Logic to be triggered before transferring tokens from this terminal.
    /// @param _to The address the transfer is going to.
    /// @param _token The token being transferred.
    /// @param _amount The number of tokens being transferred, as a fixed point number with the same number of decimals as this terminal.
    function _beforeTransferFor(address _to, address _token, uint256 _amount) internal virtual {
        // If the token is ETH, assume the native token standard.
        if (_token == JBTokenList.ETH) return;
        IERC20(_token).safeIncreaseAllowance(_to, _amount);
    }

    /// @notice Sets the permit2 allowance for a token.
    /// @param _allowance The allowance to set using permit2.
    /// @param _token The token being allowed.
    function _permitAllowance(JBSingleAllowanceData memory _allowance, address _token) internal {
        PERMIT2.permit(
            msg.sender,
            IAllowanceTransfer.PermitSingle({
                details: IAllowanceTransfer.PermitDetails({
                    token: _token,
                    amount: _allowance.amount,
                    expiration: _allowance.expiration,
                    nonce: _allowance.nonce
                }),
                spender: address(this),
                sigDeadline: _allowance.sigDeadline
            }),
            _allowance.signature
        );
    }
}
