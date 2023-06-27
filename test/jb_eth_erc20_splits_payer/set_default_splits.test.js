import { ethers } from 'hardhat';
import { expect } from 'chai';
import { deployMockContract } from '@ethereum-waffle/mock-contract';

import { makeSplits } from '../helpers/utils';

import jbDirectory from '../../artifacts/contracts/JBDirectory.sol/JBDirectory.json';
import jbSplitsStore from '../../artifacts/contracts/JBSplitsStore.sol/JBSplitsStore.json';

describe('JBETHERC20SplitsPayer::setDefaultSplits()', function () {
  const DEFAULT_PROJECT_ID = 2;
  const DEFAULT_SPLITS_PROJECT_ID = 3;
  const DEFAULT_SPLITS_DOMAIN = 1;
  const DEFAULT_SPLITS_GROUP = 1;
  const DEFAULT_BENEFICIARY = ethers.Wallet.createRandom().address;
  const DEFAULT_PREFER_CLAIMED_TOKENS = false;
  const DEFAULT_MEMO = 'hello world';
  const DEFAULT_METADATA = [0x1];
  const PREFER_ADD_TO_BALANCE = false;

  const NEW_SPLITS_PROJECT_ID = 69;
  const NEW_SPLITS_DOMAIN = 420;
  const NEW_SPLITS_GROUP = 69420;
  const NEW_SPLITS = [{ group: 123, splits: makeSplits() }];

  async function setup() {
    let [deployer, owner, caller, ...addrs] = await ethers.getSigners();

    let mockJbDirectory = await deployMockContract(deployer, jbDirectory.abi);
    let mockJbSplitsStore = await deployMockContract(deployer, jbSplitsStore.abi);

    await mockJbSplitsStore.mock.directory.returns(mockJbDirectory.address);

    let jbSplitsPayerFactory = await ethers.getContractFactory(
      'contracts/JBETHERC20SplitsPayer.sol:JBETHERC20SplitsPayer',
    );
    let jbSplitsPayer = await jbSplitsPayerFactory
      .connect(deployer)
      .deploy(mockJbSplitsStore.address);

    await jbSplitsPayer
      .connect(deployer)
      ['initialize(uint256,uint256,uint256,uint256,address,bool,string,bytes,bool,address)'](
        DEFAULT_SPLITS_PROJECT_ID,
        DEFAULT_SPLITS_DOMAIN,
        DEFAULT_SPLITS_GROUP,
        DEFAULT_PROJECT_ID,
        DEFAULT_BENEFICIARY,
        DEFAULT_PREFER_CLAIMED_TOKENS,
        DEFAULT_MEMO,
        DEFAULT_METADATA,
        PREFER_ADD_TO_BALANCE,
        owner.address,
      );

    return {
      deployer,
      caller,
      owner,
      addrs,
      jbSplitsPayer,
      mockJbSplitsStore,
    };
  }

  it(`Should set new splits in JBsplitsStore and emit events`, async function () {
    const { owner, mockJbSplitsStore, jbSplitsPayer } = await setup();

    await mockJbSplitsStore.mock.set
      .withArgs(NEW_SPLITS_PROJECT_ID, NEW_SPLITS_DOMAIN, NEW_SPLITS)
      .returns();

    await expect(
      jbSplitsPayer
        .connect(owner)
        .setDefaultSplits(NEW_SPLITS_PROJECT_ID, NEW_SPLITS_DOMAIN, NEW_SPLITS_GROUP, NEW_SPLITS),
    )
      .to.emit(jbSplitsPayer, 'SetDefaultSplitsReference')
      .withArgs(NEW_SPLITS_PROJECT_ID, NEW_SPLITS_DOMAIN, NEW_SPLITS_GROUP, owner.address);

    expect(await jbSplitsPayer.defaultSplitsProjectId()).to.equal(NEW_SPLITS_PROJECT_ID);
    expect(await jbSplitsPayer.defaultSplitsDomain()).to.equal(NEW_SPLITS_DOMAIN);
    expect(await jbSplitsPayer.defaultSplitsGroup()).to.equal(NEW_SPLITS_GROUP);
  });
});
