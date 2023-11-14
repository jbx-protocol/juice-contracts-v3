import { expect } from 'chai';
import { ethers } from 'hardhat';
import { deployMockContract } from '@ethereum-waffle/mock-contract';
import { makeSplits, packFundingCycleMetadata } from '../helpers/utils';
import errors from '../helpers/errors.json';

import JbController from '../../artifacts/contracts/JBController3_1.sol/JBController3_1.json';
import jbDirectory from '../../artifacts/contracts/JBDirectory.sol/JBDirectory.json';
import jbFundingCycleStore from '../../artifacts/contracts/JBFundingCycleStore.sol/JBFundingCycleStore.json';
import jbOperatoreStore from '../../artifacts/contracts/JBOperatorStore.sol/JBOperatorStore.json';
import jbFundAccessConstraintsStore from '../../artifacts/contracts/JBFundAccessConstraintsStore.sol/JBFundAccessConstraintsStore.json';
import jbProjects from '../../artifacts/contracts/JBProjects.sol/JBProjects.json';
import jbSplitsStore from '../../artifacts/contracts/JBSplitsStore.sol/JBSplitsStore.json';
import jbTerminal from '../../artifacts/contracts/JBETHPaymentTerminal3_1_2.sol/JBETHPaymentTerminal3_1_2.json';
import jbTokenStore from '../../artifacts/contracts/JBTokenStore.sol/JBTokenStore.json';

