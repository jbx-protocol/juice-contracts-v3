import { expect } from 'chai';
import { ethers } from 'hardhat';
import { deployMockContract } from '@ethereum-waffle/mock-contract';

import { setBalance, packFundingCycleMetadata } from '../helpers/utils';
import errors from '../helpers/errors.json';

import jbController from '../../artifacts/contracts/interfaces/IJBController.sol/IJBController.json';
import jbDirectory from '../../artifacts/contracts/interfaces/IJBDirectory.sol/IJBDirectory.json';
import JBETHPaymentTerminal from '../../artifacts/contracts/JBETHPaymentTerminal3_1.sol/JBETHPaymentTerminal3_1.json';
import jbPaymentTerminalStore from '../../artifacts/contracts/JBSingleTokenPaymentTerminalStore.sol/JBSingleTokenPaymentTerminalStore.json';
import jbFeeGauge from '../../artifacts/contracts/interfaces/IJBFeeGauge3_1.sol/IJBFeeGauge3_1.json';
import jbOperatoreStore from '../../artifacts/contracts/interfaces/IJBOperatorStore.sol/IJBOperatorStore.json';
import jbProjects from '../../artifacts/contracts/interfaces/IJBProjects.sol/IJBProjects.json';
import jbSplitsStore from '../../artifacts/contracts/interfaces/IJBSplitsStore.sol/IJBSplitsStore.json';
import jbPrices from '../../artifacts/contracts/interfaces/IJBPrices.sol/IJBPrices.json';
import jbRedemptionDelegate from '../../artifacts/contracts/interfaces/IJBRedemptionDelegate.sol/IJBRedemptionDelegate.json';

