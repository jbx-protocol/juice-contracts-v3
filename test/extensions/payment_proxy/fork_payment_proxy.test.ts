import { assert, expect } from 'chai';
import { BigNumber } from 'ethers';
import { ethers } from 'hardhat';
import fetch from 'node-fetch';
import { deployMockContract } from '@ethereum-waffle/mock-contract';
import * as helpers from '@nomicfoundation/hardhat-network-helpers';

import { packFundingCycleMetadata } from '../../helpers/utils';

import jbDirectory from '../../../artifacts/contracts/JBDirectory.sol/JBDirectory.json';
import jbOperatorStore from '../../../artifacts/contracts/JBOperatorStore.sol/JBOperatorStore.json';
import jbProjects from '../../../artifacts/contracts/JBProjects.sol/JBProjects.json';
import jbSplitsStore from '../../../artifacts/contracts/JBSplitsStore.sol/JBSplitsStore.json';
import jbPrices from '../../../artifacts/contracts/JBPrices.sol/JBPrices.json';
import jbPaymentTerminalStore from '../../../artifacts/contracts/JBSingleTokenPaymentTerminalStore.sol/JBSingleTokenPaymentTerminalStore.json';

async function abiFromAddress(
    contractAddress: string,
    etherscanKey: string,
    isProxy: boolean = false,
    proxySlot: string = '0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc'
): Promise<any> {
    if (isProxy) {
        const implementationAddress = (await ethers.getDefaultProvider().getStorageAt(contractAddress, proxySlot)).slice(-40);
        await sleep(10_000);
        return abiFromAddress(`0x${implementationAddress}`, etherscanKey, false);
    } else {
        const abi = await fetch(`https://api.etherscan.io/api?module=contract&action=getabi&address=${contractAddress}&apikey=${etherscanKey}`)
            .then((response: any) => response.json())
            .then((data: any) => JSON.parse(data['result']))
            .catch((error: any) => {
                console.log(`failed on ${contractAddress}`);
                console.log(error);
            });
        return abi;
    }
}

function sleep(ms = 1_000) {
    return new Promise((resolve) => setTimeout(resolve, ms));
}

function etherscanKey() {
    const index = Math.floor(Math.random() * 20);
    return process.env[`ETHERSCAN_API_KEY_${('00' + index).slice(-3)}`] || process.env.ETHERSCAN_API_KEY;
}