describe('JBController3_1::reconfigureFundingCycleOf(...)', function () {
  const PROJECT_ID = 1;
  const PROJECT_START = '1';
  const MEMO = 'Test Memo';

  let RECONFIGURE_INDEX;

  before(async function () {
    let jbOperationsFactory = await ethers.getContractFactory('JBOperations');
    let jbOperations = await jbOperationsFactory.deploy();

    RECONFIGURE_INDEX = await jbOperations.RECONFIGURE();
  });

  async function setup() {
    let [deployer, projectOwner, caller, ...addrs] = await ethers.getSigners();

    const blockNum = await ethers.provider.getBlockNumber();
    const block = await ethers.provider.getBlock(blockNum);
    const timestamp = block.timestamp;

    let [
      mockJbController,
      mockJbDirectory,
      mockJbFundingCycleStore,
      mockJbOperatorStore,
      mockJbProjects,
      mockJbSplitsStore,
      mockJbTerminal1,
      mockJbTerminal2,
      mockJbTokenStore,
      mockJbFundAccessConstraintsStore,
    ] = await Promise.all([
      deployMockContract(deployer, JbController.abi),
      deployMockContract(deployer, jbDirectory.abi),
      deployMockContract(deployer, jbFundingCycleStore.abi),
      deployMockContract(deployer, jbOperatoreStore.abi),
      deployMockContract(deployer, jbProjects.abi),
      deployMockContract(deployer, jbSplitsStore.abi),
      deployMockContract(deployer, jbTerminal.abi),
      deployMockContract(deployer, jbTerminal.abi),
      deployMockContract(deployer, jbTokenStore.abi),
      deployMockContract(deployer, jbFundAccessConstraintsStore.abi),
    ]);

    let jbControllerFactory = await ethers.getContractFactory(
      'contracts/JBController3_1.sol:JBController3_1',
    );
    let jbController = await jbControllerFactory.deploy(
      mockJbOperatorStore.address,
      mockJbProjects.address,
      mockJbDirectory.address,
      mockJbFundingCycleStore.address,
      mockJbTokenStore.address,
      mockJbSplitsStore.address,
      mockJbFundAccessConstraintsStore.address
    );

    const fundingCycleData = makeFundingCycleDataStruct();
    const fundingCycleMetadata = makeFundingCycleMetadata();
    const splits = makeSplits();

    await mockJbProjects.mock.ownerOf.withArgs(PROJECT_ID).returns(projectOwner.address);

    await mockJbFundingCycleStore.mock.configureFor
      .withArgs(PROJECT_ID, fundingCycleData, fundingCycleMetadata.packed, PROJECT_START)
      .returns(
        Object.assign(
          {
            number: 1,
            configuration: timestamp,
            basedOn: timestamp,
            start: timestamp,
            metadata: fundingCycleMetadata.packed,
          },
          fundingCycleData,
        ),
      );

    const groupedSplits = [{ group: 1, splits }];

    await mockJbSplitsStore.mock.set
      .withArgs(PROJECT_ID, /*configuration=*/ timestamp, groupedSplits)
      .returns();

    return {
      deployer,
      projectOwner,
      caller,
      addrs,
      jbController,
      mockJbDirectory,
      mockJbTokenStore,
      mockJbController,
      mockJbOperatorStore,
      mockJbFundAccessConstraintsStore,
      mockJbFundingCycleStore,
      mockJbTerminal1,
      mockJbTerminal2,
      mockJbSplitsStore,
      timestamp,
      fundingCycleData,
      fundingCycleMetadata,
      splits,
    };
  }

  function makeFundingCycleMetadata({
    reservedRate = 0,
    redemptionRate = 10000,
    baseCurrency = 1, // ETH
    pausePay = false,
    pauseDistributions = false,
    pauseRedeem = false,
    pauseBurn = false,
    pauseTransfers = false,
    allowMinting = false,
    allowChangeToken = false,
    allowTerminalMigration = false,
    allowControllerMigration = false,
    allowSetTerminals = false,
    allowSetControllers = false,
    holdFees = false,
    preferClaimedTokenOverride = false,
    useTotalOverflowForRedemptions = false,
    useDataSourceForPay = false,
    useDataSourceForRedeem = false,
    dataSource = ethers.constants.AddressZero,
    metadata = 0,
  } = {}) {
    const unpackedMetadata = {
      global: {
        allowSetTerminals,
        allowSetControllers,
        pauseTransfers,
      },
      reservedRate,
      redemptionRate,
      baseCurrency,
      pausePay,
      pauseDistributions,
      pauseRedeem,
      pauseBurn,
      allowMinting,
      allowChangeToken,
      allowTerminalMigration,
      allowControllerMigration,
      holdFees,
      preferClaimedTokenOverride,
      useTotalOverflowForRedemptions,
      useDataSourceForPay,
      useDataSourceForRedeem,
      dataSource,
      metadata,
    };
    return { unpacked: unpackedMetadata, packed: packFundingCycleMetadata(unpackedMetadata) };
  }
  function makeFundingCycleDataStruct({
    duration = 0,
    weight = ethers.BigNumber.from('1' + '0'.repeat(18)),
    discountRate = 900000000,
    ballot = ethers.constants.AddressZero,
  } = {}) {
    return { duration, weight, discountRate, ballot };
  }

  function makeFundingAccessConstraints({
    terminals,
    token = ethers.Wallet.createRandom().address,
    distributionLimit = 200,
    distributionLimitCurrency = 1,
    overflowAllowance = 100,
    overflowAllowanceCurrency = 2,
  } = {}) {
    let constraints = [];
    for (let terminal of terminals) {
      constraints.push({
        terminal,
        token,
        distributionLimit,
        distributionLimitCurrency,
        overflowAllowance,
        overflowAllowanceCurrency,
      });
    }
    return constraints;
  }

  it(`Should reconfigure funding cycle and emit events if caller is project owner`, async function () {
    const {
      jbController,
      projectOwner,
      timestamp,
      fundingCycleData,
      fundingCycleMetadata,
      splits,
      mockJbTerminal1,
      mockJbTerminal2,
      mockJbFundAccessConstraintsStore
    } = await setup();

    const groupedSplits = [{ group: 1, splits }];
    const terminals = [mockJbTerminal1.address, mockJbTerminal2.address];
    const fundAccessConstraints = makeFundingAccessConstraints({ terminals });

    await mockJbFundAccessConstraintsStore.mock.setFor
      .withArgs(PROJECT_ID, timestamp, fundAccessConstraints)
      .returns();

    expect(
      await jbController
        .connect(projectOwner)
        .callStatic.reconfigureFundingCyclesOf(
          PROJECT_ID,
          [{
            mustStartAtOrAfter: PROJECT_START,
            data: fundingCycleData,
            metadata: fundingCycleMetadata.unpacked,
            groupedSplits: groupedSplits,
            fundAccessConstraints: fundAccessConstraints
          }],
          MEMO,
        ),
    ).to.equal(timestamp);

    let tx = jbController
      .connect(projectOwner)
      .reconfigureFundingCyclesOf(
        PROJECT_ID,
        [{
          mustStartAtOrAfter: PROJECT_START,
          data: fundingCycleData,
          metadata: fundingCycleMetadata.unpacked,
          groupedSplits: groupedSplits,
          fundAccessConstraints: fundAccessConstraints
        }],
        MEMO,
      );

    await expect(tx)
      .to.emit(jbController, 'ReconfigureFundingCycles')
      .withArgs(
        /*fundingCycleData.configuration=*/ timestamp,
        PROJECT_ID,
        MEMO,
        projectOwner.address,
      );
  });

  it(`Should reconfigure multiple funding cycles and emit events if caller is project owner`, async function () {
    const {
      jbController,
      projectOwner,
      timestamp,
      fundingCycleData,
      fundingCycleMetadata,
      splits,
      mockJbTerminal1,
      mockJbTerminal2,
      mockJbSplitsStore,
      mockJbFundingCycleStore,
      mockJbFundAccessConstraintsStore
    } = await setup();

    const groupedSplits = [{ group: 1, splits }];
    const terminals = [mockJbTerminal1.address, mockJbTerminal2.address];
    const fundAccessConstraints = makeFundingAccessConstraints({ terminals });
    const fundAccessConstraints2 = makeFundingAccessConstraints({ terminals });

    await mockJbFundAccessConstraintsStore.mock.setFor
      .withArgs(PROJECT_ID, timestamp, fundAccessConstraints)
      .returns();

    await mockJbFundingCycleStore.mock.configureFor
      .withArgs(PROJECT_ID, fundingCycleData, fundingCycleMetadata.packed, PROJECT_START + 1)
      .returns(
        Object.assign(
          {
            number: 2,
            configuration: timestamp + 1,
            basedOn: timestamp,
            start: timestamp,
            metadata: fundingCycleMetadata.packed,
          },
          fundingCycleData,
        ),
      );

    const groupedSplits2 = [{ group: 1, splits }];

    await mockJbSplitsStore.mock.set
      .withArgs(PROJECT_ID, /*configuration=*/ timestamp + 1, groupedSplits2)
      .returns();

    // Configuration is an increment of the prior based on the timestamp.
    await mockJbFundAccessConstraintsStore.mock.setFor
      .withArgs(PROJECT_ID, timestamp + 1, fundAccessConstraints2)
      .returns();

    expect(
      await jbController
        .connect(projectOwner)
        .callStatic.reconfigureFundingCyclesOf(
          PROJECT_ID,
          [{
            mustStartAtOrAfter: PROJECT_START,
            data: fundingCycleData,
            metadata: fundingCycleMetadata.unpacked,
            groupedSplits: groupedSplits,
            fundAccessConstraints: fundAccessConstraints
          },
          {
            mustStartAtOrAfter: PROJECT_START + 1,
            data: fundingCycleData,
            metadata: fundingCycleMetadata.unpacked,
            groupedSplits: groupedSplits2,
            fundAccessConstraints: fundAccessConstraints2
          }
          ],
          MEMO,
        ),
    ).to.equal(timestamp + 1);

    let tx = jbController
      .connect(projectOwner)
      .reconfigureFundingCyclesOf(
        PROJECT_ID,
        [{
          mustStartAtOrAfter: PROJECT_START,
          data: fundingCycleData,
          metadata: fundingCycleMetadata.unpacked,
          groupedSplits: groupedSplits,
          fundAccessConstraints: fundAccessConstraints
        },
        {
          mustStartAtOrAfter: PROJECT_START + 1,
          data: fundingCycleData,
          metadata: fundingCycleMetadata.unpacked,
          groupedSplits: groupedSplits2,
          fundAccessConstraints: fundAccessConstraints2
        }
        ],
        MEMO,
      );

    await expect(tx)
      .to.emit(jbController, 'ReconfigureFundingCycles')
      .withArgs(
        /*fundingCycleData.configuration=*/ timestamp + 1,
        PROJECT_ID,
        MEMO,
        projectOwner.address,
      );
  });

  it(`Should reconfigure funding cycle with metadata using truthy bools`, async function () {
    const {
      jbController,
      projectOwner,
      timestamp,
      fundingCycleData,
      splits,
      mockJbTerminal1,
      mockJbTerminal2,
      mockJbFundingCycleStore,
      mockJbFundAccessConstraintsStore
    } = await setup();

    const groupedSplits = [{ group: 1, splits }];
    const terminals = [mockJbTerminal1.address, mockJbTerminal2.address];
    const fundAccessConstraints = makeFundingAccessConstraints({ terminals });

    await mockJbFundAccessConstraintsStore.mock.setFor
      .withArgs(PROJECT_ID, timestamp, fundAccessConstraints)
      .returns();

    const truthyMetadata = makeFundingCycleMetadata({
      pausePay: true,
      pauseDistributions: true,
      pauseRedeem: true,
      pauseBurn: true,
      allowMinting: true,
      allowChangeToken: true,
      allowTerminalMigration: true,
      allowControllerMigration: true,
      holdFees: true,
      useTotalOverflowForRedemptions: true,
      useDataSourceForPay: true,
      useDataSourceForRedeem: true,
    });
    await mockJbFundingCycleStore.mock.configureFor
      .withArgs(PROJECT_ID, fundingCycleData, truthyMetadata.packed, PROJECT_START)
      .returns(
        Object.assign(
          {
            number: 1,
            configuration: timestamp,
            basedOn: timestamp,
            start: timestamp,
            metadata: truthyMetadata.packed,
          },
          fundingCycleData,
        ),
      );
    expect(
      await jbController
        .connect(projectOwner)
        .callStatic.reconfigureFundingCyclesOf(
          PROJECT_ID,
          [{
            mustStartAtOrAfter: PROJECT_START,
            data: fundingCycleData,
            metadata: truthyMetadata.unpacked,
            groupedSplits: groupedSplits,
            fundAccessConstraints: fundAccessConstraints
          }],
          MEMO,
        ),
    ).to.equal(timestamp);
  });

  it(`Should reconfigure funding cycle and emit events if caller is not project owner but is authorized`, async function () {
    const {
      jbController,
      projectOwner,
      addrs,
      timestamp,
      fundingCycleData,
      fundingCycleMetadata,
      splits,
      mockJbOperatorStore,
      mockJbTerminal1,
      mockJbTerminal2,
      mockJbFundAccessConstraintsStore
    } = await setup();
    const caller = addrs[0];

    await mockJbOperatorStore.mock.hasPermission
      .withArgs(caller.address, projectOwner.address, PROJECT_ID, RECONFIGURE_INDEX)
      .returns(true);

    const groupedSplits = [{ group: 1, splits }];
    const terminals = [mockJbTerminal1.address, mockJbTerminal2.address];
    const fundAccessConstraints = makeFundingAccessConstraints({ terminals });

    await mockJbFundAccessConstraintsStore.mock.setFor
      .withArgs(PROJECT_ID, timestamp, fundAccessConstraints)
      .returns();

    expect(
      await jbController
        .connect(caller)
        .callStatic.reconfigureFundingCyclesOf(
          PROJECT_ID,
          [{
            mustStartAtOrAfter: PROJECT_START,
            data: fundingCycleData,
            metadata: fundingCycleMetadata.unpacked,
            groupedSplits: groupedSplits,
            fundAccessConstraints: fundAccessConstraints
          }],
          MEMO,
        ),
    ).to.equal(timestamp);

    let tx = jbController
      .connect(caller)
      .reconfigureFundingCyclesOf(
        PROJECT_ID,
        [{
          mustStartAtOrAfter: PROJECT_START,
          data: fundingCycleData,
          metadata: fundingCycleMetadata.unpacked,
          groupedSplits: groupedSplits,
          fundAccessConstraints: fundAccessConstraints
        }],
        MEMO,
      );
  });

  it(`Can't reconfigure funding cycle if caller is not authorized`, async function () {
    const {
      jbController,
      projectOwner,
      addrs,
      fundingCycleData,
      fundingCycleMetadata,
      splits,
      mockJbOperatorStore,
      mockJbTerminal1,
      mockJbTerminal2,
    } = await setup();

    const caller = addrs[0];
    await mockJbOperatorStore.mock.hasPermission
      .withArgs(caller.address, projectOwner.address, PROJECT_ID, RECONFIGURE_INDEX)
      .returns(false);

    await mockJbOperatorStore.mock.hasPermission
      .withArgs(caller.address, projectOwner.address, 0, RECONFIGURE_INDEX)
      .returns(false);

    const groupedSplits = [{ group: 1, splits }];
    const terminals = [mockJbTerminal1.address, mockJbTerminal2.address];
    const fundAccessConstraints = makeFundingAccessConstraints({ terminals });

    let tx = jbController
      .connect(caller)
      .reconfigureFundingCyclesOf(
        PROJECT_ID,
        [{
          mustStartAtOrAfter: PROJECT_START,
          data: fundingCycleData,
          metadata: fundingCycleMetadata.unpacked,
          groupedSplits: groupedSplits,
          fundAccessConstraints: fundAccessConstraints
        }],
        MEMO,
      );

    await expect(tx).to.be.revertedWith(errors.UNAUTHORIZED);
  });

  it(`Should reconfigure funding cycle without grouped splits`, async function () {
    const {
      jbController,
      projectOwner,
      timestamp,
      fundingCycleData,
      fundingCycleMetadata,
      mockJbTerminal1,
      mockJbTerminal2,
      mockJbSplitsStore,
      mockJbFundAccessConstraintsStore
    } = await setup();

    const terminals = [mockJbTerminal1.address, mockJbTerminal2.address];
    const fundAccessConstraints = makeFundingAccessConstraints({ terminals });

    await mockJbFundAccessConstraintsStore.mock.setFor
      .withArgs(PROJECT_ID, timestamp, fundAccessConstraints)
      .returns();

    const groupedSplits = [];

    await mockJbSplitsStore.mock.set
      .withArgs(PROJECT_ID, /*configuration=*/ timestamp, groupedSplits)
      .returns();

    expect(
      await jbController
        .connect(projectOwner)
        .callStatic.reconfigureFundingCyclesOf(
          PROJECT_ID,
          [{
            mustStartAtOrAfter: PROJECT_START,
            data: fundingCycleData,
            metadata: fundingCycleMetadata.unpacked,
            groupedSplits: groupedSplits,
            fundAccessConstraints: fundAccessConstraints
          }],
          MEMO,
        ),
    ).to.equal(timestamp);

    let tx = jbController
      .connect(projectOwner)
      .reconfigureFundingCyclesOf(
        PROJECT_ID,
        [{
          mustStartAtOrAfter: PROJECT_START,
          data: fundingCycleData,
          metadata: fundingCycleMetadata.unpacked,
          groupedSplits: groupedSplits,
          fundAccessConstraints: fundAccessConstraints
        }],
        MEMO,
      );
  });

  it(`Should reconfigure funding cycle with empty grouped split and without defined funding cycle constraints`, async function () {
    const {
      jbController,
      projectOwner,
      timestamp,
      fundingCycleData,
      fundingCycleMetadata,
      mockJbTerminal1,
      mockJbTerminal2,
      mockJbSplitsStore,
      mockJbFundAccessConstraintsStore
    } = await setup();

    const groupedSplits = [{ group: 1, splits: [] }];
    const terminals = [mockJbTerminal1.address, mockJbTerminal2.address];
    const fundAccessConstraints = makeFundingAccessConstraints({
      terminals,
      distributionLimit: 0,
      overflowAllowance: 0,
      currency: 0,
    });

    await mockJbFundAccessConstraintsStore.mock.setFor
      .withArgs(PROJECT_ID, timestamp, fundAccessConstraints)
      .returns();

    await mockJbSplitsStore.mock.set
      .withArgs(PROJECT_ID, /*configuration=*/ timestamp, groupedSplits)
      .returns();

    expect(
      await jbController
        .connect(projectOwner)
        .callStatic.reconfigureFundingCyclesOf(
          PROJECT_ID,
          [{
            mustStartAtOrAfter: PROJECT_START,
            data: fundingCycleData,
            metadata: fundingCycleMetadata.unpacked,
            groupedSplits: groupedSplits,
            fundAccessConstraints: fundAccessConstraints
          }],
          MEMO,
        ),
    ).to.equal(timestamp);

    let tx = jbController
      .connect(projectOwner)
      .reconfigureFundingCyclesOf(
        PROJECT_ID,
        [{
          mustStartAtOrAfter: PROJECT_START,
          data: fundingCycleData,
          metadata: fundingCycleMetadata.unpacked,
          groupedSplits: groupedSplits,
          fundAccessConstraints: fundAccessConstraints
        }],
        MEMO,
      );
  });

  it(`Can't set a reserved rate superior to 10000`, async function () {
    const {
      jbController,
      projectOwner,
      fundingCycleData,
      splits,
      mockJbTerminal1,
      mockJbTerminal2,
    } = await setup();
    const groupedSplits = [{ group: 1, splits }];
    const terminals = [mockJbTerminal1.address, mockJbTerminal2.address];
    const fundAccessConstraints = makeFundingAccessConstraints({ terminals });
    const fundingCycleMetadata = makeFundingCycleMetadata({ reservedRate: 10001 });

    let tx = jbController
      .connect(projectOwner)
      .reconfigureFundingCyclesOf(
        PROJECT_ID,
        [{
          mustStartAtOrAfter: PROJECT_START,
          data: fundingCycleData,
          metadata: fundingCycleMetadata.unpacked,
          groupedSplits: groupedSplits,
          fundAccessConstraints: fundAccessConstraints
        }],
        MEMO,
      );

    await expect(tx).to.be.revertedWith('INVALID_RESERVED_RATE()');
  });

  it(`Can't set a redemption rate superior to 10000`, async function () {
    const {
      jbController,
      projectOwner,
      fundingCycleData,
      fundingCycleMetadata,
      splits,
      mockJbTerminal1,
      mockJbTerminal2,
    } = await setup();
    const groupedSplits = [{ group: 1, splits }];
    const terminals = [mockJbTerminal1.address, mockJbTerminal2.address];
    const fundAccessConstraints = makeFundingAccessConstraints({ terminals });
    fundingCycleMetadata.unpacked.redemptionRate = 10001; //not possible in packed metadata (shl of a negative value)

    let tx = jbController
      .connect(projectOwner)
      .reconfigureFundingCyclesOf(
        PROJECT_ID,
        [{
          mustStartAtOrAfter: PROJECT_START,
          data: fundingCycleData,
          metadata: fundingCycleMetadata.unpacked,
          groupedSplits: groupedSplits,
          fundAccessConstraints: fundAccessConstraints
        }],
        MEMO,
      );

    await expect(tx).to.be.revertedWith(errors.INVALID_REDEMPTION_RATE);
  });
});
