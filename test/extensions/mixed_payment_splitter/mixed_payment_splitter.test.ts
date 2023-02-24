import { expect } from 'chai';
import { ethers } from 'hardhat';
import { BigNumber } from 'ethers';
import { deployMockContract } from '@ethereum-waffle/mock-contract';
import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/signers';

import jbDirectory from '../../../artifacts/contracts/JBDirectory.sol/JBDirectory.json';
import jbTerminal from '../../../artifacts/contracts/abstract/JBPayoutRedemptionPaymentTerminal.sol/JBPayoutRedemptionPaymentTerminal.json';

describe('MixedPaymentSplitter full-subscription tests', () => {
    const jbxJbTokensEth = '0x000000000000000000000000000000000000EEEe';

    const projects = [2, 3, 4];
    const payees: string[] = [];
    const shares = [200_000, 100_000, 200_000, 200_000, 100_000, 200_000];

    let deployer: SignerWithAddress;
    let accounts: SignerWithAddress[];
    let directory: any;
    let mixedPaymentSplitterFactory: any;
    let mixedPaymentSplitter: any;
    let token: any;

    before(async () => {
        const name = 'example-splitter';

        [deployer, ...accounts] = await ethers.getSigners();
        payees.push(accounts[0].address);
        payees.push(accounts[1].address);
        payees.push(accounts[2].address);

        const tokenFactory = await ethers.getContractFactory('MockERC20', deployer);
        token = await tokenFactory.connect(deployer).deploy();
        await token.connect(deployer).mint(deployer.address, 2_000_000_000);

        directory = await deployMockContract(deployer, jbDirectory.abi);
        const terminalTwo = await deployMockContract(deployer, jbTerminal.abi);
        const terminalThree = await deployMockContract(deployer, jbTerminal.abi);
        const terminalFour = await deployMockContract(deployer, jbTerminal.abi);

        await terminalTwo.mock.addToBalanceOf.returns();
        await terminalThree.mock.addToBalanceOf.returns();
        await terminalFour.mock.addToBalanceOf.returns();

        await directory.mock.isTerminalOf.withArgs(projects[0], terminalTwo.address).returns(true);
        await directory.mock.isTerminalOf.withArgs(projects[1], terminalThree.address).returns(true);
        await directory.mock.isTerminalOf.withArgs(projects[2], terminalFour.address).returns(true);

        await directory.mock.primaryTerminalOf.withArgs(projects[0], jbxJbTokensEth).returns(terminalTwo.address);
        await directory.mock.primaryTerminalOf.withArgs(projects[1], jbxJbTokensEth).returns(terminalThree.address);
        await directory.mock.primaryTerminalOf.withArgs(projects[2], jbxJbTokensEth).returns(terminalFour.address);

        await directory.mock.primaryTerminalOf.withArgs(projects[0], token.address).returns(terminalTwo.address);
        await directory.mock.primaryTerminalOf.withArgs(projects[1], token.address).returns(terminalThree.address);
        await directory.mock.primaryTerminalOf.withArgs(projects[2], token.address).returns(ethers.constants.AddressZero);

        mixedPaymentSplitterFactory = await ethers.getContractFactory('MixedPaymentSplitter', { signer: deployer });
        mixedPaymentSplitter = await mixedPaymentSplitterFactory
            .connect(deployer)
            .deploy(name, payees, projects, shares, directory.address, deployer.address);
    });

    it('Pay into the splitter', async () => {
        await expect(accounts[0].sendTransaction({ to: mixedPaymentSplitter.address, value: ethers.utils.parseEther('1.0') }))
            .to.emit(mixedPaymentSplitter, 'PaymentReceived');

        await token.connect(deployer).transfer(mixedPaymentSplitter.address, 1_000_000_000);
    });

    it('Get pending Ether amount', async () => {
        const largeShare = ethers.utils.parseEther('1.0').mul(2000).div(10000);

        expect(await mixedPaymentSplitter['pending(address)'](accounts[0].address)).to.equal(largeShare.toString());
        expect(await mixedPaymentSplitter['pending(uint256)'](projects[0])).to.equal(largeShare.toString());
    });

    it('Get pending token amount', async () => {
        const largeShare = BigNumber.from(1_000_000_000).mul(200_000).div(1_000_000);
        const smallShare = BigNumber.from(1_000_000_000).mul(100_000).div(1_000_000);

        expect(await mixedPaymentSplitter['pending(address,address)'](token.address, accounts[0].address)).to.equal(largeShare.toString());
        expect(await mixedPaymentSplitter['pending(address,uint256)'](token.address, projects[0])).to.equal(largeShare.toString());
        expect(await mixedPaymentSplitter['pending(address,address)'](token.address, accounts[1].address)).to.equal(smallShare.toString());
        expect(await mixedPaymentSplitter['pending(address,uint256)'](token.address, projects[1])).to.equal(smallShare.toString());
        expect(await mixedPaymentSplitter['pending(address,address)'](token.address, accounts[2].address)).to.equal(largeShare.toString());
        expect(await mixedPaymentSplitter['pending(address,uint256)'](token.address, projects[2])).to.equal(largeShare.toString());
    });

    it('Distribute Ether payment', async () => {
        const largeShare = ethers.utils.parseEther('1.0').mul(200_000).div(1_000_000);

        await expect(mixedPaymentSplitter['distribute(address)'](accounts[0].address))
            .to.emit(mixedPaymentSplitter, 'PaymentReleased').withArgs(accounts[0].address, largeShare);
        await expect(mixedPaymentSplitter['distribute(uint256)'](projects[0]))
            .to.emit(mixedPaymentSplitter, 'ProjectPaymentReleased').withArgs(projects[0], largeShare);
    });

    it('Distribute Token payment', async () => {
        const largeShare = BigNumber.from(1_000_000_000).mul(200_000).div(1_000_000);

        await expect(mixedPaymentSplitter['distribute(address,address)'](token.address, accounts[0].address))
            .to.emit(mixedPaymentSplitter, 'TokenPaymentReleased').withArgs(token.address, accounts[0].address, largeShare);
        // await expect(mixedPaymentSplitter['distribute(address,uint256)'](token.address, projects[0]))
        //     .to.emit(mixedPaymentSplitter, 'TokenProjectPaymentReleased').withArgs(token.address, projects[0], largeShare);

        expect(await token.balanceOf(accounts[0].address)).to.equal(largeShare);
    });

    it('Fail to distribute Ether payment, no share', async () => {
        await expect(mixedPaymentSplitter['distribute(address)'](accounts[4].address))
            .to.be.revertedWithCustomError(mixedPaymentSplitter, 'NO_SHARE');

        await expect(mixedPaymentSplitter['distribute(uint256)'](5))
            .to.be.revertedWithCustomError(mixedPaymentSplitter, 'NO_SHARE');
    });

    it('Fail to distribute token payment, no share', async () => {
        await expect(mixedPaymentSplitter['distribute(address,address)'](token.address, accounts[4].address))
            .to.be.revertedWithCustomError(mixedPaymentSplitter, 'NO_SHARE');

        await expect(mixedPaymentSplitter['distribute(address,uint256)'](token.address, 5))
            .to.be.revertedWithCustomError(mixedPaymentSplitter, 'NO_SHARE');
    });

    it('Fail to distribute Ether payment, nothing due', async () => {
        await expect(mixedPaymentSplitter['distribute(address)'](accounts[0].address))
            .to.be.revertedWithCustomError(mixedPaymentSplitter, 'NOTHING_DUE');
        await expect(mixedPaymentSplitter['distribute(uint256)'](projects[0]))
            .to.be.revertedWithCustomError(mixedPaymentSplitter, 'NOTHING_DUE');
    });

    it('Fail to distribute token payment, nothing due', async () => { // TODO: needs actual terminal
        await expect(mixedPaymentSplitter['distribute(address,address)'](token.address, accounts[0].address))
            .to.be.revertedWithCustomError(mixedPaymentSplitter, 'NOTHING_DUE');
        // await expect(mixedPaymentSplitter['distribute(address,uint256)'](token.address, projects[0]))
        //     .to.be.revertedWithCustomError(mixedPaymentSplitter, 'NOTHING_DUE');
    });

    it('Pay into the splitter again', async () => {
        await expect(accounts[0].sendTransaction({ to: mixedPaymentSplitter.address, value: ethers.utils.parseEther('1.0') }))
            .to.emit(mixedPaymentSplitter, 'PaymentReceived');

        await token.connect(deployer).transfer(mixedPaymentSplitter.address, 1_000_000_000);
    });

    it('Fail to distribute token payment, payment failure', async () => {
        await directory.mock.primaryTerminalOf.withArgs(projects[2], jbxJbTokensEth).returns(ethers.constants.AddressZero);

        await expect(mixedPaymentSplitter['distribute(uint256)'](projects[2]))
            .to.be.revertedWithCustomError(mixedPaymentSplitter, 'PAYMENT_FAILURE');
    });

    it('Fail to distribute token payment, payment failure', async () => {
        await expect(mixedPaymentSplitter['distribute(address,uint256)'](token.address, projects[2]))
            .to.be.revertedWithCustomError(mixedPaymentSplitter, 'PAYMENT_FAILURE');
    });

    it('Fail creation, invalid payee, address', async () => {
        await expect(mixedPaymentSplitterFactory.connect(deployer).deploy('name', [ethers.constants.AddressZero], [], [100_000], directory.address, deployer.address))
            .to.be.revertedWith('INVALID_PAYEE()');
    });

    it('Fail creation, invalid payee, project', async () => {
        await expect(mixedPaymentSplitterFactory.connect(deployer).deploy('name', [], [0], [100_000], directory.address, deployer.address))
            .to.be.revertedWith('INVALID_PAYEE()');
    });

    it('Fail creation, invalid share, address', async () => {
        await expect(mixedPaymentSplitterFactory.connect(deployer).deploy('name', [deployer.address], [], [0], directory.address, deployer.address))
            .to.be.revertedWith('INVALID_SHARE()');
    });

    it('Fail creation, invalid share, project', async () => {
        const projectId = 99;

        await directory.mock.primaryTerminalOf.withArgs(projectId, jbxJbTokensEth).returns(deployer.address);

        await expect(mixedPaymentSplitterFactory.connect(deployer).deploy('name', [], [projectId], [0], directory.address, deployer.address))
            .to.be.revertedWith('INVALID_SHARE()');
    });

    it('Fail creation, missing terminal', async () => {
        const projectId = 99;

        await directory.mock.primaryTerminalOf.withArgs(projectId, jbxJbTokensEth).returns(ethers.constants.AddressZero);

        await expect(mixedPaymentSplitterFactory.connect(deployer).deploy('name', [], [projectId], [100_000], directory.address, deployer.address))
            .to.be.revertedWith('MISSING_PROJECT_TERMINAL()');
    });

    it('Fail creation, argument length', async () => {
        await expect(mixedPaymentSplitterFactory.connect(deployer).deploy('name', [], [99, 100], [], directory.address, deployer.address))
            .to.be.revertedWith('INVALID_LENGTH()');

        await expect(mixedPaymentSplitterFactory.connect(deployer).deploy('name', [], [99, 100], [100_000], directory.address, deployer.address))
            .to.be.revertedWith('INVALID_LENGTH()');

        await expect(mixedPaymentSplitterFactory.connect(deployer).deploy('name', [deployer.address], [99, 100], [100_000], directory.address, deployer.address))
            .to.be.revertedWith('INVALID_LENGTH()');

        await expect(mixedPaymentSplitterFactory.connect(deployer).deploy('name', [], [], [], directory.address, deployer.address))
            .to.be.revertedWith('INVALID_LENGTH()');

        await expect(mixedPaymentSplitterFactory.connect(deployer).deploy('name', [], [99], [100_000], ethers.constants.AddressZero, deployer.address))
            .to.be.revertedWith('INVALID_DIRECTORY()');
    });

    it('Fail to add payees', async () => {
        await expect(mixedPaymentSplitter.connect(accounts[0])['addPayee(address,uint256)'](accounts[0].address, 100_000)).to.be.revertedWith('Ownable: caller is not the owner');

        await expect(mixedPaymentSplitter.connect(deployer)['addPayee(address,uint256)'](accounts[0].address, 100_000)).to.be.revertedWithCustomError(mixedPaymentSplitter, 'INVALID_SHARE_TOTAL');
    });
});