describe('Forked Payment Processor (fail errors, liquidate) Tests', () => {
    const projectId = 99;
    const TOKENS_ETH = '0x000000000000000000000000000000000000EEEe';
    const provider = ethers.provider;

    const hundredUsdc = 100_000_000;
    const hundredDai = ethers.utils.parseEther('1').mul(100);
    const smolEth = ethers.utils.parseEther('0.01');
    const oneEth = ethers.utils.parseEther('1');
    const tenEth = ethers.utils.parseEther('10');
    const hundredEth = ethers.utils.parseEther('100');

    let deployer;
    let paymentProcessor;
    let tokenLiquidator;

    let mockJbDirectory;
    let mockJbOperatorStore;
    let mockJbProjects;
    let mockJBPaymentTerminalStore;

    let ethTerminal;
    let wethTerminal;
    let daiTerminal;
    let usdcTerminal;

    let uniswapRouter;
    let dai;
    let weth;
    let usdc;
    let torn;

    before('Attach to DeFi contracts', async () => {
        const uniswapRouterAddress = '0xE592427A0AEce92De3Edee1F18E0157C05861564';
        const wethAddress = '0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2';
        const daiAddress = '0x6b175474e89094c44da98b954eedeac495271d0f';
        const usdcAddress = '0xa0b86991c6218b36c1d19d4a2e9eb0ce3606eb48';
        const tornAddress = '0x77777feddddffc19ff86db637967013e6c6a116c';

        const uniswapRouterAbi = await abiFromAddress(uniswapRouterAddress, etherscanKey());
        uniswapRouter = await ethers.getContractAt(uniswapRouterAbi, uniswapRouterAddress);

        const wethAbi = await abiFromAddress(wethAddress, etherscanKey());
        weth = await ethers.getContractAt(wethAbi, wethAddress);

        const daiAbi = await abiFromAddress(daiAddress, etherscanKey());
        dai = await ethers.getContractAt(daiAbi, daiAddress);

        const usdcAbi = await abiFromAddress(usdcAddress, etherscanKey(), true, '0x7050c9e0f4ca769c69bd3a8ef740bc37934f8e2c036e5a723fd8ee048ed3f8c3');
        usdc = await ethers.getContractAt(usdcAbi, usdcAddress);

        const tornAbi = await abiFromAddress(tornAddress, etherscanKey());
        torn = await ethers.getContractAt(tornAbi, tornAddress);
    });

    before('Set up initial token positions', async () => {
        const deployerAddress = '0x8a97426C1a720a45B8d69E974631f01f1168232B';
        await helpers.impersonateAccount(deployerAddress);
        deployer = await ethers.getSigner(deployerAddress);
        await helpers.setBalance(deployerAddress, hundredEth.toHexString());

        let tx = await weth.connect(deployer).deposit({ value: tenEth });
        await tx.wait();

        assert(tenEth.eq(await weth.balanceOf(deployer.address)));

        const daiSwapParams = {
            tokenIn: weth.address,
            tokenOut: dai.address,
            fee: 3000,
            recipient: deployer.address,
            deadline: Math.floor(Date.now() / 1000 + 20),
            amountIn: oneEth,
            amountOutMinimum: 1,
            sqrtPriceLimitX96: 0
        };

        tx = await weth.connect(deployer).approve(uniswapRouter.address, oneEth);
        await tx.wait();

        tx = await uniswapRouter.connect(deployer).exactInputSingle(daiSwapParams);
        await tx.wait();

        assert(((await dai.balanceOf(deployer.address)) as BigNumber).gt(100));

        const usdcSwapParams = {
            tokenIn: weth.address,
            tokenOut: usdc.address,
            fee: 3000,
            recipient: deployer.address,
            deadline: Math.floor(Date.now() / 1000 + 20),
            amountIn: oneEth,
            amountOutMinimum: 1,
            sqrtPriceLimitX96: 0
        };

        tx = await weth.connect(deployer).approve(uniswapRouter.address, oneEth);
        await tx.wait();

        tx = await uniswapRouter.connect(deployer).exactInputSingle(usdcSwapParams);
        await tx.wait();

        assert(((await usdc.balanceOf(deployer.address)) as BigNumber).gt(100));

        const tornSwapParams = {
            tokenIn: weth.address,
            tokenOut: torn.address,
            fee: 3000,
            recipient: deployer.address,
            deadline: Math.floor(Date.now() / 1000 + 20),
            amountIn: oneEth,
            amountOutMinimum: 1,
            sqrtPriceLimitX96: 0
        };

        tx = await weth.connect(deployer).approve(uniswapRouter.address, oneEth);
        await tx.wait();

        tx = await uniswapRouter.connect(deployer).exactInputSingle(tornSwapParams);
        await tx.wait();

        assert(((await torn.balanceOf(deployer.address)) as BigNumber).gt(100));
    });

    before('Deploy/mock core JBX components', async () => {
        const CURRENCY_ETH = 1;
        const CURRENCY_USD = 2;

        [mockJbDirectory, mockJbOperatorStore, mockJbProjects, mockJBPaymentTerminalStore] = await Promise.all([
            deployMockContract(deployer, jbDirectory.abi),
            deployMockContract(deployer, jbOperatorStore.abi),
            deployMockContract(deployer, jbProjects.abi),
            deployMockContract(deployer, jbPaymentTerminalStore.abi)
        ]);

        const [mockJbSplitsStore, mockJbPrices] = await Promise.all([deployMockContract(deployer, jbSplitsStore.abi), deployMockContract(deployer, jbPrices.abi)]);

        const jbTerminalFactory = await ethers.getContractFactory('contracts/JBETHPaymentTerminal.sol:JBETHPaymentTerminal', deployer);

        ethTerminal = await jbTerminalFactory
            .connect(deployer)
            .deploy(
                CURRENCY_ETH,
                mockJbOperatorStore.address,
                mockJbProjects.address,
                mockJbDirectory.address,
                mockJbSplitsStore.address,
                mockJbPrices.address,
                mockJBPaymentTerminalStore.address,
                deployer.address
            );

        const jbErc20TerminalFactory = await ethers.getContractFactory('contracts/JBERC20PaymentTerminal.sol:JBERC20PaymentTerminal', deployer);

        wethTerminal = await jbErc20TerminalFactory
            .connect(deployer)
            .deploy(
                weth.address,
                CURRENCY_ETH,
                CURRENCY_ETH,
                1,
                mockJbOperatorStore.address,
                mockJbProjects.address,
                mockJbDirectory.address,
                mockJbSplitsStore.address,
                mockJbPrices.address,
                mockJBPaymentTerminalStore.address,
                deployer.address
            );

        daiTerminal = await jbErc20TerminalFactory
            .connect(deployer)
            .deploy(
                dai.address,
                CURRENCY_USD,
                CURRENCY_USD,
                1,
                mockJbOperatorStore.address,
                mockJbProjects.address,
                mockJbDirectory.address,
                mockJbSplitsStore.address,
                mockJbPrices.address,
                mockJBPaymentTerminalStore.address,
                deployer.address
            );

        usdcTerminal = await jbErc20TerminalFactory
            .connect(deployer)
            .deploy(
                usdc.address,
                CURRENCY_USD,
                CURRENCY_USD,
                1,
                mockJbOperatorStore.address,
                mockJbProjects.address,
                mockJbDirectory.address,
                mockJbSplitsStore.address,
                mockJbPrices.address,
                mockJBPaymentTerminalStore.address,
                deployer.address
            );
    });

    before('Deploy test target', async () => {
        const tokenLiquidatorFactory = await ethers.getContractFactory('TokenLiquidator');
        tokenLiquidator = await tokenLiquidatorFactory
            .connect(deployer)
            .deploy(mockJbDirectory.address, mockJbOperatorStore.address, mockJbProjects.address, 500, 3000);

        const paymentProcessorFactory = await ethers.getContractFactory('PaymentProcessor');
        paymentProcessor = await paymentProcessorFactory.connect(deployer).deploy(
            mockJbDirectory.address,
            mockJbOperatorStore.address,
            mockJbProjects.address,
            tokenLiquidator.address,
            projectId,
            false, // ignoreFailures,
            true // defaultLiquidation
        );
        await paymentProcessor.deployed();
    });

    before('Configure JBX system', async () => {
        const MANAGE_PAYMENTS = 1002;

        const blockNum = await ethers.provider.getBlockNumber();
        const block = await ethers.provider.getBlock(blockNum);
        const timestamp = block.timestamp;

        const fundingCycle = {
            number: 1,
            configuration: timestamp,
            basedOn: timestamp,
            start: timestamp,
            duration: 0,
            weight: 0,
            discountRate: 0,
            ballot: ethers.constants.AddressZero,
            metadata: packFundingCycleMetadata({ holdFees: true })
        };

        await mockJBPaymentTerminalStore.mock.recordPaymentFrom.returns(
            fundingCycle,
            0, // number of tokens to mint, requires more mocking: IJBController(directory.controllerOf(_projectId)).mintTokensOf
            [],
            ''
        );

        await mockJBPaymentTerminalStore.mock.recordDistributionFor.returns(fundingCycle, 10);
        await mockJBPaymentTerminalStore.mock.recordAddedBalanceFor.returns();

        await mockJbDirectory.mock.isTerminalOf.withArgs(projectId, ethTerminal.address).returns(true);
        await mockJbDirectory.mock.isTerminalOf.withArgs(projectId, wethTerminal.address).returns(true);
        await mockJbDirectory.mock.isTerminalOf.withArgs(projectId, daiTerminal.address).returns(true);
        await mockJbDirectory.mock.isTerminalOf.withArgs(projectId, usdcTerminal.address).returns(true);
        await mockJbDirectory.mock.controllerOf.withArgs(projectId).returns(deployer.address);
        await mockJbDirectory.mock.controllerOf.withArgs(1).returns(deployer.address);
        await mockJbDirectory.mock.primaryTerminalOf.withArgs(projectId, TOKENS_ETH).returns(ethTerminal.address);
        await mockJbDirectory.mock.primaryTerminalOf.withArgs(projectId, weth.address).returns(wethTerminal.address);
        await mockJbDirectory.mock.primaryTerminalOf.withArgs(projectId, dai.address).returns(daiTerminal.address);
        await mockJbDirectory.mock.primaryTerminalOf.withArgs(projectId, usdc.address).returns(usdcTerminal.address);

        await mockJbProjects.mock.ownerOf.withArgs(projectId).returns(deployer.address);
        await mockJbProjects.mock.ownerOf.withArgs(1).returns(deployer.address);

        await mockJbOperatorStore.mock.hasPermission.withArgs(deployer.address, deployer.address, projectId, MANAGE_PAYMENTS).returns(true);
        await mockJbOperatorStore.mock.hasPermission.withArgs(deployer.address, deployer.address, 1, MANAGE_PAYMENTS).returns(true);

        await paymentProcessor.connect(deployer).setTokenPreferences(weth.address, true, false);
        await paymentProcessor.connect(deployer).setTokenPreferences(dai.address, true, false);
        await paymentProcessor.connect(deployer).setTokenPreferences(usdc.address, true, true);

        await tokenLiquidator.connect(deployer).blockToken(torn.address);
    });

    it('Receive direct payment in eth, forward it to a terminal', async () => {
        const initialBalance = await provider.getBalance(ethTerminal.address);

        await expect(deployer.sendTransaction({ to: paymentProcessor.address, value: smolEth })).not.to.be.reverted;

        const endingBalance = await provider.getBalance(ethTerminal.address);
        expect(endingBalance).to.be.greaterThan(initialBalance);
    });

    it('Receive payment in DAI, forward it to terminal', async () => {
        let tx = await dai.connect(deployer).approve(paymentProcessor.address, oneEth.mul(1000));
        await tx.wait();

        const initialTerminalBalance = await dai.balanceOf(daiTerminal.address);

        await expect(paymentProcessor.connect(deployer)['processPayment(address,uint256,uint256,string,bytes)'](dai.address, hundredDai, 0, '', 0x0)).not.to.be
            .reverted;

        expect(await dai.balanceOf(daiTerminal.address)).to.be.greaterThan(initialTerminalBalance);
    });

    it('Receive payment in USDC for specific Eth, forward it to WETH terminal, refund remaining USDC', async () => {
        await mockJbDirectory.mock.isTerminalOf.withArgs(projectId, ethTerminal.address).returns(false);
        await mockJbDirectory.mock.primaryTerminalOf.withArgs(projectId, TOKENS_ETH).returns(ethers.constants.AddressZero);

        let tx = await usdc.connect(deployer).approve(paymentProcessor.address, hundredUsdc * 10);
        await tx.wait();

        const initialTerminalBalance = await weth.balanceOf(wethTerminal.address);
        const initialPayerBalance: BigNumber = await usdc.balanceOf(deployer.address);

        const payment = hundredUsdc * 2;
        await expect(paymentProcessor.connect(deployer)['processPayment(address,uint256,uint256,string,bytes)'](usdc.address, payment, smolEth, '', 0x0)).not.to.be
            .reverted;

        expect(await weth.balanceOf(wethTerminal.address)).to.be.greaterThan(initialTerminalBalance);
        expect(await usdc.balanceOf(deployer.address)).to.be.greaterThan(initialPayerBalance.sub(payment));

        await mockJbDirectory.mock.isTerminalOf.withArgs(projectId, ethTerminal.address).returns(true);
        await mockJbDirectory.mock.primaryTerminalOf.withArgs(projectId, TOKENS_ETH).returns(ethTerminal.address);
    });

    it('Receive payment in USDC, liquidate it, forward it to Eth terminal', async () => {
        let tx = await usdc.connect(deployer).approve(paymentProcessor.address, oneEth.mul(1000));
        await tx.wait();

        const initialBalance = await provider.getBalance(ethTerminal.address);

        await expect(paymentProcessor.connect(deployer)['processPayment(address,uint256,uint256,string,bytes)'](usdc.address, hundredUsdc, 0, '', 0x0)).not.to.be
            .reverted;

        expect(await provider.getBalance(ethTerminal.address)).to.be.greaterThan(initialBalance);
    });

    it('Receive payment in TORN, fail to liquidate it', async () => {
        let tx = await torn.connect(deployer).approve(paymentProcessor.address, oneEth.mul(10));
        await tx.wait();

        await expect(
            paymentProcessor.connect(deployer)['processPayment(address,uint256,uint256,string,bytes)'](torn.address, 10, 0, '', 0x0)
        ).to.be.revertedWithCustomError(tokenLiquidator, 'LIQUIDATION_FAILURE');
    });

    it('Liquidate USDC from EOA account, pay proceeds to Eth terminal', async () => {
        let tx = await usdc.connect(deployer).approve(tokenLiquidator.address, hundredUsdc * 10);
        await tx.wait();

        const initialBalance = await provider.getBalance(ethTerminal.address);

        await expect(tokenLiquidator.liquidateTokens(usdc.address, hundredUsdc, 0, projectId, deployer.address, '', '0x00')).not.to.be.reverted;

        expect(await provider.getBalance(ethTerminal.address)).to.be.greaterThan(initialBalance);
    });

    it('Liquidate USDC from EOA account, pay proceeds to terminal as WETH', async () => {
        await mockJbDirectory.mock.isTerminalOf.withArgs(projectId, ethTerminal.address).returns(false);
        await mockJbDirectory.mock.primaryTerminalOf.withArgs(projectId, TOKENS_ETH).returns(ethers.constants.AddressZero);

        let tx = await usdc.connect(deployer).approve(tokenLiquidator.address, hundredUsdc * 10);
        await tx.wait();

        const initialBalance = await weth.balanceOf(wethTerminal.address);

        await expect(tokenLiquidator.liquidateTokens(usdc.address, hundredUsdc, 0, projectId, deployer.address, '', '0x00')).not.to.be.reverted;

        expect(await weth.balanceOf(wethTerminal.address)).to.be.greaterThan(initialBalance);

        await mockJbDirectory.mock.isTerminalOf.withArgs(projectId, ethTerminal.address).returns(true);
        await mockJbDirectory.mock.primaryTerminalOf.withArgs(projectId, TOKENS_ETH).returns(ethTerminal.address);
    });
});
