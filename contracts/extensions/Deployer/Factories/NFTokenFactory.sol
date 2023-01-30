// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import '../../NFT/NFToken.sol';

/**
 * @notice Creates an instance of NFToken contract
 */
library NFTokenFactory {
  /**
   * @notice In addition to taking the parameters requires by the NFToken contract, the `_owner` argument will be used to assign ownership after contract deployment.
   */
  function createNFToken(
    address payable _owner,
    string memory _name,
    string memory _symbol,
    string memory _baseUri,
    string memory _contractUri,
    uint256 _maxSupply,
    uint256 _unitPrice,
    uint256 _mintAllowance,
    bool _reveal
  ) external returns (address) {
    NFToken t = new NFToken(
      _name,
      _symbol,
      _baseUri,
      _contractUri,
      _maxSupply,
      _unitPrice,
      _mintAllowance,
      0,
      0
    );

    if (_reveal) {
      t.setBaseURI(_baseUri, true);
    }

    abdicate(t, _owner);

    return address(t);
  }

  function abdicate(NFToken _t, address payable _owner) private {
    _t.setPayoutReceiver(_owner);
    _t.setRoyalties(_owner, 0);

    _t.grantRole(0x00, _owner); // AccessControl.DEFAULT_ADMIN_ROLE
    _t.grantRole(keccak256('MINTER_ROLE'), _owner);
    _t.grantRole(keccak256('REVEALER_ROLE'), _owner);

    _t.revokeRole(keccak256('REVEALER_ROLE'), address(this));
    _t.revokeRole(keccak256('MINTER_ROLE'), address(this));
    _t.revokeRole(0x00, address(this));
  }
}
