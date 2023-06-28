// SPDX-License-Identifier: MIT
pragma solidity ^0.8.16;

import {IJBController} from './interfaces/IJBController.sol';
import {IJBDirectory} from './interfaces/IJBDirectory.sol';
import {IJBMigratable} from './interfaces/IJBMigratable.sol';
import {IJBPayoutRedemptionPaymentTerminal} from './interfaces/IJBPayoutRedemptionPaymentTerminal.sol';
import {IJBPaymentTerminal} from './interfaces/IJBPaymentTerminal.sol';
import {IJBProjects} from './interfaces/IJBProjects.sol';

/// @notice Allows projects to migrate their controller & terminal to 3.1 version
contract JBMigrationOperator {
  //*********************************************************************//
  // --------------------------- custom errors ------------------------- //
  //*********************************************************************//
  error UNAUTHORIZED();

  //*********************************************************************//
  // --------------- public immutable stored properties ---------------- //
  //*********************************************************************//

  /// @notice directory instance which keeps a track of which controller is linked to which project.
  IJBDirectory public immutable directory;

  /// @notice The NFT granting ownership to a Juicebox project
  IJBProjects public immutable projects;

  //*********************************************************************//
  // ---------------------------- constructor -------------------------- //
  //*********************************************************************//

  /// @param _directory A contract storing directories of terminals and controllers for each project.
  constructor(IJBDirectory _directory) {
    directory = _directory;
    projects = IJBProjects(_directory.projects());
  }

  //*********************************************************************//
  // --------------------- external transactions ----------------------- //
  //*********************************************************************//

  /// @notice Allows project owners to migrate the controller & terminal linked to their project to the latest version.
  /// @param _projectId The project id whose controller & terminal are to be migrated
  /// @param _newController Controller 3.1 address to migrate to.
  /// @param _newJbTerminal Terminal 3.1 address to migrate to.
  /// @param _oldJbTerminal Old terminal address to migrate from.
  function migrate(
    uint256 _projectId,
    IJBMigratable _newController,
    IJBPaymentTerminal _newJbTerminal,
    IJBPayoutRedemptionPaymentTerminal _oldJbTerminal
  ) external {
    // Only allow the project owner to migrate
    if (projects.ownerOf(_projectId) != msg.sender) revert UNAUTHORIZED();

    // controller migration
    address _oldController = directory.controllerOf(_projectId);

    // assuming the project owner has reconfigured the funding cycle with allowControllerMigration
    IJBController(_oldController).migrate(_projectId, _newController);

    // terminal migration
    IJBPaymentTerminal[] memory _newTerminals = new IJBPaymentTerminal[](1);
    _newTerminals[0] = IJBPaymentTerminal(address(_newJbTerminal));

    // assuming the project owner has reconfigured the funding cycle with allowTerminalMigration & global.allowSetTerminals
    directory.setTerminalsOf(_projectId, _newTerminals);
    _oldJbTerminal.migrate(_projectId, _newJbTerminal);
  }
}
