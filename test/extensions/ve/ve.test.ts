import { expect } from 'chai';
import * as fs from 'fs';
import { ethers } from 'hardhat';
import * as hre from 'hardhat';
import { BigNumber } from 'ethers';
import { anyValue } from '@nomicfoundation/hardhat-chai-matchers/withArgs';
import * as helpers from '@nomicfoundation/hardhat-network-helpers';
import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/signers';

import { getContractRecord, getPlatformConstant } from '../../../scripts/lib/lib';

const testNetwork = 'goerli';

describe(`Vote escrow workflow tests (forked ${testNetwork})`, () => {
    const platformDeploymentLogPath = `./deployments/${testNetwork}/platform.json`;
    const eighteen = '1000000000000000000';
    const fundingCycleDuration = 10 * 60; // seconds
    const minLockDuration = 60 * 60 * 24 * 7;

    const JBCurrencies_ETH = getPlatformConstant('JBCurrencies_ETH', 1, platformDeploymentLogPath);
    const ethToken = getPlatformConstant('ethToken', '0x000000000000000000000000000000000000EEEe', platformDeploymentLogPath);

    const projectTokensPerEth = BigNumber.from('1000000').mul(eighteen); // 1M tokens/eth, 18 decimals
    const distributionLimitEth = ethers.utils.parseEther('0.5');

    let testAccounts = [];

    let jbDirectory;
    let jbOperatorStore;
    let jbProjects;

    let jbTokenStore;
    let jbController;
    let jbETHPaymentTerminal;

    let veDeployer;

    let projectId;
    let projectToken;
    let projectVeToken;

    before('Initialize accounts', async () => {
        const testAddresses = ['0xbeeF69b41A166A8696478F117cE92DbaC35250F4', '0xC38ace8d13c4EdBc0deD20803bcbA7B3497947BD', '0x715ec973818B1c262EF89A5957E3fE76c2f8C982', '0x5594464d6c278a049D4f55e8D3D9d127c0f4De0f'];

        const testBalance = ethers.utils.parseEther('10').toHexString();
        for await (const address of testAddresses) {
            await hre.network.provider.request({ method: 'hardhat_impersonateAccount', params: [address] });
            await hre.network.provider.send('hardhat_setBalance', [address, testBalance]);
            testAccounts.push(await ethers.getSigner(address));
            const balance = await ethers.provider.getBalance(address);
        }
    });

    before('Connect to platform', async () => {
        const jbDirectoryInfo = getContractRecord('JBDirectory', platformDeploymentLogPath, testNetwork);
        jbDirectory = await ethers.getContractAt(jbDirectoryInfo.abi, jbDirectoryInfo.address);

        const jbOperatorStoreInfo = getContractRecord('JBOperatorStore', platformDeploymentLogPath, testNetwork);
        jbOperatorStore = await ethers.getContractAt(jbOperatorStoreInfo.abi, jbOperatorStoreInfo.address);

        const jbProjectsInfo = getContractRecord('JBProjects', platformDeploymentLogPath, testNetwork);
        jbProjects = await ethers.getContractAt(jbProjectsInfo.abi, jbProjectsInfo.address);

        const jbTokenStoreInfo = getContractRecord('JBTokenStore', platformDeploymentLogPath, testNetwork);
        jbTokenStore = await ethers.getContractAt(jbTokenStoreInfo.abi, jbTokenStoreInfo.address);

        const jbControllerInfo = getContractRecord('JBController', platformDeploymentLogPath, testNetwork);
        jbController = await ethers.getContractAt(jbControllerInfo.abi, jbControllerInfo.address);

        const jbETHPaymentTerminalInfo = getContractRecord('JBETHPaymentTerminal', platformDeploymentLogPath, testNetwork);
        jbETHPaymentTerminal = await ethers.getContractAt(jbETHPaymentTerminalInfo.abi, jbETHPaymentTerminalInfo.address);
    });

    before('Deploy VE components', async () => {
        const deployer = testAccounts[0];

        const contractFactory = await hre.ethers.getContractFactory('VeNftDeployer', { libraries: {}, signer: deployer });
        veDeployer = await contractFactory.connect(deployer).deploy(jbProjects.address, jbOperatorStore.address);
        await veDeployer.deployed();
    });

    before('Deploy sample project', async () => {
        const projectOwner = testAccounts[1];

        let reserveTokenSplits = [];
        let payoutSplits = [];

        const primaryBeneficiary = projectOwner.address;

        payoutSplits.push({
            preferClaimed: false,
            preferAddToBalance: false,
            percent: 1_000_000_000, // 100%
            projectId: 0,
            beneficiary: primaryBeneficiary,
            lockedUntil: 0,
            allocator: hre.ethers.constants.AddressZero,
        });

        const groupedSplits = [{ group: 1, splits: reserveTokenSplits }, { group: 2, splits: payoutSplits }];

        const domain = 0;
        const projectMetadataCID = '';
        const projectMetadata = [projectMetadataCID, domain];

        const referenceTime = (await ethers.provider.getBlock('latest')).timestamp;
        const protocolLaunchDate = referenceTime - 100;

        const duration = fundingCycleDuration; // seconds
        const weight = projectTokensPerEth;
        const discountRate = 0; // 0%
        const ballot = hre.ethers.constants.AddressZero;
        const fundingCycleData = [duration, weight, discountRate, ballot];

        const allowSetTerminals = true;
        const allowSetController = true;
        const pauseTransfer = true;
        const global = [allowSetTerminals, allowSetController, pauseTransfer];

        const reservedRate = 0;
        const redemptionRate = 10_000; // 100%
        const ballotRedemptionRate = 10_000;
        const pausePay = false;
        const pauseDistributions = false;
        const pauseRedeem = false;
        const pauseBurn = false;
        const allowMinting = false;
        const allowTerminalMigration = false;
        const allowControllerMigration = false;
        const holdFees = false;
        const preferClaimedTokenOverride = false;
        const useTotalOverflowForRedemptions = true;
        const useDataSourceForPay = false;
        const useDataSourceForRedeem = false;
        const dataSource = ethers.constants.AddressZero;
        const metadata = 0;
        const fundingCycleMetadata = [
            global,
            reservedRate,
            redemptionRate,
            ballotRedemptionRate,
            pausePay,
            pauseDistributions,
            pauseRedeem,
            pauseBurn,
            allowMinting,
            allowTerminalMigration,
            allowControllerMigration,
            holdFees,
            preferClaimedTokenOverride,
            useTotalOverflowForRedemptions,
            useDataSourceForPay,
            useDataSourceForRedeem,
            dataSource,
            metadata
        ];

        const fundAccessConstraints = [{
            terminal: jbETHPaymentTerminal.address,
            token: ethToken,
            distributionLimit: distributionLimitEth,
            distributionLimitCurrency: JBCurrencies_ETH,
            overflowAllowance: 0,
            overflowAllowanceCurrency: JBCurrencies_ETH
        }];

        const terminals = [jbETHPaymentTerminal.address];

        let tx, receipt;

        tx = await jbController.connect(projectOwner)['launchProjectFor(address,(string,uint256),(uint256,uint256,uint256,address),((bool,bool,bool),uint256,uint256,uint256,bool,bool,bool,bool,bool,bool,bool,bool,bool,bool,bool,bool,address,uint256),uint256,(uint256,(bool,bool,uint256,uint256,address,uint256,address)[])[],(address,address,uint256,uint256,uint256,uint256)[],address[],string)'](
            projectOwner.address,
            projectMetadata,
            fundingCycleData,
            fundingCycleMetadata,
            protocolLaunchDate,
            groupedSplits,
            fundAccessConstraints,
            terminals,
            ''
        );
        receipt = await tx.wait();
        let configuration, memo, owner;
        [configuration, projectId, memo, owner] = receipt.events.filter(e => e.event === 'LaunchProject')[0].args;

        tx = await jbTokenStore.connect(projectOwner).issueFor(projectId, 'Ah ah ah', 'AAA');
        receipt = await tx.wait();
        const issueEventArgs = receipt.events.filter(e => e.event === 'Issue')[0].args;

        const erc20abi = JSON.parse(fs.readFileSync('./test/extensions/erc20.abi.json').toString());
        projectToken = await hre.ethers.getContractAt(erc20abi, issueEventArgs['token']);
    });

    it('Test: deploy VE NFT', async function () {
        const projectOwner = testAccounts[1];

        let tx = await veDeployer.connect(projectOwner)
            .deployUriResolver(
                projectOwner.address,
                'ipfs://ve-nft-base-uri/',
                'ipfs://ve-nft-contract-uri/');
        let receipt = await tx.wait();
        let eventArgs = receipt.events.filter(e => e.event === 'DeployVeUriResolver')[0].args;
        const uriResolverAddress = eventArgs['resolver'];

        tx = await veDeployer.connect(projectOwner).deployNFT(
            projectId,
            've AAA Token',
            'veAAA',
            uriResolverAddress,
            jbTokenStore.address,
            jbOperatorStore.address,
            [minLockDuration, minLockDuration * 2, minLockDuration * 10],
            projectOwner.address
        );
        receipt = await tx.wait();
        eventArgs = receipt.events.filter(e => e.event === 'DeployVeNft')[0].args;
        const veAddress = eventArgs['jbVeNft'];

        const contractFactory = await hre.ethers.getContractFactory('JBVeNft');
        projectVeToken = await contractFactory.attach(veAddress);
    });

    it('Test: contribute to project', async function () {
        const projectContributor = testAccounts[2];
        const amount = ethers.utils.parseEther('0.5');

        const tx = await jbETHPaymentTerminal.connect(projectContributor).pay(projectId,
            amount,
            ethToken, // token
            projectContributor.address, // beneficiary
            1, // minReturnedTokens
            true, // preferClaimedTokens
            '', // memo
            '0x00', // metadata
            { value: amount });
        const receipt = await tx.wait();

        const projectTokenBalance = await projectToken.balanceOf(projectContributor.address);
        expect(projectTokenBalance).to.be.greaterThan(0);
    });

    it('Test: lock project tokens', async function () {
        const projectContributor = testAccounts[2];

        const projectTokenBalance = await projectToken.balanceOf(projectContributor.address);
        const lockAmount = projectTokenBalance.div(10);
        let referenceTime = (await ethers.provider.getBlock('latest')).timestamp;
        await projectToken.connect(projectContributor).approve(projectVeToken.address, lockAmount);
        let tx = await projectVeToken.connect(projectContributor).lock(
            projectContributor.address,
            lockAmount,
            minLockDuration,
            projectContributor.address,
            true, // _useJbToken,
            false // _allowPublicExtension
        );
        let receipt = await tx.wait();

        let eventArgs = receipt.events.filter(e => e.event === 'Lock')[0].args;

        expect(eventArgs['tokenId']).to.equal(1);
        expect(eventArgs['lockedUntil']).to.equal(BigNumber.from(referenceTime).add(minLockDuration).div(minLockDuration).mul(minLockDuration));

        referenceTime = (await ethers.provider.getBlock('latest')).timestamp;
        await projectToken.connect(projectContributor).approve(projectVeToken.address, lockAmount);
        tx = await projectVeToken.connect(projectContributor).lock(
            projectContributor.address,
            lockAmount,
            minLockDuration * 10,
            projectContributor.address,
            true, // _useJbToken,
            false // _allowPublicExtension
        );
        receipt = await tx.wait();

        eventArgs = receipt.events.filter(e => e.event === 'Lock')[0].args;
        expect(eventArgs['tokenId']).to.equal(2);

        await projectToken.connect(projectContributor).approve(projectVeToken.address, lockAmount);
        tx = projectVeToken.connect(projectContributor).lock(
            projectContributor.address,
            lockAmount,
            minLockDuration * 3,
            projectContributor.address,
            true, // _useJbToken,
            false // _allowPublicExtension
        );
        await expect(tx).to.be.revertedWithCustomError(projectVeToken, 'INVALID_LOCK_DURATION');
    });

    it('Test: lock project tokens', async function () {
        const projectContributor = testAccounts[2];
        const nonContributor = testAccounts[3];

        let referenceTime = (await ethers.provider.getBlock('latest')).timestamp;
        await expect(projectVeToken.connect(projectContributor).unlock([{ tokenId: 1, beneficiary: projectContributor.address }]))
            .to.be.reverted;

        referenceTime = (await ethers.provider.getBlock('latest')).timestamp;
        await ethers.provider.send("evm_setNextBlockTimestamp", [referenceTime + minLockDuration + 10]);
        await ethers.provider.send("evm_mine", []);

        await expect(projectVeToken.connect(nonContributor).unlock([{ tokenId: 1, beneficiary: projectContributor.address }]))
            .to.be.reverted;

        await expect(projectVeToken.connect(projectContributor).unlock([{ tokenId: 1, beneficiary: projectContributor.address }]))
            .not.to.be.reverted;
    });
});

// npx hardhat test test/extensions/ve/ve.test.ts
