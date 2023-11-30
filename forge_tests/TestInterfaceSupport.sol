// SPDX-License-Identifier: MIT
pragma solidity ^0.8.6;

import /* {*} from */ "./helpers/TestBaseWorkflow.sol";

/// Contracts are introspective about the interfaces they adhere to.
contract TestEIP165_Local is TestBaseWorkflow {
    bytes4 private constant _notSupportedInterface = 0xffffffff;

    function testJBController() public {
        JBController _controller = jbController();

        // Should support these interfaces
        assertTrue(_controller.supportsInterface(type(IERC165).interfaceId));
        assertTrue(_controller.supportsInterface(type(IJBMigratable).interfaceId));
        assertTrue(_controller.supportsInterface(type(IJBPermissioned).interfaceId));
        assertTrue(_controller.supportsInterface(type(IJBController).interfaceId));

        // Make sure it doesn't always return true
        assertTrue(!_controller.supportsInterface(_notSupportedInterface));
    }

    function testJBMultiTerminal() public {
        JBMultiTerminal _terminal = jbPayoutRedemptionTerminal();

        // Should support these interfaces
        assertTrue(_terminal.supportsInterface(type(IJBMultiTerminal).interfaceId));
        assertTrue(_terminal.supportsInterface(type(IJBTerminal).interfaceId));
        assertTrue(_terminal.supportsInterface(type(IJBRedeemTerminal).interfaceId));
        assertTrue(_terminal.supportsInterface(type(IJBPayoutTerminal).interfaceId));
        assertTrue(_terminal.supportsInterface(type(IJBPermitTerminal).interfaceId));
        assertTrue(_terminal.supportsInterface(type(IJBFeeTerminal).interfaceId));
        assertTrue(_terminal.supportsInterface(type(IERC165).interfaceId));

        // Make sure it doesn't always return true
        assertTrue(!_terminal.supportsInterface(_notSupportedInterface));
    }

    function testJBProjects() public {
        JBProjects _projects = jbProjects();

        // Should support these interfaces
        assertTrue(_projects.supportsInterface(type(IERC165).interfaceId));
        assertTrue(_projects.supportsInterface(type(IERC721).interfaceId));
        assertTrue(_projects.supportsInterface(type(IERC721Metadata).interfaceId));
        assertTrue(_projects.supportsInterface(type(IJBProjects).interfaceId));
        assertTrue(_projects.supportsInterface(type(IJBPermissioned).interfaceId));

        // Make sure it doesn't always return true
        assertTrue(!_projects.supportsInterface(_notSupportedInterface));
    }

    function testJBDeadline() public {
        JBDeadline _ballot = new JBDeadline(3000);

        // Should support these interfaces
        assertTrue(_ballot.supportsInterface(type(IERC165).interfaceId));
        assertTrue(_ballot.supportsInterface(type(IJBRulesetApprovalHook).interfaceId));

        // Make sure it doesn't always return true
        assertTrue(!_ballot.supportsInterface(_notSupportedInterface));
    }
}
