// SPDX-License-Identifier: MIT
pragma solidity ^0.8.16;

import {Ownable} from '@openzeppelin/contracts/access/Ownable.sol';
import {Address} from '@openzeppelin/contracts/utils/Address.sol';
import {IERC165} from '@openzeppelin/contracts/utils/introspection/IERC165.sol';
import {IERC20} from '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import {SafeERC20} from '@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol';
import {ERC165Checker} from '@openzeppelin/contracts/utils/introspection/ERC165Checker.sol';
import {PRBMath} from '@paulrberg/contracts/math/PRBMath.sol';
import {IJBAllowanceTerminal3_1} from './interfaces/IJBAllowanceTerminal3_1.sol';
import {IJBController3_1} from './interfaces/IJBController3_1.sol';
import {IJBDirectory} from './interfaces/IJBDirectory.sol';
import {IJBPayoutRedemptionTerminal} from './interfaces/IJBPayoutRedemptionTerminal.sol';
import {IJBSplitsStore} from './interfaces/IJBSplitsStore.sol';
import {IJBOperatable} from './interfaces/IJBOperatable.sol';
import {IJBOperatorStore} from './interfaces/IJBOperatorStore.sol';
import {IJBPaymentTerminal} from './interfaces/IJBPaymentTerminal.sol';
import {IJBPayoutTerminal3_1} from './interfaces/IJBPayoutTerminal3_1.sol';
import {IJBProjects} from './interfaces/IJBProjects.sol';
import {IJBRedemptionTerminal} from './interfaces/IJBRedemptionTerminal.sol';
import {IJBTerminalStore} from './interfaces/IJBTerminalStore.sol';
import {IJBSplitAllocator} from './interfaces/IJBSplitAllocator.sol';
import {JBConstants} from './libraries/JBConstants.sol';
import {JBFees} from './libraries/JBFees.sol';
import {JBFundingCycleMetadataResolver} from './libraries/JBFundingCycleMetadataResolver.sol';
import {JBOperations} from './libraries/JBOperations.sol';
import {JBTokens} from './libraries/JBTokens.sol';
import {JBTokenStandards} from './libraries/JBTokenStandards.sol';
import {JBDidRedeemData3_1_1} from './structs/JBDidRedeemData3_1_1.sol';
import {JBDidPayData3_1_1} from './structs/JBDidPayData3_1_1.sol';
import {JBFee} from './structs/JBFee.sol';
import {JBFundingCycle} from './structs/JBFundingCycle.sol';
import {JBPayDelegateAllocation3_1_1} from './structs/JBPayDelegateAllocation3_1_1.sol';
import {JBRedemptionDelegateAllocation3_1_1} from './structs/JBRedemptionDelegateAllocation3_1_1.sol';
import {JBSplit} from './structs/JBSplit.sol';
import {JBSplitAllocationData} from './structs/JBSplitAllocationData.sol';
import {JBTokenAccountingContext} from './structs/JBTokenAccountingContext.sol';
import {JBTokenAmount} from './structs/JBTokenAmount.sol';
import {JBOperatable} from './abstract/JBOperatable.sol';

