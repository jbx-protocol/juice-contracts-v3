// SPDX-License-Identifier: MIT
pragma solidity ^0.8.16;

import {IJBOperatorStore} from './interfaces/IJBOperatorStore.sol';
import {JBOperatorData} from './structs/JBOperatorData.sol';

import {ECDSA} from '@openzeppelin/contracts/utils/cryptography/ECDSA.sol';
import {EIP712} from '@openzeppelin/contracts/utils/cryptography/draft-EIP712.sol';

/// @notice Stores operator permissions for all addresses. Addresses can give permissions to any other address to take specific indexed actions on their behalf.
contract JBOperatorStore3_2 is EIP712, IJBOperatorStore {
  //*********************************************************************//
  // --------------------------- custom errors ------------------------- //
  //*********************************************************************//
  error PERMISSION_INDEX_OUT_OF_BOUNDS();
  error ERC2612ExpiredSignature(uint256 deadline);
  error ERC2612InvalidSigner(address signer, address owner);

  //*********************************************************************//
  // --------------------- public stored properties -------------------- //
  //*********************************************************************//

  /// @notice The permissions that an operator has been given to operate on a specific domain.
  /// @dev An account can give an operator permissions that only pertain to a specific domain namespace.
  /// @dev There is no domain with a value of 0 – accounts can use the 0 domain to give an operator permissions to all domains on their behalf.
  /// @dev Permissions are stored in a packed `uint256`. Each 256 bits represents the on/off state of a permission. Applications can specify the significance of each index.
  /// @custom:param _operator The address of the operator.
  /// @custom:param _account The address of the account being operated.
  /// @custom:param _domain The domain within which the permissions apply. Applications can use the domain namespace as they wish.
  mapping(address => mapping(address => mapping(uint256 => uint256))) public override permissionsOf;

  mapping(address => uint256) public nonces;

  constructor() EIP712('JBOperatorStore', '1') {}

  //*********************************************************************//
  // ------------------------- external views -------------------------- //
  //*********************************************************************//

  /// @notice Whether or not an operator has the permission to take a certain action pertaining to the specified domain.
  /// @param _operator The operator to check.
  /// @param _account The account that has given out permissions to the operator.
  /// @param _domain The domain that the operator has been given permissions to operate.
  /// @param _permissionIndex The permission index to check for.
  /// @return A flag indicating whether the operator has the specified permission.
  function hasPermission(
    address _operator,
    address _account,
    uint256 _domain,
    uint256 _permissionIndex
  ) external view override returns (bool) {
    if (_permissionIndex > 255) revert PERMISSION_INDEX_OUT_OF_BOUNDS();

    return (((permissionsOf[_operator][_account][_domain] >> _permissionIndex) & 1) == 1);
  }

  /// @notice Whether or not an operator has the permission to take certain actions pertaining to the specified domain.
  /// @param _operator The operator to check.
  /// @param _account The account that has given out permissions to the operator.
  /// @param _domain The domain that the operator has been given permissions to operate.
  /// @param _permissionIndexes An array of permission indexes to check for.
  /// @return A flag indicating whether the operator has all specified permissions.
  function hasPermissions(
    address _operator,
    address _account,
    uint256 _domain,
    uint256[] calldata _permissionIndexes
  ) external view override returns (bool) {
    for (uint256 _i; _i < _permissionIndexes.length; ) {
      uint256 _permissionIndex = _permissionIndexes[_i];

      if (_permissionIndex > 255) revert PERMISSION_INDEX_OUT_OF_BOUNDS();

      if (((permissionsOf[_operator][_account][_domain] >> _permissionIndex) & 1) == 0)
        return false;

      unchecked {
        ++_i;
      }
    }
    return true;
  }

  /**
   * @dev See {IERC20Permit-DOMAIN_SEPARATOR}.
   */
  // solhint-disable-next-line func-name-mixedcase
  function DOMAIN_SEPARATOR() external view virtual returns (bytes32) {
    return _domainSeparatorV4();
  }

  //*********************************************************************//
  // ---------------------- external transactions ---------------------- //
  //*********************************************************************//

  /// @notice Sets permissions for an operators.
  /// @dev Only an address can set its own operators.
  /// @param _operatorData The data that specifies the params for the operator being set.
  function setOperator(JBOperatorData calldata _operatorData) external override {
    _setOperator(msg.sender, _operatorData);
  }

  /// @notice Sets permissions for many operators.
  /// @dev Only an address can set its own operators.
  /// @param _operatorData The data that specify the params for each operator being set.
  function setOperators(JBOperatorData[] calldata _operatorData) external override {
    for (uint256 _i; _i < _operatorData.length; ) {
      _setOperator(msg.sender, _operatorData[_i]);
      unchecked {
        ++_i;
      }
    }
  }

  function setOperatorPermit(
    address _user,
    JBOperatorData calldata _operatorData,
    uint256 _deadline,
    uint8 _v,
    bytes32 _r,
    bytes32 _s
  ) external {
    // Increment the users nonce
    uint256 _nonce;
    unchecked {
      _nonce = nonces[_user]++;
    }

    bytes32 _structHash = _hashTypedDataV4(
      keccak256(
        abi.encode(
          keccak256(
            'JuiceboxPermissions(Permission _permission, uint256 nonce)Permission(address operator, uint256 domain, uint256[] permissionIndexes)'
          ),
          abi.encodePacked(
            _operatorData.operator,
            _operatorData.domain,
            keccak256(abi.encodePacked(_operatorData.permissionIndexes))
          ),
          _nonce
        )
      )
    );

    // Verify the validity of the signature
    _permit(_user, _structHash, _deadline, _v, _r, _s);
    // Set the operator data
    _setOperator(_user, _operatorData);
  }

  function setOperatorsPermit(
    address _user,
    JBOperatorData[] calldata _operatorData,
    uint256 _deadline,
    uint8 _v,
    bytes32 _r,
    bytes32 _s
  ) external {
    // Increment the users nonce
    uint256 _nonce;
    unchecked {
      _nonce = nonces[_user]++;
    }
    // Verify the validity of the signature
    _permit(_user, keccak256(abi.encode(_operatorData, _nonce)), _deadline, _v, _r, _s);
    // Set the operators data
    for (uint256 _i; _i < _operatorData.length; ) {
      _setOperator(_user, _operatorData[_i]);
      unchecked {
        ++_i;
      }
    }
  }

  //*********************************************************************//
  // ---------------------- internal transactions ---------------------- //
  //*********************************************************************//
  function _setOperator(address _account, JBOperatorData calldata _operatorData) internal {
    // Pack the indexes into a uint256.
    uint256 _packed = _packedPermissions(_operatorData.permissionIndexes);

    // Store the new value.
    permissionsOf[_operatorData.operator][_account][_operatorData.domain] = _packed;

    // TODO: Add who send the message
    emit SetOperator(
      _operatorData.operator,
      _account,
      _operatorData.domain,
      _operatorData.permissionIndexes,
      _packed
    );
  }

  function _permit(
    address _user,
    bytes32 _hash,
    uint256 _deadline,
    uint8 _v,
    bytes32 _r,
    bytes32 _s
  ) internal {
    // Make sure it has not expired
    // if (block.timestamp > _deadline) {
    //   revert ERC2612ExpiredSignature(_deadline);
    // }

    // bytes32 _hash = _hashTypedDataV4(_structHash);
    // This library errors if `_signer` is `address(0)`
    address _signer = ECDSA.recover(_hash, _v, _r, _s);

    // Make sure that its not possible to act as address(0)
    if (_signer != _user || _signer == address(0)) revert ERC2612InvalidSigner(_signer, _user);
  }

  //*********************************************************************//
  // --------------------- private helper functions -------------------- //
  //*********************************************************************//

  /// @notice Converts an array of permission indexes to a packed `uint256`.
  /// @param _indexes The indexes of the permissions to pack.
  /// @return packed The packed value.
  function _packedPermissions(uint256[] calldata _indexes) private pure returns (uint256 packed) {
    for (uint256 _i; _i < _indexes.length; ) {
      uint256 _index = _indexes[_i];

      if (_index > 255) revert PERMISSION_INDEX_OUT_OF_BOUNDS();

      // Turn the bit at the index on.
      packed |= 1 << _index;

      unchecked {
        ++_i;
      }
    }
  }
}
