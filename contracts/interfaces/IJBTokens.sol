// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IJBFundingCycleStore} from './IJBFundingCycleStore.sol';
import {IJBProjects} from './IJBProjects.sol';
import {IJBERC20Token} from './IJBERC20Token.sol';

interface IJBTokens {
  event DeployERC20Token(
    uint256 indexed projectId,
    IJBERC20Token indexed token,
    string name,
    string symbol,
    address caller
  );

  event Mint(
    address indexed holder,
    uint256 indexed projectId,
    uint256 amount,
    bool tokensWereClaimed,
    address caller
  );

  event Burn(
    address indexed holder,
    uint256 indexed projectId,
    uint256 amount,
    uint256 initialCreditBalance,
    uint256 initialTokenBalance,
    address caller
  );

  event ClaimTokens(
    address indexed holder,
    uint256 indexed projectId,
    uint256 initialCreditBalance,
    uint256 amount,
    address beneficiary,
    address caller
  );

  event SetToken(uint256 indexed projectId, IJBERC20Token indexed newToken, address caller);

  event TransferCredits(
    address indexed holder,
    uint256 indexed projectId,
    address indexed recipient,
    uint256 amount,
    address caller
  );

  function tokenOf(uint256 projectId) external view returns (IJBERC20Token);

  function projectIdOf(IJBERC20Token token) external view returns (uint256);

  function projects() external view returns (IJBProjects);

  function rulesets() external view returns (IJBFundingCycleStore);

  function creditBalanceOf(address holder, uint256 projectId) external view returns (uint256);

  function totalCreditSupplyOf(uint256 projectId) external view returns (uint256);

  function totalSupplyOf(uint256 projectId) external view returns (uint256);

  function totalBalanceOf(address holder, uint256 projectId) external view returns (uint256 result);

  function deployERC20TokenFor(
    uint256 projectId,
    string calldata name,
    string calldata symbol
  ) external returns (IJBERC20Token token);

  function setTokenFor(uint256 projectId, IJBERC20Token token) external;

  function burnFrom(address holder, uint256 projectId, uint256 amount) external;

  function mintFor(address holder, uint256 projectId, uint256 amount) external;

  function claimTokensFor(
    address holder,
    uint256 projectId,
    uint256 amount,
    address beneficiary
  ) external;

  function transferCreditsFrom(
    address holder,
    uint256 projectId,
    address recipient,
    uint256 amount
  ) external;
}
