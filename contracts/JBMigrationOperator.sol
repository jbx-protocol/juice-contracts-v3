// SPDX-License-Identifier: MIT
pragma solidity ^0.8.16;

import './interfaces/IJBController.sol';
import './interfaces/IJBDirectory.sol';
import './interfaces/IJBMigratable.sol';
import './interfaces/IJBPayoutRedemptionPaymentTerminal.sol';
import './interfaces/IJBPaymentTerminal.sol';


/** 
  @notice 
  Allows projects to migrate their controller & terminal to 3.1 version
*/
contract JBMigrationOperator {

  //*********************************************************************//
  // --------------- public immutable stored properties ---------------- //
  //*********************************************************************//

  /**
    @notice
    jbDirectory instance which keeps a track of which controller is linked to which project.
  */
  IJBDirectory immutable public jbDirectory;


  //*********************************************************************//
  // ---------------------------- constructor -------------------------- //
  //*********************************************************************//

  /**
    @param _jbDirectory A contract storing directories of terminals and controllers for each project.
  */
  constructor(IJBDirectory _jbDirectory) {
      jbDirectory = _jbDirectory;
  }

  
  //*********************************************************************//
  // --------------------- external transactions ----------------------- //
  //*********************************************************************//

  /**
    @notice
    Creates a project. This will mint an ERC-721 into the specified owner's account, configure a first funding cycle, and set up any splits.

    @param _projectId The project id whose controller & terminal are to be migrated
    @param _newController Controller 3.1 address to migrate to.
    @param _newJbTerminal Terminal 3.1 address to migrate to.
    @param _oldJbTerminal Old terminal address to migrate from.
  */
  function migrate(uint256 _projectId, address _newController, IJBPaymentTerminal _newJbTerminal, IJBPayoutRedemptionPaymentTerminal _oldJbTerminal) external {
      // controller migration
      address _oldController = jbDirectory.controllerOf(_projectId);

      // assuming the project owner has reconfigured the funding cycle with allowControllerMigration
      IJBController(_oldController).migrate(_projectId, IJBMigratable(_newController));

      // terminal migration
      IJBPaymentTerminal[] memory _newTerminals = new IJBPaymentTerminal[](1);
      _newTerminals[0] = IJBPaymentTerminal(address(_newJbTerminal));

      // assuming the project owner has reconfigured the funding cycle with allowTerminalMigration & global.allowSetTerminals
      jbDirectory.setTerminalsOf(_projectId, _newTerminals);
      _oldJbTerminal.migrate(_projectId, _newJbTerminal);
  }
}
