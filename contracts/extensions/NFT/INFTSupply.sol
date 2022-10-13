// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface INFTSupply {
  function totalSupply() external view returns (uint256);

  function balanceOf(address owner) external view returns (uint256);

  function ownerOf(uint256 _tokenId) external view returns (address owner);
}
