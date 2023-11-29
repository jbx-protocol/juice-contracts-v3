// SPDX-License-Identifier: MIT
pragma solidity ^0.8.6;

import /* {*} from */ "./helpers/TestBaseWorkflow.sol";

// launch project, issue token or sets the token, mint token, burn token
contract TestTokenFlow_Local is TestBaseWorkflow {
    IJBController3_1 private _controller;
    IJBTokenStore private _tokenStore;
    JBProjectMetadata private _projectMetadata;
    JBFundingCycleData private _data;
    JBFundingCycleMetadata _metadata;
    IJBPaymentTerminal private _terminal;
    uint256 private _projectId;
    address private _projectOwner;
    address private _beneficiary;

    function setUp() public override {
        super.setUp();

        _projectOwner = multisig();
        _beneficiary = beneficiary();
        _controller = jbController();
        _tokenStore = jbTokenStore();
        _terminal = jbPayoutRedemptionTerminal();
        _projectMetadata = JBProjectMetadata({content: "myIPFSHash", domain: 1});
        _data = JBFundingCycleData({
            duration: 0,
            weight: 1000 * 10 ** 18,
            discountRate: 0,
            ballot: IJBFundingCycleBallot(address(0))
        });
        _metadata = JBFundingCycleMetadata({
            global: JBGlobalFundingCycleMetadata({
                allowSetTerminals: false,
                allowSetController: false,
                pauseTransfers: false
            }),
            reservedRate: JBConstants.MAX_RESERVED_RATE / 2,
            redemptionRate: 0,
            baseCurrency: uint32(uint160(JBTokens.ETH)),
            pausePay: false,
            allowMinting: true,
            allowTerminalMigration: false,
            allowControllerMigration: false,
            holdFees: false,
            useTotalOverflowForRedemptions: false,
            useDataSourceForPay: false,
            useDataSourceForRedeem: false,
            dataSource: address(0),
            metadata: 0
        });

        // Package up cycle config.
        JBFundingCycleConfig[] memory _cycleConfig = new JBFundingCycleConfig[](1);
        _cycleConfig[0].mustStartAtOrAfter = 0;
        _cycleConfig[0].data = _data;
        _cycleConfig[0].metadata = _metadata;
        _cycleConfig[0].groupedSplits = new JBGroupedSplits[](0);
        _cycleConfig[0].fundAccessConstraints = new JBFundAccessConstraints[](0);

        // Package up terminal config.
        JBTerminalConfig[] memory _terminalConfigurations = new JBTerminalConfig[](1);
        JBAccountingContextConfig[] memory _accountingContexts = new JBAccountingContextConfig[](1);
        _accountingContexts[0] =
            JBAccountingContextConfig({token: JBTokens.ETH, standard: JBTokenStandards.NATIVE});
        _terminalConfigurations[0] =
            JBTerminalConfig({terminal: _terminal, accountingContextConfigs: _accountingContexts});

        _projectId = _controller.launchProjectFor({
            owner: address(_projectOwner),
            projectMetadata: _projectMetadata,
            fundingCycleConfigurations: _cycleConfig,
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
            _controller.issueTokenFor({
                projectId: _projectId,
                name: "TestName",
                symbol: "TestSymbol"
            });
        } else {
            // Create a new IJBToken and change it's owner to the tokenStore
            IJBToken _newToken =
                new JBToken({_name: "NewTestName", _symbol: "NewTestSymbol", _owner: _projectOwner});

            Ownable(address(_newToken)).transferOwnership(address(_tokenStore));

            // Set the projects token to _newToken
            _controller.setTokenFor(_projectId, _newToken);

            // Make sure the project's new JBToken is set.
            assertEq(address(_tokenStore.tokenOf(_projectId)), address(_newToken));
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
        assertEq(_tokenStore.balanceOf(_beneficiary, _projectId), _expectedTokenBalance);

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
        assertEq(_tokenStore.balanceOf(_beneficiary, _projectId), _expectedTokenBalance);
    }

    function testMintUnclaimedAtLimit() public {
        // Pay the project such that the _beneficiary receives 1000 "unclaimed" project tokens.
        vm.deal(_beneficiary, 1 ether);
        _terminal.pay{value: 1 ether}({
            projectId: _projectId,
            amount: 1 ether,
            token: JBTokens.ETH,
            beneficiary: _beneficiary,
            minReturnedTokens: 0,
            memo: "",
            metadata: new bytes(0)
        });

        // Calls will originate from project
        vm.startPrank(_projectOwner);

        // Issue an ERC-20 token for project,
        _controller.issueTokenFor({projectId: _projectId, name: "TestName", symbol: "TestSymbol"});

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
