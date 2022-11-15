import { expect } from 'chai';
import { ethers } from 'hardhat';
import { smock } from '@defi-wonderland/smock';

import jbDirectory from '../../artifacts/contracts/JBDirectory.sol/JBDirectory.json';
import jbOperatorStore from '../../artifacts/contracts/JBOperatorStore.sol/JBOperatorStore.json';
import jbProjects from '../../artifacts/contracts/JBProjects.sol/JBProjects.json';

describe('RoleManager Tests', () => {
    const JBOperations_MANAGE_ROLES = 1002;
    let deployer;
    let accounts;
    let roleManager;

    let mockJbDirectory: any;
    let mockJbOperatorStore: any;
    let mockJbProjects: any

    let projectA = 1;
    let projectB = 3;
    let invalidProject = 2;

    before('Initialize accounts', async () => {
        [deployer, ...accounts] = await ethers.getSigners();
    });

    before('Setup JBX components', async () => {
        mockJbDirectory = await smock.fake(jbDirectory.abi);
        mockJbOperatorStore = await smock.fake(jbOperatorStore.abi);
        mockJbProjects = await smock.fake(jbProjects.abi);

        // project A
        mockJbDirectory.controllerOf.whenCalledWith(projectA).returns(accounts[0].address);

        mockJbOperatorStore.hasPermission.whenCalledWith(accounts[0].address, accounts[0].address, projectA, JBOperations_MANAGE_ROLES).returns(true);
        mockJbOperatorStore.hasPermission.whenCalledWith(accounts[0].address, accounts[0].address, 0, JBOperations_MANAGE_ROLES).returns(false);
        mockJbOperatorStore.hasPermission.whenCalledWith(deployer.address, accounts[0].address, projectA, JBOperations_MANAGE_ROLES).returns(false);
        mockJbOperatorStore.hasPermission.whenCalledWith(deployer.address, accounts[0].address, 0, JBOperations_MANAGE_ROLES).returns(true);
        mockJbOperatorStore.hasPermission.whenCalledWith(accounts[1].address, accounts[0].address, projectA, JBOperations_MANAGE_ROLES).returns(false);
        mockJbOperatorStore.hasPermission.whenCalledWith(accounts[1].address, accounts[0].address, 0, JBOperations_MANAGE_ROLES).returns(false);

        mockJbProjects.ownerOf.whenCalledWith(projectA).returns(accounts[0].address);

        // project B
        mockJbOperatorStore.hasPermission.whenCalledWith(deployer.address, accounts[1].address, 0, JBOperations_MANAGE_ROLES).returns(true);

        mockJbDirectory.controllerOf.whenCalledWith(projectB).returns(accounts[1].address);

        mockJbProjects.ownerOf.whenCalledWith(projectB).returns(accounts[0].address);
    });

    before('Initialize contracts', async () => {
        const roleManagerFactory = await ethers.getContractFactory('RoleManager');
        roleManager = await roleManagerFactory.connect(deployer).deploy(mockJbDirectory.address, mockJbOperatorStore.address, mockJbProjects.address, deployer.address);
        await roleManager.deployed();
    });

    it('addProjectRole: unauthorized account failure', async () => {
        await expect(roleManager.connect(accounts[1]).addProjectRole(projectA, 'FINANCE_MANAGER')).to.be.revertedWithCustomError(roleManager, 'UNAUTHORIZED');
    });

    it('addProjectRole: platform admin account', async () => {
        await expect(roleManager.connect(deployer).addProjectRole(projectA, 'FINANCE_MANAGER')).not.to.be.reverted;
    });

    it('addProjectRole: authorized account', async () => {
        await expect(roleManager.connect(accounts[0]).addProjectRole(projectA, 'TOKEN_MINTER')).not.to.be.reverted;
    });

    it('addProjectRole: duplicate role failure', async () => {
        await expect(roleManager.connect(accounts[0]).addProjectRole(projectA, 'FINANCE_MANAGER')).to.be.revertedWithCustomError(roleManager, 'DUPLICATE_ROLE');
    });

    it('removeProjectRole: unauthorized account failure', async () => {
        await expect(roleManager.connect(accounts[1]).removeProjectRole(projectA, 'FINANCE_MANAGER')).to.be.revertedWithCustomError(roleManager, 'UNAUTHORIZED');
    });

    it('removeProjectRole: platform admin account', async () => {
        await expect(roleManager.connect(deployer).removeProjectRole(projectA, 'FINANCE_MANAGER')).not.to.be.reverted;
    });

    it('removeProjectRole: invalid role', async () => {
        await expect(roleManager.connect(accounts[0]).removeProjectRole(projectA, 'FINANCE_MANAGER')).to.be.revertedWithCustomError(roleManager, 'INVALID_ROLE');
    });

    it('removeProjectRole: authorized account', async () => {
        await expect(roleManager.connect(accounts[0]).removeProjectRole(projectA, 'TOKEN_MINTER')).not.to.be.reverted;
    });

    it('listProjectRoles()', async () => {
        await expect(roleManager.connect(accounts[0]).addProjectRole(projectA, 'FINANCE_MANAGER')).not.to.be.reverted;
        await expect(roleManager.connect(accounts[0]).addProjectRole(projectA, 'TOKEN_MINTER')).not.to.be.reverted;
        await expect(roleManager.connect(accounts[0]).addProjectRole(projectA, 'CONTENT_MANAGER')).not.to.be.reverted;

        await expect(roleManager.connect(deployer).addProjectRole(3, 'FINANCE_MANAGER')).not.to.be.reverted;

        const roles: string[] = await roleManager.listProjectRoles(projectA);
        expect(roles.length).to.equal(3);
        expect(roles.includes('FINANCE_MANAGER')).to.equal(true);
        expect(roles.includes('TOKEN_MINTER')).to.equal(true);
        expect(roles.includes('CONTENT_MANAGER')).to.equal(true);
    });

    it('grantProjectRole()', async () => {
        await expect(roleManager.connect(accounts[0]).grantProjectRole(projectA, accounts[2].address, 'FINANCE_MANAGER')).not.to.be.reverted;
        await expect(roleManager.connect(accounts[0]).grantProjectRole(projectA, accounts[2].address, 'FINANCE_MANAGER')).not.to.be.reverted;
        await expect(roleManager.connect(accounts[0]).grantProjectRole(projectA, accounts[2].address, 'TOKEN_MINTER')).not.to.be.reverted;
        await expect(roleManager.connect(accounts[0]).grantProjectRole(projectA, accounts[3].address, 'FINANCE_MANAGER')).not.to.be.reverted;

        await expect(roleManager.connect(accounts[1]).grantProjectRole(projectA, accounts[1].address, 'FINANCE_MANAGER')).to.be.reverted;

        await expect(roleManager.connect(accounts[0]).grantProjectRole(projectA, accounts[2].address, 'UNDEFINED_ROLE')).to.be.reverted;
    });

    it('getUserRoles()', async () => {
        let userRoles: string[] = await roleManager.getUserRoles(projectA, accounts[2].address);
        expect(userRoles.length).to.equal(2);

        userRoles = await roleManager.getUserRoles(projectA, accounts[1].address);
        expect(userRoles.length).to.equal(0);

        userRoles = await roleManager.getUserRoles(2, accounts[1].address);
        expect(userRoles.length).to.equal(0);
    });

    it('getProjectUsers()', async () => {
        let users: string[] = await roleManager.getProjectUsers(projectA, 'FINANCE_MANAGER');
        expect(users.length).to.equal(2);

        users = await roleManager.getProjectUsers(projectA, 'TOKEN_MINTER');
        expect(users.length).to.equal(1);

        users = await roleManager.getProjectUsers(projectB, 'FINANCE_MANAGER');
        expect(users.length).to.equal(0);

        await expect(roleManager.getProjectUsers(invalidProject, 'FINANCE_MANAGER')).to.be.revertedWithCustomError(roleManager, 'INVALID_ROLE');
        await expect(roleManager.getProjectUsers(projectA, 'UNDEFINED_ROLE')).to.be.revertedWithCustomError(roleManager, 'INVALID_ROLE');
    });

    it('confirmUserRole()', async () => {
        expect(await roleManager.confirmUserRole(projectA, accounts[2].address, 'TOKEN_MINTER')).to.equal(true);
        expect(await roleManager.confirmUserRole(projectA, accounts[2].address, 'FINANCE_MANAGER')).to.equal(true);
        expect(await roleManager.confirmUserRole(projectA, accounts[1].address, 'FINANCE_MANAGER')).to.equal(false);

        await expect(roleManager.confirmUserRole(projectA, accounts[2].address, 'UNDEFINED_ROLE')).to.be.reverted;
        await expect(roleManager.confirmUserRole(2, accounts[2].address, 'FINANCE_MANAGER')).to.be.reverted;
    });

    it('revokeProjectRole()', async () => {
        await expect(roleManager.connect(accounts[0]).revokeProjectRole(projectA, accounts[1].address, 'FINANCE_MANAGER')).to.be.reverted;

        await expect(roleManager.connect(accounts[0]).revokeProjectRole(projectA, accounts[2].address, 'UNDEFINED_ROLE')).to.be.reverted;

        await expect(roleManager.connect(accounts[0]).revokeProjectRole(projectA, accounts[2].address, 'FINANCE_MANAGER')).not.to.be.reverted;
        await expect(roleManager.connect(accounts[0]).revokeProjectRole(projectA, accounts[2].address, 'TOKEN_MINTER')).not.to.be.reverted;
        await expect(roleManager.connect(accounts[0]).revokeProjectRole(projectA, accounts[3].address, 'FINANCE_MANAGER')).not.to.be.reverted;
    });
});