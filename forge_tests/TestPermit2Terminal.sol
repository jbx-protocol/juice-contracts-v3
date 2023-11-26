// SPDX-License-Identifier: MIT
pragma solidity >=0.8.6;

import /* {*} from */ "./helpers/TestBaseWorkflow.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {PermitSignature} from '@permit2/src/test/utils/PermitSignature.sol';

contract TestPermit2Terminal_Local is TestBaseWorkflow, PermitSignature {
    uint256 private constant _WEIGHT = 1000 * 10 ** 18;

    IJBController3_1 private _controller;
    IJBPaymentTerminal private _terminal;
    /* IJBTerminalStore private _terminalStore;
    IJBTokenStore private _tokenStore; */
    IERC20 private _usdc;
    JBDelegateMetadataHelper private _helper;
    address private _projectOwner;
    address private _beneficiary;

    uint256 _projectId;

    // Permit2 params
    bytes32 DOMAIN_SEPARATOR;
    address from;
    uint256 fromPrivateKey;

    function setUp() public override {
        super.setUp();

        _controller = jbController();
        _projectOwner = multisig();
        _beneficiary = beneficiary();
        _terminal = jbPayoutRedemptionTerminal();
        /* _tokenStore = jbTokenStore();
        _terminalStore = jbTerminalStore(); */
        _helper = metadataHelper();
        _usdc = usdcToken();

        fromPrivateKey = 0x12341234;
        from = vm.addr(fromPrivateKey);
        DOMAIN_SEPARATOR = permit2().DOMAIN_SEPARATOR();

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
            redemptionRate: JBConstants.MAX_REDEMPTION_RATE,
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

        JBTerminalConfig[] memory _terminalConfigurations = new JBTerminalConfig[](1);
        JBAccountingContextConfig[] memory _accountingContexts = new JBAccountingContextConfig[](2);
        _accountingContexts[0] =
            JBAccountingContextConfig({token: JBTokens.ETH, standard: JBTokenStandards.NATIVE});
        _accountingContexts[1] =
                JBAccountingContextConfig({token: address(_usdc), standard: JBTokenStandards.ERC20});
        _terminalConfigurations[0] =
            JBTerminalConfig({terminal: _terminal, accountingContextConfigs: _accountingContexts});

        // First project for fee collection
        _controller.launchProjectFor({
            owner: _projectOwner,
            projectMetadata: JBProjectMetadata({content: "myIPFSHash", domain: 0}),
            fundingCycleConfigurations: _cycleConfig,
            terminalConfigurations: _terminalConfigurations,
            memo: ""
        });

        _projectId = _controller.launchProjectFor({
            owner: _projectOwner,
            projectMetadata: JBProjectMetadata({content: "myIPFSHash", domain: 1}),
            fundingCycleConfigurations: _cycleConfig,
            terminalConfigurations: _terminalConfigurations,
            memo: ""
        });
    }

    function testFuzzAddToBalance(uint256 _coins) public {
        _coins = bound(_coins, 0, type(uint160).max);
        uint48 _expires = uint48(block.timestamp + 5);
        uint256 _deadline = block.timestamp + 100;

        // prepare permit details for signing
        IAllowanceTransfer.PermitDetails memory details =
            IAllowanceTransfer.PermitDetails({token: address(_usdc), amount: uint160(_coins), expiration: _expires, nonce: 0});

        IAllowanceTransfer.PermitSingle memory permit =
            IAllowanceTransfer.PermitSingle({
            details: details,
            spender: address(_terminal),
            sigDeadline: _deadline
        });

        // Sign permit details
        bytes memory sig = getPermitSignature(permit, fromPrivateKey, DOMAIN_SEPARATOR);

        JBSingleAllowanceData memory permitData = 
            JBSingleAllowanceData({
                sigDeadline: _deadline,
                amount: uint160(_coins),
                expiration: _expires,
                nonce: uint48(0),
                signature: sig
        });

        // prepare data for metadata helper
        bytes4[] memory _ids = new bytes4[](1);
        bytes[] memory _datas = new bytes[](1);
        _datas[0] = abi.encode(permitData);
        _ids[0] = bytes4(uint32(uint160(address(_terminal))));

        // Use jb metadata library to encode
        bytes memory _packedData = _helper.createMetadata(_ids, _datas);

        // Give coins and approve permit2 contract
        deal(address(_usdc), from, _coins);
        vm.prank(from);
        IERC20(address(_usdc)).approve(address(permit2()), _coins);

        // Add to balance using permit2 data, which should transfer tokens
        vm.prank(from);
        _terminal.addToBalanceOf(
            _projectId,
            address(_usdc),
            _coins,
            false,
            "testing permit2",
            _packedData
        );

        // Check that tokens were transfered
        assertEq(_usdc.balanceOf(address(_terminal)), _coins);
    }
}