import { expect } from 'chai';
import { ethers } from 'hardhat';
import { BigNumber } from 'ethers';
import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/signers';
import * as helpers from '@nomicfoundation/hardhat-network-helpers';
import { getContractRecord } from '../../../scripts/lib/lib';
import { anyValue } from '@nomicfoundation/hardhat-chai-matchers/withArgs';

const testNetwork = 'goerli';

describe(`Deployer workflow tests (forked ${testNetwork})`, () => {
    
    const extensionDeploymentLogPath = `./deployments/${testNetwork}/extensions.json`;
    const platformDeploymentLogPath = `./deployments/${testNetwork}/platform.json`;

    const provider = ethers.provider;

    let deployer: SignerWithAddress;
    let accounts: SignerWithAddress[];

    let jbxDirectory: any;
    let jbxOperatorStore: any;
    let jbxProjects: any;

    let deployerProxy: any;

    // let tokenLiquidator: any;
    // let mixedPaymentSplitter: any;
    // let englishAuctionHouse: any;
    // let dutchAuctionHouse: any;

    before('Initialize accounts', async () => {
        [deployer, ...accounts] = await ethers.getSigners();

        await helpers.setBalance(deployer.address, ethers.utils.parseEther('10').toHexString());
        await helpers.setBalance(accounts[0].address, ethers.utils.parseEther('10').toHexString());
    });

    before('Connect juicebox contracts', async () => {
        const jbxDirectoryInfo = getContractRecord('JBDirectory', platformDeploymentLogPath, testNetwork);
        jbxDirectory = await ethers.getContractAt(jbxDirectoryInfo.abi, jbxDirectoryInfo.address);

        const jbxOperatorStoreInfo = getContractRecord('JBOperatorStore', platformDeploymentLogPath, testNetwork);
        jbxOperatorStore = await ethers.getContractAt(jbxOperatorStoreInfo.abi, jbxOperatorStoreInfo.address);

        const jbxProjectsInfo = getContractRecord('JBProjects', platformDeploymentLogPath, testNetwork);
        jbxProjects = await ethers.getContractAt(jbxProjectsInfo.abi, jbxProjectsInfo.address);
    });

    before('Connect extension contracts', async () => {
        const deployerProxyInfo = getContractRecord('DeployerProxy', extensionDeploymentLogPath, testNetwork); // NOTE: this path is relative to where tests are run from
        deployerProxy = await ethers.getContractAt(deployerProxyInfo.abi, deployerProxyInfo.address);
    });

    // TODO: v6 tests

    it('Deploy PaymentProcessor (v5)', async () => {
        const jbxProjectId = 2;
        const ignoreFailures = false;
        const defaultLiquidation = true;

        const tx = deployerProxy.connect(accounts[0]).deployPaymentProcessor(jbxDirectory.address, jbxOperatorStore.address, jbxProjects.address, jbxProjectId, ignoreFailures, defaultLiquidation);

        await expect(tx).to.emit(deployerProxy, 'Deployment').withArgs('PaymentProcessor', anyValue);
    });

    it('Deploy NFUToken (v4)', async () => {
        const owner = accounts[0].address;
        const name = 'Shared NFT';
        const symbol = 'SNFT';
        const baseUri = 'ipfs://contract-metadata';
        const contractUri = 'ipfs://contract-metadata';
        const jbxProjectId = 2;
        const maxSupply = 100;
        const unitPrice = ethers.utils.parseEther('0.0001');
        const mintAllowance = 10;

        const tx = deployerProxy.connect(accounts[0]).deployNFUToken(owner, name, symbol, baseUri, contractUri, jbxProjectId, jbxDirectory.address, maxSupply, unitPrice, mintAllowance);
        const receipt = await (await tx).wait();

        const tokenAddress = receipt.events.filter(e => e.event === 'Deployment' && e.args[0] === 'NFUToken')[0].args[1];

        await expect(tx).to.emit(deployerProxy, 'Deployment').withArgs('NFUToken', tokenAddress);
    });

    it('Deploy DutchAuction (v3)', async () => {
        const jbxProjectId = 2;
        const feeReceiver = ethers.constants.AddressZero;
        const feeRate = 500;
        const allowPublicAuctions = true;
        const periodDuration = 60 * 5;
        const owner = accounts[0].address;

        const tx = deployerProxy.connect(accounts[0]).deployDutchAuction(jbxProjectId, feeReceiver, feeRate, allowPublicAuctions, periodDuration, owner, jbxDirectory.address);

        await expect(tx).to.emit(deployerProxy, 'Deployment').withArgs('DutchAuctionHouse', anyValue);
    });

    it('Deploy EnglishAuction (v3)', async () => {
        const jbxProjectId = 2;
        const feeReceiver = ethers.constants.AddressZero;
        const feeRate = 500;
        const allowPublicAuctions = true;
        const owner = accounts[0].address;

        const tx = deployerProxy.connect(accounts[0]).deployEnglishAuction(jbxProjectId, feeReceiver, feeRate, allowPublicAuctions, owner, jbxDirectory.address);

        await expect(tx).to.emit(deployerProxy, 'Deployment').withArgs('EnglishAuctionHouse', anyValue);
    });

    it('Deploy MixedPaymentSplitter (v2)', async () => {
        const name = 'Payment Splitter'
        const payees = accounts.slice(0, 2).map(a => a.address);
        const projects: number[] = [];
        const shares = payees.map((v, i) => (i + 1) * 100_000);
        const owner = accounts[0].address;

        const tx = deployerProxy.connect(accounts[0]).deployMixedPaymentSplitter(name, payees, projects, shares, jbxDirectory.address, owner);

        await expect(tx).to.emit(deployerProxy, 'Deployment').withArgs('MixedPaymentSplitter', anyValue);
    });

    it('Deploy NFToken (v1)', async () => {
        const owner = accounts[0].address;
        const name = 'Shared NFT';
        const symbol = 'SNFT';
        const baseUri = 'ipfs://contract-metadata';
        const contractUri = 'ipfs://contract-metadata';
        const jbxProjectId = 2;
        const maxSupply = 100;
        const unitPrice = ethers.utils.parseEther('0.0001');
        const mintAllowance = 10;
        const mintPeriodStart = 0
        const mintPeriodEnd = 0;

        const tx = deployerProxy.connect(accounts[0]).deployNFToken(owner, name, symbol, baseUri, contractUri, jbxProjectId, jbxDirectory.address, maxSupply, unitPrice, mintAllowance, mintPeriodStart, mintPeriodEnd);

        await expect(tx).to.emit(deployerProxy, 'Deployment').withArgs('NFToken', anyValue);
    });
});
