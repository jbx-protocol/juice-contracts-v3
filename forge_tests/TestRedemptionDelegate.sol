// SPDX-License-Identifier: MIT
pragma solidity >=0.8.6;

import /* {*} from */ "./helpers/TestBaseWorkflow.sol";

contract TestDelegates_Local is TestBaseWorkflow {
    uint8 private constant _WEIGHT_DECIMALS = 18;
    uint8 private constant _NATIVE_TOKEN_DECIMALS = 18;
    uint256 private constant _WEIGHT = 1000 * 10 ** _WEIGHT_DECIMALS;
    uint256 private constant _DATA_SOURCE_WEIGHT = 2000 * 10 ** _WEIGHT_DECIMALS;
    address private constant _DATA_SOURCE = address(bytes20(keccak256("datasource")));
    bytes private constant _PAYER_METADATA = bytes("Some payer metadata");

    IJBController3_1 private _controller;
    IJBPaymentTerminal private _terminal;
    address private _projectOwner;
    address private _beneficiary;
    address private _payer;

    uint256 _projectId;

    function setUp() public override {
        super.setUp();

        vm.label(_DATA_SOURCE, "Data Source");

        _controller = jbController();
        _projectOwner = multisig();
        _beneficiary = beneficiary();
        _payer = address(1_234_567);
        _terminal = jbPayoutRedemptionTerminal();

        JBFundingCycleData memory _data = JBFundingCycleData({
            duration: 0,
            weight: _WEIGHT,
            discountRate: 0,
            ballot: IJBFundingCycleBallot(address(0))
        });

        JBFundingCycleMetadata memory _metadata = JBFundingCycleMetadata({
            global: JBGlobalFundingCycleMetadata({
                allowSetTerminals: false,
                allowSetController: false,
                pauseTransfers: false
            }),
            reservedRate: 0,
            redemptionRate: 0,
            baseCurrency: uint32(uint160(JBTokens.ETH)),
            pausePay: false,
            allowMinting: false,
            allowTerminalMigration: false,
            allowControllerMigration: false,
            holdFees: false,
            useTotalOverflowForRedemptions: false,
            useDataSourceForPay: false,
            useDataSourceForRedeem: true,
            dataSource: _DATA_SOURCE,
            metadata: 0
        });

        // Package up cycle config.
        JBFundingCycleConfig[] memory _cycleConfig = new JBFundingCycleConfig[](1);
        _cycleConfig[0].mustStartAtOrAfter = 0;
        _cycleConfig[0].data = _data;
        _cycleConfig[0].metadata = _metadata;
        _cycleConfig[0].groupedSplits = new JBGroupedSplits[](0);
        _cycleConfig[0].fundAccessConstraints = new JBFundAccessConstraints[](0);

        JBTerminalConfig[] memory _terminalConfigurations = new JBTerminalConfig[](1);
        JBAccountingContextConfig[] memory _accountingContexts = new JBAccountingContextConfig[](1);
        _accountingContexts[0] =
            JBAccountingContextConfig({token: JBTokens.ETH, standard: JBTokenStandards.NATIVE});
        _terminalConfigurations[0] =
            JBTerminalConfig({terminal: _terminal, accountingContextConfigs: _accountingContexts});

        _projectId = _controller.launchProjectFor({
            owner: _projectOwner,
            projectMetadata: JBProjectMetadata({content: "myIPFSHash", domain: 1}),
            fundingCycleConfigurations: _cycleConfig,
            terminalConfigurations: _terminalConfigurations,
            memo: ""
        });
    }

    function testRedemptionDelegate(uint256 _ethPayAmount) public {

        _ethPayAmount = bound(_ethPayAmount, 0, type(uint256).max / _DATA_SOURCE_WEIGHT);

        // Delegate address
        address _redDelegate = makeAddr("SOFA");
        vm.label(_redDelegate, "Redemption Delegate");

        // Keep a reference to the current funding cycle.
        (JBFundingCycle memory _fundingCycle,) = _controller.currentFundingCycleOf(_projectId);

        // Reference tokens received from pay
        uint256 _tokensDealt = PRBMath.mulDiv(
            _ethPayAmount, _WEIGHT, 10 ** 18);

        // Reference allocations
        JBRedemptionDelegateAllocation3_1_1 memory _allocations = JBRedemptionDelegateAllocation3_1_1({
            delegate: IJBRedemptionDelegate3_1_1(_redDelegate),
            amount: _tokensDealt,
            metadata: ""
        });

        // Redemption Data for mocking
        JBDidRedeemData3_1_1 memory _redeemData = JBDidRedeemData3_1_1({
            holder: _payer,
            projectId: _projectId,
            currentFundingCycleConfiguration: _fundingCycle.configuration,
            projectTokenCount: PRBMath.mulDiv(
                    _ethPayAmount, _DATA_SOURCE_WEIGHT, 10 ** _NATIVE_TOKEN_DECIMALS
            ),
            reclaimedAmount: JBTokenAmount(
                    JBTokens.ETH,
                    _ethPayAmount,
                    _terminal.accountingContextForTokenOf(_projectId, JBTokens.ETH).decimals,
                    _terminal.accountingContextForTokenOf(_projectId, JBTokens.ETH).currency
                    ),
            forwardedAmount: JBTokenAmount(
                    address(jbTokenStore().tokenOf(_projectId)),
                    _tokensDealt,
                    _terminal.accountingContextForTokenOf(_projectId, JBTokens.ETH).decimals,
                    _terminal.accountingContextForTokenOf(_projectId, JBTokens.ETH).currency
                    ),
            redemptionRate: 0,
            beneficiary: payable(_payer),
            dataSourceMetadata: "",
            redeemerMetadata: ""
        });

        vm.deal(_payer, _ethPayAmount);
        vm.startPrank(_payer);

        // Pay the project such that the _beneficiary receives project tokens.
        _terminal.pay{value: _ethPayAmount}({
            projectId: _projectId,
            amount: _ethPayAmount,
            token: JBTokens.ETH,
            beneficiary: _payer,
            minReturnedTokens: 0,
            memo: "Forge Test",
            metadata: _PAYER_METADATA
        });

        assertEq(jbTokenStore().balanceOf(_payer, _projectId), _tokensDealt);

        // Redeem ETH from the overflow using only the _beneficiary's tokens needed to clear the ETH balance.
        _terminal.redeemTokensOf({
            holder: _payer,
            projectId: _projectId,
            count: _tokensDealt,
            token: JBTokens.ETH,
            minReclaimed: 0,
            beneficiary: payable(_payer),
            metadata: new bytes(0)
        });
        vm.stopPrank();
    }
}