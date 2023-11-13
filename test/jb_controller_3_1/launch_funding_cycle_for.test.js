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

describe('JBController3_1::launchFundingCyclesFor(...)', function () {
  const EXISTING_PROJECT = 1;
  const LAUNCHED_PROJECT = 2;
  const NONEXISTANT_PROJECT = 3;
  const METADATA_CID = '';
  const METADATA_DOMAIN = 1234;
  const MEMO = 'Test Memo';
  const PROJECT_START = '1';
  let RECONFIGURE_INDEX;
  let MIGRATE_CONTROLLER_INDEX;

  before(async function () {
    let jbOperationsFactory = await ethers.getContractFactory('JBOperations');
    let jbOperations = await jbOperationsFactory.deploy();

    RECONFIGURE_INDEX = await jbOperations.RECONFIGURE();
    MIGRATE_CONTROLLER_INDEX = await jbOperations.MIGRATE_CONTROLLER();
  });

  async function setup() {
    let [deployer, projectOwner, nonOwner, ...addrs] = await ethers.getSigners();

    const blockNum = await ethers.provider.getBlockNumber();
    const block = await ethers.provider.getBlock(blockNum);
    const timestamp = block.timestamp;
    const fundingCycleData = makeFundingCycleDataStruct();
    const fundingCycleMetadata = makeFundingCycleMetadata();
    const splits = makeSplits();

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

    await mockJbProjects.mock.createFor
      .withArgs(projectOwner.address, [METADATA_CID, METADATA_DOMAIN])
      .returns(EXISTING_PROJECT);

    await mockJbProjects.mock.ownerOf.withArgs(EXISTING_PROJECT).returns(projectOwner.address);

    await mockJbProjects.mock.ownerOf.withArgs(LAUNCHED_PROJECT).returns(projectOwner.address);

    await mockJbProjects.mock.ownerOf.withArgs(NONEXISTANT_PROJECT).reverts();

    await mockJbDirectory.mock.setControllerOf
      .withArgs(EXISTING_PROJECT, jbController.address)
      .returns();

    await mockJbDirectory.mock.setTerminalsOf
      .withArgs(EXISTING_PROJECT, [mockJbTerminal1.address, mockJbTerminal2.address])
      .returns();

    await mockJbFundingCycleStore.mock.configureFor
      .withArgs(EXISTING_PROJECT, fundingCycleData, fundingCycleMetadata.packed, PROJECT_START)
      .returns(
        Object.assign(
          {
            number: EXISTING_PROJECT,
            configuration: timestamp,
            basedOn: timestamp,
            start: timestamp,
            metadata: fundingCycleMetadata.packed,
          },
          fundingCycleData,
        ),
      );

    await mockJbFundingCycleStore.mock.latestConfigurationOf.withArgs(EXISTING_PROJECT).returns(0);

    await mockJbFundingCycleStore.mock.latestConfigurationOf.withArgs(LAUNCHED_PROJECT).returns(1);

    const groupedSplits = [{ group: 1, splits }];

    await mockJbSplitsStore.mock.set
      .withArgs(EXISTING_PROJECT, /*configuration=*/ timestamp, groupedSplits)
      .returns();

    return {
      deployer,
      projectOwner,
      nonOwner,
      addrs,
      jbController,
      mockJbSplitsStore,
      mockJbDirectory,
      mockJbTokenStore,
      mockJbController,
      mockJbProjects,
      mockJbOperatorStore,
      mockJbFundingCycleStore,
      mockJbFundAccessConstraintsStore,
      mockJbTerminal1,
      mockJbTerminal2,
      timestamp,
      fundingCycleData,
      fundingCycleMetadata,
      splits,
    };
  }

  function makeFundingCycleMetadata({
    reservedRate = 0,
    redemptionRate = 10000,
    ballotRedemptionRate = 10000,
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
      ballotRedemptionRate,
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

  it(`Should launch a funding cycle for an existing project and emit events`, async function () {
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
    const token = ethers.Wallet.createRandom().address;
    const fundAccessConstraints = makeFundingAccessConstraints({ terminals, token });

    await mockJbFundAccessConstraintsStore.mock.setFor
      .withArgs(EXISTING_PROJECT, timestamp, fundAccessConstraints)
      .returns();

    expect(
      await jbController
        .connect(projectOwner)
        .callStatic.launchFundingCyclesFor(
          EXISTING_PROJECT,
          [{
            mustStartAtOrAfter: PROJECT_START,
            data: fundingCycleData,
            metadata: fundingCycleMetadata.unpacked,
            groupedSplits: groupedSplits,
            fundAccessConstraints: fundAccessConstraints
          }],
          terminals,
          MEMO,
        ),
    ).to.equal(timestamp);

    let tx = jbController
      .connect(projectOwner)
      .launchFundingCyclesFor(
        EXISTING_PROJECT,
        [{
          mustStartAtOrAfter: PROJECT_START,
          data: fundingCycleData,
          metadata: fundingCycleMetadata.unpacked,
          groupedSplits: groupedSplits,
          fundAccessConstraints: fundAccessConstraints
        }],
        terminals,
        MEMO,
      );

    await expect(tx)
      .to.emit(jbController, 'LaunchFundingCycles')
      .withArgs(
        /*fundingCycleData.configuration=*/ timestamp,
        EXISTING_PROJECT,
        MEMO,
        projectOwner.address,
      );
  });

  it(`Should launch multiple funding cycles for an existing project and emit events`, async function () {
    const {
      jbController,
      projectOwner,
      timestamp,
      fundingCycleData,
      fundingCycleMetadata,
      splits,
      mockJbFundingCycleStore,
      mockJbSplitsStore,
      mockJbTerminal1,
      mockJbTerminal2,
      mockJbFundAccessConstraintsStore
    } = await setup();
    const groupedSplits = [{ group: 1, splits }];
    const terminals = [mockJbTerminal1.address, mockJbTerminal2.address];
    const token = ethers.Wallet.createRandom().address;
    const fundAccessConstraints = makeFundingAccessConstraints({ terminals, token });
    const fundAccessConstraints2 = makeFundingAccessConstraints({ terminals, token });

    await mockJbFundAccessConstraintsStore.mock.setFor
      .withArgs(EXISTING_PROJECT, timestamp, fundAccessConstraints)
      .returns();

    await mockJbFundAccessConstraintsStore.mock.setFor
      .withArgs(EXISTING_PROJECT, timestamp + 1, fundAccessConstraints2)
      .returns();

    await mockJbFundingCycleStore.mock.configureFor
      .withArgs(EXISTING_PROJECT, fundingCycleData, fundingCycleMetadata.packed, PROJECT_START + 1)
      .returns(
        Object.assign(
          {
            number: EXISTING_PROJECT + 1,
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
      .withArgs(EXISTING_PROJECT, /*configuration=*/ timestamp + 1, groupedSplits2)
      .returns();

    expect(
      await jbController
        .connect(projectOwner)
        .callStatic.launchFundingCyclesFor(
          EXISTING_PROJECT,
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
          terminals,
          MEMO,
        ),
    ).to.equal(timestamp + 1);

    let tx = jbController
      .connect(projectOwner)
      .launchFundingCyclesFor(
        EXISTING_PROJECT,
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
        terminals,
        MEMO,
      );

    await expect(tx)
      .to.emit(jbController, 'LaunchFundingCycles')
      .withArgs(
        /*fundingCycleData.configuration=*/ timestamp + 1,
        EXISTING_PROJECT,
        MEMO,
        projectOwner.address,
      );
  });

  it(`Should launch a funding cycle without payment terminals and funding cycle constraints`, async function () {
    const {
      jbController,
      projectOwner,
      timestamp,
      fundingCycleData,
      fundingCycleMetadata,
      splits,
      mockJbFundAccessConstraintsStore
    } = await setup();
    const groupedSplits = [{ group: 1, splits }];
    const fundAccessConstraints = [];

    await mockJbFundAccessConstraintsStore.mock.setFor
      .withArgs(EXISTING_PROJECT, timestamp, fundAccessConstraints)
      .returns();

    expect(
      await jbController
        .connect(projectOwner)
        .callStatic.launchFundingCyclesFor(
          EXISTING_PROJECT,
          [{
            mustStartAtOrAfter: PROJECT_START,
            data: fundingCycleData,
            metadata: fundingCycleMetadata.unpacked,
            groupedSplits: groupedSplits,
            fundAccessConstraints: fundAccessConstraints
          }],
          [],
          MEMO,
        ),
    ).to.equal(timestamp);
  });

  it(`Can't launch a project with a reserved rate superior to 10000`, async function () {
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
      .launchFundingCyclesFor(
        EXISTING_PROJECT,
        [{
          mustStartAtOrAfter: PROJECT_START,
          data: fundingCycleData,
          metadata: fundingCycleMetadata.unpacked,
          groupedSplits: groupedSplits,
          fundAccessConstraints: fundAccessConstraints
        }],
        terminals,
        MEMO,
      );

    await expect(tx).to.be.revertedWith(errors.INVALID_RESERVED_RATE);
  });

  it(`Can't launch a project with a redemption rate superior to 10000`, async function () {
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
      .launchFundingCyclesFor(
        EXISTING_PROJECT,
        [{
          mustStartAtOrAfter: PROJECT_START,
          data: fundingCycleData,
          metadata: fundingCycleMetadata.unpacked,
          groupedSplits: groupedSplits,
          fundAccessConstraints: fundAccessConstraints
        }],
        terminals,
        MEMO,
      );

    await expect(tx).to.be.revertedWith(errors.INVALID_REDEMPTION_RATE);
  });

  it(`Can't launch a project with a ballot redemption rate superior to 10000`, async function () {
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

    fundingCycleMetadata.unpacked.ballotRedemptionRate = 10001; //not possible in packed metadata (shl of a negative value)

    let tx = jbController
      .connect(projectOwner)
      .launchFundingCyclesFor(
        EXISTING_PROJECT,
        [{
          mustStartAtOrAfter: PROJECT_START,
          data: fundingCycleData,
          metadata: fundingCycleMetadata.unpacked,
          groupedSplits: groupedSplits,
          fundAccessConstraints: fundAccessConstraints
        }],
        terminals,
        MEMO,
      );

    await expect(tx).to.be.revertedWith(errors.INVALID_BALLOT_REDEMPTION_RATE);
  });

  it(`Can't be called for a project by a non-owner`, async function () {
    const {
      jbController,
      projectOwner,
      nonOwner,
      fundingCycleData,
      fundingCycleMetadata,
      splits,
      mockJbTerminal1,
      mockJbTerminal2,
      mockJbOperatorStore,
    } = await setup();
    const groupedSplits = [{ group: 1, splits }];
    const terminals = [mockJbTerminal1.address, mockJbTerminal2.address];
    const fundAccessConstraints = makeFundingAccessConstraints({ terminals });

    await mockJbOperatorStore.mock.hasPermission
      .withArgs(nonOwner.address, projectOwner.address, EXISTING_PROJECT, RECONFIGURE_INDEX)
      .returns(false);

    await mockJbOperatorStore.mock.hasPermission
      .withArgs(nonOwner.address, projectOwner.address, 0, RECONFIGURE_INDEX)
      .returns(false);

    let tx = jbController
      .connect(nonOwner)
      .callStatic.launchFundingCyclesFor(
        EXISTING_PROJECT,
        [{
          mustStartAtOrAfter: PROJECT_START,
          data: fundingCycleData,
          metadata: fundingCycleMetadata.unpacked,
          groupedSplits: groupedSplits,
          fundAccessConstraints: fundAccessConstraints
        }],
        terminals,
        MEMO,
      );

    await expect(tx).to.be.revertedWith(errors.UNAUTHORIZED);
  });

  it(`Can't launch for a project with an existing funding cycle`, async function () {
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

    let tx = jbController
      .connect(projectOwner)
      .callStatic.launchFundingCyclesFor(
        LAUNCHED_PROJECT,
        [{
          mustStartAtOrAfter: PROJECT_START,
          data: fundingCycleData,
          metadata: fundingCycleMetadata.unpacked,
          groupedSplits: groupedSplits,
          fundAccessConstraints: fundAccessConstraints
        }],
        terminals,
        MEMO,
      );

    await expect(tx).to.be.revertedWith(errors.FUNDING_CYCLE_ALREADY_LAUNCHED);
  });
});
