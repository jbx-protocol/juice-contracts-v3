import { expect } from 'chai';
import { ethers } from 'hardhat';
import { BigNumber } from 'ethers';
import { anyValue } from '@nomicfoundation/hardhat-chai-matchers/withArgs';
import * as helpers from '@nomicfoundation/hardhat-network-helpers';
import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/signers';

import { getContractRecord } from '../../../scripts/lib/lib';

const testNetwork = 'goerli';

describe(`Deployer workflow tests (forked ${testNetwork})`, () => {
    const extensionDeploymentLogPath = `./deployments/${testNetwork}/extensions.json`;
    const platformDeploymentLogPath = `./deployments/${testNetwork}/platform.json`;

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

    const defaultOperationFee = ethers.utils.parseEther('0.001');

    before('Initialize accounts', async () => {
        [deployer, ...accounts] = await ethers.getSigners();

        await helpers.setBalance(deployer.address, ethers.utils.parseEther('10').toHexString());
        await helpers.setBalance(accounts[0].address, ethers.utils.parseEther('10').toHexString());
    });

    before('Connect jbx contracts', async () => {
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

        const tx = deployerProxy.connect(accounts[0])
            .deployNFToken(owner, name, symbol, baseUri, contractUri, jbxProjectId, jbxDirectory.address, maxSupply, unitPrice, mintAllowance, mintPeriodStart, mintPeriodEnd, { value: defaultOperationFee });

        await expect(tx).to.emit(deployerProxy, 'Deployment').withArgs('NFToken', anyValue);
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

    it('Deploy EnglishAuction (v3)', async () => {
        const jbxProjectId = 2;
        const feeReceiver = ethers.constants.AddressZero;
        const feeRate = 500;
        const allowPublicAuctions = true;
        const owner = accounts[0].address;

        const tx = deployerProxy.connect(accounts[0]).deployEnglishAuction(jbxProjectId, feeReceiver, feeRate, allowPublicAuctions, owner, jbxDirectory.address);

        await expect(tx).to.emit(deployerProxy, 'Deployment').withArgs('EnglishAuctionHouse', anyValue);
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

    it('Deploy PaymentProcessor (v5)', async () => {
        const jbxProjectId = 2;
        const ignoreFailures = false;
        const defaultLiquidation = true;

        const tx = deployerProxy.connect(accounts[0])
            .deployPaymentProcessor(jbxDirectory.address, jbxOperatorStore.address, jbxProjects.address, jbxProjectId, ignoreFailures, defaultLiquidation);

        await expect(tx).to.emit(deployerProxy, 'Deployment').withArgs('PaymentProcessor', anyValue);
    });

    it('Deploy NFTRewardDataSourceDelegate/TieredPriceResolver (v6)', async () => {
        const contributionToken = '0x000000000000000000000000000000000000EEEe'; // JBTokens.ETH
        const mintCap = BigNumber.from('1000000000000000');
        const userMintCap = BigNumber.from('1000000000000000');
        const rewardTiers = [
            {
                contributionFloor: ethers.utils.parseEther('0.0001'),
                idCeiling: 1000,
                remainingAllowance: 1000
            },
            {
                contributionFloor: ethers.utils.parseEther('0.001'),
                idCeiling: 2000,
                remainingAllowance: 1000
            },
            {
                contributionFloor: ethers.utils.parseEther('0.01'),
                idCeiling: 3000,
                remainingAllowance: 1000
            },
            {
                contributionFloor: ethers.utils.parseEther('0.1'),
                idCeiling: 4000,
                remainingAllowance: 1000
            },
            {
                contributionFloor: ethers.utils.parseEther('1'),
                idCeiling: 5000,
                remainingAllowance: 1000
            }
        ];

        let tx = await deployerProxy.connect(accounts[0]).deployTieredPriceResolver(contributionToken, mintCap, userMintCap, rewardTiers);
        let receipt = await tx.wait();
        let eventArgs = receipt.events.filter(e => e.event === 'Deployment')[0].args;
        expect(eventArgs[0]).to.equal('TieredPriceResolver');
        const priceResolverAddress = eventArgs[1];

        const uri = 'ipfs://token_base_uri';
        tx = await deployerProxy.connect(accounts[0]).deployTieredTokenUriResolver(uri, rewardTiers.map(t => t.idCeiling));
        receipt = await tx.wait();
        eventArgs = receipt.events.filter(e => e.event === 'Deployment')[0].args;
        expect(eventArgs[0]).to.equal('TieredTokenUriResolver');
        const uriResolverAddress = eventArgs[1];

        const projectId = 2;
        const maxSupply = BigNumber.from('1000000000000000');
        const minContribution = {
            token: contributionToken,
            value: ethers.utils.parseEther('0.0001'),
            decimals: 18,
            currency: 1 // JBCurrencies.ETH
        };
        const name = '';
        const symbol = 'NFT';
        const tokenUriResolverAddress = uriResolverAddress;
        const contractMetadataUri = 'ipfs://contract_metadata';
        const admin = deployer.address;
        const priceResolver = priceResolverAddress;

        tx = await deployerProxy.connect(accounts[0]).deployNFTRewardDataSource(projectId, jbxDirectory.address, maxSupply, minContribution, name, symbol, uri, tokenUriResolverAddress, contractMetadataUri, admin, priceResolver);
        receipt = await tx.wait();
        eventArgs = receipt.events.filter(e => e.event === 'Deployment')[0].args;
        expect(eventArgs[0]).to.equal('NFTRewardDataSourceDelegate');
    });

    it('Deploy NFTRewardDataSourceDelegate/OpenTieredPriceResolver (v6)', async () => {
        const contributionToken = '0x000000000000000000000000000000000000EEEe'; // JBTokens.ETH
        const rewardTiers = [
            { contributionFloor: ethers.utils.parseEther('0.0001') },
            { contributionFloor: ethers.utils.parseEther('0.001') },
            { contributionFloor: ethers.utils.parseEther('0.01') },
            { contributionFloor: ethers.utils.parseEther('0.1') },
            { contributionFloor: ethers.utils.parseEther('1') }
        ];

        let tx = await deployerProxy.connect(accounts[0]).deployOpenTieredPriceResolver(contributionToken, rewardTiers);
        let receipt = await tx.wait();
        let eventArgs = receipt.events.filter(e => e.event === 'Deployment')[0].args;
        expect(eventArgs[0]).to.equal('OpenTieredPriceResolver');


        tx = await deployerProxy.connect(accounts[0]).deployOpenTieredTokenUriResolver('ipfs://resolver_base_uri');
        receipt = await tx.wait();
        eventArgs = receipt.events.filter(e => e.event === 'Deployment')[0].args;
        expect(eventArgs[0]).to.equal('OpenTieredTokenUriResolver');

        const projectId = 2;
        const maxSupply = BigNumber.from('1000000000000000');
        const minContribution = {
            token: contributionToken,
            value: ethers.utils.parseEther('0.0001'),
            decimals: 18,
            currency: 1 // JBCurrencies.ETH
        };
        const name = '';
        const symbol = 'NFT';
        const uri = 'ipfs://token_base_uri';
        const tokenUriResolverAddress = ethers.constants.AddressZero;
        const contractMetadataUri = 'ipfs://contract_metadata';
        const admin = deployer.address;
        const priceResolver = eventArgs[1];

        tx = await deployerProxy.connect(accounts[0]).deployNFTRewardDataSource(projectId, jbxDirectory.address, maxSupply, minContribution, name, symbol, uri, tokenUriResolverAddress, contractMetadataUri, admin, priceResolver);
        receipt = await tx.wait();
        eventArgs = receipt.events.filter(e => e.event === 'Deployment')[0].args;
        expect(eventArgs[0]).to.equal('NFTRewardDataSourceDelegate');
    });

    // TODO: v7 tests
});
