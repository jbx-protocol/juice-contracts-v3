// SPDX-License-Identifier: MIT
pragma solidity ^0.8.16;

import {Ownable} from '@openzeppelin/contracts/access/Ownable.sol';
import {ERC721Votes, ERC721, EIP712} from '@openzeppelin/contracts/token/ERC721/extensions/draft-ERC721Votes.sol';
import {IERC165} from '@openzeppelin/contracts/utils/introspection/IERC165.sol';
import {JBOperatable} from './abstract/JBOperatable.sol';
import {IJBOperatable} from './interfaces/IJBOperatable.sol';
import {IJBOperatorStore} from './interfaces/IJBOperatorStore.sol';
import {IJBProjects} from './interfaces/IJBProjects.sol';
import {IJBTokenUriResolver} from './interfaces/IJBTokenUriResolver.sol';
import {JBOperations} from './libraries/JBOperations.sol';
import {JBProjectMetadata} from './structs/JBProjectMetadata.sol';

/// @notice Stores project ownership and metadata.
/// @dev Projects are represented as ERC-721's.
contract JBProjects is JBOperatable, ERC721Votes, Ownable, IJBProjects {
  //*********************************************************************//
  // --------------------- public stored properties -------------------- //
  //*********************************************************************//

  /// @notice The number of projects that have been created using this contract.
  /// @dev The count is incremented with each new project created.
  /// @dev The resulting ERC-721 token ID for each project is the newly incremented count value.
  uint256 public override count = 0;

  /// @notice The metadata for each project, which can be used across several domains.
  /// @custom:param _projectId The ID of the project to which the metadata belongs.
  /// @custom:param _domain The domain within which the metadata applies. Applications can use the domain namespace as they wish.
  mapping(uint256 => mapping(uint256 => string)) public override metadataContentOf;

  /// @notice The contract resolving each project ID to its ERC721 URI.
  IJBTokenUriResolver public override tokenUriResolver;

  //*********************************************************************//
  // -------------------------- public views --------------------------- //
  //*********************************************************************//

  /// @notice Returns the URI where the ERC-721 standard JSON of a project is hosted.
  /// @param _projectId The ID of the project to get a URI of.
  /// @return The token URI to use for the provided `_projectId`.
  function tokenURI(uint256 _projectId) public view override returns (string memory) {
    // Keep a reference to the resolver.
    IJBTokenUriResolver _tokenUriResolver = tokenUriResolver;

    // If there's no resolver, there's no URI.
    if (_tokenUriResolver == IJBTokenUriResolver(address(0))) return '';

    // Return the resolved URI.
    return _tokenUriResolver.getUri(_projectId);
  }

  /// @notice Indicates if this contract adheres to the specified interface.
  /// @dev See {IERC165-supportsInterface}.
  /// @param _interfaceId The ID of the interface to check for adherance to.
  /// @return A flag indicating if the provided interface ID is supported.
  function supportsInterface(
    bytes4 _interfaceId
  ) public view virtual override(IERC165, ERC721) returns (bool) {
    return
      _interfaceId == type(IJBProjects).interfaceId ||
      _interfaceId == type(IJBOperatable).interfaceId ||
      super.supportsInterface(_interfaceId);
  }

  //*********************************************************************//
  // -------------------------- constructor ---------------------------- //
  //*********************************************************************//

  /// @param _operatorStore A contract storing operator assignments.
  constructor(
    IJBOperatorStore _operatorStore
  )
    ERC721('Juicebox Projects', 'JUICEBOX')
    EIP712('Juicebox Projects', '1')
    JBOperatable(_operatorStore)
  // solhint-disable-next-line no-empty-blocks
  {

  }

  //*********************************************************************//
  // ---------------------- external transactions ---------------------- //
  //*********************************************************************//

  /// @notice Create a new project for the specified owner, which mints an NFT (ERC-721) into their wallet.
  /// @dev Anyone can create a project on an owner's behalf.
  /// @param _owner The address that will be the owner of the project.
  /// @param _metadata A struct containing metadata content about the project, and domain within which the metadata applies.
  /// @return projectId The token ID of the newly created project.
  function createFor(
    address _owner,
    JBProjectMetadata calldata _metadata
  ) external override returns (uint256 projectId) {
    // Increment the count, which will be used as the ID.
    projectId = ++count;

    // Mint the project.
    _safeMint(_owner, projectId);

    // Set the metadata if one was provided.
    if (bytes(_metadata.content).length > 0)
      metadataContentOf[projectId][_metadata.domain] = _metadata.content;

    emit Create(projectId, _owner, _metadata, msg.sender);
  }

  /// @notice Allows a project owner to set the project's metadata content for a particular domain namespace.
  /// @dev Only a project's owner or operator can set its metadata.
  /// @dev Applications can use the domain namespace as they wish.
  /// @param _projectId The ID of the project who's metadata is being changed.
  /// @param _metadata A struct containing metadata content, and domain within which the metadata applies.
  function setMetadataOf(
    uint256 _projectId,
    JBProjectMetadata calldata _metadata
  )
    external
    override
    requirePermission(ownerOf(_projectId), _projectId, JBOperations.SET_METADATA)
  {
    // Set the project's new metadata content within the specified domain.
    metadataContentOf[_projectId][_metadata.domain] = _metadata.content;

    emit SetMetadata(_projectId, _metadata, msg.sender);
  }

  /// @notice Sets the address of the resolver used to retrieve the tokenURI of projects.
  /// @param _newResolver The address of the new resolver.
  function setTokenUriResolver(IJBTokenUriResolver _newResolver) external override onlyOwner {
    // Store the new resolver.
    tokenUriResolver = _newResolver;

    emit SetTokenUriResolver(_newResolver, msg.sender);
  }
}
