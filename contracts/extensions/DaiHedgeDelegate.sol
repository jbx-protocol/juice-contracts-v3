// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import '../abstract/JBOperatable.sol';

import '../interfaces/IJBDirectory.sol';
import '../interfaces/IJBFundingCycleDataSource.sol';
import '../interfaces/IJBOperatorStore.sol';
import '../interfaces/IJBPayDelegate.sol';
import '../interfaces/IJBPaymentTerminal.sol';
import '../interfaces/IJBRedemptionDelegate.sol';
import '../interfaces/IJBSingleTokenPaymentTerminalStore.sol';
import '../libraries/JBCurrencies.sol';
import '../libraries/JBOperations.sol';
import '../libraries/JBTokens.sol';
import '../structs/JBDidPayData.sol';

import '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import '@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol';
import '@openzeppelin/contracts/token/ERC721/IERC721.sol';
import '@uniswap/v3-periphery/contracts/interfaces/IQuoter.sol';
import '@uniswap/v3-periphery/contracts/interfaces/ISwapRouter.sol';

interface IWETH9 is IERC20 {
  /// @notice Deposit ether to get wrapped ether
  function deposit() external payable;

  /// @notice Withdraw wrapped ether to get ether
  function withdraw(uint256) external;
}

interface IDaiHedgeDelegate {
  function setHedgeParameters(
    uint256 _projectId,
    bool _applyHedge,
    uint256 _ethShare,
    uint256 _balanceThreshold,
    uint256 _ethThreshold,
    uint256 _usdThreshold,
    HedgeFlags memory _flags
  ) external;
}

struct HedgeFlags {
  bool liveQuote;
  /**
   * @dev Use default Ether payment terminal, otherwise JBDirectory will be queries.
   */
  bool defaultEthTerminal;
  /**
   * @dev Use default DAI payment terminal, otherwise JBDirectory will be queries.
   */
  bool defaultUsdTerminal;
}

struct HedgeSettings {
  uint256 ethThreshold;
  uint256 usdThreshold;
  /**
   * @dev Bit-packed value: uint16: eth share bps, uint16: balance threshold bps (<< 16), bool: live quote (<< 32), bool: default eth terminal (<< 33), bool: default eth terminal (<< 34)
   */
  uint256 settings;
}

/**
 * @title Automated DAI treasury
 *
 * @notice Converts ether sent to it into WETH and swaps it for DAI, then `pay`s the DAI into the platform DAI sink with the beneficiary being the owner of the original target project.
 *
 */
