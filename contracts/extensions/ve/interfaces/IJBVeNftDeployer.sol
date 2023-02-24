// SPDX-License-Identifier: MIT
pragma solidity ^0.8.6;

import '../../../interfaces/IJBProjects.sol';
import '../../../interfaces/IJBTokenStore.sol';
import '../../../interfaces/IJBOperatorStore.sol';

import './IJBVeTokenUriResolver.sol';
import './IJBVeNft.sol';

interface IJBVeNftDeployer {
  event DeployVeNft(
    address jbVeNft,
    uint256 indexed projectId,
    string name,
    string symbol,
    IJBVeTokenUriResolver uriResolver,
    IJBTokenStore tokenStore,
    IJBOperatorStore operatorStore,
    uint256[] lockDurationOptions,
    address owner,
    address caller
  );

  event DeployVeUriResolver(
    address resolver,
    address owner,
    string baseUri,
    string contractUri,
    address caller
  );

  function projects() external view returns (IJBProjects);

  function deployNFT(
    uint256 _projectId,
    string memory _name,
    string memory _symbol,
    IJBVeTokenUriResolver _uriResolver,
    IJBTokenStore _tokenStore,
    IJBOperatorStore _operatorStore,
    uint256[] memory _lockDurationOptions,
    address _owner
  ) external returns (IJBVeNft veNft);

  function deployUriResolver(
    address _owner,
    string memory _baseUri,
    string memory _contractUri
  ) external returns (IJBVeTokenUriResolver);
}
