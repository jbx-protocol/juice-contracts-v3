// SPDX-License-Identifier: MIT
pragma solidity ^0.8.6;

import '../../abstract/JBOperatable.sol';

import './interfaces/IJBVeNftDeployer.sol';

import './JBVeNft.sol';
import './VeTokenUriResolver.sol';

/**
 * @notice Allows a project owner to deploy a veNFT contract.
 *
 * @dev This contract is loosely based on JBVeNftDeployer from https://github.com/jbx-protocol/juice-ve-nft/tree/master/contracts
 */
contract VeNftDeployer is IJBVeNftDeployer, JBOperatable {
  /**
   * @notice Juicebox project registry.
   */
  IJBProjects public immutable override projects;

  //*********************************************************************//
  // ---------------------------- constructor -------------------------- //
  //*********************************************************************//

  /**
   * @param _projects A contract which mints ERC-721's that represent project ownership and transfers.
   * @param _operatorStore A contract storing operator assignments.
   */
  constructor(IJBProjects _projects, IJBOperatorStore _operatorStore) {
    operatorStore = _operatorStore; // JBOperatable

    projects = _projects;
  }

  //*********************************************************************//
  // ---------------------- external transactions ---------------------- //
  //*********************************************************************//

  /**
   * @notice Deploys a new URI resolver instance for use with a VE NFT contract.
   */
  function deployUriResolver(
    address _owner,
    string memory _baseUri,
    string memory _contractUri
  ) external returns (IJBVeTokenUriResolver resolver) {
    resolver = new VeTokenUriResolver(_owner, _baseUri, _contractUri);

    emit DeployVeUriResolver(address(resolver), _owner, _baseUri, _contractUri, msg.sender);
  }

  /**
   * @notice Deploys a new VE NFT instance.
   *
   * @param _projectId The ID of the project.
   * @param _name Nft name.
   * @param _symbol Nft symbol.
   * @param _uriResolver Token uri resolver instance.
   * @param _tokenStore The JBTokenStore where unclaimed tokens are accounted for.
   * @param _lockDurationOptions The lock options, in seconds, for lock durations.
   * @param _owner The address that will own the staking contract.
   *
   * @return veNft The ve NFT contract that was deployed.
   */
  function deployNFT(
    uint256 _projectId,
    string memory _name,
    string memory _symbol,
    IJBVeTokenUriResolver _uriResolver,
    IJBTokenStore _tokenStore,
    IJBOperatorStore _operatorStore,
    uint256[] memory _lockDurationOptions,
    address _owner
  )
    external
    override
    requirePermission(projects.ownerOf(_projectId), _projectId, JBStakingOperations.DEPLOY_VE_NFT)
    returns (IJBVeNft veNft)
  {
    veNft = new JBVeNft(
      _projectId,
      _name,
      _symbol,
      _uriResolver,
      _tokenStore,
      _operatorStore,
      _lockDurationOptions,
      _owner
    );

    emit DeployVeNft(
      address(veNft),
      _projectId,
      _name,
      _symbol,
      _uriResolver,
      _tokenStore,
      _operatorStore,
      _lockDurationOptions,
      _owner,
      msg.sender
    );
  }
}