contract DaiHedgeDelegate is
  JBOperatable,
  IDaiHedgeDelegate,
  IJBFundingCycleDataSource,
  IJBPayDelegate,
  IJBRedemptionDelegate
{
  //*********************************************************************//
  // --------------------- private stored properties ------------------- //
  //*********************************************************************//

  IJBDirectory private immutable jbxDirectory;

  IERC721 private immutable jbxProjects;

  /**
   * @notice Balance token, in this case DAI, that is held by the delegate on behalf of depositors.
   */
  // IERC20Metadata private constant _dai = IERC20Metadata(0x6B175474E89094C44Da98b954EedeAC495271d0F); // DAI mainnet
  IERC20Metadata private constant _dai = IERC20Metadata(0xdc31Ee1784292379Fbb2964b3B9C4124D8F89C60); // DAI goerli

  /**
   * @notice Uniswap v3 router.
   */
  ISwapRouter private constant _swapRouter =
    ISwapRouter(0xE592427A0AEce92De3Edee1F18E0157C05861564); // TODO: this should be abstracted into a SwapProvider that can offer interfaces other than just uniswap

  /**
   * @notice Uniswap v3 quoter.
   */
  IQuoter public constant _swapQuoter = IQuoter(0xb27308f9F90D607463bb33eA1BeBb41C27CE5AB6);

  /**
   * @notice Hardwired WETH address for use as "cash" in the swaps.
   */
  IWETH9 private constant _weth = IWETH9(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);

  uint24 public constant poolFee = 3000;

  IJBSingleTokenPaymentTerminal public defaultEthTerminal;
  IJBSingleTokenPaymentTerminal public defaultUsdTerminal;
  IJBSingleTokenPaymentTerminalStore public terminalStore;
  uint256 public recentPrice;
  uint256 public recentPriceTimestamp;

  /**
   * @dev Maps project ids to hedging configuration.
   */
  mapping(uint256 => HedgeSettings) public projectHedgeSettings;

  uint256 private constant bps = 10_000;
  uint256 private constant SettingsOffsetEthShare = 0;
  uint256 private constant SettingsOffsetBalanceThreshold = 16;
  uint256 private constant SettingsOffsetLiveQuote = 32;
  uint256 private constant SettingsOffsetDefaultEthTerminal = 33;
  uint256 private constant SettingsOffsetDefaultUsdTerminal = 34;
  uint256 private constant SettingsOffsetApplyHedge = 35;

  constructor(
    IJBOperatorStore _jbxOperatorStore,
    IJBDirectory _jbxDirectory,
    IERC721 _jbxProjects,
    IJBSingleTokenPaymentTerminal _defaultEthTerminal,
    IJBSingleTokenPaymentTerminal _defaultUsdTerminal,
    IJBSingleTokenPaymentTerminalStore _terminalStore
  ) {
    operatorStore = _jbxOperatorStore; // JBOperatable

    jbxDirectory = _jbxDirectory;
    jbxProjects = _jbxProjects;

    defaultEthTerminal = _defaultEthTerminal;
    defaultUsdTerminal = _defaultUsdTerminal;
    terminalStore = _terminalStore;
  }

  //*********************************************************************//
  // ---------------------- external functions ------------------------- //
  //*********************************************************************//

  /**
   * @notice
   *
   * @dev Multiple conditions need to be met for this delegate to attempt swaps between Ether and DAI.
   *
   * @param _projectId Project id to modify settings for.
   * @param _applyHedge Enable hedging.
   * @param _ethShare Target Ether share of the total. Expressed in basis points, setting it to 6000 will make the targer 60% Ether, 40% DAI.
   * @param _balanceThreshold Distance from targer threshold at which to take action.
   * @param _ethThreshold Ether contribution threshold, below this number trandes won't be attempted.
   * @param _usdThreshold Dai contribution threshold, below this number trandes won't be attempted.
   * @param _flags When set to false and a recent price exists, do not query the pool for current price.
   */
  function setHedgeParameters(
    uint256 _projectId,
    bool _applyHedge,
    uint256 _ethShare,
    uint256 _balanceThreshold,
    uint256 _ethThreshold,
    uint256 _usdThreshold,
    HedgeFlags memory _flags
  )
    external
    requirePermissionAllowingOverride(
      jbxProjects.ownerOf(_projectId),
      _projectId,
      JBOperations.MANAGE_PAYMENTS,
      (msg.sender == address(jbxDirectory.controllerOf(_projectId)))
    )
  {
    uint256 settings = uint16(_ethShare);
    settings |= uint256(uint16(_balanceThreshold)) << SettingsOffsetBalanceThreshold;
    settings = setBoolean(settings, SettingsOffsetLiveQuote, _flags.liveQuote);
    settings = setBoolean(settings, SettingsOffsetDefaultEthTerminal, _flags.defaultEthTerminal);
    settings = setBoolean(settings, SettingsOffsetDefaultUsdTerminal, _flags.defaultUsdTerminal);
    settings = setBoolean(settings, SettingsOffsetApplyHedge, _applyHedge);

    projectHedgeSettings[_projectId] = HedgeSettings(_ethThreshold, _usdThreshold, settings);
  }

  /**
   * @notice IJBPayDelegate implementation
   *
   * @notice Will swap incoming ether via WETH into DAI using Uniswap v3 and pay the proceeds into the platform DAI sink.
   */
  function didPay(JBDidPayData calldata _data) public payable override {
    HedgeSettings memory settings = projectHedgeSettings[_data.projectId];

    if (!getBoolean(settings.settings, SettingsOffsetApplyHedge)) {
      return;
    }

    if (_data.amount.token == JBTokens.ETH) {
      // eth -> dai
      // NOTE: in this case this should be the same as msg.value
      if (_data.forwardedAmount.value >= settings.ethThreshold) {
        (uint256 projectEthBalance, IJBPaymentTerminal ethTerminal) = getProjectBalance(
          JBCurrencies.ETH,
          getBoolean(settings.settings, SettingsOffsetDefaultEthTerminal),
          _data.projectId
        );
        (uint256 projectUsdBalance, IJBPaymentTerminal daiTerminal) = getProjectBalance(
          JBCurrencies.USD,
          getBoolean(settings.settings, SettingsOffsetDefaultUsdTerminal),
          _data.projectId
        );

        uint256 projectUsdBalanceEthValue;
        if (
          getBoolean(settings.settings, SettingsOffsetLiveQuote) ||
          recentPriceTimestamp < block.timestamp - 43_200
        ) {
          recentPrice = _swapQuoter.quoteExactOutputSingle(
            address(_dai),
            address(_weth),
            poolFee,
            1000000000000000000,
            0
          );
          recentPriceTimestamp = block.timestamp;
        }
        projectUsdBalanceEthValue = projectUsdBalance / recentPrice;
        // value of the project's eth balance after adding current contribution
        uint256 newEthBalance = projectEthBalance + _data.forwardedAmount.value;
        uint256 totalEthBalance = newEthBalance + projectUsdBalanceEthValue;
        uint256 newEthShare = (projectEthBalance * bps) / totalEthBalance;
        if (
          newEthShare > uint16(settings.settings) &&
          newEthShare - uint16(settings.settings) >
          uint16(settings.settings >> SettingsOffsetBalanceThreshold)
        ) {
          uint256 ratio = (bps * uint16(settings.settings)) / (bps - uint16(settings.settings));
          uint256 swapAmount;
          if (
            _data.forwardedAmount.value + projectEthBalance <
            (ratio * projectUsdBalanceEthValue) / bps
          ) {
            swapAmount = _data.forwardedAmount.value;
          } else {
            swapAmount =
              (_data.forwardedAmount.value +
                projectEthBalance -
                (ratio * projectUsdBalanceEthValue) /
                bps) /
              ((ratio + bps * bps) / bps);
          }

          _weth.deposit{value: swapAmount}();
          _weth.approve(address(_swapRouter), swapAmount);

          ISwapRouter.ExactInputSingleParams memory params = ISwapRouter.ExactInputSingleParams({
            tokenIn: address(_weth),
            tokenOut: address(_dai),
            fee: poolFee,
            recipient: address(this),
            deadline: block.timestamp,
            amountIn: swapAmount,
            amountOutMinimum: 0,
            sqrtPriceLimitX96: 0
          });
          uint256 amountOut = _swapRouter.exactInputSingle(params);
          _weth.approve(address(_swapRouter), 0);

          _dai.approve(address(ethTerminal), amountOut);
          daiTerminal.addToBalanceOf(_data.projectId, amountOut, address(_dai), '', '');
          _dai.approve(address(ethTerminal), 0);
        }
      }
    } else if (_data.amount.token == address(_dai)) {
      // dai -> eth
      if (_data.forwardedAmount.value >= settings.usdThreshold) {
        (uint256 projectEthBalance, IJBPaymentTerminal ethTerminal) = getProjectBalance(
          JBCurrencies.ETH,
          getBoolean(settings.settings, SettingsOffsetDefaultEthTerminal),
          _data.projectId
        );
        (uint256 projectUsdBalance, ) = getProjectBalance(
          JBCurrencies.USD,
          getBoolean(settings.settings, SettingsOffsetDefaultUsdTerminal),
          _data.projectId
        );

        uint256 projectUsdBalanceEthValue;
        if (
          getBoolean(settings.settings, SettingsOffsetLiveQuote) ||
          recentPriceTimestamp < block.timestamp - 43200
        ) {
          recentPrice = _swapQuoter.quoteExactOutputSingle(
            address(_dai),
            address(_weth),
            poolFee,
            1000000000000000000,
            0
          );
          recentPriceTimestamp = block.timestamp;
        }
        // value of the project's dai balance in terms of eth after adding current contribution
        projectUsdBalanceEthValue = (projectUsdBalance + _data.forwardedAmount.value) / recentPrice;
        uint256 totalEthBalance = projectEthBalance + projectUsdBalanceEthValue;
        uint256 newEthShare = (projectEthBalance * bps) / totalEthBalance;
        if (
          newEthShare < uint16(settings.settings) &&
          uint16(settings.settings) - newEthShare >
          uint16(settings.settings >> SettingsOffsetBalanceThreshold)
        ) {
          uint256 ratio = (bps * uint16(settings.settings)) / (bps - uint16(settings.settings));
          uint256 swapAmount;
          if (_data.forwardedAmount.value + projectEthBalance < (ratio * projectUsdBalance) / bps) {
            swapAmount = _data.forwardedAmount.value;
          } else {
            swapAmount =
              (_data.forwardedAmount.value +
                projectEthBalance -
                (ratio * projectUsdBalance) /
                bps) /
              ((ratio + bps * bps) / bps);
          }

          _dai.approve(address(_swapRouter), _data.forwardedAmount.value);

          ISwapRouter.ExactInputSingleParams memory params = ISwapRouter.ExactInputSingleParams({
            tokenIn: address(_dai),
            tokenOut: address(_weth),
            fee: poolFee,
            recipient: address(this),
            deadline: block.timestamp,
            amountIn: _data.forwardedAmount.value,
            amountOutMinimum: 0,
            sqrtPriceLimitX96: 0
          });
          uint256 amountOut = _swapRouter.exactInputSingle(params);
          _dai.approve(address(_swapRouter), 0);

          _weth.withdraw(amountOut);
          ethTerminal.addToBalanceOf{value: amountOut}(
            _data.projectId,
            amountOut,
            JBTokens.ETH,
            '',
            ''
          );
        }
      }
    }
  }

  /**
   * @notice IJBRedemptionDelegate implementation
   */
  function didRedeem(JBDidRedeemData calldata) public payable override {
    // no rebalance on redemption
  }

  /**
   * @notice IJBFundingCycleDataSource implementation
   *
   * @dev This function will pass through the weight and amount parameters from the incoming data argument but will add self as the delegate address.
   */
  function payParams(
    JBPayParamsData calldata _data
  )
    public
    view
    override
    returns (
      uint256 weight,
      string memory memo,
      JBPayDelegateAllocation[] memory delegateAllocations
    )
  {
    weight = _data.weight;
    memo = _data.memo;
    delegateAllocations = new JBPayDelegateAllocation[](1);
    delegateAllocations[0] = JBPayDelegateAllocation({
      delegate: IJBPayDelegate(address(this)),
      amount: _data.amount.value
    });
  }

  /**
   * @notice IJBFundingCycleDataSource implementation
   */
  function redeemParams(
    JBRedeemParamsData calldata _data
  )
    public
    pure
    override
    returns (
      uint256 reclaimAmount,
      string memory memo,
      JBRedemptionDelegateAllocation[] memory delegateAllocations
    )
  {
    reclaimAmount = _data.reclaimAmount.value;
    memo = _data.memo;
  }

  /**
   * @notice IERC165 implementation
   */
  function supportsInterface(bytes4 interfaceId) public pure override returns (bool) {
    return
      interfaceId == type(IJBFundingCycleDataSource).interfaceId ||
      interfaceId == type(IJBPayDelegate).interfaceId ||
      interfaceId == type(IJBRedemptionDelegate).interfaceId;
  }

  /**
   * @dev didPay() receives weth from swaps that need to be unwrapped and deposited
   */
  // solhint-disable-next-line no-empty-blocks
  receive() external payable {}

  //*********************************************************************//
  // ---------------------- internal functions ------------------------- //
  //*********************************************************************//
  function getProjectBalance(
    uint256 _currency,
    bool _useDefaultTerminal,
    uint256 _projectId
  ) internal view returns (uint256 balance, IJBSingleTokenPaymentTerminal terminal) {
    if (_currency == JBCurrencies.ETH) {
      terminal = IJBSingleTokenPaymentTerminal(defaultEthTerminal);
      if (!_useDefaultTerminal) {
        terminal = IJBSingleTokenPaymentTerminal(
          address(jbxDirectory.primaryTerminalOf(_projectId, JBTokens.ETH))
        );
      }

      balance = terminalStore.balanceOf(terminal, _projectId);
    } else if (_currency == JBCurrencies.USD) {
      terminal = defaultUsdTerminal;
      if (!_useDefaultTerminal) {
        terminal = IJBSingleTokenPaymentTerminal(
          address(jbxDirectory.primaryTerminalOf(_projectId, address(_dai)))
        );
      }

      balance = terminalStore.balanceOf(terminal, _projectId);
    }
  }

  //*********************************************************************//
  // ------------------------------ utils ------------------------------ //
  //*********************************************************************//

  function getBoolean(uint256 _source, uint256 _index) internal pure returns (bool) {
    uint256 flag = (_source >> _index) & uint256(1);
    return (flag == 1 ? true : false);
  }

  function setBoolean(
    uint256 _source,
    uint256 _index,
    bool _value
  ) internal pure returns (uint256 update) {
    if (_value) {
      update = _source | (uint256(1) << _index);
    } else {
      update = _source & ~(uint256(1) << _index);
    }
  }
}
