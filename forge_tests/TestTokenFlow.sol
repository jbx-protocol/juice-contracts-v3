// SPDX-License-Identifier: MIT
pragma solidity ^0.8.6;

import /* {*} from */ "./helpers/TestBaseWorkflow.sol";

// Launch project, issue token or sets the token, mint token, burn token
contract TestTokenFlow_Local is TestBaseWorkflow {
    IJBController private _controller;
    IJBTokens private _tokens;
    JBProjectMetadata private _projectMetadata;
    JBRulesetData private _data;
    JBRulesetMetadata _metadata;
    IJBTerminal private _terminal;
    uint256 private _projectId;
    address private _projectOwner;
    address private _beneficiary;

    function setUp() public override {
        super.setUp();

        _projectOwner = multisig();
        _beneficiary = beneficiary();
        _controller = jbController();
        _tokens = jbTokens();
        _terminal = jbMultiTerminal();
        _projectMetadata = JBProjectMetadata({content: "myIPFSHash", domain: 1});
        _data = JBRulesetData({
            duration: 0,
            weight: 1000 * 10 ** 18,
            decayRate: 0,
            approvalHook: IJBRulesetApprovalHook(address(0))
        });
        _metadata = JBRulesetMetadata({
            global: JBGlobalRulesetMetadata({
                allowSetTerminals: false,
                allowSetController: false,
                pauseTransfers: false
            }),
            reservedRate: JBConstants.MAX_RESERVED_RATE / 2,
            redemptionRate: 0,
            baseCurrency: uint32(uint160(JBTokenList.Native)),
            pausePay: false,
            allowDiscretionaryMinting: true,
            allowTerminalMigration: false,
            allowControllerMigration: false,
            holdFees: false,
            useTotalSurplusForRedemptions: false,
            useDataHookForPay: false,
            useDataHookForRedeem: false,
            dataHook: address(0),
            metadata: 0
        });

        // Package up cycle config.
        JBRulesetConfig[] memory _rulesetConfig = new JBRulesetConfig[](1);
        _rulesetConfig[0].mustStartAtOrAfter = 0;
        _rulesetConfig[0].data = _data;
        _rulesetConfig[0].metadata = _metadata;
        _rulesetConfig[0].splitGroups = new JBSplitGroup[](0);
        _rulesetConfig[0].fundAccessLimitGroup = new JBFundAccessLimitGroup[](0);

        // Package up terminal config.
        JBTerminalConfig[] memory _terminalConfigurations = new JBTerminalConfig[](1);
        JBAccountingContextConfig[] memory _accountingContexts = new JBAccountingContextConfig[](1);
        _accountingContexts[0] = JBAccountingContextConfig({
            token: JBTokenList.Native,
            standard: JBTokenStandards.NATIVE
        });
        _terminalConfigurations[0] =
            JBTerminalConfig({terminal: _terminal, accountingContextConfigs: _accountingContexts});

        _projectId = _controller.launchProjectFor({
            owner: address(_projectOwner),
            projectMetadata: _projectMetadata,
            rulesetConfigurations: _rulesetConfig,
            terminalConfigurations: _terminalConfigurations,
            memo: ""
        });
    }

    function testFuzzTokenFlow(
        uint208 _mintAmount,
        uint256 _burnAmount,
        bool _issueToken,
        bool _mintPreferClaimed,
        bool _burnPreferClaimed
    ) public {
        vm.startPrank(_projectOwner);

        if (_issueToken) {
            // Issue an ERC-20 token for project
            _tokens.deployERC20TokenFor({
                projectId: _projectId,
                name: "TestName",
                symbol: "TestSymbol"
            });
        } else {
            // Create a new IJBToken and change it's owner to the tokens
            IJBToken _newToken = new JBERC20Token({
                _name: "NewTestName",
                _symbol: "NewTestSymbol",
                _owner: _projectOwner
            });

            Ownable(address(_newToken)).transferOwnership(address(_tokens));

            // Set the projects token to `_newToken`
            _tokens.setTokenFor(_projectId, _newToken);

            // Make sure the project's new JBToken is set.
            assertEq(address(_tokens.tokenOf(_projectId)), address(_newToken));
        }

        // Expect revert if there are no tokens being minted.
        if (_mintAmount == 0) vm.expectRevert(abi.encodeWithSignature("ZERO_TOKENS_TO_MINT()"));

        // Mint tokens to beneficiary.
        _controller.mintTokensOf({
            projectId: _projectId,
            tokenCount: _mintAmount,
            beneficiary: _beneficiary,
            memo: "Mint memo",
            useReservedRate: true
        });

        uint256 _expectedTokenBalance =
            _mintAmount * _metadata.reservedRate / JBConstants.MAX_RESERVED_RATE;

        // Make sure the beneficiary has the correct amount of tokens.
        assertEq(_tokens.totalBalanceOf(_beneficiary, _projectId), _expectedTokenBalance);

        if (_burnAmount == 0) {
            vm.expectRevert(abi.encodeWithSignature("NO_BURNABLE_TOKENS()"));
        } else if (_burnAmount > _expectedTokenBalance) {
            vm.expectRevert(abi.encodeWithSignature("INSUFFICIENT_FUNDS()"));
        } else {
            _expectedTokenBalance = _expectedTokenBalance - _burnAmount;
        }

        // Burn tokens from beneficiary.
        vm.stopPrank();
        vm.prank(_beneficiary);
        _controller.burnTokensOf({
            holder: _beneficiary,
            projectId: _projectId,
            tokenCount: _burnAmount,
            memo: "Burn memo"
        });

        // Make sure the total balance of tokens is updated.
        assertEq(_tokens.totalBalanceOf(_beneficiary, _projectId), _expectedTokenBalance);
    }

    function testMintUnclaimedAtLimit() public {
        // Pay the project such that the `_beneficiary` receives 1000 "unclaimed" project tokens.
        vm.deal(_beneficiary, 1 ether);
        _terminal.pay{value: 1 ether}({
            projectId: _projectId,
            amount: 1 ether,
            token: JBTokenList.Native,
            beneficiary: _beneficiary,
            minReturnedTokens: 0,
            memo: "",
            metadata: new bytes(0)
        });

        // Calls will originate from project
        vm.startPrank(_projectOwner);

        // Issue an ERC-20 token for project,
        _tokens.deployERC20TokenFor({projectId: _projectId, name: "TestName", symbol: "TestSymbol"});

        // Mint claimed tokens to beneficiary: since this is 1000 over uint(208) it will revert.
        vm.expectRevert(abi.encodeWithSignature("OVERFLOW_ALERT()"));

        _controller.mintTokensOf({
            projectId: _projectId,
            tokenCount: type(uint208).max,
            beneficiary: _beneficiary,
            memo: "Mint memo",
            useReservedRate: false
        });
    }
}
