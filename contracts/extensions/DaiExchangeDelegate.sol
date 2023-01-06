// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import '../interfaces/IJBDirectory.sol';
import '../interfaces/IJBFundingCycleDataSource.sol';
import '../interfaces/IJBPayDelegate.sol';
import '../interfaces/IJBPaymentTerminal.sol';
import '../interfaces/IJBRedemptionDelegate.sol';
import '../structs/JBDidPayData.sol';

import '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import '@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol';
import '@openzeppelin/contracts/token/ERC721/IERC721.sol';
import '@uniswap/v3-periphery/contracts/interfaces/ISwapRouter.sol';

interface IWETH9 is IERC20 {
  /// @notice Deposit ether to get wrapped ether
  function deposit() external payable;

  /// @notice Withdraw wrapped ether to get ether
  function withdraw(uint256) external;
}

interface IDaiExchangeDelegate {
  receive() external payable;
}

/**
 * @title Automated DAI treasury
 *
 * @notice Converts ether sent to it into WETH and swaps it for DAI, then `pay`s the DAI into the platform DAI sink with the beneficiary being the owner of the original target project.
 *
 */
contract DaiExchangeDelegate is
  IDaiExchangeDelegate,
  IJBFundingCycleDataSource,
  IJBPayDelegate,
  IJBRedemptionDelegate
{
  //*********************************************************************//
  // --------------------- private stored properties ------------------- //
  //*********************************************************************//

  IJBDirectory private immutable jbxDirectory;

  IERC721 private immutable jbxProjects;

  uint256 private immutable daiSinkProjectId;

  /**
   * @notice Balance token, in this case DAI, that is held by the delegate on behalf of depositors.
   */
  IERC20Metadata private constant _dai = IERC20Metadata(0x6B175474E89094C44Da98b954EedeAC495271d0F); // DAI

  /**
   * @notice Uniswap v3 pool to use for swaps.
   */
  ISwapRouter private constant _swapRouter =
    ISwapRouter(0xE592427A0AEce92De3Edee1F18E0157C05861564); // TODO: this should be abstracted into a SwapProvider that can offer interfaces other than just uniswap

  /**
   * @notice Hardwired WETH address for use as "cash" in the swaps.
   */
  IWETH9 private constant _weth = IWETH9(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);

  uint24 public constant poolFee = 3000;

  constructor(address _jbxDirectory, address _jbxProjects, uint256 _daiSinkProjectId) {
    jbxDirectory = IJBDirectory(_jbxDirectory);
    jbxProjects = IERC721(_jbxProjects);
    daiSinkProjectId = _daiSinkProjectId;
  }

  //*********************************************************************//
  // ---------------------- external functions ------------------------- //
  //*********************************************************************//

  /**
   * @notice IJBPayDelegate implementation
   *
   * @notice Will swap incoming ether via WETH into DAI using Uniswap v3 and pay the proceeds into the platform DAI sink.
   *
   */
  function didPay(JBDidPayData calldata _data) public payable override {
    _weth.deposit{value: msg.value}();
    _weth.approve(address(_swapRouter), msg.value);

    ISwapRouter.ExactInputSingleParams memory params = ISwapRouter.ExactInputSingleParams({
      tokenIn: address(_weth),
      tokenOut: address(_dai),
      fee: poolFee,
      recipient: address(this),
      deadline: block.timestamp,
      amountIn: msg.value,
      amountOutMinimum: 0,
      sqrtPriceLimitX96: 0
    });
    uint256 amountOut = _swapRouter.exactInputSingle(params);

    IJBPaymentTerminal terminal = jbxDirectory.primaryTerminalOf(daiSinkProjectId, address(_dai));
    terminal.pay(
      daiSinkProjectId,
      amountOut,
      address(_dai),
      jbxProjects.ownerOf(_data.projectId),
      0,
      false,
      '', // TODO: record _data.payer
      ''
    );
  }

  /**
   * @notice IJBRedemptionDelegate implementation
   */
  function didRedeem(JBDidRedeemData calldata _data) public payable override {
    _dai.approve(address(_swapRouter), _data.projectTokenCount);

    ISwapRouter.ExactInputSingleParams memory params = ISwapRouter.ExactInputSingleParams({
      tokenIn: address(_dai),
      tokenOut: address(_weth),
      fee: poolFee,
      recipient: address(this),
      deadline: block.timestamp,
      amountIn: _data.projectTokenCount,
      amountOutMinimum: 0,
      sqrtPriceLimitX96: 0
    });
    uint256 amountOut = _swapRouter.exactInputSingle(params);

    _weth.withdraw(amountOut);

    _data.beneficiary.transfer(amountOut);
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
    view
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
   * @dev didPay() receives ether from the terminal to wrap & send to the pool.
   */
  // solhint-disable-next-line no-empty-blocks
  receive() external payable override {}
}
