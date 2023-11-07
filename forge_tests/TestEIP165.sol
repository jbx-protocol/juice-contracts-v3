// SPDX-License-Identifier: MIT
pragma solidity ^0.8.6;

import /* {*} from */ "./helpers/TestBaseWorkflow.sol";

/// Contracts are introspective about the interfaces they adhere to.
contract TestEIP165_Local is TestBaseWorkflow {
    bytes4 constant private _notSupportedInterface = 0xffffffff;

    uint256 constant _projectId = 2;
    uint256 constant _splitsProjectId = 3;
    address payable constant _splitsBeneficiary = payable(address(420));
    uint256 constant _splitsDomain = 1;
    uint256 constant _splitsGroup = 1;
    bool constant _splitsPreferClaimedTokens = false;
    string constant _splitsMemo = "";
    bytes constant _splitsMetadata = "";
    bool constant _splitsPreferAddToBalance = true;
    address constant _splitsOwner = address(420);

    function testJBController3_1() public {
        JBController3_1 _controller = jbController();

        // Should support these interfaces
        assertTrue(_controller.supportsInterface(type(IERC165).interfaceId));
        assertTrue(_controller.supportsInterface(type(IJBMigratable).interfaceId));
        assertTrue(_controller.supportsInterface(type(IJBOperatable).interfaceId));
        assertTrue(_controller.supportsInterface(type(IJBController3_1).interfaceId));

        // Make sure it doesn't always return true
        assertTrue(!_controller.supportsInterface(_notSupportedInterface));
    }

    function testJBERC20PaymentTerminal() public {
        JBERC20PaymentTerminal3_1_2 _terminal = jbERC20PaymentTerminal();

        // Should support these interfaces
        assertTrue(_terminal.supportsInterface(type(IERC165).interfaceId));
        assertTrue(_terminal.supportsInterface(type(IJBPaymentTerminal).interfaceId));
        assertTrue(_terminal.supportsInterface(type(IJBRedemptionTerminal).interfaceId));
        assertTrue(_terminal.supportsInterface(type(IJBSingleTokenPaymentTerminal).interfaceId));
        assertTrue(_terminal.supportsInterface(type(IJBOperatable).interfaceId));
        assertTrue(_terminal.supportsInterface(type(IJBPayoutTerminal3_1).interfaceId));
        assertTrue(_terminal.supportsInterface(type(IJBAllowanceTerminal3_1).interfaceId));
        assertTrue(_terminal.supportsInterface(type(IJBPayoutRedemptionPaymentTerminal3_1).interfaceId));

        // Make sure it doesn't always return true
        assertTrue(!_terminal.supportsInterface(_notSupportedInterface));
    }

    function testJBETHPaymentTerminal() public {
        JBETHPaymentTerminal3_1_2 _terminal = jbETHPaymentTerminal();

        // Should support these interfaces
        assertTrue(_terminal.supportsInterface(type(IERC165).interfaceId));
        assertTrue(_terminal.supportsInterface(type(IJBPaymentTerminal).interfaceId));
        assertTrue(_terminal.supportsInterface(type(IJBRedemptionTerminal).interfaceId));
        assertTrue(_terminal.supportsInterface(type(IJBSingleTokenPaymentTerminal).interfaceId));
        assertTrue(_terminal.supportsInterface(type(IJBOperatable).interfaceId));

        assertTrue(_terminal.supportsInterface(type(IJBPayoutTerminal3_1).interfaceId));
        assertTrue(_terminal.supportsInterface(type(IJBAllowanceTerminal3_1).interfaceId));
        assertTrue(_terminal.supportsInterface(type(IJBPayoutRedemptionPaymentTerminal3_1).interfaceId));
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
        assertTrue(_projects.supportsInterface(type(IJBOperatable).interfaceId));

        // Make sure it doesn't always return true
        assertTrue(!_projects.supportsInterface(_notSupportedInterface));
    }

    function testJBReconfigurationBufferBallot() public {
        JBReconfigurationBufferBallot _ballot = new JBReconfigurationBufferBallot(3000);

        // Should support these interfaces
        assertTrue(_ballot.supportsInterface(type(IERC165).interfaceId));
        assertTrue(_ballot.supportsInterface(type(IJBFundingCycleBallot).interfaceId));

        // Make sure it doesn't always return true
        assertTrue(!_ballot.supportsInterface(_notSupportedInterface));
    }

    function testJBETHERC20SplitsPayer() public {
      
        JBETHERC20SplitsPayerDeployer _deployer = new JBETHERC20SplitsPayerDeployer(jbSplitsStore());

        JBETHERC20SplitsPayer _splitsPayer = JBETHERC20SplitsPayer(
            payable(
                address(
                _deployer.deploySplitsPayer(
                    _splitsProjectId,
                    _splitsDomain,
                    _splitsGroup,
                    _projectId,
                    _splitsBeneficiary,
                    _splitsPreferClaimedTokens,
                    _splitsMemo,
                    _splitsMetadata,
                    _splitsPreferAddToBalance,
                    _splitsOwner
        ))));

        // Should support these interfaces
        assertTrue(_splitsPayer.supportsInterface(type(IERC165).interfaceId));
        assertTrue(_splitsPayer.supportsInterface(type(IJBSplitsPayer).interfaceId));
        assertTrue(_splitsPayer.supportsInterface(type(IJBProjectPayer).interfaceId));

        // Make sure it doesn't always return true
        assertTrue(!_splitsPayer.supportsInterface(_notSupportedInterface));
    }
}
