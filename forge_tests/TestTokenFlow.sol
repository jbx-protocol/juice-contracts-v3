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
    JBGroupedSplits[] private _groupedSplits;
    JBFundAccessConstraints[] private _fundAccessConstraints;
    IJBPaymentTerminal[] private _terminals;
    uint256 private _projectId;
    address private _projectOwner;
    address private _beneficiary;

    function setUp() public override {
        super.setUp();

        _projectOwner = multisig();
        _beneficiary = beneficiary();
        _controller = jbController();
        _tokenStore = jbTokenStore();
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
            reservedRate: jbLibraries().MAX_RESERVED_RATE() / 2,
            redemptionRate: 0,
            baseCurrency: 1,
            pausePay: false,
            pauseDistributions: false,
            pauseRedeem: false,
            pauseBurn: false,
            allowMinting: true,
            allowTerminalMigration: false,
            allowControllerMigration: false,
            holdFees: false,
            preferClaimedTokenOverride: false,
            useTotalOverflowForRedemptions: false,
            useDataSourceForPay: false,
            useDataSourceForRedeem: false,
            dataSource: address(0),
            metadata: 0
        });

        JBFundingCycleConfiguration[] memory _cycleConfig = new JBFundingCycleConfiguration[](1);
        _cycleConfig[0].mustStartAtOrAfter = block.timestamp;
        _cycleConfig[0].data = _data;
        _cycleConfig[0].metadata = _metadata;
        _cycleConfig[0].groupedSplits = _groupedSplits;
        _cycleConfig[0].fundAccessConstraints = _fundAccessConstraints;
        _projectId = _controller.launchProjectFor(
            _projectOwner,
            _projectMetadata,
            _cycleConfig,
            _terminals,
            ""
        );
    }

    function testFuzzTokenFlow(
        uint224 _mintAmount,
        uint256 _burnAmount,
        bool _issueToken,
        bool _mintPreferClaimed,
        bool _burnPreferClaimed
    ) public {
        vm.startPrank(_projectOwner);

        if (_issueToken) {
            // Issue an ERC-20 token for project
            _tokenStore.issueFor({
                projectId: _projectId, 
                name: "TestName", 
                symbol: "TestSymbol"
            });
        } else {
            // Create a new IJBToken and change it's owner to the tokenStore
            IJBToken _newToken = new JBToken({
                _name: 'NewTestName', 
                _symbol: 'NewTestSymbol', 
                _projectId: _projectId
            });

            Ownable(address(_newToken)).transferOwnership(address(_tokenStore));

            // Set the projects token to _newToken
            _tokenStore.setFor(_projectId, _newToken);

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
            preferClaimedTokens: _mintPreferClaimed, 
            useReservedRate: true 
        }
        );

        uint256 _expectedTokenBalance = _mintAmount * _metadata.reservedRate / jbLibraries().MAX_RESERVED_RATE();

        // Make sure the beneficiary has the correct amount of tokens.
        assertEq(_tokenStore.balanceOf(_beneficiary, _projectId), _expectedTokenBalance );

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
            memo: "Burn memo",
            preferClaimedTokens: _burnPreferClaimed
        });

        // Make sure the total balance of tokens is updated.
        assertEq(_tokenStore.balanceOf(_beneficiary, _projectId), _expectedTokenBalance);
    }

    function testLargeTokenClaimFlow() public {
        // Calls will originate from project
        vm.startPrank(_projectOwner);

        // Issue an ERC-20 token for project,
        _tokenStore.issueFor({
            projectId: _projectId, 
            name: "TestName", 
            symbol: "TestSymbol"
        });

        // Mint claimed tokens to beneficiary.
        _controller.mintTokensOf({
            projectId: _projectId, 
            tokenCount: type(uint224).max / 2, 
            beneficiary: _beneficiary, 
            memo: "Mint memo", 
            preferClaimedTokens: true, 
            useReservedRate: false 
        });

        // Mint unclaimed tokens to beneficiary
        _controller.mintTokensOf({
            projectId: _projectId, 
            tokenCount: type(uint224).max / 2, 
            beneficiary: _beneficiary, 
            memo: "Mint memo", 
            preferClaimedTokens: false, 
            useReservedRate: false
        });

        // Try to claim the unclaimed tokens
        vm.stopPrank();
        vm.prank(_beneficiary);
        _tokenStore.claimFor({
            holder: _beneficiary,
            projectId: _projectId,
            amount: 1,
            beneficiary: _beneficiary
        });
    }
}