describe('JBPayoutRedemptionPaymentTerminal3_1_1::redeemTokensOf(...)', function () {
  const AMOUNT = 50000;
  const RECLAIM_AMOUNT = 40000;
  const MIN_RETURNED_AMOUNT = 30000;
  const FUNDING_CYCLE_NUM = 1;
  const MEMO = 'test memo';
  const ADJUSTED_MEMO = 'test test memo';
  const PROJECT_ID = 13;
  const WEIGHT = 1000;
  const METADATA = '0x69';
  const DECIMALS = 10;
  const DECIMALS_ETH = 18;
  const DEFAULT_FEE = 25000000; // 2.5%
  const FEE_DISCOUNT = 500000000; // 50%

  let CURRENCY_ETH;
  let MAX_FEE;
  let MAX_FEE_DISCOUNT;
  let ETH_ADDRESS;
  let token;

  before(async function () {
    let jbConstantsFactory = await ethers.getContractFactory('JBConstants');
    let jbTokenFactory = await ethers.getContractFactory('JBTokens');
    let jbConstants = await jbConstantsFactory.deploy();
    let jbToken = await jbTokenFactory.deploy();
    MAX_FEE = (await jbConstants.MAX_FEE()).toNumber();
    MAX_FEE_DISCOUNT = await jbConstants.MAX_FEE_DISCOUNT();
    ETH_ADDRESS = await jbToken.ETH();
  })
  async function setup() {
    const [deployer, beneficiary, holder, otherCaller, terminalOwner] = await ethers.getSigners();

    const blockNum = await ethers.provider.getBlockNumber();
    const block = await ethers.provider.getBlock(blockNum);
    const timestamp = block.timestamp;

    const [
      mockJbDirectory,
      mockJBPaymentTerminalStore,
      mockJbEthPaymentTerminal,
      mockJbOperatorStore,
      mockJbProjects,
      mockJbSplitsStore,
      mockJbPrices,
      mockJbRedemptionDelegate,
      mockJbRedemptionDelegate2,
      mockJbController,
      mockJbFeeGauge
    ] = await Promise.all([
      deployMockContract(deployer, jbDirectory.abi),
      deployMockContract(deployer, jbPaymentTerminalStore.abi),
      deployMockContract(deployer, JBETHPaymentTerminal.abi),
      deployMockContract(deployer, jbOperatoreStore.abi),
      deployMockContract(deployer, jbProjects.abi),
      deployMockContract(deployer, jbSplitsStore.abi),
      deployMockContract(deployer, jbPrices.abi),
      deployMockContract(deployer, jbRedemptionDelegate.abi),
      deployMockContract(deployer, jbRedemptionDelegate.abi),
      deployMockContract(deployer, jbController.abi),
      deployMockContract(deployer, jbFeeGauge.abi),
    ]);

    const jbCurrenciesFactory = await ethers.getContractFactory('JBCurrencies');
    const jbCurrencies = await jbCurrenciesFactory.deploy();
    CURRENCY_ETH = await jbCurrencies.ETH();

    const jbTerminalFactory = await ethers.getContractFactory(
      'contracts/JBETHPaymentTerminal3_1_1.sol:JBETHPaymentTerminal3_1_1',
      deployer,
    );

    const jbEthPaymentTerminal = await jbTerminalFactory
      .connect(deployer)
      .deploy(
        CURRENCY_ETH,
        mockJbOperatorStore.address,
        mockJbProjects.address,
        mockJbDirectory.address,
        mockJbSplitsStore.address,
        mockJbPrices.address,
        mockJBPaymentTerminalStore.address,
        terminalOwner.address,
      );

    token = await jbEthPaymentTerminal.token();

    /* Lib constants */

    let jbOperationsFactory = await ethers.getContractFactory('JBOperations');
    let jbOperations = await jbOperationsFactory.deploy();
    const REDEEM_PERMISSION_INDEX = await jbOperations.REDEEM();

    /* Common mocks */

    await mockJbOperatorStore.mock.hasPermission
      .withArgs(holder.address, holder.address, PROJECT_ID, REDEEM_PERMISSION_INDEX)
      .returns(true);

    const fundingCycle = {
      number: FUNDING_CYCLE_NUM,
      configuration: timestamp,
      basedOn: timestamp,
      start: timestamp,
      duration: 0,
      weight: WEIGHT,
      discountRate: 0,
      ballot: ethers.constants.AddressZero,
      metadata: 0,
    };

    return {
      beneficiary,
      holder,
      terminalOwner,
      jbEthPaymentTerminal,
      fundingCycle,
      mockJBPaymentTerminalStore,
      mockJbOperatorStore,
      mockJbRedemptionDelegate,
      mockJbEthPaymentTerminal,
      mockJbRedemptionDelegate2,
      mockJbController,
      mockJbDirectory,
      mockJbFeeGauge,
      otherCaller,
      timestamp,
    };
  }

  it('Should redeem tokens for overflow and emit event', async function () {
    const {
      beneficiary,
      fundingCycle,
      holder,
      jbEthPaymentTerminal,
      mockJBPaymentTerminalStore,
      mockJbController,
      mockJbDirectory,
      timestamp,
    } = await setup();

    await mockJbDirectory.mock.controllerOf.withArgs(PROJECT_ID).returns(mockJbController.address);
    await mockJbController.mock.burnTokensOf
      .withArgs(holder.address, PROJECT_ID, AMOUNT, /* memo */ '', /* preferClaimedTokens */ false)
      .returns();

    // Keep it simple and let 1 token exchange for 1 wei
    await mockJBPaymentTerminalStore.mock.recordRedemptionFor
      .withArgs(holder.address, PROJECT_ID, /* tokenCount */ AMOUNT, MEMO, METADATA)
      .returns(
        fundingCycle,
        /* reclaimAmount */ RECLAIM_AMOUNT,
        /* delegateAllocation */[],
        ADJUSTED_MEMO,
      );

    await setBalance(jbEthPaymentTerminal.address, RECLAIM_AMOUNT);

    const initialBeneficiaryBalance = await ethers.provider.getBalance(beneficiary.address);

    const tx = await jbEthPaymentTerminal
      .connect(holder)
      .redeemTokensOf(
        holder.address,
        PROJECT_ID,
        /* tokenCount */ AMOUNT,
        /* token */ ethers.constants.AddressZero,
        /* minReturnedTokens */ MIN_RETURNED_AMOUNT,
        beneficiary.address,
        MEMO,
        METADATA,
      );

    await expect(tx)
      .to.emit(jbEthPaymentTerminal, 'RedeemTokens(uint256,uint256,uint256,address,address,uint256,uint256,uint256,string,bytes,address)')
      .withArgs(
        /* _fundingCycle.configuration */ timestamp,
        /* _fundingCycle.number */ FUNDING_CYCLE_NUM,
        /* _projectId */ PROJECT_ID,
        /* _holder */ holder.address,
        /* _beneficiary */ beneficiary.address,
        /* _tokenCount */ AMOUNT,
        /* reclaimAmount */ RECLAIM_AMOUNT,
        /* fee */ 0,
        /* memo */ ADJUSTED_MEMO,
        /* metadata */ METADATA,
        /* msg.sender */ holder.address,
      );

    // Terminal should be out of ETH
    expect(await ethers.provider.getBalance(jbEthPaymentTerminal.address)).to.equal(0);

    // Beneficiary should have a larger balance
    expect(await ethers.provider.getBalance(beneficiary.address)).to.equal(
      initialBeneficiaryBalance.add(RECLAIM_AMOUNT),
    );
  });

  it('Should work if no burning necessary', async function () {
    const {
      beneficiary,
      fundingCycle,
      holder,
      jbEthPaymentTerminal,
      mockJBPaymentTerminalStore,
      timestamp,
    } = await setup();

    // Keep it simple and let 1 token exchange for 1 wei
    await mockJBPaymentTerminalStore.mock.recordRedemptionFor
      .withArgs(holder.address, PROJECT_ID, /* tokenCount */ 0, MEMO, METADATA)
      .returns(
        fundingCycle,
        /* reclaimAmount */ RECLAIM_AMOUNT,
        /* delegateAllocation */[],
        ADJUSTED_MEMO,
      );

    await setBalance(jbEthPaymentTerminal.address, RECLAIM_AMOUNT);

    const initialBeneficiaryBalance = await ethers.provider.getBalance(beneficiary.address);

    const tx = await jbEthPaymentTerminal
      .connect(holder)
      .redeemTokensOf(
        holder.address,
        PROJECT_ID,
        /* tokenCount */ 0,
        /* token */ ethers.constants.AddressZero,
        /* minReturnedTokens */ MIN_RETURNED_AMOUNT,
        beneficiary.address,
        MEMO,
        METADATA,
      );

    await expect(tx)
      .to.emit(jbEthPaymentTerminal, 'RedeemTokens(uint256,uint256,uint256,address,address,uint256,uint256,uint256,string,bytes,address)')
      .withArgs(
        /* _fundingCycle.configuration */ timestamp,
        /* _fundingCycle.number */ FUNDING_CYCLE_NUM,
        /* _projectId */ PROJECT_ID,
        /* _holder */ holder.address,
        /* _beneficiary */ beneficiary.address,
        /* _tokenCount */ 0,
        /* reclaimAmount */ RECLAIM_AMOUNT,
        /* fee */ 0,
        /* memo */ ADJUSTED_MEMO,
        /* metadata */ METADATA,
        /* msg.sender */ holder.address,
      );

    // Terminal should be out of ETH
    expect(await ethers.provider.getBalance(jbEthPaymentTerminal.address)).to.equal(0);

    // Beneficiary should have a larger balance
    expect(await ethers.provider.getBalance(beneficiary.address)).to.equal(
      initialBeneficiaryBalance.add(RECLAIM_AMOUNT),
    );
  });

  it('Should redeem tokens, call delegate fn, send appropriate amount and emit delegate event', async function () {
    const {
      beneficiary,
      fundingCycle,
      holder,
      jbEthPaymentTerminal,
      mockJBPaymentTerminalStore,
      mockJbRedemptionDelegate,
      mockJbDirectory,
      mockJbController,
      timestamp,
    } = await setup();

    const delegateAmount = RECLAIM_AMOUNT / 2;
    const redeemedAmount = RECLAIM_AMOUNT / 2;

    await mockJbDirectory.mock.controllerOf.withArgs(PROJECT_ID).returns(mockJbController.address);
    await mockJbController.mock.burnTokensOf
      .withArgs(holder.address, PROJECT_ID, AMOUNT, /* memo */ '', /* preferClaimedTokens */ false)
      .returns();

    await mockJBPaymentTerminalStore.mock.recordRedemptionFor
      .withArgs(holder.address, PROJECT_ID, /* tokenCount */ AMOUNT, MEMO, METADATA)
      .returns(
        fundingCycle,
        /* reclaimAmount */ redeemedAmount,
        /* delegateAllocations */[
          { delegate: mockJbRedemptionDelegate.address, amount: delegateAmount },
        ],
        ADJUSTED_MEMO,
      );

    let tokenAddress = await jbEthPaymentTerminal.token();
    await mockJbRedemptionDelegate.mock.didRedeem
      .withArgs({
        // JBDidRedeemData obj
        holder: holder.address,
        projectId: PROJECT_ID,
        currentFundingCycleConfiguration: timestamp,
        projectTokenCount: AMOUNT,
        reclaimedAmount: {
          token: tokenAddress,
          value: redeemedAmount,
          decimals: DECIMALS_ETH,
          currency: CURRENCY_ETH,
        },
        forwardedAmount: {
          token: tokenAddress,
          value: delegateAmount,
          decimals: DECIMALS_ETH,
          currency: CURRENCY_ETH,
        },
        beneficiary: beneficiary.address,
        memo: ADJUSTED_MEMO,
        metadata: METADATA,
      })
      .returns();

    await setBalance(jbEthPaymentTerminal.address, RECLAIM_AMOUNT); // = redeemed + delegate amount

    const initialBeneficiaryBalance = await ethers.provider.getBalance(beneficiary.address);

    const initialDelegateBalance = await ethers.provider.getBalance(
      mockJbRedemptionDelegate.address,
    );

    const tx = await jbEthPaymentTerminal
      .connect(holder)
      .redeemTokensOf(
        holder.address,
        PROJECT_ID,
        /* tokenCount */ AMOUNT,
        /* token */ ethers.constants.AddressZero,
        /* minReturnedTokens */ redeemedAmount,
        beneficiary.address,
        MEMO,
        METADATA,
      );

    await expect(tx).to.emit(jbEthPaymentTerminal, 'DelegateDidRedeem(address,(address,uint256,uint256,uint256,(address,uint256,uint256,uint256),(address,uint256,uint256,uint256),address,string,bytes),uint256,uint256,address)');
    // Uncaught AssertionError: expected [ Array(4) ] to equal [ Array(4) ]

    // .withArgs(
    //   mockJbRedemptionDelegate.address,
    //   [
    //     // JBDidRedeemData obj
    //     holder.address,
    //     PROJECT_ID,
    //     AMOUNT,
    //       [
    //         tokenAddress,
    //         ethers.BigNumber.from(RECLAIM_AMOUNT),
    //         ethers.BigNumber.from(DECIMALS_ETH),
    //         CURRENCY_ETH
    //       ],
    //     beneficiary.address,
    //     ADJUSTED_MEMO,
    //     METADATA,
    //   ],
    //   /* msg.sender */ holder.address,
    // );

    await expect(tx)
      .to.emit(jbEthPaymentTerminal, 'RedeemTokens(uint256,uint256,uint256,address,address,uint256,uint256,uint256,string,bytes,address)')
      .withArgs(
        /* _fundingCycle.configuration */ timestamp,
        /* _fundingCycle.number */ FUNDING_CYCLE_NUM,
        /* _projectId */ PROJECT_ID,
        /* _holder */ holder.address,
        /* _beneficiary */ beneficiary.address,
        /* _tokenCount */ AMOUNT,
        /* reclaimAmount */ redeemedAmount,
        /* fee */ 0,
        /* memo */ ADJUSTED_MEMO,
        /* metadata */ METADATA,
        /* msg.sender */ holder.address,
      );

    // Terminal should be out of ETH
    expect(await ethers.provider.getBalance(jbEthPaymentTerminal.address)).to.equal(0);

    // Beneficiary should have a larger balance
    expect(await ethers.provider.getBalance(beneficiary.address)).to.equal(
      initialBeneficiaryBalance.add(redeemedAmount),
    );

    // Delegate should have a larger balance
    expect(await ethers.provider.getBalance(mockJbRedemptionDelegate.address)).to.equal(
      initialDelegateBalance.add(delegateAmount),
    );
  });

  it('Should redeem tokens, call multiple delegate and send the appropriate amount to them', async function () {
    const {
      beneficiary,
      fundingCycle,
      holder,
      jbEthPaymentTerminal,
      mockJBPaymentTerminalStore,
      mockJbRedemptionDelegate,
      mockJbRedemptionDelegate2,
      mockJbDirectory,
      mockJbController,
      timestamp,
    } = await setup();

    const delegate1Amount = RECLAIM_AMOUNT / 2;
    const delegate2Amount = RECLAIM_AMOUNT / 4;
    const redeemedAmount = RECLAIM_AMOUNT - delegate1Amount - delegate2Amount;

    await mockJbDirectory.mock.controllerOf.withArgs(PROJECT_ID).returns(mockJbController.address);
    await mockJbController.mock.burnTokensOf
      .withArgs(holder.address, PROJECT_ID, AMOUNT, /* memo */ '', /* preferClaimedTokens */ false)
      .returns();

    // Keep it simple and let 1 token exchange for 1 wei
    await mockJBPaymentTerminalStore.mock.recordRedemptionFor
      .withArgs(holder.address, PROJECT_ID, /* tokenCount */ AMOUNT, MEMO, METADATA)
      .returns(
        fundingCycle,
        /* reclaimAmount */ redeemedAmount,
        /* delegate */[
          { delegate: mockJbRedemptionDelegate.address, amount: delegate1Amount },
          { delegate: mockJbRedemptionDelegate2.address, amount: delegate2Amount },
        ],
        ADJUSTED_MEMO,
      );

    let tokenAddress = await jbEthPaymentTerminal.token();
    await mockJbRedemptionDelegate.mock.didRedeem
      .withArgs({
        // JBDidRedeemData obj
        holder: holder.address,
        projectId: PROJECT_ID,
        currentFundingCycleConfiguration: timestamp,
        projectTokenCount: AMOUNT,
        reclaimedAmount: {
          token: tokenAddress,
          value: redeemedAmount,
          decimals: DECIMALS_ETH,
          currency: CURRENCY_ETH,
        },
        forwardedAmount: {
          token: tokenAddress,
          value: delegate1Amount,
          decimals: DECIMALS_ETH,
          currency: CURRENCY_ETH,
        },
        beneficiary: beneficiary.address,
        memo: ADJUSTED_MEMO,
        metadata: METADATA,
      })
      .returns();

    await mockJbRedemptionDelegate2.mock.didRedeem
      .withArgs({
        // JBDidRedeemData obj
        holder: holder.address,
        projectId: PROJECT_ID,
        currentFundingCycleConfiguration: timestamp,
        projectTokenCount: AMOUNT,
        reclaimedAmount: {
          token: tokenAddress,
          value: redeemedAmount,
          decimals: DECIMALS_ETH,
          currency: CURRENCY_ETH,
        },
        forwardedAmount: {
          token: tokenAddress,
          value: delegate2Amount,
          decimals: DECIMALS_ETH,
          currency: CURRENCY_ETH,
        },
        beneficiary: beneficiary.address,
        memo: ADJUSTED_MEMO,
        metadata: METADATA,
      })
      .returns();

    await setBalance(jbEthPaymentTerminal.address, RECLAIM_AMOUNT);

    const initialBeneficiaryBalance = await ethers.provider.getBalance(beneficiary.address);
    const initialDelegate1Balance = await ethers.provider.getBalance(
      mockJbRedemptionDelegate.address,
    );
    const initialDelegate2Balance = await ethers.provider.getBalance(
      mockJbRedemptionDelegate2.address,
    );

    const tx = await jbEthPaymentTerminal
      .connect(holder)
      .redeemTokensOf(
        holder.address,
        PROJECT_ID,
        /* tokenCount */ AMOUNT,
        /* token */ ethers.constants.AddressZero,
        /* minReturnedTokens */ redeemedAmount,
        beneficiary.address,
        MEMO,
        METADATA,
      );

    // Uncaught AssertionError: expected [ Array(4) ] to equal [ Array(4) ]
    await expect(tx).to.emit(jbEthPaymentTerminal, 'DelegateDidRedeem(address,(address,uint256,uint256,uint256,(address,uint256,uint256,uint256),(address,uint256,uint256,uint256),address,string,bytes),uint256,uint256,address)');
    // .withArgs(
    //   mockJbRedemptionDelegate.address,
    //   [
    //     // JBDidRedeemData obj
    //     holder.address,
    //     PROJECT_ID,
    //     AMOUNT,
    //     [
    //       tokenAddress,
    //       ethers.BigNumber.from(RECLAIM_AMOUNT),
    //       ethers.BigNumber.from(DECIMALS_ETH),
    //       CURRENCY_ETH,
    //     ],
    //     beneficiary.address,
    //     ADJUSTED_MEMO,
    //     METADATA,
    //   ],
    //   /* msg.sender */ holder.address,
    // );

    await expect(tx)
      .to.emit(jbEthPaymentTerminal, 'RedeemTokens(uint256,uint256,uint256,address,address,uint256,uint256,uint256,string,bytes,address)')
      .withArgs(
        /* _fundingCycle.configuration */ timestamp,
        /* _fundingCycle.number */ FUNDING_CYCLE_NUM,
        /* _projectId */ PROJECT_ID,
        /* _holder */ holder.address,
        /* _beneficiary */ beneficiary.address,
        /* _tokenCount */ AMOUNT,
        /* reclaimAmount */ redeemedAmount,
        /* fee */ 0,
        /* memo */ ADJUSTED_MEMO,
        /* metadata */ METADATA,
        /* msg.sender */ holder.address,
      );

    // Terminal should be out of ETH
    expect(await ethers.provider.getBalance(jbEthPaymentTerminal.address)).to.equal(0);

    // Beneficiary should have a larger balance
    expect(await ethers.provider.getBalance(beneficiary.address)).to.equal(
      initialBeneficiaryBalance.add(redeemedAmount),
    );

    // Delegate1 should have a larger balance
    expect(await ethers.provider.getBalance(mockJbRedemptionDelegate.address)).to.equal(
      initialDelegate1Balance.add(delegate1Amount),
    );

    // Delegate2 should have a larger balance
    expect(await ethers.provider.getBalance(mockJbRedemptionDelegate2.address)).to.equal(
      initialDelegate2Balance.add(delegate2Amount),
    );
  });

  it('Should redeem tokens, call multiple delegate and send the appropriate amount to them, with a sub-100% redemption rate that incurrs fees', async function () {
    const {
      beneficiary,
      fundingCycle,
      holder,
      jbEthPaymentTerminal,
      mockJbEthPaymentTerminal,
      mockJBPaymentTerminalStore,
      mockJbRedemptionDelegate,
      mockJbRedemptionDelegate2,
      mockJbDirectory,
      mockJbController,
      timestamp,
    } = await setup();

    fundingCycle.metadata = packFundingCycleMetadata({
      redemptionRate: 9000, // 90% redemption rate
    });

    const delegate1Amount = RECLAIM_AMOUNT / 2;
    const delegate2Amount = RECLAIM_AMOUNT / 4;
    const redeemedAmount = RECLAIM_AMOUNT - delegate1Amount - delegate2Amount;

    let DELEGATE_1_FEE =
      delegate1Amount - Math.floor((delegate1Amount * MAX_FEE) / (DEFAULT_FEE + MAX_FEE));
    let DELEGATE_2_FEE =
      delegate2Amount - Math.floor((delegate2Amount * MAX_FEE) / (DEFAULT_FEE + MAX_FEE));
    let REDEEM_FEE =
      redeemedAmount - Math.floor((redeemedAmount * MAX_FEE) / (DEFAULT_FEE + MAX_FEE));

    await mockJbDirectory.mock.controllerOf.withArgs(PROJECT_ID).returns(mockJbController.address);
    await mockJbController.mock.burnTokensOf
      .withArgs(holder.address, PROJECT_ID, AMOUNT, /* memo */ '', /* preferClaimedTokens */ false)
      .returns();

    // Keep it simple and let 1 token exchange for 1 wei
    await mockJBPaymentTerminalStore.mock.recordRedemptionFor
      .withArgs(holder.address, PROJECT_ID, /* tokenCount */ AMOUNT, MEMO, METADATA)
      .returns(
        fundingCycle,
        /* reclaimAmount */ redeemedAmount,
        /* delegate */[
          { delegate: mockJbRedemptionDelegate.address, amount: delegate1Amount },
          { delegate: mockJbRedemptionDelegate2.address, amount: delegate2Amount },
        ],
        ADJUSTED_MEMO,
      );

    await mockJBPaymentTerminalStore.mock.recordAddedBalanceFor.returns();

    let tokenAddress = await jbEthPaymentTerminal.token();
    await mockJbRedemptionDelegate.mock.didRedeem
      .withArgs({
        // JBDidRedeemData obj
        holder: holder.address,
        projectId: PROJECT_ID,
        currentFundingCycleConfiguration: timestamp,
        projectTokenCount: AMOUNT,
        reclaimedAmount: {
          token: tokenAddress,
          value: redeemedAmount,
          decimals: DECIMALS_ETH,
          currency: CURRENCY_ETH,
        },
        forwardedAmount: {
          token: tokenAddress,
          value: delegate1Amount - DELEGATE_1_FEE,
          decimals: DECIMALS_ETH,
          currency: CURRENCY_ETH,
        },
        beneficiary: beneficiary.address,
        memo: ADJUSTED_MEMO,
        metadata: METADATA,
      })
      .returns();

    await mockJbRedemptionDelegate2.mock.didRedeem
      .withArgs({
        // JBDidRedeemData obj
        holder: holder.address,
        projectId: PROJECT_ID,
        currentFundingCycleConfiguration: timestamp,
        projectTokenCount: AMOUNT,
        reclaimedAmount: {
          token: tokenAddress,
          value: redeemedAmount,
          decimals: DECIMALS_ETH,
          currency: CURRENCY_ETH,
        },
        forwardedAmount: {
          token: tokenAddress,
          value: delegate2Amount - DELEGATE_2_FEE,
          decimals: DECIMALS_ETH,
          currency: CURRENCY_ETH,
        },
        beneficiary: beneficiary.address,
        memo: ADJUSTED_MEMO,
        metadata: METADATA,
      })
      .returns();

    await setBalance(jbEthPaymentTerminal.address, RECLAIM_AMOUNT);

    const initialBeneficiaryBalance = await ethers.provider.getBalance(beneficiary.address);
    const initialDelegate1Balance = await ethers.provider.getBalance(
      mockJbRedemptionDelegate.address,
    );
    const initialDelegate2Balance = await ethers.provider.getBalance(
      mockJbRedemptionDelegate2.address,
    );

    // Used with hardcoded one to get JBDao terminal
    await mockJbDirectory.mock.primaryTerminalOf
      .withArgs(1, ETH_ADDRESS)
      .returns(mockJbEthPaymentTerminal.address);

    await mockJbEthPaymentTerminal.mock.pay
      .withArgs(
        1, //JBX Dao
        REDEEM_FEE + DELEGATE_1_FEE + DELEGATE_2_FEE,
        ETH_ADDRESS,
        beneficiary.address,
        0,
        false,
        '',
        ethers.utils.hexZeroPad(ethers.utils.hexlify(PROJECT_ID), 32),
      )
      .returns(0);

    const tx = await jbEthPaymentTerminal
      .connect(holder)
      .redeemTokensOf(
        holder.address,
        PROJECT_ID,
        /* tokenCount */ AMOUNT,
        /* token */ ethers.constants.AddressZero,
        /* minReturnedTokens */ redeemedAmount,
        beneficiary.address,
        MEMO,
        METADATA,
      );

    // Uncaught AssertionError: expected [ Array(4) ] to equal [ Array(4) ]
    await expect(tx).to.emit(jbEthPaymentTerminal, 'DelegateDidRedeem(address,(address,uint256,uint256,uint256,(address,uint256,uint256,uint256),(address,uint256,uint256,uint256),address,string,bytes),uint256,uint256,address)');
    // .withArgs(
    //   mockJbRedemptionDelegate.address,
    //   [
    //     // JBDidRedeemData obj
    //     holder.address,
    //     PROJECT_ID,
    //     AMOUNT,
    //     [
    //       tokenAddress,
    //       ethers.BigNumber.from(RECLAIM_AMOUNT),
    //       ethers.BigNumber.from(DECIMALS_ETH),
    //       CURRENCY_ETH,
    //     ],
    //     beneficiary.address,
    //     ADJUSTED_MEMO,
    //     METADATA,
    //   ],
    //   /* msg.sender */ holder.address,
    // );

    await expect(tx)
      .to.emit(jbEthPaymentTerminal, 'RedeemTokens(uint256,uint256,uint256,address,address,uint256,uint256,uint256,string,bytes,address)')
      .withArgs(
        /* _fundingCycle.configuration */ timestamp,
        /* _fundingCycle.number */ FUNDING_CYCLE_NUM,
        /* _projectId */ PROJECT_ID,
        /* _holder */ holder.address,
        /* _beneficiary */ beneficiary.address,
        /* _tokenCount */ AMOUNT,
        /* reclaimAmount */ redeemedAmount - REDEEM_FEE,
        /* fee */ REDEEM_FEE,
        /* memo */ ADJUSTED_MEMO,
        /* metadata */ METADATA,
        /* msg.sender */ holder.address,
      );

    // Terminal should be out of ETH
    expect(await ethers.provider.getBalance(jbEthPaymentTerminal.address)).to.equal(0);

    // Beneficiary should have a larger balance
    expect(await ethers.provider.getBalance(beneficiary.address)).to.equal(
      initialBeneficiaryBalance.add(redeemedAmount - REDEEM_FEE),
    );

    // Delegate1 should have a larger balance
    expect(await ethers.provider.getBalance(mockJbRedemptionDelegate.address)).to.equal(
      initialDelegate1Balance.add(delegate1Amount - DELEGATE_1_FEE),
    );

    // Delegate2 should have a larger balance
    expect(await ethers.provider.getBalance(mockJbRedemptionDelegate2.address)).to.equal(
      initialDelegate2Balance.add(delegate2Amount - DELEGATE_2_FEE),
    );
  });

  it('Should redeem tokens, call multiple delegate and send the appropriate amount to them, with a sub-100% redemption rate that incurrs fees with gauge', async function () {
    const {
      beneficiary,
      fundingCycle,
      holder,
      terminalOwner,
      jbEthPaymentTerminal,
      mockJbEthPaymentTerminal,
      mockJBPaymentTerminalStore,
      mockJbRedemptionDelegate,
      mockJbRedemptionDelegate2,
      mockJbDirectory,
      mockJbController,
      mockJbFeeGauge,
      timestamp,
    } = await setup();

    fundingCycle.metadata = packFundingCycleMetadata({
      redemptionRate: 9000, // 90% redemption rate
    });

    const delegate1Amount = RECLAIM_AMOUNT / 2;
    const delegate2Amount = RECLAIM_AMOUNT / 4;
    const redeemedAmount = RECLAIM_AMOUNT - delegate1Amount - delegate2Amount;

    const DISCOUNTED_FEE =
      DEFAULT_FEE - Math.floor((DEFAULT_FEE * FEE_DISCOUNT) / MAX_FEE_DISCOUNT);

    let DELEGATE_1_FEE =
      delegate1Amount - Math.floor((delegate1Amount * MAX_FEE) / (DISCOUNTED_FEE + MAX_FEE));
    let DELEGATE_2_FEE =
      delegate2Amount - Math.floor((delegate2Amount * MAX_FEE) / (DISCOUNTED_FEE + MAX_FEE));
    let REDEEM_FEE =
      redeemedAmount - Math.floor((redeemedAmount * MAX_FEE) / (DISCOUNTED_FEE + MAX_FEE));

    await jbEthPaymentTerminal.connect(terminalOwner).setFeeGauge(mockJbFeeGauge.address);
    await mockJbFeeGauge.mock.currentDiscountFor.withArgs(PROJECT_ID, 2).returns(FEE_DISCOUNT);

    await mockJbDirectory.mock.controllerOf.withArgs(PROJECT_ID).returns(mockJbController.address);
    await mockJbController.mock.burnTokensOf
      .withArgs(holder.address, PROJECT_ID, AMOUNT, /* memo */ '', /* preferClaimedTokens */ false)
      .returns();

    // Keep it simple and let 1 token exchange for 1 wei
    await mockJBPaymentTerminalStore.mock.recordRedemptionFor
      .withArgs(holder.address, PROJECT_ID, /* tokenCount */ AMOUNT, MEMO, METADATA)
      .returns(
        fundingCycle,
        /* reclaimAmount */ redeemedAmount,
        /* delegate */[
          { delegate: mockJbRedemptionDelegate.address, amount: delegate1Amount },
          { delegate: mockJbRedemptionDelegate2.address, amount: delegate2Amount },
        ],
        ADJUSTED_MEMO,
      );

    await mockJBPaymentTerminalStore.mock.recordAddedBalanceFor.returns();

    let tokenAddress = await jbEthPaymentTerminal.token();
    await mockJbRedemptionDelegate.mock.didRedeem
      .withArgs({
        // JBDidRedeemData obj
        holder: holder.address,
        projectId: PROJECT_ID,
        currentFundingCycleConfiguration: timestamp,
        projectTokenCount: AMOUNT,
        reclaimedAmount: {
          token: tokenAddress,
          value: redeemedAmount,
          decimals: DECIMALS_ETH,
          currency: CURRENCY_ETH,
        },
        forwardedAmount: {
          token: tokenAddress,
          value: delegate1Amount - DELEGATE_1_FEE,
          decimals: DECIMALS_ETH,
          currency: CURRENCY_ETH,
        },
        beneficiary: beneficiary.address,
        memo: ADJUSTED_MEMO,
        metadata: METADATA,
      })
      .returns();

    await mockJbRedemptionDelegate2.mock.didRedeem
      .withArgs({
        // JBDidRedeemData obj
        holder: holder.address,
        projectId: PROJECT_ID,
        currentFundingCycleConfiguration: timestamp,
        projectTokenCount: AMOUNT,
        reclaimedAmount: {
          token: tokenAddress,
          value: redeemedAmount,
          decimals: DECIMALS_ETH,
          currency: CURRENCY_ETH,
        },
        forwardedAmount: {
          token: tokenAddress,
          value: delegate2Amount - DELEGATE_2_FEE,
          decimals: DECIMALS_ETH,
          currency: CURRENCY_ETH,
        },
        beneficiary: beneficiary.address,
        memo: ADJUSTED_MEMO,
        metadata: METADATA,
      })
      .returns();

    await setBalance(jbEthPaymentTerminal.address, RECLAIM_AMOUNT);

    const initialBeneficiaryBalance = await ethers.provider.getBalance(beneficiary.address);
    const initialDelegate1Balance = await ethers.provider.getBalance(
      mockJbRedemptionDelegate.address,
    );
    const initialDelegate2Balance = await ethers.provider.getBalance(
      mockJbRedemptionDelegate2.address,
    );

    // Used with hardcoded one to get JBDao terminal
    await mockJbDirectory.mock.primaryTerminalOf
      .withArgs(1, ETH_ADDRESS)
      .returns(mockJbEthPaymentTerminal.address);

    const tx = await jbEthPaymentTerminal
      .connect(holder)
      .redeemTokensOf(
        holder.address,
        PROJECT_ID,
        /* tokenCount */ AMOUNT,
        /* token */ ethers.constants.AddressZero,
        /* minReturnedTokens */ redeemedAmount,
        beneficiary.address,
        MEMO,
        METADATA,
      );

    // Uncaught AssertionError: expected [ Array(4) ] to equal [ Array(4) ]
    await expect(tx).to.emit(jbEthPaymentTerminal, 'DelegateDidRedeem(address,(address,uint256,uint256,uint256,(address,uint256,uint256,uint256),(address,uint256,uint256,uint256),address,string,bytes),uint256,uint256,address)');
    // .withArgs(
    //   mockJbRedemptionDelegate.address,
    //   [
    //     // JBDidRedeemData obj
    //     holder.address,
    //     PROJECT_ID,
    //     AMOUNT,
    //     [
    //       tokenAddress,
    //       ethers.BigNumber.from(RECLAIM_AMOUNT),
    //       ethers.BigNumber.from(DECIMALS_ETH),
    //       CURRENCY_ETH,
    //     ],
    //     beneficiary.address,
    //     ADJUSTED_MEMO,
    //     METADATA,
    //   ],
    //   /* msg.sender */ holder.address,
    // );

    await expect(tx)
      .to.emit(jbEthPaymentTerminal, 'RedeemTokens(uint256,uint256,uint256,address,address,uint256,uint256,uint256,string,bytes,address)')
      .withArgs(
        /* _fundingCycle.configuration */ timestamp,
        /* _fundingCycle.number */ FUNDING_CYCLE_NUM,
        /* _projectId */ PROJECT_ID,
        /* _holder */ holder.address,
        /* _beneficiary */ beneficiary.address,
        /* _tokenCount */ AMOUNT,
        /* reclaimAmount */ redeemedAmount - REDEEM_FEE,
        /* fee */ REDEEM_FEE,
        /* memo */ ADJUSTED_MEMO,
        /* metadata */ METADATA,
        /* msg.sender */ holder.address,
      );

    // Terminal should be out of ETH
    expect(await ethers.provider.getBalance(jbEthPaymentTerminal.address)).to.equal(REDEEM_FEE + DELEGATE_1_FEE + DELEGATE_2_FEE);

    // Beneficiary should have a larger balance
    expect(await ethers.provider.getBalance(beneficiary.address)).to.equal(
      initialBeneficiaryBalance.add(redeemedAmount - REDEEM_FEE),
    );

    // Delegate1 should have a larger balance
    expect(await ethers.provider.getBalance(mockJbRedemptionDelegate.address)).to.equal(
      initialDelegate1Balance.add(delegate1Amount - DELEGATE_1_FEE),
    );

    // Delegate2 should have a larger balance
    expect(await ethers.provider.getBalance(mockJbRedemptionDelegate2.address)).to.equal(
      initialDelegate2Balance.add(delegate2Amount - DELEGATE_2_FEE),
    );
  });

  it('Should redeem tokens, call multiple delegate and send the appropriate amount to them, with a sub-100% redemption rate that would incurrs fees if the beneficiary wasnt feeless', async function () {
    const {
      beneficiary,
      fundingCycle,
      terminalOwner,
      holder,
      jbEthPaymentTerminal,
      mockJBPaymentTerminalStore,
      mockJbRedemptionDelegate,
      mockJbRedemptionDelegate2,
      mockJbDirectory,
      mockJbController,
      timestamp,
    } = await setup();

    fundingCycle.metadata = packFundingCycleMetadata({
      redemptionRate: 9000, // 90% redemption rate
    });

    const delegate1Amount = RECLAIM_AMOUNT / 2;
    const delegate2Amount = RECLAIM_AMOUNT / 4;
    const redeemedAmount = RECLAIM_AMOUNT - delegate1Amount - delegate2Amount;

    await mockJbDirectory.mock.controllerOf.withArgs(PROJECT_ID).returns(mockJbController.address);
    await mockJbController.mock.burnTokensOf
      .withArgs(holder.address, PROJECT_ID, AMOUNT, /* memo */ '', /* preferClaimedTokens */ false)
      .returns();

    // Keep it simple and let 1 token exchange for 1 wei
    await mockJBPaymentTerminalStore.mock.recordRedemptionFor
      .withArgs(holder.address, PROJECT_ID, /* tokenCount */ AMOUNT, MEMO, METADATA)
      .returns(
        fundingCycle,
        /* reclaimAmount */ redeemedAmount,
        /* delegate */[
          { delegate: mockJbRedemptionDelegate.address, amount: delegate1Amount },
          { delegate: mockJbRedemptionDelegate2.address, amount: delegate2Amount },
        ],
        ADJUSTED_MEMO,
      );

    // Used with hardcoded one to get JBDao terminal
    await mockJbDirectory.mock.primaryTerminalOf
      .withArgs(1, ETH_ADDRESS)
      .returns(jbEthPaymentTerminal.address);

    await mockJBPaymentTerminalStore.mock.recordAddedBalanceFor.returns();

    let tokenAddress = await jbEthPaymentTerminal.token();
    await mockJbRedemptionDelegate.mock.didRedeem
      .withArgs({
        // JBDidRedeemData obj
        holder: holder.address,
        projectId: PROJECT_ID,
        currentFundingCycleConfiguration: timestamp,
        projectTokenCount: AMOUNT,
        reclaimedAmount: {
          token: tokenAddress,
          value: redeemedAmount,
          decimals: DECIMALS_ETH,
          currency: CURRENCY_ETH,
        },
        forwardedAmount: {
          token: tokenAddress,
          value: delegate1Amount,
          decimals: DECIMALS_ETH,
          currency: CURRENCY_ETH,
        },
        beneficiary: beneficiary.address,
        memo: ADJUSTED_MEMO,
        metadata: METADATA,
      })
      .returns();

    await mockJbRedemptionDelegate2.mock.didRedeem
      .withArgs({
        // JBDidRedeemData obj
        holder: holder.address,
        projectId: PROJECT_ID,
        currentFundingCycleConfiguration: timestamp,
        projectTokenCount: AMOUNT,
        reclaimedAmount: {
          token: tokenAddress,
          value: redeemedAmount,
          decimals: DECIMALS_ETH,
          currency: CURRENCY_ETH,
        },
        forwardedAmount: {
          token: tokenAddress,
          value: delegate2Amount,
          decimals: DECIMALS_ETH,
          currency: CURRENCY_ETH,
        },
        beneficiary: beneficiary.address,
        memo: ADJUSTED_MEMO,
        metadata: METADATA,
      })
      .returns();

    await setBalance(jbEthPaymentTerminal.address, RECLAIM_AMOUNT);

    const initialBeneficiaryBalance = await ethers.provider.getBalance(beneficiary.address);
    const initialDelegate1Balance = await ethers.provider.getBalance(
      mockJbRedemptionDelegate.address,
    );
    const initialDelegate2Balance = await ethers.provider.getBalance(
      mockJbRedemptionDelegate2.address,
    );

    await jbEthPaymentTerminal
      .connect(terminalOwner)
      .setFeelessAddress(beneficiary.address, true);

    const tx = await jbEthPaymentTerminal
      .connect(holder)
      .redeemTokensOf(
        holder.address,
        PROJECT_ID,
        /* tokenCount */ AMOUNT,
        /* token */ ethers.constants.AddressZero,
        /* minReturnedTokens */ redeemedAmount,
        beneficiary.address,
        MEMO,
        METADATA,
      );

    // Uncaught AssertionError: expected [ Array(4) ] to equal [ Array(4) ]
    await expect(tx).to.emit(jbEthPaymentTerminal, 'DelegateDidRedeem(address,(address,uint256,uint256,uint256,(address,uint256,uint256,uint256),(address,uint256,uint256,uint256),address,string,bytes),uint256,uint256,address)');
    // .withArgs(
    //   mockJbRedemptionDelegate.address,
    //   [
    //     // JBDidRedeemData obj
    //     holder.address,
    //     PROJECT_ID,
    //     AMOUNT,
    //     [
    //       tokenAddress,
    //       ethers.BigNumber.from(RECLAIM_AMOUNT),
    //       ethers.BigNumber.from(DECIMALS_ETH),
    //       CURRENCY_ETH,
    //     ],
    //     beneficiary.address,
    //     ADJUSTED_MEMO,
    //     METADATA,
    //   ],
    //   /* msg.sender */ holder.address,
    // );

    await expect(tx)
      .to.emit(jbEthPaymentTerminal, 'RedeemTokens(uint256,uint256,uint256,address,address,uint256,uint256,uint256,string,bytes,address)')
      .withArgs(
        /* _fundingCycle.configuration */ timestamp,
        /* _fundingCycle.number */ FUNDING_CYCLE_NUM,
        /* _projectId */ PROJECT_ID,
        /* _holder */ holder.address,
        /* _beneficiary */ beneficiary.address,
        /* _tokenCount */ AMOUNT,
        /* reclaimAmount */ redeemedAmount,
        /* fee */ 0,
        /* memo */ ADJUSTED_MEMO,
        /* metadata */ METADATA,
        /* msg.sender */ holder.address,
      );

    // Terminal should be out of ETH
    expect(await ethers.provider.getBalance(jbEthPaymentTerminal.address)).to.equal(0);

    // Beneficiary should have a larger balance
    expect(await ethers.provider.getBalance(beneficiary.address)).to.equal(
      initialBeneficiaryBalance.add(redeemedAmount),
    );

    // Delegate1 should have a larger balance
    expect(await ethers.provider.getBalance(mockJbRedemptionDelegate.address)).to.equal(
      initialDelegate1Balance.add(delegate1Amount),
    );

    // Delegate2 should have a larger balance
    expect(await ethers.provider.getBalance(mockJbRedemptionDelegate2.address)).to.equal(
      initialDelegate2Balance.add(delegate2Amount),
    );
  });

  it('Should redeem tokens, call multiple delegate and send the appropriate amount to them, with a sub-100% redemption rate that would incurrs fees if the fee was non-zero', async function () {
    const {
      beneficiary,
      fundingCycle,
      terminalOwner,
      holder,
      jbEthPaymentTerminal,
      mockJBPaymentTerminalStore,
      mockJbRedemptionDelegate,
      mockJbRedemptionDelegate2,
      mockJbDirectory,
      mockJbController,
      timestamp,
    } = await setup();

    fundingCycle.metadata = packFundingCycleMetadata({
      redemptionRate: 9000, // 90% redemption rate
    });

    const delegate1Amount = RECLAIM_AMOUNT / 2;
    const delegate2Amount = RECLAIM_AMOUNT / 4;
    const redeemedAmount = RECLAIM_AMOUNT - delegate1Amount - delegate2Amount;

    await mockJbDirectory.mock.controllerOf.withArgs(PROJECT_ID).returns(mockJbController.address);
    await mockJbController.mock.burnTokensOf
      .withArgs(holder.address, PROJECT_ID, AMOUNT, /* memo */ '', /* preferClaimedTokens */ false)
      .returns();

    // Keep it simple and let 1 token exchange for 1 wei
    await mockJBPaymentTerminalStore.mock.recordRedemptionFor
      .withArgs(holder.address, PROJECT_ID, /* tokenCount */ AMOUNT, MEMO, METADATA)
      .returns(
        fundingCycle,
        /* reclaimAmount */ redeemedAmount,
        /* delegate */[
          { delegate: mockJbRedemptionDelegate.address, amount: delegate1Amount },
          { delegate: mockJbRedemptionDelegate2.address, amount: delegate2Amount },
        ],
        ADJUSTED_MEMO,
      );

    // Used with hardcoded one to get JBDao terminal
    await mockJbDirectory.mock.primaryTerminalOf
      .withArgs(1, ETH_ADDRESS)
      .returns(jbEthPaymentTerminal.address);

    await mockJBPaymentTerminalStore.mock.recordAddedBalanceFor.returns();

    let tokenAddress = await jbEthPaymentTerminal.token();
    await mockJbRedemptionDelegate.mock.didRedeem
      .withArgs({
        // JBDidRedeemData obj
        holder: holder.address,
        projectId: PROJECT_ID,
        currentFundingCycleConfiguration: timestamp,
        projectTokenCount: AMOUNT,
        reclaimedAmount: {
          token: tokenAddress,
          value: redeemedAmount,
          decimals: DECIMALS_ETH,
          currency: CURRENCY_ETH,
        },
        forwardedAmount: {
          token: tokenAddress,
          value: delegate1Amount,
          decimals: DECIMALS_ETH,
          currency: CURRENCY_ETH,
        },
        beneficiary: beneficiary.address,
        memo: ADJUSTED_MEMO,
        metadata: METADATA,
      })
      .returns();

    await mockJbRedemptionDelegate2.mock.didRedeem
      .withArgs({
        // JBDidRedeemData obj
        holder: holder.address,
        projectId: PROJECT_ID,
        currentFundingCycleConfiguration: timestamp,
        projectTokenCount: AMOUNT,
        reclaimedAmount: {
          token: tokenAddress,
          value: redeemedAmount,
          decimals: DECIMALS_ETH,
          currency: CURRENCY_ETH,
        },
        forwardedAmount: {
          token: tokenAddress,
          value: delegate2Amount,
          decimals: DECIMALS_ETH,
          currency: CURRENCY_ETH,
        },
        beneficiary: beneficiary.address,
        memo: ADJUSTED_MEMO,
        metadata: METADATA,
      })
      .returns();

    await setBalance(jbEthPaymentTerminal.address, RECLAIM_AMOUNT);

    const initialBeneficiaryBalance = await ethers.provider.getBalance(beneficiary.address);
    const initialDelegate1Balance = await ethers.provider.getBalance(
      mockJbRedemptionDelegate.address,
    );
    const initialDelegate2Balance = await ethers.provider.getBalance(
      mockJbRedemptionDelegate2.address,
    );

    await jbEthPaymentTerminal.connect(terminalOwner).setFee(0);

    const tx = await jbEthPaymentTerminal
      .connect(holder)
      .redeemTokensOf(
        holder.address,
        PROJECT_ID,
        /* tokenCount */ AMOUNT,
        /* token */ ethers.constants.AddressZero,
        /* minReturnedTokens */ redeemedAmount,
        beneficiary.address,
        MEMO,
        METADATA,
      );

    // Uncaught AssertionError: expected [ Array(4) ] to equal [ Array(4) ]
    await expect(tx).to.emit(jbEthPaymentTerminal, 'DelegateDidRedeem(address,(address,uint256,uint256,uint256,(address,uint256,uint256,uint256),(address,uint256,uint256,uint256),address,string,bytes),uint256,uint256,address)');
    // .withArgs(
    //   mockJbRedemptionDelegate.address,
    //   [
    //     // JBDidRedeemData obj
    //     holder.address,
    //     PROJECT_ID,
    //     AMOUNT,
    //     [
    //       tokenAddress,
    //       ethers.BigNumber.from(RECLAIM_AMOUNT),
    //       ethers.BigNumber.from(DECIMALS_ETH),
    //       CURRENCY_ETH,
    //     ],
    //     beneficiary.address,
    //     ADJUSTED_MEMO,
    //     METADATA,
    //   ],
    //   /* msg.sender */ holder.address,
    // );

    await expect(tx)
      .to.emit(jbEthPaymentTerminal, 'RedeemTokens(uint256,uint256,uint256,address,address,uint256,uint256,uint256,string,bytes,address)')
      .withArgs(
        /* _fundingCycle.configuration */ timestamp,
        /* _fundingCycle.number */ FUNDING_CYCLE_NUM,
        /* _projectId */ PROJECT_ID,
        /* _holder */ holder.address,
        /* _beneficiary */ beneficiary.address,
        /* _tokenCount */ AMOUNT,
        /* reclaimAmount */ redeemedAmount,
        /* fee */ 0,
        /* memo */ ADJUSTED_MEMO,
        /* metadata */ METADATA,
        /* msg.sender */ holder.address,
      );

    // Terminal should be out of ETH
    expect(await ethers.provider.getBalance(jbEthPaymentTerminal.address)).to.equal(0);

    // Beneficiary should have a larger balance
    expect(await ethers.provider.getBalance(beneficiary.address)).to.equal(
      initialBeneficiaryBalance.add(redeemedAmount),
    );

    // Delegate1 should have a larger balance
    expect(await ethers.provider.getBalance(mockJbRedemptionDelegate.address)).to.equal(
      initialDelegate1Balance.add(delegate1Amount),
    );

    // Delegate2 should have a larger balance
    expect(await ethers.provider.getBalance(mockJbRedemptionDelegate2.address)).to.equal(
      initialDelegate2Balance.add(delegate2Amount),
    );
  });

  it('Should not perform a transfer and only emit events if claim amount is 0', async function () {
    const {
      beneficiary,
      fundingCycle,
      holder,
      jbEthPaymentTerminal,
      mockJBPaymentTerminalStore,
      mockJbDirectory,
      mockJbController,
      timestamp,
    } = await setup();

    await mockJbDirectory.mock.controllerOf.withArgs(PROJECT_ID).returns(mockJbController.address);
    await mockJbController.mock.burnTokensOf
      .withArgs(holder.address, PROJECT_ID, AMOUNT, /* memo */ '', /* preferClaimedTokens */ false)
      .returns();

    // Keep it simple and let 1 token exchange for 1 wei
    await mockJBPaymentTerminalStore.mock.recordRedemptionFor
      .withArgs(holder.address, PROJECT_ID, /* tokenCount */ AMOUNT, MEMO, METADATA)
      .returns(fundingCycle, /* reclaimAmount */ 0, /* delegateAllocation */[], ADJUSTED_MEMO); // Set reclaimAmount to 0

    await setBalance(jbEthPaymentTerminal.address, AMOUNT);

    const initialBeneficiaryBalance = await ethers.provider.getBalance(beneficiary.address);

    const tx = await jbEthPaymentTerminal
      .connect(holder)
      .redeemTokensOf(
        holder.address,
        PROJECT_ID,
        /* tokenCount */ AMOUNT,
        /* token */ ethers.constants.AddressZero,
        /* minReturnedTokens */ 0,
        beneficiary.address,
        MEMO,
        METADATA,
      );

    await expect(tx)
      .to.emit(jbEthPaymentTerminal, 'RedeemTokens(uint256,uint256,uint256,address,address,uint256,uint256,uint256,string,bytes,address)')
      .withArgs(
        /* _fundingCycle.configuration */ timestamp,
        /* _fundingCycle.number */ FUNDING_CYCLE_NUM,
        /* _projectId */ PROJECT_ID,
        /* _holder */ holder.address,
        /* _beneficiary */ beneficiary.address,
        /* _tokenCount */ AMOUNT,
        /* reclaimAmount */ 0,
        /* fee */ 0,
        /* memo */ ADJUSTED_MEMO,
        /* metadata */ METADATA,
        /* msg.sender */ holder.address,
      );

    // Terminal's ETH balance should not have changed
    expect(await ethers.provider.getBalance(jbEthPaymentTerminal.address)).to.equal(AMOUNT);

    // Beneficiary should have the same balance
    expect(await ethers.provider.getBalance(beneficiary.address)).to.equal(
      initialBeneficiaryBalance,
    );
  });

  /* Sad path tests */

  it(`Can't redeem tokens for overflow without access`, async function () {
    const { beneficiary, holder, jbEthPaymentTerminal, mockJbOperatorStore, otherCaller } =
      await setup();

    await mockJbOperatorStore.mock.hasPermission.returns(false);

    await expect(
      jbEthPaymentTerminal
        .connect(otherCaller)
        .redeemTokensOf(
          holder.address,
          PROJECT_ID,
          /* tokenCount */ AMOUNT,
          /* token */ ethers.constants.AddressZero,
          /* minReturnedTokens */ AMOUNT,
          beneficiary.address,
          MEMO,
          /* delegateMetadata */ 0,
        ),
    ).to.be.revertedWith(errors.UNAUTHORIZED);
  });

  it(`Can't redeem tokens for overflow if beneficiary is zero address`, async function () {
    const { holder, jbEthPaymentTerminal } = await setup();

    await expect(
      jbEthPaymentTerminal.connect(holder).redeemTokensOf(
        holder.address,
        PROJECT_ID,
        /* tokenCount */ AMOUNT,
        ethers.constants.AddressZero,
        /* minReturnedTokens */ AMOUNT,
        /* beneficiary */ ethers.constants.AddressZero, // Beneficiary address is 0
        MEMO,
        /* delegateMetadata */ 0,
      ),
    ).to.be.revertedWith(errors.REDEEM_TO_ZERO_ADDRESS);
  });
  it("Can't redeem if reclaim amount is less than expected", async function () {
    const {
      beneficiary,
      fundingCycle,
      holder,
      jbEthPaymentTerminal,
      mockJBPaymentTerminalStore,
      mockJbDirectory,
      mockJbController,
      timestamp,
    } = await setup();

    await mockJbDirectory.mock.controllerOf.withArgs(PROJECT_ID).returns(mockJbController.address);
    await mockJbController.mock.burnTokensOf
      .withArgs(holder.address, PROJECT_ID, AMOUNT, /* memo */ '', /* preferClaimedTokens */ false)
      .returns();

    // Keep it simple and let 1 token exchange for 1 wei
    await mockJBPaymentTerminalStore.mock.recordRedemptionFor
      .withArgs(holder.address, PROJECT_ID, /* tokenCount */ AMOUNT, MEMO, METADATA)
      .returns(fundingCycle, /* reclaimAmount */ 0, /* delegateAllocation */[], ADJUSTED_MEMO); // Set reclaimAmount to 0

    await expect(
      jbEthPaymentTerminal
        .connect(holder)
        .redeemTokensOf(
          holder.address,
          PROJECT_ID,
          /* tokenCount */ AMOUNT,
          /* token */ ethers.constants.AddressZero,
          /* minReturnedTokens */ MIN_RETURNED_AMOUNT,
          beneficiary.address,
          MEMO,
          METADATA,
        ),
    ).to.be.revertedWith(errors.INADEQUATE_RECLAIM_AMOUNT);
  });
});
