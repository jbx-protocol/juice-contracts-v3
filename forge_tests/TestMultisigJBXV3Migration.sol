// SPDX-License-Identifier: MIT
pragma solidity ^0.8.6;

import "@juicebox/interfaces/IJBOperatorStore.sol";
import "@juicebox/interfaces/IJBTokenStore.sol";

import "lib/juice-v3-migration/contracts/JBV3Token.sol";
import "lib/juice-contracts-v1/contracts/interfaces/ITickets.sol";
import "lib/juice-contracts-v1/contracts/interfaces/IOperatorStore.sol";

import "forge-std/Test.sol";

/**
 *  @title  JBX migration to V3 test - mainnet fork
 */
contract TestMultisigJBXV3Migration_Fork is Test {
    address multisig;

    // Contracts needed
    ITickets tickets = ITickets(0x3abF2A4f8452cCC2CF7b4C1e4663147600646f66);
    IOperatorStore operatorStore = IOperatorStore(0xab47304D987390E27Ce3BC0fA4Fe31E3A98B0db2);

    IJBOperatorStore jbOperatorStore = IJBOperatorStore(0x6F3C5afCa0c9eDf3926eF2dDF17c8ae6391afEfb);
    IJBTokenStore jbTokenStore = IJBTokenStore(0xCBB8e16d998161AdB20465830107ca298995f371 );

    JBV3Token jbV3Token = JBV3Token(0x4554CC10898f92D45378b98D6D6c2dD54c687Fb2);

    function setUp() public {
        vm.createSelectFork("https://rpc.ankr.com/eth", 16_677_461);

        // multisig address
    }

    /**
     * @notice  Test if a project can migrate its controller and terminals using the migrator
     *          Check: V1 $JBX, V1 ticket and V2 $JBX balances are now in V3.
     */
    function testMigration_migrateV1AndV2ToV3() public {
        /**
            JBP-371:
            Call v1 OperatorStore.setOperator(...) with an _operator of JBV3Token, a _domain of 1, and a _permissionIndexes of [12] (Transfer).
            Call v2 JBOperatorStore.setOperator with an operator of JBV3Token, a domain of 1, and a permissionIndexes of 12 (Transfer).
            Call Tickets.approve(...) on v1 JBX with a spender of JBV3Token and the maximum amount (the maximum UINT256, 2**256 - 1).
            Call JBV3Token.migrate().
        */
        uint256 _v1Jbx;
        uint256 _v1Ticket;
        uint256 _v2Jbx;
        uint256 _v3Jbx;

        // Check: sanity: v3 
        assertEq(jbTokenStore.balanceOf(multisig, 1), _v1Jbx + _v1Ticket + _v2Jbx);

        // Check: v3 = v1 + ticket + v2 ?
        assertEq(jbTokenStore.balanceOf(multisig, 1), _v1Jbx + _v1Ticket + _v2Jbx);

        // Check: v1 == ticket == v2 == 0 ?
    }
}
