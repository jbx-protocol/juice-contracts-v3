// SPDX-License-Identifier: MIT
pragma solidity >=0.8.6;

import /* {*} from */ "./helpers/TestBaseWorkflow.sol";

contract TestDelegates_Local is TestBaseWorkflow {
    uint256 private _ethCurrency; 
    IJBController3_1 private _controller;
    IJBMultiTerminal private __terminal;
    IJBPrices private _prices;
    JBTokenStore private _tokenStore;
    
    JBProjectMetadata private _projectMetadata;
    JBFundingCycleData private _data;
    JBFundingCycleMetadata _metadata;
    JBGroupedSplits[] private _groupedSplits;
    IJBPaymentTerminal[] private _terminals;
    address private _projectOwner;
    address private _beneficiary;

    address _datasource = address(bytes20(keccak256("datasource")));

    uint256 _projectId;

    uint256 WEIGHT = 1000 * 10 ** 18;

    function setUp() public override {
        super.setUp();

        uint256 _ethDistributionLimit = 1 ether;
        _ethCurrency = uint32(uint160(JBTokens.ETH));
        _controller = jbController();
        _projectOwner = multisig();
        _beneficiary = beneficiary();
        _prices = jbPrices();
        __terminal = jbPayoutRedemptionTerminal();
        _tokenStore = jbTokenStore();

        _projectMetadata = JBProjectMetadata({content: "myIPFSHash", domain: 1});

        _data = JBFundingCycleData({
            duration: 14,
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
            redemptionRate: JBConstants.MAX_RESERVED_RATE / 2,
            baseCurrency: uint32(uint160(JBTokens.ETH)),
            pausePay: false,
            allowMinting: false,
            allowTerminalMigration: false,
            allowControllerMigration: false,
            holdFees: false,
            useTotalOverflowForRedemptions: false,
            useDataSourceForPay: true,
            useDataSourceForRedeem: true,
            dataSource: _datasource,
            metadata: 0
        });

        // Package up fund access constraints
        JBFundAccessConstraints[] memory _fundAccessConstraints = new JBFundAccessConstraints[](1);
        JBCurrencyAmount[] memory _distributionLimits = new JBCurrencyAmount[](1);
        JBCurrencyAmount[] memory _overflowAllowances = new JBCurrencyAmount[](1);
        
        _distributionLimits[0] = JBCurrencyAmount({
            value: _ethDistributionLimit,
            currency: uint32(uint160(JBTokens.ETH))
        });
        _overflowAllowances[0] = JBCurrencyAmount({
            value: 1 ether,
            currency: uint32(uint160(JBTokens.ETH))
        });
        _fundAccessConstraints[0] = 
            JBFundAccessConstraints({
                terminal: __terminal,
                token: JBTokens.ETH,
                distributionLimits: _distributionLimits,
                overflowAllowances: _overflowAllowances
            });

        // Package up cycle config.
        JBFundingCycleConfig[] memory _cycleConfig = new JBFundingCycleConfig[](1);
        _cycleConfig[0].mustStartAtOrAfter = 0;
        _cycleConfig[0].data = _data;
        _cycleConfig[0].metadata = _metadata;
        _cycleConfig[0].groupedSplits = _groupedSplits;
        _cycleConfig[0].fundAccessConstraints = _fundAccessConstraints;

        JBTerminalConfig[] memory _terminalConfigurations = new JBTerminalConfig[](1);
            JBAccountingContextConfig[] memory _accountingContexts = new JBAccountingContextConfig[](1);
            _accountingContexts[0] = JBAccountingContextConfig({
                token: JBTokens.ETH,
                standard: JBTokenStandards.NATIVE
            });
            /* _accountingContexts[1] = JBAccountingContextConfig({
                token: address(usdcToken()),
                standard: JBTokenStandards.ERC20
            }); */
            _terminalConfigurations[0] = JBTerminalConfig({
                terminal: __terminal,
                accountingContextConfigs: _accountingContexts
            });

        _terminals.push(__terminal);

        /* // dummy
        _controller.launchProjectFor({
            owner: _projectOwner,
            projectMetadata: _projectMetadata,
            fundingCycleConfigurations: _cycleConfig,
            terminalConfigurations: _terminalConfigurations,
            memo: ""
        }); */

        _projectId = _controller.launchProjectFor({
            owner: _projectOwner,
            projectMetadata: _projectMetadata,
            fundingCycleConfigurations: _cycleConfig,
            terminalConfigurations: _terminalConfigurations,
            memo: ""
        });
    }

    function testPayDelegates(uint256 _numberOfAllocations, uint256 _totalToAllocate) public {
        _numberOfAllocations = bound(_numberOfAllocations, 1, 5);

        JBPayDelegateAllocation3_1_1[] memory _allocations =
            new JBPayDelegateAllocation3_1_1[](_numberOfAllocations);
        uint256[] memory payDelegateAmounts = new uint256[](_numberOfAllocations);

        _beneficiary = address(bytes20(keccak256("beneficiary")));

        // Check that we are not going to overflow uint256 and calculate the total pay amount
        _totalToAllocate = bound(_totalToAllocate, payDelegateAmounts.length, type(uint224).max - 1);
        uint256 _paySum = _totalToAllocate;

        // Allocate descending amounts (by half)
        for (uint256 i; i < payDelegateAmounts.length - 1; i++) {
            payDelegateAmounts[i] = _totalToAllocate / (payDelegateAmounts.length * 2);
            _totalToAllocate -= payDelegateAmounts[i];
        }

        // Rest to allocate into the last allocations
        payDelegateAmounts[payDelegateAmounts.length - 1] = _totalToAllocate;

        (JBFundingCycle memory fundingCycle,) = _controller.currentFundingCycleOf(_projectId);
        for (uint256 i = 0; i < payDelegateAmounts.length; i++) {
            address _delegateAddress =
                address(bytes20(keccak256(abi.encodePacked("PayDelegate", i))));

            _allocations[i] = JBPayDelegateAllocation3_1_1(
                IJBPayDelegate3_1_1(_delegateAddress), payDelegateAmounts[i], bytes("")
            );

            JBDidPayData3_1_1 memory _didPayData = JBDidPayData3_1_1(
                _beneficiary,
                _projectId,
                fundingCycle.configuration,
                JBTokenAmount(
                    JBTokens.ETH,
                    _paySum,
                    JBMultiTerminal(address(_terminals[0])).accountingContextForTokenOf(_projectId, JBTokens.ETH).decimals,
                    JBMultiTerminal(address(_terminals[0])).accountingContextForTokenOf(_projectId, JBTokens.ETH).currency
                ),
                JBTokenAmount(
                    JBTokens.ETH,
                    payDelegateAmounts[i],
                    JBMultiTerminal(address(_terminals[0])).accountingContextForTokenOf(_projectId, JBTokens.ETH).decimals,
                    JBMultiTerminal(address(_terminals[0])).accountingContextForTokenOf(_projectId, JBTokens.ETH).currency
                ),
                0,
                0,
                _beneficiary,
                "",
                new bytes(0) // empty metadata
            );

            // Mock the delegate
            vm.mockCall(
                _delegateAddress, abi.encodeWithSelector(IJBPayDelegate3_1_1.didPay.selector), ""
            );

            // Assert that the delegate gets called with the expected value
            vm.expectCall(
                _delegateAddress,
                payDelegateAmounts[i],
                abi.encodeWithSelector(IJBPayDelegate3_1_1.didPay.selector, _didPayData)
            );

            /* // Expect an event to be emitted for every delegate
            vm.expectEmit(true, true, true, true);
            emit DelegateDidPay(
                IJBPayDelegate3_1_1(_delegateAddress),
                _didPayData,
                payDelegateAmounts[i],
                _beneficiary
            ); */
        }

        vm.mockCall(
            _datasource,
            abi.encodeWithSelector(IJBFundingCycleDataSource3_1_1.payParams.selector),
            abi.encode(
                0, // weight
                "", // memo
                _allocations // allocations
            )
        );

        vm.deal(_beneficiary, _paySum);
        vm.prank(_beneficiary);

        // Pay the project such that the _beneficiary receives project tokens.
        __terminal.pay{value: _paySum}({
            projectId: _projectId, 
            amount: _paySum, 
            token: JBTokens.ETH, 
            beneficiary: _beneficiary, 
            minReturnedTokens: 0, 
            memo: "Forge Test",
            metadata: new bytes(0)
        }); 
    }

    event DelegateDidPay(
        IJBPayDelegate3_1_1 indexed delegate,
        JBDidPayData3_1_1 data,
        uint256 delegatedAmount,
        address caller
    );
}