/// @notice Generic terminal managing all inflows and outflows of funds into the protocol ecosystem.
contract JBPayoutRedemptionTerminal is JBOperatable, Ownable, IJBPayoutRedemptionTerminal {
  // A library that parses the packed funding cycle metadata into a friendlier format.
  using JBFundingCycleMetadataResolver for JBFundingCycle;

  // A library that adds default safety checks to ERC20 functionality.
  using SafeERC20 for IERC20;

  //*********************************************************************//
  // --------------------------- custom errors ------------------------- //
  //*********************************************************************//

  error FEE_TOO_HIGH();
  error INADEQUATE_DISTRIBUTION_AMOUNT();
  error INADEQUATE_RECLAIM_AMOUNT();
  error INADEQUATE_TOKEN_COUNT();
  error NO_MSG_VALUE_ALLOWED();
  error PAY_TO_ZERO_ADDRESS();
  error REDEEM_TO_ZERO_ADDRESS();
  error TERMINAL_TOKENS_INCOMPATIBLE();
  error TOKEN_NOT_ACCEPTED();

  //*********************************************************************//
  // --------------------- internal stored constants ------------------- //
  //*********************************************************************//

  /// @notice Maximum fee that can be set for a funding cycle configuration.
  /// @dev Out of MAX_FEE (50_000_000 / 1_000_000_000).
  uint256 internal constant _FEE_CAP = 50_000_000;

  /// @notice The fee beneficiary project ID is 1, as it should be the first project launched during the deployment process.
  uint256 internal constant _FEE_BENEFICIARY_PROJECT_ID = 1;

  //*********************************************************************//
  // --------------------- internal stored properties ------------------ //
  //*********************************************************************//

  /// @notice Context describing how a token is accounted for by a project.
  /// @custom:param _projectId The ID of the project to which the token accounting context applies.
  /// @custom:param _token The address of the token being accounted for.
  mapping(uint256 => mapping(address => JBTokenAccountingContext))
    internal _accountingContextForTokenOf;

  /// @notice A list of tokens accepted by each project.
  /// @custom:param _projectId The ID of the project to get a list of accepted tokens for.
  mapping(uint256 => address[]) internal _tokensAcceptedBy;

  /// @notice Fees that are being held to be processed later.
  /// @custom:param _projectId The ID of the project for which fees are being held.
  mapping(uint256 => JBFee[]) internal _heldFeesOf;

  //*********************************************************************//
  // ---------------- public immutable stored properties --------------- //
  //*********************************************************************//

  /// @notice Mints ERC-721's that represent project ownership and transfers.
  IJBProjects public immutable override PROJECTS;

  /// @notice The directory of terminals and controllers for PROJECTS.
  IJBDirectory public immutable override DIRECTORY;

  /// @notice The contract that stores splits for each project.
  IJBSplitsStore public immutable override SPLITS;

  /// @notice The contract that stores and manages the terminal's data.
  IJBTerminalStore public immutable override STORE;

  //*********************************************************************//
  // --------------------- public stored properties -------------------- //
  //*********************************************************************//

  /// @notice The platform fee percent.
  /// @dev Out of MAX_FEE (25_000_000 / 1_000_000_000)
  uint256 public override fee = 25_000_000; // 2.5%

  /// @notice Addresses that can be paid towards from this terminal without incurring a fee.
  /// @dev Only addresses that are considered to be contained within the ecosystem can be feeless. Funds sent outside the ecosystem may incur fees despite being stored as feeless.
  /// @custom:param _address The address that can be paid toward.
  mapping(address => bool) public override isFeelessAddress;

  //*********************************************************************//
  // ------------------------- external views -------------------------- //
  //*********************************************************************//

  /// @notice Information on how a project accounts for tokens.
  /// @param _projectId The ID of the project to get token accounting info for.
  /// @param _token The token to check the accounting info for.
  /// @return The token's accounting info of decimals for the token.
  function accountingContextForTokenOf(
    uint256 _projectId,
    address _token
  ) external view override returns (JBTokenAccountingContext memory) {
    return _accountingContextForTokenOf[_projectId][_token];
  }

  /// @notice The tokens accepted by a project.
  /// @param _projectId The ID of the project to get accepted tokens for.
  /// @return tokenContexts The contexts of the accepted tokens.
  function tokenContextsAcceptedBy(
    uint256 _projectId
  ) external view override returns (JBTokenAccountingContext[] memory tokenContexts) {
    // Get a reference to all tokens accepted by the project;
    address[] memory _acceptedTokens = _tokensAcceptedBy[_projectId];

    // Keep a reference to the number of tokens the project accepts.
    uint256 _numberOfAcceptedTokens = _acceptedTokens.length;

    // Initialize the array that'll be returned.
    tokenContexts = new JBTokenAccountingContext[](_numberOfAcceptedTokens);

    // Iterate through each token.
    for (uint256 _i; _i < _numberOfAcceptedTokens; ) {
      JBTokenAccountingContext storage _context = _accountingContextForTokenOf[_projectId][
        _acceptedTokens[_i]
      ];
      tokenContexts[_i] = JBTokenAccountingContext({
        token: _context.token,
        decimals: _context.decimals,
        currency: _context.currency,
        standard: _context.standard
      });
      unchecked {
        ++_i;
      }
    }
  }

  /// @notice Gets the current overflowed amount in this terminal for a specified project, in terms of ETH.
  /// @dev The current overflow is represented as a fixed point number with 18 decimals.
  /// @param _projectId The ID of the project to get overflow for.
  /// @param _decimals The number of decimals included in the fixed point returned value.
  /// @param _currency The currency in which the ETH value is returned.
  /// @return The current amount of ETH overflow that project has in this terminal, as a fixed point number with 18 decimals.
  function currentOverflowOf(
    uint256 _projectId,
    uint256 _decimals,
    uint256 _currency
  ) external view virtual override returns (uint256) {
    return
      STORE.currentOverflowOf(
        this,
        _projectId,
        _tokensAcceptedBy[_projectId],
        _decimals,
        _currency
      );
  }

  /// @notice The fees that are currently being held to be processed later for each project.
  /// @param _projectId The ID of the project for which fees are being held.
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
    return
      _interfaceId == type(IJBPayoutRedemptionTerminal).interfaceId ||
      _interfaceId == type(IJBPayoutTerminal3_1).interfaceId ||
      _interfaceId == type(IJBAllowanceTerminal3_1).interfaceId ||
      _interfaceId == type(IJBRedemptionTerminal).interfaceId ||
      _interfaceId == type(IJBOperatable).interfaceId ||
      _interfaceId == type(IJBPaymentTerminal).interfaceId;
  }

  //*********************************************************************//
  // -------------------------- internal views ------------------------- //
  //*********************************************************************//

  /// @notice Checks the balance of tokens in this contract.
  /// @return The contract's balance.
  function _balance(address _token) internal view virtual returns (uint256) {
    if (_token == JBTokens.ETH) return address(this).balance;
    return IERC20(_token).balanceOf(address(this));
  }

  //*********************************************************************//
  // -------------------------- constructor ---------------------------- //
  //*********************************************************************//

  /// @param _operatorStore A contract storing operator assignments.
  /// @param _projects A contract which mints ERC-721's that represent project ownership and transfers.
  /// @param _directory A contract storing directories of terminals and controllers for each project.
  /// @param _splitsStore A contract that stores splits for each project.
  /// @param _store A contract that stores the terminal's data.
  /// @param _owner The address that will own this contract.
  constructor(
    IJBOperatorStore _operatorStore,
    IJBProjects _projects,
    IJBDirectory _directory,
    IJBSplitsStore _splitsStore,
    IJBTerminalStore _store,
    address _owner
  ) JBOperatable(_operatorStore) {
    PROJECTS = _projects;
    DIRECTORY = _directory;
    SPLITS = _splitsStore;
    STORE = _store;

    transferOwnership(_owner);
  }

  //*********************************************************************//
  // ---------------------- external transactions ---------------------- //
  //*********************************************************************//

  /// @notice Pay tokens to a project.
  /// @param _projectId The ID of the project being paid.
  /// @param _amount The amount of terminal tokens being received, as a fixed point number with the same amount of decimals as this terminal. If this terminal's token is ETH, this is ignored and msg.value is used in its place.
  /// @param _token The token being paid. This terminal ignores this property since it only manages one token.
  /// @param _beneficiary The address to mint tokens for and pass along to the funding cycle's data source and delegate.
  /// @param _minReturnedTokens The minimum number of project tokens expected in return, as a fixed point number with the same amount of decimals as this terminal.
  /// @param _memo A memo to pass along to the emitted event.
  /// @param _metadata Bytes to send along to the data source, delegate, and emitted event, if provided.
  /// @return The number of tokens minted for the beneficiary, as a fixed point number with 18 decimals.
  function pay(
    uint256 _projectId,
    address _token,
    uint256 _amount,
    address _beneficiary,
    uint256 _minReturnedTokens,
    string calldata _memo,
    bytes calldata _metadata
  ) external payable virtual override returns (uint256) {
    // Make sure the project has set an accounting context for the token being paid.
    if (_accountingContextForTokenOf[_projectId][_token].currency == 0) revert TOKEN_NOT_ACCEPTED();

    // Accept the token.
    _amount = _acceptToken(_token, _amount);

    return
      _pay(
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

  /// @notice Receives funds belonging to the specified project.
  /// @param _projectId The ID of the project to which the funds received belong.
  /// @param _amount The amount of tokens to add, as a fixed point number with the same number of decimals as this terminal. If this is an ETH terminal, this is ignored and msg.value is used instead.
  /// @param _token The token being paid. This terminal ignores this property since it only manages one currency.
  /// @param _shouldRefundHeldFees A flag indicating if held fees should be refunded based on the amount being added.
  /// @param _memo A memo to pass along to the emitted event.
  /// @param _metadata Extra data to pass along to the emitted event.
  function addToBalanceOf(
    uint256 _projectId,
    address _token,
    uint256 _amount,
    bool _shouldRefundHeldFees,
    string calldata _memo,
    bytes calldata _metadata
  ) external payable virtual override {
    // Make sure the project has set an accounting context for the token being paid.
    if (_accountingContextForTokenOf[_projectId][_token].currency == 0) revert TOKEN_NOT_ACCEPTED();

    // Accept the token.
    _amount = _acceptToken(_token, _amount);

    // Add to balance.
    _addToBalanceOf(_projectId, _token, _amount, _shouldRefundHeldFees, _memo, _metadata);
  }

  /// @notice Holders can redeem their tokens to claim the project's overflowed tokens, or to trigger rules determined by the project's current funding cycle's data source.
  /// @dev Only a token holder or a designated operator can redeem its tokens.
  /// @param _holder The account to redeem tokens for.
  /// @param _projectId The ID of the project to which the tokens being redeemed belong.
  /// @param _tokenCount The number of project tokens to redeem, as a fixed point number with 18 decimals.
  /// @param _token The token being reclaimed. This terminal ignores this property since it only manages one token.
  /// @param _minReturnedTokens The minimum amount of terminal tokens expected in return, as a fixed point number with the same amount of decimals as the terminal.
  /// @param _beneficiary The address to send the terminal tokens to.
  /// @param _metadata Bytes to send along to the data source, delegate, and emitted event, if provided.
  /// @return reclaimAmount The amount of terminal tokens that the project tokens were redeemed for, as a fixed point number with 18 decimals.
  function redeemTokensOf(
    address _holder,
    uint256 _projectId,
    address _token,
    uint256 _tokenCount,
    uint256 _minReturnedTokens,
    address payable _beneficiary,
    bytes memory _metadata
  )
    external
    virtual
    override
    requirePermission(_holder, _projectId, JBOperations.REDEEM)
    returns (uint256 reclaimAmount)
  {
    return
      _redeemTokensOf(
        _holder,
        _projectId,
        _token,
        _tokenCount,
        _minReturnedTokens,
        _beneficiary,
        _metadata
      );
  }

  /// @notice Distributes payouts for a project with the distribution limit of its current funding cycle.
  /// @dev Payouts are sent to the preprogrammed splits. Any leftover is sent to the project's owner.
  /// @dev Anyone can distribute payouts on a project's behalf. The project can preconfigure a wildcard split that is used to send funds to msg.sender. This can be used to incentivize calling this function.
  /// @dev All funds distributed outside of this contract or any feeless terminals incure the protocol fee.
  /// @param _projectId The ID of the project having its payouts distributed.
  /// @param _token The token being distributed. This terminal ignores this property since it only manages one token.
  /// @param _amount The amount of terminal tokens to distribute, as a fixed point number with same number of decimals as this terminal.
  /// @param _currency The expected currency of the amount being distributed. Must match the project's current funding cycle's distribution limit currency.
  /// @param _minReturnedTokens The minimum number of terminal tokens that the `_amount` should be valued at in terms of this terminal's currency, as a fixed point number with the same number of decimals as this terminal.
  /// @return netLeftoverDistributionAmount The amount that was sent to the project owner, as a fixed point number with the same amount of decimals as this terminal.
  function distributePayoutsOf(
    uint256 _projectId,
    address _token,
    uint256 _amount,
    uint256 _currency,
    uint256 _minReturnedTokens
  ) external virtual override returns (uint256 netLeftoverDistributionAmount) {
    return _distributePayoutsOf(_projectId, _token, _amount, _currency, _minReturnedTokens);
  }

  /// @notice Allows a project to send funds from its overflow up to the preconfigured allowance.
  /// @dev Only a project's owner or a designated operator can use its allowance.
  /// @dev Incurs the protocol fee.
  /// @param _projectId The ID of the project to use the allowance of.
  /// @param _token The token being distributed. This terminal ignores this property since it only manages one token.
  /// @param _amount The amount of terminal tokens to use from this project's current allowance, as a fixed point number with the same amount of decimals as this terminal.
  /// @param _currency The expected currency of the amount being distributed. Must match the project's current funding cycle's overflow allowance currency.
  /// @param _minReturnedTokens The minimum number of tokens that the `_amount` should be valued at in terms of this terminal's currency, as a fixed point number with 18 decimals.
  /// @param _beneficiary The address to send the funds to.
  /// @param _memo A memo to pass along to the emitted event.
  /// @return netDistributedAmount The amount of tokens that was distributed to the beneficiary, as a fixed point number with the same amount of decimals as the terminal.
  function useAllowanceOf(
    uint256 _projectId,
    address _token,
    uint256 _amount,
    uint256 _currency,
    uint256 _minReturnedTokens,
    address payable _beneficiary,
    string memory _memo
  )
    external
    virtual
    override
    requirePermission(PROJECTS.ownerOf(_projectId), _projectId, JBOperations.USE_ALLOWANCE)
    returns (uint256 netDistributedAmount)
  {
    return
      _useAllowanceOf(
        _projectId,
        _token,
        _amount,
        _currency,
        _minReturnedTokens,
        _beneficiary,
        _memo
      );
  }

  /// @notice Allows a project owner to migrate its funds and operations to a new terminal that accepts the same token type.
  /// @dev Only a project's owner or a designated operator can migrate it.
  /// @param _projectId The ID of the project being migrated.
  /// @param _token The address of the token being migrated.
  /// @param _to The terminal contract that will gain the project's funds.
  /// @return balance The amount of funds that were migrated, as a fixed point number with the same amount of decimals as this terminal.
  function migrate(
    uint256 _projectId,
    address _token,
    IJBPaymentTerminal _to
  )
    external
    virtual
    override
    requirePermission(PROJECTS.ownerOf(_projectId), _projectId, JBOperations.MIGRATE_TERMINAL)
    returns (uint256 balance)
  {
    // The terminal being migrated to must accept the same token as this terminal.
    if (_to.accountingContextForTokenOf(_projectId, _token).decimals == 0)
      revert TERMINAL_TOKENS_INCOMPATIBLE();

    // Record the migration in the store.
    balance = STORE.recordMigration(_projectId, _token);

    // Transfer the balance if needed.
    if (balance != 0) {
      // Trigger any inherited pre-transfer logic.
      _beforeTransferTo(address(_to), _token, balance);

      // If this terminal's token is ETH, send it in msg.value.
      uint256 _payableValue = _token == JBTokens.ETH ? balance : 0;

      // Withdraw the balance to transfer to the new terminal;
      _to.addToBalanceOf{value: _payableValue}(_projectId, _token, balance, false, '', bytes(''));
    }

    emit Migrate(_projectId, _to, balance, msg.sender);
  }

  /// @notice Process any fees that are being held for the project.
  /// @dev Only a project owner, an operator, or the contract's owner can process held fees.
  /// @param _projectId The ID of the project whos held fees should be processed.
  function processFees(
    uint256 _projectId,
    address _token
  )
    external
    virtual
    override
    requirePermissionAllowingOverride(
      PROJECTS.ownerOf(_projectId),
      _projectId,
      JBOperations.PROCESS_FEES,
      msg.sender == owner()
    )
  {
    // Get a reference to the project's held fees.
    JBFee[] memory _heldFees = _heldFeesOf[_projectId];

    // Delete the held fees.
    delete _heldFeesOf[_projectId];

    // Keep a reference to the amount.
    uint256 _amount;

    // Get the terminal for the protocol project.
    IJBPaymentTerminal _feeTerminal = DIRECTORY.primaryTerminalOf(
      _FEE_BENEFICIARY_PROJECT_ID,
      _token
    );

    // Keep a reference to the number of held fees.
    uint256 _numberOfHeldFees = _heldFees.length;

    // Process each fee.
    for (uint256 _i; _i < _numberOfHeldFees; ) {
      // Get the fee amount.
      _amount = (
        _heldFees[_i].fee == 0 ? 0 : JBFees.feeIn(_heldFees[_i].amount, _heldFees[_i].fee)
      );

      // Process the fee.
      _processFee(_projectId, _token, _amount, _heldFees[_i].beneficiary, _feeTerminal);

      emit ProcessFee(_projectId, _amount, true, _heldFees[_i].beneficiary, msg.sender);

      unchecked {
        ++_i;
      }
    }
  }

  /// @notice Allows the fee to be updated.
  /// @dev Only the owner of this contract can change the fee.
  /// @param _fee The new fee, out of MAX_FEE.
  function setFee(uint256 _fee) external virtual override onlyOwner {
    // The provided fee must be within the max.
    if (_fee > _FEE_CAP) revert FEE_TOO_HIGH();

    // Store the new fee.
    fee = _fee;

    emit SetFee(_fee, msg.sender);
  }

  /// @notice Sets whether projects operating on this terminal can pay towards the specified address without incurring a fee.
  /// @dev Only the owner of this contract can set addresses as feeless.
  /// @param _address The address that can be paid towards while still bypassing fees.
  /// @param _flag A flag indicating whether the terminal should be feeless or not.
  function setFeelessAddress(address _address, bool _flag) external virtual override onlyOwner {
    // Set the flag value.
    isFeelessAddress[_address] = _flag;

    emit SetFeelessAddress(_address, _flag, msg.sender);
  }

  /// @notice Sets accounting context for a token so that a project can begin accepting it.
  /// @param _projectId The ID of the project having its token accounting context set.
  /// @param _token The token that this terminal manages.
  /// @param _decimals The number of decimals the token fixed point amounts are expected to have.
  /// @param _currency The currency that this terminal's token adheres to for price feeds.
  /// @param _standard The token's standard.
  function setTokenAccountingContextFor(
    uint256 _projectId,
    address _token,
    uint8 _decimals,
    uint32 _currency,
    uint8 _standard
  ) external override {
    // Make sure the token accounting isn't already set.
    if (_accountingContextForTokenOf[_projectId][_token].decimals != 0) revert();

    // Add the token to the list of accepted tokens of the project.
    _tokensAcceptedBy[_projectId].push(_token);

    // Store the value.
    _accountingContextForTokenOf[_projectId][_token] = JBTokenAccountingContext({
      token: _token,
      decimals: _decimals,
      currency: _currency,
      standard: _standard
    });
  }

  //*********************************************************************//
  // ---------------------- internal transactions ---------------------- //
  //*********************************************************************//

  /// @notice Accepts an incoming token.
  /// @param _token The token being accepted.
  /// @param _amount The amount of tokens being accepted.
  /// @return The amount of tokens that have been accepted.
  function _acceptToken(address _token, uint256 _amount) internal returns (uint256) {
    // If the terminal's token is ETH, override `_amount` with msg.value.
    if (_token == JBTokens.ETH) return msg.value;

    // Amount must be greater than 0.
    if (msg.value != 0) revert NO_MSG_VALUE_ALLOWED();

    // If the terminal is rerouting the tokens within its own functions, there's nothing to transfer.
    if (msg.sender == address(this)) return _amount;

    // Get a reference to the balance before receiving tokens.
    uint256 _balanceBefore = _balance(_token);

    // Transfer tokens to this terminal from the msg sender.
    _transferFrom(msg.sender, payable(address(this)), _token, _amount);

    // The amount should reflect the change in balance.
    return _balance(_token) - _balanceBefore;
  }

  /// @notice Contribute tokens to a project.
  /// @param _token The address of the token being paid.
  /// @param _amount The amount of terminal tokens being received, as a fixed point number with the same amount of decimals as this terminal. If this terminal's token is ETH, this is ignored and msg.value is used in its place.
  /// @param _payer The address making the payment.
  /// @param _projectId The ID of the project being paid.
  /// @param _beneficiary The address to mint tokens for and pass along to the funding cycle's data source and delegate.
  /// @param _minReturnedTokens The minimum number of project tokens expected in return, as a fixed point number with the same amount of decimals as this terminal.
  /// @param _memo A memo to pass along to the emitted event.
  /// @param _metadata Bytes to send along to the data source, delegate, and emitted event, if provided.
  /// @return beneficiaryTokenCount The number of tokens minted for the beneficiary, as a fixed point number with 18 decimals.
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
    if (_beneficiary == address(0)) revert PAY_TO_ZERO_ADDRESS();

    // Define variables that will be needed outside the scoped section below.
    // Keep a reference to the funding cycle during which the payment is being made.
    JBFundingCycle memory _fundingCycle;

    // Scoped section prevents stack too deep. `_delegateAllocations` and `_tokenCount` only used within scope.
    {
      JBPayDelegateAllocation3_1_1[] memory _delegateAllocations;
      JBTokenAmount memory _tokenAmount;

      uint256 _tokenCount;

      // Get a reference to the token's accounting context.
      JBTokenAccountingContext memory _context = _accountingContextForTokenOf[_projectId][_token];

      // Bundle the amount info into a JBTokenAmount struct.
      _tokenAmount = JBTokenAmount(_token, _amount, _context.decimals, _context.currency);

      // Record the payment.
      (_fundingCycle, _tokenCount, _delegateAllocations) = STORE.recordPaymentFrom(
        _payer,
        _tokenAmount,
        _projectId,
        _beneficiary,
        _metadata
      );

      // Mint the tokens if needed.
      if (_tokenCount != 0)
        // Set token count to be the number of tokens minted for the beneficiary instead of the total amount.
        beneficiaryTokenCount = IJBController3_1(DIRECTORY.controllerOf(_projectId)).mintTokensOf(
          _projectId,
          _tokenCount,
          _beneficiary,
          '',
          true,
          true
        );

      // The token count for the beneficiary must be greater than or equal to the minimum expected.
      if (beneficiaryTokenCount < _minReturnedTokens) revert INADEQUATE_TOKEN_COUNT();

      // If delegate allocations were specified by the data source, fulfill them.
      if (_delegateAllocations.length != 0)
        _fulfillPayDelegateAllocationsFor(
          _projectId,
          _delegateAllocations,
          _tokenAmount,
          _payer,
          _fundingCycle,
          _beneficiary,
          beneficiaryTokenCount,
          _metadata
        );
    }

    emit Pay(
      _fundingCycle.configuration,
      _fundingCycle.number,
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

  /// @notice Receives funds belonging to the specified project.
  /// @param _projectId The ID of the project to which the funds received belong.
  /// @param _token The address of the token being added to the project's balance.
  /// @param _amount The amount of tokens to add, as a fixed point number with the same number of decimals as this terminal. If this is an ETH terminal, this is ignored and msg.value is used instead.
  /// @param _shouldRefundHeldFees A flag indicating if held fees should be refunded based on the amount being added.
  /// @param _memo A memo to pass along to the emitted event.
  /// @param _metadata Extra data to pass along to the emitted event.
  function _addToBalanceOf(
    uint256 _projectId,
    address _token,
    uint256 _amount,
    bool _shouldRefundHeldFees,
    string memory _memo,
    bytes memory _metadata
  ) internal {
    // Refund any held fees to make sure the project doesn't pay double for funds going in and out of the protocol.
    uint256 _refundedFees = _shouldRefundHeldFees ? _refundHeldFees(_projectId, _amount) : 0;

    // Record the added funds with any refunded fees.
    STORE.recordAddedBalanceFor(_projectId, _token, _amount + _refundedFees);

    emit AddToBalance(_projectId, _amount, _refundedFees, _memo, _metadata, msg.sender);
  }

  /// @notice Holders can redeem their tokens to claim the project's overflowed tokens, or to trigger rules determined by the project's current funding cycle's data source.
  /// @dev Only a token holder or a designated operator can redeem its tokens.
  /// @param _holder The account to redeem tokens for.
  /// @param _projectId The ID of the project to which the tokens being redeemed belong.
  /// @param _token The address of the token being reclaimed from the redemption.
  /// @param _tokenCount The number of project tokens to redeem, as a fixed point number with 18 decimals.
  /// @param _minReturnedTokens The minimum amount of terminal tokens expected in return, as a fixed point number with the same amount of decimals as the terminal.
  /// @param _beneficiary The address to send the terminal tokens to.
  /// @param _metadata Bytes to send along to the data source, delegate, and emitted event, if provided.
  /// @return reclaimAmount The amount of terminal tokens that the project tokens were redeemed for, as a fixed point number with 18 decimals.
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
    if (_beneficiary == address(0)) revert REDEEM_TO_ZERO_ADDRESS();

    // Define variables that will be needed outside the scoped section below.
    // Keep a reference to the funding cycle during which the redemption is being made.
    JBFundingCycle memory _fundingCycle;

    // Scoped section prevents stack too deep.
    {
      JBRedemptionDelegateAllocation3_1_1[] memory _delegateAllocations;

      // Scoped section prevents stack too deep. `_tokens` only used within scope.
      {
        // Keep a reference to the tokens accepted by the project.
        address[] memory _tokens = _tokensAcceptedBy[_projectId];

        // Record the redemption.
        (_fundingCycle, reclaimAmount, _delegateAllocations) = STORE.recordRedemptionFor(
          _holder,
          _projectId,
          _token,
          _tokens,
          _tokenCount,
          _metadata
        );
      }

      // Set the fee. No fee if the beneficiary is feeless, if the redemption rate is at its max, or if the fee beneficiary doesn't accept the given token.
      uint256 _feePercent = isFeelessAddress[_beneficiary] ||
        _fundingCycle.redemptionRate() == JBConstants.MAX_REDEMPTION_RATE
        ? 0
        : fee;

      // The amount being reclaimed must be at least as much as was expected.
      if (reclaimAmount < _minReturnedTokens) revert INADEQUATE_RECLAIM_AMOUNT();

      // Burn the project tokens.
      if (_tokenCount != 0)
        IJBController3_1(DIRECTORY.controllerOf(_projectId)).burnTokensOf(
          _holder,
          _projectId,
          _tokenCount,
          '',
          false
        );

      // Keep a reference to the amount being reclaimed that should have fees withheld from.
      uint256 _feeEligibleDistributionAmount;

      // If delegate allocations were specified by the data source, fulfill them.
      if (_delegateAllocations.length != 0) {
        // Get a reference to the token's accounting context.
        JBTokenAccountingContext memory _context = _accountingContextForTokenOf[_projectId][_token];

        // Fulfill the delegates.
        _feeEligibleDistributionAmount += _fulfillRedemptionDelegateAllocationsFor(
          _projectId,
          JBTokenAmount(_token, reclaimAmount, _context.decimals, _context.currency),
          _holder,
          _tokenCount,
          _metadata,
          _fundingCycle,
          _beneficiary,
          _delegateAllocations,
          _feePercent
        );
      }

      // Send the reclaimed funds to the beneficiary.
      if (reclaimAmount != 0) {
        // Get the fee for the reclaimed amount.
        uint256 _reclaimAmountFee = _feePercent == 0 ? 0 : JBFees.feeIn(reclaimAmount, _feePercent);

        if (_reclaimAmountFee != 0) {
          _feeEligibleDistributionAmount += reclaimAmount;
          reclaimAmount -= _reclaimAmountFee;
        }

        // Subtract the fee from the reclaim amount.
        if (reclaimAmount != 0) _transferFrom(address(this), _beneficiary, _token, reclaimAmount);
      }

      // Get the terminal for the protocol project.
      IJBPaymentTerminal _feeTerminal = DIRECTORY.primaryTerminalOf(
        _FEE_BENEFICIARY_PROJECT_ID,
        _token
      );

      // Take the fee from all outbound reclaimations.
      _feeEligibleDistributionAmount != 0
        ? _takeFeeFrom(
          _projectId,
          _token,
          _feeEligibleDistributionAmount,
          _feePercent,
          _beneficiary,
          false,
          _feeTerminal
        )
        : 0;
    }

    emit RedeemTokens(
      _fundingCycle.configuration,
      _fundingCycle.number,
      _projectId,
      _holder,
      _beneficiary,
      _tokenCount,
      reclaimAmount,
      _metadata,
      msg.sender
    );
  }

  /// @notice Distributes payouts for a project with the distribution limit of its current funding cycle.
  /// @dev Payouts are sent to the preprogrammed splits. Any leftover is sent to the project's owner.
  /// @dev Anyone can distribute payouts on a project's behalf. The project can preconfigure a wildcard split that is used to send funds to msg.sender. This can be used to incentivize calling this function.
  /// @dev All funds distributed outside of this contract or any feeless terminals incure the protocol fee.
  /// @param _projectId The ID of the project having its payouts distributed.
  /// @param _token The token being distributed.
  /// @param _amount The amount of terminal tokens to distribute, as a fixed point number with same number of decimals as this terminal.
  /// @param _currency The expected currency of the amount being distributed. Must match the project's current funding cycle's distribution limit currency.
  /// @param _minReturnedTokens The minimum number of terminal tokens that the `_amount` should be valued at in terms of this terminal's currency, as a fixed point number with the same number of decimals as this terminal.
  /// @return netLeftoverDistributionAmount The amount that was sent to the project owner, as a fixed point number with the same amount of decimals as this terminal.
  function _distributePayoutsOf(
    uint256 _projectId,
    address _token,
    uint256 _amount,
    uint256 _currency,
    uint256 _minReturnedTokens
  ) internal returns (uint256 netLeftoverDistributionAmount) {
    // Record the distribution.
    (JBFundingCycle memory _fundingCycle, uint256 _distributedAmount) = STORE.recordDistributionFor(
      _projectId,
      _token,
      _amount,
      _currency
    );

    // The amount being distributed must be at least as much as was expected.
    if (_distributedAmount < _minReturnedTokens) revert INADEQUATE_DISTRIBUTION_AMOUNT();

    // Get a reference to the project owner, which will receive tokens from paying the platform fee
    // and receive any extra distributable funds not allocated to payout splits.
    address payable _projectOwner = payable(PROJECTS.ownerOf(_projectId));

    // Keep a reference to the fee.
    // The fee is 0 if the fee beneficiary doesn't accept the given token.
    uint256 _feePercent = fee;

    // Payout to splits and get a reference to the leftover transfer amount after all splits have been paid.
    // Also get a reference to the amount that was distributed to splits from which fees should be taken.
    (
      uint256 _leftoverDistributionAmount,
      uint256 _feeEligibleDistributionAmount
    ) = _distributeToPayoutSplitsOf(
        _projectId,
        _token,
        _fundingCycle.configuration,
        _distributedAmount,
        _feePercent
      );

    if (_feePercent != 0) {
      // Leftover distribution amount is also eligible for a fee since the funds are going out of the ecosystem to _beneficiary.
      unchecked {
        _feeEligibleDistributionAmount += _leftoverDistributionAmount;
      }
    }

    // Define variables that will be needed outside the scoped section below.
    // Keep a reference to the fee amount that was paid.
    uint256 _feeTaken;

    // Scoped section prevents stack too deep. `_feeTerminal` only used within scope.
    {
      // Get the terminal for the protocol project.
      IJBPaymentTerminal _feeTerminal = DIRECTORY.primaryTerminalOf(
        _FEE_BENEFICIARY_PROJECT_ID,
        _token
      );

      // Take the fee.
      _feeTaken = _feeEligibleDistributionAmount != 0
        ? _takeFeeFrom(
          _projectId,
          _token,
          _feeEligibleDistributionAmount,
          _feePercent,
          _projectOwner,
          _fundingCycle.shouldHoldFees(),
          _feeTerminal
        )
        : 0;
    }

    // Transfer any remaining balance to the project owner and update returned leftover accordingly.
    if (_leftoverDistributionAmount != 0) {
      // Subtract the fee from the net leftover amount.
      netLeftoverDistributionAmount =
        _leftoverDistributionAmount -
        (_feePercent == 0 ? 0 : JBFees.feeIn(_leftoverDistributionAmount, _feePercent));

      // Transfer the amount to the project owner.
      _transferFrom(address(this), _projectOwner, _token, netLeftoverDistributionAmount);
    }

    emit DistributePayouts(
      _fundingCycle.configuration,
      _fundingCycle.number,
      _projectId,
      _projectOwner,
      _amount,
      _distributedAmount,
      _feeTaken,
      netLeftoverDistributionAmount,
      msg.sender
    );
  }

  /// @notice Allows a project to send funds from its overflow up to the preconfigured allowance.
  /// @dev Only a project's owner or a designated operator can use its allowance.
  /// @dev Incurs the protocol fee.
  /// @param _projectId The ID of the project to use the allowance of.
  /// @param _token The address of the token who's allowance is being used.
  /// @param _amount The amount of terminal tokens to use from this project's current allowance, as a fixed point number with the same amount of decimals as this terminal.
  /// @param _currency The expected currency of the amount being distributed. Must match the project's current funding cycle's overflow allowance currency.
  /// @param _minReturnedTokens The minimum number of tokens that the `_amount` should be valued at in terms of this terminal's currency, as a fixed point number with 18 decimals.
  /// @param _beneficiary The address to send the funds to.
  /// @param _memo A memo to pass along to the emitted event.
  /// @return netDistributedAmount The amount of tokens that was distributed to the beneficiary, as a fixed point number with the same amount of decimals as the terminal.
  function _useAllowanceOf(
    uint256 _projectId,
    address _token,
    uint256 _amount,
    uint256 _currency,
    uint256 _minReturnedTokens,
    address payable _beneficiary,
    string memory _memo
  ) internal returns (uint256 netDistributedAmount) {
    // Record the use of the allowance.
    (JBFundingCycle memory _fundingCycle, uint256 _distributedAmount) = STORE.recordUsedAllowanceOf(
      _projectId,
      _token,
      _amount,
      _currency
    );

    // The amount being withdrawn must be at least as much as was expected.
    if (_distributedAmount < _minReturnedTokens) revert INADEQUATE_DISTRIBUTION_AMOUNT();

    // Scoped section prevents stack too deep. `_projectOwner`, `_feePercent`, `_feeTerminal` and `_feeTaken` only used within scope.
    {
      // Get a reference to the project owner, which will receive tokens from paying the platform fee.
      address _projectOwner = PROJECTS.ownerOf(_projectId);

      // Keep a reference to the fee.
      // The fee is 0 if the sender is marked as feeless or if the fee beneficiary project doesn't accept the given token.
      uint256 _feePercent = isFeelessAddress[msg.sender] ? 0 : fee;

      // Get the terminal for the protocol project.
      IJBPaymentTerminal _feeTerminal = DIRECTORY.primaryTerminalOf(
        _FEE_BENEFICIARY_PROJECT_ID,
        _token
      );

      // Take a fee from the `_distributedAmount`, if needed.
      uint256 _feeTaken = _feePercent == 0
        ? 0
        : _takeFeeFrom(
          _projectId,
          _token,
          _distributedAmount,
          _feePercent,
          _projectOwner,
          _fundingCycle.shouldHoldFees(),
          _feeTerminal
        );

      unchecked {
        // The net amount is the withdrawn amount without the fee.
        netDistributedAmount = _distributedAmount - _feeTaken;
      }

      // Transfer any remaining balance to the beneficiary.
      if (netDistributedAmount != 0)
        _transferFrom(address(this), _beneficiary, _token, netDistributedAmount);
    }

    emit UseAllowance(
      _fundingCycle.configuration,
      _fundingCycle.number,
      _projectId,
      _beneficiary,
      _amount,
      _distributedAmount,
      netDistributedAmount,
      _memo,
      msg.sender
    );
  }

  /// @notice Pays out splits for a project's funding cycle configuration.
  /// @param _projectId The ID of the project for which payout splits are being distributed.
  /// @param _token The address of the token being distributed.
  /// @param _domain The domain of the splits to distribute the payout between.
  /// @param _amount The total amount being distributed, as a fixed point number with the same number of decimals as this terminal.
  /// @param _feePercent The percent of fees to take, out of MAX_FEE.
  /// @return If the leftover amount if the splits don't add up to 100%.
  /// @return feeEligibleDistributionAmount The total amount of distributions that are eligible to have fees taken from.
  function _distributeToPayoutSplitsOf(
    uint256 _projectId,
    address _token,
    uint256 _domain,
    uint256 _amount,
    uint256 _feePercent
  ) internal returns (uint256, uint256 feeEligibleDistributionAmount) {
    // The total percentage available to split
    uint256 _leftoverPercentage = JBConstants.SPLITS_TOTAL_PERCENT;

    // Get a reference to the project's payout splits.
    JBSplit[] memory _splits = SPLITS.splitsOf(_projectId, _domain, uint256(uint160(_token)));

    // Keep a reference to the split being iterated on.
    JBSplit memory _split;

    // Keep a reference to the number of splits being iterated on.
    uint256 _numberOfSplits = _splits.length;

    // Transfer between all splits.
    for (uint256 _i; _i < _numberOfSplits; ) {
      // Get a reference to the split being iterated on.
      _split = _splits[_i];

      // The amount to send towards the split.
      uint256 _payoutAmount = PRBMath.mulDiv(_amount, _split.percent, _leftoverPercentage);

      // The payout amount substracting any applicable incurred fees.
      uint256 _netPayoutAmount = _distributeToPayoutSplit(
        _split,
        _projectId,
        _token,
        _payoutAmount,
        _feePercent
      );

      // If the split allocator is set as feeless, this distribution is not eligible for a fee.
      if (_netPayoutAmount != 0 && _netPayoutAmount != _payoutAmount)
        feeEligibleDistributionAmount += _payoutAmount;

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

      emit DistributeToPayoutSplit(
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

    return (_amount, feeEligibleDistributionAmount);
  }

  /// @notice Pays out a split for a project's funding cycle configuration.
  /// @param _split The split to distribute payouts to.
  /// @param _projectId The ID of the project to which the split is originating.
  /// @param _token The address of the token being paid out.
  /// @param _amount The total amount being distributed to the split, as a fixed point number with the same number of decimals as this terminal.
  /// @param _feePercent The percent of fees to take, out of MAX_FEE.
  /// @return netPayoutAmount The amount sent to the split after subtracting fees.
  function _distributeToPayoutSplit(
    JBSplit memory _split,
    uint256 _projectId,
    address _token,
    uint256 _amount,
    uint256 _feePercent
  ) internal returns (uint256 netPayoutAmount) {
    // By default, the net payout amount is the full amount. This will be adjusted if fees are taken.
    netPayoutAmount = _amount;

    // If there's an allocator set, transfer to its `allocate` function.
    if (_split.allocator != IJBSplitAllocator(address(0))) {
      // This distribution is eligible for a fee since the funds are leaving this contract and the allocator isn't listed as feeless.
      if (_feePercent != 0 && !isFeelessAddress[address(_split.allocator)]) {
        unchecked {
          netPayoutAmount -= JBFees.feeIn(_amount, _feePercent);
        }
      }

      // Trigger any inherited pre-transfer logic.
      _beforeTransferTo(address(_split.allocator), _token, netPayoutAmount);

      // Get a reference to the token's accounting context.
      JBTokenAccountingContext memory _context = _accountingContextForTokenOf[_projectId][_token];

      // Create the data to send to the allocator.
      JBSplitAllocationData memory _data = JBSplitAllocationData(
        _token,
        netPayoutAmount,
        _context.decimals,
        _projectId,
        uint256(uint160(_token)),
        _split
      );

      // Trigger the allocator's `allocate` function.
      bytes memory _reason;

      if (
        ERC165Checker.supportsInterface(
          address(_split.allocator),
          type(IJBSplitAllocator).interfaceId
        )
      )
        // If this terminal's token is ETH, send it in msg.value.
        try
          _split.allocator.allocate{value: _token == JBTokens.ETH ? netPayoutAmount : 0}(_data)
        {} catch (bytes memory __reason) {
          _reason = __reason.length == 0 ? abi.encode('Allocate fail') : __reason;
        }
      else {
        _reason = abi.encode('IERC165 fail');
      }

      if (_reason.length != 0) {
        // Revert the payout.
        _revertTransferFrom(
          _projectId,
          _token,
          address(_split.allocator),
          netPayoutAmount,
          _amount
        );

        // Set the net payout amount to 0 to signal the reversion.
        netPayoutAmount = 0;

        emit PayoutReverted(_projectId, _split, _amount, _reason, msg.sender);
      }

      // Otherwise, if a project is specified, make a payment to it.
    } else if (_split.projectId != 0) {
      // Get a reference to the Juicebox terminal being used.
      IJBPaymentTerminal _terminal = DIRECTORY.primaryTerminalOf(_split.projectId, _token);

      // The project must have a terminal to send funds to.
      if (_terminal == IJBPaymentTerminal(address(0))) {
        // Set the net payout amount to 0 to signal the reversion.
        netPayoutAmount = 0;

        // Revert the payout.
        _revertTransferFrom(_projectId, _token, address(0), 0, _amount);

        emit PayoutReverted(_projectId, _split, _amount, 'Terminal not found', msg.sender);
      } else {
        // This distribution is eligible for a fee since the funds are leaving this contract and the terminal isn't listed as feeless.
        if (_terminal != this && _feePercent != 0 && !isFeelessAddress[address(_terminal)]) {
          unchecked {
            netPayoutAmount -= JBFees.feeIn(_amount, _feePercent);
          }
        }

        // Trigger any inherited pre-transfer logic.
        _beforeTransferTo(address(_terminal), _token, netPayoutAmount);

        // Add to balance if prefered.
        if (_split.preferAddToBalance)
          try
            _terminal.addToBalanceOf{value: _token == JBTokens.ETH ? netPayoutAmount : 0}(
              _split.projectId,
              _token,
              netPayoutAmount,
              false,
              '',
              // Send the projectId in the metadata as a referral.
              bytes(abi.encodePacked(_projectId))
            )
          {} catch (bytes memory _reason) {
            // Revert the payout.
            _revertTransferFrom(_projectId, _token, address(_terminal), netPayoutAmount, _amount);

            // Set the net payout amount to 0 to signal the reversion.
            netPayoutAmount = 0;

            emit PayoutReverted(_projectId, _split, _amount, _reason, msg.sender);
          }
        else
          try
            _terminal.pay{value: _token == JBTokens.ETH ? netPayoutAmount : 0}(
              _split.projectId,
              _token,
              netPayoutAmount,
              _split.beneficiary != address(0) ? _split.beneficiary : msg.sender,
              0,
              '',
              // Send the projectId in the metadata as a referral.
              bytes(abi.encodePacked(_projectId))
            )
          {} catch (bytes memory _reason) {
            // Revert the payout.
            _revertTransferFrom(_projectId, _token, address(_terminal), netPayoutAmount, _amount);

            // Set the net payout amount to 0 to signal the reversion.
            netPayoutAmount = 0;

            emit PayoutReverted(_projectId, _split, _amount, _reason, msg.sender);
          }
      }
    } else {
      // This distribution is eligible for a fee since the funds are leaving this contract and the beneficiary isn't listed as feeless.
      // Don't enforce feeless address for the beneficiary since the funds are leaving the ecosystem.
      if (_feePercent != 0) {
        unchecked {
          netPayoutAmount -= JBFees.feeIn(_amount, _feePercent);
        }
      }

      // If there's a beneficiary, send the funds directly to the beneficiary. Otherwise send to the msg.sender.
      _transferFrom(
        address(this),
        _split.beneficiary != address(0) ? _split.beneficiary : payable(msg.sender),
        _token,
        netPayoutAmount
      );
    }
  }

  /// @notice Fulfills payment allocations to a list of delegates.
  /// @param _projectId The ID of the project being paid that is forwarding allocations to delegates.
  /// @param _allocations The allocations being fulfilled.
  /// @param _tokenAmount The amount of tokens that were paid in to the project.
  /// @param _payer The address that sent the payment.
  /// @param _fundingCycle The funding cycle during which the payment is being accepted during.
  /// @param _beneficiary The address receiving tokens that result from the payment.
  /// @param _beneficiaryTokenCount The amount of tokens that are being minted for the beneificary.
  /// @param _metadata Bytes to send along to the data source, delegate, and emitted event, if provided.
  function _fulfillPayDelegateAllocationsFor(
    uint256 _projectId,
    JBPayDelegateAllocation3_1_1[] memory _allocations,
    JBTokenAmount memory _tokenAmount,
    address _payer,
    JBFundingCycle memory _fundingCycle,
    address _beneficiary,
    uint256 _beneficiaryTokenCount,
    bytes memory _metadata
  ) internal {
    // The accounting context.
    JBDidPayData3_1_1 memory _data = JBDidPayData3_1_1(
      _payer,
      _projectId,
      _fundingCycle.configuration,
      _tokenAmount,
      _tokenAmount,
      _fundingCycle.weight,
      _beneficiaryTokenCount,
      _beneficiary,
      bytes(''),
      _metadata
    );

    // Keep a reference to the allocation being iterated on.
    JBPayDelegateAllocation3_1_1 memory _allocation;

    // Keep a reference to the number of allocations there are.
    uint256 _numberOfAllocations = _allocations.length;

    // Fulfill each allocation.
    for (uint256 _i; _i < _numberOfAllocations; ) {
      // Set the allocation being iterated on.
      _allocation = _allocations[_i];

      // Pass the correct token forwardedAmount to the delegate
      _data.forwardedAmount.value = _allocation.amount;

      // Pass the correct metadata from the data source.
      _data.dataSourceMetadata = _allocation.metadata;

      // Trigger any inherited pre-transfer logic.
      _beforeTransferTo(address(_allocation.delegate), _tokenAmount.token, _allocation.amount);

      // Keep a reference to the value that will be forwarded.
      uint256 _value = _tokenAmount.token == JBTokens.ETH ? _allocation.amount : 0;

      // Fulfill the allocation.
      _allocation.delegate.didPay{value: _value}(_data);

      emit DelegateDidPay(_allocation.delegate, _data, _allocation.amount, msg.sender);

      unchecked {
        ++_i;
      }
    }
  }

  /// @notice Fulfills redemption allocations to a list of delegates.
  /// @param _projectId The ID of the project being redeemed from that is forwarding allocations to delegates.
  /// @param _beneficiaryTokenAmount The amount of tokens that are being reclaimed from the project.
  /// @param _holder The address that is redeeming.
  /// @param _tokenCount The amount of tokens that are being redeemed by the holder.
  /// @param _metadata Bytes to send along to the data source, delegate, and emitted event, if provided.
  /// @param _fundingCycle The funding cycle during which the redemption is being made during.
  /// @param _beneficiary The address receiving reclaimed treasury tokens that result from the redemption.
  /// @param _allocations The allocations being fulfilled.
  /// @param _feePercent The percent fee that will apply to funds allocated to delegates.
  /// @return feeEligibleDistributionAmount The amount of allocated funds to delegates that are eligible for fees.
  function _fulfillRedemptionDelegateAllocationsFor(
    uint256 _projectId,
    JBTokenAmount memory _beneficiaryTokenAmount,
    address _holder,
    uint256 _tokenCount,
    bytes memory _metadata,
    JBFundingCycle memory _fundingCycle,
    address payable _beneficiary,
    JBRedemptionDelegateAllocation3_1_1[] memory _allocations,
    uint256 _feePercent
  ) internal returns (uint256 feeEligibleDistributionAmount) {
    // Keep a reference to the data that'll get send to delegates.
    JBDidRedeemData3_1_1 memory _data = JBDidRedeemData3_1_1(
      _holder,
      _projectId,
      _fundingCycle.configuration,
      _tokenCount,
      _beneficiaryTokenAmount,
      _beneficiaryTokenAmount,
      _fundingCycle.redemptionRate(),
      _beneficiary,
      bytes(''),
      _metadata
    );

    // Keep a reference to the allocation being iterated on.
    JBRedemptionDelegateAllocation3_1_1 memory _allocation;

    // Keep a reference to the number of allocations there are.
    uint256 _numberOfAllocations = _allocations.length;

    for (uint256 _i; _i < _numberOfAllocations; ) {
      // Set the allocation being iterated on.
      _allocation = _allocations[_i];

      // Get the fee for the delegated amount.
      uint256 _delegatedAmountFee = _feePercent == 0
        ? 0
        : JBFees.feeIn(_allocation.amount, _feePercent);

      // Add the delegated amount to the amount eligible for having a fee taken.
      if (_delegatedAmountFee != 0) {
        feeEligibleDistributionAmount += _allocation.amount;
        _allocation.amount -= _delegatedAmountFee;
      }

      // Set the value of the forwarded amount.
      _data.forwardedAmount.value = _allocation.amount;

      // Pass the correct metadata from the data source.
      _data.dataSourceMetadata = _allocation.metadata;

      // Trigger any inherited pre-transfer logic.
      _beforeTransferTo(
        address(_allocation.delegate),
        _beneficiaryTokenAmount.token,
        _allocation.amount
      );

      // Keep a reference to the value that will be forwarded.
      uint256 _value = _beneficiaryTokenAmount.token == JBTokens.ETH ? _allocation.amount : 0;

      // Fulfill the allocation.
      _allocation.delegate.didRedeem{value: _value}(_data);

      emit DelegateDidRedeem(
        _allocation.delegate,
        _data,
        _allocation.amount,
        _delegatedAmountFee,
        msg.sender
      );
    }
  }

  /// @notice Takes a fee into the platform's project, which has an id of _FEE_BENEFICIARY_PROJECT_ID.
  /// @param _projectId The ID of the project having fees taken from.
  /// @param _token The address of the token that the fee is being taken in.
  /// @param _amount The amount of the fee to take, as a floating point number with 18 decimals.
  /// @param _feePercent The percent of fees to take, out of MAX_FEE.
  /// @param _beneficiary The address to mint the platforms tokens for.
  /// @param _shouldHoldFees If fees should be tracked and held back.
  /// @param _feeTerminal The terminal the fee should be taken into.
  /// @return feeAmount The amount of the fee taken.
  function _takeFeeFrom(
    uint256 _projectId,
    address _token,
    uint256 _amount,
    uint256 _feePercent,
    address _beneficiary,
    bool _shouldHoldFees,
    IJBPaymentTerminal _feeTerminal
  ) internal returns (uint256 feeAmount) {
    // Get a reference to the fee amount.
    feeAmount = JBFees.feeIn(_amount, _feePercent);

    if (_shouldHoldFees) {
      // Store the held fee.
      _heldFeesOf[_projectId].push(JBFee(_amount, uint32(_feePercent), _beneficiary));

      emit HoldFee(_projectId, _amount, _feePercent, _beneficiary, msg.sender);
    } else {
      // Process the fee.
      _processFee(_projectId, _token, feeAmount, _beneficiary, _feeTerminal); // Take the fee.

      emit ProcessFee(_projectId, feeAmount, false, _beneficiary, msg.sender);
    }
  }

  /// @notice Process a fee of the specified amount from a project.
  /// @param _projectId The project ID the fee is being paid from.
  /// @param _token The token the fee is being paid in.
  /// @param _amount The fee amount, as a floating point number with 18 decimals.
  /// @param _beneficiary The address to mint the platform's tokens for.
  /// @param _feeTerminal The terminal the fee should be taken into.
  function _processFee(
    uint256 _projectId,
    address _token,
    uint256 _amount,
    address _beneficiary,
    IJBPaymentTerminal _feeTerminal
  ) internal {
    // If
    if (address(_feeTerminal) == address(0)) {
      _revertTransferFrom(_projectId, _token, address(0), 0, _amount);
      emit FeeReverted(
        _projectId,
        _FEE_BENEFICIARY_PROJECT_ID,
        _amount,
        bytes('FEE NOT ACCEPTED'),
        msg.sender
      );
      return;
    }

    // Trigger any inherited pre-transfer logic if funds will be transferred.
    if (address(_feeTerminal) != address(this))
      _beforeTransferTo(address(_feeTerminal), _token, _amount);

    try
      // Send the fee.
      // If this terminal's token is ETH, send it in msg.value.
      _feeTerminal.pay{value: _token == JBTokens.ETH ? _amount : 0}(
        _FEE_BENEFICIARY_PROJECT_ID,
        _token,
        _amount,
        _beneficiary,
        0,
        '',
        // Send the projectId in the metadata.
        bytes(abi.encodePacked(_projectId))
      )
    {} catch (bytes memory _reason) {
      _revertTransferFrom(
        _projectId,
        _token,
        address(_feeTerminal) != address(this) ? address(_feeTerminal) : address(0),
        address(_feeTerminal) != address(this) ? _amount : 0,
        _amount
      );
      emit FeeReverted(_projectId, _FEE_BENEFICIARY_PROJECT_ID, _amount, _reason, msg.sender);
    }
  }

  /// @notice Refund fees based on the specified amount.
  /// @param _projectId The project for which fees are being refunded.
  /// @param _amount The amount to base the refund on, as a fixed point number with the same amount of decimals as this terminal.
  /// @return refundedFees How much fees were refunded, as a fixed point number with the same number of decimals as this terminal
  function _refundHeldFees(
    uint256 _projectId,
    uint256 _amount
  ) internal returns (uint256 refundedFees) {
    // Get a reference to the project's held fees.
    JBFee[] memory _heldFees = _heldFeesOf[_projectId];

    // Delete the current held fees.
    delete _heldFeesOf[_projectId];

    // Get a reference to the leftover amount once all fees have been settled.
    uint256 leftoverAmount = _amount;

    // Keep a reference to the number of held fees.
    uint256 _numberOfHeldFees = _heldFees.length;

    // Process each fee.
    for (uint256 _i; _i < _numberOfHeldFees; ) {
      if (leftoverAmount == 0) _heldFeesOf[_projectId].push(_heldFees[_i]);
      else {
        // Notice here we take feeIn the stored .amount
        uint256 _feeAmount = (
          _heldFees[_i].fee == 0 ? 0 : JBFees.feeIn(_heldFees[_i].amount, _heldFees[_i].fee)
        );

        if (leftoverAmount >= _heldFees[_i].amount - _feeAmount) {
          unchecked {
            leftoverAmount = leftoverAmount - (_heldFees[_i].amount - _feeAmount);
            refundedFees += _feeAmount;
          }
        } else {
          // And here we overwrite with feeFrom the leftoverAmount
          _feeAmount = (
            _heldFees[_i].fee == 0 ? 0 : JBFees.feeFrom(leftoverAmount, _heldFees[_i].fee)
          );

          unchecked {
            _heldFeesOf[_projectId].push(
              JBFee(
                _heldFees[_i].amount - (leftoverAmount + _feeAmount),
                _heldFees[_i].fee,
                _heldFees[_i].beneficiary
              )
            );
            refundedFees += _feeAmount;
          }
          leftoverAmount = 0;
        }
      }

      unchecked {
        ++_i;
      }
    }

    emit RefundHeldFees(_projectId, _amount, refundedFees, leftoverAmount, msg.sender);
  }

  /// @notice Reverts an expected payout.
  /// @param _projectId The ID of the project having paying out.
  /// @param _token The address of the token having its transfer reverted.
  /// @param _expectedDestination The address the payout was expected to go to.
  /// @param _allowanceAmount The amount that the destination has been allowed to use.
  /// @param _depositAmount The amount of the payout as debited from the project's balance.
  function _revertTransferFrom(
    uint256 _projectId,
    address _token,
    address _expectedDestination,
    uint256 _allowanceAmount,
    uint256 _depositAmount
  ) internal {
    // Cancel allowance if needed.
    if (_allowanceAmount != 0 && _expectedDestination != address(this))
      _cancelTransferTo(_expectedDestination, _token, _allowanceAmount);

    // Add undistributed amount back to project's balance.
    STORE.recordAddedBalanceFor(_projectId, _token, _depositAmount);
  }

  /// @notice Transfers tokens.
  /// @param _from The address from which the transfer should originate.
  /// @param _to The address to which the transfer should go.
  /// @param _token The token being transfered.
  /// @param _amount The amount of the transfer, as a fixed point number with the same number of decimals as this terminal.
  function _transferFrom(
    address _from,
    address payable _to,
    address _token,
    uint256 _amount
  ) internal virtual {
    if (_token == JBTokens.ETH) return Address.sendValue(_to, _amount);
    _from == address(this)
      ? IERC20(_token).safeTransfer(_to, _amount)
      : IERC20(_token).safeTransferFrom(_from, _to, _amount);
  }

  /// @notice Logic to be triggered before transferring tokens from this terminal.
  /// @param _to The address to which the transfer is going.
  /// @param _token The token being transfered.
  /// @param _amount The amount of the transfer, as a fixed point number with the same number of decimals as this terminal.
  function _beforeTransferTo(address _to, address _token, uint256 _amount) internal virtual {
    if (_token == JBTokens.ETH) return;
    IERC20(_token).safeIncreaseAllowance(_to, _amount);
  }

  /// @notice Logic to be triggered if a transfer should be undone
  /// @param _to The address to which the transfer went.
  /// @param _token The token being transfered.
  /// @param _amount The amount of the transfer, as a fixed point number with the same number of decimals as this terminal.
  function _cancelTransferTo(address _to, address _token, uint256 _amount) internal virtual {
    if (_token == JBTokens.ETH) return;
    IERC20(_token).safeDecreaseAllowance(_to, _amount);
  }
}
