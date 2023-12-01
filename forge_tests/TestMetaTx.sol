// SPDX-License-Identifier: MIT
pragma solidity >=0.8.6;

import /* {*} from */ "./helpers/TestBaseWorkflow.sol";
import {ERC2771Forwarder} from "@openzeppelin/contracts/metatx/ERC2771Forwarder.sol";
import {ERC2771ForwarderMock, ForwardRequest} from "./mock/ERC2771ForwarderMock.sol";

contract TestMetaTx_Local is TestBaseWorkflow {
    uint256 private constant _WEIGHT = 1000 * 10 ** 18;

    IJBController3_1 private _controller;
    IJBPaymentTerminal private _terminal;
    JBTokenStore private _tokenStore;
    ERC2771ForwarderMock internal _erc2771Forwarder = ERC2771ForwarderMock(address(123_456));
    address private _projectOwner;

    uint256 _projectId;

    // Meta Tx guys
    uint256 internal _signerPrivateKey;
    uint256 internal _relayerPrivateKey;
    address internal _signer;
    address internal _relayer;

    // utility function - setUp() is below
    function _forgeRequestData(
        uint256 value,
        uint256 nonce,
        uint48 deadline,
        bytes memory data,
        address target
    ) private view returns (ERC2771Forwarder.ForwardRequestData memory) {
        ForwardRequest memory request = ForwardRequest({
            from: _signer,
            to: address(target),
            value: value,
            gas: 300000,
            nonce: nonce,
            deadline: deadline,
            data: data
        });

        bytes32 digest = _erc2771Forwarder.structHash(request);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(_signerPrivateKey, digest);
        bytes memory signature = abi.encodePacked(r, s, v);

        return
            ERC2771Forwarder.ForwardRequestData({
                from: request.from,
                to: request.to,
                value: request.value,
                gas: request.gas,
                deadline: request.deadline,
                data: request.data,
                signature: signature
            });
    }

    function setUp() public override {
        super.setUp();

        _controller = jbController();
        _projectOwner = multisig();
        _tokenStore = jbTokenStore();
        _terminal = jbPayoutRedemptionTerminal();

        // Deploy forwarder
        deployCodeTo("ERC2771ForwarderMock.sol", abi.encode("ERC2771Forwarder"), address(123_456));

        _signerPrivateKey = 0xA11CE;
        _relayerPrivateKey = 0xB0B;

        _signer = vm.addr(_signerPrivateKey);
        _relayer = vm.addr(_relayerPrivateKey);

        JBFundingCycleData memory _data = JBFundingCycleData({
            duration: 0,
            weight: _WEIGHT,
            discountRate: 0,
            ballot: IJBFundingCycleBallot(address(0))
        });

        JBFundingCycleMetadata memory _metadata = JBFundingCycleMetadata({
            reservedRate: 0,
            redemptionRate: JBConstants.MAX_REDEMPTION_RATE,
            baseCurrency: uint32(uint160(JBTokens.ETH)),
            pausePay: false,
            pauseTokenCreditTransfers: false,
            allowMinting: true,
            allowTerminalMigration: false,
            allowSetTerminals: false,
            allowControllerMigration: false,
            allowSetController: false,
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
        _terminalConfigurations[0] =
            JBTerminalConfig({terminal: _terminal, accountingContextConfigs: _accountingContexts});

        // First project for fee collection
        _controller.launchProjectFor({
            owner: _projectOwner,
            projectMetadata: "myIPFSHash",
            fundingCycleConfigurations: _cycleConfig,
            terminalConfigurations: _terminalConfigurations,
            memo: ""
        });

        _projectId = _controller.launchProjectFor({
            owner: _projectOwner,
            projectMetadata: "myIPFSHash",
            fundingCycleConfigurations: _cycleConfig,
            terminalConfigurations: _terminalConfigurations,
            memo: ""
        });

        vm.stopPrank();
    }

    function testForwarderDeployed() public {
        // Check: forwarder deployed to address
        assertEq(_erc2771Forwarder.deployed(), true);
    }

    function testForwardedPay() public {
        // Setup: pay amounts, set balances
        uint256 _payAmount = 1 ether;
        vm.deal(_relayer, 1 ether);

        // Setup: meta tx data
        bytes memory _data = abi.encodeWithSelector(
            IJBPaymentTerminal.pay.selector,
            _projectId,
            JBTokens.ETH,
            _payAmount,
            _signer,
            0,  // minReturnedTokens
            "Take my money!",  // memo
            ""  // metadata, empty bytes
        );

        // Setup: forwarder request data
        ERC2771Forwarder.ForwardRequestData memory requestData = _forgeRequestData({
            value: _payAmount,
            nonce: 0,
            deadline: uint48(block.timestamp + 1),
            data: _data,
            target: address(_terminal)
        });

        // Send: "Meta Tx" (signed by _signer) from relayer to our trusted forwarder
        vm.prank(_relayer);
        _erc2771Forwarder.execute{value: _payAmount}(requestData);

        // Check: Ensure balance left the relayer (sponsor)
        assertEq(_relayer.balance, 0);

        // Check: Ensure terminal has ETH from meta tx
        assertEq(address(_terminal).balance, 1 ether);

        // Check: Ensure the beneficiary (signer) has a balance of tokens.
        uint256 _beneficiaryTokenBalance = PRBMathUD60x18.mul(_payAmount, _WEIGHT);
        assertEq(_tokenStore.balanceOf(_signer, _projectId), _beneficiaryTokenBalance);
    }
}
