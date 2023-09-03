import { expect } from 'chai';
import { ethers, network, config } from 'hardhat';
import '@metamask/eth-sig-util';

import { makePackedPermissions } from '../helpers/utils';
import errors from '../helpers/errors.json';
import { signTypedData } from '@metamask/eth-sig-util';

describe.only('JBOperatorStore::setOperator712(...)', function () {
  const DOMAIN = 1;
  const PERMISSION_INDEXES_EMPTY = [];
  const PERMISSION_INDEXES_1 = [1, 2, 3];
  const PERMISSION_INDEXES_2 = [4, 5, 6];
  const PERMISSION_INDEXES_OUT_OF_BOUND = [1, 2, 256];

  async function setup() {
    let [deployer, projectOwner, ...addrs] = await ethers.getSigners();

    let jbOperatorStoreFactory = await ethers.getContractFactory('JBOperatorStore3_2');
    let jbOperatorStore = await jbOperatorStoreFactory.deploy();

    return {
      projectOwner,
      deployer,
      addrs,
      jbOperatorStore,
    };
  }

  async function setOperatorAndValidateEvent(
    jbOperatorStore,
    operator,
    account,
    domain,
    permissionIndexes,
    packedPermissionIndexes,
  ) {
    // let chainId = network.config.chainId;
    const accounts = config.networks.hardhat.accounts;
    const index = 0; // first wallet, increment for next wallets
    const wallet = ethers.Wallet.fromMnemonic(accounts.mnemonic, accounts.path + `/${index}`);

    let signedData = signTypedData({
      privateKey: ethers.BigNumber.from(wallet.privateKey).toBigInt(),
      data: {
        domain: {
          chainId: network.config.chainId,
          name: "JBOperatorStore",
          verifyingContract: jbOperatorStore.address,
          version: "1",

        },
        types: {
          EIP712Domain: [
            { name: 'name', type: 'string' },
            { name: 'version', type: 'string' },
            { name: 'chainId', type: 'uint256' },
            { name: 'verifyingContract', type: 'address' }
          ],
          JuiceboxPermissions: [
            { name: 'permission', type: 'Permission' },
            { name: 'nonce', type: 'uint256' },
          ],
          Permission: [
            { name: 'operator', type: 'address' },
            { name: 'domain', type: 'uint256' },
            { name: 'permissionIndexes', type: 'uint256[]' },
          ]
        },
        message: {
          permission: {
            operator: operator.address,
            domain: domain,
            permissionIndexes: permissionIndexes
          },
          nonce: 0,
        },
        primaryType: "JuiceboxPermissions"
      },
      version: "V4"
    })

    let signature = ethers.utils.splitSignature(signedData);

    const tx = await jbOperatorStore
      .connect(account)
      .setOperatorPermit(
        wallet.address,
        [
        /*operator=*/ operator.address,
        /*domain=*/ domain,
        /*permissionsIndexes=*/ permissionIndexes,
        ],
        0, // deadline
        signature.v,
        signature.r,
        signature.s,
      );


    await expect(tx)
      .to.emit(jbOperatorStore, 'SetOperator')
      .withArgs(
        operator.address,
        account.address,
        domain,
        permissionIndexes,
        packedPermissionIndexes,
      );

    expect(await jbOperatorStore.permissionsOf(operator.address, account.address, domain)).to.equal(
      packedPermissionIndexes,
    );
  }

  it('Set operator with no previous value, override it, and clear it', async function () {
    const { deployer, projectOwner, jbOperatorStore } = await setup();

    await setOperatorAndValidateEvent(
      jbOperatorStore,
      projectOwner,
      /*account=*/ deployer,
      DOMAIN,
      PERMISSION_INDEXES_1,
      makePackedPermissions(PERMISSION_INDEXES_1),
    );

    await setOperatorAndValidateEvent(
      jbOperatorStore,
      projectOwner,
      /*account=*/ deployer,
      DOMAIN,
      PERMISSION_INDEXES_2,
      makePackedPermissions(PERMISSION_INDEXES_2),
    );

    await setOperatorAndValidateEvent(
      jbOperatorStore,
      projectOwner,
      /*account=*/ deployer,
      DOMAIN,
      PERMISSION_INDEXES_EMPTY,
      makePackedPermissions(PERMISSION_INDEXES_EMPTY),
    );
  });

  it('Index out of bounds', async function () {
    const { deployer, projectOwner, jbOperatorStore } = await setup();
    let permissionIndexes = [1, 2, 256];

    await expect(
      jbOperatorStore
        .connect(deployer)
        .setOperator([projectOwner.address, DOMAIN, PERMISSION_INDEXES_OUT_OF_BOUND]),
    ).to.be.revertedWith(errors.PERMISSION_INDEX_OUT_OF_BOUNDS);
  });
});
