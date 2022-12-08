// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import '@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol';
import '@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol';

import '../../interfaces/IJBDirectory.sol';
import './Factories/NFTokenFactory.sol';

/**
 * @notice
 */
/// @custom:oz-upgrades-unsafe-allow external-library-linking
contract Deployer_v001 is OwnableUpgradeable, UUPSUpgradeable {
  event Deployment(string contractType, address contractAddress);

  /// @custom:oz-upgrades-unsafe-allow constructor
  constructor() {
    _disableInitializers();
  }

  function initialize() public virtual initializer {
    __Ownable_init();
    __UUPSUpgradeable_init();
  }

  function _authorizeUpgrade(address) internal override onlyOwner {}

  function deployNFToken(
    address _owner,
    string memory _name,
    string memory _symbol,
    string memory _baseUri,
    string memory _contractUri,
    uint256 _jbxProjectId,
    IJBDirectory _jbxDirectory,
    uint256 _maxSupply,
    uint256 _unitPrice,
    uint256 _mintAllowance,
    uint256 _mintPeriodStart,
    uint256 _mintPeriodEnd
  ) external returns (address) {
    address t = NFTokenFactory.createNFToken(
      _owner,
      _name,
      _symbol,
      _baseUri,
      _contractUri,
      _jbxProjectId,
      _jbxDirectory,
      _maxSupply,
      _unitPrice,
      _mintAllowance,
      _mintPeriodStart,
      _mintPeriodEnd
    );

    emit Deployment('NFToken', t);

    return t;
  }
}
