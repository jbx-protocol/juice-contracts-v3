import { ethers } from 'hardhat';
import { expect } from 'chai';
import { smock } from '@defi-wonderland/smock';

import { deployMockContract } from '@ethereum-waffle/mock-contract';

import jbDirectory from '../../artifacts/contracts/JBDirectory.sol/JBDirectory.json';
import jbTerminal from '../../artifacts/contracts/abstract/JBPayoutRedemptionPaymentTerminal.sol/JBPayoutRedemptionPaymentTerminal.json';
import ierc20 from '../../artifacts/@openzeppelin/contracts/token/ERC20/ERC20.sol/ERC20.json';
import errors from '../helpers/errors.json';

describe('JBGasTokenERC20ProjectPayer::pay(...)', function () {
  const INITIAL_PROJECT_ID = 1;
  const INITIAL_BENEFICIARY = ethers.Wallet.createRandom().address;
  const INITIAL_PREFER_CLAIMED_TOKENS = false;
  const INITIAL_MEMO = 'hello world';
  const INITIAL_METADATA = '0x69';
  const INITIAL_PREFER_ADD_TO_BALANCE = false;
  const PROJECT_ID = 7;
  const AMOUNT = ethers.utils.parseEther('1.0');
  const BENEFICIARY = ethers.Wallet.createRandom().address;
  const PREFER_CLAIMED_TOKENS = true;
  const MIN_RETURNED_TOKENS = 1;
  const MEMO = 'hi world';
  const METADATA = '0x42';
  const DECIMALS = 1;
  let ethToken;

  this.beforeAll(async function () {
    let jbTokensFactory = await ethers.getContractFactory('JBTokens');
    let jbTokens = await jbTokensFactory.deploy();

    ethToken = await JBTokens.GAS_TOKEN();
  });

  async function setup() {
    let [deployer, owner, caller, ...addrs] = await ethers.getSigners();

    let mockJbDirectory = await deployMockContract(deployer, jbDirectory.abi);
    let mockJbTerminal = await deployMockContract(deployer, jbTerminal.abi);
    let mockToken = await smock.fake(ierc20.abi);

    let jbProjectPayerFactory = await ethers.getContractFactory('JBGasTokenERC20ProjectPayer');
    let jbProjectPayer = await jbProjectPayerFactory
      .connect(deployer)
      .deploy(mockJbDirectory.address);

    await jbProjectPayer
      .connect(deployer)
      .initialize(
        INITIAL_PROJECT_ID,
        INITIAL_BENEFICIARY,
        INITIAL_PREFER_CLAIMED_TOKENS,
        INITIAL_MEMO,
        INITIAL_METADATA,
        INITIAL_PREFER_ADD_TO_BALANCE,
        owner.address,
      );

    return {
      deployer,
      owner,
      caller,
      addrs,
      mockToken,
      mockJbDirectory,
      mockJbTerminal,
      jbProjectPayer,
      jbProjectPayerFactory,
    };
  }

  it(`Should pay funds towards project`, async function () {
    const { jbProjectPayer, mockJbDirectory, mockJbTerminal } = await setup();

    await mockJbDirectory.mock.primaryTerminalOf
      .withArgs(PROJECT_ID, ethToken)
      .returns(mockJbTerminal.address);

    // Eth payments should use 18 decimals.
    await mockJbTerminal.mock.decimalsForToken.withArgs(ethToken).returns(18);

    await mockJbTerminal.mock.pay
      .withArgs(
        PROJECT_ID,
        AMOUNT,
        ethToken,
        BENEFICIARY,
        MIN_RETURNED_TOKENS,
        PREFER_CLAIMED_TOKENS,
        MEMO,
        METADATA,
      )
      .returns(0);

    await expect(
      jbProjectPayer.pay(
        PROJECT_ID,
        ethToken,
        0,
        DECIMALS,
        BENEFICIARY,
        MIN_RETURNED_TOKENS,
        PREFER_CLAIMED_TOKENS,
        MEMO,
        METADATA,
        {
          value: AMOUNT,
        },
      ),
    ).to.not.be.reverted;
  });

  it(`Should pay and use the default beneficiary if set and none is passed`, async function () {
    const { caller, jbProjectPayer, mockJbDirectory, mockJbTerminal } = await setup();

    await mockJbDirectory.mock.primaryTerminalOf
      .withArgs(PROJECT_ID, ethToken)
      .returns(mockJbTerminal.address);

    // Eth payments should use 18 decimals.
    await mockJbTerminal.mock.decimalsForToken.withArgs(ethToken).returns(18);

    await mockJbTerminal.mock.pay
      .withArgs(
        PROJECT_ID,
        AMOUNT,
        ethToken,
        INITIAL_BENEFICIARY,
        MIN_RETURNED_TOKENS,
        PREFER_CLAIMED_TOKENS,
        MEMO,
        METADATA,
      )
      .returns(0);

    await jbProjectPayer
      .connect(caller)
      .pay(
        PROJECT_ID,
        ethToken,
        0,
        DECIMALS,
        ethers.constants.AddressZero,
        MIN_RETURNED_TOKENS,
        PREFER_CLAIMED_TOKENS,
        MEMO,
        METADATA,
        {
          value: AMOUNT,
        },
      );
    // ).to.not.be.reverted;
  });

  it(`Should pay and use the caller if no beneficiary or default beneficiary is set`, async function () {
    const { owner, caller, deployer, jbProjectPayerFactory, mockJbDirectory, mockJbTerminal } =
      await setup();

    let _jbProjectPayer = await jbProjectPayerFactory
      .connect(deployer)
      .deploy(mockJbDirectory.address);

    await _jbProjectPayer
      .connect(deployer)
      .initialize(
        INITIAL_PROJECT_ID,
        ethers.constants.AddressZero,
        INITIAL_PREFER_CLAIMED_TOKENS,
        INITIAL_MEMO,
        INITIAL_METADATA,
        INITIAL_PREFER_ADD_TO_BALANCE,
        owner.address,
      );

    await mockJbDirectory.mock.primaryTerminalOf
      .withArgs(PROJECT_ID, ethToken)
      .returns(mockJbTerminal.address);

    // Eth payments should use 18 decimals.
    await mockJbTerminal.mock.decimalsForToken.withArgs(ethToken).returns(18);

    await mockJbTerminal.mock.pay
      .withArgs(
        PROJECT_ID,
        AMOUNT,
        ethToken,
        caller.address,
        MIN_RETURNED_TOKENS,
        PREFER_CLAIMED_TOKENS,
        MEMO,
        METADATA,
      )
      .returns(0);

    await _jbProjectPayer
      .connect(caller)
      .pay(
        PROJECT_ID,
        ethToken,
        0,
        DECIMALS,
        ethers.constants.AddressZero,
        MIN_RETURNED_TOKENS,
        PREFER_CLAIMED_TOKENS,
        MEMO,
        METADATA,
        {
          value: AMOUNT,
        },
      );
    // ).to.not.be.reverted;
  });

  it(`Should pay funds towards project with a 9-decimals erc20 tokens`, async function () {
    const { jbProjectPayer, mockJbDirectory, mockJbTerminal, mockToken, addrs } = await setup();

    await mockJbTerminal.mock.decimalsForToken.withArgs(mockToken.address).returns(9);

    await mockJbDirectory.mock.primaryTerminalOf
      .withArgs(PROJECT_ID, mockToken.address)
      .returns(mockJbTerminal.address);

    await mockJbTerminal.mock.pay
      .withArgs(
        PROJECT_ID,
        AMOUNT,
        mockToken.address,
        BENEFICIARY,
        MIN_RETURNED_TOKENS,
        PREFER_CLAIMED_TOKENS,
        MEMO,
        METADATA,
      )
      .returns(0);

    const payer = addrs[0];

    mockToken.balanceOf.returnsAtCall(0, 0);

    mockToken.transferFrom
      .whenCalledWith(payer.address, jbProjectPayer.address, AMOUNT)
      .returns(true);

    mockToken.balanceOf.returnsAtCall(1, AMOUNT);

    mockToken.allowance.whenCalledWith(jbProjectPayer.address, mockJbTerminal.address).returns(0);

    mockToken.approve.whenCalledWith(mockJbTerminal.address, AMOUNT).returns(true);

    await expect(
      jbProjectPayer
        .connect(payer)
        .pay(
          PROJECT_ID,
          mockToken.address,
          AMOUNT,
          9,
          BENEFICIARY,
          MIN_RETURNED_TOKENS,
          PREFER_CLAIMED_TOKENS,
          MEMO,
          METADATA,
        ),
    ).to.not.be.reverted;
  });

  it(`Should pay funds towards project with a 9-decimals erc20 tokens with fee on transfer`, async function () {
    const { jbProjectPayer, mockJbDirectory, mockJbTerminal, mockToken, addrs } = await setup();

    const NET_AMOUNT = AMOUNT.sub(100);

    await mockJbTerminal.mock.decimalsForToken.withArgs(mockToken.address).returns(9);

    await mockJbDirectory.mock.primaryTerminalOf
      .withArgs(PROJECT_ID, mockToken.address)
      .returns(mockJbTerminal.address);

    await mockJbTerminal.mock.pay
      .withArgs(
        PROJECT_ID,
        NET_AMOUNT,
        mockToken.address,
        BENEFICIARY,
        MIN_RETURNED_TOKENS,
        PREFER_CLAIMED_TOKENS,
        MEMO,
        METADATA,
      )
      .returns(0);

    const payer = addrs[0];

    mockToken.balanceOf.returnsAtCall(0, 0);

    mockToken.transferFrom
      .whenCalledWith(payer.address, jbProjectPayer.address, AMOUNT)
      .returns(true);

    mockToken.balanceOf.returnsAtCall(1, NET_AMOUNT);

    mockToken.allowance.whenCalledWith(jbProjectPayer.address, mockJbTerminal.address).returns(0);

    mockToken.approve.whenCalledWith(mockJbTerminal.address, NET_AMOUNT).returns(true);

    await expect(
      jbProjectPayer
        .connect(payer)
        .pay(
          PROJECT_ID,
          mockToken.address,
          AMOUNT,
          9,
          BENEFICIARY,
          MIN_RETURNED_TOKENS,
          PREFER_CLAIMED_TOKENS,
          MEMO,
          METADATA,
        ),
    ).to.not.be.reverted;
  });

  it(`Should pay funds towards project using addToBalanceOf`, async function () {
    const { jbProjectPayer, mockJbDirectory, mockJbTerminal } = await setup();

    await mockJbDirectory.mock.primaryTerminalOf
      .withArgs(PROJECT_ID, ethToken)
      .returns(mockJbTerminal.address);

    // Eth payments should use 18 decimals.
    await mockJbTerminal.mock.decimalsForToken.withArgs(ethToken).returns(18);

    await mockJbTerminal.mock.addToBalanceOf
      .withArgs(PROJECT_ID, AMOUNT, ethToken, MEMO, METADATA)
      .returns();

    await expect(
      jbProjectPayer.addToBalanceOf(PROJECT_ID, ethToken, AMOUNT, DECIMALS, MEMO, METADATA, {
        value: AMOUNT,
      }),
    ).to.not.be.reverted;
  });

  it(`Should pay funds towards project using addToBalanceOf with a 9-decimals erc20 tokens`, async function () {
    const { jbProjectPayer, mockJbDirectory, mockJbTerminal, mockToken, addrs } = await setup();

    await mockJbTerminal.mock.decimalsForToken.withArgs(mockToken.address).returns(9);

    await mockJbDirectory.mock.primaryTerminalOf
      .withArgs(PROJECT_ID, mockToken.address)
      .returns(mockJbTerminal.address);

    await mockJbTerminal.mock.addToBalanceOf
      .withArgs(PROJECT_ID, AMOUNT, mockToken.address, MEMO, METADATA)
      .returns();

    const payer = addrs[0];
    mockToken.balanceOf.returnsAtCall(0, 0);

    mockToken.transferFrom
      .whenCalledWith(payer.address, jbProjectPayer.address, AMOUNT)
      .returns(true);

    mockToken.balanceOf.returnsAtCall(1, AMOUNT);

    mockToken.allowance.whenCalledWith(jbProjectPayer.address, mockJbTerminal.address).returns(0);

    mockToken.approve.whenCalledWith(mockJbTerminal.address, AMOUNT).returns(true);

    await expect(
      jbProjectPayer
        .connect(payer)
        .addToBalanceOf(PROJECT_ID, mockToken.address, AMOUNT, 9, MEMO, METADATA),
    ).to.not.be.reverted;
  });

  it(`Fallback function should pay funds towards default project`, async function () {
    const { jbProjectPayer, mockJbDirectory, mockJbTerminal, addrs } = await setup();

    let caller = addrs[0];

    // fallback uses 18 decimals.
    await mockJbTerminal.mock.decimalsForToken.withArgs(ethToken).returns(18);

    await mockJbDirectory.mock.primaryTerminalOf
      .withArgs(INITIAL_PROJECT_ID, ethToken)
      .returns(mockJbTerminal.address);

    await mockJbTerminal.mock.pay
      .withArgs(
        INITIAL_PROJECT_ID,
        AMOUNT,
        ethToken,
        INITIAL_BENEFICIARY,
        0,
        INITIAL_PREFER_CLAIMED_TOKENS,
        INITIAL_MEMO,
        INITIAL_METADATA,
      )
      .returns(0);

    await expect(
      caller.sendTransaction({
        to: jbProjectPayer.address,
        value: AMOUNT,
      }),
    ).to.not.be.reverted;
  });

  it(`Fallback function should pay funds towards default project with no default beneficiary`, async function () {
    const { jbProjectPayer, mockJbDirectory, mockJbTerminal, owner, addrs } = await setup();

    let caller = addrs[0];

    // fallback uses 18 decimals.
    await mockJbTerminal.mock.decimalsForToken.withArgs(ethToken).returns(18);

    await mockJbDirectory.mock.primaryTerminalOf
      .withArgs(INITIAL_PROJECT_ID, ethToken)
      .returns(mockJbTerminal.address);

    // Set the default beneficiary to the zero address.

    await jbProjectPayer.connect(owner).setDefaultValues(
      INITIAL_PROJECT_ID,
      ethers.constants.AddressZero,
      INITIAL_PREFER_CLAIMED_TOKENS,
      INITIAL_MEMO,
      INITIAL_METADATA,
      false, // prefer add to balance
    );

    await mockJbTerminal.mock.pay
      .withArgs(
        INITIAL_PROJECT_ID,
        AMOUNT,
        ethToken,
        addrs[0].address,
        0,
        INITIAL_PREFER_CLAIMED_TOKENS,
        INITIAL_MEMO,
        INITIAL_METADATA,
      )
      .returns(0);

    await expect(
      caller.sendTransaction({
        to: jbProjectPayer.address,
        value: AMOUNT,
      }),
    ).to.not.be.reverted;
  });

  it(`Fallback function should pay ETH funds towards default project with addToBalance`, async function () {
    const { jbProjectPayer, mockJbDirectory, mockJbTerminal, owner, addrs } = await setup();

    let caller = addrs[0];

    // fallback uses 18 decimals.
    await mockJbTerminal.mock.decimalsForToken.withArgs(ethToken).returns(18);

    await mockJbDirectory.mock.primaryTerminalOf
      .withArgs(INITIAL_PROJECT_ID, ethToken)
      .returns(mockJbTerminal.address);

    // Set the default beneficiary to the zero address.

    await jbProjectPayer.connect(owner).setDefaultValues(
      INITIAL_PROJECT_ID,
      ethers.constants.AddressZero,
      INITIAL_PREFER_CLAIMED_TOKENS,
      INITIAL_MEMO,
      INITIAL_METADATA,
      true, // prefer add to balance
    );

    await mockJbTerminal.mock.addToBalanceOf
      .withArgs(INITIAL_PROJECT_ID, AMOUNT, ethToken, INITIAL_MEMO, INITIAL_METADATA)
      .returns();

    await expect(
      caller.sendTransaction({
        to: jbProjectPayer.address,
        value: AMOUNT,
      }),
    ).to.not.be.reverted;
  });

  it(`Can't pay if terminal not found`, async function () {
    const { jbProjectPayer, mockJbDirectory } = await setup();

    await mockJbDirectory.mock.primaryTerminalOf
      .withArgs(PROJECT_ID, ethToken)
      .returns(ethers.constants.AddressZero);

    await expect(
      jbProjectPayer.pay(
        PROJECT_ID,
        ethToken,
        0,
        DECIMALS,
        BENEFICIARY,
        MIN_RETURNED_TOKENS,
        PREFER_CLAIMED_TOKENS,
        MEMO,
        METADATA,
        {
          value: AMOUNT,
        },
      ),
    ).to.be.revertedWith(errors.TERMINAL_NOT_FOUND);
  });

  it(`Can't pay if terminal uses different number of decimals`, async function () {
    const { jbProjectPayer, mockJbDirectory, mockJbTerminal } = await setup();

    await mockJbDirectory.mock.primaryTerminalOf
      .withArgs(PROJECT_ID, ethToken)
      .returns(mockJbTerminal.address);

    await mockJbTerminal.mock.decimalsForToken.withArgs(ethToken).returns(10);

    await expect(
      jbProjectPayer.pay(
        PROJECT_ID,
        ethToken,
        0,
        18,
        BENEFICIARY,
        MIN_RETURNED_TOKENS,
        PREFER_CLAIMED_TOKENS,
        MEMO,
        METADATA,
        {
          value: AMOUNT,
        },
      ),
    ).to.be.revertedWith(errors.INCORRECT_DECIMAL_AMOUNT);
  });

  it(`Can't send value along with non-eth token`, async function () {
    const { jbProjectPayer, mockJbDirectory } = await setup();

    await expect(
      jbProjectPayer.pay(
        PROJECT_ID,
        ethers.constants.AddressZero,
        0,
        DECIMALS,
        BENEFICIARY,
        MIN_RETURNED_TOKENS,
        PREFER_CLAIMED_TOKENS,
        MEMO,
        METADATA,
        {
          value: AMOUNT,
        },
      ),
    ).to.be.revertedWith(errors.NO_MSG_VALUE_ALLOWED);
  });
});
