// SPDX-License-Identifier: MIT
pragma solidity ^0.8.16;

import '../../contracts/structs/JBSplitAllocationData.sol';
import '../../contracts/interfaces/IJBPayDelegate.sol';
import '../../contracts/interfaces/IJBSplitAllocator.sol';
import '@openzeppelin/contracts/utils/introspection/ERC165.sol';

contract MockMaliciousAllocator is ERC165, IJBSplitAllocator {

  function allocate(JBSplitAllocationData calldata _data) external payable override {
      _data;
      revert();
  }
  

  function supportsInterface(bytes4 _interfaceId)
    public
    view
    override(IERC165, ERC165)
    returns (bool)
  {
    return
      _interfaceId == type(IJBSplitAllocator).interfaceId || super.supportsInterface(_interfaceId);
  }
}