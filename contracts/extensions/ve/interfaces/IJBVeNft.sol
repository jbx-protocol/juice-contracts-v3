// SPDX-License-Identifier: MIT
pragma solidity ^0.8.6;

import '../../../interfaces/IJBTokenStore.sol';
import '../../../interfaces/IJBOperatorStore.sol';

import '../structs/JBAllowPublicExtensionData.sol';
import '../structs/JBLockExtensionData.sol';
import '../structs/JBRedeemData.sol';
import '../structs/JBUnlockData.sol';

import './IJBVeTokenUriResolver.sol';

interface IJBVeNft {
  function projectId() external view returns (uint256);

  function tokenStore() external view returns (IJBTokenStore);

  function count() external view returns (uint256);

  function lockDurationOptions() external view returns (uint256[] memory);

  function contractURI() external view returns (string memory);

  function uriResolver() external view returns (IJBVeTokenUriResolver);

  function getSpecs(
    uint256 _tokenId
  )
    external
    view
    returns (
      uint256 amount,
      uint256 duration,
      uint256 lockedUntil,
      bool useJbToken,
      bool allowPublicExtension
    );

  function lock(
    address _account,
    uint256 _amount,
    uint256 _duration,
    address _beneficiary,
    bool _useJbToken,
    bool _allowPublicExtension
  ) external returns (uint256 tokenId);

  function unlock(JBUnlockData[] calldata _unlockData) external;

  function extendLock(
    JBLockExtensionData[] calldata _lockExtensionData
  ) external returns (uint256[] memory newTokenIds);

  function setAllowPublicExtension(
    JBAllowPublicExtensionData[] calldata _allowPublicExtensionData
  ) external;

  function redeem(JBRedeemData[] calldata _redeemData) external;

  function setUriResolver(IJBVeTokenUriResolver _resolver) external;
}
