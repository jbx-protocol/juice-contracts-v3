// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import '../../NFT/NFToken.sol';
import '../../../interfaces/IJBDirectory.sol';

/**
 * @notice Creates an instance of NFToken contract
 */
library NFTokenFactory {
  /**
   * @notice In addition to taking the parameters requires by the NFToken contract, the `_owner` argument will be used to assign ownership after contract deployment.
   */
  function createNFToken(
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
    NFToken t = new NFToken(
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

    abdicate(t, _owner);

    return address(t);
  }

  function abdicate(NFToken _t, address _owner) private {
    _t.grantRole(0x00, _owner); // AccessControl.DEFAULT_ADMIN_ROLE
    _t.grantRole(keccak256('MINTER_ROLE'), _owner);
    _t.grantRole(keccak256('REVEALER_ROLE'), _owner);
    _t.revokeRole(keccak256('REVEALER_ROLE'), address(this));
    _t.revokeRole(keccak256('MINTER_ROLE'), address(this));
    _t.revokeRole(0x00, address(this));
  }
}
