// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;

import '../abstract/JBOperatable.sol';
import '../libraries/JBOperations.sol';
import '../interfaces/IJBDirectory.sol';
import '../interfaces/IJBProjects.sol';
import '../interfaces/IJBOperatorStore.sol';

enum TokenType {
  ERC20,
  ERC721,
  ERC1155
}

struct DiscountDefinition {
  address token;
  TokenType tokenType;
  uint32 tokenIndex;
  uint32 tokenBalance; // divided by 10^18
  uint16 discount; // uses on 14b
}

interface BasicBalance {
  function balanceOf(address) external view returns (uint256);
}

interface IndexedBalance {
  function balanceOf(address, uint256) external view returns (uint256);
}

/**
 * @notice Allows registration of platform fee discounts for holders of tokens.
 */
contract PlatformDiscountManager is JBOperatable {
  error INVALID_DISCOUNT();

  event AddDiscount(
    address token,
    TokenType tokenType,
    uint256 tokenIndex,
    uint256 tokenBalance,
    uint256 discount
  );
  event RemoveDiscount(
    address token,
    TokenType tokenType,
    uint256 tokenIndex,
    uint256 tokenBalance
  );

  IJBDirectory public immutable jbxDirectory;
  IJBProjects public immutable jbxProjects;

  uint256[] public discounts;

  /**
   * @param _jbxDirectory Juicebox directory.
   * @param _jbxOperatorStore Juicebox operator store.
   * @param _jbxProjects Juicebox project registry.
   */
  constructor(
    IJBDirectory _jbxDirectory,
    IJBProjects _jbxProjects,
    IJBOperatorStore _jbxOperatorStore
  ) {
    operatorStore = _jbxOperatorStore;
    jbxDirectory = _jbxDirectory;
    jbxProjects = _jbxProjects;
  }

  /**
   * @notice Adds a discount. Note that long discount lists degrade contract performance.
   *
   * @dev The user calling this function must have the MIGRATE_CONTROLLER permission on project 1.
   *
   * @param _token Token address ownership of which qualifies a user to the given discount.
   * @param _tokenType Token type: ERC20, ERC721, etc. Defined in `TokenType` enum.
   * @param _tokenIndex Token index, used for ERC1155 token type.
   * @param _tokenBalance Minimum token balance to quilify for the discount. This value is stored as uint32, it is expected to be divided by 10^17.
   * @param _discount Discount percentage in bps, 500 = 5%.
   */
  function registerDiscount(
    address _token,
    TokenType _tokenType,
    uint256 _tokenIndex,
    uint256 _tokenBalance,
    uint256 _discount
  )
    external
    requirePermissionAllowingOverride(
      jbxProjects.ownerOf(1),
      1,
      JBOperations.MIGRATE_CONTROLLER,
      (msg.sender == address(jbxDirectory.controllerOf(1)))
    )
  {
    if (_discount > 10_000) {
      revert INVALID_DISCOUNT();
    }

    discounts.push(packDiscount(_token, _tokenType, _tokenIndex, _tokenBalance, _discount));

    emit AddDiscount(_token, _tokenType, _tokenIndex, _tokenBalance, _discount);
  }

  /**
   * @notice Removes a discount.
   *
   * @dev The user calling this function must have the MIGRATE_CONTROLLER permission on project 1.
   *
   * @param _token Token address ownership of which qualifies a user to the given discount.
   * @param _tokenType Token type: ERC20, ERC721, etc. Defined in `TokenType` enum.
   * @param _tokenIndex Token index, used for ERC1155 token type.
   * @param _tokenBalance Minimum token balance to quilify for the discount. This value is stored as uint32, it is expected to be divided by 10^17.
   */
  function removeDiscount(
    address _token,
    TokenType _tokenType,
    uint256 _tokenIndex,
    uint256 _tokenBalance
  )
    external
    requirePermissionAllowingOverride(
      jbxProjects.ownerOf(1),
      1,
      JBOperations.MIGRATE_CONTROLLER,
      (msg.sender == address(jbxDirectory.controllerOf(1)))
    )
  {
    uint256 l = discounts.length;
    if (l == 0) {
      revert INVALID_DISCOUNT();
    }
    uint256 discount = packDiscount(_token, _tokenType, _tokenIndex, _tokenBalance, 0);
    uint256[] memory updatedDiscounts = new uint256[](l - 1);
    uint256[] memory currentDiscounts = discounts;
    bool found;
    for (uint256 i; i != l; ) {
      if (found) {
        updatedDiscounts[i - 1] = currentDiscounts[i];
        unchecked {
          ++i;
        }
        continue;
      }

      uint256 discountKey = currentDiscounts[i] &
        0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF; // 232 1s to 0-out the discount rate
      if (discountKey != discount) {
        if (i == l - 1) {
          // NOTE: reached the end of the list already
          revert INVALID_DISCOUNT();
        }
        updatedDiscounts[i] = currentDiscounts[i];
      } else if (discountKey == discount) {
        found = true;
      }
      unchecked {
        ++i;
      }
    }

    discounts = updatedDiscounts;

    emit RemoveDiscount(_token, _tokenType, _tokenIndex, _tokenBalance);
  }

  function getPrice(address _actor, uint256 _fee) external view returns (uint256 price) {
    uint256[] memory currentDiscounts = discounts;
    uint256 l = currentDiscounts.length;
    uint256 discount;
    for (uint256 i; i != l; ) {
      DiscountDefinition memory dd = unpackDiscount(currentDiscounts[i]);
      uint256 actorBalance;
      if (dd.tokenType == TokenType.ERC20) {
        actorBalance = ((BasicBalance)(dd.token)).balanceOf(_actor) / 10e17;
      } else if (dd.tokenType == TokenType.ERC721) {
        actorBalance = ((BasicBalance)(dd.token)).balanceOf(_actor);
      } else if (dd.tokenType == TokenType.ERC1155) {
        actorBalance = ((IndexedBalance)(dd.token)).balanceOf(_actor, dd.tokenIndex);
      }

      if (actorBalance >= dd.tokenBalance) {
        if (dd.discount > discount) {
          discount = dd.discount;
        }
      }

      unchecked {
        ++i;
      }
    }

    if (discount == 0) {
      return _fee;
    }

    price = (_fee * (10_000 - discount)) / 10_000;
  }

  function getDiscountInfo(
    uint256 _index
  )
    external
    view
    returns (
      address token,
      TokenType tokenType,
      uint256 tokenIndex,
      uint256 tokenBalance,
      uint256 discount
    )
  {
    DiscountDefinition memory definition = unpackDiscount(discounts[_index]);
    token = definition.token;
    tokenType = definition.tokenType;
    tokenIndex = definition.tokenIndex;
    tokenBalance = definition.tokenBalance;
    discount = definition.discount;
  }

  function packDiscount(
    address _token,
    TokenType _tokenType,
    uint256 _tokenIndex,
    uint256 _tokenBalance,
    uint256 _discount
  ) internal pure returns (uint256 discount) {
    discount = uint256(uint160(_token));
    discount |= uint256(uint8(_tokenType)) << 160;
    discount |= uint256(uint32(_tokenIndex)) << 168;
    discount |= uint256(uint32(_tokenBalance)) << 200;
    discount |= uint256(uint16(_discount)) << 232;
  }

  function unpackDiscount(
    uint256 _discount
  ) internal pure returns (DiscountDefinition memory definition) {
    definition.token = address(uint160(_discount));
    definition.tokenType = TokenType(uint8(_discount >> 160));
    definition.tokenIndex = uint32(_discount >> 168);
    definition.tokenBalance = uint32(_discount >> 200);
    definition.discount = uint16(_discount >> 232);
  }
}
