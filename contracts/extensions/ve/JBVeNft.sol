// SPDX-License-Identifier: MIT
pragma solidity ^0.8.6;

import '@openzeppelin/contracts/access/Ownable.sol';
import '@openzeppelin/contracts/security/ReentrancyGuard.sol';

import '../../abstract/JBOperatable.sol';

import './veERC721.sol';
import './interfaces/IJBVeNft.sol';
import './interfaces/IJBVeTokenUriResolver.sol';
import './libraries/JBStakingOperations.sol';

/**
 * @notice Allows any JBToken holders to stake their tokens and receive a Banny based on their stake and lock in period.
 *
 *  @dev
 *  Bannies are transferrable, will be burnt when the stake is claimed before or after the lock-in period ends.
 * The Token URI will be determined by SVG for each banny category.
 * Inherits from:
 * ERC721Votes - for ERC721 and governance support.
 * Ownable - for access control.
 * ReentrancyGuard - for protection against external calls.
 */
contract JBVeNft is IJBVeNft, veERC721, Ownable, ReentrancyGuard, JBOperatable {
  //*********************************************************************//
  // --------------------------- custom errors ------------------------- //
  //*********************************************************************//
  error INVALID_ACCOUNT();
  error NON_EXISTENT_TOKEN();
  error INSUFFICIENT_ALLOWANCE();
  error LOCK_PERIOD_NOT_OVER();
  error TOKEN_MISMATCH();
  error INVALID_PUBLIC_EXTENSION_FLAG_VALUE();
  error INVALID_LOCK_EXTENSION();
  error EXCEEDS_MAX_LOCK_DURATION();
  error INVALID_LOCK_DURATION();
  error INSUFFICIENT_BALANCE();

  event Lock(
    uint256 indexed tokenId,
    address indexed account,
    uint256 amount,
    uint256 duration,
    address beneficiary,
    uint256 lockedUntil,
    address caller
  );

  event Unlock(uint256 indexed tokenId, address beneficiary, uint256 amount, address caller);

  event ExtendLock(
    uint256 indexed oldTokenID,
    uint256 indexed newTokenID,
    uint256 updatedDuration,
    uint256 updatedLockedUntil,
    address caller
  );

  event SetAllowPublicExtension(uint256 indexed tokenId, bool allowPublicExtension, address caller);

  event Redeem(
    uint256 indexed tokenId,
    address holder,
    address beneficiary,
    uint256 tokenCount,
    uint256 claimedAmount,
    string memo,
    address caller
  );

  event SetUriResolver(IJBVeTokenUriResolver indexed resolver, address caller);

  //*********************************************************************//
  // --------------------- private stored properties ------------------- //
  //*********************************************************************//

  /**
   * @notice The options for lock durations.
   */
  uint256[] private _lockDurationOptions;

  //*********************************************************************//
  // --------------------- public stored properties -------------------- //
  //*********************************************************************//

  /**
   * @notice JBProject id.
   */
  uint256 public immutable override projectId;

  /**
   * @notice The JBTokenStore where unclaimed tokens are accounted for.
   */
  IJBTokenStore public immutable override tokenStore;

  /**
   * @notice Token URI Resolver Instance
   */
  IJBVeTokenUriResolver public override uriResolver;

  /**
   * @notice Banny id counter
   */
  uint256 public override count;

  //*********************************************************************//
  // ------------------------- external views -------------------------- //
  //*********************************************************************//

  /**
   * @notice The lock duration options
   *
   * @return An array of lock duration options, in seconds.
   */
  function lockDurationOptions() external view override returns (uint256[] memory) {
    return _lockDurationOptions;
  }

  function lockExpirationForDuration(uint256 _duration) pure returns (uint256 expiration) {
    expiration = ((block.timestamp + _duration) / WEEK) * WEEK;
  }

  /**
   * @notice Provides the metadata for the storefront
   */
  function contractURI() public view override returns (string memory) {
    return uriResolver.contractURI();
  }

  /**
   * @notice Computes the metadata url based on the id.
   *
   * @param _tokenId TokenId of the Banny
   *
   * @return dynamic uri based on the svg logic for that particular banny
   */
  function tokenURI(uint256 _tokenId) public view override returns (string memory) {
    // If there isn't a token resolver, return an empty string.
    if (uriResolver == IJBVeTokenUriResolver(address(0))) return '';

    (uint256 _amount, uint256 _duration, uint256 _lockedUntil, , ) = getSpecs(_tokenId);
    return uriResolver.tokenURI(_tokenId, _amount, _duration, _lockedUntil, _lockDurationOptions);
  }

  /**
   * @dev Requires override. Calls super.
   */
  function supportsInterface(bytes4 _interfaceId) public view virtual override returns (bool) {
    return super.supportsInterface(_interfaceId);
  }

  /**
   * @notice Unpacks the packed specs of each banny based on token id.
   *
   * @param _tokenId Banny Id.
   *
   * @return amount Locked token count.
   * @return duration Locked duration.
   * @return lockedUntil Locked until this timestamp.
   * @return useJbToken If the locked tokens are JBTokens.
   * @return allowPublicExtension If the locked position can be extended by anyone.
   */
  function getSpecs(
    uint256 _tokenId
  )
    public
    view
    override
    returns (
      uint256 amount,
      uint256 duration,
      uint256 lockedUntil,
      bool useJbToken,
      bool allowPublicExtension
    )
  {
    LockedBalance storage _lock = locked[_tokenId];
    if (_lock.end == 0) revert NON_EXISTENT_TOKEN();

    amount = uint256(uint128(_lock.amount));
    lockedUntil = _lock.end;
    useJbToken = _lock.useJbToken;
    allowPublicExtension = _lock.allowPublicExtension;
    duration = _lock.duration;
  }

  //*********************************************************************//
  // ---------------------------- constructor -------------------------- //
  //*********************************************************************//
  /**
   * @param _projectId The ID of the project.
   * @param _name Nft name.
   * @param _symbol Nft symbol.
   * @param _uriResolver Token uri resolver instance.
   * @param _tokenStore The JBTokenStore where unclaimed tokens are accounted for.
   * @param _operatorStore A contract storing operator assignments.
   * @param __lockDurationOptions The lock options, in seconds, for lock durations. NOTE, minumum lock duration is one week, minumum inter-period duration is one week.
   * @param _owner The address that'll own this contract.
   */
  constructor(
    uint256 _projectId,
    string memory _name,
    string memory _symbol,
    IJBVeTokenUriResolver _uriResolver,
    IJBTokenStore _tokenStore,
    IJBOperatorStore _operatorStore,
    uint256[] memory __lockDurationOptions,
    address _owner
  ) veERC721(_name, _symbol) {
    operatorStore = _operatorStore; // JBOperatable

    // operatorStore.hasPermission(projects.ownerOf(_projectId), msg.sender, _projectId, JBStakingOperations.DEPLOY_VE_NFT);

    token = address(_tokenStore.tokenOf(_projectId));
    projectId = _projectId;
    uriResolver = _uriResolver;
    tokenStore = _tokenStore;
    _lockDurationOptions = __lockDurationOptions;

    // Make sure no durationOption is longer than the max time
    uint256 _maxTime = uint256(uint128(MAXTIME));
    for (uint256 _i; _i < _lockDurationOptions.length; ) {
      if (_lockDurationOptions[_i] > _maxTime) {
        revert EXCEEDS_MAX_LOCK_DURATION();
      }
      // TODO: consider validatiing intervals against WEEK
      unchecked {
        ++_i;
      }
    }

    _transferOwnership(_owner);
  }

  //*********************************************************************//
  // --------------------- external transactions ----------------------- //
  //*********************************************************************//

  /**
   * @notice Allows token holder to lock in their tokens in exchange for a banny.
   *
   * @dev Only an account or a designated operator can lock its tokens.
   *
   * @param _account JBToken Holder.
   * @param _amount Lock Amount.
   * @param _duration Lock time in seconds.
   * @param _beneficiary Address to mint the banny.
   * @param _useJbToken A flag indicating if JBtokens are being locked. If false, unclaimed project tokens from the JBTokenStore will be locked.
   * @param _allowPublicExtension A flag indicating if the locked position can be extended by anyone.
   *
   * @return tokenId The tokenId for the new ve position.
   */
  function lock(
    address _account,
    uint256 _amount,
    uint256 _duration,
    address _beneficiary,
    bool _useJbToken,
    bool _allowPublicExtension
  )
    external
    override
    nonReentrant
    requirePermission(_account, projectId, JBStakingOperations.LOCK)
    returns (uint256 tokenId)
  {
    if (_useJbToken) {
      // If a token wasn't set when this contract was deployed but is set now, set it.
      if (token == address(0) && tokenStore.tokenOf(projectId) != IJBToken(address(0))) {
        token = address(tokenStore.tokenOf(projectId));
        // The project's token must not have changed since this token was originally set.
      } else if (address(tokenStore.tokenOf(projectId)) != token) {
        revert TOKEN_MISMATCH();
      }
    }

    // Duration must match.
    if (!_isLockDurationAcceptable(_duration)) revert INVALID_LOCK_DURATION();

    // Increment the number of ve positions that have been minted.
    // Has to start at 1, since 0 is the id for non-token global checkpoints
    unchecked {
      tokenId = ++count;
    }

    // Calculate the time when this lock will end (in seconds).
    uint256 _lockedUntil = block.timestamp + _duration;
    _newLock(
      tokenId,
      LockedBalance(
        int128(int256(_amount)),
        _lockedUntil,
        _duration,
        _useJbToken,
        _allowPublicExtension
      )
    );

    // Mint the position for the beneficiary.
    _safeMint(_beneficiary, tokenId);

    // Enable the voting power if the user is minting for themselves
    // otherwise the `_beneficiary` has to enable it manually afterwards
    if (msg.sender == _beneficiary) {
      _activateVotingPower(tokenId, _beneficiary, true, true);
    }

    if (_useJbToken) {
      // Transfer the token to this contract where they'll be locked.
      // Will revert if not enough allowance.
      IJBToken(token).transferFrom(projectId, msg.sender, address(this), _amount);
    } else {
      // Transfer the token to this contract where they'll be locked.
      // Will revert if this contract isn't an opperator.
      tokenStore.transferFrom(msg.sender, projectId, address(this), _amount);
    }

    // Emit event.
    emit Lock(tokenId, _account, _amount, _duration, _beneficiary, locked[tokenId].end, msg.sender);
  }

  /**
   * @notice Allows banny holders to burn their banny and get back the locked in amount.
   *
   * @dev Only an account or a designated operator can unlock its tokens.
   *
   * @param _unlockData An array of banny tokens to be burnt in exchange of the locked tokens.
   */
  function unlock(JBUnlockData[] calldata _unlockData) external override nonReentrant {
    for (uint256 _i; _i < _unlockData.length; ) {
      // Verify that the sender has permission to unlock this tokenId
      _requirePermission(ownerOf(_unlockData[_i].tokenId), projectId, JBStakingOperations.UNLOCK);

      // Get the specs for the token ID.
      LockedBalance storage _lock = locked[_unlockData[_i].tokenId];
      uint256 _amount = uint128(_lock.amount);

      // The lock must have expired.
      if (block.timestamp <= _lock.end) {
        revert LOCK_PERIOD_NOT_OVER();
      }

      // Burn the token.
      _burn(_unlockData[_i].tokenId);

      if (_lock.useJbToken) {
        // Transfer the amount of locked tokens to beneficiary.
        IJBToken(token).transfer(projectId, _unlockData[_i].beneficiary, _amount);
      } else {
        // Transfer the tokens from this contract.
        tokenStore.transferFrom(_unlockData[_i].beneficiary, projectId, address(this), _amount);
      }

      // Emit event.
      emit Unlock(_unlockData[_i].tokenId, _unlockData[_i].beneficiary, _amount, msg.sender);
      unchecked {
        ++_i;
      }
    }
  }

  /**
   * @notice Allows banny holders to extend their token lock-in durations.
   *
   * @dev If the position being extended isn't set to allow public extension, only an operator account or a designated operator can extend the lock of its tokens.
   *
   * @param _lockExtensionData An array of locks to extend.
   *
   * @return newTokenIds An array of the new token ids (in the same order as _lockExtensionData)
   */
  function extendLock(
    JBLockExtensionData[] calldata _lockExtensionData
  ) external override nonReentrant returns (uint256[] memory newTokenIds) {
    newTokenIds = new uint256[](_lockExtensionData.length);

    for (uint256 _i; _i < _lockExtensionData.length; ) {
      // Get a reference to the extension being iterated.
      JBLockExtensionData calldata _data = _lockExtensionData[_i];

      // Duration must match.
      if (!_isLockDurationAcceptable(_data.updatedDuration)) revert INVALID_LOCK_DURATION();

      // Get the specs for the token ID.
      LockedBalance storage _lock = locked[_data.tokenId];

      // If the operation isn't allowed publicly, check if the msg.sender is either the position owner or is an operator.
      if (!_lock.allowPublicExtension)
        _requirePermission(ownerOf(_data.tokenId), projectId, JBStakingOperations.EXTEND_LOCK);

      // Calculate the new unlock date
      uint256 _newEndDate = (block.timestamp + _data.updatedDuration);
      if (_newEndDate < _lock.end) revert INVALID_LOCK_EXTENSION();

      // TODO: Add back in the changing tokenId, temporarily removed to improve gas usage
      // TODO: Completely removing this would save more gas, do we want to change the TokenIDs on extend?
      _extendLock(_data.tokenId, _data.updatedDuration, _newEndDate);
      newTokenIds[_i] = _data.tokenId;

      emit ExtendLock(_data.tokenId, _data.tokenId, _data.updatedDuration, _newEndDate, msg.sender);
      unchecked {
        ++_i;
      }
    }
  }

  /**
   * @notice Allows banny holders to set whether or not anyone in the public can extend their locked position.
   *
   * @dev Only an owner account or a designated operator can extend the lock of its tokens.
   *
   * @param _allowPublicExtensionData An array of locks to extend.
   */
  function setAllowPublicExtension(
    JBAllowPublicExtensionData[] calldata _allowPublicExtensionData
  ) external override nonReentrant {
    for (uint256 _i; _i < _allowPublicExtensionData.length; ) {
      // Get a reference to the extension being iterated.
      JBAllowPublicExtensionData calldata _data = _allowPublicExtensionData[_i];

      if (!_data.allowPublicExtension) {
        revert INVALID_PUBLIC_EXTENSION_FLAG_VALUE();
      }

      // Check if the msg.sender is either the position owner or is an operator.
      _requirePermission(
        ownerOf(_data.tokenId),
        projectId,
        JBStakingOperations.SET_PUBLIC_EXTENSION_FLAG
      );

      // Update the allowPublicExtension (checkpoint is not needed)
      locked[_data.tokenId].allowPublicExtension = _data.allowPublicExtension;

      emit SetAllowPublicExtension(_data.tokenId, _data.allowPublicExtension, msg.sender);
      unchecked {
        ++_i;
      }
    }
  }

  /**
   * @notice Unlock the position and redeem the locked tokens.
   *
   * @dev Only an account or a designated operator can unlock its tokens.
   *
   * @param _redeemData An array of NFTs to redeem.
   */
  function redeem(JBRedeemData[] calldata _redeemData) external override nonReentrant {
    for (uint256 _i; _i < _redeemData.length; ) {
      // Get a reference to the redeemItem being iterated.
      JBRedeemData calldata _data = _redeemData[_i];
      // Get a reference to the owner of the position.
      address _owner = ownerOf(_data.tokenId);
      // Check if the msg.sender is either the position owner or is an operator.
      _requirePermission(_owner, projectId, JBStakingOperations.REDEEM);

      // Get the amount of tokens locked
      uint256 _lockAmount = uint256(uint128(locked[_data.tokenId].amount));

      // Burn the token.
      _burn(_data.tokenId);

      // Redeem the locked tokens to reclaim treasury funds.
      uint256 _reclaimedAmount = _data.terminal.redeemTokensOf(
        address(this),
        projectId,
        _lockAmount,
        _data.token,
        _data.minReturnedTokens,
        _data.beneficiary,
        _data.memo,
        _data.metadata
      );

      // Emit event.
      emit Redeem(
        _data.tokenId,
        _owner,
        _data.beneficiary,
        _lockAmount,
        _reclaimedAmount,
        _data.memo,
        msg.sender
      );
      unchecked {
        ++_i;
      }
    }
  }

  /**
   * @notice Allows the owner to set the uri resolver.
   *
   * @param _resolver The new URI resolver.
   */
  function setUriResolver(IJBVeTokenUriResolver _resolver) external override onlyOwner {
    uriResolver = _resolver;
    emit SetUriResolver(_resolver, msg.sender);
  }

  //*********************************************************************//
  // --------------------- private helper functions -------------------- //
  //*********************************************************************//

  /**
   * @notice Returns a flag indicating if the provided duration is one of the lock duration options.
   *
   * @param _duration The duration to evaluate.
   *
   * @return A flag.
   */
  function _isLockDurationAcceptable(uint256 _duration) private view returns (bool) {
    for (uint256 _i; _i < _lockDurationOptions.length; ) {
      if (_lockDurationOptions[_i] == _duration) return true;
      unchecked {
        ++_i;
      }
    }
    return false;
  }
}
