// SPDX-License-Identifier: MIT
pragma solidity ^0.8.6;

import 'forge-std/Script.sol';
import '../JBMigrationOperator.sol';


contract DeployJBMigrationOperator_On_Mainnet is Script {

    IJBDirectory jbDirectory = IJBDirectory(0x65572FB928b46f9aDB7cfe5A4c41226F636161ea);
    JBMigrationOperator migrationOperator;

    function run() external {
      vm.startBroadcast();

      migrationOperator = new JBMigrationOperator(jbDirectory);
      console.log(address(migrationOperator));
    }
}

// only keeping this since the v3 contracts are not on sepolia yet
contract DeployJBMigrationOperator_On_Goerli is Script {

    IJBDirectory jbDirectory = IJBDirectory(0x8E05bcD2812E1449f0EC3aE24E2C395F533d9A99);
    JBMigrationOperator migrationOperator;

    function run() external {
      vm.startBroadcast();

      migrationOperator = new JBMigrationOperator(jbDirectory);
      console.log(address(migrationOperator));
    }
}